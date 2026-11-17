/* pro1x-develop — a raw camera frame to a JPEG, as libcamera's software ISP
 * would have made it, for the camera app's photos without a mode switch.
 *
 *   pro1x-develop RAW OUT.jpg WIDTH HEIGHT STRIDE ORDER BLACK
 *                 GAIN_R GAIN_G GAIN_B  C0 C1 C2 C3 C4 C5 C6 C7 C8
 *                 GAMMA CONTRAST  CROP_X CROP_Y CROP_W CROP_H
 *                 TURN SCALE QUALITY
 *
 * RAW: 10-bit packed Bayer (MIPI CSI-2: four pixels in five bytes), rows of
 * STRIDE bytes; ORDER RGGB, GRBG, GBRG or BGGR.  BLACK: the black level, a
 * fraction of the range.  The gains and the colour matrix (row major) are
 * the frame's ColourGains and ColourCorrectionMatrix; GAMMA and CONTRAST as
 * the software ISP's shader applies them (1/2.2 and 1.0 by default).  The
 * crop is in raw pixels; TURN in degrees counterclockwise (0, 90, 180, 270);
 * SCALE 1 or 2 (half size, averaged); QUALITY the JPEG's.
 *
 * The pipeline follows libcamera's bayer_1x_packed.frag (normalise above the
 * black level, white balance, clamp, colour matrix, clamp, contrast curve,
 * gamma), so a photo looks as the viewfinder did.  The demosaic is
 * Malvar-He-Cutler (gradient-corrected bilinear, IEEE ICASSP 2004), sharper
 * than the shader's bilinear one.  Rows are shared out among the CPU's
 * cores.
 *
 * Copyright 2026 fxtec-pro1x-guix contributors; GPL-3.0-or-later.
 */

#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <jpeglib.h>

#define LUT_SIZE 4096

struct job {
	const uint8_t *raw;
	int width, height, stride;
	int colour[4];			/* 0 R, 1 G, 2 B; by (y & 1) * 2 + (x & 1) */
	float black, gain[3], ccm[9];
	uint8_t lut[LUT_SIZE + 1];	/* contrast and gamma, 0..1 to 0..255 */
	int cx, cy, cw, ch;		/* the crop */
	uint8_t *rgb;			/* cw x ch, 3 bytes a pixel */
	int nthreads;
};

struct band {
	struct job *job;
	int first, last;
};

/* One pixel of the 10-bit packed raw, as 0..1023, with the edges mirrored. */
static inline int px(const struct job *j, int x, int y)
{
	if (x < 0)
		x = -x;
	else if (x >= j->width)
		x = 2 * j->width - 2 - x;
	if (y < 0)
		y = -y;
	else if (y >= j->height)
		y = 2 * j->height - 2 - y;
	const uint8_t *row = j->raw + (size_t)y * j->stride;
	const uint8_t *group = row + (x >> 2) * 5;
	int i = x & 3;
	return (group[i] << 2) | ((group[4] >> (2 * i)) & 3);
}

/* Malvar-He-Cutler: the three colours at (x, y), in raw units times 8. */
static void demosaic(const struct job *j, int x, int y, int out[3])
{
	int c = j->colour[(y & 1) * 2 + (x & 1)];
	int v = px(j, x, y);
	int n = px(j, x, y - 1), s = px(j, x, y + 1);
	int w = px(j, x - 1, y), e = px(j, x + 1, y);
	int nn = px(j, x, y - 2), ss = px(j, x, y + 2);
	int ww = px(j, x - 2, y), ee = px(j, x + 2, y);
	int nw = px(j, x - 1, y - 1), ne = px(j, x + 1, y - 1);
	int sw = px(j, x - 1, y + 1), se = px(j, x + 1, y + 1);
	int cross = n + s + w + e, far = nn + ss + ww + ee;
	int diag = nw + ne + sw + se;

	if (c == 1) {
		/* Green: red and blue from the row or the column they share
		 * with it. */
		int horiz = 5 * v + 4 * (w + e) - (ww + ee) - diag
			    + (nn + ss) / 2;
		int vert = 5 * v + 4 * (n + s) - (nn + ss) - diag
			   + (ww + ee) / 2;
		/* The colour beside it in its row. */
		int rowc = j->colour[(y & 1) * 2 + ((x + 1) & 1)];
		out[1] = 8 * v;
		if (rowc == 0) {
			out[0] = horiz;
			out[2] = vert;
		} else {
			out[2] = horiz;
			out[0] = vert;
		}
	} else {
		int green = 4 * v + 2 * cross - far;
		int other = 6 * v + 2 * diag - 3 * far / 2;
		out[c] = 8 * v;
		out[1] = green;
		out[2 - c] = other;
	}
}

static void *develop_band(void *arg)
{
	struct band *b = arg;
	struct job *j = b->job;
	const float scale = 1.0f / (8.0f * 1023.0f);
	const float black = j->black, range = 1.0f - j->black;

	for (int y = b->first; y < b->last; y++) {
		uint8_t *out = j->rgb + (size_t)(y - j->cy) * j->cw * 3;
		for (int x = j->cx; x < j->cx + j->cw; x++) {
			int v[3];
			float rgb[3], m[3];
			demosaic(j, x, y, v);
			for (int k = 0; k < 3; k++) {
				float f = (v[k] * scale - black) / range * j->gain[k];
				rgb[k] = f < 0 ? 0 : f > 1 ? 1 : f;
			}
			for (int k = 0; k < 3; k++) {
				float f = j->ccm[3 * k] * rgb[0]
					  + j->ccm[3 * k + 1] * rgb[1]
					  + j->ccm[3 * k + 2] * rgb[2];
				m[k] = f < 0 ? 0 : f > 1 ? 1 : f;
			}
			for (int k = 0; k < 3; k++)
				*out++ = j->lut[(int)(m[k] * LUT_SIZE + 0.5f)];
		}
	}
	return NULL;
}

/* The shader's S-curve, then its gamma. */
static void make_lut(struct job *j, float gamma, float contrast)
{
	for (int i = 0; i <= LUT_SIZE; i++) {
		float v = (float)i / LUT_SIZE;
		if (v < 0.5f)
			v = 0.5f * powf(v / 0.5f, contrast);
		else
			v = 1.0f - 0.5f * powf((1.0f - v) / 0.5f, contrast);
		v = powf(v, gamma);
		j->lut[i] = (uint8_t)(v * 255.0f + 0.5f);
	}
}

/* Pixel (x, y) of the turned, scaled picture, from the developed crop. */
static inline const uint8_t *source(const struct job *j, int turn, int x, int y,
				    int ow, int oh)
{
	int sx, sy;
	switch (turn) {
	case 90:  sx = j->cw - 1 - y; sy = x; break;
	case 180: sx = j->cw - 1 - x; sy = j->ch - 1 - y; break;
	case 270: sx = y; sy = j->ch - 1 - x; break;
	default:  sx = x; sy = y;
	}
	(void)ow; (void)oh;
	return j->rgb + ((size_t)sy * j->cw + sx) * 3;
}

static int write_jpeg(const struct job *j, const char *path, int turn,
		      int half, int quality)
{
	int tw = (turn == 90 || turn == 270) ? j->ch : j->cw;
	int th = (turn == 90 || turn == 270) ? j->cw : j->ch;
	int ow = half ? tw / 2 : tw, oh = half ? th / 2 : th;
	char tmp[4096];
	snprintf(tmp, sizeof tmp, "%s.part", path);
	FILE *f = fopen(tmp, "wb");
	if (!f) {
		perror(tmp);
		return -1;
	}
	struct jpeg_compress_struct cinfo;
	struct jpeg_error_mgr jerr;
	cinfo.err = jpeg_std_error(&jerr);
	jpeg_create_compress(&cinfo);
	jpeg_stdio_dest(&cinfo, f);
	cinfo.image_width = ow;
	cinfo.image_height = oh;
	cinfo.input_components = 3;
	cinfo.in_color_space = JCS_RGB;
	jpeg_set_defaults(&cinfo);
	jpeg_set_quality(&cinfo, quality, TRUE);
	jpeg_start_compress(&cinfo, TRUE);
	uint8_t *row = malloc((size_t)ow * 3);
	while (cinfo.next_scanline < (unsigned)oh) {
		int y = cinfo.next_scanline;
		for (int x = 0; x < ow; x++) {
			if (!half) {
				memcpy(row + 3 * x, source(j, turn, x, y, tw, th), 3);
				continue;
			}
			int sum[3] = { 0, 0, 0 };
			for (int dy = 0; dy < 2; dy++)
				for (int dx = 0; dx < 2; dx++) {
					const uint8_t *p = source(j, turn, 2 * x + dx,
								  2 * y + dy, tw, th);
					for (int k = 0; k < 3; k++)
						sum[k] += p[k];
				}
			for (int k = 0; k < 3; k++)
				row[3 * x + k] = (sum[k] + 2) / 4;
		}
		JSAMPROW rows[1] = { row };
		jpeg_write_scanlines(&cinfo, rows, 1);
	}
	jpeg_finish_compress(&cinfo);
	jpeg_destroy_compress(&cinfo);
	free(row);
	if (fclose(f) != 0 || rename(tmp, path) != 0) {
		perror(path);
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	if (argc != 29) {
		fprintf(stderr, "usage: see the comment at the top of pro1x-develop.c\n");
		return 2;
	}
	struct job j;
	memset(&j, 0, sizeof j);
	const char *in = argv[1], *out = argv[2];
	j.width = atoi(argv[3]);
	j.height = atoi(argv[4]);
	j.stride = atoi(argv[5]);
	const char *order = argv[6];
	if (strlen(order) != 4) {
		fprintf(stderr, "order: RGGB, GRBG, GBRG or BGGR\n");
		return 2;
	}
	for (int i = 0; i < 4; i++)
		j.colour[i] = order[i] == 'R' ? 0 : order[i] == 'G' ? 1 : 2;
	j.black = atof(argv[7]);
	for (int k = 0; k < 3; k++)
		j.gain[k] = atof(argv[8 + k]);
	for (int k = 0; k < 9; k++)
		j.ccm[k] = atof(argv[11 + k]);
	make_lut(&j, atof(argv[20]), atof(argv[21]));
	j.cx = atoi(argv[22]);
	j.cy = atoi(argv[23]);
	j.cw = atoi(argv[24]);
	j.ch = atoi(argv[25]);
	int turn = ((atoi(argv[26]) % 360) + 360) % 360;
	int half = atoi(argv[27]) == 2;
	int quality = atoi(argv[28]);
	if (j.cx < 0 || j.cy < 0 || j.cw <= 0 || j.ch <= 0 ||
	    j.cx + j.cw > j.width || j.cy + j.ch > j.height ||
	    j.stride < j.width * 5 / 4) {
		fprintf(stderr, "crop or stride out of the frame\n");
		return 2;
	}

	int fd = open(in, O_RDONLY);
	struct stat st;
	if (fd < 0 || fstat(fd, &st) < 0) {
		perror(in);
		return 1;
	}
	if (st.st_size < (off_t)j.stride * j.height) {
		fprintf(stderr, "%s: %lld bytes, short of %d rows of %d\n", in,
			(long long)st.st_size, j.height, j.stride);
		return 1;
	}
	j.raw = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (j.raw == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	j.rgb = malloc((size_t)j.cw * j.ch * 3);
	if (!j.rgb) {
		perror("malloc");
		return 1;
	}

	long n = sysconf(_SC_NPROCESSORS_ONLN);
	j.nthreads = n < 1 ? 1 : n > 16 ? 16 : (int)n;
	pthread_t threads[16];
	struct band bands[16];
	for (int t = 0; t < j.nthreads; t++) {
		bands[t].job = &j;
		bands[t].first = j.cy + (int)((long)j.ch * t / j.nthreads);
		bands[t].last = j.cy + (int)((long)j.ch * (t + 1) / j.nthreads);
		pthread_create(&threads[t], NULL, develop_band, &bands[t]);
	}
	for (int t = 0; t < j.nthreads; t++)
		pthread_join(threads[t], NULL);

	return write_jpeg(&j, out, turn, half, quality) ? 1 : 0;
}

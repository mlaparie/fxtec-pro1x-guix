/* pro1x-develop — a raw camera frame to a JPEG, as libcamera's software ISP
 * would have made it, for the camera app's photos without a mode switch.
 *
 *   pro1x-develop RAW OUT.jpg WIDTH HEIGHT STRIDE ORDER BLACK
 *                 GAIN_R GAIN_G GAIN_B  C0 C1 C2 C3 C4 C5 C6 C7 C8
 *                 GAMMA CONTRAST  CROP_X CROP_Y CROP_W CROP_H
 *                 TURN SCALE QUALITY [SHADING]
 *
 * RAW: 10-bit packed Bayer (MIPI CSI-2: four pixels in five bytes), rows of
 * STRIDE bytes; several files separated by commas are a burst, stacked
 * first (Night stack: aligned on the first, averaged, moved pixels left
 * out); "-sum" or "-mean" reads frames from standard input until it ends
 * and adds them (bulb: more light, highlights may burn) or averages them
 * (smooth: the same exposure, moving things blurred), unaligned; ORDER RGGB, GRBG, GBRG or BGGR.  BLACK: the black level, a
 * fraction of the range.  The gains and the colour matrix (row major) are
 * the frame's ColourGains and ColourCorrectionMatrix; GAMMA and CONTRAST as
 * the software ISP's shader applies them (1/2.2 and 1.0 by default).  The
 * crop is in raw pixels; TURN in degrees counterclockwise (0, 90, 180, 270);
 * SCALE 1 or 2 (half size, averaged); QUALITY the JPEG's.  Environment:
 * PRO1X_CONTRAST multiplies the contrast exponent (1: as the viewfinder),
 * PRO1X_CLARITY (0 to 1) adds local contrast (the difference from a wide
 * blur of the brightness, added back), PRO1X_VIBRANCE (0 to 1) saturates
 * the dull colours more than the vivid ones.  In bulb (-sum, -mean),
 * PRO1X_PREVIEW=PATH writes there, every PRO1X_PREVIEW_EVERY frames, the
 * frame so far, 8 times smaller and turned PRO1X_PREVIEW_TURN degrees, for
 * the viewfinder.  SHADING: the
 * rear camera module's EEPROM (at24, /sys/bus/i2c/devices/2-0050/eeprom),
 * whose lens shading table corrects the vignetting; left out, or not a
 * table that makes sense, the frame stays as it is.
 *
 * The pipeline follows libcamera's bayer_1x_packed.frag (normalise above the
 * black level, white balance, clamp, colour matrix, clamp, contrast curve,
 * gamma, and libcamera-pro1x's fade to neutral near saturation), so a photo
 * looks as the viewfinder did, but for the shading.  The demosaic is
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

/* The module's lens shading table: 17 x 13 points over the whole array,
 * each R, Gr, Gb, B, 16-bit big-endian, light relative to the brightest
 * (1023, the centre).  The IMX582 module's layout, read on the phone. */
#define SHADE_AT 0x21
#define SHADE_W 17
#define SHADE_H 13
/* The share of the brightness falloff corrected: all of it multiplies the
 * corners' noise by about 4; the colour falloff is corrected in full. */
#define SHADE_LUMA 0.8f

struct job {
	const uint8_t *raw;
	int width, height, stride;
	int colour[4];			/* 0 R, 1 G, 2 B; by (y & 1) * 2 + (x & 1) */
	float black, gain[3], ccm[9];
	uint8_t lut[LUT_SIZE + 1];	/* contrast and gamma, 0..1 to 0..255 */
	int shading;			/* shade is in use */
	float shade[SHADE_H][SHADE_W][3];	/* gains, R G B */
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

/* ── Night stack: a burst of frames aligned and averaged ─────────────── */

/* A pixel of a packed frame, in range. */
static inline int pk(const uint8_t *raw, int stride, int x, int y)
{
	const uint8_t *group = raw + (size_t)y * stride + (x >> 2) * 5;
	int i = x & 3;
	return (group[i] << 2) | ((group[4] >> (2 * i)) & 3);
}

static inline void pk_set(uint8_t *raw, int stride, int x, int y, int v)
{
	uint8_t *group = raw + (size_t)y * stride + (x >> 2) * 5;
	int i = x & 3;
	group[i] = v >> 2;
	group[4] = (group[4] & ~(3 << (2 * i))) | ((v & 3) << (2 * i));
}

#define LOW 8			/* the alignment's coarse scale */

/* A frame reduced LOW times: the mean of each block (all colours). */
static float *reduce(const uint8_t *raw, int w, int h, int stride)
{
	int lw = w / LOW, lh = h / LOW;
	float *out = malloc(sizeof(float) * lw * lh);
	for (int y = 0; y < lh; y++)
		for (int x = 0; x < lw; x++) {
			int sum = 0;
			for (int dy = 0; dy < LOW; dy += 2)
				for (int dx = 0; dx < LOW; dx += 2)
					sum += pk(raw, stride, x * LOW + dx, y * LOW + dy)
					     + pk(raw, stride, x * LOW + dx + 1, y * LOW + dy)
					     + pk(raw, stride, x * LOW + dx, y * LOW + dy + 1)
					     + pk(raw, stride, x * LOW + dx + 1, y * LOW + dy + 1);
			out[y * lw + x] = sum;
		}
	return out;
}

/* The shift of CUR against REF (reduced frames) within RANGE, by the least
 * mean absolute difference over the middle of the frame. */
static void coarse_shift(const float *ref, const float *cur, int lw, int lh,
			 int range, int *sx, int *sy)
{
	double best = 1e30;
	*sx = *sy = 0;
	for (int dy = -range; dy <= range; dy++)
		for (int dx = -range; dx <= range; dx++) {
			double sad = 0;
			int n = 0;
			for (int y = lh / 4; y < lh * 3 / 4; y += 2)
				for (int x = lw / 4; x < lw * 3 / 4; x += 2) {
					sad += fabsf(ref[y * lw + x] -
						     cur[(y + dy) * lw + x + dx]);
					n++;
				}
			sad /= n;
			if (sad < best) {
				best = sad;
				*sx = dx;
				*sy = dy;
			}
		}
}

/* Refined at full size around (*sx, *sy), in even steps (the Bayer
 * pattern stays in phase). */
static void fine_shift(const uint8_t *ref, const uint8_t *cur, int w, int h,
		       int stride, int *sx, int *sy)
{
	int bx = *sx, by = *sy;
	double best = 1e30;
	for (int dy = by - LOW; dy <= by + LOW; dy += 2)
		for (int dx = bx - LOW; dx <= bx + LOW; dx += 2) {
			double sad = 0;
			for (int y = h / 4; y < h * 3 / 4; y += 16)
				for (int x = w / 4; x < w * 3 / 4; x += 16)
					sad += abs(pk(ref, stride, x, y) -
						   pk(cur, stride, x + dx, y + dy));
			if (sad < best) {
				best = sad;
				*sx = dx;
				*sy = dy;
			}
		}
}

struct stack {
	const uint8_t **frames;
	int n, w, h, stride;
	int *dx, *dy;
	uint8_t *out;
	int first, last;
};

/* Each pixel: the mean of the frames that agree with the first within
 * their noise (a moved object or hand is left to the first frame). */
static void *stack_band(void *arg)
{
	struct stack *s = arg;
	for (int y = s->first; y < s->last; y++)
		for (int x = 0; x < s->w; x++) {
			int ref = pk(s->frames[0], s->stride, x, y);
			int sum = ref, count = 1;
			float limit = 3 * sqrtf((float)ref) + 8;
			for (int k = 1; k < s->n; k++) {
				int xx = x + s->dx[k], yy = y + s->dy[k];
				if (xx < 0 || yy < 0 || xx >= s->w || yy >= s->h)
					continue;
				int v = pk(s->frames[k], s->stride, xx, yy);
				if (abs(v - ref) <= limit) {
					sum += v;
					count++;
				}
			}
			pk_set(s->out, s->stride, x, y, (sum + count / 2) / count);
		}
	return NULL;
}

/* ── Bulb: frames from standard input, added or averaged ─────────────── */

static int write_jpeg(const struct job *j, const char *path, int turn,
		      int half, int quality);

/* The bulb's frame so far, 8 times smaller: one pixel a block, from the
 * block's top-left Bayer quad, through the same gains, matrix and curve. */
static void bulb_preview(struct job *j, const uint32_t *sum, int n, int mean,
			 int black, const char *path, int turn)
{
	int f = 8, w = j->width, lw = w / f, lh = j->height / f;
	struct job p = *j;
	p.cx = p.cy = 0;
	p.cw = lw;
	p.ch = lh;
	p.rgb = malloc((size_t)lw * lh * 3);
	if (!p.rgb)
		return;
	const float range = 1.0f - j->black;
	for (int y = 0; y < lh; y++)
		for (int x = 0; x < lw; x++) {
			float c[3] = { 0, 0, 0 };
			for (int q = 0; q < 4; q++) {
				int xx = x * f + (q & 1), yy = y * f + (q >> 1);
				int64_t v = sum[(size_t)yy * w + xx];
				v = mean ? v / n : black + v - (int64_t)n * black;
				float t = (v < 0 ? 0 : v > 1023 ? 1023 : v) / 1023.0f;
				int k = j->colour[(yy & 1) * 2 + (xx & 1)];
				c[k] += k == 1 ? t / 2 : t;
			}
			float rgb[3];
			for (int k = 0; k < 3; k++) {
				float v = (c[k] - j->black) / range * j->gain[k];
				rgb[k] = v < 0 ? 0 : v > 1 ? 1 : v;
			}
			uint8_t *out = p.rgb + ((size_t)y * lw + x) * 3;
			for (int k = 0; k < 3; k++) {
				float v = j->ccm[3 * k] * rgb[0] + j->ccm[3 * k + 1] * rgb[1]
					+ j->ccm[3 * k + 2] * rgb[2];
				v = v < 0 ? 0 : v > 1 ? 1 : v;
				out[k] = j->lut[(int)(v * LUT_SIZE + 0.5f)];
			}
		}
	write_jpeg(&p, path, turn, 0, 80);
	free(p.rgb);
}

struct accum {
	const uint8_t *frame;
	uint32_t *sum;
	int w, stride, first, last;
};

static void *accum_band(void *arg)
{
	struct accum *a = arg;
	for (int y = a->first; y < a->last; y++)
		for (int x = 0; x < a->w; x++)
			a->sum[(size_t)y * a->w + x] += pk(a->frame, a->stride, x, y);
	return NULL;
}

/* Every frame on standard input, added; then one frame: their mean, or
 * their sum above the black level (BLACK, 0..1023), clipped. */
static uint8_t *bulb_frames(struct job *j, int mean, int black)
{
	int w = j->width, h = j->height, stride = j->stride;
	size_t size = (size_t)stride * h;
	uint8_t *frame = malloc(size);
	uint32_t *sum = calloc((size_t)w * h, sizeof *sum);
	int n = 0;
	if (!frame || !sum)
		return NULL;
	const char *preview = getenv("PRO1X_PREVIEW");
	const char *every_s = getenv("PRO1X_PREVIEW_EVERY");
	const char *turn_s = getenv("PRO1X_PREVIEW_TURN");
	int every = every_s ? atoi(every_s) : 15;
	int pturn = turn_s ? ((atoi(turn_s) % 360) + 360) % 360 : 0;
	while (fread(frame, 1, size, stdin) == size) {
		pthread_t threads[16];
		struct accum bands[16];
		for (int t = 0; t < j->nthreads; t++) {
			bands[t] = (struct accum){ frame, sum, w, stride,
						   h * t / j->nthreads,
						   h * (t + 1) / j->nthreads };
			pthread_create(&threads[t], NULL, accum_band, &bands[t]);
		}
		for (int t = 0; t < j->nthreads; t++)
			pthread_join(threads[t], NULL);
		n++;
		if (preview && every > 0 && n % every == 0)
			bulb_preview(j, sum, n, mean, black, preview, pturn);
	}
	fprintf(stderr, "bulb: %d frames %s\n", n, mean ? "averaged" : "added");
	if (!n)
		return NULL;
	for (int y = 0; y < h; y++)
		for (int x = 0; x < w; x++) {
			int64_t v = sum[(size_t)y * w + x];
			v = mean ? (v + n / 2) / n : black + v - (int64_t)n * black;
			pk_set(frame, stride, x, y, v < 0 ? 0 : v > 1023 ? 1023 : (int)v);
		}
	free(sum);
	return frame;
}

/* The burst FRAMES stacked into one frame of the same layout. */
static uint8_t *stack_frames(struct job *j, const uint8_t **frames, int n)
{
	int w = j->width, h = j->height, stride = j->stride;
	int lw = w / LOW, lh = h / LOW, range = 12;
	int dx[64], dy[64];
	float *ref = reduce(frames[0], w, h, stride);
	dx[0] = dy[0] = 0;
	for (int k = 1; k < n; k++) {
		float *cur = reduce(frames[k], w, h, stride);
		int sx, sy;
		coarse_shift(ref, cur, lw, lh, range, &sx, &sy);
		free(cur);
		sx *= LOW;
		sy *= LOW;
		fine_shift(frames[0], frames[k], w, h, stride, &sx, &sy);
		dx[k] = sx;
		dy[k] = sy;
		fprintf(stderr, "stack: frame %d shifted %d,%d\n", k, sx, sy);
	}
	free(ref);
	uint8_t *out = malloc((size_t)stride * h);
	memcpy(out, frames[0], (size_t)stride * h);
	pthread_t threads[16];
	struct stack bands[16];
	for (int t = 0; t < j->nthreads; t++) {
		bands[t] = (struct stack){ frames, n, w, h, stride, dx, dy, out,
					   h * t / j->nthreads,
					   h * (t + 1) / j->nthreads };
		pthread_create(&threads[t], NULL, stack_band, &bands[t]);
	}
	for (int t = 0; t < j->nthreads; t++)
		pthread_join(threads[t], NULL);
	return out;
}

static void *develop_band(void *arg)
{
	struct band *b = arg;
	struct job *j = b->job;
	const float scale = 1.0f / (8.0f * 1023.0f);
	const float black = j->black, range = 1.0f - j->black;

	float row[SHADE_W][3];

	for (int y = b->first; y < b->last; y++) {
		uint8_t *out = j->rgb + (size_t)(y - j->cy) * j->cw * 3;
		if (j->shading) {
			/* This row of the gain grid, bilinear between its points. */
			float gy = (float)y * (SHADE_H - 1) / (j->height - 1);
			int i = gy >= SHADE_H - 1 ? SHADE_H - 2 : (int)gy;
			float t = gy - i;
			for (int g = 0; g < SHADE_W; g++)
				for (int k = 0; k < 3; k++)
					row[g][k] = j->shade[i][g][k] * (1 - t)
						    + j->shade[i + 1][g][k] * t;
		}
		for (int x = j->cx; x < j->cx + j->cw; x++) {
			int v[3];
			float rgb[3], m[3], sg[3] = { 1, 1, 1 };
			demosaic(j, x, y, v);
			if (j->shading) {
				float gx = (float)x * (SHADE_W - 1) / (j->width - 1);
				int i = gx >= SHADE_W - 1 ? SHADE_W - 2 : (int)gx;
				float t = gx - i;
				for (int k = 0; k < 3; k++)
					sg[k] = row[i][k] * (1 - t) + row[i + 1][k] * t;
			}
			float top = 0;
			for (int k = 0; k < 3; k++) {
				float n = (v[k] * scale - black) / range;
				if (n > top)
					top = n;
				float f = n * j->gain[k] * sg[k];
				rgb[k] = f < 0 ? 0 : f > 1 ? 1 : f;
			}
			float most = 0;
			for (int k = 0; k < 3; k++) {
				float f = j->ccm[3 * k] * rgb[0]
					  + j->ccm[3 * k + 1] * rgb[1]
					  + j->ccm[3 * k + 2] * rgb[2];
				m[k] = f < 0 ? 0 : f > 1 ? 1 : f;
				if (m[k] > most)
					most = m[k];
			}
			/* Near saturation one channel clips before the others
			 * and the matrix turns the near-white green: fade to
			 * neutral from 90% of the range up (our shader patch). */
			if (top > 0.9f) {
				float t = top >= 1 ? 1 : (top - 0.9f) / 0.1f;
				t = t * t * (3 - 2 * t);
				for (int k = 0; k < 3; k++)
					m[k] += (most - m[k]) * t;
			}
			for (int k = 0; k < 3; k++)
				*out++ = j->lut[(int)(m[k] * LUT_SIZE + 0.5f)];
		}
	}
	return NULL;
}

/* The shading gains from the module's EEPROM at PATH; 0 when it has no table
 * that makes sense (another module, an unprogrammed one). */
static int read_shading(struct job *j, const char *path)
{
	uint8_t d[SHADE_AT + SHADE_W * SHADE_H * 8];
	FILE *f = fopen(path, "rb");
	if (!f) {
		perror(path);
		return 0;
	}
	size_t n = fread(d, 1, sizeof d, f);
	fclose(f);
	if (n != sizeof d)
		return 0;
	for (int y = 0; y < SHADE_H; y++)
		for (int x = 0; x < SHADE_W; x++) {
			const uint8_t *p = d + SHADE_AT + (y * SHADE_W + x) * 8;
			float c[4];
			for (int k = 0; k < 4; k++) {
				int v = p[2 * k] << 8 | p[2 * k + 1];
				if (v < 64 || v > 1023)
					return 0;
				c[k] = 1023.0f / v;
			}
			/* Green's falloff in part; red's and blue's against green
			 * in full. */
			float g = (c[1] + c[2]) / 2, luma = powf(g, SHADE_LUMA);
			j->shade[y][x][0] = luma * c[0] / g;
			j->shade[y][x][1] = luma;
			j->shade[y][x][2] = luma * c[3] / g;
		}
	/* The brightest point is the centre's, at 1023. */
	const uint8_t *mid = d + SHADE_AT + (SHADE_H / 2 * SHADE_W + SHADE_W / 2) * 8;
	if ((mid[2] << 8 | mid[3]) < 1000)
		return 0;
	return 1;
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

/* Clarity: each pixel's brightness pushed away from that of its wide
 * surroundings by AMOUNT, the colours scaled with it so hues stay.  The
 * surroundings: the brightness reduced CLARITY_SCALE times, box-blurred
 * (radius CLARITY_RADIUS there, about 24 pixels here), read back bilinearly
 * (a full-size blur took 3.7 s on the phone). */
#define CLARITY_SCALE 8
#define CLARITY_RADIUS 3

static void box_blur(float *v, float *tmp, int w, int h, int r)
{
	for (int pass = 0; pass < 2; pass++) {
		for (int y = 0; y < h; y++)
			for (int x = 0; x < w; x++) {
				float sum = 0;
				for (int d = -r; d <= r; d++) {
					int xx = x + d < 0 ? 0 : x + d >= w ? w - 1 : x + d;
					sum += v[(size_t)y * w + xx];
				}
				tmp[(size_t)y * w + x] = sum / (2 * r + 1);
			}
		for (int y = 0; y < h; y++)
			for (int x = 0; x < w; x++) {
				float sum = 0;
				for (int d = -r; d <= r; d++) {
					int yy = y + d < 0 ? 0 : y + d >= h ? h - 1 : y + d;
					sum += tmp[(size_t)yy * w + x];
				}
				v[(size_t)y * w + x] = sum / (2 * r + 1);
			}
	}
}

static inline float luma_of(const uint8_t *p)
{
	return 0.299f * p[0] + 0.587f * p[1] + 0.114f * p[2];
}

static void clarity(struct job *j, float amount)
{
	int w = j->cw, h = j->ch, f = CLARITY_SCALE;
	int lw = (w + f - 1) / f, lh = (h + f - 1) / f;
	float *low = calloc((size_t)lw * lh, sizeof *low);
	float *tmp = malloc((size_t)lw * lh * sizeof *tmp);
	int *count = calloc((size_t)lw * lh, sizeof *count);
	if (!low || !tmp || !count)
		return;
	for (int y = 0; y < h; y++)
		for (int x = 0; x < w; x++) {
			size_t i = (size_t)(y / f) * lw + x / f;
			low[i] += luma_of(j->rgb + ((size_t)y * w + x) * 3);
			count[i]++;
		}
	for (size_t i = 0; i < (size_t)lw * lh; i++)
		low[i] /= count[i];
	box_blur(low, tmp, lw, lh, CLARITY_RADIUS);
	for (int y = 0; y < h; y++) {
		float gy = (y + 0.5f) / f - 0.5f;
		int y0 = gy < 0 ? 0 : (int)gy, y1 = y0 + 1 < lh ? y0 + 1 : y0;
		float ty = gy < 0 ? 0 : gy - y0;
		for (int x = 0; x < w; x++) {
			float gx = (x + 0.5f) / f - 0.5f;
			int x0 = gx < 0 ? 0 : (int)gx, x1 = x0 + 1 < lw ? x0 + 1 : x0;
			float tx = gx < 0 ? 0 : gx - x0;
			float b = (low[(size_t)y0 * lw + x0] * (1 - tx) + low[(size_t)y0 * lw + x1] * tx) * (1 - ty)
				+ (low[(size_t)y1 * lw + x0] * (1 - tx) + low[(size_t)y1 * lw + x1] * tx) * ty;
			uint8_t *p = j->rgb + ((size_t)y * w + x) * 3;
			float l = luma_of(p), want = l + amount * (l - b);
			float k = l > 1 ? want / l : 1;
			for (int c = 0; c < 3; c++) {
				float v = p[c] * k;
				p[c] = v < 0 ? 0 : v > 255 ? 255 : (uint8_t)(v + 0.5f);
			}
		}
	}
	free(low);
	free(tmp);
	free(count);
}

/* Vibrance: each pixel's colour pushed away from its grey by up to AMOUNT,
 * the less saturated the more. */
static void vibrance(struct job *j, float amount)
{
	size_t n = (size_t)j->cw * j->ch;
	for (size_t i = 0; i < n; i++) {
		uint8_t *p = j->rgb + i * 3;
		int hi = p[0] > p[1] ? (p[0] > p[2] ? p[0] : p[2]) : (p[1] > p[2] ? p[1] : p[2]);
		int lo = p[0] < p[1] ? (p[0] < p[2] ? p[0] : p[2]) : (p[1] < p[2] ? p[1] : p[2]);
		if (hi == 0)
			continue;
		float sat = (float)(hi - lo) / hi;
		float k = 1 + amount * (1 - sat);
		float grey = 0.299f * p[0] + 0.587f * p[1] + 0.114f * p[2];
		for (int c = 0; c < 3; c++) {
			float v = grey + (p[c] - grey) * k;
			p[c] = v < 0 ? 0 : v > 255 ? 255 : (uint8_t)(v + 0.5f);
		}
	}
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
	if (argc != 29 && argc != 30) {
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
	const char *contrast = getenv("PRO1X_CONTRAST");
	make_lut(&j, atof(argv[20]),
		 atof(argv[21]) * (contrast ? atof(contrast) : 1.0f));
	j.cx = atoi(argv[22]);
	j.cy = atoi(argv[23]);
	j.cw = atoi(argv[24]);
	j.ch = atoi(argv[25]);
	int turn = ((atoi(argv[26]) % 360) + 360) % 360;
	int half = atoi(argv[27]) == 2;
	int quality = atoi(argv[28]);
	if (argc == 30 && strcmp(argv[29], "-") != 0) {
		j.shading = read_shading(&j, argv[29]);
		if (!j.shading)
			fprintf(stderr, "%s: no lens shading table\n", argv[29]);
	}
	if (j.cx < 0 || j.cy < 0 || j.cw <= 0 || j.ch <= 0 ||
	    j.cx + j.cw > j.width || j.cy + j.ch > j.height ||
	    j.stride < j.width * 5 / 4) {
		fprintf(stderr, "crop or stride out of the frame\n");
		return 2;
	}

	long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
	j.nthreads = ncpu < 1 ? 1 : ncpu > 16 ? 16 : (int)ncpu;

	/* Bulb: frames from standard input. */
	if (!strcmp(in, "-sum") || !strcmp(in, "-mean")) {
		j.raw = bulb_frames(&j, !strcmp(in, "-mean"),
				    (int)(j.black * 1023 + 0.5f));
		if (!j.raw) {
			fprintf(stderr, "bulb: no frame\n");
			return 1;
		}
		goto developed_input;
	}

	/* The frame, or the burst's frames (comma separated) stacked. */
	const uint8_t *frames[64];
	int nframes = 0;
	char *list = strdup(in);
	for (char *name = strtok(list, ","); name && nframes < 64;
	     name = strtok(NULL, ",")) {
		int fd = open(name, O_RDONLY);
		struct stat st;
		if (fd < 0 || fstat(fd, &st) < 0) {
			perror(name);
			return 1;
		}
		if (st.st_size < (off_t)j.stride * j.height) {
			fprintf(stderr, "%s: %lld bytes, short of %d rows of %d\n",
				name, (long long)st.st_size, j.height, j.stride);
			return 1;
		}
		frames[nframes] = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE,
				       fd, 0);
		if (frames[nframes] == MAP_FAILED) {
			perror("mmap");
			return 1;
		}
		nframes++;
	}
	j.raw = nframes > 1 ? stack_frames(&j, frames, nframes) : frames[0];
developed_input:
	j.rgb = malloc((size_t)j.cw * j.ch * 3);
	if (!j.rgb) {
		perror("malloc");
		return 1;
	}

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

	const char *amount = getenv("PRO1X_CLARITY");
	if (amount && atof(amount) > 0)
		clarity(&j, atof(amount));
	const char *vivid = getenv("PRO1X_VIBRANCE");
	if (vivid && atof(vivid) > 0)
		vibrance(&j, atof(vivid));
	return write_jpeg(&j, out, turn, half, quality) ? 1 : 0;
}

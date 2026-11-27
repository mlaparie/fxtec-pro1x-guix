/* pro1x-uvc-feed — serve a video command's output as a UVC webcam.
 *
 *   pro1x-uvc-feed [-d /dev/videoN] [-g CONFIGFS-FUNCTION] [-i VS-INTERFACE]
 *                  [-v] -- COMMAND...
 *
 * The UVC gadget function (usb_f_uvc, set up by pro1x-usb-gadget) gives
 * the phone a V4L2 output device: what is queued on it goes to the USB host
 * as webcam frames.  The function leaves the class requests to userspace,
 * so this program:
 *   1. reads the formats and frame sizes the gadget offers from configfs
 *      (their indices are the kernel's, so they match the descriptors);
 *   2. answers the host's PROBE and COMMIT requests with them;
 *   3. when the host starts streaming, runs COMMAND with %w %h %r %f
 *      replaced by the committed width, height, rate and format (h264 or
 *      mjpeg), and queues each frame of its standard output to the gadget:
 *      H.264 as pro1x-screencast's PXSC records or as plain Annex B (one
 *      access unit per UVC frame), MJPEG as JPEG pictures (SOI to EOI);
 *   4. stops COMMAND when the host stops streaming or unplugs.
 * Nothing runs while no host streams.  A dropped isochronous packet costs
 * the host the rest of that frame, so keep keyframes frequent (-g 2 for
 * pro1x-screencast); SPS and PPS are repeated before every keyframe here.
 *
 * Frame-based (H.264) frames have no dwMaxVideoFrameBufferSize in configfs:
 * the kernel keeps 460800 bytes for them, and an access unit above that is
 * sent over consecutive buffers (the host sees two frames; a decoder's
 * parser joins them).  Keep the bit rate such that keyframes fit.
 *
 * -i: the interface number of the video streaming interface (default 1:
 * pro1x-usb-gadget links the UVC function first, so control is 0 and
 * streaming 1).  -v: log the requests.
 *
 * State: written 2026-11-27 from the kernel's f_uvc (Linux 7.3) and the
 * UVC 1.1 class specification; compiled, not yet run on the phone (its
 * kernel has no usb_f_uvc yet).
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <linux/usb/ch9.h>
#include <linux/usb/video.h>
#include <linux/videodev2.h>

#if __has_include(<linux/usb/g_uvc.h>)
#include <linux/usb/g_uvc.h>
#else
/* include/uapi/linux/usb/g_uvc.h, for a build without it. */
#define UVC_EVENT_FIRST		(V4L2_EVENT_PRIVATE_START + 0)
#define UVC_EVENT_CONNECT	(V4L2_EVENT_PRIVATE_START + 0)
#define UVC_EVENT_DISCONNECT	(V4L2_EVENT_PRIVATE_START + 1)
#define UVC_EVENT_STREAMON	(V4L2_EVENT_PRIVATE_START + 2)
#define UVC_EVENT_STREAMOFF	(V4L2_EVENT_PRIVATE_START + 3)
#define UVC_EVENT_SETUP		(V4L2_EVENT_PRIVATE_START + 4)
#define UVC_EVENT_DATA		(V4L2_EVENT_PRIVATE_START + 5)
struct uvc_request_data { __s32 length; __u8 data[60]; };
struct uvc_event {
	union {
		enum usb_device_speed speed;
		struct usb_ctrlrequest req;
		struct uvc_request_data data;
	};
};
#define UVCIOC_SEND_RESPONSE	_IOW('U', 1, struct uvc_request_data)
#endif

#define NBUF 4
#define MAX_FRAMES 32

static bool verbose, dry_run;
static int vs_intf = 1;
static const char *dev_path;
static const char *fn_path = "/sys/kernel/config/usb_gadget/pro1x/functions/uvc.usb0";
static char **command;
static int ncommand;

static void say(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	fputs("pro1x-uvc-feed: ", stderr);
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
}

static void die(const char *what)
{
	fprintf(stderr, "pro1x-uvc-feed: %s: %s\n", what, strerror(errno));
	exit(1);
}

/* ---- The formats and frames the gadget offers (from configfs) ---- */

struct frame {
	int fmt_index, frame_index;
	uint32_t fcc;		/* V4L2_PIX_FMT_H264 or _MJPEG */
	int w, h;
	uint32_t interval;	/* default, 100 ns units */
	uint32_t maxsize;	/* bytes per frame, for the probe control */
};
static struct frame frames[MAX_FRAMES];
static int nframes;

static long read_num(const char *dir, const char *name, long dflt)
{
	char path[512], buf[64];
	snprintf(path, sizeof path, "%s/%s", dir, name);
	FILE *f = fopen(path, "r");
	if (!f)
		return dflt;
	long v = dflt;
	if (fgets(buf, sizeof buf, f))
		v = strtol(buf, NULL, 0);
	fclose(f);
	return v;
}

static void read_format_dir(const char *group, uint32_t fcc)
{
	char dir[512];
	snprintf(dir, sizeof dir, "%s/streaming/%s", fn_path, group);
	DIR *d = opendir(dir);
	if (!d)
		return;
	struct dirent *e;
	while ((e = readdir(d))) {
		if (e->d_name[0] == '.')
			continue;
		char fdir[768];
		snprintf(fdir, sizeof fdir, "%s/%s", dir, e->d_name);
		int fmt_index = read_num(fdir, "bFormatIndex", 0);
		if (fmt_index <= 0)
			continue;	/* not linked into the header */
		DIR *fd = opendir(fdir);
		if (!fd)
			continue;
		struct dirent *fe;
		while ((fe = readdir(fd)) && nframes < MAX_FRAMES) {
			char frdir[1024];
			if (fe->d_name[0] == '.')
				continue;
			snprintf(frdir, sizeof frdir, "%s/%s", fdir, fe->d_name);
			int fi = read_num(frdir, "bFrameIndex", 0);
			if (fi <= 0)
				continue;
			struct frame *fr = &frames[nframes++];
			fr->fmt_index = fmt_index;
			fr->frame_index = fi;
			fr->fcc = fcc;
			fr->w = read_num(frdir, "wWidth", 0);
			fr->h = read_num(frdir, "wHeight", 0);
			fr->interval = read_num(frdir, "dwDefaultFrameInterval", 333333);
			/* The kernel's own default for frames without the attribute. */
			fr->maxsize = read_num(frdir, "dwMaxVideoFrameBufferSize", 460800);
		}
		closedir(fd);
	}
	closedir(d);
}

static struct frame *find_frame(int fmt_index, int frame_index)
{
	for (int i = 0; i < nframes; i++)
		if (frames[i].fmt_index == fmt_index &&
		    frames[i].frame_index == frame_index)
			return &frames[i];
	return NULL;
}

/* The first frame of a format: its default. */
static struct frame *first_frame(int fmt_index)
{
	struct frame *best = NULL;
	for (int i = 0; i < nframes; i++)
		if (frames[i].fmt_index == fmt_index &&
		    (!best || frames[i].frame_index < best->frame_index))
			best = &frames[i];
	return best;
}

/* ---- The probe and commit controls ---- */

static struct uvc_streaming_control probe, commit;
static int last_cs;		/* the control a SET_CUR is for */
static uint8_t vc_error;	/* VC_REQUEST_ERROR_CODE_CONTROL */

static void fill_control(struct uvc_streaming_control *c, int fmt_index,
			 int frame_index, uint32_t interval)
{
	struct frame *fr = find_frame(fmt_index, frame_index);
	if (!fr)
		fr = first_frame(fmt_index);
	if (!fr)
		fr = &frames[0];
	memset(c, 0, sizeof *c);
	c->bmHint = 1;		/* keep the frame interval */
	c->bFormatIndex = fr->fmt_index;
	c->bFrameIndex = fr->frame_index;
	c->dwFrameInterval = interval ? interval : fr->interval;
	c->dwMaxVideoFrameSize = fr->maxsize;
	c->dwMaxPayloadTransferSize = 3072;
	c->bmFramingInfo = 3;	/* FID and EOF are used */
	c->bPreferedVersion = 1;
	c->bMinVersion = 1;
	c->bMaxVersion = 1;
}

static void send_response(int fd, struct uvc_request_data *resp)
{
	if (ioctl(fd, UVCIOC_SEND_RESPONSE, resp) < 0)
		say("UVCIOC_SEND_RESPONSE: %s", strerror(errno));
}

static void stall(struct uvc_request_data *resp)
{
	resp->length = -EL2HLT;
}

static void handle_setup(int fd, const struct usb_ctrlrequest *req)
{
	struct uvc_request_data resp = { .length = 0 };
	int intf = req->wIndex & 0xff, entity = req->wIndex >> 8;
	int cs = req->wValue >> 8;
	bool get = req->bRequestType & USB_DIR_IN;

	if (verbose)
		say("setup type %02x req %02x cs %d intf %d entity %d len %d",
		     req->bRequestType, req->bRequest, cs, intf, entity,
		     req->wLength);

	if (entity != 0) {
		/* The camera terminal and processing unit declare no controls. */
		vc_error = 0x06;	/* invalid control */
		stall(&resp);
	} else if (intf == vs_intf &&
		   (cs == UVC_VS_PROBE_CONTROL || cs == UVC_VS_COMMIT_CONTROL)) {
		struct uvc_streaming_control *c =
			cs == UVC_VS_PROBE_CONTROL ? &probe : &commit;
		switch (req->bRequest) {
		case UVC_SET_CUR:
			last_cs = cs;
			resp.length = req->wLength;	/* the data follows */
			break;
		case UVC_GET_CUR:
			resp.length = req->wLength < (int)sizeof *c ? req->wLength : sizeof *c;
			memcpy(resp.data, c, resp.length);
			break;
		case UVC_GET_MIN:
		case UVC_GET_MAX:
		case UVC_GET_DEF: {
			struct uvc_streaming_control tmp;
			fill_control(&tmp, c->bFormatIndex ? c->bFormatIndex : 1,
				     c->bFrameIndex, 0);
			resp.length = req->wLength < (int)sizeof tmp ? req->wLength : sizeof tmp;
			memcpy(resp.data, &tmp, resp.length);
			break;
		}
		case UVC_GET_RES:
			resp.length = sizeof *c;
			memset(resp.data, 0, resp.length);
			break;
		case UVC_GET_LEN:
			resp.data[0] = sizeof *c;
			resp.data[1] = 0;
			resp.length = 2;
			break;
		case UVC_GET_INFO:
			resp.data[0] = 0x03;	/* get and set */
			resp.length = 1;
			break;
		default:
			stall(&resp);
		}
	} else if (intf == vs_intf - 1) {
		/* The video control interface itself. */
		if (cs == UVC_VC_REQUEST_ERROR_CODE_CONTROL && get) {
			if (req->bRequest == UVC_GET_INFO) {
				resp.data[0] = 0x01;
				resp.length = 1;
			} else {
				resp.data[0] = vc_error;
				resp.length = 1;
				vc_error = 0;
			}
		} else {
			vc_error = 0x06;
			stall(&resp);
		}
	} else {
		stall(&resp);
	}
	send_response(fd, &resp);
}

static void handle_data(int fd, const struct uvc_request_data *data)
{
	struct uvc_streaming_control in, *c;
	(void)fd;
	if (data->length < 8)
		return;
	memset(&in, 0, sizeof in);
	memcpy(&in, data->data,
	       data->length < (int)sizeof in ? (size_t)data->length : sizeof in);
	c = last_cs == UVC_VS_COMMIT_CONTROL ? &commit : &probe;
	fill_control(c, in.bFormatIndex, in.bFrameIndex, in.dwFrameInterval);
	if (verbose)
		say("%s: format %d frame %d interval %u",
		     last_cs == UVC_VS_COMMIT_CONTROL ? "commit" : "probe",
		     c->bFormatIndex, c->bFrameIndex, c->dwFrameInterval);
}

static void each_nal(const uint8_t *d, size_t n,
		     void (*fn)(const uint8_t *, size_t, void *), void *arg);
static uint32_t producer_fcc;

/* ---- The gadget's buffers ---- */

static struct { void *p; size_t len; bool queued; } bufs[NBUF];
static size_t sizeimage;
static bool streaming;
static long frames_sent, frames_dropped, frames_split;

static int xioctl(int fd, unsigned long req, void *arg)
{
	int r;
	do r = ioctl(fd, req, arg); while (r < 0 && errno == EINTR);
	return r;
}

static int stream_start(int fd, const struct frame *fr)
{
	struct v4l2_format fmt = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT };
	fmt.fmt.pix.width = fr->w;
	fmt.fmt.pix.height = fr->h;
	fmt.fmt.pix.pixelformat = fr->fcc;
	fmt.fmt.pix.field = V4L2_FIELD_NONE;
	fmt.fmt.pix.sizeimage = fr->maxsize;
	if (xioctl(fd, VIDIOC_S_FMT, &fmt) < 0) {
		say("VIDIOC_S_FMT %dx%d: %s", fr->w, fr->h, strerror(errno));
		return -1;
	}
	sizeimage = fmt.fmt.pix.sizeimage;

	struct v4l2_requestbuffers rb = {
		.count = NBUF, .type = V4L2_BUF_TYPE_VIDEO_OUTPUT,
		.memory = V4L2_MEMORY_MMAP };
	if (xioctl(fd, VIDIOC_REQBUFS, &rb) < 0) {
		say("VIDIOC_REQBUFS: %s", strerror(errno));
		return -1;
	}
	for (unsigned i = 0; i < rb.count && i < NBUF; i++) {
		struct v4l2_buffer b = { .index = i,
			.type = V4L2_BUF_TYPE_VIDEO_OUTPUT, .memory = V4L2_MEMORY_MMAP };
		if (xioctl(fd, VIDIOC_QUERYBUF, &b) < 0) {
			say("VIDIOC_QUERYBUF: %s", strerror(errno));
			return -1;
		}
		bufs[i].len = b.length;
		bufs[i].p = mmap(NULL, b.length, PROT_READ | PROT_WRITE,
				 MAP_SHARED, fd, b.m.offset);
		if (bufs[i].p == MAP_FAILED) {
			say("mmap: %s", strerror(errno));
			return -1;
		}
		bufs[i].queued = false;
	}
	int type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	if (xioctl(fd, VIDIOC_STREAMON, &type) < 0) {
		say("VIDIOC_STREAMON: %s", strerror(errno));
		return -1;
	}
	streaming = true;
	frames_sent = frames_dropped = frames_split = 0;
	return 0;
}

static void stream_stop(int fd)
{
	int type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	if (!streaming)
		return;
	xioctl(fd, VIDIOC_STREAMOFF, &type);
	for (int i = 0; i < NBUF; i++) {
		if (bufs[i].p && bufs[i].p != MAP_FAILED)
			munmap(bufs[i].p, bufs[i].len);
		bufs[i].p = NULL;
		bufs[i].queued = false;
	}
	struct v4l2_requestbuffers rb = { .count = 0,
		.type = V4L2_BUF_TYPE_VIDEO_OUTPUT, .memory = V4L2_MEMORY_MMAP };
	xioctl(fd, VIDIOC_REQBUFS, &rb);
	streaming = false;
	say("stream stopped: %ld frames sent, %ld dropped, %ld split",
	     frames_sent, frames_dropped, frames_split);
}

static bool any_queued(void)
{
	for (int i = 0; i < NBUF; i++)
		if (bufs[i].queued)
			return true;
	return false;
}

static int free_buffer(void)
{
	for (int i = 0; i < NBUF; i++)
		if (bufs[i].p && !bufs[i].queued)
			return i;
	return -1;
}

static void dequeue(int fd)
{
	struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT,
				 .memory = V4L2_MEMORY_MMAP };
	while (xioctl(fd, VIDIOC_DQBUF, &b) == 0) {
		if (b.index < NBUF)
			bufs[b.index].queued = false;
		memset(&b, 0, sizeof b);
		b.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
		b.memory = V4L2_MEMORY_MMAP;
	}
}

static void describe_nal(const uint8_t *nal, size_t n, void *arg)
{
	(void)arg;
	printf(" nal%d(%zu)", nal[0] & 0x1f, n);
}

/* One frame to the host; longer than a buffer, over several. */
static void send_frame(int fd, const uint8_t *data, size_t len)
{
	if (dry_run) {
		printf("frame %zu bytes:", len);
		if (producer_fcc == V4L2_PIX_FMT_MJPEG)
			printf(" jpeg %02x%02x..%02x%02x", data[0], data[1],
			       data[len - 2], data[len - 1]);
		else
			each_nal(data, len, describe_nal, NULL);
		printf("\n");
		frames_sent++;
		return;
	}
	if (!streaming)
		return;
	size_t off = 0;
	int parts = 0;
	while (off < len) {
		int i = free_buffer();
		if (i < 0) {
			dequeue(fd);
			i = free_buffer();
		}
		if (i < 0) {
			frames_dropped++;
			return;
		}
		size_t n = len - off;
		if (n > sizeimage)
			n = sizeimage;
		memcpy(bufs[i].p, data + off, n);
		struct v4l2_buffer b = { .index = i,
			.type = V4L2_BUF_TYPE_VIDEO_OUTPUT, .memory = V4L2_MEMORY_MMAP,
			.bytesused = n, .field = V4L2_FIELD_NONE };
		struct timespec ts;
		clock_gettime(CLOCK_MONOTONIC, &ts);
		b.timestamp.tv_sec = ts.tv_sec;
		b.timestamp.tv_usec = ts.tv_nsec / 1000;
		if (xioctl(fd, VIDIOC_QBUF, &b) < 0) {
			say("VIDIOC_QBUF: %s", strerror(errno));
			frames_dropped++;
			return;
		}
		bufs[i].queued = true;
		off += n;
		parts++;
	}
	frames_sent++;
	if (parts > 1)
		frames_split++;
}

/* ---- The producer: COMMAND, its frames parsed from a pipe ---- */

static pid_t producer;
static int producer_fd = -1;
static uint8_t *inbuf;
static size_t inlen, incap;
static time_t producer_died_at;
static struct frame current;

static char *expand(const char *s, const struct frame *fr)
{
	char *out = malloc(strlen(s) * 8 + 64), *o = out;
	int rate = fr->interval ? (10000000 + fr->interval / 2) / fr->interval : 30;
	for (; *s; s++) {
		if (*s == '%' && s[1]) {
			s++;
			switch (*s) {
			case 'w': o += sprintf(o, "%d", fr->w); break;
			case 'h': o += sprintf(o, "%d", fr->h); break;
			case 'r': o += sprintf(o, "%d", rate); break;
			case 'f': o += sprintf(o, "%s", fr->fcc == V4L2_PIX_FMT_MJPEG
					       ? "mjpeg" : "h264"); break;
			case '%': *o++ = '%'; break;
			default: *o++ = '%'; *o++ = *s;
			}
		} else {
			*o++ = *s;
		}
	}
	*o = 0;
	return out;
}

static void producer_start(const struct frame *fr)
{
	int p[2];
	if (pipe(p) < 0)
		die("pipe");
	producer = fork();
	if (producer < 0)
		die("fork");
	if (producer == 0) {
		char **argv = calloc(ncommand + 1, sizeof *argv);
		for (int i = 0; i < ncommand; i++)
			argv[i] = expand(command[i], fr);
		dup2(p[1], 1);
		close(p[0]);
		close(p[1]);
		/* Its own group, so a shell's children go with it. */
		setpgid(0, 0);
		execvp(argv[0], argv);
		fprintf(stderr, "pro1x-uvc-feed: exec %s: %s\n", argv[0], strerror(errno));
		_exit(127);
	}
	close(p[1]);
	producer_fd = p[0];
	producer_fcc = fr->fcc;
	inlen = 0;
	if (verbose)
		say("producer %d started for %dx%d", producer, fr->w, fr->h);
}

static void producer_stop(void)
{
	if (producer > 0) {
		kill(-producer, SIGTERM);
		kill(producer, SIGTERM);
		int st;
		for (int i = 0; i < 20 && waitpid(producer, &st, WNOHANG) == 0; i++)
			usleep(100000);
		if (waitpid(producer, &st, WNOHANG) == 0) {
			kill(-producer, SIGKILL);
			waitpid(producer, &st, 0);
		}
		producer = 0;
	}
	if (producer_fd >= 0)
		close(producer_fd);
	producer_fd = -1;
	inlen = 0;
}

/* ---- H.264: SPS and PPS before every keyframe ---- */

static uint8_t sps[256], pps[256];
static size_t sps_len, pps_len;

/* Call FN for each NAL of an Annex B access unit. */
static void each_nal(const uint8_t *d, size_t n,
		     void (*fn)(const uint8_t *, size_t, void *), void *arg)
{
	size_t i = 0, start = 0;
	bool in = false;
	while (i + 3 <= n) {
		if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1) {
			if (in && i > start)
				fn(d + start, i - start - (i > start && d[i - 1] == 0 ? 1 : 0), arg);
			start = i + 3;
			in = true;
			i += 3;
		} else {
			i++;
		}
	}
	if (in && n > start)
		fn(d + start, n - start, arg);
}

struct au_info { bool has_idr, has_sps, has_pps; };

static void nal_info(const uint8_t *nal, size_t n, void *arg)
{
	struct au_info *ai = arg;
	if (n < 1)
		return;
	switch (nal[0] & 0x1f) {
	case 5: ai->has_idr = true; break;
	case 7:
		ai->has_sps = true;
		if (n <= sizeof sps) { memcpy(sps, nal, n); sps_len = n; }
		break;
	case 8:
		ai->has_pps = true;
		if (n <= sizeof pps) { memcpy(pps, nal, n); pps_len = n; }
		break;
	}
}

static void send_h264_au(int fd, const uint8_t *d, size_t n)
{
	struct au_info ai = { 0 };
	each_nal(d, n, nal_info, &ai);
	if (ai.has_idr && !ai.has_sps && sps_len && pps_len) {
		static const uint8_t sc[4] = { 0, 0, 0, 1 };
		size_t total = 8 + sps_len + pps_len + n;
		uint8_t *out = malloc(total), *o = out;
		memcpy(o, sc, 4); o += 4; memcpy(o, sps, sps_len); o += sps_len;
		memcpy(o, sc, 4); o += 4; memcpy(o, pps, pps_len); o += pps_len;
		memcpy(o, d, n);
		send_frame(fd, out, total);
		free(out);
	} else {
		send_frame(fd, d, n);
	}
}

/* ---- Splitting the producer's byte stream into frames ---- */

static bool nal_starts_au(const uint8_t *nal, size_t n)
{
	int type = nal[0] & 0x1f;
	if (type == 9 || type == 7 || type == 8 || type == 6)
		return true;
	/* A slice whose first_mb_in_slice is 0: ue(v) "1" is the top bit. */
	return type >= 1 && type <= 5 && n >= 2 && (nal[1] & 0x80);
}

static bool nal_is_vcl(const uint8_t *nal)
{
	int type = nal[0] & 0x1f;
	return type >= 1 && type <= 5;
}

/* Returns how many bytes of inbuf were consumed. */
static size_t parse_frames(int fd)
{
	size_t used = 0;
	if (producer_fcc == V4L2_PIX_FMT_MJPEG) {
		for (;;) {
			uint8_t *p = inbuf + used, *end = inbuf + inlen;
			uint8_t *soi = NULL, *eoi = NULL;
			for (uint8_t *q = p; q + 1 < end; q++)
				if (q[0] == 0xff && q[1] == 0xd8) { soi = q; break; }
			if (!soi) { used = inlen; break; }
			for (uint8_t *q = soi + 2; q + 1 < end; q++)
				if (q[0] == 0xff && q[1] == 0xd9) { eoi = q + 2; break; }
			if (!eoi) { used = soi - inbuf; break; }
			send_frame(fd, soi, eoi - soi);
			used = eoi - inbuf;
		}
		return used;
	}
	if (inlen >= 4 && memcmp(inbuf, "PXSC", 4) == 0) {
		/* pro1x-screencast records: magic, u32 length, u8 keyframe,
		 * u64 capture time, u64 encode time, then the Annex B bytes. */
		for (;;) {
			uint8_t *p = inbuf + used;
			size_t left = inlen - used;
			if (left < 25)
				break;
			if (memcmp(p, "PXSC", 4) != 0) {
				say("lost sync with the PXSC records");
				used = inlen;
				break;
			}
			uint32_t len;
			memcpy(&len, p + 4, 4);
			if (left < 25 + len)
				break;
			send_h264_au(fd, p + 25, len);
			used += 25 + len;
		}
		return used;
	}
	/* Plain Annex B: an access unit ends where the next one starts, so
	 * each frame leaves one frame after it arrived. */
	size_t i = 0, au_start = 0;
	bool au_vcl = false;
	for (;;) {
		while (i + 3 <= inlen &&
		       !(inbuf[i] == 0 && inbuf[i + 1] == 0 && inbuf[i + 2] == 1))
			i++;
		if (i + 5 > inlen)
			break;		/* no start code, or no NAL header yet */
		const uint8_t *nal = inbuf + i + 3;
		size_t sc = i > au_start && inbuf[i - 1] == 0 ? i - 1 : i;
		if (au_vcl && nal_starts_au(nal, inlen - (i + 3))) {
			send_h264_au(fd, inbuf + au_start, sc - au_start);
			au_start = sc;
			au_vcl = false;
		}
		if (nal_is_vcl(nal))
			au_vcl = true;
		i += 3;
	}
	return au_start;
}

static void read_producer(int fd)
{
	if (incap - inlen < 65536) {
		incap = incap ? incap * 2 : (1 << 20);
		inbuf = realloc(inbuf, incap);
		if (!inbuf)
			die("realloc");
	}
	ssize_t n = read(producer_fd, inbuf + inlen, incap - inlen);
	if (n <= 0) {
		if (n < 0 && (errno == EAGAIN || errno == EINTR))
			return;
		int st = 0;
		waitpid(producer, &st, WNOHANG);
		say("producer ended (status %d); again in a second", st);
		close(producer_fd);
		producer_fd = -1;
		producer = 0;
		producer_died_at = time(NULL);
		return;
	}
	inlen += n;
	size_t used = parse_frames(fd);
	if (used) {
		memmove(inbuf, inbuf + used, inlen - used);
		inlen -= used;
	}
	if (inlen > (32u << 20)) {
		say("no frame boundary in 32 MB: dropping the input");
		inlen = 0;
	}
}

/* ---- Events ---- */

static void subscribe(int fd, uint32_t type)
{
	struct v4l2_event_subscription sub = { .type = type };
	if (xioctl(fd, VIDIOC_SUBSCRIBE_EVENT, &sub) < 0)
		die("VIDIOC_SUBSCRIBE_EVENT");
}

static void handle_event(int fd)
{
	struct v4l2_event ev;
	if (xioctl(fd, VIDIOC_DQEVENT, &ev) < 0)
		return;
	struct uvc_event *uev = (struct uvc_event *)ev.u.data;
	switch (ev.type) {
	case UVC_EVENT_CONNECT:
		if (verbose)
			say("host connected, speed %d", uev->speed);
		break;
	case UVC_EVENT_DISCONNECT:
		say("host gone");
		producer_stop();
		stream_stop(fd);
		break;
	case UVC_EVENT_SETUP:
		handle_setup(fd, &uev->req);
		break;
	case UVC_EVENT_DATA:
		handle_data(fd, &uev->data);
		break;
	case UVC_EVENT_STREAMON: {
		struct frame *fr = find_frame(commit.bFormatIndex, commit.bFrameIndex);
		if (!fr)
			fr = &frames[0];
		current = *fr;
		current.interval = commit.dwFrameInterval ? commit.dwFrameInterval : fr->interval;
		say("host streams %s %dx%d at %u/100ns", fr->fcc == V4L2_PIX_FMT_MJPEG ?
		     "MJPEG" : "H.264", fr->w, fr->h, current.interval);
		producer_stop();
		stream_stop(fd);
		if (stream_start(fd, &current) < 0) {
			stream_stop(fd);
			break;
		}
		producer_start(&current);
		break;
	}
	case UVC_EVENT_STREAMOFF:
		say("host stopped");
		producer_stop();
		stream_stop(fd);
		break;
	}
}

/* ---- main ---- */

static const char *find_device(void)
{
	static char path[300];
	DIR *d = opendir("/sys/class/video4linux");
	if (!d)
		return NULL;
	struct dirent *e;
	while ((e = readdir(d))) {
		char fn[320];
		if (strncmp(e->d_name, "video", 5) != 0)
			continue;
		snprintf(fn, sizeof fn, "/sys/class/video4linux/%s/function_name", e->d_name);
		if (access(fn, R_OK) == 0) {
			snprintf(path, sizeof path, "/dev/%s", e->d_name);
			closedir(d);
			return path;
		}
	}
	closedir(d);
	return NULL;
}

static volatile sig_atomic_t quit;
static void on_signal(int s) { (void)s; quit = 1; }

int main(int argc, char **argv)
{
	int opt;
	while ((opt = getopt(argc, argv, "d:g:i:vt:")) != -1) {
		switch (opt) {
		case 't':
			/* -t h264|mjpeg: parse stdin, print the frames, no device. */
			dry_run = true;
			producer_fcc = strcmp(optarg, "mjpeg") == 0 ?
				V4L2_PIX_FMT_MJPEG : V4L2_PIX_FMT_H264;
			break;
		case 'd': dev_path = optarg; break;
		case 'g': fn_path = optarg; break;
		case 'i': vs_intf = atoi(optarg); break;
		case 'v': verbose = true; break;
		default:
			fprintf(stderr, "usage: pro1x-uvc-feed [-d DEV] [-g FUNCTION-DIR] "
				"[-i VS-INTERFACE] [-v] -- COMMAND...\n"
				"       pro1x-uvc-feed -t h264|mjpeg < STREAM\n");
			return 2;
		}
	}
	if (dry_run) {
		producer_fd = 0;
		while (producer_fd >= 0) {
			read_producer(-1);
			if (producer_fd < 0 || (inlen == 0 && feof(stdin)))
				break;
		}
		printf("%ld frames, %zu bytes left unparsed\n", frames_sent, inlen);
		return 0;
	}
	command = argv + optind;
	ncommand = argc - optind;
	if (ncommand < 1) {
		say("no command given");
		return 2;
	}
	if (!dev_path)
		dev_path = find_device();
	if (!dev_path) {
		say("no UVC gadget device (is pro1x-usb-gadget in video mode?)");
		return 1;
	}
	read_format_dir("framebased", V4L2_PIX_FMT_H264);
	read_format_dir("mjpeg", V4L2_PIX_FMT_MJPEG);
	if (!nframes) {
		say("no formats under %s/streaming", fn_path);
		return 1;
	}
	for (int i = 0; i < nframes; i++)
		if (verbose)
			say("format %d frame %d: %s %dx%d", frames[i].fmt_index,
			     frames[i].frame_index, frames[i].fcc == V4L2_PIX_FMT_MJPEG ?
			     "MJPEG" : "H.264", frames[i].w, frames[i].h);
	fill_control(&probe, 1, 1, 0);
	commit = probe;

	int fd = open(dev_path, O_RDWR | O_NONBLOCK);
	if (fd < 0)
		die(dev_path);
	struct v4l2_capability cap;
	if (xioctl(fd, VIDIOC_QUERYCAP, &cap) < 0)
		die("VIDIOC_QUERYCAP");
	if (!(cap.device_caps & V4L2_CAP_VIDEO_OUTPUT)) {
		say("%s is not a video output device", dev_path);
		return 1;
	}
	subscribe(fd, UVC_EVENT_CONNECT);
	subscribe(fd, UVC_EVENT_DISCONNECT);
	subscribe(fd, UVC_EVENT_SETUP);
	subscribe(fd, UVC_EVENT_DATA);
	subscribe(fd, UVC_EVENT_STREAMON);
	subscribe(fd, UVC_EVENT_STREAMOFF);
	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);
	signal(SIGPIPE, SIG_IGN);
	say("serving %s (%s), %d frame sizes", dev_path, cap.card, nframes);

	while (!quit) {
		struct pollfd pfd[2] = {
			/* POLLOUT only with buffers out: with none queued the
			 * output queue is always writable. */
			{ fd, POLLPRI | (streaming && any_queued() ? POLLOUT : 0), 0 },
			{ producer_fd, producer_fd >= 0 ? POLLIN : 0, 0 },
		};
		int r = poll(pfd, 2, 500);
		if (r < 0) {
			if (errno == EINTR)
				continue;
			die("poll");
		}
		if (pfd[0].revents & POLLPRI)
			handle_event(fd);
		if (pfd[0].revents & POLLOUT)
			dequeue(fd);
		if (pfd[1].revents & (POLLIN | POLLHUP))
			read_producer(fd);
		if (streaming && producer == 0 && producer_fd < 0 &&
		    time(NULL) > producer_died_at)
			producer_start(&current);
	}
	producer_stop();
	stream_stop(fd);
	close(fd);
	return 0;
}

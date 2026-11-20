/* pro1x-screencast — the screen to H.264 with no CPU copy of a pixel.
 *
 *   pro1x-screencast [-o OUTPUT] [-s WxH] [-r FPS] [-b BITRATE] [-g GOP]
 *                    [-t TURN] [-n FRAMES]
 *
 * As scrcpy does on Android (the encoder's input surface), but on Sway:
 *   1. Sway copies the output into a GPU buffer of ours (wlr-screencopy,
 *      on damage), not through the portal and PipeWire, whose frames came
 *      400 ms old (2026-11-20);
 *   2. the GPU turns, scales and converts it to NV12 straight into
 *      Venus's own input buffers (V4L2 buffers exported as DMA-BUFs,
 *      rendered as an 8-bit and a 16-bit image: Y, then UV);
 *   3. Venus encodes it; each access unit goes to stdout as
 *      "PXSC" magic, u32 length, u8 keyframe, u64 capture time (realtime,
 *      µs), u64 time it left the encoder (realtime, µs), then the Annex B
 *      bytes (SPS and PPS only before the first keyframe: Venus does not
 *      repeat them, the reader keeps them).
 * stdin, one byte each: k a keyframe, h hold (no new frames for the
 * encoder: the network is behind), g go again, q quit.
 *
 * Defaults: output DSI-1, 1600x800, 20 fps, 2 Mbit/s constant, a keyframe
 * every 10 s, the turn of the output (0, 90, 180 or 270; -t overrides).
 * -n FRAMES: stop after that many frames (tests).
 *
 * State: written 2026-11-20; see the end of device/stream/README.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <time.h>
#include <unistd.h>

#include <drm_fourcc.h>
#include <gbm.h>
#include <linux/videodev2.h>
#include <wayland-client.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include "linux-dmabuf-v1-client-protocol.h"
#include "wlr-screencopy-unstable-v1-client-protocol.h"

#define CAPS 3                  /* screen copies in flight or ready */
#define OUTS 4                  /* Venus input buffers */
#define CAPTURES 4              /* Venus output buffers */

static void die(const char *what)
{
	fprintf(stderr, "pro1x-screencast: %s: %s\n", what, strerror(errno));
	exit(1);
}

static void fail(const char *what)
{
	fprintf(stderr, "pro1x-screencast: %s\n", what);
	exit(1);
}

static uint64_t now_us(clockid_t clk)
{
	struct timespec ts;
	clock_gettime(clk, &ts);
	return (uint64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

/* ---- options ---- */
static const char *want_output = "DSI-1";
static int W = 1600, H = 800, FPS = 20, BITRATE = 2000000, GOP_S = 10;
static int TURN = -1;           /* -1: the output's own */
static long FRAMES = 0;

/* ---- Wayland ---- */
static struct wl_display *display;
static struct zwlr_screencopy_manager_v1 *copier;
static struct zwp_linux_dmabuf_v1 *dmabuf;
static struct wl_output *output;
static int output_transform;

struct shot {
	struct gbm_bo *bo;
	struct wl_buffer *buffer;
	EGLImageKHR image;
	GLuint tex;
	uint64_t mono_us;           /* when Sway presented it */
	bool busy;                  /* being copied into */
	bool ready;                 /* copied, not yet encoded */
	bool y_invert;
};
static struct shot shots[CAPS];
static uint32_t shot_format, shot_w, shot_h;
static bool shot_dmabuf_ok, shot_buffer_done;
static struct zwlr_screencopy_frame_v1 *frame;
static struct shot *frame_shot;

/* Each output's transform, kept with it (its listener's data): with one
 * variable, the last output listed (a stream's own, not turned) gave its
 * turn to the panel, whose picture came sideways (2026-11-20). */
static void output_geometry(void *d, struct wl_output *o, int32_t x, int32_t y,
			    int32_t pw, int32_t ph, int32_t sub, const char *make,
			    const char *model, int32_t transform)
{
	(void)o; (void)x; (void)y; (void)pw; (void)ph; (void)sub;
	(void)make; (void)model;
	*(int *)d = transform;
	if (o == output)
		output_transform = transform;
}
static void output_mode(void *d, struct wl_output *o, uint32_t f, int32_t w,
			int32_t h, int32_t r) { (void)d; (void)o; (void)f; (void)w; (void)h; (void)r; }
static void output_done(void *d, struct wl_output *o) { (void)d; (void)o; }
static void output_scale(void *d, struct wl_output *o, int32_t s) { (void)d; (void)o; (void)s; }
static struct wl_output *candidate;
static void output_name(void *d, struct wl_output *o, const char *name)
{
	if (!strcmp(name, want_output)) {
		output = o;
		output_transform = *(int *)d;
	}
}
static void output_description(void *d, struct wl_output *o, const char *s) { (void)d; (void)o; (void)s; }
static const struct wl_output_listener output_listener = {
	output_geometry, output_mode, output_done, output_scale,
	output_name, output_description,
};

static void global(void *d, struct wl_registry *reg, uint32_t name,
		   const char *iface, uint32_t version)
{
	(void)d;
	if (!strcmp(iface, zwlr_screencopy_manager_v1_interface.name))
		copier = wl_registry_bind(reg, name, &zwlr_screencopy_manager_v1_interface,
					  version < 3 ? version : 3);
	else if (!strcmp(iface, zwp_linux_dmabuf_v1_interface.name))
		dmabuf = wl_registry_bind(reg, name, &zwp_linux_dmabuf_v1_interface, 3);
	else if (!strcmp(iface, wl_output_interface.name) && version >= 4) {
		candidate = wl_registry_bind(reg, name, &wl_output_interface, 4);
		wl_output_add_listener(candidate, &output_listener, calloc(1, sizeof(int)));
	}
}
static void global_remove(void *d, struct wl_registry *r, uint32_t n) { (void)d; (void)r; (void)n; }
static const struct wl_registry_listener registry_listener = { global, global_remove };

/* ---- GBM, EGL, GL ---- */
static struct gbm_device *gbm;
static EGLDisplay egl;
static EGLContext ctx;
static PFNEGLCREATEIMAGEKHRPROC create_image;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target;
static GLuint prog_y, prog_uv, vbo;
static GLint uni_turn_y, uni_turn_uv, uni_flip_y, uni_flip_uv, uni_px_uv;

static GLuint shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	GLint ok;
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[1024];
		glGetShaderInfoLog(s, sizeof log, NULL, log);
		fprintf(stderr, "shader: %s\n", log);
		exit(1);
	}
	return s;
}

/* The stream's pixel (u, v in 0..1, landscape as viewed) to the copy's,
 * which is the output's buffer before its turn. */
static const char *vertex_src =
	"attribute vec2 pos;\n"
	"varying vec2 uv;\n"
	"void main() { uv = pos * 0.5 + 0.5; gl_Position = vec4(pos, 0.0, 1.0); }\n";

#define SAMPLE \
	"precision mediump float;\n" \
	"varying vec2 uv;\n" \
	"uniform sampler2D tex;\n" \
	"uniform int turn;\n" \
	"uniform float flip;\n" \
	"vec3 at(vec2 p) {\n" \
	"  vec2 q = p;\n" /* row 0 is the top in both buffers */ \
	"  vec2 s = q;\n" \
	"  if (turn == 1) s = vec2(q.y, 1.0 - q.x);\n" \
	"  else if (turn == 2) s = vec2(1.0 - q.x, 1.0 - q.y);\n" \
	"  else if (turn == 3) s = vec2(1.0 - q.y, q.x);\n" \
	"  if (flip > 0.5) s.y = 1.0 - s.y;\n" \
	"  return texture2D(tex, s).rgb;\n" /* EGL samples in the format's own order */ \
	"}\n"

/* BT.709, limited range, as the stream's VUI says (venus_setup): with no
 * colour information, Chromium assumed BT.709 and the BT.601 colours of the
 * first version looked wrong (author, 2026-11-20). */
static const char *y_src = SAMPLE
	"void main() { vec3 c = at(uv);\n"
	"  gl_FragColor = vec4(dot(c, vec3(0.1826, 0.6142, 0.0620)) + 0.0625, 0.0, 0.0, 1.0); }\n";
static const char *uv_src = SAMPLE
	"uniform vec2 px;\n"     /* one stream pixel, in uv */
	"void main() {\n"
	"  vec3 c = 0.25 * (at(uv + vec2(-0.5, -0.5) * px) + at(uv + vec2(0.5, -0.5) * px)\n"
	"                 + at(uv + vec2(-0.5, 0.5) * px) + at(uv + vec2(0.5, 0.5) * px));\n"
	"  float u = dot(c, vec3(-0.1006, -0.3386, 0.4392)) + 0.5;\n"
	"  float v = dot(c, vec3(0.4392, -0.3989, -0.0403)) + 0.5;\n"
	"  gl_FragColor = vec4(u, v, 0.0, 1.0); }\n";

static GLuint program(const char *frag, GLint *turn, GLint *flip)
{
	GLuint p = glCreateProgram();
	glAttachShader(p, shader(GL_VERTEX_SHADER, vertex_src));
	glAttachShader(p, shader(GL_FRAGMENT_SHADER, frag));
	glBindAttribLocation(p, 0, "pos");
	glLinkProgram(p);
	GLint ok;
	glGetProgramiv(p, GL_LINK_STATUS, &ok);
	if (!ok)
		fail("program does not link");
	*turn = glGetUniformLocation(p, "turn");
	*flip = glGetUniformLocation(p, "flip");
	return p;
}

static void gl_setup(void)
{
	int fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
	if (fd < 0)
		die("/dev/dri/renderD128");
	gbm = gbm_create_device(fd);
	if (!gbm)
		fail("gbm_create_device");
	PFNEGLGETPLATFORMDISPLAYEXTPROC get_display =
		(void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
	egl = get_display(EGL_PLATFORM_GBM_KHR, gbm, NULL);
	if (!eglInitialize(egl, NULL, NULL))
		fail("eglInitialize");
	eglBindAPI(EGL_OPENGL_ES_API);
	static const EGLint attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	ctx = eglCreateContext(egl, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, attrs);
	if (ctx == EGL_NO_CONTEXT)
		fail("eglCreateContext");
	if (!eglMakeCurrent(egl, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx))
		fail("eglMakeCurrent (surfaceless)");
	create_image = (void *)eglGetProcAddress("eglCreateImageKHR");
	image_target = (void *)eglGetProcAddress("glEGLImageTargetTexture2DOES");
	prog_y = program(y_src, &uni_turn_y, &uni_flip_y);
	prog_uv = program(uv_src, &uni_turn_uv, &uni_flip_uv);
	uni_px_uv = glGetUniformLocation(prog_uv, "px");
	static const GLfloat quad[] = { -1, -1, 1, -1, -1, 1, 1, 1 };
	glGenBuffers(1, &vbo);
	glBindBuffer(GL_ARRAY_BUFFER, vbo);
	glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
}

static EGLImageKHR import(int fd, uint32_t fourcc, int w, int h, int pitch,
			  int offset, uint64_t modifier)
{
	EGLint a[] = {
		EGL_WIDTH, w, EGL_HEIGHT, h, EGL_LINUX_DRM_FOURCC_EXT, fourcc,
		EGL_DMA_BUF_PLANE0_FD_EXT, fd, EGL_DMA_BUF_PLANE0_OFFSET_EXT, offset,
		EGL_DMA_BUF_PLANE0_PITCH_EXT, pitch,
		EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, (EGLint)(modifier & 0xffffffff),
		EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, (EGLint)(modifier >> 32),
		EGL_NONE,
	};
	if (modifier == DRM_FORMAT_MOD_INVALID)
		a[12] = EGL_NONE;
	EGLImageKHR img = create_image(egl, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, a);
	if (img == EGL_NO_IMAGE_KHR)
		fprintf(stderr, "pro1x-screencast: eglCreateImage %.4s %dx%d pitch %d offset %d: 0x%x\n",
			(char *)&fourcc, w, h, pitch, offset, eglGetError());
	return img;
}

static GLuint texture(EGLImageKHR img)
{
	GLuint t;
	glGenTextures(1, &t);
	glBindTexture(GL_TEXTURE_2D, t);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	image_target(GL_TEXTURE_2D, img);
	return t;
}

/* ---- Venus ---- */
static int enc = -1;
struct outbuf {
	int fd;                     /* its DMA-BUF */
	GLuint fb_y, fb_uv;
	bool queued;
};
static struct outbuf outs[OUTS];
static void *caps_map[CAPTURES];
static size_t caps_len[CAPTURES];
static int stride, uv_offset;
static bool hold;
static long sent;
static bool stdin_open = true;

static int xioctl(int fd, unsigned long req, void *arg)
{
	int r;
	do r = ioctl(fd, req, arg); while (r < 0 && errno == EINTR);
	return r;
}

static void ctrl(uint32_t id, int32_t value, const char *name)
{
	struct v4l2_control c = { .id = id, .value = value };
	if (xioctl(enc, VIDIOC_S_CTRL, &c) < 0)
		fprintf(stderr, "pro1x-screencast: %s: %s\n", name, strerror(errno));
}

static void venus_setup(void)
{
	for (int i = 0; i < 32 && enc < 0; i++) {
		char path[32];
		snprintf(path, sizeof path, "/dev/video%d", i);
		int fd = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0)
			continue;
		struct v4l2_capability cap = { 0 };
		if (!xioctl(fd, VIDIOC_QUERYCAP, &cap) && strstr((char *)cap.card, "encoder"))
			enc = fd;
		else
			close(fd);
	}
	if (enc < 0)
		fail("no Venus encoder");

	struct v4l2_format f = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE };
	f.fmt.pix_mp.width = W;
	f.fmt.pix_mp.height = H;
	f.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_H264;
	f.fmt.pix_mp.num_planes = 1;
	f.fmt.pix_mp.plane_fmt[0].sizeimage = 1024 * 1024;
	if (xioctl(enc, VIDIOC_S_FMT, &f) < 0)
		die("S_FMT capture");
	memset(&f, 0, sizeof f);
	f.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	f.fmt.pix_mp.width = W;
	f.fmt.pix_mp.height = H;
	f.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_NV12;
	f.fmt.pix_mp.num_planes = 1;
	/* What the shaders write; Venus puts it in the stream's VUI. */
	f.fmt.pix_mp.colorspace = V4L2_COLORSPACE_REC709;
	f.fmt.pix_mp.ycbcr_enc = V4L2_YCBCR_ENC_709;
	f.fmt.pix_mp.quantization = V4L2_QUANTIZATION_LIM_RANGE;
	f.fmt.pix_mp.xfer_func = V4L2_XFER_FUNC_709;
	if (xioctl(enc, VIDIOC_S_FMT, &f) < 0)
		die("S_FMT output");
	stride = f.fmt.pix_mp.plane_fmt[0].bytesperline;
	/* Venus rounds the width up to its alignment (1600 became 1664):
	 * the picture is the top left W x H of its buffer, so says the crop. */
	struct v4l2_selection sel = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT,
		.target = V4L2_SEL_TGT_CROP, .r = { 0, 0, W, H } };
	if (xioctl(enc, VIDIOC_S_SELECTION, &sel) < 0)
		fprintf(stderr, "pro1x-screencast: crop: %s\n", strerror(errno));
	/* NV12 as Venus lays it out: the UV rows after the Y rows, each
	 * plane's rows a multiple of 32 (sizeimage holds both, and more). */
	int rows = (f.fmt.pix_mp.height + 31) & ~31;
	uv_offset = stride * rows;
	fprintf(stderr, "pro1x-screencast: Venus NV12 %ux%u, stride %d, UV at %d, size %u\n",
		f.fmt.pix_mp.width, f.fmt.pix_mp.height, stride, uv_offset,
		f.fmt.pix_mp.plane_fmt[0].sizeimage);

	struct v4l2_streamparm parm = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE };
	parm.parm.output.timeperframe.numerator = 1;
	parm.parm.output.timeperframe.denominator = FPS;
	xioctl(enc, VIDIOC_S_PARM, &parm);

	/* Set once, before streaming: changed on a running encoder they
	 * killed its firmware (2026-11-19). */
	ctrl(V4L2_CID_MPEG_VIDEO_BITRATE_MODE, V4L2_MPEG_VIDEO_BITRATE_MODE_CBR, "bitrate mode");
	ctrl(V4L2_CID_MPEG_VIDEO_BITRATE, BITRATE, "bitrate");
	ctrl(V4L2_CID_MPEG_VIDEO_GOP_SIZE, GOP_S * FPS, "gop");
	ctrl(V4L2_CID_MPEG_VIDEO_H264_I_PERIOD, GOP_S * FPS, "i period");
	ctrl(V4L2_CID_MPEG_VIDEO_H264_PROFILE,
	     V4L2_MPEG_VIDEO_H264_PROFILE_CONSTRAINED_BASELINE, "profile");
	ctrl(V4L2_CID_MPEG_VIDEO_H264_LEVEL, V4L2_MPEG_VIDEO_H264_LEVEL_4_0, "level");
	/* Venus does not repeat SPS and PPS before later keyframes
	 * (PREPEND_SPSPPS_TO_IDR: EINVAL): the reader keeps the first ones. */
	ctrl(V4L2_CID_MPEG_VIDEO_B_FRAMES, 0, "no B frames");

	struct v4l2_requestbuffers rb = { .count = OUTS,
		.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE, .memory = V4L2_MEMORY_MMAP };
	if (xioctl(enc, VIDIOC_REQBUFS, &rb) < 0 || rb.count < OUTS)
		die("REQBUFS output");
	for (int i = 0; i < OUTS; i++) {
		struct v4l2_exportbuffer e = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE,
			.index = i, .plane = 0, .flags = O_RDWR | O_CLOEXEC };
		if (xioctl(enc, VIDIOC_EXPBUF, &e) < 0)
			die("EXPBUF");
		outs[i].fd = e.fd;
		/* Y as an 8-bit image, UV as a 16-bit (two 8-bit channels)
		 * image of half the size, both in the one buffer. */
		EGLImageKHR iy = import(e.fd, DRM_FORMAT_R8, W, H, stride, 0, DRM_FORMAT_MOD_LINEAR);
		EGLImageKHR iuv = import(e.fd, DRM_FORMAT_GR88, W / 2, H / 2, stride,
					 uv_offset, DRM_FORMAT_MOD_LINEAR);
		if (iy == EGL_NO_IMAGE_KHR || iuv == EGL_NO_IMAGE_KHR)
			fail("Venus's buffer as a GL image");
		GLuint ty = texture(iy), tuv = texture(iuv);
		glGenFramebuffers(1, &outs[i].fb_y);
		glBindFramebuffer(GL_FRAMEBUFFER, outs[i].fb_y);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, ty, 0);
		if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
			fail("Y plane is not renderable");
		glGenFramebuffers(1, &outs[i].fb_uv);
		glBindFramebuffer(GL_FRAMEBUFFER, outs[i].fb_uv);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tuv, 0);
		if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
			fail("UV plane is not renderable");
	}

	rb = (struct v4l2_requestbuffers){ .count = CAPTURES,
		.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE, .memory = V4L2_MEMORY_MMAP };
	if (xioctl(enc, VIDIOC_REQBUFS, &rb) < 0)
		die("REQBUFS capture");
	for (unsigned i = 0; i < rb.count && i < CAPTURES; i++) {
		struct v4l2_plane pl = { 0 };
		struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE,
			.memory = V4L2_MEMORY_MMAP, .index = i, .m.planes = &pl, .length = 1 };
		if (xioctl(enc, VIDIOC_QUERYBUF, &b) < 0)
			die("QUERYBUF");
		caps_len[i] = pl.length;
		caps_map[i] = mmap(NULL, pl.length, PROT_READ, MAP_SHARED, enc, pl.m.mem_offset);
		if (caps_map[i] == MAP_FAILED)
			die("mmap");
		if (xioctl(enc, VIDIOC_QBUF, &b) < 0)
			die("QBUF capture");
	}
	int t = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	if (xioctl(enc, VIDIOC_STREAMON, &t) < 0)
		die("STREAMON output");
	t = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	if (xioctl(enc, VIDIOC_STREAMON, &t) < 0)
		die("STREAMON capture");
}

/* ---- the screen copies ---- */
static void request_copy(void);

static void shot_setup(struct shot *s)
{
	s->bo = gbm_bo_create(gbm, shot_w, shot_h, shot_format,
			      GBM_BO_USE_RENDERING | GBM_BO_USE_LINEAR);
	if (!s->bo)
		fail("gbm_bo_create");
	int fd = gbm_bo_get_fd(s->bo);
	uint32_t pitch = gbm_bo_get_stride(s->bo);
	struct zwp_linux_buffer_params_v1 *p = zwp_linux_dmabuf_v1_create_params(dmabuf);
	zwp_linux_buffer_params_v1_add(p, fd, 0, 0, pitch, DRM_FORMAT_MOD_LINEAR >> 32,
				       DRM_FORMAT_MOD_LINEAR & 0xffffffff);
	s->buffer = zwp_linux_buffer_params_v1_create_immed(p, shot_w, shot_h, shot_format, 0);
	zwp_linux_buffer_params_v1_destroy(p);
	s->image = import(fd, shot_format, shot_w, shot_h, pitch, 0, DRM_FORMAT_MOD_LINEAR);
	if (s->image == EGL_NO_IMAGE_KHR)
		fail("the screen copy as a GL image");
	s->tex = texture(s->image);
	close(fd);
}

static void f_buffer(void *d, struct zwlr_screencopy_frame_v1 *f, uint32_t fmt,
		     uint32_t w, uint32_t h, uint32_t stride_)
{ (void)d; (void)f; (void)fmt; (void)w; (void)h; (void)stride_; }
static void f_flags(void *d, struct zwlr_screencopy_frame_v1 *f, uint32_t flags)
{
	(void)d; (void)f;
	frame_shot->y_invert = flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT;
}
static void f_ready(void *d, struct zwlr_screencopy_frame_v1 *f, uint32_t sec_hi,
		    uint32_t sec_lo, uint32_t nsec)
{
	(void)d;
	struct shot *s = frame_shot;
	s->mono_us = (((uint64_t)sec_hi << 32 | sec_lo) * 1000000) + nsec / 1000;
	s->busy = false;
	s->ready = true;
	zwlr_screencopy_frame_v1_destroy(f);
	frame = NULL;
}
static void f_failed(void *d, struct zwlr_screencopy_frame_v1 *f)
{
	(void)d;
	frame_shot->busy = false;
	zwlr_screencopy_frame_v1_destroy(f);
	frame = NULL;
}
static void f_damage(void *d, struct zwlr_screencopy_frame_v1 *f, uint32_t x,
		     uint32_t y, uint32_t w, uint32_t h)
{ (void)d; (void)f; (void)x; (void)y; (void)w; (void)h; }
static void f_linux_dmabuf(void *d, struct zwlr_screencopy_frame_v1 *f,
			   uint32_t fmt, uint32_t w, uint32_t h)
{
	(void)d; (void)f;
	shot_format = fmt;
	shot_w = w;
	shot_h = h;
	shot_dmabuf_ok = true;
}
static void f_buffer_done(void *d, struct zwlr_screencopy_frame_v1 *f)
{
	(void)d;
	if (!shot_dmabuf_ok)
		fail("Sway offers no DMA-BUF copy");
	if (!shots[0].bo)
		for (int i = 0; i < CAPS; i++)
			shot_setup(&shots[i]);
	/* On damage: Sway answers at its next frame that changed. */
	zwlr_screencopy_frame_v1_copy_with_damage(f, frame_shot->buffer);
	shot_buffer_done = true;
}
static const struct zwlr_screencopy_frame_v1_listener frame_listener = {
	f_buffer, f_flags, f_ready, f_failed, f_damage, f_linux_dmabuf, f_buffer_done,
};

static uint64_t last_copy_us;

static void request_copy(void)
{
	if (frame || hold)
		return;
	/* A free shot: not being copied into, not waiting to be encoded.
	 * The oldest waiting one is given up: the newest frame wins. */
	struct shot *s = NULL;
	for (int i = 0; i < CAPS; i++)
		if (!shots[i].busy && !shots[i].ready) { s = &shots[i]; break; }
	if (!s && shots[0].bo) {
		for (int i = 0; i < CAPS; i++)
			if (!shots[i].busy && (!s || shots[i].mono_us < s->mono_us))
				s = &shots[i];
		if (s)
			s->ready = false;
	}
	if (!s)
		s = &shots[0];
	frame_shot = s;
	s->busy = true;
	frame = zwlr_screencopy_manager_v1_capture_output(copier, 0, output);
	zwlr_screencopy_frame_v1_add_listener(frame, &frame_listener, NULL);
	last_copy_us = now_us(CLOCK_MONOTONIC);
}

/* ---- converting and encoding ---- */
static int free_out(void)
{
	for (int i = 0; i < OUTS; i++)
		if (!outs[i].queued)
			return i;
	return -1;
}

static void draw(GLuint prog, GLint uturn, GLint uflip, struct shot *s, int turn)
{
	glUseProgram(prog);
	glUniform1i(uturn, turn / 90);
	glUniform1f(uflip, s->y_invert ? 1.0f : 0.0f);
	glBindTexture(GL_TEXTURE_2D, s->tex);
	glBindBuffer(GL_ARRAY_BUFFER, vbo);
	glEnableVertexAttribArray(0);
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

static int64_t mono_to_real_us;

static void encode_ready(void)
{
	struct shot *s = NULL;
	for (int i = 0; i < CAPS; i++)
		if (shots[i].ready && (!s || shots[i].mono_us > s->mono_us))
			s = &shots[i];
	int o = free_out();
	if (!s || o < 0)
		return;
	/* The turn: the output's (its buffer is copied before it), unless
	 * given.  wl_output's 90 is a turn of the content counterclockwise. */
	int turn = TURN >= 0 ? TURN : (output_transform & 3) * 90;
	glBindFramebuffer(GL_FRAMEBUFFER, outs[o].fb_y);
	glViewport(0, 0, W, H);
	draw(prog_y, uni_turn_y, uni_flip_y, s, turn);
	glBindFramebuffer(GL_FRAMEBUFFER, outs[o].fb_uv);
	glViewport(0, 0, W / 2, H / 2);
	glUseProgram(prog_uv);
	glUniform2f(uni_px_uv, 1.0f / W, 1.0f / H);
	draw(prog_uv, uni_turn_uv, uni_flip_uv, s, turn);
	/* V4L2 does not wait for the GPU: finished before Venus reads. */
	glFinish();
	s->ready = false;

	struct v4l2_plane pl = { .bytesused = uv_offset + stride * (H / 2) };
	struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE,
		.memory = V4L2_MEMORY_MMAP, .index = o, .m.planes = &pl, .length = 1 };
	uint64_t real = s->mono_us + mono_to_real_us;
	b.timestamp.tv_sec = real / 1000000;
	b.timestamp.tv_usec = real % 1000000;
	if (xioctl(enc, VIDIOC_QBUF, &b) < 0)
		die("QBUF output");
	outs[o].queued = true;
}

static void reclaim(void)
{
	for (;;) {
		struct v4l2_plane pl = { 0 };
		struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE,
			.memory = V4L2_MEMORY_MMAP, .m.planes = &pl, .length = 1 };
		if (xioctl(enc, VIDIOC_DQBUF, &b) < 0)
			return;
		outs[b.index].queued = false;
	}
}

static void write_all(const void *p, size_t n)
{
	const char *c = p;
	while (n) {
		ssize_t w = write(1, c, n);
		if (w < 0) {
			if (errno == EINTR)
				continue;
			exit(0);    /* the reader went */
		}
		c += w;
		n -= w;
	}
}

static void collect(void)
{
	for (;;) {
		struct v4l2_plane pl = { 0 };
		struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE,
			.memory = V4L2_MEMORY_MMAP, .m.planes = &pl, .length = 1 };
		if (xioctl(enc, VIDIOC_DQBUF, &b) < 0)
			return;
		uint32_t len = pl.bytesused - pl.data_offset;
		uint8_t key = (b.flags & V4L2_BUF_FLAG_KEYFRAME) ? 1 : 0;
		uint64_t cap = (uint64_t)b.timestamp.tv_sec * 1000000 + b.timestamp.tv_usec;
		uint64_t out = now_us(CLOCK_REALTIME);
		uint8_t head[25];
		memcpy(head, "PXSC", 4);
		memcpy(head + 4, &len, 4);
		head[8] = key;
		memcpy(head + 9, &cap, 8);
		memcpy(head + 17, &out, 8);
		write_all(head, sizeof head);
		write_all((char *)caps_map[b.index] + pl.data_offset, len);
		if (xioctl(enc, VIDIOC_QBUF, &b) < 0)
			die("QBUF capture again");
		if (FRAMES && ++sent >= FRAMES)
			exit(0);
	}
}

static void command(void)
{
	char c[16];
	ssize_t n = read(0, c, sizeof c);
	if (n <= 0) {
		/* The server went; in a test (-n), stdin may simply be empty. */
		if (!FRAMES)
			exit(0);
		stdin_open = false;
		return;
	}
	for (ssize_t i = 0; i < n; i++) {
		if (c[i] == 'k')
			ctrl(V4L2_CID_MPEG_VIDEO_FORCE_KEY_FRAME, 1, "keyframe");
		else if (c[i] == 'h')
			hold = true;
		else if (c[i] == 'g') {
			hold = false;
			request_copy();
		} else if (c[i] == 'q')
			exit(0);
	}
}

int main(int argc, char **argv)
{
	int opt;
	while ((opt = getopt(argc, argv, "o:s:r:b:g:t:n:")) != -1) {
		switch (opt) {
		case 'o': want_output = optarg; break;
		case 's': if (sscanf(optarg, "%dx%d", &W, &H) != 2) fail("-s WxH"); break;
		case 'r': FPS = atoi(optarg); break;
		case 'b': BITRATE = atoi(optarg); break;
		case 'g': GOP_S = atoi(optarg); break;
		case 't': TURN = atoi(optarg); break;
		case 'n': FRAMES = atol(optarg); break;
		default: fail("usage: pro1x-screencast [-o OUTPUT] [-s WxH] [-r FPS] "
			      "[-b BITRATE] [-g GOP_S] [-t TURN] [-n FRAMES]");
		}
	}
	/* Gone with the server that started it, however it ends. */
	prctl(PR_SET_PDEATHSIG, SIGTERM);
	if (getppid() == 1)
		return 0;
	W &= ~15;
	H &= ~15;
	mono_to_real_us = (int64_t)now_us(CLOCK_REALTIME) - (int64_t)now_us(CLOCK_MONOTONIC);

	display = wl_display_connect(NULL);
	if (!display)
		fail("no Wayland display");
	struct wl_registry *reg = wl_display_get_registry(display);
	wl_registry_add_listener(reg, &registry_listener, NULL);
	wl_display_roundtrip(display);
	wl_display_roundtrip(display);
	if (!copier || !dmabuf)
		fail("Sway lacks wlr-screencopy or linux-dmabuf");
	if (!output)
		fail("no such output");

	gl_setup();
	venus_setup();
	request_copy();

	uint64_t frame_us = 1000000 / FPS;
	for (;;) {
		struct pollfd p[3] = {
			{ wl_display_get_fd(display), POLLIN, 0 },
			{ enc, POLLIN | POLLOUT, 0 },
			{ stdin_open ? 0 : -1, POLLIN, 0 },
		};
		wl_display_flush(display);
		/* At most FPS copies a second: the next one is asked a frame's
		 * time after the last. */
		int wait = -1;
		if (!frame && !hold) {
			uint64_t due = last_copy_us + frame_us, t = now_us(CLOCK_MONOTONIC);
			wait = due > t ? (int)((due - t) / 1000) : 0;
		}
		if (poll(p, 3, wait) < 0 && errno != EINTR)
			die("poll");
		if (p[0].revents & POLLIN) {
			if (wl_display_dispatch(display) < 0)
				fail("Wayland connection lost");
		}
		if (p[1].revents & (POLLIN | POLLOUT)) {
			reclaim();
			collect();
		}
		if (p[2].revents & (POLLIN | POLLHUP))
			command();
		encode_ready();
		if (!frame && !hold && now_us(CLOCK_MONOTONIC) >= last_copy_us + frame_us)
			request_copy();
	}
}

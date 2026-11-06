// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * mafp-client: send one command to the Pro1X fingerprint trusted app (mafp)
 * through the QSEECOM TEE driver (kernel patch pro1x-qseecom-tee), and print
 * the reply.  A test tool for mapping the protocol (../README.md).
 *
 *   mafp-client CMD LEN [SIZE]   e.g. mafp-client 0xef 0xc
 *
 * SIZE: the request and response buffer size (default 0x20000, Android's).
 *
 * The app must be loaded (herd start qsee-app-loader-mafp), which also needs
 * qsee-supplicant.  As Android's library does, the buffer is
 * [u32 command][u32 length][payload], 0x20000 bytes, all zero but for the
 * header: a payload of garbage once reset a machine running another QSEE
 * app (Wróbel's notes), so nothing else is written into it.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <linux/tee.h>

#ifndef TEE_IMPL_ID_QSEECOM
#define TEE_IMPL_ID_QSEECOM 5
#endif

#define APP "mafp"
#define BUF_SIZE 0x20000

struct shm {
	int id;
	uint8_t *va;
	size_t size;
};

static int shm_alloc(int fd, size_t size, struct shm *out)
{
	struct tee_ioctl_shm_alloc_data data = { .size = size };
	int shm_fd = ioctl(fd, TEE_IOC_SHM_ALLOC, &data);

	if (shm_fd < 0) {
		perror("TEE_IOC_SHM_ALLOC");
		return -1;
	}
	out->va = mmap(NULL, data.size, PROT_READ | PROT_WRITE, MAP_SHARED,
		       shm_fd, 0);
	close(shm_fd);
	if (out->va == MAP_FAILED) {
		perror("mmap");
		return -1;
	}
	out->id = data.id;
	out->size = data.size;
	memset(out->va, 0, data.size);
	return 0;
}

/* The client device of the QSEECOM TEE driver: which /dev/teeN it gets
 * depends on what registered first, so ask each for its implementation. */
static int open_device(void)
{
	char path[32];
	int i;

	for (i = 0; i < 16; i++) {
		struct tee_ioctl_version_data v = { 0 };
		int fd;

		snprintf(path, sizeof(path), "/dev/tee%d", i);
		fd = open(path, O_RDWR);
		if (fd < 0)
			continue;
		if (!ioctl(fd, TEE_IOC_VERSION, &v) &&
		    v.impl_id == TEE_IMPL_ID_QSEECOM) {
			printf("device %s\n", path);
			return fd;
		}
		close(fd);
	}
	fprintf(stderr, "no QSEECOM TEE device (is qseecomtee loaded?)\n");
	return -1;
}

/* A session by name: parameter 0 is a buffer holding it, the UUID zero. */
static int open_session(int fd, uint32_t *session)
{
	struct {
		struct tee_ioctl_open_session_arg arg;
		struct tee_ioctl_param params[1];
	} buf = { 0 };
	struct tee_ioctl_buf_data bd = { (uintptr_t)&buf, sizeof(buf) };
	struct shm name;

	if (shm_alloc(fd, 64, &name))
		return -1;
	strcpy((char *)name.va, APP);
	buf.arg.num_params = 1;
	buf.params[0].attr = TEE_IOCTL_PARAM_ATTR_TYPE_MEMREF_INPUT;
	buf.params[0].a = 0;
	buf.params[0].b = sizeof(APP);
	buf.params[0].c = name.id;
	if (ioctl(fd, TEE_IOC_OPEN_SESSION, &bd)) {
		perror("TEE_IOC_OPEN_SESSION");
		return -1;
	}
	printf("session %u, ret 0x%x, origin %u\n", buf.arg.session,
	       buf.arg.ret, buf.arg.ret_origin);
	*session = buf.arg.session;
	return buf.arg.ret ? -1 : 0;
}

static void dump(const uint8_t *p, size_t n)
{
	size_t i;

	for (i = 0; i < n; i++)
		printf("%s%02x%s", i % 16 ? "" : "  ", p[i],
		       i % 16 == 15 || i == n - 1 ? "\n" : " ");
}

int main(int argc, char **argv)
{
	struct {
		struct tee_ioctl_invoke_arg arg;
		struct tee_ioctl_param params[2];
	} buf = { 0 };
	struct tee_ioctl_buf_data bd = { (uintptr_t)&buf, sizeof(buf) };
	struct shm req, rsp;
	uint32_t cmd, len, session;
	size_t shown, size = BUF_SIZE;
	int fd;

	if (argc != 3 && argc != 4) {
		fprintf(stderr, "usage: %s CMD LEN [SIZE]\n", argv[0]);
		return 2;
	}
	cmd = strtoul(argv[1], NULL, 0);
	len = strtoul(argv[2], NULL, 0);
	if (argc == 4)
		size = strtoul(argv[3], NULL, 0);
	if (size < 8 || size > BUF_SIZE || len > size - 8) {
		fprintf(stderr, "need 8 <= SIZE <= 0x%x and LEN <= SIZE - 8\n",
			BUF_SIZE);
		return 2;
	}

	fd = open_device();
	if (fd < 0 || open_session(fd, &session))
		return 1;
	if (shm_alloc(fd, BUF_SIZE, &req) || shm_alloc(fd, BUF_SIZE, &rsp))
		return 1;
	memcpy(req.va, &cmd, 4);
	memcpy(req.va + 4, &len, 4);

	buf.arg.session = session;
	buf.arg.num_params = 2;
	buf.params[0].attr = TEE_IOCTL_PARAM_ATTR_TYPE_MEMREF_INPUT;
	buf.params[0].b = size;
	buf.params[0].c = req.id;
	buf.params[1].attr = TEE_IOCTL_PARAM_ATTR_TYPE_MEMREF_OUTPUT;
	buf.params[1].b = size;
	buf.params[1].c = rsp.id;
	if (ioctl(fd, TEE_IOC_INVOKE, &bd)) {
		perror("TEE_IOC_INVOKE");
		return 1;
	}
	printf("cmd 0x%x len 0x%x size 0x%zx: ret 0x%x, origin %u\n", cmd, len,
	       size, buf.arg.ret, buf.arg.ret_origin);
	shown = len + 8 < 0x100 ? len + 8 : 0x100;
	if (shown > size)
		shown = size;
	printf("reply (first 0x%zx bytes):\n", shown);
	dump(rsp.va, shown);
	return buf.arg.ret ? 1 : 0;
}

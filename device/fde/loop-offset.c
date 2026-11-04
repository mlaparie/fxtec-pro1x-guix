/*
 * pro1x-loop-offset: attach LOOP to DEVICE from byte OFFSET.
 *
 *   pro1x-loop-offset LOOP DEVICE OFFSET
 *
 * For the initrd of an encrypted system (services/fde.scm), where the LUKS2 container
 * starts OFFSET bytes into the userdata partition. It has no losetup, and its static
 * Guile has no ioctl. Static, so that it brings nothing else into the initrd.
 */
#include <fcntl.h>
#include <linux/loop.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	struct loop_info64 info;
	int loop, device;

	if (argc != 4) {
		fprintf(stderr, "usage: pro1x-loop-offset LOOP DEVICE OFFSET\n");
		return 2;
	}
	loop = open(argv[1], O_RDWR);
	if (loop < 0) {
		perror(argv[1]);
		return 1;
	}
	device = open(argv[2], O_RDWR);
	if (device < 0) {
		perror(argv[2]);
		return 1;
	}
	if (ioctl(loop, LOOP_SET_FD, device) < 0) {
		perror("LOOP_SET_FD");
		return 1;
	}
	memset(&info, 0, sizeof(info));
	info.lo_offset = strtoull(argv[3], NULL, 10);
	if (ioctl(loop, LOOP_SET_STATUS64, &info) < 0) {
		perror("LOOP_SET_STATUS64");
		ioctl(loop, LOOP_CLR_FD, 0);
		return 1;
	}
	return 0;
}

/*
 * pro1x-dm-offset: map DEVICE from byte OFFSET to the end as /dev/mapper/NAME.
 *
 *   pro1x-dm-offset NAME DEVICE OFFSET
 *
 * For the initrd of an encrypted system (services/fde.scm), where the LUKS2 container
 * starts OFFSET bytes into the userdata partition. It has no dmsetup, and its static
 * Guile has no ioctl. Static, so that it brings nothing else into the initrd.
 *
 * A device-mapper linear target, not a loop device: the loop driver's workqueue is
 * freezable, and stays frozen while the hibernation image is written, so writing it
 * to swap inside the container never ends. A linear target remaps each request in
 * place, without a thread of its own, and keeps no second page cache.
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/dm-ioctl.h>
#include <linux/fs.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

static void init(struct dm_ioctl *io, size_t size, const char *name)
{
	memset(io, 0, size);
	io->version[0] = DM_VERSION_MAJOR;
	io->version[1] = 0;
	io->version[2] = 0;
	io->data_size = size;
	io->data_start = sizeof(*io);
	strncpy(io->name, name, sizeof(io->name) - 1);
}

int main(int argc, char **argv)
{
	union {
		struct dm_ioctl io;
		char bytes[16384];
	} buf;
	struct dm_ioctl *io = &buf.io;
	struct dm_target_spec *spec;
	uint64_t size, offset;
	char path[sizeof(io->name) + 16];
	int control, device;
	dev_t dev;

	if (argc != 4) {
		fprintf(stderr, "usage: pro1x-dm-offset NAME DEVICE OFFSET\n");
		return 2;
	}
	offset = strtoull(argv[3], NULL, 10);
	device = open(argv[2], O_RDONLY);
	if (device < 0 || ioctl(device, BLKGETSIZE64, &size) < 0) {
		perror(argv[2]);
		return 1;
	}
	close(device);
	if (offset % 512 || offset >= size) {
		fprintf(stderr, "pro1x-dm-offset: bad offset %s\n", argv[3]);
		return 2;
	}
	control = open("/dev/mapper/control", O_RDWR);
	if (control < 0) {
		perror("/dev/mapper/control");
		return 1;
	}

	init(io, sizeof(*io), argv[1]);
	if (ioctl(control, DM_DEV_CREATE, io) < 0) {
		perror("DM_DEV_CREATE");
		return 1;
	}
	dev = io->dev;

	/* One linear target over the whole mapping: "DEVICE START-SECTOR". */
	init(io, sizeof(buf), argv[1]);
	io->target_count = 1;
	spec = (struct dm_target_spec *)(buf.bytes + sizeof(*io));
	spec->sector_start = 0;
	spec->length = (size - offset) / 512;
	strcpy(spec->target_type, "linear");
	snprintf((char *)(spec + 1), sizeof(buf) - sizeof(*io) - sizeof(*spec),
		 "%s %llu", argv[2], (unsigned long long)(offset / 512));
	if (ioctl(control, DM_TABLE_LOAD, io) < 0) {
		perror("DM_TABLE_LOAD");
		goto remove;
	}

	/* Without DM_SUSPEND_FLAG, DM_DEV_SUSPEND resumes: the table goes live. */
	init(io, sizeof(*io), argv[1]);
	if (ioctl(control, DM_DEV_SUSPEND, io) < 0) {
		perror("DM_DEV_SUSPEND");
		goto remove;
	}

	/* No udev in the initrd to make the node. */
	snprintf(path, sizeof(path), "/dev/mapper/%s", argv[1]);
	if (mknod(path, S_IFBLK | 0600, makedev(major(dev), minor(dev))) < 0 &&
	    errno != EEXIST) {
		perror(path);
		return 1;
	}
	return 0;

remove:
	init(io, sizeof(*io), argv[1]);
	ioctl(control, DM_DEV_REMOVE, io);
	return 1;
}

/* pro1x-nsbind SRC PID TARGET — bind SRC (a path in this mount namespace)
 * onto TARGET (a path in the mount namespace of process PID): the tree is
 * cloned here (open_tree), then attached there after setns (move_mount).
 * For pro1x-waydroid-share: the phone's folders reach Waydroid's Android
 * without a mount under ~/.local/share/waydroid on the phone's side, so
 * deleting Waydroid's data cannot reach them.
 *
 * Copyright 2026 fxtec-pro1x-guix contributors; GPL-3.0-or-later. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/mount.h>

int main(int argc, char **argv)
{
	if (argc != 4) {
		fprintf(stderr, "usage: pro1x-nsbind SRC PID TARGET\n");
		return 2;
	}
	int tree = syscall(SYS_open_tree, AT_FDCWD, argv[1],
			   OPEN_TREE_CLONE | OPEN_TREE_CLOEXEC | AT_RECURSIVE);
	if (tree < 0) { perror("open_tree"); return 1; }
	char ns[64];
	snprintf(ns, sizeof ns, "/proc/%s/ns/mnt", argv[2]);
	int nsfd = open(ns, O_RDONLY | O_CLOEXEC);
	if (nsfd < 0 || setns(nsfd, CLONE_NEWNS) < 0) { perror(ns); return 1; }
	if (syscall(SYS_move_mount, tree, "", AT_FDCWD, argv[3],
		    MOVE_MOUNT_F_EMPTY_PATH) < 0) { perror("move_mount"); return 1; }
	return 0;
}

// SPDX-License-Identifier: GPL-2.0-only
/*
 * pro1x-qsee-probe: a test module for the Pro1X fingerprint reader's
 * trusted app (QSEE "mafp", see ../README.md).
 *
 * Mainline's qcom_scm finds QSEECOM on this TrustZone but does not create
 * its device on unlisted machines, and it cannot load apps.  This module
 * finds out, step by step, whether the stock TA can run under mainline:
 *
 *   lookup=   app names to look up (exported qcom_scm API, read-only);
 *   image=    a file holding mafp.mdt followed by mafp.b00..bNN: load it
 *             (raw QSEE OS "app start" SMC, as the vendor qseecom driver);
 *   mdt_len=  the size of the .mdt part of image;
 *   lib=, lib_mdt_len=  the same for a common library to load first
 *             (cmnlib for a 32-bit app, which mafp is: the vendor driver loads
 *             it before the first 32-bit app; the bootloader only loads
 *             cmnlib64).  Left loaded, as the vendor driver does;
 *   cmd=      once loaded, send this one command (0 = none) with an empty
 *             payload of cmd_len bytes, and dump the reply;
 *   app_id=   send cmd to this already loaded app (e.g. mafp loaded by
 *             qsee-app-loader) instead of loading image.  The physical
 *             addresses of the request and reply are printed: mafp is a
 *             32-bit app, and the vendor driver refuses its buffers above
 *             4 GiB.
 *
 *   peek=     a kernel address (from /proc/kallsyms) whose byte is printed:
 *             e.g. qcom_tzmem_using_shm_bridge, whether mainline enabled
 *             TrustZone's SHM bridge.  A memory read, no TrustZone call.
 *
 * The app is shut down again when the module is removed.  Nothing is
 * written to any partition.  Load-time only: every parameter is 0444.
 *
 * SMC IDs and request layouts follow the GPL vendor driver
 * (drivers/misc/qseecom.c, include/soc/qcom/qseecomi.h of
 * LineageOS android_kernel_fxtec_sm6115).
 */

#include <linux/arm-smccc.h>
#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/firmware/qcom/qcom_scm.h>
#include <linux/firmware/qcom/qcom_tzmem.h>
#include <linux/kernel_read_file.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/vmalloc.h>

static char *lookup = "mafp,keymaster64,keymaster,qcom.tz.uefisecapp,uefisecapp,widevine,gpqese";
module_param(lookup, charp, 0444);
MODULE_PARM_DESC(lookup, "Comma-separated QSEE app names to look up");

static char *image;
module_param(image, charp, 0444);
MODULE_PARM_DESC(image, "mdt + segments of the app to load (empty: no load)");

static uint mdt_len;
module_param(mdt_len, uint, 0444);
MODULE_PARM_DESC(mdt_len, "Size of the .mdt part of image");

static char *lib;
module_param(lib, charp, 0444);
MODULE_PARM_DESC(lib, "mdt + segments of a common library to load first (empty: none)");

static uint lib_mdt_len;
module_param(lib_mdt_len, uint, 0444);
MODULE_PARM_DESC(lib_mdt_len, "Size of the .mdt part of lib");

static unsigned long peek;
module_param(peek, ulong, 0444);
MODULE_PARM_DESC(peek, "Kernel address whose byte to print (0: none)");

static char *app_name = "mafp";
module_param(app_name, charp, 0444);
MODULE_PARM_DESC(app_name, "Name of the app in image");

static uint cmd;
module_param(cmd, uint, 0444);
MODULE_PARM_DESC(cmd, "TA command to send once loaded (0: none)");

static uint app_id;
module_param(app_id, uint, 0444);
MODULE_PARM_DESC(app_id, "Loaded app to send cmd to, instead of loading image (0: none)");

static uint cmd_len = 8;
module_param(cmd_len, uint, 0444);
MODULE_PARM_DESC(cmd_len, "Payload length for cmd");

/* QSEE OS calls (owner 50, app manager service 1). */
#define QSEE_OWNER_QSEE_OS	50
#define QSEE_SVC_APP_MGR	1
#define QSEE_CMD_APP_START	1
#define QSEE_CMD_APP_SHUTDOWN	2
#define QSEE_CMD_LOAD_SERV_IMAGE	7

#define QSEE_RESULT_SUCCESS	0
#define QSEE_RESULT_INCOMPLETE	1
#define QSEE_RESULT_BLOCKED	2

#define SCM_INTERRUPTED		1
#define SCM_V2_EBUSY		-12

/* TZ maps an app image itself and wants it 4 MiB aligned (the vendor's TA
 * heap is reserved so; Dawid Wróbel's mainline QSEECOM TEE driver,
 * drivers/tee/qseecom/core.c, QSEECOM_TEE_IMAGE_ALIGN).  The pool only
 * promises page alignment: an image at 0xfe200000 got status -2 here. */
#define QSEE_IMAGE_ALIGN	SZ_4M

/* The client library's shared buffer: [u32 cmd][u32 len][payload]. */
#define TA_BUF_SIZE		0x20000

static struct qcom_tzmem_pool *pool;
static struct clk *ce_clk;
static u32 loaded_app_id;

/* One QSEE OS call with value arguments, as qcom_scm-smc.c does it. */
static int qsee_os_call(u32 svc, u32 cmdid, u32 nargs, const u64 *args,
			struct arm_smccc_res *res)
{
	struct arm_smccc_quirk quirk = { .id = ARM_SMCCC_QUIRK_QCOM_A6 };
	unsigned long a0, a[4] = { 0 };
	int retry = 0;
	u32 i;

	for (i = 0; i < nargs && i < 4; i++)
		a[i] = args[i];

	do {
		a0 = ARM_SMCCC_CALL_VAL(ARM_SMCCC_STD_CALL, ARM_SMCCC_SMC_64,
					QSEE_OWNER_QSEE_OS,
					((svc & 0xff) << 8) | (cmdid & 0xff));
		quirk.state.a6 = 0;
		do {
			/* arginfo: nargs values (type 0 = VAL) */
			arm_smccc_smc_quirk(a0, nargs, a[0], a[1], a[2], a[3],
					    quirk.state.a6, 0, res, &quirk);
			if (res->a0 == SCM_INTERRUPTED)
				a0 = res->a0;
		} while (res->a0 == SCM_INTERRUPTED);

		if ((long)res->a0 != SCM_V2_EBUSY)
			break;
		msleep(30);
	} while (retry++ < 20);

	return (long)res->a0 ? -EIO : 0;
}

static void do_lookups(void)
{
	char *names, *p, *name;
	u32 id;
	int ret;

	names = kstrdup(lookup, GFP_KERNEL);
	if (!names)
		return;
	p = names;
	while ((name = strsep(&p, ",")) != NULL) {
		if (!*name)
			continue;
		ret = qcom_scm_qseecom_app_get_id(name, &id);
		if (ret)
			pr_info("lookup %s: not loaded (%d)\n", name, ret);
		else
			pr_info("lookup %s: app id %u\n", name, id);
	}
	kfree(names);
}

static int ce_clock_on(void)
{
	struct device_node *np;
	struct platform_device *pdev;

	/* The crypto BAM's clock is the RPM's CE1 clock the vendor driver
	 * voted for (QSEECOM_CE1_CLK). */
	np = of_find_compatible_node(NULL, NULL, "qcom,bam-v1.7.4");
	if (!np)
		return -ENODEV;
	pdev = of_find_device_by_node(np);
	of_node_put(np);
	if (!pdev)
		return -ENODEV;
	ce_clk = clk_get(&pdev->dev, "bam_clk");
	put_device(&pdev->dev);
	if (IS_ERR(ce_clk)) {
		int ret = PTR_ERR(ce_clk);

		ce_clk = NULL;
		return ret;
	}
	return clk_prepare_enable(ce_clk);
}

static void ce_clock_off(void)
{
	if (ce_clk) {
		clk_disable_unprepare(ce_clk);
		clk_put(ce_clk);
		ce_clk = NULL;
	}
}

/* Hand an image (.mdt then its segments, in one file) to the QSEE OS:
 * app start (cmd 1) or common library load (cmd 7), same arguments. */
static int tz_load(const char *path, u32 mdt, u32 cmdid, const char *what,
		   struct arm_smccc_res *res)
{
	void *file = NULL, *buf, *img;
	phys_addr_t buf_pa, img_pa;
	size_t fsize = 0, stage;
	ssize_t n;
	u64 args[3];
	int ret;

	n = kernel_read_file_from_path(path, 0, &file, SZ_4M, &fsize,
				       READING_FIRMWARE);
	if (n < 0) {
		pr_err("reading %s: %zd\n", path, n);
		return n;
	}
	if (!mdt || mdt >= fsize) {
		pr_err("mdt length %u does not fit %s size %zu\n", mdt, path, fsize);
		vfree(file);
		return -EINVAL;
	}

	/* A copy at the first 4 MiB boundary inside a larger buffer: the
	 * buffer is physically contiguous, so one offset serves both. */
	stage = PAGE_ALIGN(fsize) + QSEE_IMAGE_ALIGN;
	buf = qcom_tzmem_alloc(pool, stage, GFP_KERNEL);
	if (!buf) {
		vfree(file);
		return -ENOMEM;
	}
	buf_pa = qcom_tzmem_to_phys(buf);
	img_pa = ALIGN(buf_pa, QSEE_IMAGE_ALIGN);
	img = buf + (img_pa - buf_pa);
	memcpy(img, file, fsize);
	vfree(file);

	ret = ce_clock_on();
	if (ret)
		pr_warn("CE clock not enabled (%d), loading anyway\n", ret);

	/* As the vendor driver for QSEE >= 4.0: mdt_len, img_len, address. */
	args[0] = mdt;
	args[1] = fsize;
	args[2] = img_pa;
	pr_info("loading %s: mdt %u, image %zu bytes at %pa\n", what, mdt,
		fsize, &args[2]);
	ret = qsee_os_call(QSEE_SVC_APP_MGR, cmdid, 3, args, res);
	pr_info("%s: status %ld, result %lu, type 0x%lx, data %lu\n", what,
		(long)res->a0, res->a1, res->a2, res->a3);

	ce_clock_off();
	qcom_tzmem_free(buf);

	if (ret)
		return ret;
	if (res->a1 == QSEE_RESULT_INCOMPLETE || res->a1 == QSEE_RESULT_BLOCKED) {
		pr_err("%s wants a listener during load: not supported here\n", what);
		return -EOPNOTSUPP;
	}
	return res->a1 == QSEE_RESULT_SUCCESS ? 0 : -EIO;
}

static int do_load(void)
{
	struct arm_smccc_res res;
	u32 id;
	int ret;

	if (!qcom_scm_qseecom_app_get_id(app_name, &id)) {
		pr_info("%s is already loaded, app id %u\n", app_name, id);
		return 0;
	}

	if (lib && *lib) {
		ret = tz_load(lib, lib_mdt_len, QSEE_CMD_LOAD_SERV_IMAGE,
			      "common library", &res);
		if (ret)
			return ret;
	}

	ret = tz_load(image, mdt_len, QSEE_CMD_APP_START, app_name, &res);
	if (ret)
		return ret;

	loaded_app_id = res.a3;
	pr_info("%s loaded, app id %u\n", app_name, loaded_app_id);
	return 0;
}

static void do_cmd(u32 app_id)
{
	u32 *req, *rsp;
	int ret;

	if (cmd_len > TA_BUF_SIZE - 8)
		return;
	/* The request, then the reply right after it: they must not overlap
	 * (the same buffer for both got -EINVAL from the SCM call; Wróbel's
	 * driver lays them out this way). */
	req = qcom_tzmem_alloc(pool, 2 * TA_BUF_SIZE, GFP_KERNEL);
	if (!req)
		return;
	memset(req, 0, 2 * TA_BUF_SIZE);
	rsp = req + TA_BUF_SIZE / sizeof(*req);
	req[0] = cmd;
	req[1] = cmd_len;
	pr_info("request at %pa, reply at %pa\n", &(phys_addr_t){ qcom_tzmem_to_phys(req) },
		&(phys_addr_t){ qcom_tzmem_to_phys(rsp) });
	ret = qcom_scm_qseecom_app_send(app_id, req, TA_BUF_SIZE,
					rsp, TA_BUF_SIZE);
	pr_info("cmd 0x%x (len %u): %d\n", cmd, cmd_len, ret);
	if (!ret)
		print_hex_dump(KERN_INFO, "reply: ", DUMP_PREFIX_OFFSET, 16, 1,
			       rsp, min_t(u32, cmd_len + 8, 0x180), true);
	qcom_tzmem_free(req);
}

static int __init qsee_probe_init(void)
{
	struct qcom_tzmem_pool_config config = {
		.policy = QCOM_TZMEM_POLICY_ON_DEMAND,
		.max_size = SZ_16M,
	};
	u32 id;
	int ret;

	if (!qcom_scm_is_available())
		return -EPROBE_DEFER;

	if (peek)
		pr_info("byte at 0x%lx: %u\n", peek, *(const u8 *)peek);

	do_lookups();

	if ((!image || !*image) && !(cmd && app_id))
		return 0;

	pool = qcom_tzmem_pool_new(&config);
	if (IS_ERR(pool)) {
		ret = PTR_ERR(pool);
		pool = NULL;
		return ret;
	}

	if (!image || !*image) {
		do_cmd(app_id);
		return 0;
	}

	ret = do_load();
	if (ret)
		goto out_pool;

	/* An app loaded from Linux is not found by lookup (Wróbel's notes):
	 * use the id the load returned. */
	if (cmd && loaded_app_id)
		do_cmd(loaded_app_id);
	else if (cmd && !qcom_scm_qseecom_app_get_id(app_name, &id))
		do_cmd(id);
	return 0;

out_pool:
	qcom_tzmem_pool_free(pool);
	pool = NULL;
	return ret;
}

static void __exit qsee_probe_exit(void)
{
	struct arm_smccc_res res;
	u64 args[1];

	if (loaded_app_id) {
		args[0] = loaded_app_id;
		qsee_os_call(QSEE_SVC_APP_MGR, QSEE_CMD_APP_SHUTDOWN, 1, args, &res);
		pr_info("app %u shut down: status %ld, result %lu\n",
			loaded_app_id, (long)res.a0, res.a1);
	}
	if (pool)
		qcom_tzmem_pool_free(pool);
}

module_init(qsee_probe_init);
module_exit(qsee_probe_exit);

MODULE_DESCRIPTION("Pro1X: probe the fingerprint trusted app under mainline QSEECOM");
MODULE_LICENSE("GPL");

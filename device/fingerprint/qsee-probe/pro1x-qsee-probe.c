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
 *             4 GiB;
 *   whitelist= send cmd as the vendor driver does when TrustZone has the
 *             whitelist feature: TZ_APP_QSAPP_SEND_DATA_WITH_WHITELIST_ID
 *             (command 6), with an empty sglist table.  The feature's
 *             version is printed before the send;
 *   uefi=     instead of a fingerprint command, send QueryVariableInfo to
 *             qcom.tz.uefisecapp (loaded by the bootloader), laid out as
 *             mainline's qcom_qseecom_uefisecapp does: a read-only query,
 *             whether this TrustZone takes app commands from mainline's
 *             memory at all.  With whitelist=, command 6;
 *   gcc_clks= GCC clock ids (dt-bindings/clock/qcom,gcc-sm6115.h) to keep
 *             on while the module is loaded, e.g. 91,90,102 for the QUP
 *             wrapper 0 core clocks and SE5, the SPI engine TrustZone
 *             drives for the sensor: no Linux driver claims them, so mainline
 *             turns them off at boot.
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
#include <linux/clk-provider.h>
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

static bool whitelist;
module_param(whitelist, bool, 0444);
MODULE_PARM_DESC(whitelist, "Send cmd with the whitelist variant (command 6)");

static bool uefi;
module_param(uefi, bool, 0444);
MODULE_PARM_DESC(uefi, "Send QueryVariableInfo to qcom.tz.uefisecapp");

static uint cmd_len = 8;

static uint gcc_clks[8];
static int n_gcc_clks;
module_param_array(gcc_clks, uint, &n_gcc_clks, 0444);
MODULE_PARM_DESC(gcc_clks, "GCC clock ids to keep enabled while loaded");
static struct clk *held_clks[8];

static uint uefi_size = PAGE_SIZE;
module_param(uefi_size, uint, 0444);
MODULE_PARM_DESC(uefi_size, "Size of the block for uefi= (more than a page comes from elsewhere)");

static uint buf_size = 0x20000;
module_param(buf_size, uint, 0444);
MODULE_PARM_DESC(buf_size, "Request and reply size for cmd (the library's: 0x20000)");
module_param(cmd_len, uint, 0444);
MODULE_PARM_DESC(cmd_len, "Payload length for cmd");

/* QSEE OS calls (owner 50, app manager service 1). */
#define QSEE_OWNER_SIP		2
#define QSEE_OWNER_TZ_APPS	48
#define QSEE_OWNER_QSEE_OS	50
#define QSEE_SVC_APP_ID_PLACEHOLDER	0
#define QSEE_SVC_INFO		6
#define QSEE_CMD_GET_FEAT_VERSION	3
#define QSEE_CMD_SEND_DATA_WHITELIST	6
#define QSEE_FEATURE_WHITELIST	15
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

/* The vendor driver's sglist table: 4 entries of struct sglist_info
 * {u32 indexAndFlags; u32 sizeOrCount;}, all zero for a plain command. */
#define SGLISTINFO_TABLE_SIZE	32

/* Argument types in arginfo, as qcom_scm.h's QCOM_SCM_ARGS(). */
#define ARG_VAL			0
#define ARG_RW			2
#define ARGINFO(n, types)	(((types) << 4) | ((n) & 0xf))
#define T(i, t)			((t) << (2 * (i)))

static struct qcom_tzmem_pool *pool;
static struct clk *ce_clk;
static u32 loaded_app_id;

/* One SCM call, as qcom_scm-smc.c does it: four arguments in registers;
 * with more, the fourth register holds the address of the fourth and later
 * ones (ext, TZ memory of at least 7 u64). */
static int scm_call(u32 owner, u32 svc, u32 cmdid, u32 arginfo, u32 nargs,
		    const u64 *args, __le64 *ext, struct arm_smccc_res *res)
{
	struct arm_smccc_quirk quirk = { .id = ARM_SMCCC_QUIRK_QCOM_A6 };
	unsigned long a0, a[4] = { 0 };
	int retry = 0;
	u32 i;

	for (i = 0; i < nargs && i < 4; i++)
		a[i] = args[i];
	if (nargs > 4) {
		if (!ext || nargs > 10)
			return -EINVAL;
		for (i = 3; i < nargs; i++)
			ext[i - 3] = cpu_to_le64(args[i]);
		a[3] = qcom_tzmem_to_phys(ext);
	}

	do {
		a0 = ARM_SMCCC_CALL_VAL(ARM_SMCCC_STD_CALL, ARM_SMCCC_SMC_64,
					owner, ((svc & 0xff) << 8) | (cmdid & 0xff));
		quirk.state.a6 = 0;
		do {
			arm_smccc_smc_quirk(a0, arginfo, a[0], a[1], a[2], a[3],
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

/* One QSEE OS call with value arguments. */
static int qsee_os_call(u32 svc, u32 cmdid, u32 nargs, const u64 *args,
			struct arm_smccc_res *res)
{
	return scm_call(QSEE_OWNER_QSEE_OS, svc, cmdid, ARGINFO(nargs, 0),
			nargs, args, NULL, res);
}

/* The vendor driver's qseecom_check_whitelist_feature(): its version, or
 * negative when TrustZone does not answer. */
static long whitelist_version(void)
{
	struct arm_smccc_res res;
	u64 arg = QSEE_FEATURE_WHITELIST;
	int ret;

	ret = scm_call(QSEE_OWNER_SIP, QSEE_SVC_INFO, QSEE_CMD_GET_FEAT_VERSION,
		       ARGINFO(1, 0), 1, &arg, NULL, &res);
	pr_info("whitelist feature: status %ld, version 0x%lx\n",
		(long)res.a0, res.a1);
	return ret ? ret : res.a1;
}

/* TZ_APP_QSAPP_SEND_DATA_WITH_WHITELIST_ID: app id, request, its size,
 * reply, its size, sglist table, its size.  The table, the extra
 * arguments and the buffers all lie in buf (TZ memory). */
static int send_whitelist(u32 app_id, void *req, size_t req_size, void *rsp,
			  size_t rsp_size, void *table, __le64 *ext,
			  struct arm_smccc_res *res)
{
	u64 args[7] = {
		app_id,
		qcom_tzmem_to_phys(req), req_size,
		qcom_tzmem_to_phys(rsp), rsp_size,
		qcom_tzmem_to_phys(table), SGLISTINFO_TABLE_SIZE,
	};
	u32 types = T(0, ARG_VAL) | T(1, ARG_RW) | T(2, ARG_VAL) |
		    T(3, ARG_RW) | T(4, ARG_VAL) | T(5, ARG_RW) | T(6, ARG_VAL);

	return scm_call(QSEE_OWNER_TZ_APPS, QSEE_SVC_APP_ID_PLACEHOLDER,
			QSEE_CMD_SEND_DATA_WHITELIST, ARGINFO(7, types), 7,
			args, ext, res);
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

	if (buf_size < 16 || buf_size > TA_BUF_SIZE || cmd_len > buf_size - 8)
		return;
	/* The request, then the reply right after it: they must not overlap
	 * (the same buffer for both got -EINVAL from the SCM call; Wróbel's
	 * driver lays them out this way).  Then a page for the sglist table
	 * and the extra arguments of command 6. */
	req = qcom_tzmem_alloc(pool, PAGE_ALIGN(2 * buf_size) + PAGE_SIZE, GFP_KERNEL);
	if (!req)
		return;
	memset(req, 0, PAGE_ALIGN(2 * buf_size) + PAGE_SIZE);
	rsp = req + ALIGN(buf_size, 8) / sizeof(*req);
	req[0] = cmd;
	req[1] = cmd_len;
	pr_info("request at %pa, reply at %pa\n", &(phys_addr_t){ qcom_tzmem_to_phys(req) },
		&(phys_addr_t){ qcom_tzmem_to_phys(rsp) });
	if (whitelist) {
		void *table = (u8 *)req + PAGE_ALIGN(2 * buf_size);
		__le64 *ext = table + 64;
		struct arm_smccc_res res;

		if (whitelist_version() <= 0) {
			pr_info("no whitelist feature: not sending command 6\n");
			qcom_tzmem_free(req);
			return;
		}
		ret = send_whitelist(app_id, req, buf_size, rsp, buf_size,
				     table, ext, &res);
		pr_info("cmd 0x%x (len %u), command 6: status %ld, result %lu, type 0x%lx, data 0x%lx\n",
			cmd, cmd_len, (long)res.a0, res.a1, res.a2, res.a3);
		if (!ret && res.a1 != QSEE_RESULT_SUCCESS)
			ret = -EIO;
	} else {
		ret = qcom_scm_qseecom_app_send(app_id, req, buf_size,
						rsp, buf_size);
	}
	pr_info("cmd 0x%x (len %u): %d\n", cmd, cmd_len, ret);
	if (!ret)
		print_hex_dump(KERN_INFO, "reply: ", DUMP_PREFIX_OFFSET, 16, 1,
			       rsp, min_t(u32, cmd_len + 8, 0x180), true);
	qcom_tzmem_free(req);
}

/* mainline's qsee_req/rsp_uefi_query_variable_info */
struct uefi_query_req {
	u32 command_id;
	u32 length;
	u32 attributes;
} __packed;

struct uefi_query_rsp {
	u32 command_id;
	u32 length;
	u32 status;
	u32 pad;
	u64 storage_space;
	u64 remaining_space;
	u64 max_variable_size;
} __packed;

#define UEFI_CMD_QUERY_VARIABLE_INFO	0x8003
#define UEFI_ATTR_NV_BS_RT		7

static void do_uefi_query(void)
{
	struct uefi_query_req *req;
	struct uefi_query_rsp *rsp;
	struct arm_smccc_res res;
	size_t rsp_offs = ALIGN(sizeof(*req), 8);
	void *buf;
	u32 id;
	int ret;

	ret = qcom_scm_qseecom_app_get_id("qcom.tz.uefisecapp", &id);
	if (ret) {
		pr_info("uefisecapp not found (%d)\n", ret);
		return;
	}
	/* One block for both, as mainline (separate ones crashed laptops);
	 * the sglist table and extra arguments of command 6 after them. */
	if (uefi_size < PAGE_SIZE || uefi_size > SZ_1M)
		return;
	buf = qcom_tzmem_alloc(pool, uefi_size, GFP_KERNEL);
	if (!buf)
		return;
	memset(buf, 0, uefi_size);
	req = buf;
	rsp = buf + rsp_offs;
	req->command_id = UEFI_CMD_QUERY_VARIABLE_INFO;
	req->length = sizeof(*req);
	req->attributes = UEFI_ATTR_NV_BS_RT;
	pr_info("uefisecapp is app %u; request at %pa\n", id,
		&(phys_addr_t){ qcom_tzmem_to_phys(buf) });

	if (whitelist) {
		ret = send_whitelist(id, req, sizeof(*req), rsp, sizeof(*rsp),
				     buf + 2048, buf + 2048 + 64, &res);
		pr_info("uefi query, command 6: status %ld, result %lu, type 0x%lx, data 0x%lx\n",
			(long)res.a0, res.a1, res.a2, res.a3);
	} else {
		ret = qcom_scm_qseecom_app_send(id, req, sizeof(*req), rsp,
						sizeof(*rsp));
	}
	pr_info("uefi query: %d; reply cmd 0x%x len %u status 0x%x, storage %llu, free %llu, max %llu\n",
		ret, rsp->command_id, rsp->length, rsp->status,
		rsp->storage_space, rsp->remaining_space, rsp->max_variable_size);
	qcom_tzmem_free(buf);
}

static void gcc_clocks_on(void)
{
	struct of_phandle_args a = { .args_count = 1 };
	int i, ret;

	a.np = of_find_compatible_node(NULL, NULL, "qcom,gcc-sm6115");
	if (!a.np) {
		pr_err("no GCC node\n");
		return;
	}
	for (i = 0; i < n_gcc_clks; i++) {
		struct clk *c;

		a.args[0] = gcc_clks[i];
		c = of_clk_get_from_provider(&a);
		if (IS_ERR(c)) {
			pr_err("GCC clock %u: %ld\n", gcc_clks[i], PTR_ERR(c));
			continue;
		}
		ret = clk_prepare_enable(c);
		pr_info("GCC clock %u (%s) on: %d, rate %lu\n", gcc_clks[i],
			__clk_get_name(c), ret, clk_get_rate(c));
		if (ret) {
			clk_put(c);
			continue;
		}
		held_clks[i] = c;
	}
	of_node_put(a.np);
}

static void gcc_clocks_off(void)
{
	int i;

	for (i = n_gcc_clks - 1; i >= 0; i--) {
		if (!held_clks[i])
			continue;
		clk_disable_unprepare(held_clks[i]);
		clk_put(held_clks[i]);
		held_clks[i] = NULL;
	}
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

	gcc_clocks_on();

	do_lookups();

	if ((!image || !*image) && !(cmd && app_id) && !uefi)
		return 0;

	pool = qcom_tzmem_pool_new(&config);
	if (IS_ERR(pool)) {
		ret = PTR_ERR(pool);
		pool = NULL;
		return ret;
	}

	if (uefi) {
		do_uefi_query();
		return 0;
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
	gcc_clocks_off();
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
	gcc_clocks_off();
}

module_init(qsee_probe_init);
module_exit(qsee_probe_exit);

MODULE_DESCRIPTION("Pro1X: probe the fingerprint trusted app under mainline QSEECOM");
MODULE_LICENSE("GPL");

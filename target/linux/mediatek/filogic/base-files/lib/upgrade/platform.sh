REQUIRE_IMAGE_METADATA=1
RAMFS_COPY_BIN='fitblk fit_check_sign'

# Viettel 32x6 Multi Firmware upgrade: the running firmware (fit + rootfs_data)
# is kept as the spare slot (fit_spare + rootfs_data_spare, replacing the old
# spare) and a trial boot is armed. U-Boot counts boots while boot_trial is
# set and swaps the spare back after 3 failed attempts; /etc/init.d/multifw
# confirms the trial once the new system is up. Stored firmwares in slots
# 2/3 are never touched. Set U-Boot env upgrade_backup=0 to upgrade in place.
#
# Runs from platform_pre_upgrade, i.e. in the full running system BEFORE the
# switch to the RAM root. Renaming only touches the UBI volume table; the
# running overlay and fitblk root keep working, and fit_do_upgrade then finds
# no "fit"/"rootfs_data" volume and creates fresh ones.
viettel_32x6_backup_on() {
	[ "$(fw_printenv -n upgrade_backup 2>/dev/null)" != "0" ]
}

viettel_32x6_vol_bytes() {	# <ubidev> <volname> -> data bytes or 0
	local n; n="$(nand_find_volume "$1" "$2")"
	[ -n "$n" ] && cat "/sys/class/ubi/$n/data_bytes" || echo 0
}

# refuse an upgrade that cannot keep a spare copy, before anything is touched
viettel_32x6_check_space() {
	local img="$1" ubidev leb need avail datamax
	viettel_32x6_backup_on || return 0
	ubidev="$(nand_find_ubi ubi)" || return 0
	[ -n "$(nand_find_volume $ubidev fit)" ] || return 0
	leb=$(cat /sys/class/ubi/$ubidev/eraseblock_size)
	datamax=$(( $(fw_printenv -n rootfs_data_max 2>/dev/null || echo 0x600000) ))
	# new image + new settings volume, rounded up to whole LEBs
	need=$(( ( ($(wc -c < "$img") + leb - 1) / leb + (datamax + leb - 1) / leb ) * leb ))
	# free space + what deleting the current spare gives back
	avail=$(( $(cat /sys/class/ubi/$ubidev/avail_eraseblocks) * leb + \
		$(viettel_32x6_vol_bytes $ubidev fit_spare) + $(viettel_32x6_vol_bytes $ubidev rootfs_data_spare) ))
	[ "$need" -le "$avail" ] && return 0
	echo "Multi Firmware: not enough space to keep the current firmware as spare"
	echo "  need $((need / 1048576)) MiB, available $((avail / 1048576)) MiB."
	echo "  Free a slot (multifw delete 2), shrink settings (multifw reset 2),"
	echo "  or upgrade without a spare copy: multifw backup off"
	return 1
}

viettel_32x6_keep_spare()
{
	local ubidev id f=/tmp/multifw.upgrade.env

	viettel_32x6_backup_on || return 0
	ubidev="$(nand_find_ubi ubi)" || return 0
	[ -n "$ubidev" ] && [ -n "$(nand_find_volume $ubidev fit)" ] || return 0

	sync
	: > "$f"
	id="$(nand_find_volume $ubidev fit_spare)"
	[ -n "$id" ] && { echo "fwname_${id##*_}" >> "$f"; ubirmvol /dev/$ubidev -N fit_spare; }
	[ -n "$(nand_find_volume $ubidev rootfs_data_spare)" ] && ubirmvol /dev/$ubidev -N rootfs_data_spare

	if [ -n "$(nand_find_volume $ubidev rootfs_data)" ]; then
		ubirename /dev/$ubidev fit fit_spare rootfs_data rootfs_data_spare || return 1
	else
		ubirename /dev/$ubidev fit fit_spare || return 1
	fi

	# write the env through a file: never pipe $(fw_printenv) into fw_setenv,
	# both take fw_printenv.lock and the upgrade deadlocks
	printf 'boot_trial 1\nboot_count 0\n' >> "$f"
	fw_setenv -s "$f" && echo "Multi Firmware: running firmware kept as spare, trial boot armed"
	local rc=$?
	rm -f "$f"
	return $rc
}

asus_initial_setup()
{
	# initialize UBI if it's running on initramfs
	[ "$(rootfs_type)" = "tmpfs" ] || return 0

	ubirmvol /dev/ubi0 -N rootfs
	ubirmvol /dev/ubi0 -N rootfs_data
	ubirmvol /dev/ubi0 -N jffs2
	ubimkvol /dev/ubi0 -N jffs2 -s 0x3e000
}

buffalo_initial_setup()
{
	local mtdnum="$( find_mtd_index ubi )"
	if [ ! "$mtdnum" ]; then
		echo "unable to find mtd partition ubi"
		return 1
	fi

	ubidetach -m "$mtdnum"
	ubiformat /dev/mtd$mtdnum -y
}

jiorouter_initial_setup()
{
	[ "$(rootfs_type)" = "tmpfs" ] || return 0

	local mtdnum="$( find_mtd_index ubi )"
	if [ ! "$mtdnum" ]; then
		echo "unable to find mtd partition ubi"
		return 1
	fi

	ubidetach -m "$mtdnum" 2>/dev/null
	ubiformat /dev/mtd$mtdnum -y || exit 1
	ubiattach -m "$mtdnum" || exit 1

	local ubidev="$(nand_find_ubi ubi)"
	[ -n "$ubidev" ] || { echo "cannot attach ubi"; exit 1; }

	if ! ubimkvol /dev/$ubidev -n 0 -N u-boot-env -s 0x80000; then
		echo "failed to create u-boot-env volume - aborting"
		exit 1
	fi

	local envdev="$(nand_find_volume "$ubidev" u-boot-env)"
	[ -n "$envdev" ] || { echo "cannot find u-boot-env volume - aborting"; exit 1; }
	echo "/dev/$envdev 0x0 0x80000 0x1f000 5" > /etc/fw_env.config

	# Set boot arguments in freshly created U-Boot environment
	fw_setenv bootcmd 'ubi read 46000000 kernel;fdt addr $(fdtcontroladdr);fdt rm /signature;bootm 0x46000000'
	fw_setenv bootdelay 0
	fw_setenv ipaddr ''
}

xiaomi_initial_setup()
{
	# initialize UBI and setup uboot-env if it's running on initramfs
	[ "$(rootfs_type)" = "tmpfs" ] || return 0

	local mtdnum="$( find_mtd_index ubi )"
	if [ ! "$mtdnum" ]; then
		echo "unable to find mtd partition ubi"
		return 1
	fi

	local kern_mtdnum="$( find_mtd_index ubi_kernel )"
	if [ ! "$kern_mtdnum" ]; then
		echo "unable to find mtd partition ubi_kernel"
		return 1
	fi

	ubidetach -m "$mtdnum"
	ubiformat /dev/mtd$mtdnum -y

	ubidetach -m "$kern_mtdnum"
	ubiformat /dev/mtd$kern_mtdnum -y

	if ! fw_printenv -n flag_try_sys2_failed &>/dev/null; then
		echo "failed to access u-boot-env. skip env setup."
		return 0
	fi

	fw_setenv -s - <<-EOF
		boot_wait on
		uart_en 1
		flag_boot_rootfs 0
		flag_last_success 1
		flag_boot_success 1
		flag_try_sys1_failed 8
		flag_try_sys2_failed 8
	EOF

	local board=$(board_name)
	case "$board" in
	xiaomi,mi-router-ax3000t|\
	xiaomi,mi-router-wr30u-stock)
		fw_setenv mtdparts "nmbm0:1024k(bl2),256k(Nvram),256k(Bdata),2048k(factory),2048k(fip),256k(crash),256k(crash_log),34816k(ubi),34816k(ubi1),32768k(overlay),12288k(data),256k(KF)"
		;;
	xiaomi,redmi-router-ax6000-stock)
		fw_setenv mtdparts "nmbm0:1024k(bl2),256k(Nvram),256k(Bdata),2048k(factory),2048k(fip),256k(crash),256k(crash_log),30720k(ubi),30720k(ubi1),51200k(overlay)"
		;;
	esac
}

platform_do_upgrade() {
	local board=$(board_name)

	case "$board" in
	abt,asr3000|\
	acer,predator-w6x-ubootmod|\
	asus,zenwifi-bt8-ubootmod|\
	bananapi,bpi-r3|\
	bananapi,bpi-r3-mini|\
	bananapi,bpi-r4|\
	bananapi,bpi-r4-2g5|\
	bananapi,bpi-r4-poe|\
	bananapi,bpi-r4-lite|\
	bazis,ax3000wm|\
	cmcc,a10-ubootmod|\
	cmcc,rax3000m|\
	comfast,cf-wr632ax-ubootmod|\
	creatlentem,clt-r30b1-ubi|\
	cudy,m3000-v1-ubootmod|\
	cudy,m3000-v2-yt8821-ubootmod|\
	cudy,tr3000-v1-ubootmod|\
	cudy,wbr3000uax-v1-ubootmod|\
	cudy,wr3000e-v1-ubootmod|\
	cudy,wr3000s-v1-ubootmod|\
	cudy,wr3000h-v1-ubootmod|\
	cudy,wr3000p-v1-ubootmod|\
	gatonetworks,gdsp|\
	globitel,bt-r320|\
	h3c,magic-nx30-pro|\
	imou,hx21|\
	jcg,q30-pro|\
	jdcloud,re-cp-03|\
	konka,komi-a31|\
	mediatek,mt7981-rfb|\
	mediatek,mt7988a-rfb|\
	mercusys,mr90x-v1-ubi|\
	netis,eap930-v1|\
	netis,n6-v2|\
	netis,nx30v2|\
	netis,nx31|\
	netis,nx32u|\
	nokia,ea0326gmp|\
	openwrt,one|\
	netcore,n60|\
	netcore,n60-pro|\
	qihoo,360t7|\
	qihoo,360t7-ubi|\
	routerich,ax3000-ubootmod|\
	routerich,be7200|\
	snr,snr-cpe-ax2|\
	teralink,tl3020-256mb|\
	tplink,tl-xdr4288|\
	tplink,tl-xdr6086|\
	tplink,tl-xdr6088|\
	tplink,tl-xtr8488|\
	wavlink,wl-wnt100x3-ubootmod|\
	xiaomi,mi-router-ax3000t-ubootmod|\
	xiaomi,redmi-router-ax6000-ubootmod|\
	xiaomi,mi-router-wr30u-ubootmod|\
	zyxel,ex5601-t0-ubootmod|\
	zyxel,wx5600-t0-ubootmod)
		fit_do_upgrade "$1"
		;;
	viettel,32x6)
		fit_do_upgrade "$1"
		;;
	acer,predator-w6|\
	acer,predator-w6d|\
	acer,vero-w6m|\
	airpi,ap3000m|\
	arcadyan,mozart|\
	glinet,gl-mt2500|\
	glinet,gl-mt2500-airoha|\
	glinet,gl-mt6000|\
	glinet,gl-x3000|\
	glinet,gl-xe3000|\
	hiveton,h5000m|\
	huasifei,wh3000|\
	huasifei,wh3000-pro-emmc|\
	smartrg,sdg-8612|\
	smartrg,sdg-8614|\
	smartrg,sdg-8622|\
	smartrg,sdg-8632|\
	smartrg,sdg-8733|\
	smartrg,sdg-8733a|\
	smartrg,sdg-8734)
		CI_KERNPART="kernel"
		CI_ROOTPART="rootfs"
		emmc_do_upgrade "$1"
		;;
	airtel,aap4221zy)
		# ZyXEL zloader requires a "zyfwinfo" UBI volume with valid
		# metadata (magic + checksum) to select the boot partition.
		# Without it, zloader refuses to boot the firmware. It has to be
		# written before nand_do_upgrade(), which sizes rootfs_data to
		# fill the remaining space.
		local ubidev="$(nand_attach_ubi "${CI_UBIPART:-ubi}")"
		[ "$ubidev" ] || nand_do_upgrade_failed
		local vol="$(nand_find_volume "$ubidev" zyfwinfo)"
		if [ ! "$vol" ]; then
			# rootfs_data may occupy all LEBs, nand_do_upgrade() recreates it
			[ "$(nand_find_volume "$ubidev" rootfs_data)" ] && \
				ubirmvol /dev/$ubidev -N rootfs_data
			if ! ubimkvol /dev/$ubidev -N zyfwinfo -s 256 -t dynamic; then
				echo "cannot create zyfwinfo volume"
				nand_do_upgrade_failed
			fi
			vol="$(nand_find_volume "$ubidev" zyfwinfo)"
		fi
		local tmpfile="/tmp/zyfwinfo.bin"
		echo -n -e '\x45\x58\x59\x5A\x02\x00\xB3\x15\x00\x01\x00\x00' > "$tmpfile"
		dd if=/dev/zero bs=1 count=242 >> "$tmpfile" 2>/dev/null
		echo -n -e '\x1B\x02' >> "$tmpfile"
		ubiupdatevol /dev/$vol -s 256 "$tmpfile"
		rm -f "$tmpfile"
		nand_do_upgrade "$1"
		;;
	asus,rt-ax52|\
	asus,rt-ax57m|\
	asus,rt-ax59u|\
	asus,tuf-ax4200|\
	asus,tuf-ax4200q|\
	asus,tuf-ax6000|\
	asus,zenwifi-bt8)
		CI_UBIPART="UBI_DEV"
		CI_KERNPART="linux"
		nand_do_upgrade "$1"
		;;
	buffalo,wsr-6000ax8|\
	cudy,wr3000h-v1|\
	cudy,wr3000p-v1|\
	huasifei,wh3000-pro-nand|\
	huasifei,wh3000r-nand|\
	jiorouter,ax6000-jidu6101|\
	jiorouter,ax6000-jidu6j01)
		CI_UBIPART="ubi"
		nand_do_upgrade "$1"
		;;
	cudy,re3000-v1|\
	cudy,wr3000-v1|\
	kebidumei,ax3000-u22|\
	totolink,x6000r|\
	wavlink,wl-wn573hx3|\
	widelantech,wap430x|\
	yuncore,ax835)
		default_do_upgrade "$1"
		;;
	dlink,aquila-pro-ai-e30-a1|\
	dlink,aquila-pro-ai-m30-a1|\
	dlink,aquila-pro-ai-m60-a1)
		fw_setenv sw_tryactive 0
		nand_do_upgrade "$1"
		;;
	elecom,wrc-x3000gs3)
		local bootnum="$(mstc_rw_bootnum)"
		case "$bootnum" in
		1|2)
			CI_UBIPART="ubi$bootnum"
			[ -z "$(find_mtd_index $CI_UBIPART)" ] &&
				CI_UBIPART="ubi"
			;;
		*)
			v "invalid bootnum found ($bootnum), rebooting..."
			nand_do_upgrade_failed
			;;
		esac
		nand_do_upgrade "$1"
		;;
	mercusys,mr80x-v3|\
	mercusys,mr85x|\
	mercusys,mr90x-v1|\
	tplink,archer-ax80-v1|\
	tplink,archer-ax80-v1-eu|\
	tplink,be450|\
	tplink,re6000xd)
		CI_UBIPART="ubi0"
		nand_do_upgrade "$1"
		;;
	netgear,eax17)
		echo "UPGRADING SECOND SLOT"
		CI_KERNPART="kernel2"
		CI_ROOTPART="rootfs2"
		nand_do_flash_file "$1" || nand_do_upgrade_failed
		echo "UPGRADING PRIMARY SLOT"
		CI_KERNPART="kernel"
		CI_ROOTPART="rootfs"
		nand_do_flash_file "$1" || nand_do_upgrade_failed
		nand_do_upgrade_success
		;;
	tplink,fr365-v1)
		CI_UBIPART="ubi"
		CI_KERNPART="kernel"
		CI_ROOTPART="rootfs"
		nand_do_upgrade "$1"
		;;
	teltonika,rutc50)
		CI_UBIPART="$(cmdline_get_var ubi.mtd)"
		nand_do_upgrade "$1"
		;;
	nradio,c8-668gl)
		CI_DATAPART="rootfs_data"
		CI_KERNPART="kernel_2nd"
		CI_ROOTPART="rootfs_2nd"
		emmc_do_upgrade "$1"
		;;
	ubnt,unifi-6-plus)
		CI_KERNPART="kernel0"
		EMMC_ROOT_DEV="$(cmdline_get_var root)"
		emmc_do_upgrade "$1"
		;;
	unielec,u7981-01*)
		local rootdev="$(cmdline_get_var root)"
		rootdev="${rootdev##*/}"
		rootdev="${rootdev%p[0-9]*}"
		case "$rootdev" in
		mmc*)
			CI_ROOTDEV="$rootdev"
			CI_KERNPART="kernel"
			CI_ROOTPART="rootfs"
			emmc_do_upgrade "$1"
			;;
		*)
			CI_KERNPART="fit"
			nand_do_upgrade "$1"
			;;
		esac
		;;
	xiaomi,mi-router-ax3000t|\
	xiaomi,mi-router-wr30u-stock|\
	xiaomi,redmi-router-ax6000-stock)
		CI_KERN_UBIPART=ubi_kernel
		CI_ROOT_UBIPART=ubi
		CI_DATA_UBIPART=ubi
		nand_do_upgrade "$1"
		;;
	*)
		nand_do_upgrade "$1"
		;;
	esac
}

PART_NAME=firmware

platform_check_image() {
	local board=$(board_name)

	[ "$#" -gt 1 ] && return 1

	case "$board" in
	viettel,32x6)
		fit_check_image "$1" || return $?
		viettel_32x6_check_space "$1"
		return $?
		;;
	abt,asr3000|\
	acer,predator-w6x-ubootmod|\
	asus,zenwifi-bt8-ubootmod|\
	bananapi,bpi-r3|\
	bananapi,bpi-r3-mini|\
	bananapi,bpi-r4|\
	bananapi,bpi-r4-2g5|\
	bananapi,bpi-r4-poe|\
	bananapi,bpi-r4-lite|\
	bazis,ax3000wm|\
	cmcc,a10-ubootmod|\
	cmcc,rax3000m|\
	comfast,cf-wr632ax-ubootmod|\
	creatlentem,clt-r30b1-ubi|\
	cudy,m3000-v1-ubootmod|\
	cudy,m3000-v2-yt8821-ubootmod|\
	cudy,tr3000-v1-ubootmod|\
	cudy,wbr3000uax-v1-ubootmod|\
	cudy,wr3000e-v1-ubootmod|\
	cudy,wr3000s-v1-ubootmod|\
	cudy,wr3000h-v1-ubootmod|\
	cudy,wr3000p-v1-ubootmod|\
	gatonetworks,gdsp|\
	globitel,bt-r320|\
	h3c,magic-nx30-pro|\
	jcg,q30-pro|\
	jdcloud,re-cp-03|\
	konka,komi-a31|\
	mediatek,mt7981-rfb|\
	mediatek,mt7988a-rfb|\
	mercusys,mr90x-v1-ubi|\
	nokia,ea0326gmp|\
	netis,eap930-v1|\
	netis,n6-v2|\
	netis,nx32u|\
	openwrt,one|\
	netcore,n60|\
	qihoo,360t7|\
	qihoo,360t7-ubi|\
	routerich,ax3000-ubootmod|\
	teralink,tl3020-256mb|\
	tplink,tl-xdr4288|\
	tplink,tl-xdr6086|\
	tplink,tl-xdr6088|\
	tplink,tl-xtr8488|\
	wavlink,wl-wnt100x3-ubootmod|\
	xiaomi,mi-router-ax3000t-ubootmod|\
	xiaomi,redmi-router-ax6000-ubootmod|\
	xiaomi,mi-router-wr30u-ubootmod|\
	zyxel,ex5601-t0-ubootmod)
		fit_check_image "$1"
		return $?
		;;
	creatlentem,clt-r30b1|\
	creatlentem,clt-r30b1-112m|\
	hiveton,h5000m|\
	nradio,c8-668gl)
		# tar magic `ustar`
		magic="$(dd if="$1" bs=1 skip=257 count=5 2>/dev/null)"

		[ "$magic" != "ustar" ] && {
			echo "Invalid image type."
			return 1
		}

		return 0
		;;
	*)
		nand_do_platform_check "$board" "$1"
		return $?
		;;
	esac

	return 0
}

platform_copy_config() {
	case "$(board_name)" in
	bananapi,bpi-r3|\
	bananapi,bpi-r3-mini|\
	bananapi,bpi-r4|\
	bananapi,bpi-r4-2g5|\
	bananapi,bpi-r4-poe|\
	bananapi,bpi-r4-lite|\
	cmcc,rax3000m|\
	gatonetworks,gdsp|\
	mediatek,mt7988a-rfb)
		if [ "$CI_METHOD" = "emmc" ]; then
			emmc_copy_config
		fi
		;;
	acer,predator-w6|\
	acer,predator-w6d|\
	acer,vero-w6m|\
	airpi,ap3000m|\
	arcadyan,mozart|\
	glinet,gl-mt2500|\
	glinet,gl-mt2500-airoha|\
	glinet,gl-mt6000|\
	glinet,gl-x3000|\
	glinet,gl-xe3000|\
	globitel,bt-r320|\
	hiveton,h5000m|\
	huasifei,wh3000|\
	huasifei,wh3000-pro-emmc|\
	jdcloud,re-cp-03|\
	nradio,c8-668gl|\
	smartrg,sdg-8612|\
	smartrg,sdg-8614|\
	smartrg,sdg-8622|\
	smartrg,sdg-8632|\
	smartrg,sdg-8733|\
	smartrg,sdg-8733a|\
	smartrg,sdg-8734|\
	ubnt,unifi-6-plus)
		emmc_copy_config
		;;
	esac
}

platform_pre_upgrade() {
	local board=$(board_name)

	case "$board" in
	asus,rt-ax52|\
	asus,rt-ax57m|\
	asus,rt-ax59u|\
	asus,tuf-ax4200|\
	asus,tuf-ax4200q|\
	asus,tuf-ax6000|\
	asus,zenwifi-bt8)
		asus_initial_setup
		;;
	buffalo,wsr-6000ax8)
		buffalo_initial_setup
		;;
	viettel,32x6)
		viettel_32x6_keep_spare || echo "Multi Firmware: could not keep a spare, upgrading in place"
		;;
	jiorouter,ax6000-jidu6101|\
	jiorouter,ax6000-jidu6j01)
		jiorouter_initial_setup
		;;
	xiaomi,mi-router-ax3000t|\
	xiaomi,mi-router-wr30u-stock|\
	xiaomi,redmi-router-ax6000-stock)
		xiaomi_initial_setup
		;;
	esac
}

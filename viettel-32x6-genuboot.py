import re,sys
root=sys.argv[1]
src=open(root+'/package/boot/uboot-mediatek/patches/445-add-netis-nx31.patch',encoding='utf-8').read()
parts=re.split(r'(?m)^--- /dev/null\n\+\+\+ b/(\S+)\n@@ [^\n]*\n',src)
files={}
for i in range(1,len(parts),2):
    files[parts[i]]='\n'.join(l[1:] for l in parts[i+1].rstrip('\n').split('\n'))+'\n'
defc=files['configs/mt7981_netis_nx31_defconfig'].replace('mt7981-netis_nx31','mt7981-viettel_32x6').replace('defenvs/netis_nx31_env','defenvs/viettel_32x6_env')
dts=files['arch/arm/dts/mt7981-netis_nx31.dts']
dts=dts.replace(' * Copyright (c) 2025\n * Author: Mikhail Zhilkin <csharper2005@gmail.com>',' * Viettel vAP-32X6V1, based on netis NX31 by Mikhail Zhilkin <csharper2005@gmail.com>')
dts=dts.replace('model = "netis NX31";','model = "Viettel vAP-32X6V1";').replace('"netis,nx31"','"viettel,32x6"')
a=dts.index('\tkeys {'); b=dts.index('\t};\n};\n')+4
dts=dts[:a]+'''\tkeys {
		compatible = "gpio-keys";

		button-0 {
			label = "mesh";
			linux,code = <BTN_0>;
			gpios = <&pio 0 GPIO_ACTIVE_LOW>;
		};

		button-1 {
			label = "reset";
			linux,code = <KEY_RESTART>;
			gpios = <&pio 1 GPIO_ACTIVE_LOW>;
		};
	};

	leds {
		compatible = "gpio-leds";

		led-0 {
			label = "red:power";
			gpios = <&pio 5 GPIO_ACTIVE_LOW>;
		};

		led-1 {
			label = "blue:status";
			gpios = <&pio 7 GPIO_ACTIVE_LOW>;
		};

		led-2 {
			label = "green:status";
			gpios = <&pio 8 GPIO_ACTIVE_LOW>;
		};
	};
'''+dts[b:]
dts=dts.replace('partition@160000','partition@180000')
# NAND layout with KeeneticOS: UBI shrinks to end at 0x6000000, the last 32 MiB
# is the raw "keenetic" partition; the unused u-boot-env area holds U-Config
def drep(x,y):
    global dts
    assert dts.count(x)==1, x[:50]
    dts=dts.replace(x,y)
drep('label = "u-boot-env (unused)";','label = "U-Config";')
drep('reg = <0x580000 0x7a80000>;','reg = <0x580000 0x5a80000>;')
a=dts.index('\t\t\tpartition@580000 {'); b=dts.index('\t\t\t};\n',a)+5
dts=dts[:b]+'\n\t\t\tpartition@6000000 {\n\t\t\t\tlabel = "keenetic";\n\t\t\t\treg = <0x6000000 0x2000000>;\n\t\t\t};\n'+dts[b:]
env=files['defenvs/netis_nx31_env'].replace('netis_nx31','viettel_32x6')
def rep(x,y):
    global env
    assert x in env, x[:50]
    env=env.replace(x,y)
rep('bootled_status=blue:status','bootled_status=red:power')
rep('ethaddr_factory=mtd read Factory 0x40080000 0x1e0000 0x20000 && env readmem -b ethaddr 0x4009ef20 0x6 ; setenv ethaddr_factory',
    'ethaddr_factory=mtd read Factory 0x40080000 0x0 0x20000 && env readmem -b ethaddr 0x4008002a 0x6 ; setenv ethaddr_factory')
rep('bootcmd=run check_buttons ; if','bootcmd=run check_buttons ; run mfw_fixup ; run mfw_check ; run boot_keenetic ; run check_trial ; if')
rep('check_buttons=if button reset ; then run boot_tftp ; fi','check_buttons=if button reset ; then run boot_tftp ; fi ; if button mesh ; then echo "Multi Firmware: mesh button held, booting OpenWrt" ; led blue:status on ; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 ; do if button mesh ; then sleep 1 ; fi ; done ; led blue:status off ; if env exists mfw_os ; then run kn_savelog ; setenv mfw_os ; saveenv ; saveenv ; fi ; if env exists mfw_home ; then if test "${mfw_home}" != "1" ; then setenv mfw_sn ${mfw_home} ; run mfw_swap ; fi ; fi ; fi')
rep('boot_ubi=run boot_production ; run boot_recovery','boot_ubi=run boot_production ; run trial_rollback ; run boot_recovery')
rep('bootmenu_8=Reboot.=reset\nbootmenu_9=Reset all settings to factory defaults.=run reset_factory ; reset\n',
 'bootmenu_8=Multi Firmware: load slot 2 via TFTP (slot2.itb).=setenv mfw_sn 2 ; run mfw_tftp ; run bootmenu_confirm_return\n'
 'bootmenu_9=Multi Firmware: boot slot 2.=setenv mfw_sn 2 ; run mfw_swap ; run boot_production ; run bootmenu_confirm_return\n'
 'bootmenu_10=Multi Firmware: boot spare (backup of last upgrade).=setenv mfw_sn spare ; run mfw_swap ; run boot_production ; run bootmenu_confirm_return\n'
 'bootmenu_11=Multi Firmware: boot KeeneticOS (mesh button returns to OpenWrt).=setenv mfw_os keenetic ; saveenv ; saveenv ; run boot_keenetic ; run bootmenu_confirm_return\n'
 'bootmenu_12=Reboot.=reset\n'
 'bootmenu_13=Reset all settings to factory defaults.=run reset_factory ; reset\n')
# Multi Firmware: the running firmware is always "fit"+"rootfs_data" (the kernel
# and fstools need those names); stored slots are fit_2, fit_3 and fit_spare
# with matching rootfs_data_<n>. mfw_swap exchanges slot 1 with slot ${mfw_sn}.
# Firmware names live in Linux (env fwname_<UBI volume id>), so U-Boot never
# has to move them. mfw_pend makes an interrupted swap recoverable.
# KeeneticOS: env mfw_os=keenetic boots the raw "keenetic" partition (FIT in
# the first 2 MiB, squashfs after it). RAM survives the warm reset, so when the
# mesh button returns from it, 1 MiB holding its kernel log buffer (__log_buf
# at 0x485f1d40 in this build, see System.map) is saved to UBI volume kn_log.
extra='''mfw_env=6
boot_keenetic=if test "${mfw_os}" = "keenetic" ; then echo "Multi Firmware: booting KeeneticOS" ; led $bootled_status on ; mtd read keenetic $loadaddr 0x0 0x200000 && bootm $loadaddr ; echo "Multi Firmware: KeeneticOS did not start, booting OpenWrt" ; setenv mfw_os ; saveenv ; saveenv ; fi
kn_savelog=ubi part ubi ; if ubi check kn_log ; then else ubi create kn_log 0x100000 dynamic ; fi ; ubi write 0x48580000 kn_log 0x100000
rootfs_data_max=0x600000
trial_max=3
mfw_tftp=tftpboot $loadaddr slot${mfw_sn}.itb && iminfo $loadaddr && run mfw_write
mfw_write=ubi part ubi ; if ubi check fit_${mfw_sn} ; then ubi remove fit_${mfw_sn} ; fi ; if ubi check rootfs_data_${mfw_sn} ; then ubi remove rootfs_data_${mfw_sn} ; fi ; ubi create fit_${mfw_sn} $filesize dynamic && ubi write $loadaddr fit_${mfw_sn} $filesize
mfw_check=if env exists boot_slot ; then setenv mfw_sn ${boot_slot} ; setenv boot_slot ; setenv boot_trial ; setenv boot_count ; saveenv ; saveenv ; run mfw_swap ; fi
mfw_swap=ubi part ubi ; if ubi check fit_${mfw_sn} ; then setenv mfw_pend ${mfw_sn} ; saveenv ; if ubi check fit ; then ubi rename fit fit_tmp ; fi ; ubi rename fit_${mfw_sn} fit ; if ubi check fit_tmp ; then ubi rename fit_tmp fit_${mfw_sn} ; fi ; if ubi check rootfs_data ; then ubi rename rootfs_data rootfs_data_tmp ; fi ; if ubi check rootfs_data_${mfw_sn} ; then ubi rename rootfs_data_${mfw_sn} rootfs_data ; fi ; if ubi check rootfs_data_tmp ; then ubi rename rootfs_data_tmp rootfs_data_${mfw_sn} ; fi ; setenv mfw_pend ; run mfw_track ; saveenv ; saveenv ; else echo "Multi Firmware: slot ${mfw_sn} is empty" ; fi
mfw_track=if test "${mfw_home}" = "1" ; then setenv mfw_home ${mfw_sn} ; else if test "${mfw_home}" = "${mfw_sn}" ; then setenv mfw_home 1 ; fi ; fi
mfw_fixup=if env exists mfw_pend ; then ubi part ubi ; if ubi check fit_tmp ; then if ubi check fit ; then ubi rename fit_tmp fit_${mfw_pend} ; else ubi rename fit_tmp fit ; fi ; fi ; if ubi check rootfs_data_tmp ; then if ubi check rootfs_data ; then ubi rename rootfs_data_tmp rootfs_data_${mfw_pend} ; else ubi rename rootfs_data_tmp rootfs_data ; fi ; fi ; setenv mfw_pend ; saveenv ; fi
check_trial=if env exists boot_trial ; then if env exists boot_count ; then setexpr boot_count $boot_count + 1 ; else setenv boot_count 1 ; fi ; saveenv ; saveenv ; if test $boot_count -gt $trial_max ; then echo "Multi Firmware: upgrade failed $trial_max boots, rolling back to the spare slot" ; run trial_rollback ; fi ; fi
trial_rollback=if env exists boot_trial ; then setenv boot_trial ; setenv boot_count ; setenv rolled_back 1 ; saveenv ; saveenv ; setenv mfw_sn spare ; run mfw_swap ; if test "${mfw_home}" = "spare" ; then setenv mfw_home 1 ; saveenv ; fi ; run boot_production ; fi
'''
rep('part_default=production\n',extra+'part_default=production\n')
out=''
for name,txt in [('configs/mt7981_viettel_32x6_defconfig',defc),('arch/arm/dts/mt7981-viettel_32x6.dts',dts),('defenvs/viettel_32x6_env',env)]:
    lines=txt.rstrip('\n').split('\n')
    out+='--- /dev/null\n+++ b/%s\n@@ -0,0 +1,%d @@\n'%(name,len(lines))+''.join('+'+l+'\n' for l in lines)
open(root+'/package/boot/uboot-mediatek/patches/476-add-viettel-32x6.patch','w',encoding='utf-8',newline='\n').write(out)
print('ok',len(out))

envfile = root + '/package/utils/multi-firmware/files/uboot-env.txt'
import os
os.makedirs(os.path.dirname(envfile), exist_ok=True)
skip = ('ipaddr', 'serverip', 'ethaddr', 'bootdelay', 'bootmenu_delay', 'bootmenu_title',
        'bootmenu_0', 'bootmenu_0d', '_firstboot', '_init_env', '_switch_to_menu',
        '_bootmenu_update_title', 'rootfs_data_max')
with open(envfile, 'w', encoding='utf-8', newline='\n') as f:
    f.write('# Generated by viettel-32x6-genuboot.py from defenvs/viettel_32x6_env.\n'
            '# multifw writes these keys into the saved U-Boot env when mfw_env differs.\n')
    for line in env.rstrip('\n').split('\n'):
        k, _, v = line.partition('=')
        if k and k not in skip:
            f.write('%s %s\n' % (k, v))
print('env file', envfile)

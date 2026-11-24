# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Advanced wireless options, hardware info and Multi Firmware
LUCI_DESCRIPTION:=One page that gathers advanced mac80211/mt76 radio options \
	(country, tx power, beamforming, coverage presets) and the Multi Firmware \
	slot manager of the Viettel vAP-32X6V1 U-Boot, plus a Hardware row \
	(CPU temperature, NAND type) on the Overview page.
LUCI_DEPENDS:=+luci-base +multi-firmware
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

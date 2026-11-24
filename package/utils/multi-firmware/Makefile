# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=multi-firmware
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/multi-firmware
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Multi Firmware: several firmwares + upgrade rollback (Viettel 32x6 U-Boot)
  DEPENDS:=+uboot-envtools +ubi-utils
  PKGARCH:=all
endef

define Package/multi-firmware/description
  Manages the Multi Firmware layout of the Viettel vAP-32X6V1 U-Boot: the
  running firmware (slot 1), two stored firmwares (slots 2, 3), a spare
  slot that keeps the previous version on upgrade, and the recovery image.
  Provides "multifw" and an init script that confirms a trial boot.
endef

define Build/Compile
endef

define Package/multi-firmware/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/usr/share/multifw
	$(INSTALL_BIN) ./files/multifw $(1)/usr/sbin/multifw
	$(INSTALL_BIN) ./files/multifw.init $(1)/etc/init.d/multifw
	$(INSTALL_DATA) ./files/uboot-env.txt $(1)/usr/share/multifw/uboot-env.txt
endef

$(eval $(call BuildPackage,multi-firmware))

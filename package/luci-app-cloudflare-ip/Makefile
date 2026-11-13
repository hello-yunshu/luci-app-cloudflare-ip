include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-cloudflare-ip
PKG_VERSION:=2.6.0
PKG_RELEASE:=14

PKG_MAINTAINER:=yunshu
PKG_LICENSE:=GPL-3.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-cloudflare-ip
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Cloudflare IP - Safe endpoint orchestration for PassWall/OpenClash on OpenWrt
  # uhttpd is only used by the optional LAN Result Publisher. Do not install a
  # second web server on nginx/lighttpd systems; the publisher fails closed and
  # reports a missing runtime when it is enabled without uhttpd.
  DEPENDS:=+luci-base +bash +flock +curl +tar +jq +ca-bundle +ca-certificates
  PKGARCH:=all
endef

define Package/luci-app-cloudflare-ip/description
OpenWrt plugin for automatically selecting the fastest Cloudflare IPs
using CloudflareSpeedTest, and updating PassWall or OpenClash proxy
configurations. Includes Native, Adaptive Measurement, Operational Health,
and the optional Candidate Rill consumer integration. The Rill Runtime
binary remains an independently packaged optional dependency.
endef

define Package/luci-app-cloudflare-ip/conffiles
/etc/config/cf_ip
/etc/cf_ip
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./root ./htdocs $(PKG_BUILD_DIR)/
endef

define Build/Compile
	mkdir -p $(PKG_BUILD_DIR)/lmo; \
	for po_dir in $(CURDIR)/po/*/; do \
		[ -d "$$$$po_dir" ] || continue; \
		lang=$$$$(basename "$$$$po_dir"); \
		[ "$$$$lang" = "templates" ] && continue; \
		[ -f "$$$$po_dir/cloudflare-ip.po" ] || continue; \
		lmo_lang="$$$$lang"; \
		[ "$$$$lmo_lang" = "zh_Hans" ] && lmo_lang="zh-cn"; \
		if [ -x "$(STAGING_DIR_HOSTPKG)/bin/po2lmo" ]; then \
			"$(STAGING_DIR_HOSTPKG)/bin/po2lmo" "$$$$po_dir/cloudflare-ip.po" "$(PKG_BUILD_DIR)/lmo/cloudflare-ip.$$$$lmo_lang.lmo" || exit 1; \
		else \
			echo "ERROR: po2lmo not found at $(STAGING_DIR_HOSTPKG)/bin; build luci-base/host first" >&2; \
			exit 1; \
		fi; \
	done; \
	for file in root/usr/bin/cf-ip-auto-v2 root/usr/bin/cf-ip-auto-legacy root/usr/libexec/rpcd/cf_ip htdocs/luci-static/resources/cloudflare-ip/utils.js; do \
		sed -i 's/@PKG_VERSION@/$(PKG_VERSION)/g; s/@PKG_RELEASE@/$(PKG_RELEASE)/g; s/@PKG_FULL_VERSION@/$(PKG_VERSION)-r$(PKG_RELEASE)/g' "$(PKG_BUILD_DIR)/$$$$file" || exit 1; \
	done
endef

define Package/luci-app-cloudflare-ip/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/cf-ip-auto-v2 $(1)/usr/bin/cf-ip-auto
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/cf-ip-auto-legacy $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/root/etc/config/cf_ip $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/etc/init.d/cf_ip $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/libexec/rpcd/cf_ip $(1)/usr/libexec/rpcd/
	$(INSTALL_DIR) $(1)/usr/libexec/cf-ip
	for script in writer-lock.sh common.sh config.sh status.sh source.sh scheduler.sh cfst.sh observe.sh adaptive-measurement.sh context-policy.sh transaction.sh openclash-transform.sh openclash-readback.sh publisher.sh rill-disabled.sh candidate-rill.sh reuse.sh operational-health.sh; do \
		$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/libexec/cf-ip/$$$$script $(1)/usr/libexec/cf-ip/; \
	done
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/libexec/cf-ip/migrate-self-update-url.sh $(1)/usr/libexec/cf-ip/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/libexec/cf-ip/migrate-managed-config.sh $(1)/usr/libexec/cf-ip/
	$(INSTALL_DIR) $(1)/usr/share/cf-ip
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/cf-ip/candidate-rill-feature-schema-v2.json $(1)/usr/share/cf-ip/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/etc/init.d/cf_ip_publisher $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/cloudflare-ip
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/cloudflare-ip/*.js $(1)/www/luci-static/resources/view/cloudflare-ip/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/cloudflare-ip
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/cloudflare-ip/*.js $(PKG_BUILD_DIR)/htdocs/luci-static/resources/cloudflare-ip/*.css $(1)/www/luci-static/resources/cloudflare-ip/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/luci/menu.d/luci-app-cloudflare-ip.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/lib/lua/luci/controller/cloudflare-ip.lua $(1)/usr/lib/lua/luci/controller/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/rpcd/acl.d/luci-app-cloudflare-ip.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/lmo/*.lmo $(1)/usr/lib/lua/luci/i18n/
endef

define Package/luci-app-cloudflare-ip/preinst
#!/bin/sh
[ "$${PKG_UPGRADE:-0}" = 1 ] || exit 0
[ -n "$${IPKG_INSTROOT}" ] && exit 0
[ ! -x /etc/init.d/cf_ip ] || /etc/init.d/cf_ip stop || { echo "cf_ip stop failed; refusing package upgrade" >&2; exit 1; }
[ ! -x /etc/init.d/cf_ip_publisher ] || /etc/init.d/cf_ip_publisher stop || { echo "cf_ip_publisher stop failed; refusing package upgrade" >&2; exit 1; }
exit 0
endef

define Package/luci-app-cloudflare-ip/postinst
#!/bin/sh
# Offline/rootfs installs cannot run the online lifecycle.
[ -n "$${IPKG_INSTROOT}" ] && exit 0
# Each step reports its own failure instead of being swallowed by a trailing
# "exit 0": an upgrade that cannot migrate or enable must not look successful.
if [ -x /usr/libexec/cf-ip/migrate-self-update-url.sh ]; then
	/usr/libexec/cf-ip/migrate-self-update-url.sh || { echo "cf-ip self-update URL migration failed" >&2; exit 1; }
fi
if [ -x /usr/libexec/cf-ip/migrate-managed-config.sh ]; then
	/usr/libexec/cf-ip/migrate-managed-config.sh || { echo "cf-ip managed config migration failed" >&2; exit 1; }
fi
if [ -x /etc/init.d/cf_ip ]; then
	/etc/init.d/cf_ip enable || { echo "cf_ip enable failed" >&2; exit 1; }
fi
# Do not rewrite the global LuCI language here: this package only ships its
# own zh-cn catalog and must not change another package's configuration.
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload 2>/dev/null || true
if [ -f /tmp/cf_ip/status.json ] && [ ! -f /etc/cf_ip/status.json ]; then
	mkdir -p /etc/cf_ip || { echo "cf-ip status migration failed: cannot create /etc/cf_ip" >&2; exit 1; }
	mv /tmp/cf_ip/status.json /etc/cf_ip/status.json || { echo "cf-ip status migration failed" >&2; exit 1; }
	if [ -f /tmp/cf_ip/env_cache.json ]; then
		mv /tmp/cf_ip/env_cache.json /etc/cf_ip/env_cache.json || { echo "cf-ip env cache migration failed" >&2; exit 1; }
	fi
fi
exit 0
endef

define Package/luci-app-cloudflare-ip/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { \
	/etc/init.d/cf_ip stop || { echo "cf_ip stop failed; refusing package removal" >&2; exit 1; }; \
	/etc/init.d/cf_ip_publisher stop || { echo "cf_ip_publisher stop failed; refusing package removal" >&2; exit 1; }; \
	/etc/init.d/cf_ip disable || { echo "cf_ip disable failed; refusing package removal" >&2; exit 1; }; \
	rm -f /tmp/luci-indexcache.*; \
	rm -rf /tmp/luci-modulecache/; \
	exit 0; \
}
endef

$(eval $(call BuildPackage,luci-app-cloudflare-ip))

define Package/luci-app-cloudflare-ip-rill
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Cloudflare IP optional Rill contextual learner integration
  DEPENDS:=+luci-app-cloudflare-ip +rill-runtime-preview
  PKGARCH:=all
endef

define Package/luci-app-cloudflare-ip-rill/description
Deprecated compatibility package.
Rill consumer integration is included in luci-app-cloudflare-ip.
This package only retains dependency compatibility for existing installations.
endef

define Package/luci-app-cloudflare-ip-rill/install
	:
endef

$(eval $(call BuildPackage,luci-app-cloudflare-ip-rill))

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/sdk/include" "$TMP/bin" "$TMP/build"
: >"$TMP/sdk/rules.mk"; : >"$TMP/sdk/include/package.mk"
cp -R "$ROOT/package/luci-app-cloudflare-ip/root" "$TMP/build/"
cp -R "$ROOT/package/luci-app-cloudflare-ip/htdocs" "$TMP/build/"
cat >"$TMP/harness.mk" <<'MAKE'
include $(REPO)/package/luci-app-cloudflare-ip/Makefile
ifeq ($(DUMP),1)
$(info $(Package/luci-app-cloudflare-ip/postinst))
endif
.PHONY: empty
empty:
	@:
define staged_install
stage:
	$(call Package/luci-app-cloudflare-ip/install,$(DEST))
endef
$(eval $(staged_install))
MAKE
# Exercise both make expansion and the resulting staged install recipe. This is
# an isolated packaging recipe check, not an IPK/APK package-manager install.
args=(-s -f "$TMP/harness.mk" "REPO=$ROOT" "TOPDIR=$TMP/sdk" "INCLUDE_DIR=$TMP/sdk/include" "PKG_BUILD_DIR=$TMP/build" "DEST=$TMP/stage" 'INSTALL_DIR=mkdir -p' 'INSTALL_BIN=cp' 'INSTALL_CONF=cp' 'INSTALL_DATA=cp')
make "${args[@]}" stage
make "${args[@]}" DUMP=1 empty >"$TMP/postinst.sh"
sh -n "$TMP/postinst.sh"
rg -q '/usr/libexec/cf-ip/migrate-self-update-url.sh' "$TMP/postinst.sh"
rg -q '\$\{IPKG_INSTROOT\}' "$TMP/postinst.sh"
IPKG_INSTROOT="$TMP/stage" sh "$TMP/postinst.sh" # Offline install must not touch host services/UCI.
cat >"$TMP/bin/uci" <<'UCI'
#!/usr/bin/env bash
[[ "$1" != -q ]] || shift
case "$1" in
get) [[ "$2" == cf_ip.main.self_update_url ]] || exit 1; cat "$MIGRATE_TMP/url" ;;
set) [[ "$2" == cf_ip.main.self_update_url=* ]] || exit 1; printf '%s' "${2#*=}" >"$MIGRATE_TMP/url" ;;
commit) printf 'commit\n' >>"$MIGRATE_TMP/commits" ;;
*) exit 1 ;;
esac
UCI
chmod +x "$TMP/bin/uci"
export MIGRATE_TMP="$TMP" PATH="$TMP/bin:$PATH"
helper="$TMP/stage/usr/libexec/cf-ip/migrate-self-update-url.sh"
old='https://raw.githubusercontent.com/hello-yunshu/use-cloudflare-ip/main/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto'
new='https://raw.githubusercontent.com/hello-yunshu/luci-app-cloudflare-ip/main/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto'
printf '%s' "$old" >"$TMP/url"; : >"$TMP/commits"
printf '0' >"$TMP/self-update-enabled"
sh "$helper"; sh "$helper"
test "$(cat "$TMP/url")" = "$new"; test "$(wc -l <"$TMP/commits" | tr -d ' ')" = 1
test "$(cat "$TMP/self-update-enabled")" = 0
for value in 'https://custom.invalid/script' 'https://mirror.invalid/official-script' '' "$new"; do
 printf '%s' "$value" >"$TMP/url"; : >"$TMP/commits"
 sh "$helper"; test "$(cat "$TMP/url")" = "$value"; test ! -s "$TMP/commits"
done
echo 'Expanded Makefile installs migration helper; postinst offline guard, exact URL migration and custom/empty preservation passed'

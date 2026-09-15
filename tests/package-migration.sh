#!/usr/bin/env bash
set -Eeuo pipefail

KIND="${1:?ipk or apk required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEGACY_BASE="${2:?legacy base package required}"
LEGACY_ADDON="${3:?legacy addon package required}"
CURRENT_BASE="${4:?current base package required}"
CURRENT_ADDON="${5:?current compatibility package required}"
RUNTIME_BIN="${6:?qualified Runtime binary required}"
OPKG="${OPKG:-opkg}"
APK="${APK:-apk}"
R3_BASE="${R3_BASE:-$LEGACY_BASE}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

OLD_SCRIPT=/usr/libexec/cf-ip/rill.sh
OLD_SCHEMA=/usr/share/cf-ip/rill-feature-schema-v2.json
NEW_SCRIPT=/usr/libexec/cf-ip/candidate-rill.sh
NEW_SCHEMA=/usr/share/cf-ip/candidate-rill-feature-schema-v2.json
BASE_PACKAGE=luci-app-cloudflare-ip
ADDON_PACKAGE=luci-app-cloudflare-ip-rill

manager() {
    case "$KIND" in
        ipk) "$OPKG" --offline-root "$1" --force-depends --force-confold --force-maintainer "${@:2}" ;;
        apk) "$APK" --root "$1" --network=no --repositories-file /dev/null --allow-untrusted "${@:2}" ;;
        *) echo "unsupported package kind: $KIND" >&2; exit 2 ;;
    esac
}

init_root() {
    local root="$1"
    mkdir -p "$root"
    case "$KIND" in
        ipk) mkdir -p "$root/etc/opkg" "$root/usr/lib/opkg" ;;
        apk) manager "$root" add --initdb --no-scripts ;;
    esac
}

install_package() {
    local root="$1" package="$2"
    case "$KIND" in
        ipk) manager "$root" install "$package" ;;
        apk) manager "$root" add --no-scripts --force-broken-world "$package" ;;
    esac
}

remove_package() {
    local root="$1" package="$2"
    case "$KIND" in
        ipk) manager "$root" remove "$package" ;;
        apk) manager "$root" del --no-scripts "$package" ;;
    esac
}

assert_installed() {
    local root="$1" package="$2"
    case "$KIND" in
        ipk)
            if ! manager "$root" status "$package" | grep -Eq '^Status: install (ok )?installed$'; then
                echo "package is not installed: kind=$KIND package=$package root=$root" >&2
                manager "$root" status "$package" >&2 || true
                exit 1
            fi
            ;;
        apk)
            if ! manager "$root" info -e "$package" >/dev/null; then
                echo "package is not installed: kind=$KIND package=$package root=$root" >&2
                manager "$root" info >&2 || true
                exit 1
            fi
            ;;
    esac
}

package_files() {
    local root="$1" package="$2"
    case "$KIND" in
        ipk) manager "$root" files "$package" ;;
        apk) manager "$root" info -L "$package" ;;
    esac
}

assert_owner() {
    local root="$1" package="$2" path="$3"
    local listing
    listing="$(package_files "$root" "$package")" || {
        echo "could not list package files: kind=$KIND package=$package root=$root" >&2
        exit 1
    }
    if ! grep -Eq "(^|[[:space:]])${path#/}(\$|[[:space:]])|(^|[[:space:]])$path(\$|[[:space:]])" <<<"$listing"; then
        echo "$package does not own $path (kind=$KIND root=$root)" >&2
        printf '%s\n' "$listing" >&2
        exit 1
    fi
}

assert_not_owner() {
    local root="$1" package="$2" path="$3"
    local listing
    listing="$(package_files "$root" "$package" 2>/dev/null || true)"
    if grep -Eq "(^|[[:space:]])${path#/}(\$|[[:space:]])|(^|[[:space:]])$path(\$|[[:space:]])" <<<"$listing"; then
        echo "$package unexpectedly owns $path" >&2
        exit 1
    fi
}

assert_file() {
    local root="$1" path="$2"
    test -e "$root$path" || { echo "missing filesystem path: $path" >&2; exit 1; }
}

assert_absent() {
    local root="$1" path="$2"
    test ! -e "$root$path" || { echo "unexpected filesystem path: $path" >&2; exit 1; }
}

runtime_absence() {
    local root="$1"
    CFIP_TEST_LIB_DIR="$root/usr/libexec/cf-ip" \
      CFIP_TEST_SCHEMA_FILE="$root$NEW_SCHEMA" \
      bash "$ROOT/tests/rill-runtime-absence.sh"
}

runtime_present() {
    local root="$1"
    CFIP_TEST_LIB_DIR="$root/usr/libexec/cf-ip" \
      CFIP_TEST_SCHEMA_FILE="$root$NEW_SCHEMA" \
      bash "$ROOT/tests/rill-feedback-integration.sh" "$RUNTIME_BIN"
}

check_base_runtime() {
    local root="$1"
    assert_file "$root" "$NEW_SCRIPT"
    assert_file "$root" "$NEW_SCHEMA"
    assert_owner "$root" "$BASE_PACKAGE" "$NEW_SCRIPT"
    assert_owner "$root" "$BASE_PACKAGE" "$NEW_SCHEMA"
    assert_not_owner "$root" "$BASE_PACKAGE" "$OLD_SCRIPT"
    assert_not_owner "$root" "$BASE_PACKAGE" "$OLD_SCHEMA"
    runtime_absence "$root"
}

fresh_root() {
    local name="$1" root="$WORK/$1"
    mkdir -p "$root"
    init_root "$root" >/dev/null
    printf '%s\n' "$root"
}

run_scenario() {
    local name="$1" root
    echo "running real $KIND package migration scenario $name"
    root="$(fresh_root "$name")"
    shift
    "$@" "$root"
}

scenario_a() {
    local root="$1"
    install_package "$root" "$LEGACY_BASE"
    install_package "$root" "$CURRENT_BASE"
    assert_installed "$root" "$BASE_PACKAGE"
    check_base_runtime "$root"
    assert_absent "$root" "$OLD_SCRIPT"
    assert_absent "$root" "$OLD_SCHEMA"
    runtime_present "$root"
}

scenario_b() {
    local root="$1"
    install_package "$root" "$LEGACY_BASE"
    install_package "$root" "$LEGACY_ADDON"
    install_package "$root" "$CURRENT_BASE"
    assert_installed "$root" "$ADDON_PACKAGE"
    check_base_runtime "$root"
    assert_file "$root" "$OLD_SCRIPT"
    assert_file "$root" "$OLD_SCHEMA"
    assert_owner "$root" "$ADDON_PACKAGE" "$OLD_SCRIPT"
    assert_owner "$root" "$ADDON_PACKAGE" "$OLD_SCHEMA"
    runtime_present "$root"
}

scenario_c() {
    local root="$1"
    install_package "$root" "$LEGACY_BASE"
    install_package "$root" "$LEGACY_ADDON"
    install_package "$root" "$CURRENT_BASE"
    install_package "$root" "$CURRENT_ADDON"
    assert_installed "$root" "$ADDON_PACKAGE"
    check_base_runtime "$root"
    assert_absent "$root" "$OLD_SCRIPT"
    assert_absent "$root" "$OLD_SCHEMA"
    assert_not_owner "$root" "$ADDON_PACKAGE" "$OLD_SCRIPT"
    assert_not_owner "$root" "$ADDON_PACKAGE" "$OLD_SCHEMA"
    runtime_present "$root"
}

scenario_d() {
    local root="$1"
    install_package "$root" "$LEGACY_BASE"
    install_package "$root" "$LEGACY_ADDON"
    install_package "$root" "$CURRENT_BASE"
    remove_package "$root" "$ADDON_PACKAGE"
    assert_absent "$root" "$OLD_SCRIPT"
    assert_absent "$root" "$OLD_SCHEMA"
    check_base_runtime "$root"
    runtime_present "$root"
}

scenario_e() {
    local root="$1"
    install_package "$root" "$R3_BASE"
    install_package "$root" "$CURRENT_BASE"
    assert_installed "$root" "$BASE_PACKAGE"
    check_base_runtime "$root"
    assert_absent "$root" "$OLD_SCRIPT"
    assert_absent "$root" "$OLD_SCHEMA"
    runtime_present "$root"
}

run_scenario "${KIND}-a" scenario_a
run_scenario "${KIND}-b" scenario_b
run_scenario "${KIND}-c" scenario_c
run_scenario "${KIND}-d" scenario_d
run_scenario "${KIND}-e" scenario_e

source_tag="${SOURCE_TAG:-v2.6.0-2}"
source_sha="${SOURCE_SHA:-unknown}"
jq -n --arg kind "$KIND" --arg tag "$source_tag" --arg sha "$source_sha" --arg current "${GITHUB_SHA:-unknown}" \
  '{schemaVersion:1,kind:$kind,sourceTag:$tag,sourceSHA:$sha,currentSHA:$current,legacyVersion:"2.6.0-r2",ipk:(if $kind=="ipk" then "PASS" else "NOT_APPLICABLE" end),apk:(if $kind=="apk" then "PASS" else "NOT_APPLICABLE" end),baseOnlyUpgrade:true,baseAddonToBaseUpgrade:true,addonRemovalSafe:true,r3ToR4:true,runtimeAbsent:true,runtimePresent:true}' \
  > package-migration-evidence.json
echo "real $KIND package-manager migration matrix passed"

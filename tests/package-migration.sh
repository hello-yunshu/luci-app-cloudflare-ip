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
EVIDENCE_DIR="${MIGRATION_EVIDENCE_DIR:-$PWD/package-migration-details}"
mkdir -p "$EVIDENCE_DIR"
WORK="$(mktemp -d)"
SCENARIO=
STAGE=0
trap 'rm -rf "$WORK"' EXIT

OLD_SCRIPT=/usr/libexec/cf-ip/rill.sh
OLD_SCHEMA=/usr/share/cf-ip/rill-feature-schema-v2.json
NEW_SCRIPT=/usr/libexec/cf-ip/candidate-rill.sh
NEW_SCHEMA=/usr/share/cf-ip/candidate-rill-feature-schema-v2.json
BASE_PACKAGE=luci-app-cloudflare-ip
ADDON_PACKAGE=luci-app-cloudflare-ip-rill

manager() {
    case "$KIND" in
        ipk) "$OPKG" --conf "$1/etc/opkg.conf" --offline-root "$1" --add-arch all:10 --force-depends "${@:2}" ;;
        apk) "$APK" --root "$1" --network=no --repositories-file "$APK_REPOSITORIES_FILE" --allow-untrusted --force-non-repository "${@:2}" ;;
        *) echo "unsupported package kind: $KIND" >&2; exit 2 ;;
    esac
}

init_root() {
    local root="$1"
    mkdir -p "$root" "$root/tmp"
    case "$KIND" in
        ipk)
            mkdir -p "$root/etc/opkg" "$root/usr/lib/opkg/info"
            printf 'arch all 1\narch x86_64 10\n' >"$root/etc/opkg.conf"
            for package in libc luci-base bash flock curl tar jq ca-bundle ca-certificates uhttpd rill-runtime-preview; do
                printf 'Package: %s\nVersion: 1\nArchitecture: x86_64\nStatus: install ok installed\n\n' "$package"
                : >"$root/usr/lib/opkg/info/$package.list"
            done >"$root/usr/lib/opkg/status"
            ;;
        apk)
            manager "$root" add --initdb --no-scripts
            manager "$root" add --no-scripts \
                libc=1-r0 luci-base=1-r0 bash=1-r0 flock=1-r0 curl=1-r0 tar=1-r0 jq=1-r0 \
                ca-bundle=1-r0 ca-certificates=1-r0 uhttpd=1-r0 rill-runtime-preview=1-r0
            ;;
    esac
}

snapshot_root() {
    local root="$1" label="$2" out
    STAGE=$((STAGE + 1))
    out="$EVIDENCE_DIR/$SCENARIO/$STAGE-$label"
    mkdir -p "$out"
    case "$KIND" in
        ipk) cp -R "$root/usr/lib/opkg" "$out/installed-db" ;;
        apk) cp -R "$root/lib/apk" "$out/installed-db" ;;
    esac
    manager "$root" info >"$out/manager-info.txt" 2>&1 || true
    for owned in "$BASE_PACKAGE" "$ADDON_PACKAGE"; do
        package_files "$root" "$owned" >"$out/$owned.files" 2>&1 || true
    done
    (cd "$root" && find etc -type f -exec sha256sum {} + | sort) >"$out/etc-sha256.txt"
}

seed_user_data() {
    local root="$1"
    mkdir -p "$root/etc/config" "$root/etc/cf_ip/backups" "$root/etc/crontabs"
    cat >"$root/etc/config/cf_ip" <<'UCI'
config global 'global'
 option enabled '0'
 option self_update_url 'https://example.invalid/private-feed'
 option custom_user_marker 'migration-preservation'
UCI
    printf 'retained backup\n' >"$root/etc/cf_ip/backups/migration.yaml"
    printf '{"retained":true}\n' >"$root/etc/cf_ip/history.json"
    printf '17 3 * * * /usr/bin/true # migration-user-cron\n' >"$root/etc/crontabs/root"
    (cd "$root" && sha256sum etc/config/cf_ip etc/cf_ip/backups/migration.yaml etc/cf_ip/history.json etc/crontabs/root) >"$EVIDENCE_DIR/$SCENARIO/user-before.sha256"
}

assert_user_data() {
    local root="$1"
    (cd "$root" && sha256sum -c "$EVIDENCE_DIR/$SCENARIO/user-before.sha256")
}

install_package() {
    local root="$1" package="$2"
    if [[ "$package" == "$CURRENT_BASE" ]]; then
        seed_user_data "$root"
        snapshot_root "$root" before-current
    fi
    case "$KIND" in
        ipk) manager "$root" install "$package" ;;
        apk)
            local metadata name version
            metadata=$("$APK" adbdump --format json "$package")
            name=$(jq -r '.info.name' <<<"$metadata")
            version=$(jq -r '.info.version' <<<"$metadata")
            manager "$root" add --no-scripts "$name=$version"
            ;;
    esac
    snapshot_root "$root" installed
    if [[ "$package" == "$CURRENT_BASE" ]]; then assert_user_data "$root"; fi
}

remove_package() {
    local root="$1" package="$2"
    case "$KIND" in
        ipk) manager "$root" remove "$package" ;;
        apk) manager "$root" del --no-scripts "$package" ;;
    esac
    snapshot_root "$root" removed
    assert_user_data "$root"
}

assert_installed() {
    local root="$1" package="$2"
    case "$KIND" in
        ipk)
            if ! manager "$root" status "$package" | grep -Eq '^Status: install (ok |user )?installed$'; then
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
        ipk) manager "$root" files "$package" | sed "s#^$root##" ;;
        apk) manager "$root" info -L "$package" | sed "s#^$root##" ;;
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
    SCENARIO="$name"
    STAGE=0
    mkdir -p "$EVIDENCE_DIR/$SCENARIO"
    root="$(fresh_root "$name")"
    shift
    "$@" "$root"
    assert_user_data "$root"
    snapshot_root "$root" final
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

# A rejected input must leave the already installed candidate and user data intact.
# These are input-rejection cases, not mid-install rollback or owner-conflict proof.
payload_snapshot() {
    python3 - "$1" "$2" <<'PYSNAPSHOT'
import hashlib,json,os,stat,sys
from pathlib import Path
root=Path(sys.argv[1]); records={}
exclude={'tmp','usr/lib/opkg','lib/apk'}
for directory,dirs,files in os.walk(root,followlinks=False):
    relative=Path(directory).relative_to(root)
    dirs[:]=sorted(d for d in dirs if (relative/d).as_posix() not in exclude)
    for name in sorted(dirs+files):
        p=Path(directory)/name; key=p.relative_to(root).as_posix(); meta=p.lstat()
        if stat.S_ISLNK(meta.st_mode): records[key]={'link':os.readlink(p)}
        elif stat.S_ISREG(meta.st_mode): records[key]={'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'size':meta.st_size,'mode':stat.S_IMODE(meta.st_mode)}
Path(sys.argv[2]).write_text(json.dumps(records,sort_keys=True,indent=2)+'\n')
PYSNAPSHOT
}

negative_install() {
    local case_name="$1" root out input install_rc=0
    SCENARIO="$KIND-negative-$case_name"; STAGE=0
    out="$EVIDENCE_DIR/$SCENARIO"; mkdir -p "$out"
    root="$(fresh_root "$SCENARIO")"
    install_package "$root" "$CURRENT_BASE"
    assert_installed "$root" "$BASE_PACKAGE"
    package_files "$root" "$BASE_PACKAGE" >"$out/owner-before.txt"
    manager "$root" info >"$out/installed-before.txt"
    payload_snapshot "$root" "$out/payload-before.json"
    input="$WORK/$case_name.$KIND"
    case "$case_name" in
        missing) test ! -e "$input" ;;
        truncated) head -c 32 "$CURRENT_BASE" >"$input"; sha256sum "$input" >"$out/rejected-input.sha256" ;;
        *) return 2 ;;
    esac
    case "$KIND" in
        ipk) manager "$root" install "$input" >"$out/install.log" 2>&1 || install_rc=$? ;;
        apk) manager "$root" add --no-scripts "$input" >"$out/install.log" 2>&1 || install_rc=$? ;;
    esac
    test "$install_rc" -ne 0 || { echo "invalid $case_name package was accepted by $KIND" >&2; return 1; }
    assert_installed "$root" "$BASE_PACKAGE"
    package_files "$root" "$BASE_PACKAGE" >"$out/owner-after.txt"
    manager "$root" info >"$out/installed-after.txt"
    payload_snapshot "$root" "$out/payload-after.json"
    cmp "$out/owner-before.txt" "$out/owner-after.txt"
    cmp "$out/installed-before.txt" "$out/installed-after.txt"
    cmp "$out/payload-before.json" "$out/payload-after.json"
    assert_user_data "$root"
    snapshot_root "$root" rejected-preserved
    jq -n --arg id "$case_name" --arg directory "$SCENARIO" --argjson rc "$install_rc" \
      '{id:$id,status:"PASS",rejected:true,exitCode:$rc,installedStatePreserved:true,payloadPreserved:true,userDataPreserved:true,evidenceDirectory:$directory}' >"$out/result.json"
    echo "PASS real $KIND rejects $case_name package and preserves installed payload/ownership/user data"
}

if [[ "$KIND" == apk ]]; then
    apk_repository="$WORK/apk-repository"
    mkdir -p "$apk_repository"
    for package in libc luci-base bash flock curl tar jq ca-bundle ca-certificates uhttpd rill-runtime-preview; do
        "$APK" mkpkg --output "$apk_repository/$package.apk" \
            --info "name:$package" --info 'version:1-r0' --info 'arch:x86_64' \
            --info 'description:package migration test fixture'
    done
    for package in "$LEGACY_BASE" "$LEGACY_ADDON" "$CURRENT_BASE" "$CURRENT_ADDON" "$R3_BASE"; do
        cp "$package" "$apk_repository/$(basename "$package")"
    done
    "$APK" --allow-untrusted mkndx --output "$apk_repository/packages.adb" "$apk_repository"/*.apk
    APK_REPOSITORIES_FILE="$WORK/apk-repositories"
    printf '%s\n' "$apk_repository/packages.adb" >"$APK_REPOSITORIES_FILE"
fi

# Inspect the exact input bytes, including locally rebuilt historical packages.
for role in legacyBase legacyAddon currentBase currentAddon recentBase; do
    case "$role" in
        legacyBase) input="$LEGACY_BASE"; package_name="$BASE_PACKAGE" ;;
        legacyAddon) input="$LEGACY_ADDON"; package_name="$ADDON_PACKAGE" ;;
        currentBase) input="$CURRENT_BASE"; package_name="$BASE_PACKAGE" ;;
        currentAddon) input="$CURRENT_ADDON"; package_name="$ADDON_PACKAGE" ;;
        recentBase) input="$R3_BASE"; package_name="$BASE_PACKAGE" ;;
    esac
    python3 "$ROOT/scripts/openwrt-package-metadata.py" "$input" --format "$KIND" \
        --apk-bin "$APK" --package-name "$package_name" --output "$EVIDENCE_DIR/$role.json"
done

run_scenario "${KIND}-a" scenario_a
run_scenario "${KIND}-b" scenario_b
run_scenario "${KIND}-c" scenario_c
run_scenario "${KIND}-d" scenario_d
run_scenario "${KIND}-e" scenario_e
negative_install missing
negative_install truncated

jq -n --arg kind "$KIND" \
    --slurpfile missing "$EVIDENCE_DIR/$KIND-negative-missing/result.json" --slurpfile truncated "$EVIDENCE_DIR/$KIND-negative-truncated/result.json" \
    --slurpfile old "$EVIDENCE_DIR/legacyBase.json" --slurpfile addon "$EVIDENCE_DIR/legacyAddon.json" \
    --slurpfile current "$EVIDENCE_DIR/currentBase.json" --slurpfile compat "$EVIDENCE_DIR/currentAddon.json" \
    --slurpfile recent "$EVIDENCE_DIR/recentBase.json" \
    '{schemaVersion:1,packageManager:$kind,negativeInstalls:[$missing[0],$truncated[0]],inputs:{legacyBase:$old[0],legacyAddon:$addon[0],currentBase:$current[0],currentAddon:$compat[0],recentBase:$recent[0]},
      scenarios:[
       {id:"a",from:["legacyBase"],to:["currentBase"],addon:"absent"},
       {id:"b",from:["legacyBase","legacyAddon"],to:["currentBase"],addon:"retained"},
       {id:"c",from:["legacyBase","legacyAddon"],to:["currentBase","currentAddon"],addon:"replaced"},
       {id:"d",from:["legacyBase","legacyAddon"],to:["currentBase"],addon:"removed"},
       {id:"e",from:["recentBase"],to:["currentBase"],addon:"absent"}
      ] | map(. + {status:"PASS",runtimeAbsent:true,runtimePresent:true,userDataPreserved:true,evidenceDirectory:($kind+"-"+.id)})}' \
      >"$EVIDENCE_DIR/current-matrix.json"

source_tag="${SOURCE_TAG:-v2.6.0-2}"
source_sha="${SOURCE_SHA:-unknown}"
jq -n --slurpfile matrix "$EVIDENCE_DIR/current-matrix.json" --arg kind "$KIND" --arg tag "$source_tag" --arg sha "$source_sha" --arg current "${GITHUB_SHA:-unknown}" \
  '{schemaVersion:1,currentMatrix:$matrix[0],historicalR3ToR4Meaning:"legacy field retained; current from/to identity is in currentMatrix",kind:$kind,sourceTag:$tag,sourceSHA:$sha,currentSHA:$current,legacyVersion:"2.6.0-r2",ipk:(if $kind=="ipk" then "PASS" else "NOT_APPLICABLE" end),apk:(if $kind=="apk" then "PASS" else "NOT_APPLICABLE" end),baseOnlyUpgrade:true,baseAddonToBaseUpgrade:true,addonRemovalSafe:true,r3ToR4:true,runtimeAbsent:true,runtimePresent:true}' \
  > package-migration-evidence.json
echo "real $KIND package-manager migration matrix passed"

#!/usr/bin/env bash
# Normalize legacy UCI values before the new engine starts. The original
# config is copied to /etc/cf_ip/backups before the first mutation.
set -u

CONFIG=/etc/config/cf_ip
BACKUP_ROOT=${CFIP_STATUS_DIR:-/etc/cf_ip}/backups
BACKUP_DIR=""
CHANGED=false

[ -f "$CONFIG" ] || exit 0
# shellcheck source=common.sh
. "${CFIP_LIB_DIR:-/usr/libexec/cf-ip}/common.sh"

ensure_backup() {
    local stamp
    [[ -n "$BACKUP_DIR" ]] && return 0
    stamp="$(date +%Y%m%d%H%M%S)"
    BACKUP_DIR="$BACKUP_ROOT/pre-upgrade-${stamp}.$$"
    mkdir -p "$BACKUP_DIR" || return 1
    chmod 700 "$BACKUP_DIR" 2>/dev/null || true
    cp -p "$CONFIG" "$BACKUP_DIR/cf_ip" || return 1
    : >"$BACKUP_DIR/changes.tsv" || return 1
}

set_value() {
    local key="$1" old="$2" new="$3"
    [[ "$old" == "$new" ]] && return 0
    ensure_backup || return 1
    uci -q set "$key=$new" || return 1
    printf '%s\t%s\t%s\n' "$key" "$old" "$new" >>"$BACKUP_DIR/changes.tsv"
    CHANGED=true
}

clamp_int() {
    local key="$1" minimum="$2" maximum="$3" old new
    old="$(uci -q get "$key" 2>/dev/null)" || return 0
    [[ "$old" =~ ^[0-9]+$ ]] || return 0
    new="$old"
    if ((10#$old < minimum)); then new="$minimum"; fi
    if ((10#$old > maximum)); then new="$maximum"; fi
    set_value "$key" "$old" "$new"
}

normalize_path() {
    local key="$1" default="$2" checker="$3" old
    old="$(uci -q get "$key" 2>/dev/null)" || old=""
    if [[ -z "$old" ]]; then
        set_value "$key" "$old" "$default"
        return 0
    fi
    "$checker" "$old" || set_value "$key" "$old" "$default"
}

normalize_runtime_channel() {
    local enabled
    enabled="$(uci -q get cf_ip.rill.enabled 2>/dev/null)" || return 0
    [[ "$(cfip_bool "$enabled")" == true ]] || return 0
    if ! cfip_rill_runtime_allowed; then
        set_value cf_ip.rill.enabled "$enabled" 0
        logger -t cf_ip -p daemon.warn "Rill disabled: runtime channel is $(cfip_rill_runtime_channel), not preview"
    fi
}

# Runtime paths are fixed or confined to package-owned directories.
normalize_path cf_ip.rill.runtime /usr/bin/rill-runtime cfip_managed_runtime_path_safe
normalize_path cf_ip.rill.state_file /etc/cf_ip/rill-state.json cfip_managed_rill_state_safe
normalize_path cf_ip.main.work_dir /usr/bin cfip_managed_work_dir_safe
normalize_path cf_ip.openclash.config /etc/openclash/config/config.yaml cfip_managed_openclash_config_safe
normalize_runtime_channel

# Keep values accepted by the legacy engine within the new safety bounds.
clamp_int cf_ip.main.ip_count 1 32
clamp_int cf_ip.main.candidate_budget 100 512
clamp_int cf_ip.main.probe_top_count 1 32
clamp_int cf_ip.main.probe_concurrency 1 16
clamp_int cf_ip.main.probe_batch_size 1 16
clamp_int cf_ip.main.max_probe_count 1 32
clamp_int cf_ip.main.probe_timeout 1 30
clamp_int cf_ip.main.measurement_timeout 20 300
clamp_int cf_ip.main.recovery_timeout 10 120
clamp_int cf_ip.main.speedtest_dn 1 100
clamp_int cf_ip.main.speedtest_dt 1 60
clamp_int cf_ip.main.speedtest_threads 1 1000
clamp_int cf_ip.main.speedtest_ping_count 1 20
clamp_int cf_ip.main.adaptive_target_ratio_percent 1 100
clamp_int cf_ip.main.adaptive_min_probe_count 1 512
clamp_int cf_ip.main.adaptive_expansion_batch_size 1 32
clamp_int cf_ip.main.adaptive_exploration_ratio_percent 0 50
clamp_int cf_ip.main.adaptive_min_evidence 1 100
clamp_int cf_ip.main.adaptive_evidence_window 1 100
clamp_int cf_ip.main.adaptive_evaluation_max_age_seconds 3600 2592000
clamp_int cf_ip.main.adaptive_audit_interval 1 1000
clamp_int cf_ip.main.max_full_optimize_interval 300 604800
clamp_int cf_ip.main.reuse_validation_timeout 1 30
clamp_int cf_ip.lan.port 1024 65535
clamp_int cf_ip.rill.safe_top_k 1 8
clamp_int cf_ip.rill.min_feedback_samples 1 200
clamp_int cf_ip.rill.evaluation_max_age_seconds 1 604800
clamp_int cf_ip.rill.delayed_feedback_minutes 1 1440

normalize_enum() {
    local key="$1" old allowed
    old="$(uci -q get "$key" 2>/dev/null)" || return 0
    allowed=" $2 "
    [[ " $allowed " == *" $old "* ]] || set_value "$key" "$old" "$3"
}
normalize_enum cf_ip.main.ip_type "ipv4 ipv6 both" ipv4
normalize_enum cf_ip.main.speedtest_protocol "tcp http" tcp
normalize_enum cf_ip.main.mode "passwall openclash" passwall
normalize_enum cf_ip.main.source_policy "balanced official-heavy history-heavy diversity-heavy community-heavy" balanced
normalize_enum cf_ip.main.adaptive_measurement_mode "off shadow guarded" shadow
normalize_enum cf_ip.rill.mode "off shadow assisted" shadow

# Legacy values that would fail the new start validator.
startup="$(uci -q get cf_ip.main.startup_delay 2>/dev/null)" || startup=""
if [[ -n "$startup" && "$startup" != random && ! "$startup" =~ ^[0-9]+$ ]]; then
    set_value cf_ip.main.startup_delay "$startup" ""
fi
tl="$(uci -q get cf_ip.main.speedtest_tl 2>/dev/null)" || tl=""
if [[ -n "$tl" && ! "$tl" =~ ^[0-9]+$ ]]; then set_value cf_ip.main.speedtest_tl "$tl" ""; fi
tll="$(uci -q get cf_ip.main.speedtest_tll 2>/dev/null)" || tll=""
if [[ -n "$tll" && ! "$tll" =~ ^[0-9]+$ ]]; then set_value cf_ip.main.speedtest_tll "$tll" "40"; fi
mirror="$(uci -q get cf_ip.main.github_mirror 2>/dev/null)" || mirror=""
if [[ -n "$mirror" && ("$mirror" != https://* || "$mirror" != */) ]]; then
    set_value cf_ip.main.github_mirror "$mirror" ""
fi

interval="$(uci -q get cf_ip.main.cron_interval 2>/dev/null)" || interval=""
custom="$(uci -q get cf_ip.main.cron_custom 2>/dev/null)" || custom=""
if [[ "$interval" == custom ]]; then
    # Legacy installs stored the expression in cron_custom; keep it rather
    # than silently replacing a user schedule with the 6h default.
    if [[ -z "$custom" ]] || ! /usr/bin/cf-ip-auto --to-cron custom "$custom" >/dev/null 2>&1; then
        set_value cf_ip.main.cron_interval "$interval" "6h"
    fi
elif [[ -z "$interval" ]] || ! /usr/bin/cf-ip-auto --to-cron "$interval" >/dev/null 2>&1; then
    set_value cf_ip.main.cron_interval "$interval" "6h"
fi

# Keep probe_top_count >= ip_count, max_probe_count within that range, and
# adaptive probe bounds consistent with the same candidate budget.
ip_count="$(uci -q get cf_ip.main.ip_count 2>/dev/null)" || ip_count=""
probe_top="$(uci -q get cf_ip.main.probe_top_count 2>/dev/null)" || probe_top=""
if [[ "$ip_count" =~ ^[0-9]+$ && "$probe_top" =~ ^[0-9]+$ ]] && ((10#$probe_top < 10#$ip_count)); then
    set_value cf_ip.main.probe_top_count "$probe_top" "$ip_count"
    probe_top="$ip_count"
fi
max_probe="$(uci -q get cf_ip.main.max_probe_count 2>/dev/null)" || max_probe=""
if [[ "$ip_count" =~ ^[0-9]+$ && "$probe_top" =~ ^[0-9]+$ && "$max_probe" =~ ^[0-9]+$ ]]; then
    if ((10#$max_probe < 10#$ip_count)); then
        set_value cf_ip.main.max_probe_count "$max_probe" "$ip_count"
    elif ((10#$max_probe > 10#$probe_top)); then
        set_value cf_ip.main.max_probe_count "$max_probe" "$probe_top"
    fi
fi
adaptive_min="$(uci -q get cf_ip.main.adaptive_min_probe_count 2>/dev/null)" || adaptive_min=""
adaptive_max="$(uci -q get cf_ip.main.adaptive_max_probe_count 2>/dev/null)" || adaptive_max=""
budget="$(uci -q get cf_ip.main.candidate_budget 2>/dev/null)" || budget=""
if [[ "$ip_count" =~ ^[0-9]+$ && "$adaptive_min" =~ ^[0-9]+$ && "$adaptive_max" =~ ^[0-9]+$ && "$budget" =~ ^[0-9]+$ ]]; then
    if ((10#$adaptive_min < 10#$ip_count)); then
        set_value cf_ip.main.adaptive_min_probe_count "$adaptive_min" "$ip_count"
        adaptive_min="$ip_count"
    fi
    if ((10#$adaptive_max < 10#$adaptive_min)); then
        set_value cf_ip.main.adaptive_max_probe_count "$adaptive_max" "$adaptive_min"
    elif ((10#$adaptive_max > 10#$budget)); then
        set_value cf_ip.main.adaptive_max_probe_count "$adaptive_max" "$budget"
    fi
fi

if [[ "$CHANGED" == true ]]; then
    uci -q commit cf_ip || exit 1
    logger -t cf_ip -p daemon.warn "legacy configuration migrated; backup=$BACKUP_DIR"
    printf '%s\n' "$BACKUP_DIR"
fi
exit 0

#!/usr/bin/env bash
# shellcheck shell=bash

CFIP_INIT_DIR="${CFIP_INIT_DIR:-/etc/init.d}"

cfip_log() {
    local msg="$*" ts
    ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
    mkdir -p "${CFIP_LOG_FILE%/*}" 2>/dev/null || true
    printf '[%s] %s\n' "$ts" "$msg" >>"$CFIP_LOG_FILE" 2>/dev/null || true
    [[ "${CFIP_VERBOSE:-false}" == true ]] && printf '[cloudflare-ip] %s\n' "$msg" >&2 || true
}

cfip_json_error() {
    jq -cn --arg error "$1" '{success:false,error:$error}'
}

cfip_bool() {
    case "${1:-}" in 1|on|true|yes|enabled) printf true ;; *) printf false ;; esac
}

cfip_atomic_write() {
    local output="$1" tmp
    mkdir -p "${output%/*}" 2>/dev/null || true
    tmp="$(mktemp "${output}.tmp.XXXXXX")" || return 1
    cat >"$tmp" || { rm -f "$tmp"; return 1; }
    chmod 600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$output"
}

cfip_generate_run_id() {
    local now rand
    now="$(date +%s 2>/dev/null || printf 0)"
    rand="${RANDOM:-0}"
    printf '%s-%s-%s' "$now" "$$" "$rand"
}

cfip_now_millis() {
    local value
    value="$(date +%s%3N 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s' "$value"
    else
        printf '%s000' "$(date +%s)"
    fi
}

cfip_is_ipv4() {
    local ip="$1" IFS=. octets i
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    read -r -a octets <<<"$ip"
    ((${#octets[@]} == 4)) || return 1
    for i in "${octets[@]}"; do [[ "$i" =~ ^[0-9]+$ ]] && ((10#$i <= 255)) || return 1; done
}

cfip_is_ipv6() {
    local ip="$1"
    [[ "$ip" == *:* && "$ip" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
    declare -F cfip_expand_ipv6_hex >/dev/null 2>&1 || return 1
    cfip_expand_ipv6_hex "$ip" >/dev/null 2>&1
}

cfip_ip_family() {
    cfip_is_ipv4 "$1" && { printf ipv4; return 0; }
    cfip_is_ipv6 "$1" && { printf ipv6; return 0; }
    return 1
}

# Return the canonical aggregate key used by Prefix Intelligence.  IPv4 is
# grouped by /24 and IPv6 by /64; IPv6 is normalized through the same parser
# used by the address safety checks, so textual compression does not create
# duplicate groups.
cfip_prefix_key() {
    local ip="$1" family hex out i a b c _
    if cfip_is_ipv4 "$ip"; then
        IFS=. read -r a b c _ <<<"$ip"
        printf '%s.%s.%s.0/24' "$((10#$a))" "$((10#$b))" "$((10#$c))"
        return 0
    fi
    family="$(cfip_ip_family "$ip" 2>/dev/null || true)"
    [[ "$family" == ipv6 ]] || return 1
    declare -F cfip_expand_ipv6_hex >/dev/null 2>&1 || return 1
    hex="$(cfip_expand_ipv6_hex "$ip")" || return 1
    out=""
    for ((i=0; i<16; i+=4)); do
        [[ -n "$out" ]] && out+=:
        out+="${hex:i:4}"
    done
    printf '%s/64' "$out"
}

cfip_ipv6_in_prefix() {
    local ip="$1" cidr="$2" network prefix ip_hex network_hex fixed rem mask ip_nibble network_nibble
    [[ "$cidr" == */* ]] || return 1
    network="${cidr%/*}"; prefix="${cidr##*/}"
    [[ "$prefix" =~ ^[0-9]+$ ]] && ((prefix <= 128)) || return 1
    ip_hex="$(cfip_expand_ipv6_hex "$ip")" || return 1
    network_hex="$(cfip_expand_ipv6_hex "$network")" || return 1
    fixed=$((prefix / 4)); rem=$((prefix % 4))
    if ((fixed > 0)) && [[ "${ip_hex:0:fixed}" != "${network_hex:0:fixed}" ]]; then
        return 1
    fi
    if ((rem > 0)); then
        mask=$((0xF << (4 - rem)))
        ip_nibble=$((16#${ip_hex:fixed:1}))
        network_nibble=$((16#${network_hex:fixed:1}))
        (( (ip_nibble & mask) == (network_nibble & mask) )) || return 1
    fi
    return 0
}

cfip_is_public_candidate() {
    local ip="$1" first second third fourth special_prefix
    if cfip_is_ipv4 "$ip"; then
        IFS=. read -r first second third fourth <<<"$ip"
        ((first >= 1 && first <= 223)) || return 1
        ((first == 10)) && return 1
        ((first == 100 && second >= 64 && second <= 127)) && return 1
        ((first == 127 || first == 169 && second == 254)) && return 1
        ((first == 172 && second >= 16 && second <= 31)) && return 1
        ((first == 192 && second == 168)) && return 1
        ((first == 192 && second == 0 && third == 0)) && return 1
        ((first == 192 && second == 0 && third == 2)) && return 1
        ((first == 192 && second == 31 && third == 196)) && return 1
        ((first == 192 && second == 52 && third == 193)) && return 1
        ((first == 192 && second == 88 && third == 99)) && return 1
        ((first == 192 && second == 175 && third == 48)) && return 1
        ((first == 198 && second == 18 || first == 198 && second == 19)) && return 1
        ((first == 198 && second == 51 && third == 100)) && return 1
        ((first == 203 && second == 0 && third == 113)) && return 1
        ((first >= 224)) && return 1
        return 0
    fi
    cfip_is_ipv6 "$ip" || return 1
    for special_prefix in \
        ::/128 \
        ::1/128 \
        ::ffff:0:0/96 \
        64:ff9b::/96 \
        64:ff9b:1::/48 \
        100::/64 \
        100:0:0:1::/64 \
        2001:0::/32 \
        2001:1::/32 \
        2001:2::/32 \
        2001:3::/32 \
        2001:4:112::/48 \
        2001:10::/28 \
        2001:20::/28 \
        2001:30::/28 \
        2001:db8::/32 \
        2002::/16 \
        fc00::/7 \
        fe80::/10 \
        ff00::/8 \
        3ffe::/16 \
        3fff::/16 \
        5f00::/16 \
        2620:4f:8000::/48; do
        cfip_ipv6_in_prefix "$ip" "$special_prefix" && return 1
    done
    return 0
}

cfip_normalize_domain_list() {
    local input="$1" out=() raw d
    IFS=',' read -r -a raw <<<"$input"
    for d in "${raw[@]}"; do
        d="${d#${d%%[![:space:]]*}}"; d="${d%${d##*[![:space:]]}}"
        [[ -n "$d" && ${#d} -le 253 && "$d" =~ ^[A-Za-z0-9._-]+$ && "$d" == *.* ]] || continue
        out+=("$d")
    done
    ((${#out[@]} > 0)) || return 1
    local IFS=,
    printf '%s' "${out[*]}"
}

cfip_https_url_or_empty() {
    [[ -z "${1:-}" || "$1" =~ ^https://[^[:space:][:cntrl:]]+$ ]]
}

cfip_valid_cron() {
    local expr="$1" f1 f2 f3 f4 f5
    [[ -n "$expr" && "$expr" != *$'\n'* && "$expr" != *$'\r'* ]] || return 1
    [[ "$expr" =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)$ ]] || return 1
    f1="${BASH_REMATCH[1]}"; f2="${BASH_REMATCH[2]}"; f3="${BASH_REMATCH[3]}"; f4="${BASH_REMATCH[4]}"; f5="${BASH_REMATCH[5]}"
    cfip_valid_cron_field "$f1" 0 59 || return 1
    cfip_valid_cron_field "$f2" 0 23 || return 1
    cfip_valid_cron_field "$f3" 1 31 || return 1
    cfip_valid_cron_field "$f4" 1 12 || return 1
    cfip_valid_cron_field "$f5" 0 7 || return 1
}

cfip_valid_cron_field() {
    local field="$1" minimum="$2" maximum="$3" term base step left right value
    local -a terms=()
    IFS=',' read -r -a terms <<<"$field"
    ((${#terms[@]} > 0)) || return 1
    for term in "${terms[@]}"; do
        [[ -n "$term" && "$term" != *'?'* ]] || return 1
        step=1; base="$term"
        if [[ "$term" == */* ]]; then
            [[ "$term" != */*/* ]] || return 1
            base="${term%%/*}"; step="${term#*/}"
            [[ "$step" =~ ^[1-9][0-9]*$ ]] || return 1
            ((step <= maximum - minimum + 1)) || return 1
            [[ "$base" == '*' || "$base" =~ ^[0-9]+-[0-9]+$ ]] || return 1
        fi
        if [[ "$base" == '*' ]]; then
            continue
        elif [[ "$base" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            left="${BASH_REMATCH[1]}"; right="${BASH_REMATCH[2]}"
            ((left >= minimum && right <= maximum && left <= right)) || return 1
        elif [[ "$base" =~ ^[0-9]+$ ]]; then
            value="$base"; ((value >= minimum && value <= maximum)) || return 1
            [[ "$step" == 1 ]] || return 1
        else
            return 1
        fi
    done
}

cfip_service_status_timeout() {
    local class="${1:-status}" remaining
    case "$class" in
        measurement|normal) remaining="$(cfip_measurement_remaining)" ;;
        recovery) remaining="$(cfip_recovery_remaining)" ;;
        status) printf '%s' "${CFIP_STATUS_TIMEOUT_SECONDS:-3}"; return 0 ;;
        *) [[ "$class" =~ ^[1-9][0-9]*$ ]] || return 2; printf '%s' "$class"; return 0 ;;
    esac
    ((remaining > 0)) && printf '%s' "$remaining" || printf 0
}

cfip_service_running() {
    local service="$1" timeout_class="${2:-status}" timeout rc=0
    [[ -x "$CFIP_INIT_DIR/$service" ]] || return 1
    timeout="$(cfip_service_status_timeout "$timeout_class")" || return 2
    ((timeout > 0)) || return 124
    cfip_run_with_timeout "$timeout" "$CFIP_INIT_DIR/$service" running >/dev/null 2>&1 || rc=$?
    ((rc == 0)) && return 0
    [[ "$service" == openclash ]] && pidof clash >/dev/null 2>&1
}

# OpenClash's own start path waits up to 300 seconds for its local /group
# controller endpoint (see check_core_status() in /etc/init.d/openclash).
CFIP_OPENCLASH_START_TIMEOUT_SECONDS=312
CFIP_OPENCLASH_EXPECTED_ENABLED=""
CFIP_OPENCLASH_INITIAL_RUNNING=false
CFIP_OPENCLASH_INITIAL_HEALTHY=false
CFIP_OPENCLASH_DEFERRED=false
CFIP_OPENCLASH_CF_STOPPED=false
CFIP_OPENCLASH_RECOVERY_ATTEMPTED=false
CFIP_OPENCLASH_RECOVERY_VERIFIED=false
CFIP_OPENCLASH_RESTART_ATTEMPTS=0
CFIP_OPENCLASH_FILE_WRITTEN=false
CFIP_OPENCLASH_SERVICE_APPLIED=false
CFIP_OPENCLASH_SERVICE_ERROR=""
CFIP_OPENCLASH_ENABLE_VALUE=""

cfip_openclash_read_enable() {
    local value rc=0
    CFIP_OPENCLASH_ENABLE_VALUE=""
    command -v uci >/dev/null 2>&1 || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash is not installed or UCI is unavailable"; return 1; }
    value="$(uci -q get openclash.config.enable 2>/dev/null)" || rc=$?
    ((rc == 0)) || { CFIP_OPENCLASH_SERVICE_ERROR="cannot read openclash.config.enable"; return 1; }
    case "$value" in
        0|1) CFIP_OPENCLASH_ENABLE_VALUE="$value" ;;
        *) CFIP_OPENCLASH_SERVICE_ERROR="openclash.config.enable is missing or invalid"; return 1 ;;
    esac
}

cfip_openclash_secret() {
    local config="${CFIP_OPENCLASH_CONFIG:-/etc/openclash/config/config.yaml}"
    [[ -r "$config" ]] || return 1
    awk '
        /^[[:space:]]*secret:[[:space:]]*/ {
            value=$0
            sub(/^[[:space:]]*secret:[[:space:]]*/, "", value)
            sub(/[[:space:]]+#.*/, "", value)
            sub(/[[:space:]]+$/, "", value)
            if (value ~ /^\047.*\047$/ || value ~ /^".*"$/) value=substr(value, 2, length(value)-2)
            print value
            exit
        }
    ' "$config"
}

# This probes the same local controller endpoint used by OpenClash's
# check_core_status() and never prints the response, URL, or authorization.
cfip_openclash_health_once() {
    local pids_before pids_after port secret curl_cfg body code rc=0 healthy=false limit="${1:-4}"
    pids_before="$(pidof clash 2>/dev/null)" || pids_before=""
    [[ -n "$pids_before" ]] || return 1
    port="$(uci -q get openclash.config.cn_port 2>/dev/null)" || return 1
    [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && ((port <= 65535)) || return 1
    secret="$(cfip_openclash_secret 2>/dev/null)" || return 1
    body="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-health.XXXXXX")" || return 1
    curl_cfg="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-curl.XXXXXX")" || { rm -f "$body"; return 1; }
    chmod 600 "$curl_cfg" "$body" 2>/dev/null || true
    if [[ -n "$secret" ]]; then
        [[ "$secret" != *$'\n'* && "$secret" != *$'\r'* ]] || { rm -f "$body" "$curl_cfg"; return 1; }
        secret="${secret//\\/\\\\}"
        secret="${secret//\"/\\\"}"
        printf 'header = "Authorization: Bearer %s"\n' "$secret" >"$curl_cfg" || { rm -f "$body" "$curl_cfg"; return 1; }
    fi
    code="$(curl --config "$curl_cfg" --connect-timeout 2 --max-time "$limit" --silent --show-error --output "$body" --write-out '%{http_code}' "http://127.0.0.1:${port}/group" 2>/dev/null)" || rc=$?
    pids_after="$(pidof clash 2>/dev/null)" || pids_after=""
    if ((rc == 0)) && [[ "$code" == 200 && "$pids_before" == "$pids_after" ]] && jq -e 'type == "object"' "$body" >/dev/null 2>&1; then
        healthy=true
    fi
    rm -f "$body" "$curl_cfg"
    [[ "$healthy" == true ]]
}

cfip_openclash_health_wait() {
    local timeout="${1:-10}" spacing="${2:-${CFIP_OPENCLASH_HEALTH_WAIT_INTERVAL_SECONDS:-2}}" started now remaining limit delay healthy=0 pids="" previous_pids=""
    [[ "$timeout" =~ ^[1-9][0-9]*$ && "$spacing" =~ ^[1-9][0-9]*$ ]] || return 2
    started="$(cfip_monotonic_seconds)" || return 1
    while :; do
        now="$(cfip_monotonic_seconds)" || return 1
        remaining=$((started + timeout - now)); ((remaining > 0)) || return 1
        limit=4; ((remaining >= limit)) || limit="$remaining"
        pids="$(pidof clash 2>/dev/null)" || pids=""
        if [[ -n "$pids" ]] && cfip_openclash_health_once "$limit"; then
            if [[ "$pids" == "$previous_pids" ]]; then healthy=$((healthy + 1)); else healthy=1; fi
        else
            healthy=0
        fi
        previous_pids="$pids"
        now="$(cfip_monotonic_seconds)" || return 1
        remaining=$((started + timeout - now)); ((remaining > 0)) || return 1
        ((healthy >= 3)) && return 0
        delay="$spacing"; ((remaining >= delay)) || delay="$remaining"
        sleep "$delay"
    done
    return 1
}

cfip_openclash_capture_state() {
    local enable
    CFIP_OPENCLASH_SERVICE_ERROR=""
    [[ -x "$CFIP_INIT_DIR/openclash" ]] || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash is not installed"; return 1; }
    cfip_openclash_read_enable || return 1
    enable="$CFIP_OPENCLASH_ENABLE_VALUE"
    CFIP_OPENCLASH_EXPECTED_ENABLED="$enable"
    CFIP_OPENCLASH_INITIAL_RUNNING=false
    CFIP_OPENCLASH_INITIAL_HEALTHY=false
    CFIP_OPENCLASH_DEFERRED=false
    if pidof clash >/dev/null 2>&1; then CFIP_OPENCLASH_INITIAL_RUNNING=true; fi
    if [[ "$enable" == 0 ]]; then
        if [[ "$CFIP_OPENCLASH_INITIAL_RUNNING" == true ]]; then
            CFIP_OPENCLASH_SERVICE_ERROR="OpenClash state is inconsistent (disabled but core is running); no changes were made"
            return 1
        fi
        CFIP_OPENCLASH_DEFERRED=true
        return 0
    fi
    if [[ "$CFIP_OPENCLASH_INITIAL_RUNNING" != true ]]; then
        CFIP_OPENCLASH_SERVICE_ERROR="OpenClash is enabled but its core is not running; restore OpenClash before running CF"
        return 1
    fi
    if ! cfip_openclash_health_wait 5; then
        CFIP_OPENCLASH_SERVICE_ERROR="OpenClash is enabled but its core or local controller is unhealthy; restore OpenClash before running CF"
        return 1
    fi
    cfip_openclash_read_enable || return 1
    [[ "$CFIP_OPENCLASH_ENABLE_VALUE" == 1 ]] || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash enable state changed during preflight"; return 1; }
    CFIP_OPENCLASH_INITIAL_HEALTHY=true
}

cfip_openclash_check_before_write() {
    local expected="${CFIP_OPENCLASH_EXPECTED_ENABLED:-}"
    [[ "${CFIP_OPENCLASH_CF_STOPPED:-false}" == true ]] && expected=0
    cfip_openclash_read_enable || return 1
    [[ "$CFIP_OPENCLASH_ENABLE_VALUE" == "$expected" ]] || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash enable state changed before node write; no changes were made"; return 1; }
    if [[ "$expected" == 0 ]]; then
        ! pidof clash >/dev/null 2>&1 || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash core started externally before node write; no changes were made"; return 1; }
    else
        cfip_openclash_health_wait 5 || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash became unhealthy before node write; restore it before running CF"; return 1; }
    fi
    cfip_openclash_read_enable || return 1
    [[ "$CFIP_OPENCLASH_ENABLE_VALUE" == "$expected" ]] || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash enable state changed before node write"; return 1; }
}

cfip_bounded_external() {
    local deadline_class="$1" remaining
    shift
    case "$deadline_class" in
        recovery) remaining="$(cfip_recovery_remaining)" ;;
        measurement|normal) remaining="$(cfip_measurement_remaining)" ;;
        *) return 2 ;;
    esac
    ((remaining > 0)) || return 124
    cfip_run_with_timeout "$remaining" "$@"
}

cfip_stop_service() {
    local service="$1" enable rc=0
    [[ -x "$CFIP_INIT_DIR/$service" ]] || return 1
    if [[ "$service" == openclash ]]; then
        [[ "${CFIP_OPENCLASH_EXPECTED_ENABLED:-}" == 1 && "${CFIP_OPENCLASH_INITIAL_HEALTHY:-false}" == true ]] || {
            CFIP_OPENCLASH_SERVICE_ERROR="OpenClash state was not captured as healthy; refusing to stop it"
            return 1
        }
        cfip_openclash_read_enable || return 1
        enable="$CFIP_OPENCLASH_ENABLE_VALUE"
        [[ "$enable" == 1 ]] || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash enable state changed before stop; refusing service/config changes"; return 1; }
        uci -q set openclash.config.enable=0 || { CFIP_OPENCLASH_SERVICE_ERROR="failed to set temporary OpenClash stop state"; return 1; }
        if ! uci -q commit openclash; then
            if cfip_openclash_read_enable && [[ "$CFIP_OPENCLASH_ENABLE_VALUE" == 0 ]]; then
                uci -q set openclash.config.enable=1 && uci -q commit openclash || true
            fi
            CFIP_OPENCLASH_SERVICE_ERROR="failed to commit temporary OpenClash stop state; service stop was not requested"
            return 1
        fi
    fi
    cfip_bounded_external measurement "$CFIP_INIT_DIR/$service" stop >/dev/null 2>&1 || rc=$?
    if [[ "$service" == openclash ]]; then
        local i pids
        for i in $(seq 1 30); do
            pids="$(pidof clash 2>/dev/null || true)"
            if [[ -z "$pids" ]]; then
                CFIP_OPENCLASH_CF_STOPPED=true
                ((rc == 0)) && return 0
                CFIP_OPENCLASH_SERVICE_ERROR="OpenClash stopped but its init stop command failed (rc=$rc)"
                return "$rc"
            fi
            sleep 1
        done
        pids="$(pidof clash 2>/dev/null || true)"
        if [[ -n "$pids" ]]; then
            enable=""
            if cfip_openclash_read_enable 2>/dev/null; then enable="$CFIP_OPENCLASH_ENABLE_VALUE"; fi
            if [[ "$enable" == 0 ]]; then
                if ! uci -q set openclash.config.enable=1 || ! uci -q commit openclash; then
                    CFIP_OPENCLASH_SERVICE_ERROR="OpenClash stop timed out and restoring its enable state failed"
                    return 1
                fi
            fi
            CFIP_OPENCLASH_SERVICE_ERROR="OpenClash core remained running after the bounded stop request"
            return 1
        fi
        CFIP_OPENCLASH_CF_STOPPED=true
        ((rc == 0)) || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash stop failed (rc=$rc)"; return "$rc"; }
        return 0
    fi
    return "$rc"
}

cfip_restart_service() {
    local service="$1" deadline_class="${2:-normal}" remaining
    [[ -x "$CFIP_INIT_DIR/$service" ]] || return 1
    if [[ "$service" == openclash ]]; then
        local enable rc=0
        [[ "${CFIP_OPENCLASH_CF_STOPPED:-false}" != true ]] || CFIP_OPENCLASH_RECOVERY_ATTEMPTED=true
        [[ "${CFIP_OPENCLASH_EXPECTED_ENABLED:-}" == 1 ]] || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash was not initially enabled; restart is forbidden"; return 1; }
        ((CFIP_OPENCLASH_RESTART_ATTEMPTS < 2)) || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash restart attempt limit reached"; return 1; }
        cfip_openclash_read_enable || return 1
        enable="$CFIP_OPENCLASH_ENABLE_VALUE"
        if ((CFIP_OPENCLASH_RESTART_ATTEMPTS == 0)) && [[ "$enable" == 0 ]]; then
            [[ "${CFIP_OPENCLASH_CF_STOPPED:-false}" == true ]] || {
                CFIP_OPENCLASH_SERVICE_ERROR="OpenClash enable state changed before apply; refusing to re-enable it"
                return 1
            }
            if ! uci -q set openclash.config.enable=1 || ! uci -q commit openclash; then
                CFIP_OPENCLASH_SERVICE_ERROR="failed to restore OpenClash enable state before restart"
                return 1
            fi
            enable=1
        elif [[ "$enable" == 0 ]]; then
            CFIP_OPENCLASH_SERVICE_ERROR="OpenClash disabled itself during startup; inspect its core start failure before retrying"
            CFIP_OPENCLASH_RECOVERY_ATTEMPTED=true
            return 1
        fi
        [[ "$enable" == 1 ]] || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash enable state changed; refusing to overwrite it"; return 1; }
        CFIP_OPENCLASH_RESTART_ATTEMPTS=$((CFIP_OPENCLASH_RESTART_ATTEMPTS + 1))
        cfip_run_with_timeout "$CFIP_OPENCLASH_START_TIMEOUT_SECONDS" "$CFIP_INIT_DIR/openclash" restart >/dev/null 2>&1 || rc=$?
        if ((rc != 0)); then
            ((rc == 124)) && CFIP_OPENCLASH_SERVICE_ERROR="OpenClash restart exceeded its 312-second startup bound" || CFIP_OPENCLASH_SERVICE_ERROR="OpenClash init restart failed (rc=$rc)"
            return "$rc"
        fi
        enable=""
        if cfip_openclash_read_enable 2>/dev/null; then enable="$CFIP_OPENCLASH_ENABLE_VALUE"; fi
        if [[ "$enable" == 0 ]]; then
            CFIP_OPENCLASH_SERVICE_ERROR="OpenClash disabled itself after core startup failed; inspect OpenClash logs"
            return 1
        fi
        if [[ "$enable" != 1 ]] || ! cfip_openclash_health_wait 10 2; then
            CFIP_OPENCLASH_SERVICE_ERROR="OpenClash restart returned but stable core and local /group health were not verified"
            return 1
        fi
        cfip_openclash_read_enable || return 1
        [[ "$CFIP_OPENCLASH_ENABLE_VALUE" == 1 ]] || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash enable state changed during startup verification"; return 1; }
        [[ "${CFIP_OPENCLASH_RECOVERY_ATTEMPTED:-false}" != true ]] || CFIP_OPENCLASH_RECOVERY_VERIFIED=true
        CFIP_OPENCLASH_SERVICE_APPLIED=true
        return 0
    fi
    cfip_bounded_external "$deadline_class" "$CFIP_INIT_DIR/$service" restart >/dev/null 2>&1 || return $?
    local i
    for i in $(seq 1 20); do
        if [[ "$deadline_class" == recovery ]]; then
            remaining="$(cfip_recovery_remaining)"
        else
            remaining="$(cfip_measurement_remaining)"
        fi
        [[ "$remaining" -gt 0 ]] || return 124
        cfip_service_running "$service" "$deadline_class" && return 0
        sleep 1
    done
    return 1
}

cfip_read_log_json() {
    local content=""
    [[ -f "$CFIP_LOG_FILE" ]] && content="$(tail -n 500 "$CFIP_LOG_FILE" 2>/dev/null || true)"
    jq -cn --arg logs "$content" '{success:true,logs:$logs}'
}

cfip_now_epoch() { date +%s 2>/dev/null || printf 0; }

# Runtime budgets must use Linux's monotonic uptime clock.  The injectable
# file/value hooks make clock-jump behavior testable without changing the
# production wall-clock history contract.
cfip_monotonic_seconds() {
    if [[ "${CFIP_MONOTONIC_SECONDS:-}" =~ ^[0-9]+$ ]]; then
        printf '%s' "$CFIP_MONOTONIC_SECONDS"
    elif [[ -r "${CFIP_MONOTONIC_FILE:-/proc/uptime}" ]]; then
        awk '{print int($1); exit}' "${CFIP_MONOTONIC_FILE:-/proc/uptime}"
    elif [[ "${CFIP_MONOTONIC_FALLBACK:-}" =~ ^[0-9]+$ ]]; then
        printf '%s' "$CFIP_MONOTONIC_FALLBACK"
    else
        # Non-Linux development hosts may lack /proc/uptime.  OpenWrt/Linux
        # always takes the monotonic branch; this explicit last-resort keeps
        # host contracts runnable without pretending wall time is monotonic.
        date +%s 2>/dev/null || return 1
    fi
}

cfip_measurement_remaining() {
    local deadline="${CFIP_MEASUREMENT_DEADLINE:-0}" now
    ((deadline>0)) || { printf 86400; return 0; }
    now="$(cfip_monotonic_seconds)" || return 1
    ((deadline>now)) && printf '%s' "$((deadline-now))" || printf 0
}

cfip_recovery_remaining() {
    local deadline="${CFIP_RECOVERY_DEADLINE:-0}" now
    ((deadline>0)) || { printf 86400; return 0; }
    now="$(cfip_monotonic_seconds)" || return 1
    ((deadline>now)) && printf '%s' "$((deadline-now))" || printf 0
}

# Compatibility name for measurement callers. Recovery must use its own clock.
cfip_deadline_remaining() { cfip_measurement_remaining; }

cfip_begin_recovery() {
    local now timeout="${CFIP_RECOVERY_TIMEOUT:-30}"
    [[ "${CFIP_RECOVERY_ACTIVE:-false}" == true ]] && return 0
    now="$(cfip_monotonic_seconds)" || return 1
    if [[ "${CFIP_OPENCLASH_EXPECTED_ENABLED:-}" == 1 && ( "${CFIP_TXN_MODE:-}" == openclash || "${CFIP_STOPPED_MODE:-}" == openclash ) ]]; then
        timeout=$((CFIP_OPENCLASH_START_TIMEOUT_SECONDS + 10))
    fi
    CFIP_RECOVERY_STARTED_AT="$now"
    CFIP_RECOVERY_DEADLINE=$((now + timeout))
    CFIP_RECOVERY_ACTIVE=true
    CFIP_RECOVERY_ERROR=""
}

# Stop an operation process group where possible, with a Linux /proc child-tree
# fallback for BusyBox environments without a usable setsid.
cfip_process_children() {
    local pid="$1" children child
    [[ -r "/proc/$pid/task/$pid/children" ]] || return 0
    read -r children <"/proc/$pid/task/$pid/children" || true
    for child in $children; do
        cfip_process_children "$child"
        printf '%s\n' "$child"
    done
}

cfip_kill_operation_tree() {
    local pid="${1:-}" pgid="${2:-}" signal="${3:-TERM}" child
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0
    if [[ "$pgid" =~ ^[0-9]+$ && "$pgid" != 0 ]]; then
        kill -"$signal" -- "-$pgid" 2>/dev/null || true
        return 0
    fi
    while IFS= read -r child; do kill -"$signal" "$child" 2>/dev/null || true; done < <(cfip_process_children "$pid")
    kill -"$signal" "$pid" 2>/dev/null || true
}

cfip_cancel_active_operation() {
    local pid="${1:-${CFIP_ACTIVE_PID:-}}" pgid="${2:-${CFIP_ACTIVE_PGID:-}}" grace="${CFIP_TIMEOUT_GRACE_SECONDS:-1}"
    local watcher="${CFIP_ACTIVE_WATCHER_PID:-}" watcher_pgid="${CFIP_ACTIVE_WATCHER_PGID:-}"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        cfip_kill_operation_tree "$pid" "$pgid" TERM
        [[ "$grace" =~ ^[0-9]+$ ]] && ((grace > 0)) && sleep "$grace"
        kill -0 "$pid" 2>/dev/null && cfip_kill_operation_tree "$pid" "$pgid" KILL
        wait "$pid" 2>/dev/null || true
    fi
    if [[ "$watcher" =~ ^[0-9]+$ ]] && kill -0 "$watcher" 2>/dev/null; then
        cfip_kill_operation_tree "$watcher" "$watcher_pgid" TERM
        kill -0 "$watcher" 2>/dev/null && cfip_kill_operation_tree "$watcher" "$watcher_pgid" KILL
    fi
    [[ "$watcher" =~ ^[0-9]+$ ]] && wait "$watcher" 2>/dev/null || true
    CFIP_ACTIVE_PID=""
    CFIP_ACTIVE_PGID=""
    CFIP_ACTIVE_WATCHER_PID=""
    CFIP_ACTIVE_WATCHER_PGID=""
}

# Portable watchdog for OpenWrt/Bash; does not require coreutils timeout.
# Returns 124 when the watchdog expires and terminates the complete operation.
cfip_run_with_timeout() {
    local limit="$1" marker pid watcher pgid watcher_pgid rc timed_out=false
    shift
    [[ "$limit" =~ ^[1-9][0-9]*$ ]] || return 2
    marker="$(mktemp "${TMPDIR:-/tmp}/cfip-timeout.XXXXXX")" || return 2
    rm -f "$marker"
    if command -v setsid >/dev/null 2>&1 && [[ "${CFIP_DISABLE_SETSID:-false}" != true ]]; then
        setsid "$@" & pid=$!
        pgid="$pid"
    else
        "$@" & pid=$!
        pgid=""
    fi
    CFIP_ACTIVE_PID="$pid"
    CFIP_ACTIVE_PGID="$pgid"
    # The timer is the direct child, so it has no shell-owned sleep child that
    # can outlive the watcher. The parent polls both children and performs the
    # timeout action itself, which also keeps signal cleanup in one shell.
    sleep "$limit" & watcher=$!
    watcher_pgid=""
    CFIP_ACTIVE_WATCHER_PID="$watcher"
    CFIP_ACTIVE_WATCHER_PGID="$watcher_pgid"
    while kill -0 "$pid" 2>/dev/null && kill -0 "$watcher" 2>/dev/null; do
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null && ! kill -0 "$watcher" 2>/dev/null; then
        : >"$marker"
        timed_out=true
        cfip_cancel_active_operation "$pid" "$pgid"
    else
        rc=0; wait "$pid" 2>/dev/null || rc=$?
    fi
    if kill -0 "$watcher" 2>/dev/null; then
        cfip_kill_operation_tree "$watcher" "$watcher_pgid" TERM
        kill -0 "$watcher" 2>/dev/null && cfip_kill_operation_tree "$watcher" "$watcher_pgid" KILL
    fi
    wait "$watcher" 2>/dev/null || true
    [[ "$CFIP_ACTIVE_PID" == "$pid" ]] && { CFIP_ACTIVE_PID=""; CFIP_ACTIVE_PGID=""; }
    [[ "$CFIP_ACTIVE_WATCHER_PID" == "$watcher" ]] && { CFIP_ACTIVE_WATCHER_PID=""; CFIP_ACTIVE_WATCHER_PGID=""; }
    if [[ "$timed_out" == true || -f "$marker" ]]; then rm -f "$marker"; return 124; fi
    rm -f "$marker"
    return "$rc"
}

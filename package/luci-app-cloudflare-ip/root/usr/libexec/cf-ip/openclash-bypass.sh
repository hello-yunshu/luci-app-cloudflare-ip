#!/usr/bin/env bash
# Optional, narrowly scoped OpenClash measurement bypass.
# It never changes OpenClash UCI/config or restarts the proxy. A unique UID,
# candidate-only address sets with a short TTL, and exact output-chain rules
# keep the exception limited to CFI's pre-apply probes.

CFIP_OPENCLASH_BYPASS_ACTIVE=false
CFIP_OPENCLASH_BYPASS_CHAIN_V4=""
CFIP_OPENCLASH_BYPASS_CHAIN_V6=""
CFIP_OPENCLASH_BYPASS_SET_V4=""
CFIP_OPENCLASH_BYPASS_SET_V6=""
CFIP_OPENCLASH_BYPASS_COMMENT=""
CFIP_OPENCLASH_BYPASS_UID=""
CFIP_OPENCLASH_BYPASS_STARTED=""
CFIP_OPENCLASH_BYPASS_USER="nobody"
CFIP_OPENCLASH_BYPASS_GROUP="daemon"
CFIP_OPENCLASH_BYPASS_TTL=300
CFIP_OPENCLASH_BYPASS_ERROR=""
CFIP_OPENCLASH_MEASUREMENT_BYPASS_USED=false

cfip_openclash_measurement_bypass_discover_chains() {
    local family="$1" parent chain parent_listing child_listing
    local -a chains=() targets=()
    case "$family" in
        ipv4) targets=(openclash_mangle_output openclash_output) ;;
        ipv6) targets=(openclash_mangle_output_v6 openclash_output_v6) ;;
        *) return 1 ;;
    esac
    for parent in mangle_output nat_output; do
        parent_listing="$(nft -a list chain inet fw4 "$parent" 2>/dev/null)" || continue
        grep -q 'hook output' <<<"$parent_listing" || continue
        for chain in "${targets[@]}"; do
            grep -Eq "(jump|goto)[[:space:]]+${chain}([[:space:];]|$)" <<<"$parent_listing" || continue
            child_listing="$(nft -a list chain inet fw4 "$chain" 2>/dev/null)" || continue
            grep -Eq 'return|redirect|mark set' <<<"$child_listing" || continue
            if ((${#chains[@]} == 0)) || [[ " ${chains[*]} " != *" $chain "* ]]; then
                chains+=("$chain")
            fi
        done
    done
    printf '%s' "${chains[*]}"
}

cfip_openclash_bypass_candidate_ips() {
    local file="$1" ip family
    local -a v4=() v6=()
    [[ -s "$file" && -f "$file" && ! -L "$file" ]] || return 1
    while IFS= read -r ip || [[ -n "$ip" ]]; do
        ip="${ip%$'\r'}"
        [[ -n "$ip" ]] || continue
        # Strip CIDR suffix (/32, /128, etc.) — CFST input uses CIDR notation
        # but nftables bypass sets need bare addresses.
        ip="${ip%%/*}"
        family="$(cfip_ip_family "$ip" 2>/dev/null)" || return 1
        case "$family" in ipv4) v4+=("$ip") ;; ipv6) v6+=("$ip") ;; *) return 1 ;; esac
    done <"$file"
    ((${#v4[@]} + ${#v6[@]} > 0)) || return 1
    CFIP_OPENCLASH_BYPASS_IPS_V4="$(printf '%s\n' "${v4[@]}" | sed '/^$/d' | sort -u | awk 'BEGIN{ORS=""} NR>1{printf ","} {printf "%s",$0}')"
    CFIP_OPENCLASH_BYPASS_IPS_V6="$(printf '%s\n' "${v6[@]}" | sed '/^$/d' | sort -u | awk 'BEGIN{ORS=""} NR>1{printf ","} {printf "%s",$0}')"
}

cfip_openclash_bypass_rule_count() {
    local chain="$1" listing
    listing="$(nft -a list chain inet fw4 "$chain" 2>/dev/null)" || return 1
    printf '%s\n' "$listing" | awk -v c="comment \"${CFIP_OPENCLASH_BYPASS_COMMENT}\"" 'index($0,c) { n++ } END { print n+0 }'
}

cfip_openclash_bypass_rule_valid() {
    local family="$1" chain="$2" listing expected
    listing="$(nft -a list chain inet fw4 "$chain" 2>/dev/null)" || return 1
    case "$family" in
        ipv4) expected="meta skuid ${CFIP_OPENCLASH_BYPASS_UID} ip daddr . tcp dport @${CFIP_OPENCLASH_BYPASS_SET_V4} return comment \"${CFIP_OPENCLASH_BYPASS_COMMENT}\"" ;;
        ipv6) expected="meta skuid ${CFIP_OPENCLASH_BYPASS_UID} ip6 daddr . tcp dport @${CFIP_OPENCLASH_BYPASS_SET_V6} return comment \"${CFIP_OPENCLASH_BYPASS_COMMENT}\"" ;;
        *) return 1 ;;
    esac
    awk -v expected="$expected" '
        index($0, expected) { bypass=NR }
        /(redirect|tproxy|mark set)/ && intercept==0 { intercept=NR }
        END { exit !(bypass > 0 && (intercept == 0 || bypass < intercept)) }
    ' <<<"$listing"
}

cfip_openclash_bypass_set_valid() {
    local family="$1" set="$2" listing ip
    local -a ips=()
    listing="$(nft list set inet fw4 "$set" 2>/dev/null)" || return 1
    case "$family" in
        ipv4) IFS=',' read -r -a ips <<<"$CFIP_OPENCLASH_BYPASS_IPS_V4" ;;
        ipv6) IFS=',' read -r -a ips <<<"$CFIP_OPENCLASH_BYPASS_IPS_V6" ;;
        *) return 1 ;;
    esac
    for ip in "${ips[@]}"; do
        grep -Fq "$ip . 443" <<<"$listing" || return 1
    done
}

cfip_openclash_measurement_bypass_assert() {
    local now count chain expected=0 current
    local -a chains=()
    [[ "$CFIP_OPENCLASH_BYPASS_ACTIVE" == true ]] || return 1
    cfip_openclash_runtime_unchanged || { CFIP_OPENCLASH_BYPASS_ERROR="OpenClash core identity changed during bypass measurement"; return 1; }
    now="$(cfip_monotonic_seconds 2>/dev/null)" || return 1
    [[ "$now" =~ ^[0-9]+$ ]] || return 1
    ((now - CFIP_OPENCLASH_BYPASS_STARTED < CFIP_OPENCLASH_BYPASS_TTL)) || {
        CFIP_OPENCLASH_BYPASS_ERROR="measurement bypass TTL expired; result is invalid"
        return 1
    }
    if [[ -n "$CFIP_OPENCLASH_BYPASS_CHAIN_V4" ]]; then
        current="$(cfip_openclash_measurement_bypass_discover_chains ipv4)"
        [[ "$current" == "$CFIP_OPENCLASH_BYPASS_CHAIN_V4" ]] || { CFIP_OPENCLASH_BYPASS_ERROR="OpenClash IPv4 output chain membership changed; measurement is invalid"; return 1; }
        read -r -a chains <<<"$CFIP_OPENCLASH_BYPASS_CHAIN_V4"
        expected=$((expected + ${#chains[@]}))
        for chain in "${chains[@]}"; do
            count="$(cfip_openclash_bypass_rule_count "$chain")" || return 1
            ((count == 1)) && cfip_openclash_bypass_rule_valid ipv4 "$chain" || { CFIP_OPENCLASH_BYPASS_ERROR="OpenClash IPv4 bypass rule disappeared or changed; measurement is invalid"; return 1; }
        done
        cfip_openclash_bypass_set_valid ipv4 "$CFIP_OPENCLASH_BYPASS_SET_V4" || { CFIP_OPENCLASH_BYPASS_ERROR="OpenClash IPv4 candidate set disappeared or changed; measurement is invalid"; return 1; }
    fi
    if [[ -n "$CFIP_OPENCLASH_BYPASS_CHAIN_V6" ]]; then
        current="$(cfip_openclash_measurement_bypass_discover_chains ipv6)"
        [[ "$current" == "$CFIP_OPENCLASH_BYPASS_CHAIN_V6" ]] || { CFIP_OPENCLASH_BYPASS_ERROR="OpenClash IPv6 output chain membership changed; measurement is invalid"; return 1; }
        read -r -a chains <<<"$CFIP_OPENCLASH_BYPASS_CHAIN_V6"
        expected=$((expected + ${#chains[@]}))
        for chain in "${chains[@]}"; do
            count="$(cfip_openclash_bypass_rule_count "$chain")" || return 1
            ((count == 1)) && cfip_openclash_bypass_rule_valid ipv6 "$chain" || { CFIP_OPENCLASH_BYPASS_ERROR="OpenClash IPv6 bypass rule disappeared or changed; measurement is invalid"; return 1; }
        done
        cfip_openclash_bypass_set_valid ipv6 "$CFIP_OPENCLASH_BYPASS_SET_V6" || { CFIP_OPENCLASH_BYPASS_ERROR="OpenClash IPv6 candidate set disappeared or changed; measurement is invalid"; return 1; }
    fi
    ((expected > 0))
}

cfip_openclash_measurement_bypass_begin() {
    local uid gid token tmp ip chain
    local -a _v4_ips=() _v6_ips=()
    CFIP_OPENCLASH_BYPASS_ACTIVE=false
    CFIP_OPENCLASH_BYPASS_ERROR=""
    [[ "${CFIP_MODE:-}" == openclash && "${CFIP_OPENCLASH_EXPECTED_ENABLED:-0}" == 1 && "${CFIP_OPENCLASH_INITIAL_HEALTHY:-false}" == true ]] || return 1
    [[ "${CFIP_SPEEDTEST_PROTOCOL:-tcp}" == tcp || "${CFIP_SPEEDTEST_PROTOCOL:-tcp}" == http ]] || {
        CFIP_OPENCLASH_BYPASS_ERROR="temporary bypass is verified only for TCPing or HTTPS HTTPing on TCP/443; using maintenance mode"
        return 1
    }
    [[ -x "${CFIP_PROBE_EXEC:-/usr/libexec/cf-ip/probe-exec}" ]] || { CFIP_OPENCLASH_BYPASS_ERROR="low-privilege probe helper is unavailable"; return 1; }
    command -v start-stop-daemon >/dev/null 2>&1 && command -v nft >/dev/null 2>&1 || { CFIP_OPENCLASH_BYPASS_ERROR="start-stop-daemon or nft is unavailable"; return 1; }
    uid="$(id -u "$CFIP_OPENCLASH_BYPASS_USER" 2>/dev/null)"
    gid="$(id -g "$CFIP_OPENCLASH_BYPASS_GROUP" 2>/dev/null)"
    [[ "$uid" =~ ^[1-9][0-9]*$ && "$gid" =~ ^[1-9][0-9]*$ && "$gid" != 65534 ]] || {
        CFIP_OPENCLASH_BYPASS_ERROR="non-root probe UID and a group outside OpenClash's broad nobody-group exemption are unavailable"
        return 1
    }
    cfip_openclash_runtime_unchanged || { CFIP_OPENCLASH_BYPASS_ERROR="OpenClash core identity changed before bypass setup"; return 1; }
    nft list table inet fw4 >/dev/null 2>&1 || { CFIP_OPENCLASH_BYPASS_ERROR="active nft fw4 table is unavailable"; return 1; }
    cfip_openclash_bypass_candidate_ips "$CFIP_CANDIDATE_INPUT_FILE" || { CFIP_OPENCLASH_BYPASS_ERROR="candidate address set is invalid"; return 1; }
    [[ -z "$CFIP_OPENCLASH_BYPASS_IPS_V4" ]] || {
        CFIP_OPENCLASH_BYPASS_CHAIN_V4="$(cfip_openclash_measurement_bypass_discover_chains ipv4)"
        [[ -n "$CFIP_OPENCLASH_BYPASS_CHAIN_V4" ]] || { CFIP_OPENCLASH_BYPASS_ERROR="active OpenClash IPv4 output chain is unavailable or unrecognized"; return 1; }
    }
    [[ -z "$CFIP_OPENCLASH_BYPASS_IPS_V6" ]] || {
        CFIP_OPENCLASH_BYPASS_CHAIN_V6="$(cfip_openclash_measurement_bypass_discover_chains ipv6)"
        [[ -n "$CFIP_OPENCLASH_BYPASS_CHAIN_V6" ]] || { CFIP_OPENCLASH_BYPASS_ERROR="active OpenClash IPv6 output chain is unavailable or unrecognized"; return 1; }
    }
    token="$(printf '%s' "${CFIP_RUN_ID:-$$-$RANDOM}" | tr -cd 'A-Za-z0-9' | cut -c1-14)"
    [[ -n "$token" ]] || token="$$$RANDOM"
    CFIP_OPENCLASH_BYPASS_COMMENT="cfip_probe_${token}"
    CFIP_OPENCLASH_BYPASS_SET_V4="cfip_${token}_v4"
    CFIP_OPENCLASH_BYPASS_SET_V6="cfip_${token}_v6"
    CFIP_OPENCLASH_BYPASS_UID="$uid"
    CFIP_OPENCLASH_BYPASS_GID="$gid"
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-bypass.XXXXXX")" || return 1
    {
        if [[ -n "$CFIP_OPENCLASH_BYPASS_CHAIN_V4" ]]; then
            printf 'add set inet fw4 %s { type ipv4_addr . inet_service; flags timeout; timeout %ss; }\n' "$CFIP_OPENCLASH_BYPASS_SET_V4" "$CFIP_OPENCLASH_BYPASS_TTL"
            IFS=',' read -r -a _v4_ips <<<"$CFIP_OPENCLASH_BYPASS_IPS_V4"
            for ip in "${_v4_ips[@]}"; do printf 'add element inet fw4 %s { %s . 443 timeout %ss }\n' "$CFIP_OPENCLASH_BYPASS_SET_V4" "$ip" "$CFIP_OPENCLASH_BYPASS_TTL"; done
            for chain in $CFIP_OPENCLASH_BYPASS_CHAIN_V4; do
                printf 'insert rule inet fw4 %s meta skuid %s ip daddr . tcp dport @%s return comment "%s"\n' \
                    "$chain" "$uid" "$CFIP_OPENCLASH_BYPASS_SET_V4" "$CFIP_OPENCLASH_BYPASS_COMMENT"
            done
        fi
        if [[ -n "$CFIP_OPENCLASH_BYPASS_CHAIN_V6" ]]; then
            printf 'add set inet fw4 %s { type ipv6_addr . inet_service; flags timeout; timeout %ss; }\n' "$CFIP_OPENCLASH_BYPASS_SET_V6" "$CFIP_OPENCLASH_BYPASS_TTL"
            IFS=',' read -r -a _v6_ips <<<"$CFIP_OPENCLASH_BYPASS_IPS_V6"
            for ip in "${_v6_ips[@]}"; do printf 'add element inet fw4 %s { %s . 443 timeout %ss }\n' "$CFIP_OPENCLASH_BYPASS_SET_V6" "$ip" "$CFIP_OPENCLASH_BYPASS_TTL"; done
            for chain in $CFIP_OPENCLASH_BYPASS_CHAIN_V6; do
                printf 'insert rule inet fw4 %s meta skuid %s ip6 daddr . tcp dport @%s return comment "%s"\n' \
                    "$chain" "$uid" "$CFIP_OPENCLASH_BYPASS_SET_V6" "$CFIP_OPENCLASH_BYPASS_COMMENT"
            done
        fi
    } >"$tmp" || { rm -f "$tmp"; return 1; }
    if ! nft -c -f "$tmp" >/dev/null 2>&1 || ! nft -f "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        CFIP_OPENCLASH_BYPASS_ERROR="temporary OpenClash measurement rule was rejected"
        cfip_openclash_measurement_bypass_cleanup_owned || true
        return 1
    fi
    rm -f "$tmp"
    CFIP_OPENCLASH_BYPASS_STARTED="$(cfip_monotonic_seconds)" || { cfip_openclash_measurement_bypass_cleanup_owned || true; return 1; }
    CFIP_OPENCLASH_BYPASS_ACTIVE=true
    CFIP_OPENCLASH_MEASUREMENT_BYPASS_USED=true
    cfip_openclash_measurement_bypass_assert || { CFIP_OPENCLASH_BYPASS_ACTIVE=false; cfip_openclash_measurement_bypass_cleanup_owned || true; return 1; }
}

cfip_openclash_measurement_bypass_cleanup_owned() {
    local chain listing handles handle set family_chains
    local -a chains=()
    for family_chains in "$CFIP_OPENCLASH_BYPASS_CHAIN_V4" "$CFIP_OPENCLASH_BYPASS_CHAIN_V6"; do
        [[ -n "$family_chains" ]] || continue
        read -r -a chains <<<"$family_chains"
        for chain in "${chains[@]}"; do
        listing="$(nft -a list chain inet fw4 "$chain" 2>/dev/null || true)"
        handles="$(printf '%s\n' "$listing" | awk -v c="comment \"${CFIP_OPENCLASH_BYPASS_COMMENT}\"" '
            index($0,c) && match($0, /# handle [0-9]+/) { print substr($0,RSTART+9,RLENGTH-9) }')"
        while IFS= read -r handle; do
            [[ "$handle" =~ ^[0-9]+$ ]] || continue
            nft delete rule inet fw4 "$chain" handle "$handle" >/dev/null 2>&1 || return 1
        done <<<"$handles"
        done
    done
    for set in "$CFIP_OPENCLASH_BYPASS_SET_V4" "$CFIP_OPENCLASH_BYPASS_SET_V6"; do
        [[ -n "$set" ]] || continue
        if nft list set inet fw4 "$set" >/dev/null 2>&1; then
            nft delete set inet fw4 "$set" >/dev/null 2>&1 || return 1
        fi
    done
    return 0
}

cfip_openclash_measurement_bypass_end() {
    [[ "$CFIP_OPENCLASH_BYPASS_ACTIVE" == true ]] || return 0
    local error=""
    cfip_openclash_measurement_bypass_assert || error="${CFIP_OPENCLASH_BYPASS_ERROR:-bypass rule was lost; measurement is invalid}"
    cfip_openclash_measurement_bypass_cleanup_owned || {
        CFIP_OPENCLASH_BYPASS_ERROR="could not remove the temporary OpenClash measurement exception"
        return 1
    }
    CFIP_OPENCLASH_BYPASS_ACTIVE=false
    [[ -z "$error" ]] || { CFIP_OPENCLASH_BYPASS_ERROR="$error"; return 1; }
    return 0
}

cfip_openclash_measurement_command() {
    local rc=0
    [[ "$CFIP_OPENCLASH_BYPASS_ACTIVE" == true ]] || { "$@"; return $?; }
    cfip_openclash_measurement_bypass_assert || return 125
    start-stop-daemon -S -c "$CFIP_OPENCLASH_BYPASS_USER:$CFIP_OPENCLASH_BYPASS_GROUP" -x "$CFIP_PROBE_EXEC" -- "$@" || rc=$?
    cfip_openclash_measurement_bypass_assert || return 125
    return "$rc"
}

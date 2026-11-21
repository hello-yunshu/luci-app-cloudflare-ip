#!/usr/bin/env bash
# HomeProxy persistence-only support for exact, audited runtime generations.
# This module never invokes init or reloads the proxy process.

CFIP_HOMEPROXY_SUPPORTED_VERSIONS=('26.300.08316~d72e293' '26.298.29275~c84adb9')
CFIP_HOMEPROXY_NODE_SECTION=''
CFIP_HOMEPROXY_NODE_TYPE=''
CFIP_HOMEPROXY_ORIGINAL_ADDRESS=''
CFIP_HOMEPROXY_BEFORE_ADDRESS=''
CFIP_HOMEPROXY_TARGET_DOMAIN=''
CFIP_HOMEPROXY_ROUTING_MODE=''
CFIP_HOMEPROXY_MAIN_NODE=''
CFIP_HOMEPROXY_MAIN_UDP_NODE=''
CFIP_HOMEPROXY_VERSION=''
CFIP_HOMEPROXY_UPDATED=false

cfip_homeproxy_state_file() {
    printf '%s' "${CFIP_HOMEPROXY_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/homeproxy-managed.json}"
}

cfip_homeproxy_package_version() {
    local output version
    if command -v opkg >/dev/null 2>&1; then
        output="$(opkg status luci-app-homeproxy 2>/dev/null)" || return 1
        version="$(awk '$1 == "Package:" { found = ($2 == "luci-app-homeproxy") }
            found && $1 == "Version:" { print $2; exit }' <<<"$output")"
    elif [[ -r /lib/apk/db/installed ]]; then
        version="$(awk -F: '$1 == "P" { found = ($2 == "luci-app-homeproxy") }
            found && $1 == "V" { print substr($0, 3); exit }' /lib/apk/db/installed)"
    else
        return 1
    fi
    [[ -n "$version" ]] || return 1
    printf '%s' "$version"
}

cfip_homeproxy_version_supported() {
    local version supported_version
    version="$(cfip_homeproxy_package_version)" || {
        CFIP_RECOVERY_ERROR='HomeProxy package version could not be identified reliably'
        return 1
    }
    CFIP_HOMEPROXY_VERSION="$version"
    for supported_version in "${CFIP_HOMEPROXY_SUPPORTED_VERSIONS[@]}"; do
        [[ "$version" == "$supported_version" ]] && break
    done
    [[ "$version" == "$supported_version" ]] || {
        CFIP_RECOVERY_ERROR="Unsupported HomeProxy version: $version (supported: ${CFIP_HOMEPROXY_SUPPORTED_VERSIONS[*]})"
        return 1
    }
    [[ -x "${CFIP_INIT_DIR:-/etc/init.d}/homeproxy" ]] || {
        CFIP_RECOVERY_ERROR='HomeProxy init entry is unavailable'
        return 1
    }
    return 0
}

cfip_homeproxy_environment_json() {
    local version='' installed=false supported=false running=false supported_version
    version="$(cfip_homeproxy_package_version 2>/dev/null || true)"
    if [[ -n "$version" && -x "${CFIP_INIT_DIR:-/etc/init.d}/homeproxy" ]]; then
        installed=true
        for supported_version in "${CFIP_HOMEPROXY_SUPPORTED_VERSIONS[@]}"; do
            [[ "$version" == "$supported_version" ]] && { supported=true; break; }
        done
        [[ "$supported" == true ]] && cfip_service_running homeproxy status && running=true
    fi
    jq -cn --arg version "$version" --argjson installed "$installed" --argjson supported "$supported" --argjson running "$running" \
        '{homeproxy_installed:$installed,homeproxy_supported:$supported,homeproxy_version:(if $version=="" then null else $version end),homeproxy_running:$running}'
}

cfip_homeproxy_normalize_domain() {
    local domain="${1:-}"
    domain="${domain#${domain%%[![:space:]]*}}"
    domain="${domain%${domain##*[![:space:]]}}"
    # BusyBox tr on target images can mis-map lowercase characters when POSIX
    # character classes are used. Domains are ASCII, so request ASCII folding.
    domain="$(printf '%s' "$domain" | tr 'A-Z' 'a-z')"
    [[ ${#domain} -le 253 && "$domain" == *.* &&
       "$domain" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]] || return 1
    printf '%s' "$domain"
}

cfip_homeproxy_read_state() {
    local state_file section
    state_file="$(cfip_homeproxy_state_file)"
    if [[ ! -e "$state_file" && ! -L "$state_file" ]]; then
        printf '%s' '{"schemaVersion":1,"section":null,"domain":null,"originalAddress":null,"lastAddress":null,"nodeType":null}'
        return 0
    fi
    [[ -f "$state_file" && ! -L "$state_file" ]] || return 1
    jq -e 'type=="object" and .schemaVersion==1 and
        ((.section==null) or ((.section|type)=="string")) and
        ((.domain==null) or ((.domain|type)=="string")) and
        ((.originalAddress==null) or ((.originalAddress|type)=="string")) and
        ((.lastAddress==null) or ((.lastAddress|type)=="string")) and
        ((.nodeType==null) or ((.nodeType|type)=="string"))' "$state_file" >/dev/null 2>&1 || return 1
    # OpenWrt's reduced jq build may omit Oniguruma, which removes test()/match()
    # even though those filters work on developer hosts. Validate the bounded
    # UCI identifier with Bash's built-in ERE instead of a jq regex function.
    section="$(jq -r '.section // empty' "$state_file")" || return 1
    [[ -z "$section" || "$section" =~ ^[A-Za-z0-9_]+$ ]] || return 1
    cat "$state_file"
}

cfip_homeproxy_resolve_active_node() {
    local target="$1" state state_section state_domain state_address state_type current_address
    local config_type routing main_node main_udp node_section_type node_type
    cfip_homeproxy_version_supported || return 1
    target="$(cfip_homeproxy_normalize_domain "$target")" || {
        CFIP_RECOVERY_ERROR='HomeProxy target must be one exact DNS hostname'
        return 1
    }
    config_type="$(uci -q get homeproxy.config 2>/dev/null || true)"
    [[ "$config_type" == homeproxy ]] || { CFIP_RECOVERY_ERROR='HomeProxy config section is missing'; return 1; }
    routing="$(uci -q get homeproxy.config.routing_mode 2>/dev/null || true)"
    case "$routing" in
        global|bypass_mainland_china|proxy_mainland_china) ;;
        custom) CFIP_RECOVERY_ERROR='HomeProxy custom routing is unsupported; no nodes were changed'; return 1 ;;
        *) CFIP_RECOVERY_ERROR="Unsupported HomeProxy routing mode: ${routing:-missing}"; return 1 ;;
    esac
    main_node="$(uci -q get homeproxy.config.main_node 2>/dev/null || true)"
    main_udp="$(uci -q get homeproxy.config.main_udp_node 2>/dev/null || true)"
    [[ "$main_node" =~ ^[A-Za-z0-9_]+$ && "$main_node" != urltest && "$main_node" != nil ]] || {
        CFIP_RECOVERY_ERROR='HomeProxy main_node is missing or is a URLTest/special role; no nodes were changed'
        return 1
    }
    [[ "$main_udp" == same || "$main_udp" == "$main_node" ]] || {
        CFIP_RECOVERY_ERROR='HomeProxy has a separate or unsupported UDP node; no nodes were changed'
        return 1
    }
    node_section_type="$(uci -q get "homeproxy.$main_node" 2>/dev/null || true)"
    [[ "$node_section_type" == node ]] || {
        CFIP_RECOVERY_ERROR='HomeProxy main_node does not reference a recognized node section'
        return 1
    }
    node_type="$(uci -q get "homeproxy.$main_node.type" 2>/dev/null || true)"
    # Only the ordinary SOCKS outbound is generator- and runtime-evidenced by
    # the pinned package in the isolated guest. Refuse all other protocols
    # until their UCI-to-sing-box mapping has its own qualification.
    case "$node_type" in
        socks) ;;
        ''|wireguard|urltest|direct|block|nil)
            CFIP_RECOVERY_ERROR="HomeProxy main_node type is not a supported ordinary outbound: ${node_type:-missing}"
            return 1
            ;;
        *) CFIP_RECOVERY_ERROR="HomeProxy main_node protocol is not qualified for persistence-only updates: $node_type"; return 1 ;;
    esac
    current_address="$(uci -q get "homeproxy.$main_node.address" 2>/dev/null || true)"
    [[ -n "$current_address" ]] || { CFIP_RECOVERY_ERROR='HomeProxy main_node address is missing'; return 1; }

    state="$(cfip_homeproxy_read_state)" || { CFIP_RECOVERY_ERROR='HomeProxy ownership state is invalid'; return 1; }
    state_section="$(jq -r '.section // empty' <<<"$state")"
    state_domain="$(jq -r '.domain // empty' <<<"$state")"
    state_address="$(jq -r '.lastAddress // empty' <<<"$state")"
    state_type="$(jq -r '.nodeType // empty' <<<"$state")"
    if [[ -n "$state_section" ]]; then
        [[ "$state_section" == "$main_node" && "$state_domain" == "$target" && "$state_type" == "$node_type" ]] || {
            CFIP_RECOVERY_ERROR='HomeProxy managed node, target, or type changed outside this transaction'
            return 1
        }
        [[ "$current_address" == "$state_address" || "$current_address" == "$state_domain" ]] || {
            CFIP_RECOVERY_ERROR='HomeProxy managed address changed outside this transaction'
            return 1
        }
    else
        [[ "$(cfip_homeproxy_normalize_domain "$current_address" 2>/dev/null || true)" == "$target" ]] || {
            CFIP_RECOVERY_ERROR='Active HomeProxy main_node address does not exactly match the target domain'
            return 1
        }
    fi
    CFIP_HOMEPROXY_TARGET_DOMAIN="$target"
    CFIP_HOMEPROXY_NODE_SECTION="$main_node"
    CFIP_HOMEPROXY_NODE_TYPE="$node_type"
    CFIP_HOMEPROXY_ORIGINAL_ADDRESS="$(jq -r '.originalAddress // empty' <<<"$state")"
    [[ -n "$CFIP_HOMEPROXY_ORIGINAL_ADDRESS" ]] || CFIP_HOMEPROXY_ORIGINAL_ADDRESS="$current_address"
    CFIP_HOMEPROXY_BEFORE_ADDRESS="$current_address"
    CFIP_HOMEPROXY_ROUTING_MODE="$routing"
    CFIP_HOMEPROXY_MAIN_NODE="$main_node"
    CFIP_HOMEPROXY_MAIN_UDP_NODE="$main_udp"
}

cfip_homeproxy_context_matches() {
    local version
    version="$(cfip_homeproxy_package_version)" || return 1
    [[ "$version" == "$CFIP_HOMEPROXY_VERSION" &&
       "$(uci -q get homeproxy.config 2>/dev/null || true)" == homeproxy &&
       "$(uci -q get homeproxy.config.routing_mode 2>/dev/null || true)" == "$CFIP_HOMEPROXY_ROUTING_MODE" &&
       "$(uci -q get homeproxy.config.main_node 2>/dev/null || true)" == "$CFIP_HOMEPROXY_MAIN_NODE" &&
       "$(uci -q get homeproxy.config.main_udp_node 2>/dev/null || true)" == "$CFIP_HOMEPROXY_MAIN_UDP_NODE" &&
       "$(uci -q get "homeproxy.$CFIP_HOMEPROXY_NODE_SECTION" 2>/dev/null || true)" == node &&
       "$(uci -q get "homeproxy.$CFIP_HOMEPROXY_NODE_SECTION.type" 2>/dev/null || true)" == "$CFIP_HOMEPROXY_NODE_TYPE" ]]
}

cfip_homeproxy_pending_is_owned() {
    local changes key before expected before_q expected_q record remaining prefix suffix
    changes="$(uci changes homeproxy 2>/dev/null)" || return 1
    [[ -n "$changes" ]] || return 0
    [[ -f "$CFIP_TXN_DIR/homeproxy-fields.json" ]] || return 1
    key="$(jq -r '.key // empty' "$CFIP_TXN_DIR/homeproxy-fields.json")" || return 1
    [[ -n "$key" ]] || return 1
    before="$(jq -r '.before // empty' "$CFIP_TXN_DIR/homeproxy-fields.json")" || return 1
    expected="$(jq -r '.expected // empty' "$CFIP_TXN_DIR/homeproxy-fields.json")" || return 1
    before_q="$(jq -rn --arg value "$before" '$value|@sh')" || return 1
    expected_q="$(jq -rn --arg value "$expected" '$value|@sh')" || return 1
    remaining=$'\n'"$changes"$'\n'
    for record in "$key=$before_q" "$key=$expected_q"; do
        record=$'\n'"$record"$'\n'
        while [[ "$remaining" == *"$record"* ]]; do
            prefix="${remaining%%"$record"*}"; suffix="${remaining#*"$record"}"
            remaining="$prefix"$'\n'"$suffix"
        done
    done
    [[ -z "${remaining//$'\n'/}" ]]
}

cfip_homeproxy_state_matches_before() {
    local state_file
    state_file="$(cfip_homeproxy_state_file)"
    if [[ "$(cat "$CFIP_TXN_DIR/homeproxy-managed.state" 2>/dev/null)" == present ]]; then
        [[ -f "$state_file" && ! -L "$state_file" ]] && cmp -s "$state_file" "$CFIP_TXN_DIR/homeproxy-managed.json"
    else
        [[ ! -e "$state_file" && ! -L "$state_file" ]]
    fi
}

cfip_homeproxy_apply_selected() {
    local selected="$1" ip family key state state_file pending
    CFIP_HOMEPROXY_UPDATED=false
    [[ -f "$selected" ]] || { CFIP_RECOVERY_ERROR='HomeProxy selected candidates are missing'; return 1; }
    ip="$(jq -r '.[0].ip // empty' "$selected" 2>/dev/null)"
    family="$(jq -r '.[0].family // empty' "$selected" 2>/dev/null)"
    case "$family" in
        ipv4) cfip_is_ipv4 "$ip" || { CFIP_RECOVERY_ERROR='HomeProxy selected IPv4 candidate is invalid'; return 1; } ;;
        ipv6) cfip_is_ipv6 "$ip" || { CFIP_RECOVERY_ERROR='HomeProxy selected IPv6 candidate is invalid'; return 1; } ;;
        *) CFIP_RECOVERY_ERROR='HomeProxy selected candidate family is invalid'; return 1 ;;
    esac
    cfip_homeproxy_pending_is_owned || { CFIP_RECOVERY_ERROR='HomeProxy has unrelated pending UCI changes'; return 1; }
    cfip_homeproxy_context_matches || { CFIP_RECOVERY_ERROR='HomeProxy active node references changed before write'; return 1; }
    key="homeproxy.${CFIP_HOMEPROXY_NODE_SECTION}.address"
    if [[ "$(uci -q get "$key" 2>/dev/null || true)" == "$CFIP_HOMEPROXY_BEFORE_ADDRESS" ]]; then
        :
    elif [[ -n "$(jq -r '.expected // empty' "$CFIP_TXN_DIR/homeproxy-fields.json" 2>/dev/null)" ]]; then
        :
    else
        CFIP_RECOVERY_ERROR='HomeProxy address no longer matches the captured preimage'
        return 1
    fi
    if [[ ! -f "$CFIP_TXN_DIR/homeproxy-fields.json" ]] || [[ -z "$(jq -r '.key // empty' "$CFIP_TXN_DIR/homeproxy-fields.json" 2>/dev/null)" ]]; then
        jq -n --arg key "$key" --arg before "$CFIP_HOMEPROXY_BEFORE_ADDRESS" --arg expected "$ip" \
            '{key:$key,before:$before,expected:$expected}' >"$CFIP_TXN_DIR/homeproxy-fields.json" || return 1
    else
        jq --arg expected "$ip" '.expected=$expected' "$CFIP_TXN_DIR/homeproxy-fields.json" >"$CFIP_TXN_DIR/homeproxy-fields.json.next" &&
            mv "$CFIP_TXN_DIR/homeproxy-fields.json.next" "$CFIP_TXN_DIR/homeproxy-fields.json" || return 1
    fi
    cfip_homeproxy_pending_is_owned || { CFIP_RECOVERY_ERROR='HomeProxy has unrelated pending UCI changes'; return 1; }
    uci set "$key=$ip" || { CFIP_RECOVERY_ERROR='Failed to stage HomeProxy address'; return 1; }
    cfip_homeproxy_pending_is_owned || { CFIP_RECOVERY_ERROR='HomeProxy pending changes conflict with this transaction'; return 1; }
    cfip_homeproxy_context_matches || { CFIP_RECOVERY_ERROR='HomeProxy active node references changed during write'; return 1; }
    [[ "$(uci -q get "$key" 2>/dev/null || true)" == "$ip" ]] || { CFIP_RECOVERY_ERROR='HomeProxy address readback failed'; return 1; }
    uci commit homeproxy || { CFIP_RECOVERY_ERROR='HomeProxy UCI commit failed'; return 1; }
    [[ "$(uci -q get "$key" 2>/dev/null || true)" == "$ip" ]] && cfip_homeproxy_context_matches || {
        CFIP_RECOVERY_ERROR='HomeProxy post-commit readback failed; rollback is required'
        return 1
    }
    [[ -z "$(uci changes homeproxy 2>/dev/null)" ]] || { CFIP_RECOVERY_ERROR='HomeProxy has pending changes after commit'; return 1; }
    state_file="$(cfip_homeproxy_state_file)"
    if [[ -e "$state_file" || -L "$state_file" ]]; then
        cfip_homeproxy_state_matches_before || { CFIP_RECOVERY_ERROR='HomeProxy ownership state changed before commit'; return 1; }
        state="$(cat "$state_file")" || return 1
    else
        state='{"schemaVersion":1,"section":null,"domain":null,"originalAddress":null,"lastAddress":null,"nodeType":null}'
    fi
    pending="$CFIP_TXN_DIR/homeproxy-managed.json.pending"
    jq -n --arg section "$CFIP_HOMEPROXY_NODE_SECTION" --arg domain "$CFIP_HOMEPROXY_TARGET_DOMAIN" \
        --arg original "$CFIP_HOMEPROXY_ORIGINAL_ADDRESS" --arg address "$ip" --arg type "$CFIP_HOMEPROXY_NODE_TYPE" \
        '{schemaVersion:1,section:$section,domain:$domain,originalAddress:$original,lastAddress:$address,nodeType:$type}' >"$pending" || return 1
    cfip_homeproxy_pending_is_owned || return 1
    CFIP_HOMEPROXY_UPDATED=true
}

cfip_homeproxy_restore_fields() {
    local file key before expected current
    file="$CFIP_TXN_DIR/homeproxy-fields.json"
    [[ -f "$file" ]] || return 1
    key="$(jq -r '.key // empty' "$file")" || return 1
    [[ -n "$key" ]] || return 0
    before="$(jq -r '.before' "$file")" || return 1
    expected="$(jq -r '.expected' "$file")" || return 1
    [[ "$key" =~ ^homeproxy\.[A-Za-z0-9_]+\.address$ ]] || return 1
    cfip_homeproxy_pending_is_owned || { CFIP_RECOVERY_ERROR='HomeProxy has unrelated pending changes; preserved them'; return 1; }
    cfip_homeproxy_context_matches || { CFIP_RECOVERY_ERROR='HomeProxy active references changed during rollback; preserved the transaction'; return 1; }
    current="$(uci -q get "$key" 2>/dev/null || true)"
    if [[ "$current" == "$before" ]]; then
        uci -q revert homeproxy >/dev/null 2>&1 || true
    elif [[ "$current" == "$expected" ]]; then
        uci set "$key=$before" || return 1
        cfip_homeproxy_pending_is_owned || { CFIP_RECOVERY_ERROR='HomeProxy rollback conflicts with a user edit'; return 1; }
        uci commit homeproxy || { CFIP_RECOVERY_ERROR='HomeProxy field rollback commit failed'; return 1; }
    else
        CFIP_RECOVERY_ERROR='HomeProxy owned address changed outside this transaction; preserved it and the journal'
        return 1
    fi
    [[ "$(uci -q get "$key" 2>/dev/null || true)" == "$before" ]] || return 1
    cfip_homeproxy_context_matches || return 1
}

cfip_homeproxy_state_safe() {
    local state_file
    state_file="$(cfip_homeproxy_state_file)"
    cfip_homeproxy_state_matches_before && return 0
    if [[ -f "$state_file" && ! -L "$state_file" && -f "$CFIP_TXN_DIR/homeproxy-managed.written.json" ]] &&
       cmp -s "$state_file" "$CFIP_TXN_DIR/homeproxy-managed.written.json"; then return 0; fi
    CFIP_RECOVERY_ERROR='HomeProxy managed state changed outside this transaction; preserved state and journal'
    return 1
}

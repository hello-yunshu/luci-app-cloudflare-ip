#!/usr/bin/env bash
# Fail-closed PassWall2 adapter for a statically enumerable global node graph.
# This module only changes UCI and ownership state; it never invokes init.

CFIP_PASSWALL2_SUPPORTED_VERSION='26.11.11-r1'
CFIP_PW2_ROOT_NODE=''
CFIP_PW2_TARGET_NODE=''
CFIP_PW2_TARGET_PROTOCOL=''
CFIP_PW2_TARGET_DOMAIN=''
CFIP_PW2_BEFORE_ADDRESS=''
CFIP_PW2_ORIGINAL_ADDRESS=''
CFIP_PW2_PACKAGE_VERSION=''
CFIP_PW2_CLOSURE=''
CFIP_PW2_EXPECTED_NODE=''
CFIP_PW2_EXPECTED_ADDRESS=''

cfip_pw2_state_file() {
    printf '%s' "${CFIP_PASSWALL2_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/passwall2-managed.json}"
}

cfip_pw2_package_version() {
    local output version
    if command -v opkg >/dev/null 2>&1; then
        output="$(opkg status luci-app-passwall2 2>/dev/null)" || return 1
        version="$(awk '$1 == "Package:" { found = ($2 == "luci-app-passwall2") }
            found && $1 == "Version:" { print $2; exit }' <<<"$output")"
    elif [[ -r "${CFIP_APK_DB:-/lib/apk/db/installed}" ]]; then
        version="$(awk -F: '$1 == "P" { found = ($2 == "luci-app-passwall2") }
            found && $1 == "V" { print substr($0, 3); exit }' "${CFIP_APK_DB:-/lib/apk/db/installed}")"
    else
        return 1
    fi
    [[ -n "$version" ]] || return 1
    printf '%s' "$version"
}

cfip_pw2_version_supported() {
    local version
    version="$(cfip_pw2_package_version)" || { CFIP_RECOVERY_ERROR='PassWall2 package version could not be identified reliably'; return 1; }
    CFIP_PW2_PACKAGE_VERSION="$version"
    [[ "$version" == "$CFIP_PASSWALL2_SUPPORTED_VERSION" ]] || {
        CFIP_RECOVERY_ERROR="Unsupported PassWall2 version: $version (supported: $CFIP_PASSWALL2_SUPPORTED_VERSION)"
        return 1
    }
    [[ -x "${CFIP_INIT_DIR:-/etc/init.d}/passwall2" ]] || { CFIP_RECOVERY_ERROR='PassWall2 init entry is unavailable'; return 1; }
}

cfip_pw2_environment_json() {
    local version='' installed=false supported=false running=false
    version="$(cfip_pw2_package_version 2>/dev/null || true)"
    if [[ -n "$version" && -x "${CFIP_INIT_DIR:-/etc/init.d}/passwall2" ]]; then
        installed=true
        [[ "$version" == "$CFIP_PASSWALL2_SUPPORTED_VERSION" ]] && supported=true
        [[ "$supported" == true ]] && cfip_service_running passwall2 status && running=true
    fi
    jq -cn --arg version "$version" --argjson installed "$installed" --argjson supported "$supported" --argjson running "$running" \
        '{passwall2_installed:$installed,passwall2_supported:$supported,passwall2_version:(if $version=="" then null else $version end),passwall2_running:$running}'
}

cfip_pw2_normalize_target() {
    local domain="${1:-}"
    domain="${domain#"${domain%%[![:space:]]*}"}"
    domain="${domain%"${domain##*[![:space:]]}"}"
    # BusyBox tr on the target image mishandles locale character classes on
    # some builds (for example, mapping `p` to `w`). Keep the hostname fold
    # explicitly ASCII, matching the DNS label grammar below.
    domain="$(printf '%s' "$domain" | tr 'A-Z' 'a-z')"
    [[ ${#domain} -le 253 && "$domain" == *.* &&
       "$domain" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]] || return 1
    printf '%s' "$domain"
}

cfip_pw2_read_state() {
    local state_file
    state_file="$(cfip_pw2_state_file)"
    if [[ ! -e "$state_file" && ! -L "$state_file" ]]; then
        printf '%s' '{"schemaVersion":1,"rootNode":null,"node":null,"domain":null,"originalAddress":null,"lastAddress":null,"protocol":null,"packageVersion":null}'
        return 0
    fi
    [[ -f "$state_file" && ! -L "$state_file" ]] || return 1
    jq -e 'type=="object" and .schemaVersion==1 and
      ((.rootNode==null) or ((.rootNode|type)=="string")) and
      ((.node==null) or ((.node|type)=="string")) and
      ((.domain==null) or ((.domain|type)=="string")) and
      ((.originalAddress==null) or ((.originalAddress|type)=="string")) and
      ((.lastAddress==null) or ((.lastAddress|type)=="string")) and
      ((.protocol==null) or ((.protocol|type)=="string")) and
      ((.packageVersion==null) or ((.packageVersion|type)=="string"))' "$state_file" >/dev/null 2>&1 || return 1
    cat "$state_file"
}

cfip_pw2_known_leaf_protocol() {
    case "$1" in
      direct|block|socks|http|shadowsocks|shadowsocksr|trojan|vmess|vless|wireguard|hysteria|hysteria2|tuic|naive|shadowtls|anytls|snell|masque|ssh) return 0 ;;
      *) return 1 ;;
    esac
}

CFIP_PW2_WALK_VISITED=''
CFIP_PW2_WALK_STACK=''
CFIP_PW2_WALK_LEAVES=''
CFIP_PW2_WALK_EDGES=''
CFIP_PW2_MATCHES=''

cfip_pw2_walk_node() {
    local node="$1" depth="${2:-0}" type protocol default_node group rules rule_id rule_group ref option value address normalized_address
    [[ "$node" =~ ^[A-Za-z0-9_-]+$ ]] || { CFIP_RECOVERY_ERROR="PassWall2 graph contains an invalid node reference: $node"; return 1; }
    case "|$CFIP_PW2_WALK_STACK|" in *"|$node|"*) CFIP_RECOVERY_ERROR="PassWall2 graph contains a cycle at $node"; return 1 ;; esac
    case "|$CFIP_PW2_WALK_VISITED|" in *"|$node|"*) return 0 ;; esac
    ((depth <= 16)) || { CFIP_RECOVERY_ERROR='PassWall2 graph exceeds the supported static traversal depth'; return 1; }
    type="$(uci -q get "passwall2.$node" 2>/dev/null || true)"
    [[ "$type" == nodes ]] || { CFIP_RECOVERY_ERROR="PassWall2 active reference $node is missing or is not a nodes section"; return 1; }
    protocol="$(uci -q get "passwall2.$node.protocol" 2>/dev/null || true)"
    [[ -n "$protocol" ]] || { CFIP_RECOVERY_ERROR="PassWall2 active node $node has no protocol"; return 1; }
    CFIP_PW2_WALK_VISITED+="$node|"
    CFIP_PW2_WALK_STACK+="$node|"
    if [[ "$protocol" == _shunt ]]; then
        group="$(uci -q get "passwall2.$node.shunt_group" 2>/dev/null || true)"
        [[ -n "$group" ]] || { CFIP_RECOVERY_ERROR="PassWall2 shunt node $node has no shunt_group"; return 1; }
        CFIP_PW2_WALK_EDGES+="$node:group:$group|"
        default_node="$(uci -q get "passwall2.$node.default_node" 2>/dev/null || true)"
        [[ -n "$default_node" ]] || default_node=_direct
        CFIP_PW2_WALK_EDGES+="$node:default:$default_node|"
        case "$default_node" in _direct|_blackhole) ;; _default|nil) CFIP_RECOVERY_ERROR="PassWall2 shunt node $node has an invalid default_node"; return 1 ;; *) cfip_pw2_walk_node "$default_node" "$((depth+1))" || return 1 ;; esac
        rules="$(uci -q show passwall2 2>/dev/null | sed -n 's/^passwall2\.\([A-Za-z0-9_-][A-Za-z0-9_-]*\)=shunt_rules$/\1/p' | LC_ALL=C sort)"
        while IFS= read -r rule_id; do
            [[ -n "$rule_id" ]] || continue
            rule_group="$(uci -q get "passwall2.$rule_id.group" 2>/dev/null || true)"
            [[ "$rule_group" == "$group" ]] || continue
            option="$(uci -q get "passwall2.$rule_id.remarks" 2>/dev/null || true)"
            [[ -n "$option" ]] || continue
            ref="$(uci -q get "passwall2.$node.$rule_id" 2>/dev/null || true)"
            [[ -n "$ref" ]] || continue
            CFIP_PW2_WALK_EDGES+="$node:rule:$rule_id:$ref|"
            case "$ref" in
              _direct|_blackhole|_default) ;;
              nil) CFIP_RECOVERY_ERROR="PassWall2 shunt rule $rule_id contains nil as its outbound"; return 1 ;;
              *) cfip_pw2_walk_node "$ref" "$((depth+1))" || return 1 ;;
            esac
        done <<<"$rules"
    else
        case "$protocol" in
          _urltest|_balancing|_iface|urltest|balancing|iface)
            CFIP_RECOVERY_ERROR="PassWall2 active $protocol node $node is not statically enumerable"; return 1 ;;
          _*) CFIP_RECOVERY_ERROR="PassWall2 active special protocol $protocol is unsupported"; return 1 ;;
        esac
        cfip_pw2_known_leaf_protocol "$protocol" || { CFIP_RECOVERY_ERROR="PassWall2 active leaf protocol is unknown: $protocol"; return 1; }
        for option in chain_proxy preproxy_node to_node outbound_node outbound_node_address outbound_iface node_add_mode; do
            value="$(uci -q get "passwall2.$node.$option" 2>/dev/null || true)"
            case "$option:$value" in
              chain_proxy:|chain_proxy:0|node_add_mode:|node_add_mode:0) ;;
              *:*) [[ -z "$value" ]] || { CFIP_RECOVERY_ERROR="PassWall2 active leaf $node uses unsupported $option=$value"; return 1; } ;;
            esac
        done
        if [[ "$protocol" != direct && "$protocol" != block ]]; then
            address="$(uci -q get "passwall2.$node.address" 2>/dev/null || true)"
            [[ -n "$address" ]] || { CFIP_RECOVERY_ERROR="PassWall2 active leaf $node has no address"; return 1; }
            CFIP_PW2_WALK_LEAVES+="$node:$protocol:$address|"
            normalized_address="$(cfip_pw2_normalize_target "$address" 2>/dev/null || true)"
            if [[ "$normalized_address" == "$CFIP_PW2_RESOLVE_DOMAIN" || \
                  ( "$node" == "$CFIP_PW2_STATE_NODE" && ( "$address" == "$CFIP_PW2_STATE_LAST" || "$(cfip_pw2_normalize_target "$address" 2>/dev/null || true)" == "$CFIP_PW2_RESOLVE_DOMAIN" ) ) || \
                  ( "$node" == "$CFIP_PW2_EXPECTED_NODE" && "$address" == "$CFIP_PW2_EXPECTED_ADDRESS" ) ]]; then
                [[ "$protocol" == socks ]] || { CFIP_RECOVERY_ERROR="PassWall2 matching target leaf $node protocol $protocol is not qualified; only SOCKS leaves are currently runtime-tested"; return 1; }
                CFIP_PW2_MATCHES+="$node"$'\n'
            fi
        fi
    fi
    CFIP_PW2_WALK_STACK="${CFIP_PW2_WALK_STACK%"$node"|}"
    return 0
}

cfip_pw2_resolve_target() {
    local target="$1" state config_type acl_enabled socks_enabled global_enabled root section address protocol matches count
    cfip_pw2_version_supported || return 1
    target="$(cfip_pw2_normalize_target "$target")" || { CFIP_RECOVERY_ERROR='PassWall2 requires one exact target hostname'; return 1; }
    config_type="$(uci -q get passwall2.@global[0] 2>/dev/null || true)"
    [[ "$config_type" == global ]] || { CFIP_RECOVERY_ERROR='PassWall2 global section is missing'; return 1; }
    acl_enabled="$(uci -q get passwall2.@global[0].acl_enable 2>/dev/null || printf 0)"
    socks_enabled="$(uci -q get passwall2.@global[0].socks_enabled 2>/dev/null || printf 0)"
    global_enabled="$(uci -q get passwall2.@global[0].enabled 2>/dev/null || printf 0)"
    [[ "$acl_enabled" == 0 && "$socks_enabled" == 0 ]] || { CFIP_RECOVERY_ERROR='PassWall2 ACL or extra SOCKS services are active; their node roots are not included in this limited adapter'; return 1; }
    [[ "$global_enabled" == 0 || "$global_enabled" == 1 ]] || { CFIP_RECOVERY_ERROR='PassWall2 global enabled state is invalid'; return 1; }
    root="$(uci -q get passwall2.@global[0].node 2>/dev/null || true)"
    [[ -n "$root" && "$root" != nil ]] || { CFIP_RECOVERY_ERROR='PassWall2 global node is missing'; return 1; }
    state="$(cfip_pw2_read_state)" || { CFIP_RECOVERY_ERROR='PassWall2 ownership state is invalid'; return 1; }
    CFIP_PW2_STATE_NODE="$(jq -r '.node // empty' <<<"$state")"
    CFIP_PW2_STATE_LAST="$(jq -r '.lastAddress // empty' <<<"$state")"
    section="$(jq -r '.rootNode // empty' <<<"$state")"
    if [[ -n "$(jq -r '.node // empty' <<<"$state")" ]]; then
        [[ "$section" == "$root" && "$(jq -r '.domain // empty' <<<"$state")" == "$target" && \
           "$(jq -r '.packageVersion // empty' <<<"$state")" == "$CFIP_PW2_PACKAGE_VERSION" && \
           "$(jq -r '.protocol // empty' <<<"$state")" == socks ]] || { CFIP_RECOVERY_ERROR='PassWall2 managed graph, target, protocol, or package changed outside CFI'; return 1; }
    fi
    CFIP_PW2_ROOT_NODE="$root"
    CFIP_PW2_TARGET_DOMAIN="$target"
    CFIP_PW2_RESOLVE_DOMAIN="$target"
    CFIP_PW2_WALK_VISITED=''; CFIP_PW2_WALK_STACK=''; CFIP_PW2_WALK_LEAVES=''; CFIP_PW2_WALK_EDGES=''; CFIP_PW2_MATCHES=''
    cfip_pw2_walk_node "$root" 0 || return 1
    matches="$(printf '%s' "$CFIP_PW2_MATCHES" | sed '/^$/d')"
    count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
    [[ "$count" == 1 ]] || { CFIP_RECOVERY_ERROR="PassWall2 active graph has $count exact target SOCKS leaves; exactly one is required"; return 1; }
    CFIP_PW2_TARGET_NODE="$matches"
    protocol="$(uci -q get "passwall2.$CFIP_PW2_TARGET_NODE.protocol" 2>/dev/null || true)"
    address="$(uci -q get "passwall2.$CFIP_PW2_TARGET_NODE.address" 2>/dev/null || true)"
    if [[ -n "$CFIP_PW2_STATE_NODE" ]]; then
        [[ "$CFIP_PW2_STATE_NODE" == "$CFIP_PW2_TARGET_NODE" && ( "$address" == "$CFIP_PW2_STATE_LAST" || "$(cfip_pw2_normalize_target "$address" 2>/dev/null || true)" == "$target" || ( "$CFIP_PW2_EXPECTED_NODE" == "$CFIP_PW2_TARGET_NODE" && "$address" == "$CFIP_PW2_EXPECTED_ADDRESS" ) ) ]] || { CFIP_RECOVERY_ERROR='PassWall2 managed address changed outside CFI'; return 1; }
        CFIP_PW2_ORIGINAL_ADDRESS="$(jq -r '.originalAddress // empty' <<<"$state")"
    else
        [[ "$(cfip_pw2_normalize_target "$address" 2>/dev/null || true)" == "$target" || ( "$CFIP_PW2_EXPECTED_NODE" == "$CFIP_PW2_TARGET_NODE" && "$address" == "$CFIP_PW2_EXPECTED_ADDRESS" ) ]] || { CFIP_RECOVERY_ERROR='PassWall2 active target leaf address does not exactly match the requested hostname'; return 1; }
        CFIP_PW2_ORIGINAL_ADDRESS="$address"
    fi
    CFIP_PW2_TARGET_PROTOCOL="$protocol"
    CFIP_PW2_BEFORE_ADDRESS="$address"
    CFIP_PW2_CLOSURE="$CFIP_PW2_WALK_EDGES$CFIP_PW2_WALK_LEAVES"
}

cfip_pw2_context_matches() {
    local version root old_node old_closure old_root old_target old_protocol old_before old_original old_package old_domain old_signature new_signature
    version="$(cfip_pw2_package_version 2>/dev/null || true)"
    [[ "$version" == "$CFIP_PW2_PACKAGE_VERSION" ]] || return 1
    root="$(uci -q get passwall2.@global[0].node 2>/dev/null || true)"
    [[ "$root" == "$CFIP_PW2_ROOT_NODE" ]] || return 1
    old_node="$CFIP_PW2_TARGET_NODE"; old_closure="$CFIP_PW2_CLOSURE"
    old_root="$CFIP_PW2_ROOT_NODE"; old_target="$CFIP_PW2_TARGET_DOMAIN"; old_protocol="$CFIP_PW2_TARGET_PROTOCOL"
    old_before="$CFIP_PW2_BEFORE_ADDRESS"; old_original="$CFIP_PW2_ORIGINAL_ADDRESS"; old_package="$CFIP_PW2_PACKAGE_VERSION"; old_domain="$CFIP_PW2_RESOLVE_DOMAIN"
    local rc=0
    if cfip_pw2_resolve_target "$old_target"; then
        new_signature="$(cfip_pw2_canonical_closure "$CFIP_PW2_CLOSURE" "$old_node")"
        old_signature="$(cfip_pw2_canonical_closure "$old_closure" "$old_node")"
        [[ "$CFIP_PW2_TARGET_NODE" == "$old_node" && "$new_signature" == "$old_signature" ]] || rc=1
    else
        rc=1
    fi
    CFIP_PW2_TARGET_NODE="$old_node"; CFIP_PW2_CLOSURE="$old_closure"; CFIP_PW2_ROOT_NODE="$old_root"
    CFIP_PW2_TARGET_DOMAIN="$old_target"; CFIP_PW2_TARGET_PROTOCOL="$old_protocol"; CFIP_PW2_BEFORE_ADDRESS="$old_before"
    CFIP_PW2_ORIGINAL_ADDRESS="$old_original"; CFIP_PW2_PACKAGE_VERSION="$old_package"; CFIP_PW2_RESOLVE_DOMAIN="$old_domain"
    return "$rc"
}

cfip_pw2_canonical_closure() {
    local list="$1" target_node="$2" entry node tail proto result=''
    local -a entries
    IFS='|' read -r -a entries <<<"$list"
    for entry in "${entries[@]}"; do
        [[ -n "$entry" ]] || continue
        node="${entry%%:*}"; tail="${entry#*:}"; proto="${tail%%:*}"
        [[ "$node" != "$target_node" ]] || entry="$node:$proto:@CFI_TARGET@"
        result+="$entry|"
    done
    printf '%s' "$result"
}

cfip_pw2_state_matches_before() {
    local file
    file="$(cfip_pw2_state_file)"
    if [[ "$(cat "$CFIP_TXN_DIR/passwall2-managed.state" 2>/dev/null)" == present ]]; then
        [[ -f "$file" && ! -L "$file" ]] && cmp -s "$file" "$CFIP_TXN_DIR/passwall2-managed.json"
    else
        [[ ! -e "$file" && ! -L "$file" ]]
    fi
}

cfip_pw2_pending_is_owned() {
    local changes key before expected before_q expected_q remaining record prefix suffix
    changes="$(uci changes passwall2 2>/dev/null)" || return 1
    [[ -n "$changes" ]] || return 0
    [[ -f "$CFIP_TXN_DIR/passwall2-fields.json" ]] || return 1
    key="$(jq -r '.key // empty' "$CFIP_TXN_DIR/passwall2-fields.json")" || return 1
    [[ -n "$key" ]] || return 1
    before="$(jq -r '.before // empty' "$CFIP_TXN_DIR/passwall2-fields.json")" || return 1
    expected="$(jq -r '.expected // empty' "$CFIP_TXN_DIR/passwall2-fields.json")" || return 1
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

cfip_pw2_apply_selected() {
    local selected="$1" ip family key state_file state pending
    [[ -f "$selected" ]] || { CFIP_RECOVERY_ERROR='PassWall2 selected candidates are missing'; return 1; }
    ip="$(jq -r '.[0].ip // empty' "$selected" 2>/dev/null)"
    family="$(jq -r '.[0].family // empty' "$selected" 2>/dev/null)"
    case "$family" in
      ipv4) cfip_is_ipv4 "$ip" || { CFIP_RECOVERY_ERROR='PassWall2 selected IPv4 candidate is invalid'; return 1; } ;;
      ipv6) cfip_is_ipv6 "$ip" || { CFIP_RECOVERY_ERROR='PassWall2 selected IPv6 candidate is invalid'; return 1; } ;;
      *) CFIP_RECOVERY_ERROR='PassWall2 selected candidate family is invalid'; return 1 ;;
    esac
    cfip_pw2_pending_is_owned || { CFIP_RECOVERY_ERROR='PassWall2 has unrelated pending UCI changes'; return 1; }
    cfip_pw2_context_matches || { CFIP_RECOVERY_ERROR='PassWall2 package or active graph changed before write'; return 1; }
    key="passwall2.$CFIP_PW2_TARGET_NODE.address"
    CFIP_PW2_EXPECTED_NODE="$CFIP_PW2_TARGET_NODE"; CFIP_PW2_EXPECTED_ADDRESS="$ip"
    [[ "$(uci -q get "$key" 2>/dev/null || true)" == "$CFIP_PW2_BEFORE_ADDRESS" ]] || { CFIP_RECOVERY_ERROR='PassWall2 target leaf changed before write'; return 1; }
    if [[ ! -f "$CFIP_TXN_DIR/passwall2-fields.json" ]] || [[ -z "$(jq -r '.key // empty' "$CFIP_TXN_DIR/passwall2-fields.json" 2>/dev/null)" ]]; then
        jq -n --arg key "$key" --arg before "$CFIP_PW2_BEFORE_ADDRESS" --arg expected "$ip" '{key:$key,before:$before,expected:$expected}' >"$CFIP_TXN_DIR/passwall2-fields.json" || return 1
    else
        jq --arg expected "$ip" '.expected=$expected' "$CFIP_TXN_DIR/passwall2-fields.json" >"$CFIP_TXN_DIR/passwall2-fields.json.next" && mv "$CFIP_TXN_DIR/passwall2-fields.json.next" "$CFIP_TXN_DIR/passwall2-fields.json" || return 1
    fi
    cfip_pw2_pending_is_owned || { CFIP_RECOVERY_ERROR='PassWall2 pending changes conflict with this transaction'; return 1; }
    uci set "$key=$ip" || { CFIP_RECOVERY_ERROR='Failed to stage PassWall2 target address'; return 1; }
    if ! cfip_pw2_pending_is_owned || ! cfip_pw2_context_matches; then CFIP_RECOVERY_ERROR='PassWall2 active graph changed during write'; return 1; fi
    [[ "$(uci -q get "$key" 2>/dev/null || true)" == "$ip" ]] || { CFIP_RECOVERY_ERROR='PassWall2 address readback failed'; return 1; }
    uci commit passwall2 || { CFIP_RECOVERY_ERROR='PassWall2 UCI commit failed'; return 1; }
    if [[ "$(uci -q get "$key" 2>/dev/null || true)" != "$ip" ]] || ! cfip_pw2_context_matches; then CFIP_RECOVERY_ERROR='PassWall2 post-commit readback failed'; return 1; fi
    [[ -z "$(uci changes passwall2 2>/dev/null)" ]] || { CFIP_RECOVERY_ERROR='PassWall2 has pending changes after commit'; return 1; }
    state_file="$(cfip_pw2_state_file)"
    if [[ -e "$state_file" || -L "$state_file" ]]; then
        cfip_pw2_state_matches_before || { CFIP_RECOVERY_ERROR='PassWall2 ownership state changed before commit'; return 1; }
        state="$(cat "$state_file")" || return 1
    else
        state='{"schemaVersion":1,"rootNode":null,"node":null,"domain":null,"originalAddress":null,"lastAddress":null,"protocol":null,"packageVersion":null}'
    fi
    pending="$CFIP_TXN_DIR/passwall2-managed.json.pending"
    jq -n --arg root "$CFIP_PW2_ROOT_NODE" --arg node "$CFIP_PW2_TARGET_NODE" --arg domain "$CFIP_PW2_TARGET_DOMAIN" \
      --arg original "$CFIP_PW2_ORIGINAL_ADDRESS" --arg address "$ip" --arg version "$CFIP_PW2_PACKAGE_VERSION" \
      '{schemaVersion:1,rootNode:$root,node:$node,domain:$domain,originalAddress:$original,lastAddress:$address,protocol:"socks",packageVersion:$version}' >"$pending" || return 1
}

cfip_pw2_restore_fields() {
    local file key before expected current
    file="$CFIP_TXN_DIR/passwall2-fields.json"
    [[ -f "$file" ]] || return 1
    key="$(jq -r '.key // empty' "$file")" || return 1
    [[ -n "$key" ]] || return 0
    before="$(jq -r '.before // empty' "$file")" || return 1
    expected="$(jq -r '.expected // empty' "$file")" || return 1
    [[ "$key" == "passwall2.$CFIP_PW2_TARGET_NODE.address" ]] || return 1
    CFIP_PW2_EXPECTED_NODE="$CFIP_PW2_TARGET_NODE"; CFIP_PW2_EXPECTED_ADDRESS="$expected"
    cfip_pw2_pending_is_owned || { CFIP_RECOVERY_ERROR='PassWall2 has unrelated pending changes; preserved them'; return 1; }
    cfip_pw2_context_matches || { CFIP_RECOVERY_ERROR='PassWall2 active graph changed during rollback; preserved transaction evidence'; return 1; }
    current="$(uci -q get "$key" 2>/dev/null || true)"
    if [[ "$current" == "$before" ]]; then
        :
    elif [[ "$current" == "$expected" ]]; then
        uci set "$key=$before" || return 1
        cfip_pw2_pending_is_owned || { CFIP_RECOVERY_ERROR='PassWall2 rollback conflicts with a user edit'; return 1; }
        uci commit passwall2 || { CFIP_RECOVERY_ERROR='PassWall2 field rollback commit failed'; return 1; }
    else
        CFIP_RECOVERY_ERROR='PassWall2 owned target address changed outside CFI; preserved current value and journal'
        return 1
    fi
    [[ "$(uci -q get "$key" 2>/dev/null || true)" == "$before" ]] || return 1
    cfip_pw2_context_matches || return 1
}

cfip_pw2_state_safe() {
    local state_file
    state_file="$(cfip_pw2_state_file)"
    cfip_pw2_state_matches_before && return 0
    if [[ -f "$state_file" && ! -L "$state_file" && -f "$CFIP_TXN_DIR/passwall2-managed.written.json" ]] &&
       cmp -s "$state_file" "$CFIP_TXN_DIR/passwall2-managed.written.json"; then return 0; fi
    CFIP_RECOVERY_ERROR='PassWall2 managed state changed outside this transaction; preserved state and journal'
    return 1
}

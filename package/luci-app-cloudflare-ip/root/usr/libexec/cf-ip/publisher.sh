#!/usr/bin/env bash
# shellcheck shell=bash

CFIP_PUBLISH_DIR="${CFIP_PUBLISH_DIR:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publish}"
CFIP_PUBLISH_STATUS_FILE="${CFIP_PUBLISH_STATUS_FILE:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publisher-status.json}"
CFIP_PUBLISH_INIT="${CFIP_PUBLISH_INIT:-/etc/init.d/cf_ip_publisher}"

cfip_publisher_directory_mode() {
    local mode
    mode="$(LC_ALL=C ls -ld "$1")" || return 1
    mode="${mode%% *}"
    [[ "$mode" =~ ^d[rwxstST-]{9} ]] || return 1
    printf '%s' "${mode:0:10}"
}

cfip_publisher_workspace_root() {
    local parent root mode tag=cf-ip-publisher-work-v1
    [[ "$CFIP_PUBLISH_DIR" == /* && "$CFIP_PUBLISH_DIR" != / && "$CFIP_PUBLISH_DIR" != */ ]] || return 1
    parent="${CFIP_PUBLISH_DIR%/*}"; root="$parent/.cfip-publisher-work"
    [[ -d "$parent" && ! -L "$parent" ]] || return 1
    [[ -O "$parent" ]] || return 1
    mode="$(cfip_publisher_directory_mode "$parent")" || return 1
    [[ "${mode:5:1}${mode:8:1}" != *w* || "${mode:9:1}" == [tT] ]] || return 1
    [[ ! -L "$root" ]] || return 1
    if [[ ! -e "$root" ]]; then mkdir -m 700 "$root" 2>/dev/null || [[ -d "$root" && ! -L "$root" ]] || return 1; fi
    [[ -d "$root" && -O "$root" ]] || return 1
    mode="$(cfip_publisher_directory_mode "$root")" || return 1
    [[ "${mode:5:1}${mode:8:1}" != *w* ]] || return 1
    if [[ ! -L "$root/.owner" || "$(readlink "$root/.owner")" != "$tag" ]]; then
        [[ ! -e "$root/.owner" && ! -L "$root/.owner" ]] || return 1
        if [[ -n "$(find "$root" -mindepth 1 -maxdepth 1 -print | head -n 1)" ]]; then
            [[ -L "$root/.owner" && "$(readlink "$root/.owner")" == "$tag" ]] || return 1
        else
            ln -s "$tag" "$root/.owner" 2>/dev/null || { [[ -L "$root/.owner" && "$(readlink "$root/.owner")" == "$tag" ]] || return 1; }
        fi
    fi
    chmod 700 "$root" || return 1
    printf '%s' "$root"
}

cfip_publisher_workspace_pid() {
    local name="${1##*/}"
    name="${name#.reap.}"
    [[ "$name" =~ ^(stage|link|readback)\.([1-9][0-9]{0,9})\.[A-Za-z0-9]{6}$ ]] || return 1
    printf '%s' "${BASH_REMATCH[2]}"
}

cfip_publisher_workspace_alive() {
    kill -0 "$1" 2>/dev/null || [[ -d "/proc/$1" ]]
}

# First detach a dead owner's path atomically. An orphaned external mv can
# then either have completed before us, or fail to find its old source path.
cfip_publisher_workspace_reap() {
    local dir="$1" root="${1%/*}" name="${1##*/}" pid quarantine
    [[ -d "$dir" && ! -L "$dir" && -O "$dir" ]] || return 0
    pid="$(cfip_publisher_workspace_pid "$name")" || return 0
    if [[ "$name" != .reap.* ]]; then
        cfip_publisher_workspace_alive "$pid" && return 0
        quarantine="$root/.reap.$name"
        [[ ! -e "$quarantine" && ! -L "$quarantine" ]] || return 0
        case "$(uname -s)" in
            Darwin) mv -fh "$dir" "$quarantine" 2>/dev/null || { [[ ! -e "$dir" ]] && return 0; return 1; } ;;
            *) mv -fT "$dir" "$quarantine" 2>/dev/null || { [[ ! -e "$dir" ]] && return 0; return 1; } ;;
        esac
        dir="$quarantine"
    fi
    rm -rf "$dir"
}

cfip_publisher_workspace_sweep() {
    local root="$1" dir
    # Only owned PID-framed directories are candidates; unknown entries remain.
    while IFS= read -r dir; do cfip_publisher_workspace_reap "$dir" || return 1; done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print | head -n 64)
}

cfip_publisher_workspace_create() {
    local kind="$1" pid="$2" root dir count
    case "$kind" in stage|link|readback) ;; *) return 1 ;; esac
    [[ "$pid" =~ ^[1-9][0-9]{0,9}$ ]] && cfip_publisher_workspace_alive "$pid" || return 1
    root="$(cfip_publisher_workspace_root)" || return 1
    cfip_publisher_workspace_sweep "$root" || return 1
    dir="$(mktemp -d "$root/$kind.$pid.XXXXXX")" || return 1
    # Reserve the empty directory BEFORE counting. Concurrent reservations are
    # visible to each other; rejected reservations never receive payload bytes.
    # Unknown directories also consume capacity rather than being deleted.
    count="$(find "$root" -mindepth 1 -maxdepth 1 -type d -print | head -n 17 | wc -l)" || { rm -rf "$dir"; return 1; }
    if ((count <= 16)); then printf '%s' "$dir"; return 0; fi
    rm -rf "$dir"
    return 1
}

cfip_publisher_resolve_bind() {
    local bind="$1" status address
    if [[ -n "$bind" && "$bind" != lan-auto ]]; then
        [[ "$bind" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && ! "$bind" =~ (^|\.)0[0-9] ]] && cfip_is_ipv4 "$bind" || return 1
        printf '%s' "$bind"; return 0
    fi
    status="$(ubus -t 1 call network.interface.lan status 2>/dev/null)" || return 1
    jq -e '.up==true' <<<"$status" >/dev/null || return 1
    while IFS= read -r address; do
        [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && ! "$address" =~ (^|\.)0[0-9] ]] && cfip_is_ipv4 "$address" || continue
        case "$address" in 10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) printf '%s' "$address"; return 0 ;; esac
    done < <(jq -r '.["ipv4-address"][]?.address // empty' <<<"$status")
    return 1
}

# Init exit status is not listener readiness. Verify bounded bytes from the
# resolved endpoint against the result just published; never use HTTP proxies.
cfip_publisher_wait_ready() {
    local bind="$1" port="$2" expected="$3" path="${4:-/result.json}" tmp bytes attempt generation count attempts="${CFIP_PUBLISH_READY_ATTEMPTS:-3}"
    local -a statuses
    local lease_pid="${BASHPID:-$$}"
    [[ "$attempts" =~ ^[1-5]$ && "$port" =~ ^[0-9]{1,5}$ ]] || return 1
    port=$((10#$port)); ((port >= 1024 && port <= 65535)) || return 1
    bind="$(cfip_publisher_resolve_bind "$bind")" || return 1
    tmp="$(cfip_publisher_workspace_create readback "$lease_pid")" || return 1
    head -c 1048577 "$expected" >"$tmp/expected" || { rm -rf "$tmp"; return 1; }
    bytes="$(wc -c <"$tmp/expected")" || { rm -rf "$tmp"; return 1; }
    if ! ((bytes > 0 && bytes <= 1048576)) || ! jq -e '.schemaVersion==1 and (.ips|type)=="array" and (.selected|type)=="array"' "$tmp/expected" >/dev/null 2>&1; then rm -rf "$tmp"; return 1; fi
    generation="$(jq -r '.generation // empty' "$tmp/expected")" || { rm -rf "$tmp"; return 1; }
    [[ -z "$generation" || "$generation" =~ ^gen\.[0-9a-f]{64}$ ]] || { rm -rf "$tmp"; return 1; }
    for ((attempt=1; attempt<=attempts; attempt++)); do
        if curl -fsS --noproxy '*' --connect-timeout 1 --max-time 1 "http://$bind:$port$path" 2>/dev/null |
            head -c "$((bytes+1))" >"$tmp/body"; then statuses=("${PIPESTATUS[@]}"); else statuses=("${PIPESTATUS[@]}"); fi
        if ((statuses[0] == 0 && statuses[1] == 0)) && cmp -s "$tmp/expected" "$tmp/body"; then
            count="$(jq '.selected|length' "$tmp/expected")" || { rm -rf "$tmp"; return 1; }
            CFIP_PUBLISH_EFFECTIVE_BIND="$bind"; CFIP_PUBLISH_EFFECTIVE_GENERATION="$generation"; CFIP_PUBLISH_EFFECTIVE_COUNT="$count"
            rm -rf "$tmp"; return 0
        fi
        ((attempt == attempts)) || sleep 1
    done
    rm -rf "$tmp"
    return 1
}

# Return 0 when a TCP/HTTP endpoint still responds, 1 when unreachable, 2
# when its address cannot be resolved. This never stops a service itself.
cfip_publisher_endpoint_open() {
    local bind="$1" port="$2" remote
    bind="$(cfip_publisher_resolve_bind "$bind")" || return 2
    [[ "$bind" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && "$port" =~ ^[0-9]{1,5}$ ]] || return 2
    port=$((10#$port))
    ((port >= 1024 && port <= 65535)) || return 2
    remote="$(curl --noproxy '*' -IsS --connect-timeout 1 --max-time 1 -o /dev/null -w '%{remote_ip}' "http://$bind:$port/result.json" 2>/dev/null || true)"
    [[ -n "$remote" ]]
}

cfip_publisher_disable() {
    local bind="${CFIP_PUBLISH_BIND:-}" port="${CFIP_PUBLISH_PORT:-12345}" attempt responding=false
    local configured_bind="$bind" configured_port="$port"
    if [[ -s "$CFIP_PUBLISH_STATUS_FILE" ]]; then
        bind="$(jq -r '.bind // empty' "$CFIP_PUBLISH_STATUS_FILE" 2>/dev/null || true)"
        port="$(jq -r '.port // 12345' "$CFIP_PUBLISH_STATUS_FILE" 2>/dev/null || printf 12345)"
    fi
    if [[ ! -x "$CFIP_PUBLISH_INIT" ]] || ! "$CFIP_PUBLISH_INIT" stop >/dev/null 2>&1; then
        jq -cn --arg bind "$bind" --arg port "$port" '{success:false,state:"error",listenerReady:false,error:"publisher_stop_failed",bind:$bind,port:($port|tonumber? // null),observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"
        return 3
    fi
    for attempt in 1 2 3; do
        if ! cfip_publisher_endpoint_open "$bind" "$port" &&
            { [[ "$configured_bind:$configured_port" == "$bind:$port" ]] || ! cfip_publisher_endpoint_open "$configured_bind" "$configured_port"; }; then responding=false; break; fi
        responding=true
        ((attempt == 3)) || sleep 1
    done
    if [[ "$responding" == true ]]; then
        jq -cn --arg bind "$bind" --arg port "$port" '{success:false,state:"error",listenerReady:false,error:"publisher_still_responding",bind:$bind,port:($port|tonumber? // null),observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"
        return 6
    fi
    jq -cn --arg bind "$bind" --arg port "$port" '{success:false,state:"disabled",listenerReady:false,count:0,paths:[],bind:$bind,port:($port|tonumber? // null),stopAcknowledged:true,observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"
}

cfip_publisher_generation_id() {
    printf '%s:%s:%s' "${CFIP_RUN_ID:-}" "$1" "$(date +%s)" | sha256sum | awk '{print "gen."$1}'
}

cfip_publisher_link_swap() {
    local target="$1" destination="$2" tmp rc=0 lease_pid="${BASHPID:-$$}"
    [[ ! -d "$destination" || -L "$destination" ]] || return 1
    tmp="$(cfip_publisher_workspace_create link "$lease_pid")" || return 1
    if ln -s "$target" "$tmp/link"; then
        case "$(uname -s)" in
            Darwin) mv -fh "$tmp/link" "$destination" || rc=1 ;;
            *) mv -fT "$tmp/link" "$destination" || rc=1 ;;
        esac
    else rc=1; fi
    if [[ -L "$destination" && "$(readlink "$destination")" == "$target" ]]; then rc=0; else rc=1; fi
    rm -rf "$tmp"
    return "$rc"
}

cfip_publisher_generation_owner() {
    jq -cn --arg generation "$2" '{application:"cf-ip-publisher",generation:$generation}' >"$1/.cfip-owner"
}

cfip_publisher_owned_generation() {
    local dir="$1" id="${1##*/}"
    [[ "$id" =~ ^gen\.[0-9a-f]{64}$ && -d "$dir" && ! -L "$dir" && -f "$dir/.cfip-owner" && ! -L "$dir/.cfip-owner" ]] || return 1
    head -c 4097 "$dir/.cfip-owner" | jq -e --arg id "$id" '.application=="cf-ip-publisher" and .generation==$id' >/dev/null 2>&1
}

# Bootstrap compatibility links against a byte-identical legacy snapshot first.
# Partial link conversion still serves only the old bytes, not the new candidate.
cfip_publisher_prepare_layout() {
    local tmp id f target="" snapshot_needed=false lease_pid="${BASHPID:-$$}"
    [[ "$CFIP_PUBLISH_DIR" == /* && ! -L "$CFIP_PUBLISH_DIR" && ! -L "$CFIP_PUBLISH_DIR/generations" ]] || return 1
    mkdir -p "$CFIP_PUBLISH_DIR/generations" || return 1
    if [[ -e "$CFIP_PUBLISH_DIR/current" || -L "$CFIP_PUBLISH_DIR/current" ]]; then
        target="$(readlink "$CFIP_PUBLISH_DIR/current")" || return 1
        [[ "$target" =~ ^generations/gen\.[0-9a-f]{64}$ ]] && cfip_publisher_owned_generation "$CFIP_PUBLISH_DIR/$target" || return 1
        for f in ip.txt best-ipv4.txt best-ipv6.txt result.json; do
            if [[ -f "$CFIP_PUBLISH_DIR/$f" && ! -L "$CFIP_PUBLISH_DIR/$f" ]] && ! cmp -s "$CFIP_PUBLISH_DIR/$f" "$CFIP_PUBLISH_DIR/current/$f"; then snapshot_needed=true; fi
        done
    else snapshot_needed=true; fi
    # Interrupted first migration may have no cursor yet. Prune only after
    # validating any existing cursor, before adding another legacy snapshot.
    cfip_publisher_prune_generations "${target:-}" '' || return 1
    if [[ "$snapshot_needed" == true ]]; then
        tmp="$(cfip_publisher_workspace_create stage "$lease_pid")" || return 1
        id="$(cfip_publisher_generation_id "$tmp")" || { rm -rf "$tmp"; return 1; }
        for f in ip.txt best-ipv4.txt best-ipv6.txt result.json; do
            if [[ -d "$CFIP_PUBLISH_DIR/$f" ]]; then rm -rf "$tmp"; return 1; fi
            if [[ -L "$CFIP_PUBLISH_DIR/$f" && "$(readlink "$CFIP_PUBLISH_DIR/$f")" != "current/$f" ]]; then rm -rf "$tmp"; return 1; fi
            if [[ -f "$CFIP_PUBLISH_DIR/$f" ]]; then
                head -c 1048577 "$CFIP_PUBLISH_DIR/$f" >"$tmp/$f" || { rm -rf "$tmp"; return 1; }
                (($(wc -c <"$tmp/$f") <= 1048576)) || { rm -rf "$tmp"; return 1; }
                chmod 644 "$tmp/$f" || { rm -rf "$tmp"; return 1; }
            fi
        done
        cfip_publisher_generation_owner "$tmp" "$id" && chmod 755 "$tmp" || { rm -rf "$tmp"; return 1; }
        [[ ! -e "$CFIP_PUBLISH_DIR/generations/$id" ]] && mv "$tmp" "$CFIP_PUBLISH_DIR/generations/$id" || { rm -rf "$tmp"; return 1; }
        if ! cfip_publisher_link_swap "generations/$id" "$CFIP_PUBLISH_DIR/current"; then rm -rf "$CFIP_PUBLISH_DIR/generations/$id"; return 1; fi
    fi
    for f in ip.txt best-ipv4.txt best-ipv6.txt result.json; do
        if [[ -L "$CFIP_PUBLISH_DIR/$f" ]]; then
            [[ "$(readlink "$CFIP_PUBLISH_DIR/$f")" == "current/$f" ]] || return 1
        else
            [[ ! -d "$CFIP_PUBLISH_DIR/$f" ]] && cfip_publisher_link_swap "current/$f" "$CFIP_PUBLISH_DIR/$f" || return 1
        fi
    done
}

cfip_publisher_render_generation() {
    local selected="$1" tmp="$2" id="$3" run_id="${CFIP_RUN_ID:-}" ip family f hash bytes artifacts='{}'
    head -c 1048577 "$selected" >"$tmp/.selected" || return 1
    (($(wc -c <"$tmp/.selected") <= 1048576)) || return 1
    jq -e 'type=="array" and length>0 and length<=20 and (map(.ip)|unique|length)==length and all(.[]; (.ip|type)=="string" and (.family=="ipv4" or .family=="ipv6"))' "$tmp/.selected" >/dev/null || return 1
    while IFS=$'\t' read -r ip family; do
        [[ "$(cfip_ip_family "$ip")" == "$family" ]] && cfip_is_public_candidate "$ip" || return 1
    done < <(jq -r '.[]|[.ip,.family]|@tsv' "$tmp/.selected")
    jq -r '.[].ip' "$tmp/.selected" >"$tmp/ip.txt" || return 1
    jq -r '.[]|select(.family=="ipv4")|.ip' "$tmp/.selected" >"$tmp/best-ipv4.txt" || return 1
    jq -r '.[]|select(.family=="ipv6")|.ip' "$tmp/.selected" >"$tmp/best-ipv6.txt" || return 1
    for f in ip.txt best-ipv4.txt best-ipv6.txt; do
        hash="$(sha256sum "$tmp/$f" | awk '{print $1}')" || return 1
        bytes="$(wc -c <"$tmp/$f")" || return 1
        artifacts="$(jq -cn --argjson previous "$artifacts" --arg name "$f" --arg hash "$hash" --argjson size "$bytes" '$previous + {($name):{sha256:$hash,sizeBytes:$size}}')" || return 1
    done
    jq -n --arg runId "$run_id" --arg generation "$id" --argjson artifacts "$artifacts" --slurpfile selected "$tmp/.selected" \
        '{schemaVersion:1,runId:$runId,generation:$generation,generationPath:("/generations/"+$generation),generatedAt:now,ips:[$selected[0][].ip],selected:$selected[0],artifacts:$artifacts}' >"$tmp/result.json" || return 1
    (($(wc -c <"$tmp/result.json") <= 1048576)) || return 1
    rm -f "$tmp/.selected" || return 1
    cfip_publisher_generation_owner "$tmp" "$id" && chmod 644 "$tmp"/*.txt "$tmp/result.json" "$tmp/.cfip-owner" && chmod 755 "$tmp"
}

cfip_publisher_prune_generations() {
    local current="$1" previous="$2" keep="${CFIP_PUBLISH_KEEP_GENERATIONS:-3}" dir retained=1 ordered
    local -a dirs=()
    [[ -n "$current" ]] || retained=0
    [[ "$keep" =~ ^[2-8]$ ]] || return 1
    for dir in "$CFIP_PUBLISH_DIR"/generations/gen.*; do cfip_publisher_owned_generation "$dir" && dirs+=("$dir"); done
    ((${#dirs[@]} > 0)) || return 0
    [[ "$previous" == "$current" || -z "$previous" ]] || retained=$((retained+1))
    ordered="$(ls -td "${dirs[@]}")" || return 1
    while IFS= read -r dir; do
        [[ "generations/${dir##*/}" != "$current" && "generations/${dir##*/}" != "$previous" ]] || continue
        if ((retained < keep)); then retained=$((retained+1)); else rm -rf "$dir" || return 1; fi
    done <<<"$ordered"
}

cfip_publisher_publish_error() {
    jq -cn --arg error "$1" '{success:false,state:"error",listenerReady:false,error:$error,observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"
}

cfip_publish_result() {
    local selected="$1" tmp id count bind port previous generation_dir keep="${CFIP_PUBLISH_KEEP_GENERATIONS:-3}" lease_pid="${BASHPID:-$$}"
    [[ "${CFIP_PUBLISH_ENABLED:-false}" == true ]] || { cfip_publisher_disable; return $?; }
    [[ "$keep" =~ ^[2-8]$ ]] || { cfip_publisher_publish_error publisher_retention_policy_invalid; return 2; }
    [[ -s "$selected" && "$CFIP_PUBLISH_DIR" == /* && "$CFIP_PUBLISH_DIR" != / && ! -L "$CFIP_PUBLISH_DIR" ]] || return 2
    mkdir -p "${CFIP_PUBLISH_DIR%/*}" || return 1
    tmp="$(cfip_publisher_workspace_create stage "$lease_pid")" || { cfip_publisher_publish_error publisher_workspace_unavailable; return 1; }
    id="$(cfip_publisher_generation_id "$tmp")" || { rm -rf "$tmp"; return 1; }
    if ! cfip_publisher_render_generation "$selected" "$tmp" "$id"; then rm -rf "$tmp"; cfip_publisher_publish_error publisher_render_failed; return 1; fi
    count="$(jq '.selected|length' "$tmp/result.json")" || { rm -rf "$tmp"; return 1; }
    if ! cfip_publisher_prepare_layout; then rm -rf "$tmp"; cfip_publisher_publish_error publisher_layout_failed; return 1; fi
    previous="$(readlink "$CFIP_PUBLISH_DIR/current")" || { rm -rf "$tmp"; return 1; }
    if ! cfip_publisher_prune_generations "$previous" ''; then rm -rf "$tmp"; cfip_publisher_publish_error publisher_retention_failed; return 1; fi
    generation_dir="$CFIP_PUBLISH_DIR/generations/$id"
    [[ ! -e "$generation_dir" ]] && mv "$tmp" "$generation_dir" || { rm -rf "$tmp"; cfip_publisher_publish_error publisher_generation_failed; return 1; }
    bind="${CFIP_PUBLISH_BIND:-}"; port="${CFIP_PUBLISH_PORT:-12345}"
    if [[ ! -x "$CFIP_PUBLISH_INIT" ]] || ! "$CFIP_PUBLISH_INIT" restart >/dev/null 2>&1; then
        rm -rf "$generation_dir"; cfip_publisher_publish_error publisher_start_failed; return 3
    fi
    if ! cfip_publisher_wait_ready "$bind" "$port" "$generation_dir/result.json" "/generations/$id/result.json"; then
        rm -rf "$generation_dir"; cfip_publisher_publish_error publisher_generation_readback_failed; return 5
    fi
    if ! cfip_publisher_link_swap "generations/$id" "$CFIP_PUBLISH_DIR/current"; then
        rm -rf "$generation_dir"; cfip_publisher_publish_error publisher_switch_failed; return 1
    fi
    if ! cfip_publisher_wait_ready "$bind" "$port" "$generation_dir/result.json"; then
        if ! cfip_publisher_link_swap "$previous" "$CFIP_PUBLISH_DIR/current"; then cfip_publisher_publish_error publisher_rollback_failed; return 1; fi
        rm -rf "$generation_dir"; cfip_publisher_publish_error publisher_http_readback_failed; return 5
    fi
    if ! cfip_publisher_prune_generations "generations/$id" "$previous"; then cfip_publisher_publish_error publisher_retention_failed; return 1; fi
    jq -cn --arg generation "$id" --arg bind "${CFIP_PUBLISH_EFFECTIVE_BIND:-$bind}" --arg requestedBind "$bind" --argjson port "$port" --argjson count "$count" \
        '{success:true,state:"ready",listenerReady:true,generation:$generation,generationPath:("/generations/"+$generation),bind:$bind,requestedBind:$requestedBind,port:$port,count:$count,paths:["/ip.txt","/best-ipv4.txt","/best-ipv6.txt","/result.json"],observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"
}

cfip_publisher_status_json() {
    local snapshot bind port LC_ALL=C
    if [[ ! -s "$CFIP_PUBLISH_STATUS_FILE" ]]; then printf '{"success":false,"state":"disabled_or_not_started","listenerReady":false}'; return 0; fi
    snapshot="$(head -c 16385 "$CFIP_PUBLISH_STATUS_FILE" && printf '.')" || return 1
    snapshot="${snapshot%.}"
    if ((${#snapshot} > 16384)) || ! jq -e 'type=="object" and (.success|type)=="boolean"' <<<"$snapshot" >/dev/null 2>&1; then
        printf '{"success":false,"state":"error","error":"publisher_status_invalid","listenerReady":false}'
        return 0
    fi
    if [[ "${CFIP_PUBLISH_ENABLED:-unknown}" == false ]]; then
        bind="$(jq -r '.bind // empty' <<<"$snapshot")"; port="$(jq -r '.port // 12345' <<<"$snapshot")"
        if cfip_publisher_endpoint_open "$bind" "$port" ||
            { [[ "${CFIP_PUBLISH_BIND-$bind}:${CFIP_PUBLISH_PORT-$port}" != "$bind:$port" ]] && cfip_publisher_endpoint_open "${CFIP_PUBLISH_BIND-$bind}" "${CFIP_PUBLISH_PORT-$port}"; }; then
            jq -cn '{success:false,state:"error",error:"publisher_still_responding",listenerReady:false,observedAt:now}'
        elif jq -e '.state=="error"' <<<"$snapshot" >/dev/null; then printf '%s' "$snapshot"
        else jq -cn '{success:false,state:"disabled",listenerReady:false,observedAt:now}'; fi
        return 0
    fi
    if jq -e '.success==true' <<<"$snapshot" >/dev/null; then
        bind="$(jq -r '.bind // empty' <<<"$snapshot")"; port="$(jq -r '.port // 12345' <<<"$snapshot")"
        if [[ "${CFIP_PUBLISH_BIND+x}" == x ]]; then bind="$CFIP_PUBLISH_BIND"; fi
        if [[ "${CFIP_PUBLISH_PORT+x}" == x ]]; then port="$CFIP_PUBLISH_PORT"; fi
        [[ "$bind" != lan-auto ]] || bind="${CFIP_PUBLISH_BIND:-}"
        if CFIP_PUBLISH_READY_ATTEMPTS=1 cfip_publisher_wait_ready "$bind" "$port" "$CFIP_PUBLISH_DIR/result.json"; then
            jq --arg bind "${CFIP_PUBLISH_EFFECTIVE_BIND:-$bind}" --argjson port "$((10#$port))" --arg generation "${CFIP_PUBLISH_EFFECTIVE_GENERATION:-}" --argjson count "${CFIP_PUBLISH_EFFECTIVE_COUNT:-0}" '. + {state:"ready",listenerReady:true,bind:$bind,port:$port,count:$count,lastCheckedAt:now} | if $generation!="" then . + {generation:$generation,generationPath:("/generations/"+$generation)} else del(.generation,.generationPath) end' <<<"$snapshot"
        else
            jq '. + {success:false,state:"unavailable",listenerReady:false,error:"publisher_http_readback_failed",lastCheckedAt:now}' <<<"$snapshot"
        fi
    else printf '%s' "$snapshot"; fi
}

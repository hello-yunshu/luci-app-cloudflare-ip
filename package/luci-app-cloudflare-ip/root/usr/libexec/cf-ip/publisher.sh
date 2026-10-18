#!/usr/bin/env bash
# shellcheck shell=bash

CFIP_PUBLISH_DIR="${CFIP_PUBLISH_DIR:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publish}"
CFIP_PUBLISH_STATUS_FILE="${CFIP_PUBLISH_STATUS_FILE:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publisher-status.json}"
CFIP_PUBLISH_INIT="${CFIP_PUBLISH_INIT:-/etc/init.d/cf_ip_publisher}"

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
    local bind="$1" port="$2" expected="$3" tmp bytes attempt attempts="${CFIP_PUBLISH_READY_ATTEMPTS:-3}"
    local -a statuses
    [[ "$attempts" =~ ^[1-5]$ && "$port" =~ ^[0-9]{1,5}$ ]] || return 1
    port=$((10#$port)); ((port >= 1024 && port <= 65535)) || return 1
    bind="$(cfip_publisher_resolve_bind "$bind")" || return 1
    bytes="$(wc -c <"$expected")" || return 1
    ((bytes > 0 && bytes <= 1048576)) || return 1
    tmp="$(mktemp "${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publisher-readback.XXXXXX")" || return 1
    for ((attempt=1; attempt<=attempts; attempt++)); do
        if curl -fsS --noproxy '*' --connect-timeout 1 --max-time 1 "http://$bind:$port/result.json" 2>/dev/null |
            head -c "$((bytes+1))" >"$tmp"; then statuses=("${PIPESTATUS[@]}"); else statuses=("${PIPESTATUS[@]}"); fi
        if ((statuses[0] == 0 && statuses[1] == 0)) && cmp -s "$expected" "$tmp"; then CFIP_PUBLISH_EFFECTIVE_BIND="$bind"; rm -f "$tmp"; return 0; fi
        ((attempt == attempts)) || sleep 1
    done
    rm -f "$tmp"
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

cfip_publish_result() {
    local selected="$1" run_id="${CFIP_RUN_ID:-}" tmp count bind port
    [[ "${CFIP_PUBLISH_ENABLED:-false}" == true ]] || { cfip_publisher_disable; return $?; }
    [[ -s "$selected" ]] || return 2
    count="$(jq 'length' "$selected")"; ((count>0)) || return 2
    mkdir -p "$CFIP_PUBLISH_DIR"
    tmp="$(mktemp -d "${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publish-next.XXXXXX")" || return 1
    jq -r '.[].ip' "$selected" >"$tmp/ip.txt"
    jq -r '.[]|select(.family=="ipv4")|.ip' "$selected" >"$tmp/best-ipv4.txt"
    jq -r '.[]|select(.family=="ipv6")|.ip' "$selected" >"$tmp/best-ipv6.txt"
    jq -n --arg runId "$run_id" --argjson selected "$(cat "$selected")" '{schemaVersion:1,runId:$runId,generatedAt:now,ips:[$selected[].ip],selected:$selected}' >"$tmp/result.json"
    chmod 644 "$tmp"/*.txt "$tmp/result.json" 2>/dev/null || true
    for f in ip.txt best-ipv4.txt best-ipv6.txt result.json; do cat "$tmp/$f" | cfip_atomic_write "$CFIP_PUBLISH_DIR/$f"; chmod 644 "$CFIP_PUBLISH_DIR/$f" 2>/dev/null || true; done
    rm -rf "$tmp"
    bind="${CFIP_PUBLISH_BIND:-}"; port="${CFIP_PUBLISH_PORT:-12345}"
    if [[ -x "$CFIP_PUBLISH_INIT" ]]; then
        "$CFIP_PUBLISH_INIT" restart >/dev/null 2>&1 || { jq -cn --arg bind "$bind" --argjson port "$port" '{success:false,error:"uhttpd_start_failed",bind:$bind,port:$port,observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"; return 3; }
    else
        jq -cn '{success:false,error:"publisher_init_missing",observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"; return 4
    fi
    if ! cfip_publisher_wait_ready "$bind" "$port" "$CFIP_PUBLISH_DIR/result.json"; then
        jq -cn --arg bind "$bind" --argjson port "$port" '{success:false,error:"publisher_http_readback_failed",bind:$bind,port:$port,observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"
        return 5
    fi
    jq -cn --arg bind "${CFIP_PUBLISH_EFFECTIVE_BIND:-$bind}" --arg requestedBind "$bind" --argjson port "$port" --argjson count "$count" '{success:true,state:"ready",listenerReady:true,bind:$bind,requestedBind:$requestedBind,port:$port,count:$count,paths:["/ip.txt","/best-ipv4.txt","/best-ipv6.txt","/result.json"],observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"
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
            jq --arg bind "${CFIP_PUBLISH_EFFECTIVE_BIND:-$bind}" --argjson port "$((10#$port))" '. + {state:"ready",listenerReady:true,bind:$bind,port:$port,lastCheckedAt:now}' <<<"$snapshot"
        else
            jq '. + {success:false,state:"unavailable",listenerReady:false,error:"publisher_http_readback_failed",lastCheckedAt:now}' <<<"$snapshot"
        fi
    else printf '%s' "$snapshot"; fi
}

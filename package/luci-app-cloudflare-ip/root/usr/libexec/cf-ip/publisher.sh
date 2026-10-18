#!/usr/bin/env bash
# shellcheck shell=bash

CFIP_PUBLISH_DIR="${CFIP_PUBLISH_DIR:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publish}"
CFIP_PUBLISH_STATUS_FILE="${CFIP_PUBLISH_STATUS_FILE:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publisher-status.json}"
CFIP_PUBLISH_INIT="${CFIP_PUBLISH_INIT:-/etc/init.d/cf_ip_publisher}"

# Init exit status is not listener readiness. Verify bounded bytes from the
# resolved endpoint against the result just published; never use HTTP proxies.
cfip_publisher_wait_ready() {
    local bind="$1" port="$2" expected="$3" tmp bytes attempt attempts="${CFIP_PUBLISH_READY_ATTEMPTS:-3}"
    local -a statuses
    [[ "$attempts" =~ ^[1-5]$ ]] || return 1
    if [[ -z "$bind" ]]; then
        bind="$(ubus call network.interface.lan status 2>/dev/null | jq -r '.["ipv4-address"][0].address // empty')" || return 1
    fi
    [[ "$bind" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    bytes="$(wc -c <"$expected")" || return 1
    ((bytes > 0 && bytes <= 1048576)) || return 1
    tmp="$(mktemp "${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publisher-readback.XXXXXX")" || return 1
    for ((attempt=1; attempt<=attempts; attempt++)); do
        if curl -fsS --noproxy '*' --connect-timeout 1 --max-time 1 "http://$bind:$port/result.json" 2>/dev/null |
            head -c "$((bytes+1))" >"$tmp"; then statuses=("${PIPESTATUS[@]}"); else statuses=("${PIPESTATUS[@]}"); fi
        if ((statuses[0] == 0 && statuses[1] == 0)) && cmp -s "$expected" "$tmp"; then rm -f "$tmp"; return 0; fi
        ((attempt == attempts)) || sleep 1
    done
    rm -f "$tmp"
    return 1
}

cfip_publish_result() {
    local selected="$1" run_id="${CFIP_RUN_ID:-}" tmp count bind port
    [[ "${CFIP_PUBLISH_ENABLED:-false}" == true ]] || { [[ -x "$CFIP_PUBLISH_INIT" ]] && "$CFIP_PUBLISH_INIT" stop >/dev/null 2>&1 || true; return 0; }
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
    jq -cn --arg bind "$bind" --argjson port "$port" --argjson count "$count" '{success:true,bind:(if $bind=="" then "lan-auto" else $bind end),port:$port,count:$count,paths:["/ip.txt","/best-ipv4.txt","/best-ipv6.txt","/result.json"],observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"
}

cfip_publisher_status_json() {
    [[ -s "$CFIP_PUBLISH_STATUS_FILE" ]] && cat "$CFIP_PUBLISH_STATUS_FILE" || printf '{"success":false,"state":"disabled_or_not_started"}'
}

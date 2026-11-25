#!/usr/bin/env bash
# CFST process boundary: one task, one input, one invocation.

cfip_cfst_version() {
    local binary="${1:-${CFIP_WORK_DIR:-/usr/bin}/cfst/cfst}" version_file output version
    version_file="${binary}_version.txt"
    if [[ -s "$version_file" ]]; then
        version="$(head -n 1 "$version_file" | tr -d '\r')"
        [[ "$version" =~ ^v?[0-9]+([.][0-9]+)+([.-][A-Za-z0-9._-]+)?$ ]] && { printf '%s' "$version"; return 0; }
    fi
    [[ -x "$binary" ]] || return 1
    output="$(cfip_run_with_timeout 3 "$binary" --version 2>&1 || true)"
    version="$(printf '%s\n' "$output" | grep -Eo 'v?[0-9]+([.][0-9]+)+' | head -n 1 || true)"
    [[ -n "$version" ]] || return 1
    printf '%s' "$version"
}

cfip_cfst_invocation_record() {
    CFIP_CFST_INVOCATION_COUNT=$(( ${CFIP_CFST_INVOCATION_COUNT:-0} + 1 ))
}

# Translate run_cfst exit codes into the operator-facing failure reason.
# Keep the historical "no valid ... candidates" wording for rc=2 so existing
# UI/docs greps stay valid, but never mask a more specific cause behind it.
cfip_cfst_failure_message() {
    local rc="${1:-}"
    case "$rc" in
        124) printf '%s' "measurement timeout during CloudflareSpeedTest" ;;
        125) printf '%s' "${CFIP_OPENCLASH_SERVICE_ERROR:-OpenClash measurement bypass was invalidated during CloudflareSpeedTest; retry after OpenClash finishes reloading}" ;;
        1) printf '%s' "CloudflareSpeedTest is not runnable: the binary is missing or the candidate input is empty" ;;
        3) printf '%s' "CloudflareSpeedTest output could not be parsed into candidate observations" ;;
        2) printf '%s' "no valid CloudflareSpeedTest candidates (no candidate IP passed the latency filter)" ;;
        *) printf '%s' "CloudflareSpeedTest failed (rc=$rc)${CFIP_OPENCLASH_SERVICE_ERROR:+: $CFIP_OPENCLASH_SERVICE_ERROR}" ;;
    esac
}

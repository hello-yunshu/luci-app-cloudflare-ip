#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
UTILS="$ROOT/package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/utils.js"
mkdir -p "$TMP/bin" "$TMP/status" "$TMP/runtime"
cat >"$TMP/bin/uci" <<'EOF_UCI'
#!/usr/bin/env bash
set -e
[[ "${1:-}" == -q ]] && shift
case "${1:-}" in
    show)
        printf "%s\n" "cf_ip.main.builtin_sources='cloudflare-official-v4 cloudflare-official-v6'"
        ;;
    get)
        case "${2:-}" in
            cf_ip.main.enabled) printf '0' ;;
            cf_ip.main.mode) printf 'passwall' ;;
            cf_ip.main.ip_count) printf '4' ;;
            cf_ip.main.ip_type) printf 'ipv4' ;;
            cf_ip.main.speedtest_protocol) printf 'tcp' ;;
            cf_ip.main.speedtest_dn) printf '8' ;;
            cf_ip.main.speedtest_dt) printf '6' ;;
            cf_ip.main.speedtest_tll) printf '40' ;;
            cf_ip.main.speedtest_threads) printf '200' ;;
            cf_ip.main.speedtest_ping_count) printf '3' ;;
            cf_ip.main.stop_service) printf '1' ;;
            cf_ip.main.work_dir) printf '%s' "$TMP/work" ;;
            cf_ip.main.cron_interval) printf '6h' ;;
            cf_ip.main.candidate_budget) printf '128' ;;
            cf_ip.main.probe_top_count) printf '8' ;;
            cf_ip.main.probe_concurrency) printf '4' ;;
            cf_ip.main.probe_timeout) printf '5' ;;
            cf_ip.main.measurement_timeout) printf '60' ;;
            cf_ip.main.recovery_timeout) printf '30' ;;
            cf_ip.main.probe_batch_size) printf '4' ;;
            cf_ip.main.max_probe_count) printf '8' ;;
            cf_ip.main.early_stop_enabled) printf '1' ;;
            cf_ip.main.source_policy) printf 'balanced' ;;
            cf_ip.main.reuse_enabled) printf '1' ;;
            cf_ip.main.max_full_optimize_interval) printf '86400' ;;
            cf_ip.main.reuse_validation_timeout) printf '5' ;;
            cf_ip.main.reuse_loss_limit) printf '0.25' ;;
            cf_ip.main.reuse_ttfb_limit) printf '3000' ;;
            cf_ip.main.reuse_total_limit) printf '5000' ;;
            cf_ip.passwall.target_domain) printf 'one.example' ;;
            cf_ip.rill.enabled) printf '0' ;;
            cf_ip.rill.mode) printf 'shadow' ;;
            cf_ip.rill.runtime) printf '/usr/bin/rill-runtime' ;;
            cf_ip.rill.safe_top_k) printf '3' ;;
            cf_ip.rill.min_feedback_samples) printf '30' ;;
            cf_ip.rill.delayed_feedback_minutes) printf '10' ;;
            cf_ip.rill.timeout_ms) printf '2000' ;;
            cf_ip.lan.enabled) printf '0' ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF_UCI
chmod +x "$TMP/bin/uci"
export PATH="$TMP/bin:$PATH" CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log" CFIP_INIT_DIR="$TMP/init" CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
mkdir -p "$CFIP_INIT_DIR"
committed="$($BIN --validate-config)"
jq -e '.success == true and .valid == true' <<<"$committed" >/dev/null
mkdir -p "$CFIP_STATUS_DIR"
printf '%s\n' '{"formatVersion":1,"partitions":[]}' >"$CFIP_STATUS_DIR/rill-state.json"
printf '%s\n' '{"releaseEligible":true}' >"$CFIP_STATUS_DIR/rill-qualification.json"
printf '%s\n' '{"decisions":[]}' >"$CFIP_STATUS_DIR/candidate-history.json"
printf '%s\n' '{"entries":{}}' >"$CFIP_STATUS_DIR/prefix-history.json"
printf '%s\n' '{"entries":{}}' >"$CFIP_STATUS_DIR/colo-history.json"
printf '%s\n' '[]' >"$CFIP_STATUS_DIR/rill-pending-feedback.json"
printf '%s\n' '{"truncated":' >"$CFIP_STATUS_DIR/rill-evidence.json"
printf '%s\n' '{"assistedDisagreementCount":2}' >"$CFIP_STATUS_DIR/rill-holdout-cadence.json"
printf '{"contextFingerprint":"%064d"}\n' 1 >"$CFIP_STATUS_DIR/rill-state-meta.json"
snapshot_state() {
    find "$CFIP_STATUS_DIR" -type f -printf '%P\n' | sort
    find "$CFIP_STATUS_DIR" -type f -print0 | sort -z | xargs -0 -r sha256sum
}
before_validation="$(snapshot_state)"
staged="$($BIN --validate-config '{"cf_ip.passwall.target_domain":"two.example"}')"
jq -e '.success == true and .valid == true' <<<"$staged" >/dev/null
after_validation="$(snapshot_state)"
if [[ "$before_validation" != "$after_validation" ]]; then
    echo 'staged validation changed persisted Rill state or lineage' >&2
    diff -u <(printf '%s\n' "$before_validation") <(printf '%s\n' "$after_validation") >&2 || true
    exit 1
fi
before_diagnostics="$(snapshot_state)"
diagnostics="$($BIN --rill-diagnostics)"
jq -e '.success == true' <<<"$diagnostics" >/dev/null
after_diagnostics="$(snapshot_state)"
if [[ "$before_diagnostics" != "$after_diagnostics" ]]; then
    echo 'read-only diagnostics changed persisted Rill state or lineage' >&2
    diff -u <(printf '%s\n' "$before_diagnostics") <(printf '%s\n' "$after_diagnostics") >&2 || true
    exit 1
fi
if "$BIN" --validate-config '{"cf_ip.main.candidate_budget":"10"}' >/dev/null 2>&1; then
    echo 'staged invalid budget was accepted' >&2
    exit 1
fi
grep -Fq 'callValidateConfig(candidate)' "$UTILS"
if grep -Fq 'callValidateConfig()' "$UTILS"; then
    echo 'validation call omitted staged candidate' >&2
    exit 1
fi
validate_line="$(grep -n 'callValidateConfig(candidate)' "$UTILS" | head -n1 | cut -d: -f1)"
apply_line="$(grep -n 'return safeApply' "$UTILS" | head -n1 | cut -d: -f1)"
test "$validate_line" -lt "$apply_line"
echo 'LuCI staged candidate validation rejects before safeApply'

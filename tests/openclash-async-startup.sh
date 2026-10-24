#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/init"; printf '#!/bin/sh\nexit 0\n' >"$TMP/init/openclash"; chmod +x "$TMP/init/openclash"
for engine in common legacy standalone; do
  for scenario in delayed exhausted never; do
    (
      printf 0 >"$TMP/clock"
      case "$engine" in
        common) source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh" ;;
        legacy) source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy" ;;
        standalone) source "$ROOT/cf-openwrt-auto.sh" ;;
      esac
      sleep() { printf '%s' "$(( $(cat "$TMP/clock") + $1 ))" >"$TMP/clock"; }
      pidof() { printf 1234; }
      date() { if [[ "${1:-}" == +%s ]]; then cat "$TMP/clock"; else command date "$@"; fi; }
      cfip_monotonic_seconds() { cat "$TMP/clock"; }
      cfip_openclash_read_enable() { CFIP_OPENCLASH_ENABLE_VALUE=1; }
      openclash_enable_state() { printf 1; }
      cfip_openclash_health_once() { [[ "$scenario" != never ]] && (( $(cat "$TMP/clock") >= 8 )); }
      openclash_health_once() { cfip_openclash_health_once; }
      init_stub() { [[ "$scenario" != exhausted ]] || printf 310 >"$TMP/clock"; return 0; }
      cfip_run_with_timeout() { init_stub; }
      openclash_init_bounded() { init_stub; }
      CFIP_INIT_DIR="$TMP/init"; INIT_DIR="$TMP/init"
      CFIP_OPENCLASH_EXPECTED_ENABLED=1; CFIP_OPENCLASH_RESTART_ATTEMPTS=0
      _OPENCLASH_EXPECTED_ENABLED=1; _OPENCLASH_RESTART_ATTEMPTS=0
      if [[ "$engine" == common ]]; then
        if cfip_restart_service openclash; then result=0; else result=$?; fi
      else
        if restart_service openclash; then result=0; else result=$?; fi
      fi
      elapsed="$(cat "$TMP/clock")"
      if [[ "$scenario" == delayed ]]; then
        [[ "$result" == 0 ]] || { echo "FAIL $engine: asynchronous healthy startup rejected at ${elapsed}s"; exit 1; }
        ((elapsed >= 12 && elapsed < 312))
      else
        [[ "$result" != 0 ]] || { echo "FAIL $engine: $scenario startup accepted"; exit 1; }
        ((elapsed <= 312)) || { echo "FAIL $engine: init and health exceeded shared startup bound"; exit 1; }
      fi
      echo "PASS $engine $scenario: elapsed=${elapsed}s result=$result"
    )
  done
done

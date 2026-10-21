#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_REAL_JQ="$(command -v jq)"
mkdir "$TMP/bin"
cat >"$TMP/bin/jq" <<'JQ_WRAPPER'
#!/bin/sh
for arg in "$@"; do
    case "$arg" in *'test('*|*'match('*|*'capture('*|*'scan('*|*'sub('*|*'gsub('*)
        echo 'fixture: optional jq regex support unavailable' >&2; exit 5 ;;
    esac
done
exec "$CFIP_REAL_JQ" "$@"
JQ_WRAPPER
chmod +x "$TMP/bin/jq"
export PATH="$TMP/bin:$PATH"
for name in rill-context-fingerprint operational-history v2-observation prefix-colo-intelligence; do
    bash "$ROOT/tests/$name.sh"
done
export CFIP_STATUS_DIR="$TMP/status"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
filter="$(cfip_jq_trim_filter)"
jq -ne --argjson cases '[
 ["", ""], [" \t\r\n", ""], ["  x y  ", "x y"],
 ["\u0085\u00a0\u1680foo \u2003 bar\u2028", "foo \u2003 bar"],
 ["\u2000foo\u2029", "foo"], ["\u202ffoo\u205f", "foo"],
 ["\u3000foo\u3000", "foo"], ["\u001cfoo\u001d", "\u001cfoo\u001d"],
 ["\u200bfoo\ufeff", "\u200bfoo\ufeff"], ["  Ä.Example  ", "Ä.Example"]
]' "$filter"'$cases | all(.[]; (.[0] | cfip_trim) == .[1])' >/dev/null
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/candidate-rill.sh"
cfip_rill_context_json(){ return 23; }
if cfip_rill_context_fingerprint >"$TMP/hash"; then echo 'failed context was hashed as a valid fingerprint' >&2; exit 1; fi
test ! -s "$TMP/hash"
cfip_rill_context_json(){ :; }
if cfip_rill_context_fingerprint >"$TMP/hash"; then echo 'empty context was hashed as a valid fingerprint' >&2; exit 1; fi
test ! -s "$TMP/hash"
echo 'Runtime JSON paths work without regex; Unicode whitespace and failed fingerprint inputs retain their contracts'

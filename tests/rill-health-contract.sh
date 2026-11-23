#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CFIP_LOG_FILE="$TMP/log" CFIP_STATUS_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json"
export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=assisted CFIP_RUN_ID=health-contract
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/candidate-rill-feature-schema-v2.json"
export CFIP_RILL_RUNTIME="$TMP/fake-runtime"
# The Stable package still answers on the legacy "preview" protocol, so the two
# channels must stay distinct in the payload: package channel comes from the
# channel marker, protocol channel comes from the Runtime response.
export CFIP_RILL_CHANNEL_FILE="$TMP/runtime-channel"
printf 'stable\n' >"$CFIP_RILL_CHANNEL_FILE"

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/candidate-rill.sh"

cat > "$CFIP_RILL_RUNTIME" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
request="$(cat)"
method="$(jq -r '.request.method // empty' <<<"$request")"
id="$(jq -r '.requestId' <<<"$request")"
schema="$(jq -r '.featureSchemaHash' <<<"$request")"
case "$method" in
  handshake)
    jq -cn --arg id "$id" --arg schema "$schema" '{requestId:$id,apiVersion:3,modelGeneration:2,stateGeneration:9,runtimeIdentity:{name:"rill-runtime",version:"0.2.0-preview"},response:{kind:"handshake",channel:"preview",featureSchemaHash:$schema,handlerApiVersion:2,capabilities:["org.rill.preview.decide","org.rill.preview.feedback","org.rill.preview.inspect"]}}'
    ;;
  health)
    jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"health",healthy:true,status:"healthy",reasonCodes:[]}}'
    ;;
  inspect)
    jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"inspection",summary:{runtimeVersion:"0.2.0-preview",protocolVersion:3,channel:"preview",modelGeneration:2,stateGeneration:9,stateSchemaVersion:2,stateChecksum:"abc",pendingDecisions:1,completedDecisions:8,resourceProfile:{},resourceUtilization:{},rollbackAvailable:false,candidateAvailable:true,health:{status:"healthy"},lastError:null,handler:"preview"}}}'
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$CFIP_RILL_RUNTIME"

status="$(cfip_rill_status_json)"
test "$(jq -r '.available' <<<"$status")" = true
test "$(jq -r '.health' <<<"$status")" = healthy
test "$(jq -r '.healthHealthy' <<<"$status")" = true
test "$(jq -r '.resourcePressure' <<<"$status")" = false
test "$(jq -r '.modelGeneration' <<<"$status")" = 2
test "$(jq -r '.inspect.pendingDecisions' <<<"$status")" = 1
test "$(jq -r '.packageChannel' <<<"$status")" = stable
test "$(jq -r '.protocolChannel' <<<"$status")" = preview
test "$(jq -r 'has("channel")' <<<"$status")" = false
# Freshness is a first-class status field: the UI and the decision confidence
# both need to tell "fresh" from "stale" without recomputing the window.
case "$(jq -r '.qualificationFreshness' <<<"$status")" in
    fresh|stale|expired|none) ;;
    *) echo "unexpected qualificationFreshness: $(jq -r '.qualificationFreshness' <<<"$status")" >&2; exit 1 ;;
esac

# A Runtime that omits the protocol channel must report null, never a
# misleading "preview" default.
CFIP_RILL_RUNTIME="$TMP/fake-runtime-no-channel"
sed 's/channel:"preview",//' "$TMP/fake-runtime" >"$CFIP_RILL_RUNTIME"
chmod +x "$CFIP_RILL_RUNTIME"
no_channel_status="$(cfip_rill_status_json)"
test "$(jq -r '.protocolChannel' <<<"$no_channel_status")" = null
test "$(jq -r '.packageChannel' <<<"$no_channel_status")" = stable

echo 'Rill health and inspect contract passed'

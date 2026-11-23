#!/usr/bin/env bash
# Assert CFI's UCI assumptions against the configuration the upstream package
# actually ships, not against a fixture this repository authored.
#
# Usage: bash tests/upstream-schema-contract.sh --config-dir DIR
#   DIR is produced by scripts/fetch-upstream-config.py and holds one UCI file
#   per upstream, plus sources.json.
#
# Requires UCI_REAL_BIN: a real uci binary (tests/build-real-uci.sh builds one).
# A missing coordinate here is evidence of breakage. A version number is not.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES="$ROOT/upstream-schema-sources.json"
BASELINE="$ROOT/proxy-upstream-baseline.json"
UCI_REAL_BIN="${UCI_REAL_BIN:?real UCI CLI required}"

config_dir=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--config-dir) config_dir="${2:?--config-dir needs a value}"; shift 2 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done
[[ -n "$config_dir" && -d "$config_dir" ]] || { echo "--config-dir must name a directory" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
checked=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

uci_get() { "$UCI_REAL_BIN" -c "$1" -t "$1" -q get "$2" 2>/dev/null; }

# `pkg.@type[*].option` means: at least one section of that type still carries
# the option. Section order is upstream's business, so pinning an index would
# turn a harmless reordering into a false alarm.
check_instances() {
	local name="$1" conf="$2" coordinate="$3"
	local head="${coordinate%%\[\*\]*}" tail="${coordinate#*\[\*\]}"
	local index=0 section value
	while [[ "$index" -lt 500 ]]; do
		section="${head}[$index]"
		uci_get "$conf" "$section" >/dev/null || break
		if value="$(uci_get "$conf" "${section}${tail}")" && [[ -n "$value" ]]; then
			return 0
		fi
		index=$((index + 1))
	done
	fail "$name: no instance of ${head}[*] still carries ${tail#.}"
	return 1
}

# Coverage guard: every upstream in the baseline must be covered by a schema
# source or explicitly declared to have no UCI surface, so a newly tracked
# upstream cannot silently escape this contract.
while read -r name; do
	jq -e --arg name "$name" \
		'(.upstreams | any(.name == $name)) or (.notApplicable | any(.name == $name))' \
		"$SOURCES" >/dev/null ||
		fail "$name is tracked in the baseline but upstream-schema-sources.json neither covers it nor explains why not"
done < <(jq -r '.upstreams[].name' "$BASELINE")

while read -r name dest; do
	[[ -n "$name" && -n "$dest" ]] || continue
	file="$config_dir/$dest"
	if [[ ! -f "$file" ]]; then
		fail "$name: $dest was not fetched into $config_dir"
		continue
	fi
	conf="$TMP/$dest.dir"
	mkdir -p "$conf"
	cp "$file" "$conf/$dest"

	if ! "$UCI_REAL_BIN" -c "$conf" -t "$conf" show "$dest" >/dev/null 2>"$TMP/err"; then
		fail "$name: the shipped configuration does not parse ($(head -1 "$TMP/err"))"
		continue
	fi

	while read -r coordinate; do
		[[ -n "$coordinate" ]] || continue
		checked=$((checked + 1))
		if [[ "$coordinate" == *'[*]'* ]]; then
			check_instances "$name" "$conf" "$coordinate" || true
			continue
		fi
		if ! value="$(uci_get "$conf" "$coordinate")"; then
			fail "$name: $coordinate no longer exists in the shipped configuration"
			continue
		fi
		[[ -n "$value" ]] || fail "$name: $coordinate exists but is empty"
	done < <(jq -r --arg name "$name" '.upstreams[] | select(.name == $name) | .shipped[]' "$SOURCES")
done < <(jq -r '.upstreams[] | "\(.name) \(.dest)"' "$SOURCES")

echo "upstream schema contract: $checked coordinate(s) asserted across $(jq '.upstreams | length' "$SOURCES") upstream(s)"
[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)" >&2; exit 1; }
echo 'PASS: every coordinate CFI depends on still exists in the real upstream configuration'

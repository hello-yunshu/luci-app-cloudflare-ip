#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEGACY="$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cfip-ruby-precheck.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/init" "$TMP/bin"
cat >"$TMP/init/openclash" <<'EOF'
#!/bin/sh
[ "${1:-}" = "running" ] && exit 1
exit 0
EOF
chmod +x "$TMP/init/openclash"
for command in bash curl tar jq date awk sed tr wc ls dirname basename mktemp grep head cut sort uname; do
	command -v "$command" >/dev/null 2>&1 || continue
	ln -s "$(command -v "$command")" "$TMP/bin/$command"
done

run_case() {
	local name="$1" ruby_mode="$2" expected_status="$3" expected_psych="$4" expected_usable="$5" expected_restore="$6"
	rm -rf "$TMP/path"; mkdir -p "$TMP/path"
	for link in "$TMP"/bin/*; do ln -s "$(readlink "$link")" "$TMP/path/$(basename "$link")"; done
	if [[ "$ruby_mode" == "available" ]]; then
		cat >"$TMP/path/ruby" <<'EOF'
#!/bin/sh
case " $* " in
	*" -rpsych "*) exit 0 ;;
	*" RUBY_VERSION "*) printf '3.3.10' ;;
	*) exit 0 ;;
esac
EOF
		chmod +x "$TMP/path/ruby"
	elif [[ "$ruby_mode" == "psych" ]]; then
		cat >"$TMP/path/ruby" <<'EOF'
#!/bin/sh
case " $* " in
	*" -rpsych "*) exit 1 ;;
	*) printf '3.3.10' ;;
esac
EOF
		chmod +x "$TMP/path/ruby"
	elif [[ "$ruby_mode" == "crash" ]]; then
		cat >"$TMP/path/ruby" <<'EOF'
#!/bin/sh
exit 139
EOF
		chmod +x "$TMP/path/ruby"
	fi
	# Without a ruby shim, the restricted PATH hides the host Ruby.
	local output
	output="$(PATH="$TMP/path" INIT_DIR="$TMP/init" STATUS_DIR="$TMP/status" LOG_FILE="$TMP/log" \
		bash "$LEGACY" --check-env)"
	printf '%s\n' "$output" | jq -e --arg status "$expected_status" --argjson psych "$expected_psych" \
		--argjson usable "$expected_usable" --argjson restore "$expected_restore" \
		'.success == true and .openclash_installed == true and
		 .ruby_status == $status and .ruby_psych == $psych and
		 .ruby_usable == $usable and .openclash_restore_available == $restore' >/dev/null ||
		{ printf 'FAIL %s: %s\n' "$name" "$output" >&2; exit 1; }
	printf 'PASS %s: %s\n' "$name" "$output"
}

run_case "ruby-missing" missing ruby_missing false false false
run_case "psych-missing" psych psych_missing false true false
run_case "ruby-unusable" crash ruby_unusable false false false
run_case "available" available available true true true
printf 'PASS OpenClash Ruby/Psych precheck covers missing, Psych and unusable states\n'

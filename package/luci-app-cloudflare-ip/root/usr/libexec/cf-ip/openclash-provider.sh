#!/usr/bin/env bash
# Fail-closed resolver and controller adapter for OpenClash file providers.
# This module never invokes OpenClash init actions.

CFIP_OPENCLASH_RUNTIME_CONFIG=""
CFIP_OPENCLASH_RUNTIME_ID=""
CFIP_OPENCLASH_TARGET_CONFIG=""
CFIP_OPENCLASH_PROVIDER_NAME=""
CFIP_OPENCLASH_PROVIDER_REFRESHED=false
CFIP_OPENCLASH_PROVIDER_RUNTIME_VERIFIED=false
CFIP_OPENCLASH_PROVIDER_RUNTIME_NAMES="[]"

cfip_openclash_capture_runtime() {
    local pids pid arg config count start exe canonical i
    local -a all_pids=() args=()
    pids="$(pidof clash 2>/dev/null)" || pids=""
    read -r -a all_pids <<<"$pids"
    ((${#all_pids[@]} == 1)) || {
        CFIP_OPENCLASH_SERVICE_ERROR="OpenClash core identity is missing or ambiguous"
        return 1
    }
    pid="${all_pids[0]}"
    [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/cmdline" && -r "/proc/$pid/stat" ]] || return 1
    while IFS= read -r -d '' arg; do args+=("$arg"); done <"/proc/$pid/cmdline"
    count=0; config=""
    for ((i=0; i<${#args[@]}; i++)); do
        case "${args[$i]}" in
            -f|--config)
                ((i+1 < ${#args[@]})) || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash core has an incomplete config argument"; return 1; }
                config="${args[$((i+1))]}"; count=$((count+1)); i=$((i+1)) ;;
            -f=*|--config=*) config="${args[$i]#*=}"; count=$((count+1)) ;;
        esac
    done
    ((count == 1)) && [[ "$config" == /* && -f "$config" && ! -L "$config" ]] || {
        CFIP_OPENCLASH_SERVICE_ERROR="OpenClash active -f config is unavailable or ambiguous"
        return 1
    }
    canonical="$(readlink -f "$config" 2>/dev/null)" || return 1
    [[ "$canonical" == "$config" ]] || {
        CFIP_OPENCLASH_SERVICE_ERROR="OpenClash active config resolves through a symlink; refusing hot apply"
        return 1
    }
    start="$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)" || return 1
    [[ "$start" =~ ^[0-9]+$ ]] || return 1
    exe="$(readlink "/proc/$pid/exe" 2>/dev/null)" || return 1
    [[ -n "$exe" ]] || return 1
    CFIP_OPENCLASH_RUNTIME_CONFIG="$canonical"
    CFIP_OPENCLASH_RUNTIME_ID="$pid:$start:$exe:$canonical"
}

cfip_openclash_runtime_unchanged() {
    local old_config="${CFIP_OPENCLASH_RUNTIME_CONFIG:-}" old_id="${CFIP_OPENCLASH_RUNTIME_ID:-}"
    [[ -n "$old_config" && -n "$old_id" ]] || return 1
    cfip_openclash_capture_runtime || return 1
    [[ "$CFIP_OPENCLASH_RUNTIME_CONFIG" == "$old_config" && "$CFIP_OPENCLASH_RUNTIME_ID" == "$old_id" ]]
}

# Return only file providers referenced by a proxy-group. YAML is data-only;
# aliases are needed for upstream configs. Only numeric port symbols are allowed.
cfip_openclash_file_providers_json() {
    local config="$1"
    command -v ruby >/dev/null 2>&1 || return 1
    ruby -rpsych -rjson - "$config" <<'CFIP_PROVIDER_SCAN'
path = ARGV.fetch(0)
def cfip_safe_yaml(path)
  text = File.read(path)
  document = Psych.parse(text)
  symbols = []
  visit = lambda do |node|
    if node.is_a?(Psych::Nodes::Scalar) && (match = node.value.match(/\A:(\d{1,5})\z/)) && match[1].to_i.between?(1, 65_535)
      symbols << match[1].to_sym
    end
    node.children&.each { |child| visit.call(child) } if node.respond_to?(:children)
  end
  visit.call(document)
  Psych.safe_load(text, permitted_classes: [Symbol], permitted_symbols: symbols.uniq, aliases: true)
end
begin
  config = cfip_safe_yaml(path)
  abort 'OpenClash config root must be a mapping' unless config.is_a?(Hash)
  providers = config['proxy-providers']
  groups = config['proxy-groups']
  abort 'proxy-providers must be a mapping' unless providers.is_a?(Hash)
  abort 'proxy-groups must be a sequence' unless groups.is_a?(Array)
  used = groups.flat_map do |group|
    next [] unless group.is_a?(Hash)
    refs = group['use']
    refs.is_a?(Array) ? refs : []
  end
  out = providers.each_with_object([]) do |(name, provider), result|
    next unless name.is_a?(String) && provider.is_a?(Hash)
    next unless provider['type'] == 'file' && provider['path'].is_a?(String)
    next unless used.include?(name)
    expanded = File.expand_path(provider['path'], File.dirname(path))
    next unless File.file?(expanded)
    result << { 'name' => name, 'path' => File.realpath(expanded) }
  end
  puts JSON.generate(out)
rescue Psych::Exception, ArgumentError, SystemCallError => e
  warn "OpenClash provider scan failed: #{e.class}"
  exit 1
end
CFIP_PROVIDER_SCAN
}

cfip_openclash_provider_has_target() {
    local file="$1" domains="${CFIP_OPENCLASH_TARGET_DOMAIN:-}" name type server tls network sni host domain
    local -a _cfip_domains=()
    [[ -n "$domains" ]] || return 1
    IFS=',' read -r -a _cfip_domains <<<"$domains"
    while IFS= read -r -d '' name && IFS= read -r -d '' type && IFS= read -r -d '' server &&
          IFS= read -r -d '' tls && IFS= read -r -d '' network && IFS= read -r -d '' sni && IFS= read -r -d '' host; do
        cfip_openclash_protocol_supported "$type" "$tls" "$network" || continue
        for domain in "${_cfip_domains[@]}"; do
            domain="${domain#${domain%%[![:space:]]*}}"; domain="${domain%${domain##*[![:space:]]}}"
            if [[ "$server" == "$domain" || "$sni" == "$domain" || "$host" == "$domain" ]]; then return 0; fi
        done
    done < <(cfip_openclash_mapping_tsv "$file")
    return 1
}

cfip_openclash_resolve_provider_target() {
    local rows row name path matches=0 selected_path="" selected_name="" main_config
    main_config="${CFIP_OPENCLASH_RUNTIME_CONFIG:-}"
    [[ -n "$main_config" && -f "$main_config" ]] || {
        CFIP_OPENCLASH_SERVICE_ERROR="OpenClash running config was not captured"
        return 1
    }
    rows="$(cfip_openclash_file_providers_json "$main_config")" || {
        CFIP_OPENCLASH_SERVICE_ERROR="OpenClash provider references could not be parsed"
        return 1
    }
    jq -e 'type == "array"' <<<"$rows" >/dev/null || return 1
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        name="$(jq -r '.name' <<<"$row")" || return 1
        path="$(jq -r '.path' <<<"$row")" || return 1
        cfip_managed_openclash_config_safe "$path" || continue
        cfip_openclash_provider_has_target "$path" || continue
        matches=$((matches+1)); selected_path="$path"; selected_name="$name"
    done < <(jq -c '.[]' <<<"$rows")
    ((matches == 1)) || {
        CFIP_OPENCLASH_SERVICE_ERROR="Expected exactly one referenced file provider matching the configured target domain; found $matches"
        return 1
    }
    CFIP_OPENCLASH_TARGET_CONFIG="$selected_path"
    CFIP_OPENCLASH_PROVIDER_NAME="$selected_name"
}

cfip_openclash_provider_expected_names() {
    ruby -rpsych -rjson - "$1" <<'CFIP_PROVIDER_NAMES'
path = ARGV.fetch(0)
config = Psych.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: true)
proxies = config.is_a?(Hash) ? config['proxies'] : nil
abort 'provider proxies must be a sequence' unless proxies.is_a?(Array)
names = proxies.map { |proxy| proxy.is_a?(Hash) ? proxy['name'] : nil }
abort 'provider contains invalid or duplicate proxy names' unless names.all? { |name| name.is_a?(String) && !name.empty? } && names.uniq.length == names.length
puts JSON.generate(names.sort)
CFIP_PROVIDER_NAMES
}

# Backup restore accepts only the provider document shape. Historical backups
# beside the old UCI path may contain an entire Clash config; reject those
# instead of ever uploading the main config as a provider payload.
cfip_openclash_provider_document_valid() {
    ruby -rpsych - "$1" <<'CFIP_PROVIDER_DOCUMENT'
config = Psych.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: true)
abort 'provider document must contain only proxies' unless config.is_a?(Hash) && config.keys == ['proxies']
proxies = config['proxies']
abort 'provider proxies must be a sequence' unless proxies.is_a?(Array)
names = proxies.map { |proxy| proxy.is_a?(Hash) ? proxy['name'] : nil }
abort 'provider contains invalid or duplicate proxy names' unless names.all? { |name| name.is_a?(String) && !name.empty? } && names.uniq.length == names.length
CFIP_PROVIDER_DOCUMENT
}

cfip_openclash_controller_matches_port() {
    ruby -rpsych - "$1" "$2" <<'CFIP_CONTROLLER_PORT'
def cfip_safe_yaml(path)
  text = File.read(path)
  document = Psych.parse(text)
  symbols = []
  visit = lambda do |node|
    if node.is_a?(Psych::Nodes::Scalar) && (match = node.value.match(/\A:(\d{1,5})\z/)) && match[1].to_i.between?(1, 65_535)
      symbols << match[1].to_sym
    end
    node.children&.each { |child| visit.call(child) } if node.respond_to?(:children)
  end
  visit.call(document)
  Psych.safe_load(text, permitted_classes: [Symbol], permitted_symbols: symbols.uniq, aliases: true)
end
config = cfip_safe_yaml(ARGV.fetch(0))
controller = config.is_a?(Hash) ? config['external-controller'] : nil
expected = ARGV.fetch(1)
match = controller.is_a?(String) && controller.match(/:(\d+)\z/)
exit(match && match[1] == expected ? 0 : 1)
CFIP_CONTROLLER_PORT
}

cfip_openclash_provider_inspect_runtime() {
    local target="${CFIP_OPENCLASH_TARGET_CONFIG:-}" main="${CFIP_OPENCLASH_RUNTIME_CONFIG:-}" name="${CFIP_OPENCLASH_PROVIDER_NAME:-}"
    local port secret cfg body code names
    [[ -n "$target" && -n "$main" && -n "$name" ]] || return 1
    cfip_openclash_runtime_unchanged || return 1
    port="$(uci -q get openclash.config.cn_port 2>/dev/null)" || return 1
    [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && ((port <= 65535)) || return 1
    cfip_openclash_controller_matches_port "$main" "$port" || return 1
    secret="$(cfip_openclash_secret 2>/dev/null)" || return 1
    [[ "$secret" != *$'\n'* && "$secret" != *$'\r'* ]] || return 1
    cfg="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-inspect-curl.XXXXXX")" || return 1
    body="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-inspect-body.XXXXXX")" || { rm -f "$cfg"; return 1; }
    chmod 600 "$cfg" "$body" 2>/dev/null || true
    secret="${secret//\\/\\\\}"; secret="${secret//\"/\\\"}"
    printf 'header = "Authorization: Bearer %s"\n' "$secret" >"$cfg" || { rm -f "$cfg" "$body"; return 1; }
    code="$(curl --config "$cfg" --connect-timeout 2 --max-time 8 --silent --show-error --output "$body" --write-out '%{http_code}' "http://127.0.0.1:${port}/providers/proxies/$(jq -rn --arg name "$name" '$name|@uri')" 2>/dev/null)" || code="curl_failed"
    names="$(jq -ce 'if (.proxies|type)=="array" and all(.proxies[]; (.name|type)=="string") then [.proxies[].name]|sort else error("invalid provider response") end' "$body" 2>/dev/null)" || names=""
    rm -f "$cfg" "$body"
    [[ "$code" == 200 && -n "$names" ]] && cfip_openclash_runtime_unchanged || return 1
    CFIP_OPENCLASH_PROVIDER_RUNTIME_VERIFIED=true
    CFIP_OPENCLASH_PROVIDER_RUNTIME_NAMES="$names"
}

cfip_openclash_provider_refresh() {
    local target="${CFIP_OPENCLASH_TARGET_CONFIG:-}" main="${CFIP_OPENCLASH_RUNTIME_CONFIG:-}" name="${CFIP_OPENCLASH_PROVIDER_NAME:-}"
    local port secret cfg body code expected actual encoded controller
    [[ -n "$target" && -n "$main" && -n "$name" ]] || return 1
    CFIP_OPENCLASH_PROVIDER_RUNTIME_VERIFIED=false
    CFIP_OPENCLASH_PROVIDER_RUNTIME_NAMES='[]'
    cfip_openclash_runtime_unchanged || { CFIP_OPENCLASH_SERVICE_ERROR="OpenClash core identity changed before provider refresh"; return 1; }
    port="$(uci -q get openclash.config.cn_port 2>/dev/null)" || return 1
    [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && ((port <= 65535)) || return 1
    cfip_openclash_controller_matches_port "$main" "$port" || {
        CFIP_OPENCLASH_SERVICE_ERROR="OpenClash controller port does not match the active config and UCI"
        return 1
    }
    secret="$(cfip_openclash_secret 2>/dev/null)" || return 1
    [[ "$secret" != *$'\n'* && "$secret" != *$'\r'* ]] || return 1
    cfg="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-provider-curl.XXXXXX")" || return 1
    body="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-provider-body.XXXXXX")" || { rm -f "$cfg"; return 1; }
    chmod 600 "$cfg" "$body" 2>/dev/null || true
    secret="${secret//\\/\\\\}"; secret="${secret//\"/\\\"}"
    printf 'header = "Authorization: Bearer %s"\n' "$secret" >"$cfg" || { rm -f "$cfg" "$body"; return 1; }
    encoded="$(jq -rn --arg name "$name" '$name|@uri')" || { rm -f "$cfg" "$body"; return 1; }
    controller="http://127.0.0.1:${port}/providers/proxies/${encoded}"
    code="$(curl --config "$cfg" --connect-timeout 2 --max-time 10 --silent --show-error --output /dev/null --write-out '%{http_code}' -X PUT "$controller" 2>/dev/null)" || code="curl_failed"
    if [[ "$code" != 204 ]] || ! cfip_openclash_runtime_unchanged; then
        # A timeout can occur after Mihomo accepted the PUT. Read the live
        # provider before the caller decides whether transaction-owned bytes
        # may be restored. This records runtime observation, never outbound proof.
        rm -f "$cfg" "$body"
        cfip_openclash_provider_inspect_runtime || true
        CFIP_OPENCLASH_SERVICE_ERROR="OpenClash provider refresh failed or core identity changed"
        return 1
    fi
    code="$(curl --config "$cfg" --connect-timeout 2 --max-time 8 --silent --show-error --output "$body" --write-out '%{http_code}' "$controller" 2>/dev/null)" || code="curl_failed"
    expected="$(cfip_openclash_provider_expected_names "$target")" || { rm -f "$cfg" "$body"; return 1; }
    actual="$(jq -c '[.proxies[].name]|sort' "$body" 2>/dev/null)" || actual=""
    if [[ "$code" != 200 || "$actual" != "$expected" ]] || ! cfip_openclash_runtime_unchanged; then
        CFIP_OPENCLASH_SERVICE_ERROR="OpenClash provider readback or core identity validation failed"
        rm -f "$cfg" "$body"
        return 1
    fi
    rm -f "$cfg" "$body"
    CFIP_OPENCLASH_PROVIDER_REFRESHED=true
    CFIP_OPENCLASH_PROVIDER_RUNTIME_VERIFIED=true
    CFIP_OPENCLASH_PROVIDER_RUNTIME_NAMES="$actual"
}

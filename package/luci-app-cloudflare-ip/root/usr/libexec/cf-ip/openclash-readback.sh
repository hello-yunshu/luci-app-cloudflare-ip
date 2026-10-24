#!/usr/bin/env bash
# OpenClash IntendedMappingV1 readback. A server IP alone is insufficient
# evidence: every expected proxy block is compared as one complete record.

# Reject unsupported proxy forms rather than returning a partial mapping.
# Keep the block mapping boundary and validate the entire document before writes.
cfip_openclash_yaml_supported() {
    awk '
      function reject(reason) { print "unsupported OpenClash proxy YAML at line " NR ": " reason > "/dev/stderr"; bad=1; exit 1 }
      /\t/ { reject("tab indentation or scalar") }
      /^proxies:/ {
        if (seen++) reject("duplicate proxies section")
        value=$0; sub(/^proxies:[ ]*/, "", value)
        if (value!="" && value !~ /^#/) reject("proxies must use block sequence form")
        active=1; next
      }
      /^[^ #][^:]*:/ { active=0 }
      active {
        text=$0; sub(/^[ ]*/, "", text)
        if (text=="" || text ~ /^#/) next
        if (text ~ /^-[ ]*/ && text !~ /^-[ ]+name:/ && text !~ /^-[ ]*$/) reject("proxy entries require block name-first form")
        if (text ~ /^<<:/) reject("merge key")
        if (text ~ /^-[ ]+name:/) {
            for (field in mapped) delete mapped[field]
            key="name"
            proxy_indent=match($0,/[^ ]/)-1
        } else { key=text; sub(/:.*/, "", key) }
        if (key ~ /^(name|type|server|tls|network|servername|Host)$/) {
            if (mapped[key]++) reject("duplicate mapped field " key)
            if (key!="name" && key!="Host" && match($0,/[^ ]/)-1 != proxy_indent+2) reject("nested mapped field " key)
        }
        value=text; sub(/^[^:]+:[ ]*/, "", value)
        if (value ~ /^[{&*!|>]/) reject("flow map, anchor, alias, tag or block scalar")
      }
      END { if (!seen || bad) exit 1 }
    ' "$1" || return 1
    command -v ruby >/dev/null 2>&1 || { printf '%s\n' 'unsupported OpenClash proxy YAML: Ruby/Psych is required for document validation' >&2; return 1; }
    ruby -rpsych - "$1" <<'CFIP_YAML_DOCUMENT'
path = ARGV.fetch(0)
lines = File.readlines(path)
def refuse(node, reason)
  line = node.respond_to?(:start_line) ? node.start_line + 1 : 1
  raise ArgumentError, "line #{line}: #{reason}"
end
def visit(node, lines, mapped = false)
  if node.is_a?(Psych::Nodes::Mapping)
    seen = {}
    node.children.each_slice(2) do |key, value|
      refuse(key, 'complex mapping keys are unsupported') unless key.is_a?(Psych::Nodes::Scalar)
      refuse(key, 'typed mapping keys are unsupported') if (key.tag && key.tag != 'tag:yaml.org,2002:str') ||
        (key.plain && key.value.match?(/\A(?:[-+]?(?:[0-9]|\.[0-9])|~\z|(?:true|false|yes|no|on|off|null)\z)/i))
      refuse(key, 'duplicate mapping key') if seen[key.value]
      seen[key.value] = true
      if mapped && %w[name type server tls network servername Host].include?(key.value)
        refuse(value, 'mapped values must be single-line scalars') unless value.is_a?(Psych::Nodes::Scalar) && value.start_line == value.end_line
        raw = lines.fetch(key.start_line).chomp
        prefix = /\A\s*(?:-\s+)?#{Regexp.escape(key.value)}:\s*/
        refuse(key, 'quoted or ambiguous mapped key') unless raw.match?(prefix)
        raw = raw.sub(prefix, '').strip.sub(/\A["']/, '').sub(/["']\z/, '')
        refuse(value, 'unsupported mapped scalar escaping or comment') unless raw == value.value
      end
      visit(value, lines, mapped)
    end
  elsif node.respond_to?(:children) && node.children
    node.children.each { |child| visit(child, lines, mapped) }
  end
end
begin
  stream = Psych.parse_stream(lines.join, filename: path)
  refuse(stream, 'exactly one YAML document is required') unless stream.children.length == 1
  root = stream.children.first.root
  refuse(root, 'document root must be a mapping') unless root.is_a?(Psych::Nodes::Mapping)
  visit(root, lines)
  proxies = root.children.each_slice(2).find { |key, _| key.value == 'proxies' }
  refuse(root, 'proxies must be a sequence') unless proxies && proxies[1].is_a?(Psych::Nodes::Sequence)
  proxies[1].children.each do |entry|
    refuse(entry, 'proxy entries require indented name-first block maps') unless entry.is_a?(Psych::Nodes::Mapping) &&
      lines.fetch(entry.start_line).match?(/\A[ ]+-[ ]+name:/)
  end
  visit(proxies[1], lines, true)
rescue Psych::SyntaxError => error
  warn "unsupported OpenClash proxy YAML at line #{error.line}: invalid document syntax"
  exit 1
rescue ArgumentError => error
  warn "unsupported OpenClash proxy YAML at #{error.message}"
  exit 1
end
CFIP_YAML_DOCUMENT
}

cfip_openclash_protocol_supported() {
    local type tls network
    type="$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')"
    tls="$(printf '%s' "${2:-}" | tr 'A-Z' 'a-z')"
    network="$(printf '%s' "${3:-}" | tr 'A-Z' 'a-z')"
    [[ "$type" == vless || "$type" == vmess || "$type" == trojan ]] || return 1
    [[ "$tls" == true ]] && return 0
    [[ "$network" == ws || "$network" == xhttp || "$network" == grpc || "$network" == h2 || "$network" == http ]]
}

cfip_openclash_mapping_tsv() {
    # NUL separates fields so an empty TLS/SNI/Host value never collapses as
    # it does with Bash's whitespace IFS. Current supported YAML is the
    # block form with one proxy per `- name:` and scalar fields on separate
    # lines; inline maps, anchors, folded values and escaped multiline YAML
    # are intentionally outside this conservative parser's contract.
    local config="$1"
    awk '
      function trim(v) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(/^["'"'"']|["'"'"']$/, "", v); return v }
      function emit() { if (name != "") printf "%s%c%s%c%s%c%s%c%s%c%s%c%s%c", name,0,type,0,server,0,tls,0,network,0,servername,0,host,0 }
      /^proxies:[ ]*($|#)/ { active=1; next }
      /^[^ #][^:]*:/ { if (active) { emit(); name="" }; active=0; next }
      !active { next }
      /^[[:space:]]*-[[:space:]]+name:[[:space:]]*/ {
        emit(); line=$0; sub(/^[[:space:]]*-[[:space:]]+name:[[:space:]]*/, "", line)
        name=trim(line); type=""; server=""; tls=""; network=""; servername=""; host=""; next
      }
      name != "" && /^[[:space:]]+type:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+type:[[:space:]]*/, "", line); type=trim(line); next }
      name != "" && /^[[:space:]]+server:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+server:[[:space:]]*/, "", line); server=trim(line); next }
      name != "" && /^[[:space:]]+tls:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+tls:[[:space:]]*/, "", line); tls=trim(line); next }
      name != "" && /^[[:space:]]+network:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+network:[[:space:]]*/, "", line); network=trim(line); next }
      name != "" && /^[[:space:]]+servername:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+servername:[[:space:]]*/, "", line); servername=trim(line); next }
      name != "" && /^[[:space:]]+Host:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+Host:[[:space:]]*/, "", line); host=trim(line); next }
      END { emit() }
    ' "$config"
}

cfip_openclash_actual_mapping() {
    local config="$1" output="$2" tmp row name type server tls network servername host
    cfip_openclash_yaml_supported "$config" || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-actual.XXXXXX")" || return 1
    printf '[]' >"$tmp"
    while IFS= read -r -d '' name && IFS= read -r -d '' type && IFS= read -r -d '' server && IFS= read -r -d '' tls && IFS= read -r -d '' network && IFS= read -r -d '' servername && IFS= read -r -d '' host; do
        [[ -n "$name" ]] || continue
        jq -cn --arg name "$name" --arg type "$type" --arg server "$server" --arg tls "$tls" \
          --arg network "$network" --arg servername "$servername" --arg host "$host" \
          '{name:$name,type:$type,server:$server,tls:$tls,network:$network,servername:(if $servername=="" then null else $servername end),host:(if $host=="" then null else $host end)}' \
          >"$tmp.row"
        jq --argjson row "$(cat "$tmp.row")" '. + [$row]' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp" || { rm -f "$tmp" "$tmp.row"; return 1; }
    done < <(cfip_openclash_mapping_tsv "$config")
    mv "$tmp" "$output"
    rm -f "$tmp.row"
}

cfip_openclash_intended_from_templates() {
    local selected="$1" config="$2" domains_csv="$3" suffix="$4" filter="$5" output="$6"
    local count name type server tls network servername host domain base seq ip idx line tmp filter_lc
    cfip_openclash_yaml_supported "$config" || return 1
    local -a domains=() ips=()
    filter_lc="$(printf '%s' "$filter" | tr 'A-Z' 'a-z')"
    IFS=',' read -r -a domains <<<"$domains_csv"
    while IFS= read -r ip; do [[ -n "$ip" ]] && ips+=("$ip"); done < <(jq -r '.[].ip' "$selected")
    ((${#ips[@]} > 0)) || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-intended.XXXXXX")" || return 1
    printf '[]' >"$tmp"
    while IFS= read -r -d '' name && IFS= read -r -d '' type && IFS= read -r -d '' server && IFS= read -r -d '' tls && IFS= read -r -d '' network && IFS= read -r -d '' servername && IFS= read -r -d '' host; do
        [[ -n "$name" ]] || continue
        cfip_openclash_protocol_supported "$type" "$tls" "$network" || continue
        if [[ -n "$filter_lc" && ",${filter_lc}," != *",${network},"* ]]; then continue; fi
        domain=""
        for line in "${domains[@]}"; do
            line="${line#${line%%[![:space:]]*}}"; line="${line%${line##*[![:space:]]}}"
            if [[ "$server" == "$line" || "$servername" == "$line" || "$host" == "$line" ]]; then domain="$line"; break; fi
        done
        [[ -n "$domain" ]] || continue
        base="$name"
        while [[ "$base" =~ ^(.*)[[:space:]]\[CF-[0-9]+\][^[:space:]]*$ ]]; do base="${BASH_REMATCH[1]}"; done
        count=1; [[ -n "$suffix" ]] && count="${#ips[@]}"
        for ((idx=0; idx<count; idx++)); do
            seq=$((idx+1)); ip="${ips[$idx]}"; line="$suffix"; line="${line//\{n\}/$seq}"; line="${line//\{ip\}/$ip}"
            name="$base$line"
            jq -cn --arg name "$name" --arg server "$ip" --arg servername "$domain" --arg network "$network" \
              --argjson hostRequired "$([[ "$network" == ws || "$network" == xhttp ]] && printf true || printf false)" \
              '{name:$name,server:$server,servername:$servername,network:$network,host:(if $hostRequired then $servername else null end)}' \
              >"$tmp.row"
            jq --argjson row "$(cat "$tmp.row")" '. + [$row]' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp" || { rm -f "$tmp" "$tmp.row"; return 1; }
        done
    done < <(cfip_openclash_mapping_tsv "$config")
    mv "$tmp" "$output"
    rm -f "$tmp.row"
}

cfip_openclash_validate_mapping() {
    local intended="$1" actual="$2"
    jq -n -e --slurpfile expected "$intended" --slurpfile observed "$actual" '
      ($expected[0]) as $e | ($observed[0] | map(select(.name|contains("[CF-")))) as $a |
      ($e|length)>0 and ($a|length)==($e|length) and
      (($a | map([.name,.server,.servername,.network,.host] | join("\u0000")) | unique | length) == ($a|length)) and
      all($e[]; . as $wanted | any($a[]; .name==$wanted.name and .server==$wanted.server and .servername==$wanted.servername and .network==$wanted.network and .host==$wanted.host))
    ' >/dev/null
}

cfip_openclash_readback_intended() {
    local selected="$1" config="$2" domains_csv="$3" suffix="$4" filter="${5:-}"
    local actual intended rc ip
    [[ -s "$selected" && -s "$config" ]] || return 1
    actual="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-readback.XXXXXX")" || return 1
    cfip_openclash_actual_mapping "$config" "$actual" || { rm -f "$actual"; return 1; }
    intended="${CFIP_TXN_DIR:+$CFIP_TXN_DIR/openclash-intended.json}"
    if [[ -s "$intended" ]]; then
        cfip_openclash_validate_mapping "$intended" "$actual"; rc=$?
        rm -f "$actual"
        return "$rc"
    fi
    # Compatibility fallback for callers outside a host transaction: require
    # each selected IP to belong to one marked block and validate fields in it.
    while IFS= read -r ip; do
        awk -v wanted="$ip" -v domains="$domains_csv" -v filter="$filter" '
          function ok_domain(v, n,a) { n=split(domains,a,","); for(i=1;i<=n;i++){gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i]); if(v==a[i]) return 1} return 0 }
          function emit(){ if(in_block && server==wanted && index(name,"[CF-") && (servername!="" || host!="") && ok_domain(servername!=""?servername:host) && (filter=="" || ("," filter ",") ~ "," network ",")) found=1 }
          /^[[:space:]]*-[[:space:]]+name:/ { emit(); in_block=1; name=$0; sub(/^.*name:[[:space:]]*/,"",name); server=""; servername=""; host=""; network=""; next }
          in_block && /^[[:space:]]+server:/ { server=$0; sub(/^.*server:[[:space:]]*/,"",server); next }
          in_block && /^[[:space:]]+servername:/ { servername=$0; sub(/^.*servername:[[:space:]]*/,"",servername); next }
          in_block && /^[[:space:]]+Host:/ { host=$0; sub(/^.*Host:[[:space:]]*/,"",host); next }
          in_block && /^[[:space:]]+network:/ { network=$0; sub(/^.*network:[[:space:]]*/,"",network); next }
          END { emit(); exit(found ? 0 : 1) }
        ' "$config" || { rm -f "$actual"; return 1; }
    done < <(jq -r '.[].ip' "$selected")
    rm -f "$actual"
}

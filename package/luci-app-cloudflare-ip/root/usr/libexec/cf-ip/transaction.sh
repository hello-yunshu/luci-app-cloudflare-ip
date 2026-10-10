#!/usr/bin/env bash
# shellcheck shell=bash

CFIP_TXN_DIR=""
CFIP_TXN_ROLLED_BACK=false
CFIP_TXN_STATE=NONE
CFIP_TXN_MODE=""
CFIP_TXN_COMMITTED=false
CFIP_TXN_ORIGINAL_RUNNING=false

cfip_txn_restart_original_service() {
    local service="$1" deadline_class="${2:-normal}"
    [[ "${CFIP_TXN_ORIGINAL_RUNNING:-false}" == true ]] || return 0
    cfip_restart_service "$service" "$deadline_class"
}

cfip_txn_prepare() {
    local mode="$1"
    CFIP_TXN_MODE="$mode"
    CFIP_TXN_COMMITTED=false
    CFIP_TXN_ROLLED_BACK=false
    CFIP_TXN_ORIGINAL_RUNNING=false
    if [[ "$mode" == openclash ]]; then
        cfip_openclash_capture_state || return 20
        [[ "$CFIP_OPENCLASH_INITIAL_HEALTHY" == true ]] && CFIP_TXN_ORIGINAL_RUNNING=true
    elif declare -F cfip_service_running >/dev/null 2>&1 && cfip_service_running "$mode" measurement; then
        CFIP_TXN_ORIGINAL_RUNNING=true
    fi
    CFIP_TXN_DIR="$(mktemp -d "${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/txn-${CFIP_RUN_ID}.XXXXXX")" || return 1
    case "$mode" in
      passwall)
        uci export passwall >"$CFIP_TXN_DIR/passwall.uci" 2>/dev/null || { rm -rf "$CFIP_TXN_DIR"; CFIP_TXN_DIR=""; return 1; }
        if [[ -f "${CFIP_PASSWALL_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/passwall-managed.json}" ]]; then
            cp -p "${CFIP_PASSWALL_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/passwall-managed.json}" "$CFIP_TXN_DIR/passwall-managed.json" || { rm -rf "$CFIP_TXN_DIR"; CFIP_TXN_DIR=""; return 1; }
            printf '%s\n' present >"$CFIP_TXN_DIR/passwall-managed.state"
        else
            printf '%s\n' absent >"$CFIP_TXN_DIR/passwall-managed.state"
        fi
        ;;
      openclash)
        [[ -f "$CFIP_OPENCLASH_CONFIG" ]] || { rm -rf "$CFIP_TXN_DIR"; CFIP_TXN_DIR=""; return 1; }
        cp -p "$CFIP_OPENCLASH_CONFIG" "$CFIP_TXN_DIR/openclash.yaml" || { rm -rf "$CFIP_TXN_DIR"; CFIP_TXN_DIR=""; return 1; }
        printf '%s\n' "$CFIP_OPENCLASH_EXPECTED_ENABLED" >"$CFIP_TXN_DIR/openclash.enable"
        ;;
      *) rm -rf "$CFIP_TXN_DIR"; CFIP_TXN_DIR=""; return 1 ;;
    esac
    CFIP_TXN_STATE=PREPARED
}

cfip_txn_rollback() {
    local mode="$1" txn_dir
    [[ "${CFIP_TXN_ROLLED_BACK:-false}" == true ]] && return 0
    [[ -n "$CFIP_TXN_DIR" && -d "$CFIP_TXN_DIR" ]] || return 1
    [[ "${CFIP_TXN_STATE:-NONE}" != COMMITTED ]] || return 0
    cfip_begin_recovery
    CFIP_TXN_STATE=ROLLING_BACK
    CFIP_TXN_ROLLED_BACK=false
    CFIP_RECOVERY_ERROR=""
    rm -f "$CFIP_TXN_DIR/passwall-managed.json.pending" 2>/dev/null || true
    case "$mode" in
      passwall)
        uci -q revert passwall || true
        uci import passwall <"$CFIP_TXN_DIR/passwall.uci" >/dev/null 2>&1 || return 1
        uci commit passwall >/dev/null 2>&1 || return 1
        local state_file="${CFIP_PASSWALL_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/passwall-managed.json}"
        if [[ "$(cat "$CFIP_TXN_DIR/passwall-managed.state" 2>/dev/null || printf absent)" == present ]]; then
            mkdir -p "${state_file%/*}" 2>/dev/null || return 1
            cp -p "$CFIP_TXN_DIR/passwall-managed.json" "${state_file}.rollback.$$" || return 1
            mv "${state_file}.rollback.$$" "$state_file" || return 1
        else
            rm -f "$state_file" || return 1
        fi
        local recovery_rc=0
        cfip_txn_restart_original_service passwall recovery || recovery_rc=$?
        if ((recovery_rc != 0)); then
            ((recovery_rc == 124)) && CFIP_RECOVERY_ERROR="RecoveryTimeout" || CFIP_RECOVERY_ERROR="RecoveryRestartFailed"
            return 1
        fi
        uci export passwall 2>/dev/null | cmp -s - "$CFIP_TXN_DIR/passwall.uci" || return 1
        CFIP_TXN_ROLLED_BACK=true
        CFIP_TXN_STATE=ROLLED_BACK
        ;;
      openclash)
        # A failed normal startup is final for this run. Keep its node file,
        # snapshot and OpenClash's own failure state for diagnosis.
        if { ((CFIP_OPENCLASH_RESTART_ATTEMPTS > 0)) || [[ "$CFIP_OPENCLASH_CF_STOPPED" == true && "$CFIP_OPENCLASH_RECOVERY_ATTEMPTED" == true ]]; } && [[ "$CFIP_OPENCLASH_SERVICE_APPLIED" != true ]]; then
            CFIP_STOPPED_MODE=""
            CFIP_RECOVERY_ERROR="${CFIP_OPENCLASH_SERVICE_ERROR:-OpenClashRecoveryFailed}"
            return 1
        fi
        local restored_config=false config_conflict=false
        if cmp -s "$CFIP_OPENCLASH_CONFIG" "$CFIP_TXN_DIR/openclash.yaml"; then
            :
        elif [[ -f "$CFIP_TXN_DIR/openclash.written.yaml" ]] && cmp -s "$CFIP_OPENCLASH_CONFIG" "$CFIP_TXN_DIR/openclash.written.yaml"; then
            cp "$CFIP_TXN_DIR/openclash.yaml" "${CFIP_OPENCLASH_CONFIG}.rollback.$$" || return 1
            mv "${CFIP_OPENCLASH_CONFIG}.rollback.$$" "$CFIP_OPENCLASH_CONFIG" || return 1
            restored_config=true
        else
            config_conflict=true
            CFIP_RECOVERY_ERROR="OpenClash config changed outside this transaction; preserved current file and snapshot"
        fi
        if [[ "$CFIP_OPENCLASH_EXPECTED_ENABLED" == 1 ]] && {
            [[ "$CFIP_OPENCLASH_CF_STOPPED" == true && "$CFIP_OPENCLASH_RECOVERY_ATTEMPTED" != true ]] ||
            [[ "$restored_config" == true && "$CFIP_OPENCLASH_SERVICE_APPLIED" == true ]];
        }; then
            local recovery_rc=0
            CFIP_OPENCLASH_RECOVERY_ATTEMPTED=true
            cfip_txn_restart_original_service openclash recovery || recovery_rc=$?
            CFIP_STOPPED_MODE=""
            if ((recovery_rc != 0)); then
                CFIP_RECOVERY_ERROR="${CFIP_OPENCLASH_SERVICE_ERROR:-OpenClashRecoveryFailed}"
                return 1
            fi
            [[ "$restored_config" != true ]] || CFIP_OPENCLASH_SERVICE_APPLIED=false
        else
            # A disabled service is deliberately left disabled. Do not rewrite
            # UCI on rollback; this preserves detectable user changes.
            CFIP_STOPPED_MODE=""
        fi
        [[ "$config_conflict" != true ]] || return 1
        CFIP_TXN_ROLLED_BACK=true
        CFIP_TXN_STATE=ROLLED_BACK
        ;;
      *) return 1 ;;
    esac
    txn_dir="$CFIP_TXN_DIR"
    CFIP_TXN_DIR=""
    [[ -z "$txn_dir" ]] || rm -rf "$txn_dir" 2>/dev/null || true
}

cfip_txn_commit() {
    if [[ -n "$CFIP_TXN_DIR" && -f "$CFIP_TXN_DIR/passwall-managed.json.pending" ]]; then
        mv "$CFIP_TXN_DIR/passwall-managed.json.pending" "${CFIP_PASSWALL_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/passwall-managed.json}" || return 1
    fi
    [[ -n "$CFIP_TXN_DIR" ]] && rm -rf "$CFIP_TXN_DIR" 2>/dev/null || true
    CFIP_TXN_STATE=COMMITTED
    CFIP_TXN_COMMITTED=true
    CFIP_TXN_DIR=""
}

cfip_passwall_apply_selected() {
    local selected="$1" line key value section domain ip idx=0 count
    local -a domains=() sections=() section_domains=() base_names=() old_addresses=() old_remarks_list=()
    local state_file="${CFIP_PASSWALL_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/passwall-managed.json}"
    local pending_state_file="${CFIP_TXN_DIR:+$CFIP_TXN_DIR/passwall-managed.json.pending}"
    local state='{"sections":[]}' state_section saved_domain saved_address saved_remarks current_address current_remarks
    local base_remarks new_remarks entries tmp
    CFIP_PASSWALL_UPDATED=0
    IFS=',' read -r -a domains <<<"$CFIP_PASSWALL_TARGET_DOMAIN"
    count="$(jq 'length' "$selected" 2>/dev/null || printf 0)"; ((count > 0)) || return 1
    [[ -e "$state_file" ]] && { jq empty "$state_file" >/dev/null 2>&1 || return 1; state="$(cat "$state_file")"; }

    # Recover owned sections first. Once an address is managed, its current IP is
    # authoritative; relying only on address==target_domain loses it on rerun.
    while IFS=$'\t' read -r state_section saved_domain saved_address saved_remarks; do
        [[ -n "$state_section" ]] || continue
        current_address="$(uci -q get "passwall.${state_section}.address" 2>/dev/null || true)"
        current_remarks="$(uci -q get "passwall.${state_section}.remarks" 2>/dev/null || true)"
        [[ -n "$current_address" ]] || continue
        if [[ "$current_address" != "$saved_address" && "$current_address" != "$saved_domain" ]]; then
            cfip_log "PassWall ownership conflict in section ${state_section}; refusing to guess"
            return 1
        fi
        if [[ -n "$saved_remarks" && "$current_remarks" != "$saved_remarks" ]]; then
            cfip_log "PassWall user edit conflict in section ${state_section}; refusing to overwrite"
            return 1
        fi
        local still_target=false active_domain managed_base
        for active_domain in "${domains[@]}"; do
            [[ "$active_domain" == "$saved_domain" ]] && still_target=true
        done
        if [[ "$still_target" != true ]]; then
            managed_base="$(jq -r --arg s "$state_section" '.sections[]|select(.section==$s)|.baseRemarks//""' <<<"$state")"
            uci set "passwall.${state_section}.address=${saved_domain}" >/dev/null || return 1
            [[ -z "$managed_base" ]] || uci set "passwall.${state_section}.remarks=${managed_base}" >/dev/null || return 1
            cfip_log "PassWall ownership relinquished for removed target ${saved_domain} in ${state_section}"
            continue
        fi
        sections+=("$state_section"); section_domains+=("$saved_domain"); base_names+=("$(jq -r --arg s "$state_section" '.sections[]|select(.section==$s)|.baseRemarks//""' <<<"$state")"); old_addresses+=("$current_address"); old_remarks_list+=("$current_remarks")
    done < <(jq -r '.sections[]? | [.section,.domain,.lastAddress,.lastRemarks] | @tsv' <<<"$state")

    # First-run and newly-added domains still use the legacy domain lookup.
    while IFS= read -r line; do
        [[ "$line" == passwall.*.address=* ]] || continue
        key="${line%%=*}"; value="${line#*=}"; value="${value#\'}"; value="${value%\'}"; value="${value#\"}"; value="${value%\"}"
        section="${key#passwall.}"; section="${section%.address}"
        for domain in "${domains[@]}"; do
            [[ "$value" == "$domain" ]] || continue
            local known=false existing
            for existing in "${sections[@]-}"; do [[ "$existing" == "$section" ]] && known=true; done
            [[ "$known" == true ]] && break
            current_remarks="$(uci -q get "passwall.${section}.remarks" 2>/dev/null || true)"
            base_remarks="$(cfip_passwall_base_remarks "$current_remarks")"
            sections+=("$section"); section_domains+=("$domain"); base_names+=("$base_remarks"); old_addresses+=("$value"); old_remarks_list+=("$current_remarks")
            break
        done
    done < <(uci show passwall 2>/dev/null)
    ((${#sections[@]} > 0)) || return 1

    tmp="$(mktemp "${CFIP_RUNTIME_DIR:-/tmp}/passwall-managed.XXXXXX")" || return 1
    printf '[]' >"$tmp"
    for idx in "${!sections[@]}"; do
        section="${sections[$idx]}"; domain="${section_domains[$idx]}"; ip="$(jq -r --argjson i "$((idx%count))" '.[$i].ip' "$selected")"
        [[ "$ip" != null && -n "$ip" ]] || { rm -f "$tmp"; return 1; }
        uci set "passwall.${section}.address=${ip}" >/dev/null || { rm -f "$tmp"; return 1; }
        base_remarks="${base_names[$idx]}"; new_remarks="${old_remarks_list[$idx]}"
        if [[ -n "${CFIP_PASSWALL_NAME_SUFFIX:-}" && -n "$base_remarks" ]]; then
            new_remarks="${base_remarks}$(cfip_passwall_expand_suffix "$CFIP_PASSWALL_NAME_SUFFIX" "$((idx+1))" "$ip")"
            uci set "passwall.${section}.remarks=${new_remarks}" >/dev/null || { rm -f "$tmp"; return 1; }
        fi
        jq --arg section "$section" --arg domain "$domain" --arg base "$base_remarks" --arg address "$ip" --arg remarks "$new_remarks" '. + [{section:$section,domain:$domain,baseRemarks:$base,lastAddress:$address,lastRemarks:$remarks}]' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp" || { rm -f "$tmp"; return 1; }
    done
    uci commit passwall >/dev/null || { rm -f "$tmp"; return 1; }
    for idx in "${!sections[@]}"; do
        section="${sections[$idx]}"; ip="$(jq -r --arg s "$section" '.[]|select(.section==$s)|.lastAddress' "$tmp")"
        [[ "$(uci -q get "passwall.${section}.address" 2>/dev/null || true)" == "$ip" ]] || { rm -f "$tmp"; return 1; }
    done
    [[ -n "$pending_state_file" ]] || pending_state_file="$state_file"
    jq -n --argjson sections "$(cat "$tmp")" '{schemaVersion:1,sections:$sections}' | cfip_atomic_write "$pending_state_file" || { rm -f "$tmp"; return 1; }
    CFIP_PASSWALL_UPDATED="${#sections[@]}"
    rm -f "$tmp"
    [[ "${CFIP_TXN_APPLY:-false}" == true ]] || cfip_restart_service passwall
}

# OpenClash uses the full 1.8.3 transformer through an explicit selected-IP
# entry point. Candidate selection remains owned by v2; YAML transformation,
# protocol filtering, suffix rerun behavior and backup rotation remain legacy-
# compatible and are executed inside this transaction boundary.
cfip_openclash_apply_selected() {
    local selected="$1"
    cfip_openclash_intended_from_templates "$selected" "$CFIP_TXN_DIR/openclash.yaml" "$CFIP_TARGET_DOMAINS" "$CFIP_OPENCLASH_NAME_SUFFIX" "$CFIP_OPENCLASH_TRANSPORT_FILTER" "$CFIP_TXN_DIR/openclash-intended.json" || return 1
    cfip_openclash_transform_selected "$selected"
}

cfip_openclash_readback_selected() {
    cfip_openclash_readback_intended "$1" "$CFIP_OPENCLASH_CONFIG" "$CFIP_TARGET_DOMAINS" "$CFIP_OPENCLASH_NAME_SUFFIX" "$CFIP_OPENCLASH_TRANSPORT_FILTER"
}

cfip_passwall_base_remarks() {
    local value="$1"
    while [[ "$value" =~ ^(.*)[[:space:]]\[CF-[^]]+\]$ ]]; do value="${BASH_REMATCH[1]}"; done
    printf '%s' "$value"
}

cfip_passwall_expand_suffix() {
    local suffix="$1" seq="$2" ip="$3"
    suffix="${suffix//\{n\}/$seq}"
    suffix="${suffix//\{ip\}/$ip}"
    printf '%s' "$suffix"
}

cfip_txn_apply() {
    local mode="$1" selected="$2"
    [[ -n "$CFIP_TXN_DIR" && -d "$CFIP_TXN_DIR" ]] || cfip_txn_prepare "$mode" || return 10
    CFIP_TXN_MODE="$mode"
    if [[ "$mode" == openclash ]]; then
        cfip_openclash_check_before_write || return 17
        cmp -s "$CFIP_OPENCLASH_CONFIG" "$CFIP_TXN_DIR/openclash.yaml" || {
            CFIP_OPENCLASH_SERVICE_ERROR="OpenClash config changed before node write; preserved external changes"
            return 17
        }
    fi
    CFIP_TXN_STATE=MUTATED
    CFIP_TXN_APPLY=true
    case "$mode" in
      passwall)
        if ! cfip_passwall_apply_selected "$selected"; then
            CFIP_TXN_APPLY=false
            if cfip_txn_rollback "$mode"; then return 11; else return 12; fi
        fi
        if ! cfip_txn_restart_original_service passwall normal; then
            CFIP_TXN_APPLY=false
            if cfip_txn_rollback "$mode"; then return 11; else return 12; fi
        fi
        [[ "${CFIP_TXN_ORIGINAL_RUNNING:-false}" == true ]] && CFIP_TXN_STATE=RESTARTED
        ;;
      openclash)
        if ! cfip_openclash_apply_selected "$selected"; then
            cmp -s "$CFIP_OPENCLASH_CONFIG" "$CFIP_TXN_DIR/openclash.yaml" || CFIP_OPENCLASH_FILE_WRITTEN=true
            CFIP_TXN_APPLY=false
            if cfip_txn_rollback "$mode"; then return 13; else return 14; fi
        fi
        CFIP_OPENCLASH_FILE_WRITTEN=true
        cp -p "$CFIP_OPENCLASH_CONFIG" "$CFIP_TXN_DIR/openclash.written.yaml" || return 14
        if ! cfip_openclash_readback_selected "$selected"; then
            CFIP_TXN_APPLY=false
            if cfip_txn_rollback "$mode"; then return 15; else return 16; fi
        fi
        if [[ "${CFIP_OPENCLASH_EXPECTED_ENABLED:-}" == 1 ]] && ! cfip_txn_restart_original_service openclash normal; then
            CFIP_TXN_APPLY=false
            if cfip_txn_rollback "$mode"; then return 15; else return 16; fi
        fi
        [[ "${CFIP_TXN_ORIGINAL_RUNNING:-false}" == true && "${CFIP_OPENCLASH_SERVICE_APPLIED:-false}" == true ]] && CFIP_TXN_STATE=RESTARTED
        ;;
      *) CFIP_TXN_APPLY=false; return 10 ;;
    esac
    CFIP_TXN_APPLY=false
}

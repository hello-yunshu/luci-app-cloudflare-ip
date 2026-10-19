#!/bin/sh
# Serialize PID-directory acquisition/recovery/release on one persistent inode.
# The gate is held only during metadata operations, not for the whole task.

_cf_ip_writer_gate_enter() {
	local root="$1" attempts="${2:-1}" gate count=0 gate_rc=0
	CF_IP_WRITER_LOCK_ERROR=
	CF_IP_WRITER_LOCK_RC=0
	case "$root" in /*) ;; *) CF_IP_WRITER_LOCK_ERROR=unsafe_runtime; return 1 ;; esac
	[ "$root" != / ] && [ ! -L "$root" ] || { CF_IP_WRITER_LOCK_ERROR=unsafe_runtime; return 1; }
	command -v "${CFIP_FLOCK:-flock}" >/dev/null 2>&1 || { CF_IP_WRITER_LOCK_ERROR=flock_unavailable; return 1; }
	mkdir -p "$root" || { CF_IP_WRITER_LOCK_ERROR=runtime_unavailable; return 1; }
	[ -d "$root" ] && [ -O "$root" ] || { CF_IP_WRITER_LOCK_ERROR=unsafe_runtime; return 1; }
	gate="$root/.cf-ip-writer-gate"
	[ ! -L "$gate" ] || { CF_IP_WRITER_LOCK_ERROR=unsafe_gate; return 1; }
	if [ -e "$gate" ]; then
		[ -f "$gate" ] && [ -O "$gate" ] || { CF_IP_WRITER_LOCK_ERROR=unsafe_gate; return 1; }
	else
		(umask 077; : >>"$gate") || { CF_IP_WRITER_LOCK_ERROR=gate_unavailable; return 1; }
	fi
	# Bash 3 crashes on command-exec FD restoration; dash needs command to
	# keep a redirection failure from terminating the whole RPC interpreter.
	if [ -n "${BASH_VERSION:-}" ]; then
		if ! exec 9>>"$gate"; then CF_IP_WRITER_LOCK_ERROR=gate_unavailable; return 1; fi
	else
		if ! command exec 9>>"$gate"; then CF_IP_WRITER_LOCK_ERROR=gate_unavailable; return 1; fi
	fi
	while :; do
		if "${CFIP_FLOCK:-flock}" -n 9 2>/dev/null; then CF_IP_WRITER_LOCK_RC=0; break; else gate_rc=$?; fi
		CF_IP_WRITER_LOCK_RC="$gate_rc"
		if [ "$gate_rc" -ne 1 ]; then exec 9>&-; CF_IP_WRITER_LOCK_ERROR=flock_failed; return 1; fi
		count=$((count+1))
		if [ "$count" -ge "$attempts" ]; then exec 9>&-; CF_IP_WRITER_LOCK_ERROR=gate_busy; return 1; fi
		sleep 1
	done
}

_cf_ip_writer_gate_leave() { exec 9>&-; }

_cf_ip_writer_pid_alive() {
	kill -0 "$1" 2>/dev/null && return 0
	[ ! -d "/proc/$1" ] || return 0
	case "$(uname -s)" in
		Darwin) ps -p "$1" -o pid= >/dev/null 2>&1 ;;
		*) [ -d /proc ] || return 0; return 1 ;;
	esac
}

_cf_ip_writer_acquire_guarded() {
	local root="$1" lock="$1/cf-ip-auto-v2.lock" pid entry
	if [ -e "$lock" ] || [ -L "$lock" ]; then
		[ -d "$lock" ] && [ ! -L "$lock" ] && [ -O "$lock" ] && [ -f "$lock/pid" ] && [ ! -L "$lock/pid" ] && [ -O "$lock/pid" ] || { CF_IP_WRITER_LOCK_ERROR=invalid_lock; return 1; }
		pid="$(cat "$lock/pid")" || { CF_IP_WRITER_LOCK_ERROR=invalid_lock; return 1; }
		case "$pid" in ''|0*|*[!0-9]*|???????????*) CF_IP_WRITER_LOCK_ERROR=invalid_lock; return 1 ;; esac
		_cf_ip_writer_pid_alive "$pid" && { CF_IP_WRITER_LOCK_ERROR=lock_busy; return 1; }
		# Do not recursively remove unknown entries in a stale lock namespace.
		for entry in "$lock"/* "$lock"/.[!.]* "$lock"/..?*; do
			[ -e "$entry" ] || [ -L "$entry" ] || continue
			[ "$entry" = "$lock/pid" ] || { CF_IP_WRITER_LOCK_ERROR=invalid_lock; return 1; }
		done
		rm -f "$lock/pid" && rmdir "$lock" || { CF_IP_WRITER_LOCK_ERROR=cleanup_failed; return 1; }
	fi
	mkdir "$lock" 2>/dev/null || { CF_IP_WRITER_LOCK_ERROR=lock_busy; return 1; }
	if printf '%s\n' "$$" >"$lock/pid"; then :; else
		CF_IP_WRITER_LOCK_RC=$?
		# Remove only our newly created regular PID candidate, not a link or
		# unexpected directory. A transient partial write must be retryable.
		if [ -f "$lock/pid" ] && [ ! -L "$lock/pid" ] && [ -O "$lock/pid" ]; then rm -f "$lock/pid" || true; fi
		rmdir "$lock" 2>/dev/null || true
		CF_IP_WRITER_LOCK_ERROR=pid_write_failed
		return 1
	fi
}

cf_ip_writer_lock_acquire() {
	local rc
	_cf_ip_writer_gate_enter "$1" || return 1
	if _cf_ip_writer_acquire_guarded "$1"; then rc=0; else rc=$?; fi
	_cf_ip_writer_gate_leave
	return "$rc"
}

cf_ip_writer_lock_release() {
	local root="$1" lock="$1/cf-ip-auto-v2.lock" rc=0
	_cf_ip_writer_gate_enter "$root" 3 || return 1
	if [ -d "$lock" ] && [ ! -L "$lock" ] && [ -O "$lock" ] && [ -f "$lock/pid" ] && [ ! -L "$lock/pid" ] && [ -O "$lock/pid" ] && [ "$(cat "$lock/pid" 2>/dev/null)" = "$$" ]; then
		rm -f "$lock/pid" && rmdir "$lock" 2>/dev/null || rc=1
	fi
	_cf_ip_writer_gate_leave
	return "$rc"
}

cf_ip_writer_lock_message() {
	case "${CF_IP_WRITER_LOCK_ERROR:-}" in
		flock_failed) printf 'writer lock unavailable: flock failed (rc=%s)' "${CF_IP_WRITER_LOCK_RC:-1}" ;;
		flock_unavailable) printf 'writer lock unavailable: flock is missing' ;;
		unsafe_runtime|unsafe_gate|invalid_lock) printf 'writer lock metadata is unsafe or incomplete' ;;
		runtime_unavailable|gate_unavailable|pid_write_failed|cleanup_failed) printf 'failed to initialize writer lock metadata' ;;
		*) printf 'another v2 instance is running' ;;
	esac
}

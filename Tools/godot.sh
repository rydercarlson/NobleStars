#!/bin/bash
# Run Godot on a Noble Stars project directory under a real lock.
#
# Why this exists: two Godot processes on the SAME project directory contend on
# the import lock hard enough to look like a hang — an import that takes 1.2s
# alone has sat for six minutes beside a second instance. Every ad-hoc attempt
# to detect that by hand has gone wrong at least once:
#
#   * `ps -eo command | grep Godot` matches the shell running your own detector,
#     so it reports a held lock forever, including when the lock is free.
#   * `pgrep -x Godot` alone over-matches the other way: another agent running
#     NS3_SIM on its own worktree copy holds no lock of yours, and waiting on it
#     stalls indefinitely.
#   * `pkill Godot` leaves the shell that launched it alive, and that shell
#     starts the next Godot in its chain minutes later and retakes the lock.
#   * A human playing the game looks exactly like a stale agent process, and
#     killing the wrong one closes the game out from under them.
#
# So this refuses rather than clearing, and it NEVER kills anything. The lock is
# keyed on the resolved project directory, so separate git worktrees — which
# each have their own `.godot` cache and their own real lock — do not block each
# other. That is the whole point: it is per project, not per machine.
#
#   Tools/godot.sh --path godot --headless --import
#   NS3_KIT=nova Tools/godot.sh --path godot
#   Tools/godot.sh --wait 120 --path godot --headless --script res://tools/sfx_probe.gd
#   Tools/godot.sh --status --path godot
#
# Options consumed by the wrapper (everything else is passed through verbatim):
#   --wait <seconds>   block until the project is free, then run; default 0 (refuse immediately)
#   --status           report who holds the project and exit
#   --no-lock          run without taking or checking the lock
#
# `--no-lock` exists for ONE case: the wifi-play test harness, which is two
# instances of the SAME project on purpose (NS3_HOST on one, NS3_JOIN=127.0.0.1
# on the other). That is a documented, supported thing to do — the contention
# this wrapper prevents is on the IMPORT, and by the time you are running the
# harness the project is already imported. Import once, normally, then start
# both halves with --no-lock. Do not reach for it to get past a refusal you did
# not expect: that refusal is the wrapper doing its job.
#
# Exit codes: 0 ok, 1 wrapper usage error, 2 wrapper error, 75 project busy
# (75 = EX_TEMPFAIL, i.e. "try again", distinct from anything Godot itself returns).

set -u

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
BUSY=75

wait_secs=0
status_only=0
no_lock=0

# --- split the wrapper's own flags out of the Godot argument list ------------
godot_args=()
while [ $# -gt 0 ]; do
	case "$1" in
		--wait)
			[ $# -ge 2 ] || { echo "godot.sh: --wait needs a value" >&2; exit 1; }
			wait_secs="$2"; shift 2 ;;
		--wait=*)
			wait_secs="${1#--wait=}"; shift ;;
		--status)
			status_only=1; shift ;;
		--no-lock)
			no_lock=1; shift ;;
		*)
			godot_args+=("$1"); shift ;;
	esac
done

case "$wait_secs" in
	''|*[!0-9]*) echo "godot.sh: --wait wants whole seconds, got '$wait_secs'" >&2; exit 1 ;;
esac

# --- work out which project directory this invocation is about --------------
# Godot takes `--path <dir>`; accept `--path=<dir>` too. With neither, Godot
# uses the working directory, so we do the same.
project=""
i=0
n=${#godot_args[@]}
while [ $i -lt $n ]; do
	a="${godot_args[$i]}"
	case "$a" in
		--path)
			j=$((i + 1))
			[ $j -lt $n ] && project="${godot_args[$j]}" ;;
		--path=*)
			project="${a#--path=}" ;;
	esac
	i=$((i + 1))
done
[ -n "$project" ] || project="$PWD"

# Resolve to an absolute real path so `--path godot`, `--path .` from inside it
# and an absolute path all key the same lock. `cd -P` rather than realpath,
# which is not on a stock macOS.
if ! project_abs="$(cd "$project" 2>/dev/null && pwd -P)"; then
	echo "godot.sh: no such directory: $project" >&2
	exit 2
fi

# No project file means no import lock to protect — nothing to serialise.
if [ ! -f "$project_abs/project.godot" ]; then
	[ "$status_only" -eq 1 ] && { echo "godot.sh: $project_abs is not a Godot project"; exit 0; }
	exec "$GODOT_BIN" "${godot_args[@]+"${godot_args[@]}"}"
fi

if [ "$no_lock" -eq 1 ] && [ "$status_only" -eq 0 ]; then
	echo "godot.sh: --no-lock, running unguarded on $project_abs" >&2
	exec "$GODOT_BIN" "${godot_args[@]+"${godot_args[@]}"}"
fi

# Shared across sessions and users of this machine, so /tmp rather than TMPDIR
# (which on macOS is per-user and would let two accounts collide silently).
key="$(printf '%s' "$project_abs" | shasum | cut -c1-12)"
lock="/tmp/noblestars-godot-$key.lock"
owner_file="$lock/owner"

alive() { kill -0 "$1" 2>/dev/null; }

describe_pid() {
	ps -o args= -p "$1" 2>/dev/null | head -1 | cut -c1-160
}

# The working directory of a running process, which is what a relative
# `--path godot` resolves against. lsof is the only way to get it on macOS and
# it can fail (permissions, a process exiting under us) — callers treat an
# empty answer as "unknown", never as "does not match".
pid_cwd() {
	lsof -a -d cwd -p "$1" -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
}

abs_project_dir() {
	local d
	d="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
	[ -f "$d/project.godot" ] || return 1
	echo "$d"
}

# The absolute project directory a running Godot is serving, or "" if it cannot
# be determined.
#
# The load-bearing fact, found by measuring rather than reasoning: **a running
# Godot has already chdir'd into its own project directory**, so its cwd IS the
# answer. The first version of this resolved `--path godot` against the process
# cwd and got `<project>/godot/godot`, which does not exist — so every foreign
# Godot came back unresolvable and the wrapper cheerfully ran a second one
# alongside it. Only an ABSOLUTE `--path` is trusted ahead of the cwd, since
# that one is unambiguous even in the moment before the chdir lands.
godot_project_of() {
	local pid="$1" args cwd raw
	args="$(ps -o args= -p "$pid" 2>/dev/null)" || return 0
	[ -n "$args" ] || return 0
	raw="$(printf '%s\n' "$args" | awk '{
		for (i = 1; i <= NF; i++) {
			if ($i == "--path" && i < NF) { print $(i + 1); exit }
			if ($i ~ /^--path=/) { sub(/^--path=/, "", $i); print $i; exit }
		}
	}')"
	case "$raw" in
		/*) abs_project_dir "$raw" && return 0 ;;
	esac
	cwd="$(pid_cwd "$pid")"
	[ -n "$cwd" ] || return 0
	abs_project_dir "$cwd" && return 0
	# Only reachable in the window before Godot has chdir'd, where the cwd is
	# still the shell's and a relative --path resolves against it.
	[ -n "$raw" ] && abs_project_dir "$cwd/$raw"
	return 0
}

# Any Godot on OUR project that did not come through this wrapper — a human
# playing the game, or a session that ran the binary directly. `pgrep -x`
# matches the binary by exact process name, so unlike `ps | grep` it can never
# match the shell running this script.
foreign_holder() {
	local pid proj
	for pid in $(pgrep -x Godot 2>/dev/null); do
		proj="$(godot_project_of "$pid")"
		[ "$proj" = "$project_abs" ] && { echo "$pid"; return 0; }
	done
	return 1
}

# Who has the project right now: "<kind> <pid>", or nothing when it is free.
# A lock whose owner has died is stale and is reported as such by the caller.
current_holder() {
	local pid
	if [ -d "$lock" ]; then
		pid="$(sed -n '1p' "$owner_file" 2>/dev/null)"
		if [ -n "$pid" ] && alive "$pid"; then
			echo "lock $pid"
			return 0
		fi
		echo "stale ${pid:-?}"
		return 0
	fi
	if pid="$(foreign_holder)"; then
		echo "foreign $pid"
		return 0
	fi
	return 1
}

report_holder() {
	local kind="$1" pid="$2" parent pcmd
	case "$kind" in
		lock)
			echo "godot.sh: $project_abs is in use by godot.sh (pid $pid)" >&2
			echo "  $(describe_pid "$pid")" >&2
			echo "  Wait for it, or re-run with --wait <seconds>." >&2 ;;
		foreign)
			parent="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
			pcmd="$(ps -o args= -p "${parent:-0}" 2>/dev/null | head -1)"
			echo "godot.sh: $project_abs already has a Godot running (pid $pid)" >&2
			echo "  $(describe_pid "$pid")" >&2
			echo "  parent: $(printf '%s' "${pcmd:-unknown}" | cut -c1-100)" >&2
			# Whose Godot this is comes off the parent's argv[0], NOT off a
			# substring of the whole command line: a login shell is spelt with a
			# leading dash (`-zsh`), while a Claude/CI job is `/bin/zsh -c …`.
			# Matching the line as a whole gets this backwards, because the
			# wrapper's own `…/shell-snapshots/snapshot-zsh-….sh` argument
			# contains the literal `-zsh` an interactive shell is identified by.
			case "$(printf '%s' "$pcmd" | awk '{print $1}')" in
				-*)
					echo "  That parent is an interactive login shell — this is very likely a" >&2
					echo "  PERSON playing the game. Do NOT kill it. Wait, or skip the run." >&2 ;;
				*)
					case " $pcmd " in
						*" -c "*)
							echo "  That parent is a script/agent job, not a person. Kill the JOB if" >&2
							echo "  you own it — killing the binary alone leaves the shell to start" >&2
							echo "  the next Godot in its chain and retake the project." >&2 ;;
						*)
							echo "  Unidentified. Do not kill a Godot you have not positively" >&2
							echo "  identified as yours; wait, or skip the run." >&2 ;;
					esac ;;
			esac ;;
	esac
}

if [ "$status_only" -eq 1 ]; then
	echo "project: $project_abs"
	echo "lock:    $lock"
	if holder="$(current_holder)"; then
		set -- $holder
		case "$1" in
			stale) echo "holder:  none (stale lock from pid $2, will be reclaimed)" ;;
			*)     echo "holder:  $1 pid $2"
			       echo "         $(describe_pid "$2")" ;;
		esac
	else
		echo "holder:  none — free"
	fi
	exit 0
fi

# --- acquire ----------------------------------------------------------------
# `mkdir` is the atomic primitive: it either creates the directory or fails, with
# no window between the two. A lockfile written with `>` has one.
acquired=0
deadline=$(( $(date +%s) + wait_secs ))

while :; do
	if pid="$(foreign_holder)"; then
		holder_kind="foreign"; holder_pid="$pid"
	elif mkdir "$lock" 2>/dev/null; then
		printf '%s\n%s\n%s\n' "$$" "$project_abs" "$(date '+%Y-%m-%d %H:%M:%S')" > "$owner_file"
		acquired=1
		break
	else
		holder_pid="$(sed -n '1p' "$owner_file" 2>/dev/null)"
		if [ -z "$holder_pid" ] || ! alive "$holder_pid"; then
			# The owner is gone. Reclaim rather than refuse — a stale lock is the
			# one case where clearing is correct, because there is provably
			# nothing running behind it.
			rm -rf "$lock"
			continue
		fi
		holder_kind="lock"
	fi

	[ "$(date +%s)" -lt "$deadline" ] || break
	sleep 2
done

if [ "$acquired" -ne 1 ]; then
	report_holder "$holder_kind" "$holder_pid"
	exit $BUSY
fi

release() {
	rm -rf "$lock"
}
trap 'release' EXIT
# Killing the wrapper releases the lock and takes Godot with it, which is the
# "kill the job, not the binary" rule made automatic.
trap 'release; exit 130' INT
trap 'release; exit 143' TERM

"$GODOT_BIN" "${godot_args[@]+"${godot_args[@]}"}"
exit $?

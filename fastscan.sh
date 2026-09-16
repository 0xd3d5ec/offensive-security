#!/usr/bin/env bash
#
# fastscan.sh - rustscan + nmap wrapper for fast full-range TCP/UDP scanning.
#
# Strategy:
#   Phase 1 (discovery): rustscan blasts all 65535 TCP ports (falls back to a
#                        high-rate nmap SYN sweep if rustscan isn't installed).
#   Phase 2 (enumeration): nmap -sV + scripts against ONLY the open ports
#                        found in phase 1.
#   UDP: nmap -sU runs concurrently with the TCP phases (rustscan is TCP-only).
#
set -Eeuo pipefail

VERSION="1.2.0"
PROG="${0##*/}"

# ---------------------------------------------------------------- defaults ---
TARGETS=()
TARGETS_FILE=""
THREADS=4500           # rustscan batch size / nmap min-parallelism
PORTS=""               # empty => full range for TCP, top-ports for UDP
DO_TCP=1
DO_UDP=1
UDP_ALL=0
UDP_TOP=100
TIMEOUT=1500           # rustscan per-port timeout (ms)
MIN_RATE=5000          # nmap packets/sec
NMAP_TIMING="-T4"
OUTDIR=""
SCRIPTS="default"      # nmap --script value; "none" to skip
EXTRA_NMAP=()
ASSUME_YES=0
QUIET=0
NO_PING=1
HOST_TIMEOUT="20m"     # nmap --host-timeout for -sV/UDP phases; 0 disables

# ------------------------------------------------------------------ colors ---
if [[ -t 1 ]]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; C=$'\e[36m'; N=$'\e[0m'
else
  R=""; G=""; Y=""; B=""; C=""; N=""
fi
log()  { (( QUIET )) || printf '%s[*]%s %s\n' "$B" "$N" "$*" >&2; }
ok()   { (( QUIET )) || printf '%s[+]%s %s\n' "$G" "$N" "$*" >&2; }
warn() { printf '%s[!]%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s[-]%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() {
cat <<EOF
${C}$PROG v$VERSION${N} - fast TCP+UDP port scanner (rustscan -> nmap)

${C}USAGE${N}
  $PROG -t <target[,target...]> [options]
  $PROG <target> [<target>...] [options]

${C}TARGETS${N} (at least one required; all forms can be combined)
  -t, --target <spec>     IP, hostname, or CIDR. Comma-separated lists are
                          fine (10.0.0.1,10.0.0.5,192.168.1.0/24) and the
                          flag can be repeated.
  -f, --file <path>       File of targets, one per line ('#' comments and
                          blank lines ignored).

${C}COMMON${N}
  -T, --threads <n>       Parallelism. rustscan batch size / nmap
                          --min-parallelism. Default: $THREADS
  -p, --ports <spec>      Scan only these ports (e.g. 22,80,443 or 1-1024).
                          Default: ALL 65535 TCP ports, top-$UDP_TOP UDP.
  -o, --outdir <dir>      Write results here. Default: ./scan-<target>-<ts>
  -h, --help              This help.

${C}PROTOCOL SELECTION${N}
      --tcp-only          Skip the UDP scan.
      --udp-only          Skip the TCP scan.
      --udp-all           Scan all 65535 UDP ports (VERY slow - hours).
      --udp-top <n>       UDP top-N ports. Default: $UDP_TOP

${C}TUNING${N}
      --timeout <ms>      rustscan per-port timeout. Default: $TIMEOUT
      --min-rate <pps>    nmap min packet rate. Default: $MIN_RATE
      --timing <T0-T5>    nmap timing template. Default: $NMAP_TIMING
      --scripts <spec>    nmap --script value. Default: $SCRIPTS ("none" to skip)
      --ping              Allow host discovery (default sends -Pn).
      --host-timeout <t>  Give up on a host after this long in the -sV/UDP
                          phases (e.g. 10m, 600s; "0" = no limit). Default: $HOST_TIMEOUT
  -y, --yes               Don't prompt for confirmation.
  -q, --quiet             Only the final results table.
      --                  Everything after this is passed straight to nmap.

${C}EXAMPLES${N}
  $PROG -t 10.10.10.5
  $PROG -t 10.10.10.5,10.10.10.6 -t 192.168.1.0/24
  $PROG -f targets.txt --tcp-only
  $PROG -t 10.10.10.5 -T 8000 --tcp-only
  $PROG -t scanme.nmap.org -p 22,80,443,8080
  $PROG -t 10.10.10.5 --udp-all -T 2000 -o ./loot
  $PROG -t 10.10.10.5 -- --script vuln
EOF
}

# -------------------------------------------------------------- arg parsing ---
add_targets() {  # split a comma-separated spec into TARGETS
  local IFS=',' t
  for t in $1; do
    t="${t//[[:space:]]/}"
    [[ -n "$t" ]] && TARGETS+=( "$t" )
  done
}

[[ $# -eq 0 ]] && { usage; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)   add_targets "${2:?--target needs a value}"; shift 2 ;;
    -f|--file)     TARGETS_FILE="${2:?--file needs a value}"; shift 2 ;;
    -T|--threads)  THREADS="${2:?}"; shift 2 ;;
    -p|--ports)    PORTS="${2:?}"; shift 2 ;;
    -o|--outdir)   OUTDIR="${2:?}"; shift 2 ;;
    --tcp-only)    DO_UDP=0; shift ;;
    --udp-only)    DO_TCP=0; shift ;;
    --udp-all)     UDP_ALL=1; shift ;;
    --udp-top)     UDP_TOP="${2:?}"; shift 2 ;;
    --timeout)     TIMEOUT="${2:?}"; shift 2 ;;
    --min-rate)    MIN_RATE="${2:?}"; shift 2 ;;
    --timing)      NMAP_TIMING="${2:?}"; shift 2 ;;
    --scripts)     SCRIPTS="${2:?}"; shift 2 ;;
    --ping)        NO_PING=0; shift ;;
    --host-timeout) HOST_TIMEOUT="${2:?}"; shift 2 ;;
    -y|--yes)      ASSUME_YES=1; shift ;;
    -q|--quiet)    QUIET=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    -V|--version)  echo "$PROG $VERSION"; exit 0 ;;
    --)            shift; EXTRA_NMAP+=("$@"); break ;;
    -*)            die "Unknown option: $1  (see --help)" ;;
    *)             add_targets "$1"; shift ;;
  esac
done

if [[ -n "$TARGETS_FILE" ]]; then
  [[ -r "$TARGETS_FILE" ]] || die "Cannot read targets file: $TARGETS_FILE"
  while IFS= read -r line; do
    line="${line%%#*}"                       # strip comments
    add_targets "$line"
  done < "$TARGETS_FILE"
fi
(( ${#TARGETS[@]} )) || die "No targets. Use -t <ip|host|cidr>[,...] or -f <file>."
# de-duplicate, preserving order
mapfile -t TARGETS < <(printf '%s\n' "${TARGETS[@]}" | awk '!seen[$0]++')
TARGETS_CSV="$(IFS=,; echo "${TARGETS[*]}")"
[[ "$THREADS" =~ ^[0-9]+$ && "$THREADS" -gt 0 ]] || die "--threads must be a positive integer."
(( DO_TCP || DO_UDP )) || die "--tcp-only and --udp-only are mutually exclusive."
if [[ -n "$PORTS" && ! "$PORTS" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]]; then
  die "Bad --ports spec: '$PORTS' (use e.g. 22,80,443 or 1-1024 or 22,8000-8100)"
fi

command -v nmap >/dev/null || die "nmap is not installed. (apt install nmap)"
HAVE_RUSTSCAN=0; command -v rustscan >/dev/null && HAVE_RUSTSCAN=1

# ------------------------------------------------------------ privilege ------
# SYN scan (-sS), UDP scan (-sU) and OS detection need raw sockets.
SUDO=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null; then
    SUDO="sudo"
  else
    warn "Not root and no sudo: falling back to TCP connect() scan; UDP disabled."
    DO_UDP=0
  fi
fi

# ------------------------------------------------------------ output setup ---
TS="$(date +%Y%m%d-%H%M%S)"
SAFE_TARGET="$(printf '%s' "${TARGETS[0]}" | tr -c 'A-Za-z0-9._-' '_')"
(( ${#TARGETS[@]} > 1 )) && SAFE_TARGET+="-and-$(( ${#TARGETS[@]} - 1 ))-more"
[[ -z "$OUTDIR" ]] && OUTDIR="./scan-${SAFE_TARGET}-${TS}"
mkdir -p "$OUTDIR" || die "Cannot create outdir: $OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
SUMMARY="$OUTDIR/summary.txt"

# raise fd limit for rustscan's batch size when we're allowed to
ULIMIT_TARGET=$(( THREADS + 1000 ))
HARD="$(ulimit -Hn 2>/dev/null || echo 1024)"
[[ "$HARD" == "unlimited" ]] && HARD=$ULIMIT_TARGET
(( ULIMIT_TARGET > HARD )) && ULIMIT_TARGET=$HARD
ulimit -n "$ULIMIT_TARGET" 2>/dev/null || true
CUR_ULIMIT="$(ulimit -n)"
if (( DO_TCP && HAVE_RUSTSCAN && THREADS > CUR_ULIMIT - 100 )); then
  warn "Batch size $THREADS exceeds fd limit ($CUR_ULIMIT); rustscan will self-adjust."
fi

# -------------------------------------------------------------- pre-flight ---
TCP_PORT_SPEC="${PORTS:-1-65535}"
if (( UDP_ALL )); then UDP_PORT_SPEC="${PORTS:-1-65535}"; else UDP_PORT_SPEC="$PORTS"; fi

(( QUIET )) || cat >&2 <<EOF
${C}=====================================================${N}
 targets     : $( (( ${#TARGETS[@]} <= 4 )) && echo "$TARGETS_CSV" || echo "${#TARGETS[@]} targets (${TARGETS[0]}, ...)" )
 protocols   : $( ((DO_TCP)) && printf 'TCP ' ; ((DO_UDP)) && printf 'UDP' ; ((DO_TCP||DO_UDP))||printf none )
 tcp ports   : $( ((DO_TCP)) && echo "$TCP_PORT_SPEC" || echo skipped )
 udp ports   : $( if ((!DO_UDP)); then echo skipped; elif [[ -n "$UDP_PORT_SPEC" ]]; then echo "$UDP_PORT_SPEC"; else echo "top-$UDP_TOP"; fi )
 threads     : ${THREADS}
 discovery   : $( ((HAVE_RUSTSCAN)) && echo rustscan || echo "nmap (rustscan not found)" )
 outdir      : ${OUTDIR}
${C}=====================================================${N}
EOF

if (( ! ASSUME_YES )); then
  warn "Only scan hosts you are authorized to test."
  read -r -p "Proceed? [y/N] " a < /dev/tty || a="n"
  [[ "$a" =~ ^[Yy]$ ]] || die "Aborted."
fi

cleanup() { local c=$?; jobs -p | xargs -r kill 2>/dev/null || true; exit $c; }
trap cleanup INT TERM

# Keep sudo warm so the background UDP job never blocks on a password prompt.
# If we can't get it (no tty / not a sudoer), degrade gracefully instead of dying.
if [[ -n "$SUDO" ]] && ! $SUDO -n true 2>/dev/null; then
  if [[ -t 0 ]] && $SUDO -v; then :; else
    warn "No sudo privileges: using TCP connect() scan, skipping UDP."
    SUDO=""; DO_UDP=0
  fi
fi
(( DO_TCP || DO_UDP )) || die "Nothing left to scan: UDP requires root/sudo."

START=$(date +%s)

# nmap's --min-parallelism is a probe-window hint, not a thread count; very large
# values hurt reliability, so cap the nmap side while rustscan gets the full batch.
NMAP_PAR=$(( THREADS > 256 ? 256 : THREADS ))

# common nmap flags
NMAP_COMMON=( "$NMAP_TIMING" --min-rate "$MIN_RATE" --min-parallelism "$NMAP_PAR"
              --max-retries 2 --defeat-rst-ratelimit --stats-every 15s )
(( NO_PING )) && NMAP_COMMON+=( -Pn )
NMAP_SCRIPT=()
[[ "$SCRIPTS" != "none" ]] && NMAP_SCRIPT=( --script "$SCRIPTS" --script-timeout 90s )
NMAP_HTO=()
[[ "$HOST_TIMEOUT" != "0" ]] && NMAP_HTO=( --host-timeout "$HOST_TIMEOUT" )

# Relay nmap's progress lines ("About X% done; ETC: ...") to the terminal
# while <pid> runs, so long phases don't look frozen.
watch_progress() {  # <pid> <logfile> <label>
  local pid=$1 logf=$2 label=$3 last="" line
  while kill -0 "$pid" 2>/dev/null; do
    sleep 15
    kill -0 "$pid" 2>/dev/null || break
    line="$(grep -oE 'About [0-9.]+% done; ETC: [0-9:]+ \([^)]*\)' "$logf" 2>/dev/null | tail -1 || true)"
    [[ -z "$line" ]] && line="$(grep -c . "$logf" 2>/dev/null || echo 0) log lines, still running"
    [[ "$line" != "$last" ]] && { log "$label: $line"; last="$line"; }
  done
  wait "$pid" 2>/dev/null || true
}

# Pull the core results out of an nmap .nmap file: the PORT table (incl. NSE
# script lines), plus Service Info / OS lines. Everything else is noise.
extract_core() {  # <file.nmap>
  [[ -f "$1" ]] || return 0
  awk '
    /^Nmap scan report for /     { print "" ; print "-- " substr($0, 22) ; next }
    /^PORT[[:space:]]/           { in_table=1 }
    in_table && /^$/             { in_table=0 }
    in_table                     { print; next }
    /^(Service Info|OS |Running|Host script results)/ { print }
  ' "$1"
}

# ============================================================== TCP phase ====
run_tcp() {
  local open="" list="$OUTDIR/tcp-open-ports.txt"
  local use_rustscan=$HAVE_RUSTSCAN

  # rustscan takes comma lists via -p and a single range via -r, but not a
  # mixed spec like 22,8000-8100 -> hand those to the nmap sweep instead.
  local rs_portflag=()
  if [[ -z "$PORTS" ]]; then
    rs_portflag=( -r 1-65535 )
  elif [[ "$PORTS" =~ ^[0-9]+-[0-9]+$ ]]; then
    rs_portflag=( -r "$PORTS" )
  elif [[ "$PORTS" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    rs_portflag=( -p "$PORTS" )
  else
    (( use_rustscan )) && log "Mixed port spec: using nmap for discovery (rustscan can't mix lists and ranges)."
    use_rustscan=0
  fi

  if (( use_rustscan )); then
    log "TCP discovery: rustscan (batch=$THREADS timeout=${TIMEOUT}ms ports=$TCP_PORT_SPEC)"
    rustscan -a "$TARGETS_CSV" -b "$THREADS" -t "$TIMEOUT" --ulimit "$CUR_ULIMIT" \
        --scan-order random --greppable "${rs_portflag[@]}" \
        > "$OUTDIR/rustscan.log" 2> "$OUTDIR/rustscan.err" || true
    # greppable lines look like: 10.0.0.5 -> [22,80,443]
    { grep -oE '\[[0-9][0-9,]*\]' "$OUTDIR/rustscan.log" | tr -d '[]' | tr ',' '\n'
      grep -oE '^Open [^ :]+:[0-9]+' "$OUTDIR/rustscan.log" | awk -F: '{print $NF}'
    } 2>/dev/null | grep -E '^[0-9]+$' | sort -un > "$list" || true
  else
    log "TCP discovery: nmap sweep (rate=$MIN_RATE ports=$TCP_PORT_SPEC)"
    local st="-sS"; [[ -z "$SUDO" && $EUID -ne 0 ]] && st="-sT"   # connect() scan w/o root
    $SUDO nmap $st -p "$TCP_PORT_SPEC" --open -n "${NMAP_COMMON[@]}" \
      -oG "$OUTDIR/tcp-discovery.gnmap" "${TARGETS[@]}" > "$OUTDIR/tcp-discovery.txt" 2>&1 &
    watch_progress $! "$OUTDIR/tcp-discovery.txt" "TCP discovery"
    grep -hoE '[0-9]+/open/tcp' "$OUTDIR/tcp-discovery.gnmap" 2>/dev/null \
      | cut -d/ -f1 | sort -un > "$list" || true
  fi

  open="$(paste -sd, "$list" 2>/dev/null || true)"
  if [[ -z "$open" ]]; then
    warn "TCP: no open ports found."
    return 0
  fi
  ok "TCP open: $open"

  log "TCP enumeration: nmap -sV on $(wc -l < "$list") port(s)"
  $SUDO nmap -sV --version-intensity 6 -p "$open" --open "${NMAP_COMMON[@]}" "${NMAP_HTO[@]}" "${NMAP_SCRIPT[@]}" \
    "${EXTRA_NMAP[@]}" -oA "$OUTDIR/tcp" "${TARGETS[@]}" > "$OUTDIR/tcp-scan.txt" 2>&1 &
    watch_progress $! "$OUTDIR/tcp-scan.txt" "TCP enumeration"
  ok "TCP enumeration done"
}

# ============================================================== UDP phase ====
run_udp() {
  local args=( -sU --open -n "$NMAP_TIMING" --min-rate "$MIN_RATE"
               --min-parallelism "$NMAP_PAR" --max-retries 1 --stats-every 15s )
  (( NO_PING )) && args+=( -Pn )
  if [[ -n "$UDP_PORT_SPEC" ]]; then
    args+=( -p "$UDP_PORT_SPEC" )
    (( UDP_ALL )) && warn "UDP full range requested - this can take hours."
  else
    args+=( --top-ports "$UDP_TOP" )
  fi
  args+=( -sV --version-intensity 0 )
  (( ${#NMAP_HTO[@]} )) && args+=( "${NMAP_HTO[@]}" )

  log "UDP scan: $( [[ -n "$UDP_PORT_SPEC" ]] && echo "ports $UDP_PORT_SPEC" || echo "top-$UDP_TOP" )"
  $SUDO nmap "${args[@]}" "${EXTRA_NMAP[@]}" -oA "$OUTDIR/udp" "${TARGETS[@]}" \
    > "$OUTDIR/udp-scan.txt" 2>&1 || true
  ok "UDP scan done"
}

# ================================================================== drive =====
UDP_PID=""
if (( DO_UDP )); then run_udp & UDP_PID=$!; fi   # slow: run it alongside TCP
if (( DO_TCP )); then run_tcp; fi
[[ -n "$UDP_PID" ]] && { log "waiting on UDP scan (progress every ~15s; UDP is inherently slow)..."
  watch_progress "$UDP_PID" "$OUTDIR/udp-scan.txt" "UDP"; }

ELAPSED=$(( $(date +%s) - START ))

# ------------------------------------------------- assemble clean results ----
{
  echo "targets: $TARGETS_CSV"
  echo "date   : $(date -Is)   elapsed: ${ELAPSED}s"
  if (( DO_TCP )); then
    echo; echo "== TCP =="
    tcp_core="$(extract_core "$OUTDIR/tcp.nmap")"
    [[ -n "$tcp_core" ]] && echo "$tcp_core" || echo "no open ports"
  fi
  if (( DO_UDP )); then
    echo; echo "== UDP =="
    udp_core="$(extract_core "$OUTDIR/udp.nmap")"
    [[ -n "$udp_core" ]] && echo "$udp_core" || echo "no open ports"
  fi
} > "$SUMMARY"

ok "Finished in ${ELAPSED}s. Full output: $OUTDIR"
echo
cat "$SUMMARY"

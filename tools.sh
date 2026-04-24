#!/usr/bin/env bash
# =============================================================================
#  OSCP+ / PNPT  Tools Setup Script  v6.0
#  Target : ~/Desktop/Tools/
#  Usage  : chmod +x tools.sh && ./tools.sh
#           ./tools.sh --module windows linux   # re-run specific modules
#           ./tools.sh --module config          # re-run post-install config only
#           ./tools.sh --list                   # list all available modules
#
#  EXAM NOTES:
#   * OSCP+  : sqlmap PROHIBITED  |  Metasploit ONE target  |  no AI/LLMs
#   * PNPT   : all tools permitted
# =============================================================================
#
# CHANGES v6.0:
#  * ASCII art banner "ANON - TOOLS SETUP" in block-pixel font (7 rows)
#  * Byline row: "Developed by Anon  -  v6.0 for OSCP/PNPT"
#  * Header zone expanded to 9 rows; all layout row numbers updated
#  * All v5.1 bug fixes retained (DIRS global, (( n++ )) || true, TUI_ACTIVE guard)
# =============================================================================
set -uo pipefail
# NOTE: arithmetic (( expr )) is wrapped in  || true  throughout to prevent
#       exit-on-false under pipefail when the result is 0.

# ── GitHub token (optional but strongly recommended) ─────────────────────────
# Set before running:  export GITHUB_TOKEN="ghp_yourtoken"
# Without it: 60 API requests/hour (unauthenticated)
# With it:  5000 API requests/hour — eliminates rate-limit failures
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
# Build reusable curl/wget auth args — empty if no token set
_gh_curl_auth() {
  if [[ -n "$GITHUB_TOKEN" ]]; then
    printf '%s' "-H "Authorization: token ${GITHUB_TOKEN}""
  fi
}

# ── ASCII art banner: exact Figlet box-drawing glyphs "ANON - TOOLS SETUP" ───
BANNER_ART=(
  " █████╗ ███╗   ██╗ ██████╗ ███╗   ██╗              ████████╗ ██████╗  ██████╗ ██╗     ███████╗    ███████╗███████╗████████╗██╗   ██╗██████╗  "
  "██╔══██╗████╗  ██║██╔═══██╗████╗  ██║              ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗ "
  "███████║██╔██╗ ██║██║   ██║██╔██╗ ██║    █████╗       ██║   ██║   ██║██║   ██║██║     ███████╗    ███████╗█████╗     ██║   ██║   ██║██████╔╝ "
  "██╔══██║██║╚██╗██║██║   ██║██║╚██╗██║    ╚════╝       ██║   ██║   ██║██║   ██║██║     ╚════██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝  "
  "██║  ██║██║ ╚████║╚██████╔╝██║ ╚████║                 ██║   ╚██████╔╝╚██████╔╝███████╗███████║    ███████║███████╗   ██║   ╚██████╔╝██║      "
  "╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═══╝                 ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝      "
)
# Byline printed on row 7 (art is 6 rows) + separator on row 8
BANNER_BYLINE="  Developed by Anon  -  v6.0 for OSCP/PNPT"

# ── Raw ANSI escape sequences ─────────────────────────────────────────────────
ESC=$'\033'
R="${ESC}[0;31m"   G="${ESC}[0;32m"   Y="${ESC}[1;33m"
C="${ESC}[0;36m"   W="${ESC}[1;37m"   DIM="${ESC}[2m"   BOLD="${ESC}[1m"
RST="${ESC}[0m"

c256() { printf "${ESC}[38;5;%dm" "$1"; }
b256() { printf "${ESC}[48;5;%dm" "$1"; }

BLUE_FILL=$(c256 39)
GREY_EMPTY=$(c256 238)
FG_OK=$(c256 245)
FG_FAIL=$(c256 196)
FG_SKIP=$(c256 240)
FG_HEAD=$(c256 39)
FG_MOD=$(c256 214)
FG_TOOL=$(c256 255)
FG_QUOTE=$(c256 135)
FG_LEET=$(c256 196)
FG_DIVIDER=$(c256 59)

# ── Paths ─────────────────────────────────────────────────────────────────────
TOOLS_BASE="$HOME/Desktop/Tools"
LOG_FILE="$TOOLS_BASE/install.log"

# ── Counters (global, never local) ───────────────────────────────────────────
TOTAL=0
CURRENT=0
PASS=0
FAIL=0
SKIP=0
START_TIME=0
DRY_RUN=0        # set to 1 via --dry-run; prints actions without executing
UPDATE_MODE=0    # set to 1 via --update; re-downloads files and pulls repos
OSCP_MODE=0      # set to 1 via --mode oscp; skips OSCP-prohibited tools
RATE_LIMIT_MODE=0       # set to 1 via --rate-limit; throttles gh_latest API calls
RATE_LIMIT_THRESHOLD=50 # max gh_latest calls per hour before we pause (default 50, max safe=58)
GH_API_CALLS=0          # running count of API calls made this window
GH_WINDOW_START=0       # epoch second when current rate-limit window started
declare -a FAILED_TOOLS=()
QUOTE_CHANGED=0
CURRENT_MODULE="Initialising..."
CURRENT_TOOL=""
TUI_ACTIVE=0    # guards EXIT trap — only teardown when TUI is actually running

# ── DIRS global (BUG FIX: was local to main(), modules couldn't see it) ───────
declare -A DIRS=(
  [ad]="$TOOLS_BASE/AD"
  [adcs]="$TOOLS_BASE/AD/ADCS"
  [win]="$TOOLS_BASE/Windows"
  [linux]="$TOOLS_BASE/Linux"
  [web]="$TOOLS_BASE/Web"
  [pivoting]="$TOOLS_BASE/Pivoting"
  [exploit]="$TOOLS_BASE/Exploit"
  [wordlists]="$TOOLS_BASE/Wordlists"
  [rules]="$TOOLS_BASE/Wordlists/hashcat-rules"
  [shells]="$TOOLS_BASE/Shells"
  [utils]="$TOOLS_BASE/Utils"
  [recon]="$TOOLS_BASE/Recon"
  [bof]="$TOOLS_BASE/BOF-ExploitDev"
  [osint]="$TOOLS_BASE/OSINT"
  [reporting]="$TOOLS_BASE/Reporting"
)

# ── Terminal dimensions ───────────────────────────────────────────────────────
ROWS=24
COLS=80
refresh_dims() {
  ROWS=$(tput lines 2>/dev/null || echo 24)
  COLS=$(tput cols  2>/dev/null || echo 80)
}
refresh_dims

# ── Layout rows (recomputed in tui_init after fresh dim read) ─────────────────
# Header zone:  7 art rows + 1 byline + 1 separator = 9 rows
HEADER_ROWS=8
PANEL_ROWS=7   # panel_sep + 3 panel rows + quote_sep + quote + bot_sep
LOG_H=4
LOG_TOP=10
LOG_BOT=13
PANEL_SEP=14
PANEL_R1=15
PANEL_R2=16
PANEL_R3=17
QUOTE_SEP=18
QUOTE_ROW=19
BOT_SEP=20

# ── Cursor helpers ────────────────────────────────────────────────────────────
_at() { printf "${ESC}[%d;%dH" "$1" "$2"; }
_el() { printf "${ESC}[2K"; }

# ── Quotes ────────────────────────────────────────────────────────────────────
QUOTES=(
  "\"Supreme excellence consists in breaking the enemy's resistance without fighting.\" -- Sun Tzu"
  "\"If you know the enemy and know yourself, you need not fear the result of a hundred battles.\" -- Sun Tzu"
  "\"The greatest victory is that which requires no battle.\" -- Sun Tzu"
  "\"Appear weak when you are strong, and strong when you are weak.\" -- Sun Tzu"
  "\"In the midst of chaos, there is also opportunity.\" -- Sun Tzu"
  "\"All warfare is based on deception.\" -- Sun Tzu"
  "\"Let your plans be dark and impenetrable as night.\" -- Sun Tzu"
  "\"Move swift as the Wind, quiet as the Forest, conquer like the Fire, steady as the Mountain.\" -- Sun Tzu"
  "\"Victorious warriors win first and then go to war. Defeated warriors go to war first.\" -- Sun Tzu"
  "\"The wise warrior avoids the battle.\" -- Sun Tzu"
  "\"The quieter you become, the more you are able to hear.\" -- Kali Linux motto"
  "\"Passwords are like underwear: change often, don't share, don't leave them on your desk.\" -- Infosec proverb"
  "\"There is no patch for human stupidity.\" -- Kevin Mitnick"
  "\"The only truly secure system is powered off and cast in a block of concrete.\" -- Gene Spafford"
  "\"Hacking is not a crime. It is a skill. What you do with it decides your destiny.\" -- Anonymous"
  "\"Security is a process, not a product.\" -- Bruce Schneier"
  "\"1f y0u c4n r34d thi5, y0u r3 4lr34dy h4lfw4y t0 b31ng 4 h4ck3r.\" -- l33tspeak proverb"
  "\"The art of exploitation is nothing more than the art of creative problem-solving.\" -- Jon Erickson"
  "\"R00t is not just a user. It is a philosophy.\" -- /dev/null"
  "\"Every system is insecure. Every human is an attack vector.\" -- Red team axiom"
  "\"Never trust user input. Never.\" -- Every developer who got pwned"
  "\"3num3r4t3, 3sc4l4t3, 3xf1ltr8, r3p34t.\" -- OSCP candidate #99999"
  "\"Try harder.\" -- Offensive Security"
  "\"The n00b fires exploits blindly. The 31337 reads the source code first.\" -- Old-school wisdom"
  "\"Your shell is only as good as your TTY upgrade.\" -- CTF proverb"
  "\"An unpatched server is an invitation.\" -- Threat intel axiom"
  "\"P3rs1st3nc3 is not just a Metasploit module. It is a mindset.\" -- Red team philosophy"
  "\"Hacking teaches humility. Every target you can't break teaches you something new.\" -- Bug bounty truth"
  "\"The best firewall is the one between the keyboard and the chair.\" -- Security trainer classic"
  "\"0wn the b0x, write the rep0rt, sl33p, r3p34t.\" -- OSCP grind"
)
# QUOTE_IDX, QUOTE_LAST_CHANGE, QUOTE_CHANGED set dynamically in pick_quote init block
LEET_LABELS=("[ 1337 ]" "[ h4x0r ]" "[ 0day ]" "[ r00t ]" "[ pwn3d ]" "[ 3xpl01t ]")

# Seed random from PID + time so each run gets a different start
QUOTE_IDX=$(( (RANDOM + $$) % 30 )) || true
QUOTE_LAST_CHANGE=0
QUOTE_PREV_IDX=-1

pick_quote() {
  local now
  now=$(date +%s)
  if (( now - QUOTE_LAST_CHANGE >= 5 )); then
    # Pick a different random quote each time
    local new_idx=$QUOTE_IDX
    while (( new_idx == QUOTE_IDX )); do
      new_idx=$(( RANDOM % ${#QUOTES[@]} )) || true
    done
    QUOTE_PREV_IDX=$QUOTE_IDX
    QUOTE_IDX=$new_idx
    QUOTE_LAST_CHANGE=$now
    QUOTE_CHANGED=1
  else
    QUOTE_CHANGED=0
  fi
}

# Typewriter-fade: wipe old quote left-to-right then type new one in
animate_quote() {
  local leet="${LEET_LABELS[$(( QUOTE_IDX % ${#LEET_LABELS[@]} ))]}"
  local q="${QUOTES[$QUOTE_IDX]}"
  local max_q=$(( COLS - ${#leet} - 5 ))
  if (( max_q < 10 )); then max_q=10; fi
  if (( ${#q} > max_q )); then
    q="${q:0:$(( max_q - 3 ))}..."
  fi

  # Phase 1: erase old quote by overwriting with spaces char-by-char (fast)
  local old_q="${QUOTES[$QUOTE_PREV_IDX]}"
  local max_old=$(( COLS - ${#leet} - 5 ))
  if (( max_old < 10 )); then max_old=10; fi
  if (( ${#old_q} > max_old )); then
    old_q="${old_q:0:$(( max_old - 3 ))}..."
  fi
  local old_len=${#old_q}
  local erase_start=$(( ${#leet} + 4 ))   # col where quote text begins
  local col
  for (( col=old_len; col>=1; col-- )); do
    _at "$QUOTE_ROW" $(( erase_start + col ))
    printf " "
    sleep 0.01
  done

  # Phase 2: type new quote char-by-char
  _at "$QUOTE_ROW" 1; _el
  printf "  ${FG_LEET}${BOLD}%s${RST}  ${FG_QUOTE}" "$leet"
  local ci
  for (( ci=0; ci<${#q}; ci++ )); do
    printf "%s" "${q:$ci:1}"
    sleep 0.02
  done
  printf "${RST}"
}

# ── Draw separator (double-line ═ like nala, full terminal width) ─────────────
draw_sep() {
  local row=$1
  _at "$row" 1
  printf "${FG_DIVIDER}"
  # printf with awk for speed — no per-char loop
  printf "%s" "$(printf '═%.0s' $(seq 1 "$COLS"))"
  printf "${RST}"
}

# ── Draw fixed ASCII-art header (rows 1-8, never scrolled) ───────────────────
# Art is 6 rows of box-drawing glyphs; row 7 = byline; row 8 = separator
draw_header() {
  local FG_ART; FG_ART=$(c256 196)   # red           — glyph fill
  local FG_BYL; FG_BYL=$(c256 214)   # orange        — byline text
  local FG_TS;  FG_TS=$(c256 245)    # silver        — timestamp

  # ── Rows 1-6: box-drawing glyph art ──────────────────────────────────────
  local row_num=1
  local art_line
  for art_line in "${BANNER_ART[@]}"; do
    _at "$row_num" 1; _el
    # Two-tone: glyph chars in red (196), spaces in dark grey (235)
    local _char _colored="" _ci
    for (( _ci=0; _ci<${#art_line}; _ci++ )); do
      _char="${art_line:$_ci:1}"
      if [[ "$_char" == " " ]]; then
        _colored+="$(c256 235) "
      else
        _colored+="${FG_ART}${BOLD}${_char}"
      fi
    done
    printf "%b${RST}" "$_colored"
    (( row_num++ )) || true
  done

  # ── Row 7: byline (left) + clock (right) ─────────────────────────────────
  _at 7 1; _el
  local ts; ts=$(date '+%H:%M:%S')
  local ts_str="  ${ts}  "
  local pad=$(( COLS - ${#BANNER_BYLINE} - ${#ts_str} ))
  if (( pad < 0 )); then pad=0; fi
  printf "${FG_BYL}${BOLD}%s%*s${FG_TS}%s${RST}" \
    "$BANNER_BYLINE" "$pad" "" "$ts_str"

  # ── Row 8: double-line separator ─────────────────────────────────────────
  draw_sep 8
}

# ── Draw bottom panel ─────────────────────────────────────────────────────────
draw_panel() {
  local bar_w=$(( COLS - 4 ))
  if (( bar_w < 8 )); then bar_w=8; fi
  local pct=0
  local filled=0
  if (( TOTAL > 0 )); then
    pct=$(( CURRENT * 100 / TOTAL )) || true
    filled=$(( CURRENT * bar_w / TOTAL )) || true
  fi
  local empty=$(( bar_w - filled )) || true

  # Smooth block bar: filled=█ (U+2588) empty=░ (U+2591)
  local bar="${BLUE_FILL}"
  local i
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  bar+="${GREY_EMPTY}"
  for (( i=0; i<empty; i++ )); do bar+="░"; done
  bar+="${RST}"

  draw_sep "$PANEL_SEP"

  # Row 1: module | current tool
  _at "$PANEL_R1" 1; _el
  local mlabel; mlabel=$(printf "%-28s" "${CURRENT_MODULE:0:28}")
  local tlabel; tlabel=$(printf "%-40s" "${CURRENT_TOOL:0:40}")
  printf "  ${FG_MOD}${BOLD}%s${RST}  ${DIM}|>${RST}  ${FG_TOOL}%s${RST}" \
    "$mlabel" "$tlabel"

  # Row 2: progress bar
  _at "$PANEL_R2" 1; _el
  printf "  %b  " "$bar"

  # Row 3: counters left, steps+pct right
  _at "$PANEL_R3" 1; _el
  printf "  ${FG_OK}${BOLD}+  %-4d${RST}  ${FG_FAIL}${BOLD}!  %-4d${RST}  ${FG_SKIP}-  %-4d${RST}" \
    "$PASS" "$FAIL" "$SKIP"
  local steps_str; steps_str=$(printf "%d/%d  %d%%" "$CURRENT" "$TOTAL" "$pct")
  local right_col=$(( COLS - ${#steps_str} - 2 ))
  if (( right_col < 1 )); then right_col=1; fi
  _at "$PANEL_R3" "$right_col"
  printf "${BOLD}${FG_HEAD}%s${RST}  " "$steps_str"

  # Quote separator + row
  draw_sep "$QUOTE_SEP"
  pick_quote
  if (( QUOTE_CHANGED == 1 )); then
    # Animate transition (typewriter erase + retype)
    animate_quote
  else
    # Static redraw (no change this tick)
    local leet="${LEET_LABELS[$(( QUOTE_IDX % ${#LEET_LABELS[@]} ))]}"
    local q="${QUOTES[$QUOTE_IDX]}"
    local max_q=$(( COLS - ${#leet} - 5 ))
    if (( max_q < 10 )); then max_q=10; fi
    if (( ${#q} > max_q )); then
      q="${q:0:$(( max_q - 3 ))}..."
    fi
    _at "$QUOTE_ROW" 1; _el
    printf "  ${FG_LEET}${BOLD}%s${RST}  ${FG_QUOTE}%s${RST}" "$leet" "$q"
  fi

  draw_sep "$BOT_SEP"
}

# ── Scrolling log event ───────────────────────────────────────────────────────
# Protocol:
#   1. Lock scroll region to LOG_TOP..LOG_BOT
#   2. Move to bottom of log zone
#   3. Send \n — terminal scrolls WITHIN the locked region, header untouched
#   4. Move up one row (we are now on the blank line the scroll created)
#   5. Print the new entry on that blank line (no trailing \n)
#   6. Unlock scroll region
#   7. Redraw header (belt-and-suspenders, keeps clock fresh)
log_event() {
  local icon="$1" text="$2"
  printf "${ESC}[%d;%dr" "$LOG_TOP" "$LOG_BOT"  # lock scroll to log zone
  _at "$LOG_BOT" 1                               # move to last log row
  printf "\n"                                   # scroll up WITHIN locked region
  _at "$LOG_BOT" 1; _el                          # move back to (now blank) last row
  printf "%b %b${RST}" "$icon" "$text"           # write line — NO trailing \n
  printf "${ESC}[r"                              # unlock scroll region
  draw_header                                    # refresh header + clock
}

# ── Section header into log ───────────────────────────────────────────────────
hdr() {
  CURRENT_MODULE="$*"
  log_event "${FG_HEAD}${BOLD}>>${RST}" "${FG_HEAD}${BOLD}$*${RST}"
  draw_panel
}

# ── Show tool name in panel before blocking op ────────────────────────────────
announce() {
  CURRENT_TOOL="$1"
  draw_panel
}

# ── Record result in log + panel ─────────────────────────────────────────────
draw_progress() {
  local name="$1" status="$2"
  CURRENT=$(( CURRENT + 1 )) || true
  CURRENT_TOOL="$name"
  case "$status" in
    ok)
      PASS=$(( PASS + 1 )) || true
      log_event "${FG_OK}${BOLD}+${RST}" "${FG_OK}${name}${RST}"
      printf "[OK  ] (%d/%d) %s\n" "$CURRENT" "$TOTAL" "$name" >> "$LOG_FILE"
      ;;
    fail)
      FAIL=$(( FAIL + 1 )) || true
      FAILED_TOOLS+=("$name")
      log_event "${FG_FAIL}${BOLD}!${RST}" "${FG_FAIL}${name}${RST}"
      printf "[FAIL] (%d/%d) %s\n" "$CURRENT" "$TOTAL" "$name" >> "$LOG_FILE"
      ;;
    skip)
      SKIP=$(( SKIP + 1 )) || true
      log_event "${FG_SKIP}-${RST}" "${DIM}${name} (exists)${RST}"
      printf "[SKIP] (%d/%d) %s\n" "$CURRENT" "$TOTAL" "$name" >> "$LOG_FILE"
      ;;
  esac
  draw_panel
}

# ── TUI init ─────────────────────────────────────────────────────────────────
tui_init() {
  refresh_dims
  # Header occupies 8 rows (6 art rows + byline + separator)
  HEADER_ROWS=8
  LOG_H=$(( ROWS - HEADER_ROWS - PANEL_ROWS ))
  if (( LOG_H < 4 )); then LOG_H=4; fi
  LOG_TOP=$(( HEADER_ROWS + 1 ))
  LOG_BOT=$(( LOG_TOP + LOG_H - 1 ))
  PANEL_SEP=$(( LOG_BOT + 1 ))
  PANEL_R1=$(( LOG_BOT + 2 ))
  PANEL_R2=$(( LOG_BOT + 3 ))
  PANEL_R3=$(( LOG_BOT + 4 ))
  QUOTE_SEP=$(( LOG_BOT + 5 ))
  QUOTE_ROW=$(( LOG_BOT + 6 ))
  BOT_SEP=$(( LOG_BOT + 7 ))

  TUI_ACTIVE=1
  tput civis 2>/dev/null || true
  tput clear  2>/dev/null || true

  # Pre-fill log zone with blank lines
  local r
  for (( r=LOG_TOP; r<=LOG_BOT; r++ )); do
    _at "$r" 1; _el
  done

  draw_header
  draw_panel
}

# ── TUI teardown ──────────────────────────────────────────────────────────────
tui_teardown() {
  # Only run if TUI was actually started
  if (( TUI_ACTIVE == 1 )); then
    printf "${ESC}[r"
    tput cnorm 2>/dev/null || true
    _at "$ROWS" 1
    printf "\n"
    TUI_ACTIVE=0
  fi
}
trap tui_teardown EXIT

# =============================================================================
#  INSTALL HELPERS
# =============================================================================
# Minimum valid file sizes by extension (bytes)
# Anything smaller is assumed to be an error page or empty response
_dl_min_size() {
  case "${1##*.}" in
    exe|zip|gz|tar) echo 10240  ;;   # binaries/archives: at least 10 KB
    ps1|sh|py|pl)   echo 512    ;;   # scripts: at least 512 bytes
    rule)           echo 64     ;;   # hashcat rules can be small
    *)              echo 256    ;;   # everything else: at least 256 bytes
  esac
}

dl() {
  local dest="$1" url="$2"
  local name; name="$(basename "$dest")"
  announce "$name"
  if (( DRY_RUN )); then
    draw_progress "[DRY] ${name}" ok
    return
  fi
  if [[ -f "$dest" ]]; then
    if (( UPDATE_MODE )); then
      # Remove old file so wget downloads fresh
      rm -f "$dest"
      printf "[UPDATE] re-downloading %s\n" "$name" >> "$LOG_FILE"
    else
      draw_progress "$name" skip
      return
    fi
  fi
  if wget -q --timeout=30 --tries=3 -O "$dest" "$url" >> "$LOG_FILE" 2>&1; then
    # Validate: reject files that are suspiciously small (HTML error pages, 0-byte)
    local min_sz; min_sz=$(_dl_min_size "$name")
    local actual_sz=0
    [[ -f "$dest" ]] && actual_sz=$(stat -c%s "$dest" 2>/dev/null || echo 0)
    if (( actual_sz < min_sz )); then
      printf "[FAIL-SIZE] %s: got %d bytes (min %d) url=%s\n" \
        "$name" "$actual_sz" "$min_sz" "$url" >> "$LOG_FILE"
      rm -f "$dest"
      draw_progress "${name}:too-small" fail
    else
      draw_progress "$name" ok
    fi
  else
    rm -f "$dest"
    draw_progress "$name" fail
  fi
}

gc() {
  local dest="$1" url="$2"
  local name; name="$(basename "$dest")"
  announce "$name"
  if (( DRY_RUN )); then
    draw_progress "[DRY] ${name}" ok
    return
  fi
  if [[ -d "$dest" ]]; then
    if git -C "$dest" pull -q >> "$LOG_FILE" 2>&1; then
      if (( UPDATE_MODE )); then
        draw_progress "${name}:updated" ok
      else
        draw_progress "$name" ok
      fi
    else
      draw_progress "${name}:pull-failed" fail
    fi
    return
  fi
  if git clone -q --depth 1 "$url" "$dest" >> "$LOG_FILE" 2>&1; then
    draw_progress "$name" ok
  else
    draw_progress "$name" fail
  fi
}

# ── GitHub API rate-limit throttle ───────────────────────────────────────────
# Called before every curl API hit in gh_latest.
# In RATE_LIMIT_MODE: tracks calls per rolling hour; sleeps with countdown
# when RATE_LIMIT_THRESHOLD is reached, then resets the window.
# Without a token GitHub allows 60 req/hr; we default to 50 to leave headroom.
_gh_rate_check() {
  # Only throttle when explicitly requested AND no token is set
  if (( ! RATE_LIMIT_MODE )) || [[ -n "$GITHUB_TOKEN" ]]; then
    return
  fi

  local now; now=$(date +%s)

  # Initialise window on first call
  if (( GH_WINDOW_START == 0 )); then
    GH_WINDOW_START=$now
  fi

  GH_API_CALLS=$(( GH_API_CALLS + 1 )) || true

  local window_age=$(( now - GH_WINDOW_START ))
  local window_remaining=$(( 3600 - window_age ))

  printf "[RATE] call=%d/%d window_age=%ds\n"     "$GH_API_CALLS" "$RATE_LIMIT_THRESHOLD" "$window_age" >> "$LOG_FILE"

  # If window has expired naturally, reset counter and start fresh
  if (( window_age >= 3600 )); then
    GH_API_CALLS=1
    GH_WINDOW_START=$now
    return
  fi

  # If we haven't hit the threshold yet, proceed immediately
  if (( GH_API_CALLS <= RATE_LIMIT_THRESHOLD )); then
    return
  fi

  # ── Threshold reached: sleep until window resets ─────────────────────────
  # Add 5s buffer so GitHub's clock and ours don't disagree
  local sleep_secs=$(( window_remaining + 5 ))
  if (( sleep_secs < 1 )); then sleep_secs=1; fi

  printf "[RATE-PAUSE] hit %d calls; sleeping %ds until window resets\n"     "$GH_API_CALLS" "$sleep_secs" >> "$LOG_FILE"

  # Show countdown in the TUI panel row / quote row so user knows what's happening
  local saved_tool="$CURRENT_TOOL"
  local saved_mod="$CURRENT_MODULE"
  CURRENT_MODULE="GitHub rate-limit pause"

  local remaining=$sleep_secs
  while (( remaining > 0 )); do
    CURRENT_TOOL="$(printf "resuming in %dm %02ds  [%d/%d calls used]"       "$(( remaining / 60 ))" "$(( remaining % 60 ))"       "$GH_API_CALLS" "$RATE_LIMIT_THRESHOLD")"
    draw_panel
    sleep 1
    (( remaining-- )) || true
  done

  # Reset window after sleeping
  GH_API_CALLS=1
  GH_WINDOW_START=$(date +%s)

  # Restore panel state
  CURRENT_MODULE="$saved_mod"
  CURRENT_TOOL="$saved_tool"
}

gh_latest() {
  local dest="$1" repo="$2" pattern="$3"
  local label; label="$(basename "$repo")"
  announce "$label"
  if (( DRY_RUN )); then draw_progress "[DRY] ${label}" ok; return; fi

  # Build auth header for curl — empty string if no token
  local auth_hdr=()
  [[ -n "$GITHUB_TOKEN" ]] && auth_hdr=(-H "Authorization: token ${GITHUB_TOKEN}")

  # Throttle if rate-limit mode is active (no-op when token is set or mode is off)
  _gh_rate_check

  local api_response url
  api_response=$(curl -s "${auth_hdr[@]}"     "https://api.github.com/repos/${repo}/releases/latest" 2>>"$LOG_FILE") || true

  # Detect rate-limit or API error before trying to parse
  if echo "$api_response" | grep -q '"message"'; then
    local msg; msg=$(echo "$api_response" | grep -oP '"message":\s*"\K[^"]+' | head -1)
    printf "[FAIL-API] repo=%s msg=%s\n" "$repo" "$msg" >> "$LOG_FILE"
    draw_progress "${label}:api-error" fail
    return
  fi

  url=$(echo "$api_response"         | grep -oP '"browser_download_url":\s*"\K[^"]+'         | grep -iE -- "$(printf '%s' "$pattern")" | head -1) || true

  if [[ -z "$url" ]]; then
    draw_progress "${label}:no-asset" fail
    printf "[FAIL-ASSET] repo=%s pattern=%s\n" "$repo" "$pattern" >> "$LOG_FILE"
    return
  fi

  local fname; fname="$(basename "$url")"
  announce "$fname"

  # Pass token for wget downloads from github.com release assets too
  local wget_auth=()
  [[ -n "$GITHUB_TOKEN" ]] && wget_auth=(--header "Authorization: token ${GITHUB_TOKEN}")

  if wget -q --timeout=60 --tries=3 "${wget_auth[@]}" -O "$dest/$fname" "$url" >> "$LOG_FILE" 2>&1; then
    # Size validation — same thresholds as dl()
    local min_sz; min_sz=$(_dl_min_size "$fname")
    local actual_sz=0
    [[ -f "$dest/$fname" ]] && actual_sz=$(stat -c%s "$dest/$fname" 2>/dev/null || echo 0)
    if (( actual_sz < min_sz )); then
      printf "[FAIL-SIZE] %s: got %d bytes (min %d)\n" "$fname" "$actual_sz" "$min_sz" >> "$LOG_FILE"
      rm -f "$dest/$fname"
      draw_progress "${fname}:too-small" fail
    else
      draw_progress "$fname" ok
    fi
  else
    rm -f "$dest/$fname"
    draw_progress "$fname" fail
  fi
}

pipi() {
  local label="pip:$1"
  announce "$label"
  if (( DRY_RUN )); then draw_progress "[DRY] ${label}" ok; return; fi
  local pip_flags=()
  (( UPDATE_MODE )) && pip_flags+=(--upgrade)
  if pip3 install --quiet --break-system-packages "${pip_flags[@]}" "$@" >> "$LOG_FILE" 2>&1   || pip3 install --quiet "${pip_flags[@]}" "$@" >> "$LOG_FILE" 2>&1; then
    draw_progress "$label" ok
  else
    draw_progress "$label" fail
  fi
}

apti() {
  for pkg in "$@"; do
    local label="apt:$pkg"
    announce "$label"
    if (( DRY_RUN )); then draw_progress "[DRY] ${label}" ok; continue; fi
    if (( UPDATE_MODE )); then
      # In update mode: upgrade if already installed, install if missing
      if dpkg -l "$pkg" &>/dev/null; then
        if DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y -qq "$pkg"              >> "$LOG_FILE" 2>&1; then
          draw_progress "${label}:upgraded" ok
        else
          draw_progress "${label}:upgrade-skip" skip
        fi
        continue
      fi
    fi
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" \
         >> "$LOG_FILE" 2>&1; then
      draw_progress "$label" ok
    else
      draw_progress "$label" fail
    fi
  done
}

# apt_or <apt_pkg> <fallback_cmd...>
# Installs via apt if the package exists in repos, otherwise runs fallback
apt_or() {
  local pkg="$1"; shift
  local label="apt:$pkg"
  announce "$label"
  if apt-cache show "$pkg" >> "$LOG_FILE" 2>&1; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" >> "$LOG_FILE" 2>&1; then
      draw_progress "$label" ok
      return
    fi
  fi
  # apt failed or package not in repos — run fallback
  draw_progress "$label" fail
  "$@"
}

# apt_exists <pkg> — returns 0 if pkg is in Kali repos
apt_exists() { apt-cache show "$1" >> "$LOG_FILE" 2>&1; }

gem_install() {
  local label="gem:$1"
  announce "$label"
  if gem install "$1" --quiet >> "$LOG_FILE" 2>&1; then
    draw_progress "$label" ok
  else
    draw_progress "$label" fail
  fi
}

# =============================================================================
#  COUNT HELPERS
# =============================================================================
count_ad()     { TOTAL=$(( TOTAL + 42 )) || true; }
count_adcs()     { TOTAL=$(( TOTAL + 9 )) || true; }
count_coercion()     { TOTAL=$(( TOTAL + 7 )) || true; }
count_windows()     { TOTAL=$(( TOTAL + 48 )) || true; }
count_linux()     { TOTAL=$(( TOTAL + 15 )) || true; }
count_web()     { TOTAL=$(( TOTAL + 27 )) || true; }
count_pivoting()     { TOTAL=$(( TOTAL + 9 )) || true; }
count_recon()     { TOTAL=$(( TOTAL + 17 )) || true; }
count_passwords()     { TOTAL=$(( TOTAL + 10 )) || true; }
count_rules()     { TOTAL=$(( TOTAL + 4 )) || true; }
count_wordlists()     { TOTAL=$(( TOTAL + 7 )) || true; }
count_exploit()     { TOTAL=$(( TOTAL + 7 )) || true; }
count_shells()     { TOTAL=$(( TOTAL + 8 )) || true; }
count_bof()     { TOTAL=$(( TOTAL + 10 )) || true; }
count_osint()     { TOTAL=$(( TOTAL + 10 )) || true; }
count_reporting()     { TOTAL=$(( TOTAL + 3 )) || true; }
count_utils()     { TOTAL=$(( TOTAL + 8 )) || true; }

# =============================================================================
#  MODULE INSTALL FUNCTIONS
# =============================================================================
install_ad() {
  hdr "Active Directory -- Core"
  local AD="${DIRS[ad]}"
  gc  "$AD/BloodHound"                 "https://github.com/SpecterOps/BloodHound"
  apt_or bloodhound pipi bloodhound
  # SharpHound — releases ship as SharpHound-v*.zip containing .exe + .ps1
  gh_latest "$AD" "SpecterOps/SharpHound" "SharpHound-v.*\.zip$"
  for f in "$AD"/SharpHound-v*.zip; do
    if [[ -f "$f" ]]; then
      unzip -q -o -j "$f" -d "$AD" >> "$LOG_FILE" 2>&1 || true
    fi
  done
  gc  "$AD/PowerSploit"                "https://github.com/PowerShellMafia/PowerSploit"
  gc  "$AD/SharpView"                  "https://github.com/tevora-threat/SharpView"
  gc  "$AD/Powermad"                   "https://github.com/Kevin-Robertson/Powermad"
  gc  "$AD/Invoke-TheHash"             "https://github.com/Kevin-Robertson/Invoke-TheHash"
  gc  "$AD/Invoke-DNSUpdate"           "https://github.com/Kevin-Robertson/Invoke-DNSUpdate"
  # Rubeus.exe — downloaded to Windows/ by windows module; symlink here
  local _rb="$WIN/Rubeus.exe"
  if [[ -f "$_rb" ]]; then
    ln -sf "$_rb" "$AD/Rubeus.exe" >> "$LOG_FILE" 2>&1 || true
    draw_progress "Rubeus.exe" skip
  else
    dl  "$AD/Rubeus.exe" "https://github.com/r3motecontrol/Ghostpack-CompiledBinaries/raw/master/Rubeus.exe"
  fi
  gh_latest "$AD" "ropnop/kerbrute"                "kerbrute_linux_amd64$"
  gh_latest "$AD" "ropnop/kerbrute"                "kerbrute_windows_amd64\.exe$"
  chmod +x "$AD/kerbrute_linux_amd64" >> "$LOG_FILE" 2>&1 || true
  gc  "$AD/impacket"                   "https://github.com/fortra/impacket"
  apt_or impacket-scripts pipi impacket
  gc  "$AD/windapsearch"               "https://github.com/ropnop/windapsearch"
  gc  "$AD/ldapdomaindump"             "https://github.com/dirkjanm/ldapdomaindump"
  pipi ldapdomaindump
  pipi ldeep
  pipi adidnsdump
  pipi bloodyAD
  # GMSAPasswordReader has no releases (source-only) — use SharpCollection
  dl  "$AD/GMSAPasswordReader.exe" "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/GMSAPasswordReader.exe"
  # SharpGPOAbuse releases ship .zip, not .exe — use raw binary from main branch
  dl  "$AD/SharpGPOAbuse.exe" "https://github.com/byronkg/SharpGPOAbuse/raw/main/SharpGPOAbuse-master/SharpGPOAbuse.exe"
  gc  "$AD/LAPSToolkit"                "https://github.com/leoloobeek/LAPSToolkit"
  gh_latest "$AD" "SnaffCon/Snaffler"               "Snaffler\.exe$"
  gc  "$AD/SessionGopher"              "https://github.com/Arvanaghi/SessionGopher"
  gc  "$AD/SharpDPAPI"                 "https://github.com/GhostPack/SharpDPAPI"
  pipi donpapi
  gc  "$AD/SharpCollection"            "https://github.com/Flangvik/SharpCollection"
  gc  "$AD/Ghostpack-CompiledBinaries" "https://github.com/r3motecontrol/Ghostpack-CompiledBinaries"
  announce "netexec"
  if command -v netexec &>/dev/null || command -v crackmapexec &>/dev/null; then
    draw_progress "netexec/cme" skip
  elif apt_exists netexec; then
    apti netexec
  elif pipx install netexec >> "$LOG_FILE" 2>&1; then
    draw_progress "netexec" ok
  else
    pipi crackmapexec
  fi
  # Mimikatz — stable latest download URL (no API call)
  dl  "$AD/mimikatz_trunk.zip" "https://github.com/gentilkiwi/mimikatz/releases/latest/download/mimikatz_trunk.zip"
  if [[ -f "$AD/mimikatz_trunk.zip" ]]; then unzip -q -o "$AD/mimikatz_trunk.zip" -d "$AD/mimikatz" >> "$LOG_FILE" 2>&1 || true; fi
  # pypykatz installed by passwords module — skip duplicate here
  gc  "$AD/Responder"                  "https://github.com/lgandx/Responder"
  if command -v evil-winrm &>/dev/null; then
    draw_progress "evil-winrm" skip
  elif apt_exists evil-winrm; then
    apti evil-winrm
  else
    gem_install evil-winrm
  fi
  gc  "$AD/targetedKerberoast"         "https://github.com/ShutdownRepo/targetedKerberoast"
  gc  "$AD/krbrelayx"                  "https://github.com/dirkjanm/krbrelayx"
  gc  "$AD/DomainPasswordSpray"        "https://github.com/dafthack/DomainPasswordSpray"
  gc  "$AD/Spray"                      "https://github.com/Greenwolf/Spray"
  # o365spray + trevorspray installed by passwords module — skip duplicates here
}

install_adcs() {
  hdr "AD CS / Certificate Attacks"
  local ADCS="${DIRS[adcs]}"
  apt_or certipy-ad pipi certipy-ad
  gc  "$ADCS/PKINITtools"  "https://github.com/dirkjanm/PKINITtools"
  pipi dsinternals
  gc  "$ADCS/Whisker"      "https://github.com/eladshamir/Whisker"
  gc  "$ADCS/pywhisker"    "https://github.com/ShutdownRepo/pywhisker"
  pipi pywhisker
  gc  "$ADCS/PassTheCert"  "https://github.com/AlmondOffSec/PassTheCert"
  gc  "$ADCS/ADCSPwn"      "https://github.com/bats3c/ADCSPwn"
  draw_progress "Certify(in SharpCollection)" skip
}

install_coercion() {
  hdr "Auth Coercion + AD CVEs"
  local AD="${DIRS[ad]}"
  gc  "$AD/PetitPotam"         "https://github.com/topotam/PetitPotam"
  apt_or python3-coercer pipi coercer
  gc  "$AD/DFSCoerce"          "https://github.com/Wh04m1001/DFSCoerce"
  gc  "$AD/SpoolSample"        "https://github.com/leechristensen/SpoolSample"
  gc  "$AD/noPac"              "https://github.com/Ridter/noPac"
  gc  "$AD/CVE-2020-1472-test" "https://github.com/SecuraBV/CVE-2020-1472"
  gc  "$AD/CVE-2020-1472"      "https://github.com/dirkjanm/CVE-2020-1472"
}

install_windows() {
  hdr "Windows Binaries"
  local WIN="${DIRS[win]}"
  local GP_BASE="https://github.com/r3motecontrol/Ghostpack-CompiledBinaries/raw/master"
  local SHARP_BASE="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any"

  # WinPEAS — stable /releases/latest/download/ URLs (no API call needed)
  local PEASS_BASE="https://github.com/peass-ng/PEASS-ng/releases/latest/download"
  dl  "$WIN/winPEASx64.exe"      "${PEASS_BASE}/winPEASx64.exe"
  dl  "$WIN/winPEASx86.exe"      "${PEASS_BASE}/winPEASx86.exe"
  dl  "$WIN/winPEAS.bat"         "${PEASS_BASE}/winPEAS.bat"

  # PowerShell privesc scripts — direct raw URLs, always reliable
  dl  "$WIN/PowerUp.ps1"         "https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Privesc/PowerUp.ps1"
  # PrivescCheck — direct URL to confirmed release asset (repo restructured, raw URL broken)
  dl  "$WIN/PrivescCheck.ps1" "https://github.com/itm4n/PrivescCheck/releases/download/2026.01.30-1/PrivescCheck.ps1"
  gc  "$WIN/SharpUp"             "https://github.com/GhostPack/SharpUp"
  dl  "$WIN/jaws-enum.ps1"       "https://raw.githubusercontent.com/411Hall/JAWS/master/jaws-enum.ps1"

  # GhostPack tools — deliberately publish NO release binaries.
  # Use Ghostpack-CompiledBinaries (r3motecontrol) or SharpCollection (Flangvik)
  dl  "$WIN/Seatbelt.exe"        "${GP_BASE}/Seatbelt.exe"
  dl  "$WIN/Rubeus.exe"          "${GP_BASE}/Rubeus.exe"
  dl  "$WIN/SharpUp.exe"         "${GP_BASE}/SharpUp.exe"
  dl  "$WIN/SharpDPAPI.exe"      "${GP_BASE}/SharpDPAPI.exe"
  dl  "$WIN/Certify.exe"         "${SHARP_BASE}/Certify.exe"
  dl  "$WIN/SharpView.exe"       "${SHARP_BASE}/SharpView.exe"
  dl  "$WIN/Watson.exe"          "${SHARP_BASE}/Watson.exe"

  gc  "$WIN/wesng"               "https://github.com/bitsadmin/wesng"
  pipi wesng
  gc  "$WIN/windows-exploit-suggester" "https://github.com/AonCyberLabs/Windows-Exploit-Suggester"
  gc  "$WIN/BeRoot"              "https://github.com/AlessandroZ/BeRoot"

  # Sysinternals — live.sysinternals.com direct download
  dl  "$WIN/accesschk64.exe"     "https://live.sysinternals.com/accesschk64.exe"
  dl  "$WIN/accesschk.exe"       "https://live.sysinternals.com/accesschk.exe"
  dl  "$WIN/PsExec64.exe"        "https://live.sysinternals.com/PsExec64.exe"
  dl  "$WIN/PsExec.exe"          "https://live.sysinternals.com/PsExec.exe"
  dl  "$WIN/ProcMon64.exe"       "https://live.sysinternals.com/Procmon64.exe"

  # SeRestoreAbuse — no releases; binaries committed directly to RajChowdhury240 repo
  dl  "$WIN/SeRestoreAbuse-x64.exe" "https://raw.githubusercontent.com/RajChowdhury240/SeRestoreAbuse/main/SeRestoreAbuse-x64.exe"
  dl  "$WIN/SeRestoreAbuse-x86.exe" "https://raw.githubusercontent.com/RajChowdhury240/SeRestoreAbuse/main/SeRestoreAbuse-x86.exe"

  # SeManageVolumeExploit — release tag is "public" (not semver), direct URL
  dl  "$WIN/SeManageVolumeExploit.exe" "https://github.com/CsEnox/SeManageVolumeExploit/releases/download/public/SeManageVolumeExploit.exe"

  # FullPowers — direct confirmed URL
  dl  "$WIN/FullPowers.exe" "https://github.com/itm4n/FullPowers/releases/download/v0.1/FullPowers.exe"

  # PrintSpoofer — direct confirmed URLs, tag v1.0
  dl  "$WIN/PrintSpoofer64.exe" "https://github.com/itm4n/PrintSpoofer/releases/download/v1.0/PrintSpoofer64.exe"
  dl  "$WIN/PrintSpoofer32.exe" "https://github.com/itm4n/PrintSpoofer/releases/download/v1.0/PrintSpoofer32.exe"

  # ── Potato exploits ──────────────────────────────────────────────────────
  # GodPotato — direct URL, tag V1.20, asset name GodPotato-NET4.exe (confirmed)
  dl  "$WIN/GodPotato-NET4.exe" "https://github.com/BeichenDream/GodPotato/releases/download/V1.20/GodPotato-NET4.exe"

  # JuicyPotatoNG v1.1 — release asset is JuicyPotatoNG.zip, direct confirmed URL
  dl  "$WIN/JuicyPotatoNG.zip" "https://github.com/antonioCoco/JuicyPotatoNG/releases/download/v1.1/JuicyPotatoNG.zip"
  if [[ -f "$WIN/JuicyPotatoNG.zip" ]]; then unzip -q -o "$WIN/JuicyPotatoNG.zip" -d "$WIN" >> "$LOG_FILE" 2>&1 || true; fi

  # JuicyPotato (classic) — actual filenames are jp.exe (x64) and jp32.exe (x86)
  dl  "$WIN/JuicyPotato_x64.exe" "https://raw.githubusercontent.com/k4sth4/Juicy-Potato/main/x64/jp.exe"
  dl  "$WIN/JuicyPotato_x86.exe" "https://raw.githubusercontent.com/k4sth4/Juicy-Potato/main/x86/jp32.exe"

  # SweetPotato — NO releases (CCob/SweetPotato is source only)
  # Use SharpCollection precompiled binary
  dl  "$WIN/SweetPotato.exe"     "${SHARP_BASE}/SweetPotato.exe"

  # RoguePotato — NO releases (antonioCoco/RoguePotato is source only)
  # Use k4sth4 mirror which has the binary committed directly to repo
  dl  "$WIN/RoguePotato.exe"     "https://github.com/k4sth4/Rogue-Potato/raw/refs/heads/main/RoguePotato.exe"

  gc  "$WIN/EfsPotato"           "https://github.com/zcgonvh/EfsPotato"
  gc  "$WIN/SpoolFool"           "https://github.com/ly4k/SpoolFool"
  gc  "$WIN/Tokenvator"          "https://github.com/0xbadjuju/Tokenvator"

  # RunasCs v1.5 — release asset is RunasCs.zip containing RunasCs.exe + RunasCs_net2.exe
  dl  "$WIN/RunasCs.zip" "https://github.com/antonioCoco/RunasCs/releases/download/v1.5/RunasCs.zip"
  if [[ -f "$WIN/RunasCs.zip" ]]; then unzip -q -o "$WIN/RunasCs.zip" -d "$WIN" >> "$LOG_FILE" 2>&1 || true; fi
  dl  "$WIN/Invoke-RunasCs.ps1"  "https://raw.githubusercontent.com/antonioCoco/RunasCs/master/Invoke-RunasCs.ps1"
  dl  "$WIN/powercat.ps1"        "https://raw.githubusercontent.com/besimorhino/powercat/master/powercat.ps1"
  gc  "$WIN/nishang"             "https://github.com/samratashok/nishang"

  # LaZagne v2.4.7 — confirmed direct URL, asset name is "LaZagne.exe"
  dl  "$WIN/LaZagne.exe" "https://github.com/AlessandroZ/LaZagne/releases/download/v2.4.7/LaZagne.exe"

  dl  "$WIN/Invoke-Mimikatz.ps1" "https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Exfiltration/Invoke-Mimikatz.ps1"
  dl  "$WIN/nc64.exe"            "https://github.com/int0x33/nc.exe/raw/master/nc64.exe"
  dl  "$WIN/nc.exe"              "https://github.com/int0x33/nc.exe/raw/master/nc.exe"
  gc  "$WIN/LOLBAS"              "https://github.com/LOLBAS-Project/LOLBAS"
  gc  "$WIN/DefaultCreds"        "https://github.com/ihebski/DefaultCreds-cheat-sheet"
  # defaultcreds-cheat-sheet pip package installed by passwords module
}

install_linux() {
  hdr "Linux Tools"
  local LIN="${DIRS[linux]}"
  dl  "$LIN/linpeas.sh" "https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh"
  chmod +x "$LIN/linpeas.sh" >> "$LOG_FILE" 2>&1 || true
  dl  "$LIN/LinEnum.sh"             "https://raw.githubusercontent.com/rebootuser/LinEnum/master/LinEnum.sh"
  dl  "$LIN/lse.sh"                 "https://raw.githubusercontent.com/diego-treitos/linux-smart-enumeration/master/lse.sh"
  dl  "$LIN/linux-exploit-suggester.sh" \
      "https://raw.githubusercontent.com/The-Z-Labs/linux-exploit-suggester/master/linux-exploit-suggester.sh"
  dl  "$LIN/les2.pl"                "https://raw.githubusercontent.com/jondonas/linux-exploit-suggester-2/master/linux-exploit-suggester-2.pl"
  # pspy — in Kali repos; fallback to gh_latest
  if apt_exists pspy; then
    apti pspy
    if [[ -f /usr/bin/pspy64 ]]; then ln -sf /usr/bin/pspy64 "$LIN/pspy64" >> "$LOG_FILE" 2>&1 || true; fi
    if [[ -f /usr/bin/pspy32 ]]; then ln -sf /usr/bin/pspy32 "$LIN/pspy32" >> "$LOG_FILE" 2>&1 || true; fi
  else
    gh_latest "$LIN" "DominicBreuker/pspy"  "^pspy64$"
    gh_latest "$LIN" "DominicBreuker/pspy"  "^pspy32$"
    chmod +x "$LIN/pspy64" "$LIN/pspy32" >> "$LOG_FILE" 2>&1 || true
  fi
  dl  "$LIN/linuxprivchecker.py"    "https://raw.githubusercontent.com/sleventyeleven/linuxprivchecker/master/linuxprivchecker.py"
  dl  "$LIN/unix-privesc-check"     "https://raw.githubusercontent.com/pentestmonkey/unix-privesc-check/master/unix-privesc-check"
  gc  "$LIN/suid3num"               "https://github.com/Anon-Exploiter/SUID3NUM"
  gc  "$LIN/gtfobins"               "https://github.com/GTFOBins/GTFOBins.github.io"
  gc  "$LIN/static-binaries"        "https://github.com/andrew-d/static-binaries"
  dl  "$LIN/nc_static"              "https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/ncat"
  dl  "$LIN/socat_static"           "https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/socat"
  chmod +x "$LIN/nc_static" "$LIN/socat_static" >> "$LOG_FILE" 2>&1 || true
}

install_web() {
  hdr "Web Exploitation Tools"
  local WEB="${DIRS[web]}"
  # ffuf — in Kali repos; gh_latest fallback if apt fails
  if command -v ffuf &>/dev/null; then
    draw_progress "ffuf" skip
  elif apt_exists ffuf; then
    apti ffuf
  else
    gh_latest "$WEB" "ffuf/ffuf" "ffuf.*linux_amd64\.tar\.gz$"
    for f in "$WEB"/ffuf*.tar.gz; do
      if [[ -f "$f" ]]; then tar -xzf "$f" -C "$WEB" >> "$LOG_FILE" 2>&1 || true; fi
    done
    chmod +x "$WEB/ffuf" >> "$LOG_FILE" 2>&1 || true
  fi
  # feroxbuster — in Kali repos
  if command -v feroxbuster &>/dev/null; then draw_progress "feroxbuster" skip; else apti feroxbuster; fi
  gc  "$WEB/dirsearch"              "https://github.com/maurosoria/dirsearch"
  if command -v whatweb &>/dev/null; then draw_progress "whatweb" skip; else apti whatweb; fi
  if command -v nikto &>/dev/null; then draw_progress "nikto" skip; else apti nikto; fi
  if command -v gobuster &>/dev/null; then draw_progress "gobuster" skip; else apti gobuster; fi
  if command -v wfuzz &>/dev/null; then draw_progress "wfuzz" skip; else apt_or wfuzz pipi wfuzz; fi
  apt_or wafw00f pipi wafw00f
  pipi arjun
  gc  "$WEB/commix"                 "https://github.com/commixproject/commix"
  gc  "$WEB/SSTImap"                "https://github.com/vladko312/SSTImap"
  gc  "$WEB/tplmap"                 "https://github.com/epinna/tplmap"
  gc  "$WEB/jwt_tool"               "https://github.com/ticarpi/jwt_tool"
  gc  "$WEB/php-filter-chain-generator" "https://github.com/synacktiv/php_filter_chain_generator"
  # nuclei — in Kali repos
  if command -v nuclei &>/dev/null; then
    draw_progress "nuclei" skip
  elif apt_exists nuclei; then
    apti nuclei
    nuclei -update-templates -silent >> "$LOG_FILE" 2>&1 || true
  else
    gh_latest "$WEB" "projectdiscovery/nuclei" "nuclei_.*_linux_amd64\.zip$"
    for f in "$WEB"/nuclei_*.zip; do if [[ -f "$f" ]]; then unzip -q -o "$f" nuclei -d "$WEB" >> "$LOG_FILE" 2>&1 || true; fi; done
    chmod +x "$WEB/nuclei" >> "$LOG_FILE" 2>&1 || true
    if [[ -f "$WEB/nuclei" ]]; then "$WEB/nuclei" -update-templates -silent >> "$LOG_FILE" 2>&1 || true; fi
  fi
  # httpx — in Kali repos (golang-github-projectdiscovery-httpx)
  if command -v httpx &>/dev/null; then draw_progress "httpx" skip; else apti httpx; fi
  # katana — in Kali repos
  if command -v katana &>/dev/null; then draw_progress "katana" skip; else apti katana; fi
  # gowitness — in Kali repos
  if command -v gowitness &>/dev/null; then draw_progress "gowitness" skip; else apti gowitness; fi
  gc  "$WEB/EyeWitness"             "https://github.com/FortyNorthSecurity/EyeWitness"
  gc  "$WEB/joomscan"               "https://github.com/OWASP/joomscan"
  pipi droopescan
  gc  "$WEB/CMSeeK"                 "https://github.com/Tuhinshubhra/CMSeeK"
  gc  "$WEB/SSRFmap"                "https://github.com/swisskyrepo/SSRFmap"
  gc  "$WEB/NoSQLMap"               "https://github.com/codingo/NoSQLMap"
  gc  "$WEB/XXEinjector"            "https://github.com/enjoiz/XXEinjector"
  gc  "$WEB/CORStest"               "https://github.com/RUB-NDS/CORStest"
  gc  "$WEB/git-dumper"             "https://github.com/arthaud/git-dumper"
  # sqlmap — PROHIBITED on OSCP exam
  if (( OSCP_MODE )); then
    draw_progress "sqlmap:OSCP-skip" skip
  else
    if command -v sqlmap &>/dev/null; then draw_progress "sqlmap" skip; else apti sqlmap; fi
  fi
  if command -v wpscan &>/dev/null; then draw_progress "wpscan" skip; else apti wpscan; fi
  gc  "$WEB/XSStrike"               "https://github.com/s0md3v/XSStrike"
  gc  "$WEB/PayloadsAllTheThings"   "https://github.com/swisskyrepo/PayloadsAllTheThings"
  # SecLists installed by wordlists module — skip here to avoid duplicate clone
  draw_progress "SecLists" skip
}

install_pivoting() {
  hdr "Pivoting & Tunneling"
  local PIV="${DIRS[pivoting]}"
  # ligolo-ng — in Kali repos
  if apt_exists ligolo-ng; then
    apti ligolo-ng
  else
    gh_latest "$PIV" "nicocha30/ligolo-ng" "ligolo-ng_agent_.*_linux_amd64\.tar\.gz$"
    gh_latest "$PIV" "nicocha30/ligolo-ng" "ligolo-ng_proxy_.*_linux_amd64\.tar\.gz$"
    gh_latest "$PIV" "nicocha30/ligolo-ng" "ligolo-ng_agent_.*_windows_amd64\.zip$"
    for f in "$PIV"/ligolo*.tar.gz; do if [[ -f "$f" ]]; then tar -xzf "$f" -C "$PIV" >> "$LOG_FILE" 2>&1 || true; fi; done
    for f in "$PIV"/ligolo*.zip;    do if [[ -f "$f" ]]; then unzip -q -o "$f" -d "$PIV" >> "$LOG_FILE" 2>&1 || true; fi; done
  fi
  # chisel — in Kali repos; gh_latest fallback if apt fails
  if command -v chisel &>/dev/null; then
    draw_progress "chisel" skip
  elif apt_exists chisel; then
    apti chisel
  else
    gh_latest "$PIV" "jpillora/chisel" "chisel_.*_linux_amd64\.gz$"
    gh_latest "$PIV" "jpillora/chisel" "chisel_.*_windows_amd64\.gz$"
    for f in "$PIV"/chisel*.gz; do
      if [[ -f "$f" ]]; then gunzip -kf "$f" >> "$LOG_FILE" 2>&1 || true; fi
    done
  fi
  dl  "$PIV/socat"  "https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/socat"
  chmod +x "$PIV/socat" >> "$LOG_FILE" 2>&1 || true
  if command -v sshuttle &>/dev/null; then draw_progress "sshuttle" skip; else pipi sshuttle; fi
  if command -v proxychains4 &>/dev/null; then draw_progress "proxychains4" skip; else apti proxychains4; fi
}

install_recon() {
  hdr "Network Reconnaissance"
  local REC="${DIRS[recon]}"
  # rustscan — in Kali repos
  if command -v rustscan &>/dev/null; then draw_progress "rustscan" skip; else apti rustscan; fi
  if command -v masscan &>/dev/null; then draw_progress "masscan" skip; else apti masscan; fi
  gc  "$REC/nmapAutomator"  "https://github.com/21y4d/nmapAutomator"
  ln -sf "$REC/nmapAutomator/nmapAutomator.sh" /usr/local/bin/nmapAutomator >> "$LOG_FILE" 2>&1 || true
  gc  "$REC/AutoRecon"      "https://github.com/Tib3rius/AutoRecon"
  mkdir -p "$REC/nmap-scripts"
  gc  "$REC/nmap-scripts/nmap-vulners"  "https://github.com/vulnersCom/nmap-vulners"
  gc  "$REC/nmap-scripts/vulscan"       "https://github.com/scipag/vulscan"
  ln -sf "$REC/nmap-scripts/nmap-vulners/vulners.nse" /usr/share/nmap/scripts/vulners.nse >> "$LOG_FILE" 2>&1 || true
  ln -sf "$REC/nmap-scripts/vulscan" /usr/share/nmap/scripts/vulscan >> "$LOG_FILE" 2>&1 || true
  nmap --script-updatedb >> "$LOG_FILE" 2>&1 || true
  # smbmap: prefer apt; clone only if package isn't in repos
  if apt_exists smbmap; then
    apti smbmap
  else
    gc "$REC/smbmap" "https://github.com/ShawnDEvans/smbmap"
  fi
  apti smbclient nbtscan
  gc  "$REC/enum4linux-ng"  "https://github.com/cddmp/enum4linux-ng"
  gc  "$REC/WADComs"        "https://github.com/WADComs/WADComs.github.io"
  apti snmp snmp-mibs-downloader onesixtyone
  sed -i 's/^mibs :/#mibs :/' /etc/snmp/snmp.conf >> "$LOG_FILE" 2>&1 || true
  apti dnsrecon dnsenum
  gc  "$REC/dnsrecon"       "https://github.com/darkoperator/dnsrecon"
  apti smtp-user-enum
  apti sqsh redis-tools
  gc  "$REC/odat"           "https://github.com/quentinhardy/odat"
  pipi ssh-audit
  apti arp-scan freerdp2-x11
}

install_passwords() {
  hdr "Password Attacks & Cracking"
  if command -v john &>/dev/null; then draw_progress "john" skip; else apti john; fi
  if command -v hashcat &>/dev/null; then draw_progress "hashcat" skip; else apti hashcat; fi
  pipi name-that-hash
  pipi pypykatz
  if command -v hydra &>/dev/null; then draw_progress "hydra" skip; else apti hydra; fi
  if command -v cewl &>/dev/null; then draw_progress "cewl" skip; else apti cewl; fi
  gc  "$TOOLS_BASE/Wordlists/cupp" "https://github.com/Mebus/cupp"
  dl  "$TOOLS_BASE/Utils/username-anarchy" \
      "https://raw.githubusercontent.com/urbanadventurer/username-anarchy/master/username-anarchy"
  chmod +x "$TOOLS_BASE/Utils/username-anarchy" >> "$LOG_FILE" 2>&1 || true
  gc  "$TOOLS_BASE/Wordlists/statistically-likely-usernames" \
      "https://github.com/insidetrust/statistically-likely-usernames"
  pipi o365spray
  pipi trevorspray
  apti kpcli
  apti fcrackzip
  pipi defaultcreds-cheat-sheet
}

install_rules() {
  hdr "Hashcat Rules"
  local RULES="${DIRS[rules]}"
  dl  "$RULES/OneRuleToRuleThemStill.rule" \
      "https://raw.githubusercontent.com/stealthsploit/OneRuleToRuleThemStill/main/OneRuleToRuleThemStill.rule"
  dl  "$RULES/OneRuleToRuleThemAll.rule" \
      "https://raw.githubusercontent.com/NotSoSecure/password_cracking_rules/master/OneRuleToRuleThemAll.rule"
  gc  "$RULES/Hob0Rules"  "https://github.com/praetorian-code/Hob0Rules"
  ln -sf /usr/share/hashcat/rules "$RULES/hashcat-builtin" >> "$LOG_FILE" 2>&1 || true
  draw_progress "hashcat-builtin-symlink" ok
}

install_wordlists() {
  hdr "Wordlists"
  local WL="${DIRS[wordlists]}"
  if [[ ! -f /usr/share/wordlists/rockyou.txt ]]; then
    if [[ -f /usr/share/wordlists/rockyou.txt.gz ]]; then
      if gunzip /usr/share/wordlists/rockyou.txt.gz >> "$LOG_FILE" 2>&1; then
        draw_progress "rockyou.txt" ok
      else
        draw_progress "rockyou.txt" fail
      fi
    else
      draw_progress "rockyou.txt" fail
    fi
  else
    draw_progress "rockyou.txt" skip
  fi
  ln -sf /usr/share/wordlists "$WL/system_wordlists" >> "$LOG_FILE" 2>&1 || true
  draw_progress "system_wordlists-symlink" ok
  if [[ ! -d /usr/share/seclists ]] && [[ ! -d "$WL/SecLists" ]]; then
    gc "$WL/SecLists" "https://github.com/danielmiessler/SecLists"
  else
    draw_progress "SecLists" skip
  fi
}

install_exploit() {
  hdr "Exploit Resources"
  local EXP="${DIRS[exploit]}"
  if [[ -d /usr/share/exploitdb ]]; then
    draw_progress "exploitdb" skip
  else
    apti exploitdb
  fi
  gc  "$EXP/PEASS-ng"         "https://github.com/peass-ng/PEASS-ng"
  gc  "$EXP/CVE-2021-4034"    "https://github.com/ly4k/PwnKit"
  gc  "$EXP/CVE-2022-0847"    "https://github.com/AlexisAhmed/CVE-2022-0847-DirtyPipe-Exploits"
  gc  "$EXP/CVE-2021-3156"    "https://github.com/blasty/CVE-2021-3156"
  gc  "$EXP/awesome-privesc"  "https://github.com/m0nad/awesome-privilege-escalation"
}

install_shells() {
  hdr "Shell Handlers & Resources"
  local SHL="${DIRS[shells]}"
  # Villain C2 — in Kali repos
  if command -v villain &>/dev/null; then draw_progress "villain" skip; else apti villain; fi
  apt_or pwncat pipi pwncat-cs
  gc  "$SHL/penelope"              "https://github.com/brightio/penelope"
  gc  "$SHL/revshellgen"           "https://github.com/0dayCTF/reverse-shell-generator"
  gc  "$SHL/webshells"             "https://github.com/tennc/webshell"
  dl  "$SHL/p0wny-shell.php"       "https://raw.githubusercontent.com/flozz/p0wny-shell/master/shell.php"
  dl  "$SHL/php-reverse-shell.php" "https://raw.githubusercontent.com/pentestmonkey/php-reverse-shell/master/php-reverse-shell.php"
  dl  "$SHL/msfvenom-cheatsheet.md" "https://raw.githubusercontent.com/frizb/MSF-Venom-Cheatsheet/master/README.md"
  apti rlwrap
}

install_bof() {
  hdr "Buffer Overflow / Exploit Dev"
  local BOF="${DIRS[bof]}"
  pipi pwntools
  pipi ROPgadget
  pipi ropper
  pipi checksec
  if [[ ! -d "$BOF/pwndbg" ]]; then
    gc "$BOF/pwndbg" "https://github.com/pwndbg/pwndbg"
    ( cd "$BOF/pwndbg" && ./setup.sh --quiet >> "$LOG_FILE" 2>&1; ) || true
  else
    draw_progress "pwndbg" skip
  fi
  dl  "$BOF/gef.py"   "https://raw.githubusercontent.com/hugsy/gef/main/gef.py"
  dl  "$BOF/mona.py"  "https://raw.githubusercontent.com/corelan/mona/master/mona.py"
  gem_install one_gadget
  draw_progress "Ghidra(download-manually)" skip
}

install_osint() {
  hdr "OSINT Tools (primarily PNPT)"
  local OSI="${DIRS[osint]}"
  gc  "$OSI/theHarvester"  "https://github.com/laramies/theHarvester"
  gc  "$OSI/recon-ng"      "https://github.com/lanmaster53/recon-ng"
  gc  "$OSI/sherlock"      "https://github.com/sherlock-project/sherlock"
  gc  "$OSI/spiderfoot"    "https://github.com/smicallef/spiderfoot"
  gc  "$OSI/Sublist3r"     "https://github.com/aboul3la/Sublist3r"
  gc  "$OSI/Photon"        "https://github.com/s0md3v/Photon"
  apti metagoofil libimage-exiftool-perl
  pipi shodan
  gh_latest "$OSI" "owasp-amass/amass"  "amass_linux_amd64.*\.zip$"
  for f in "$OSI"/amass_*.zip; do
    if [[ -f "$f" ]]; then unzip -q -o "$f" -d "$OSI" >> "$LOG_FILE" 2>&1 || true; fi
  done
  draw_progress "amass-extract" ok
}

install_reporting() {
  hdr "Reporting Tools"
  local REP="${DIRS[reporting]}"
  gc  "$REP/OSCP-Exam-Report-Template" "https://github.com/noraj/OSCP-Exam-Report-Template-Markdown"
  gc  "$REP/OffSec-Reporting"          "https://github.com/Syslifters/OffSec-Reporting"
  apti cherrytree flameshot
}

install_utils() {
  hdr "Utilities & Cheatsheets"
  local UTL="$TOOLS_BASE/Utils"
  gc  "$UTL/haiti"             "https://github.com/noraj/haiti"
  # enum4linux-ng installed by recon module — skip duplicate clone here
  gc  "$UTL/0xsyr0-OSCP"       "https://github.com/0xsyr0/OSCP"
  gc  "$UTL/HackTricks"        "https://github.com/HackTricks-wiki/hacktricks"
  gc  "$UTL/TheHackerRecipes"  "https://github.com/ShutdownRepo/The-Hacker-Recipes"
  gc  "$UTL/tmux-logging"      "https://github.com/tmux-plugins/tmux-logging"
  apti krb5-user ntpdate faketime
  gh_latest "$UTL" "denisidoro/navi"  "navi-v.*-x86_64-unknown-linux-musl\.tar\.gz$"
  for f in "$UTL"/navi-v*.tar.gz; do
    if [[ -f "$f" ]]; then tar -xzf "$f" -C "$UTL" >> "$LOG_FILE" 2>&1 || true; fi
  done
  draw_progress "navi-extract" ok
  cat > "$UTL/krb5.conf.template" << 'KRB5'
[libdefaults]
    default_realm = DOMAIN.LOCAL
    dns_lookup_realm = false
    dns_lookup_kdc   = true
    ticket_lifetime  = 24h
    forwardable      = true
[realms]
    DOMAIN.LOCAL = { kdc = DC_IP   admin_server = DC_IP }
[domain_realm]
    .domain.local = DOMAIN.LOCAL
    domain.local  = DOMAIN.LOCAL
KRB5
}

# =============================================================================
#  MODULE REGISTRY
# =============================================================================
ALL_MODULES=(ad adcs coercion windows linux web pivoting recon passwords rules wordlists exploit shells bof osint reporting utils)
declare -A MOD_NAME=(
  [ad]="Active Directory -- Core"
  [adcs]="AD CS / Certificate Attacks"
  [coercion]="Auth Coercion + Relay + AD CVEs"
  [windows]="Windows Binaries  (WinPEAS, Potatoes, Privesc)"
  [linux]="Linux Tools  (LinPEAS, pspy, GTFOBins)"
  [web]="Web Exploitation  (ffuf, nuclei, commix, SSTImap)"
  [pivoting]="Pivoting & Tunneling  (Ligolo-ng, Chisel)"
  [recon]="Network Recon  (RustScan, SNMP, SMB, DNS)"
  [passwords]="Password Attacks & Cracking"
  [rules]="Hashcat Rules  (OneRuleToRuleThemStill)"
  [wordlists]="Wordlists  (SecLists, rockyou)"
  [exploit]="Exploit Resources  (PEASS-ng, CVEs)"
  [shells]="Shell Handlers  (Villain, pwncat, Penelope, webshells)"
  [bof]="Buffer Overflow / Exploit Dev  (pwntools, ROPgadget)"
  [osint]="OSINT -- primarily PNPT  (Sherlock, theHarvester)"
  [reporting]="Reporting Tools  (templates, Flameshot)"
  [utils]="Utilities & Cheatsheets  (navi, HackTricks, krb5)"
)
PRESET_OSCP=(ad adcs coercion windows linux web pivoting recon passwords rules wordlists exploit shells bof utils)
PRESET_PNPT=(ad adcs coercion windows linux web pivoting recon passwords rules wordlists exploit shells bof osint reporting utils)
PRESET_AD=(ad adcs coercion recon passwords rules wordlists utils)
PRESET_WEB=(web recon wordlists shells utils)

# =============================================================================
#  INTERACTIVE MENU
# =============================================================================
declare -a SELECTED_MODULES=()

show_menu() {
  clear
  # ── Block-font banner (Figlet "ANON - TOOLS SETUP", box-drawing glyphs) ────
  local FG_ART; FG_ART="$(c256 196)"   # red           for filled glyphs
  local FG_BOX; FG_BOX="$(c256 240)"   # dark grey      for box border
  local FG_DIM; FG_DIM="$(c256 59)"    # dimmer grey    for interior space
  printf "${FG_BOX}+--------------------------------------------------------------------------------------------------------------------------------------------+${RST}\n"
  printf "${FG_BOX}|${RST} ${FG_ART}${BOLD}█████╗ ███╗   ██╗ ██████╗ ███╗   ██╗              ████████╗ ██████╗  ██████╗ ██╗     ███████╗    ███████╗███████╗████████╗██╗   ██╗██████╗${RST} ${FG_BOX}|${RST}\n"
  printf "${FG_BOX}|${RST}${FG_ART}${BOLD}██╔══██╗████╗  ██║██╔═══██╗████╗  ██║              ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗${RST}${FG_BOX}|${RST}\n"
  printf "${FG_BOX}|${RST}${FG_ART}${BOLD}███████║██╔██╗ ██║██║   ██║██╔██╗ ██║    █████╗       ██║   ██║   ██║██║   ██║██║     ███████╗    ███████╗█████╗     ██║   ██║   ██║██████╔╝${RST}${FG_BOX}|${RST}\n"
  printf "${FG_BOX}|${RST}${FG_ART}${BOLD}██╔══██║██║╚██╗██║██║   ██║██║╚██╗██║    ╚════╝       ██║   ██║   ██║██║   ██║██║     ╚════██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ ${RST}${FG_BOX}|${RST}\n"
  printf "${FG_BOX}|${RST}${FG_ART}${BOLD}██║  ██║██║ ╚████║╚██████╔╝██║ ╚████║                 ██║   ╚██████╔╝╚██████╔╝███████╗███████║    ███████║███████╗   ██║   ╚██████╔╝██║     ${RST}${FG_BOX}|${RST}\n"
  printf "${FG_BOX}|${RST}${FG_ART}${BOLD}╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═══╝                 ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ${RST}${FG_BOX}|${RST}\n"
  printf "${FG_BOX}+--------------------------------------------------------------------------------------------------------------------------------------------+${RST}\n"
  # ── Byline row: left-aligned with | borders ─────────────────────────────────
  local byline="  Developed by Anon  -  v6.0 for OSCP/PNPT"
  local inner=144
  local rpad=$(( inner - ${#byline} ))
  if (( rpad < 0 )); then rpad=0; fi
  printf "${FG_BOX}|${RST}$(c256 214)${BOLD}%s%*s${RST}${FG_BOX}|${RST}\n" \
    "$byline" "$rpad" ""
  printf "${FG_BOX}+--------------------------------------------------------------------------------------------------------------------------------------------+${RST}\n"
  printf "\n"
  printf "  ${BOLD}PRESETS${RST}\n"
  printf "  ${G}[A]${RST}  All 17 modules\n"
  printf "  ${G}[O]${RST}  OSCP+ preset  (15 modules -- no OSINT/reporting)\n"
  printf "  ${G}[P]${RST}  PNPT preset   (all 17 modules)\n"
  printf "  ${G}[D]${RST}  AD-only       (AD + ADCS + coercion + recon + passwords)\n"
  printf "  ${G}[W]${RST}  Web-only      (web + recon + wordlists + shells)\n"
  printf "\n  ${BOLD}INDIVIDUAL MODULES${RST}\n"
  local i=1
  for mod in "${ALL_MODULES[@]}"; do
    printf "  ${Y}[%2d]${RST}  %s\n" "$i" "${MOD_NAME[$mod]}"
    (( i++ )) || true
  done
  printf "\n  ${BOLD}[Q]${RST}  Quit\n"
  printf "\n  ${DIM}Enter preset letter, number(s) space-separated, or Q:${RST}\n"
  printf "  ${C}> ${RST}"
}

pick_modules() {
  while true; do
    show_menu
    read -r input
    input=$(printf '%s' "$input" | tr '[:lower:]' '[:upper:]' | xargs)
    case "$input" in
      A) SELECTED_MODULES=("${ALL_MODULES[@]}");  break ;;
      O) SELECTED_MODULES=("${PRESET_OSCP[@]}");  break ;;
      P) SELECTED_MODULES=("${PRESET_PNPT[@]}");  break ;;
      D) SELECTED_MODULES=("${PRESET_AD[@]}");    break ;;
      W) SELECTED_MODULES=("${PRESET_WEB[@]}");   break ;;
      Q) printf "\n  Aborted.\n\n"; exit 0 ;;
      *)
        local ok=true
        local chosen=()
        for tok in $input; do
          if [[ "$tok" =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= ${#ALL_MODULES[@]} )); then
            chosen+=("${ALL_MODULES[$((tok-1))]}")
          else
            printf "\n  ${R}Invalid: %s${RST}\n" "$tok"
            ok=false
            break
          fi
        done
        if $ok && (( ${#chosen[@]} > 0 )); then
          SELECTED_MODULES=("${chosen[@]}")
          break
        fi
        sleep 1
        ;;
    esac
  done
}

confirm_selection() {
  clear
  printf "\n${C}${BOLD}  Selected modules:${RST}\n\n"
  for mod in "${SELECTED_MODULES[@]}"; do
    printf "    ${G}+${RST}  %s\n" "${MOD_NAME[$mod]}"
  done
  printf "\n  ${BOLD}Total operations: ${Y}%d${RST}\n" "$TOTAL"
  printf "  ${DIM}Install path : %s${RST}\n" "$TOOLS_BASE"
  printf "  ${DIM}Log file     : %s${RST}\n" "$LOG_FILE"
  # Show GitHub token status
  printf "  "
  if [[ -n "$GITHUB_TOKEN" ]]; then
    printf "${G}${BOLD}  GitHub token : SET (5000 req/hr — rate limiting disabled)${RST}\n"
  elif (( RATE_LIMIT_MODE )); then
    printf "${C}${BOLD}  GitHub token : NOT SET — rate-limit mode ON (pause at %d/60 calls/hr)${RST}\n"       "$RATE_LIMIT_THRESHOLD"
  else
    printf "${Y}${BOLD}  GitHub token : NOT SET (60 req/hr — gh_latest calls may fail)${RST}\n"
    printf "  ${DIM}  Tip: use --rate-limit to throttle safely, or set GITHUB_TOKEN${RST}\n"
  fi
  if (( OSCP_MODE )); then
    printf "\n  ${R}${BOLD}  !! OSCP MODE ACTIVE — sqlmap and auto-exploitation tools will be SKIPPED !!${RST}\n"
  fi
  printf "\n"
  printf "  ${BOLD}Proceed? [Y/n]: ${RST}"
  read -r yn
  [[ "$yn" =~ ^[Nn]$ ]] && { printf "\n  Aborted.\n\n"; exit 0; }
}

# =============================================================================
#  POST-INSTALL CONFIGURATION
# =============================================================================
post_install_config() {
  hdr "Post-install configuration"

  # ── 1. Metasploit DB init ─────────────────────────────────────────────────
  # msfdb init takes ~30s; only run if postgresql is available and msfdb exists
  announce "msfdb-init"
  if command -v msfdb &>/dev/null; then
    if msfdb status 2>>"$LOG_FILE" | grep -q "connected"; then
      draw_progress "msfdb" skip
    elif msfdb init >> "$LOG_FILE" 2>&1; then
      draw_progress "msfdb" ok
    else
      draw_progress "msfdb" fail
    fi
  else
    draw_progress "msfdb:not-found" skip
  fi

  # ── 2. Proxychains4 — enable dynamic_chain, disable strict_chain ──────────
  announce "proxychains4-config"
  local pc4_conf="/etc/proxychains4.conf"
  if [[ -f "$pc4_conf" ]]; then
    # Switch strict_chain → dynamic_chain (comment out strict, uncomment dynamic)
    if sed -i         -e 's/^strict_chain/#strict_chain/'         -e 's/^#dynamic_chain/dynamic_chain/'         -e 's/^#proxy_dns/proxy_dns/'         "$pc4_conf" >> "$LOG_FILE" 2>&1; then
      draw_progress "proxychains4-config" ok
      printf "[CONFIG] proxychains4: dynamic_chain enabled\n" >> "$LOG_FILE"
    else
      draw_progress "proxychains4-config" fail
    fi
  else
    draw_progress "proxychains4-config:not-found" skip
  fi

  # ── 3. krb5.conf — deploy template if file is default/empty ──────────────
  announce "krb5.conf"
  local krb5_dest="/etc/krb5.conf"
  local krb5_tmpl="$TOOLS_BASE/Utils/krb5.conf.template"
  if [[ ! -f "$krb5_tmpl" ]]; then
    draw_progress "krb5.conf:no-template" skip
  elif [[ ! -f "$krb5_dest" ]] || ! grep -q "DOMAIN.LOCAL" "$krb5_dest" 2>/dev/null; then
    # Only deploy if not already customised
    if cp "$krb5_tmpl" "$krb5_dest" >> "$LOG_FILE" 2>&1; then
      draw_progress "krb5.conf" ok
      printf "[CONFIG] krb5.conf deployed — edit DOMAIN.LOCAL and DC_IP\n" >> "$LOG_FILE"
    else
      draw_progress "krb5.conf" fail
    fi
  else
    draw_progress "krb5.conf" skip
  fi

  # ── 4. nmap script database update ───────────────────────────────────────
  announce "nmap-script-updatedb"
  if command -v nmap &>/dev/null; then
    if nmap --script-updatedb >> "$LOG_FILE" 2>&1; then
      draw_progress "nmap-script-updatedb" ok
    else
      draw_progress "nmap-script-updatedb" fail
    fi
  else
    draw_progress "nmap-script-updatedb:not-found" skip
  fi

  # ── 5. tmux logging plugin — install via tpm if present ──────────────────
  announce "tmux-logging-install"
  local tmux_log="$TOOLS_BASE/Utils/tmux-logging"
  local tmux_plugins="$HOME/.tmux/plugins"
  if [[ -d "$tmux_log" ]]; then
    mkdir -p "$tmux_plugins"
    if [[ ! -d "$tmux_plugins/tmux-logging" ]]; then
      ln -sf "$tmux_log" "$tmux_plugins/tmux-logging" >> "$LOG_FILE" 2>&1 || true
    fi
    draw_progress "tmux-logging-install" ok
  else
    draw_progress "tmux-logging-install:not-found" skip
  fi

}

# =============================================================================
#  POST-INSTALL SUMMARY
# =============================================================================
print_summary() {
  printf "\n"
  printf "${C}${BOLD}  == Installation Summary =============================${RST}\n"
  printf "  ${G}+  Installed : %d${RST}\n" "$PASS"
  printf "  ${DIM}-  Skipped   : %d${RST}\n" "$SKIP"
  printf "  ${R}!  Failed    : %d${RST}\n" "$FAIL"
  printf "  ${BOLD}   Total     : %d / %d${RST}\n\n" "$(( PASS + SKIP + FAIL ))" "$TOTAL"
  if (( ${#FAILED_TOOLS[@]} > 0 )); then
    printf "  ${R}${BOLD}Failed tools:${RST}\n"
    for t in "${FAILED_TOOLS[@]}"; do
      printf "    ${R}!${RST} %s\n" "$t"
    done
    printf "\n"
  fi
  # Elapsed time
  if (( START_TIME > 0 )); then
    local elapsed=$(( $(date +%s) - START_TIME ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))
    printf "  ${DIM}Elapsed  : %dm %02ds${RST}\n" "$mins" "$secs"
  fi
  printf "  ${DIM}Full log : %s${RST}\n\n" "$LOG_FILE"
  # Retry command for failed modules
  if (( ${#FAILED_TOOLS[@]} > 0 )); then
    # Derive which modules had failures
    local failed_mods=()
    for mod in "${SELECTED_MODULES[@]}"; do
      for ft in "${FAILED_TOOLS[@]}"; do
        # Check if tool name loosely matches module dir
        local mod_dir="${DIRS[$mod]:-}"
        if [[ -n "$mod_dir" ]] && echo "$ft" | grep -qi "$(basename "${mod_dir:-x}")"; then
          failed_mods+=("$mod"); break
        fi
      done
    done
    if (( ${#failed_mods[@]} > 0 )); then
      local unique_mods
      unique_mods=$(printf '%s
' "${failed_mods[@]}" | sort -u | tr '\n' ' ')
      printf "  ${Y}${BOLD}  Retry failed modules:${RST}\n"
      printf "  ${C}  ./tools.sh --module %s${RST}\n\n" "$unique_mods"
    else
      printf "  ${Y}${BOLD}  Retry all selected modules:${RST}\n"
      printf "  ${C}  ./tools.sh --module %s${RST}\n\n" "${SELECTED_MODULES[*]}"
    fi
  fi
  printf "${Y}${BOLD}  Auto-configured:${RST}\n"
  printf "  ${G}*${RST} msfdb init          (Metasploit PostgreSQL DB)\n"
  printf "  ${G}*${RST} proxychains4        (dynamic_chain + proxy_dns enabled)\n"
  printf "  ${G}*${RST} /etc/krb5.conf      (template deployed — edit DOMAIN.LOCAL + DC_IP)\n"
  printf "  ${G}*${RST} nmap scripts db     (updatedb run)\n"
  printf "\n${Y}${BOLD}  Still manual:${RST}\n"
  printf "  ${Y}*${RST} /etc/krb5.conf      → replace DOMAIN.LOCAL and DC_IP with real values\n"
  printf "  ${Y}*${RST} Sync clock          → sudo ntpdate <DC_IP>\n"
  printf "  ${Y}*${RST} BloodHound CE       → docker compose up  (inside AD/BloodHound)\n"
  printf "  ${Y}*${RST} Shell handler       → pwncat-cs -lp 4444  or  penelope -p 4444\n"
  printf "  ${R}*${RST} OSCP: sqlmap PROHIBITED | Metasploit ONE target | no AI\n\n"
}

# =============================================================================
#  MAIN
# =============================================================================
# Module → directory key mapping (used to create only needed dirs)
declare -A MOD_DIRS=(
  [ad]="ad adcs"
  [adcs]="adcs"
  [coercion]="ad"
  [windows]="win"
  [linux]="linux"
  [web]="web wordlists"
  [pivoting]="pivoting"
  [recon]="recon"
  [passwords]="wordlists utils"
  [rules]="rules wordlists"
  [wordlists]="wordlists"
  [exploit]="exploit"
  [shells]="shells"
  [bof]="bof"
  [osint]="osint"
  [reporting]="reporting"
  [utils]="utils"
)

# =============================================================================
#  CONNECTIVITY PRE-CHECK
# =============================================================================
check_connectivity() {
  printf "\n${C}${BOLD}  Checking connectivity...${RST}\n\n"
  local ok=true

  # ── 1. DNS ────────────────────────────────────────────────────────────────
  printf "  %-40s" "DNS (github.com)..."
  if host github.com >> "$LOG_FILE" 2>&1   || nslookup github.com >> "$LOG_FILE" 2>&1; then
    printf "${G}${BOLD}OK${RST}\n"
  else
    printf "${R}${BOLD}FAIL${RST}\n"
    ok=false
  fi

  # ── 2. HTTPS ─────────────────────────────────────────────────────────────
  printf "  %-40s" "HTTPS (github.com)..."
  if curl -s --max-time 8 --head "https://github.com" >> "$LOG_FILE" 2>&1; then
    printf "${G}${BOLD}OK${RST}\n"
  else
    printf "${R}${BOLD}FAIL${RST}\n"
    ok=false
  fi

  # ── 3. raw.githubusercontent.com ─────────────────────────────────────────
  printf "  %-40s" "HTTPS (raw.githubusercontent.com)..."
  if curl -s --max-time 8 --head "https://raw.githubusercontent.com" >> "$LOG_FILE" 2>&1; then
    printf "${G}${BOLD}OK${RST}\n"
  else
    printf "${R}${BOLD}FAIL${RST}\n"
    ok=false
  fi

  # ── 4. apt ────────────────────────────────────────────────────────────────
  printf "  %-40s" "apt repos..."
  if DEBIAN_FRONTEND=noninteractive apt-get update -qq >> "$LOG_FILE" 2>&1; then
    printf "${G}${BOLD}OK${RST}\n"
  else
    printf "${Y}${BOLD}WARN (apt update failed — cached lists will be used)${RST}\n"
  fi

  # ── 5. GitHub API rate limit ──────────────────────────────────────────────
  printf "  %-40s" "GitHub API rate limit..."
  local auth_hdr=()
  [[ -n "$GITHUB_TOKEN" ]] && auth_hdr=(-H "Authorization: token ${GITHUB_TOKEN}")
  local rate_json remaining limit
  rate_json=$(curl -s --max-time 8 "${auth_hdr[@]}"     "https://api.github.com/rate_limit" 2>>"$LOG_FILE") || true
  remaining=$(echo "$rate_json" | grep -oP '"remaining":\s*\K[0-9]+' | head -1)
  limit=$(echo    "$rate_json" | grep -oP '"limit":\s*\K[0-9]+'     | head -1)
  if [[ -z "$remaining" ]]; then
    printf "${Y}${BOLD}WARN (could not fetch — API may be unreachable)${RST}\n"
  elif (( remaining < 10 )); then
    printf "${R}${BOLD}${remaining}/${limit} — CRITICAL: gh_latest calls will fail!${RST}\n"
    printf "  ${DIM}  Set GITHUB_TOKEN to get 5000/hr instead of 60/hr${RST}\n"
    ok=false
  elif (( remaining < 30 )); then
    printf "${Y}${BOLD}${remaining}/${limit} — LOW: some gh_latest calls may fail${RST}\n"
    printf "  ${DIM}  Set GITHUB_TOKEN to get 5000/hr${RST}\n"
  else
    printf "${G}${BOLD}${remaining}/${limit}${RST}\n"
  fi

  # ── Result ────────────────────────────────────────────────────────────────
  printf "\n"
  if ! $ok; then
    printf "  ${R}${BOLD}  One or more connectivity checks failed.${RST}\n"
    printf "  ${Y}  Downloads that depend on failed services will fail silently.${RST}\n"
    printf "\n  ${BOLD}Continue anyway? [y/N]: ${RST}"
    read -r yn
    [[ ! "$yn" =~ ^[Yy]$ ]] && { printf "\n  Aborted.\n\n"; exit 1; }
  else
    printf "  ${G}${BOLD}  All checks passed.${RST}  Starting in 2s...\n\n"
    sleep 2
  fi
}

# =============================================================================
#  ARGUMENT PARSING
# =============================================================================
_parse_args() {
  local mode="interactive"   # interactive | module | update | list | config
  local cli_modules=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --module|-m)
        mode="module"
        shift
        while [[ $# -gt 0 && "$1" != --* ]]; do
          cli_modules+=("$1"); shift
        done
        ;;
      --update|-u)
        mode="update"
        UPDATE_MODE=1
        shift
        while [[ $# -gt 0 && "$1" != --* ]]; do
          cli_modules+=("$1"); shift
        done
        ;;
      --config|-c)
        mode="config"; shift ;;
      --list|-l)
        mode="list"; shift ;;
      --dry-run|-n)
        DRY_RUN=1; shift ;;
      --mode)
        shift
        [[ "${1:-}" == "oscp" ]] && OSCP_MODE=1
        shift ;;
      --rate-limit|-r)
        RATE_LIMIT_MODE=1; shift ;;
      --rate-limit-threshold)
        shift
        if [[ "${1:-}" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 58 )); then
          RATE_LIMIT_THRESHOLD="$1"
        else
          printf "  ${R}--rate-limit-threshold must be 1-58 (GitHub allows 60/hr unauthenticated)${RST}\n" >&2
          exit 1
        fi
        RATE_LIMIT_MODE=1   # implicitly enables rate-limit mode
        shift ;;
      --help|-h)
        printf "\nUsage:\n"
        printf "  ./tools.sh                          # interactive menu\n"
        printf "  ./tools.sh --module <mod> [mod...]  # re-run specific modules\n"
        printf "  ./tools.sh --config                 # re-run post-install config only\n"
        printf "  ./tools.sh --list                   # list all available modules\n"
        printf "  ./tools.sh --dry-run                # preview what would be installed\n"
        printf "  ./tools.sh --mode oscp               # skip OSCP-prohibited tools (sqlmap etc)\n"
        printf "  ./tools.sh --rate-limit               # throttle gh_latest calls (no token needed)\n"
        printf "  ./tools.sh --rate-limit-threshold N   # set threshold 1-58 (default 50)\n"
        printf "  ./tools.sh --update                   # update all modules (re-dl, git pull, apt upgrade)\n"
        printf "  ./tools.sh --update <mod> [mod...]    # update specific modules only\n"
        printf "  ./tools.sh --dry-run --module <mod> # preview specific module\n"
        printf "\nModules:\n"
        for m in "${ALL_MODULES[@]}"; do
          printf "  %-14s  %s\n" "$m" "${MOD_NAME[$m]}"
        done
        printf "\n"
        exit 0
        ;;
      *)
        printf "Unknown option: %s\n  Use --help for usage.\n" "$1" >&2
        exit 1 ;;
    esac
  done

  printf '%s' "$mode"
  # Pass cli_modules back via a global
  CLI_MODULES=("${cli_modules[@]}")
}

declare -a CLI_MODULES=()

main() {
  local mode; mode=$(_parse_args "$@")

  # ── --list : just print modules and exit ─────────────────────────────────
  if [[ "$mode" == "list" ]]; then
    printf "\n${C}${BOLD}  Available modules:${RST}\n\n"
    for m in "${ALL_MODULES[@]}"; do
      printf "  ${Y}%-14s${RST}  %s\n" "$m" "${MOD_NAME[$m]}"
    done
    printf "\n  ${DIM}Presets: A=all  O=oscp  P=pnpt  D=ad-only  W=web-only${RST}\n\n"
    exit 0
  fi

  # ── --update : re-download files, pull repos, upgrade apt/pip packages ──────
  if [[ "$mode" == "update" ]]; then
    UPDATE_MODE=1

    # If no modules specified, update all of them
    if (( ${#CLI_MODULES[@]} == 0 )); then
      SELECTED_MODULES=("${ALL_MODULES[@]}")
    else
      # Validate provided module names
      for m in "${CLI_MODULES[@]}"; do
        local found=false
        for valid in "${ALL_MODULES[@]}"; do
          [[ "$m" == "$valid" ]] && found=true && break
        done
        if ! $found; then
          printf "  ${R}Unknown module: '%s'  — use --list to see valid names${RST}\n\n" "$m" >&2
          exit 1
        fi
      done
      SELECTED_MODULES=("${CLI_MODULES[@]}")
    fi

    mkdir -p "$TOOLS_BASE" "$TOOLS_BASE/Utils" "$TOOLS_BASE/Wordlists"
    printf "\n[UPDATE] %s modules=%s\n" "$(date)" "${SELECTED_MODULES[*]}" >> "$LOG_FILE"
    check_connectivity

    # Count ops
    for mod in "${SELECTED_MODULES[@]}"; do
      case "$mod" in
        ad)        count_ad ;;        adcs)      count_adcs ;;
        coercion)  count_coercion ;;  windows)   count_windows ;;
        linux)     count_linux ;;     web)       count_web ;;
        pivoting)  count_pivoting ;;  recon)     count_recon ;;
        passwords) count_passwords ;; rules)     count_rules ;;
        wordlists) count_wordlists ;; exploit)   count_exploit ;;
        shells)    count_shells ;;    bof)       count_bof ;;
        osint)     count_osint ;;     reporting) count_reporting ;;
        utils)     count_utils ;;
      esac
    done

    # Ensure dirs exist
    local _k
    for mod in "${SELECTED_MODULES[@]}"; do
      local dir_keys="${MOD_DIRS[$mod]:-}"
      for _k in $dir_keys; do
        [[ -n "${DIRS[$_k]+x}" ]] && mkdir -p "${DIRS[$_k]}"
      done
    done
    mkdir -p "$TOOLS_BASE/Utils" "$TOOLS_BASE/Wordlists"

    # Confirm screen
    clear
    printf "\n${C}${BOLD}  Update mode — modules to refresh:${RST}\n\n"
    for m in "${SELECTED_MODULES[@]}"; do
      printf "    ${C}↑  ${RST}%s\n" "${MOD_NAME[$m]}"
    done
    printf "\n  ${DIM}What will happen:${RST}\n"
    printf "  ${DIM}  dl  files  → deleted and re-downloaded fresh${RST}\n"
    printf "  ${DIM}  gc  repos  → git pull on every repo${RST}\n"
    printf "  ${DIM}  apt tools  → apt-get install --only-upgrade${RST}\n"
    printf "  ${DIM}  pip tools  → pip install --upgrade${RST}\n"
    printf "\n  ${BOLD}Operations : ${Y}%d${RST}\n" "$TOTAL"
    if [[ -n "$GITHUB_TOKEN" ]]; then
      printf "  ${G}${BOLD}  GitHub token : SET${RST}\n"
    elif (( RATE_LIMIT_MODE )); then
      printf "  ${C}${BOLD}  Rate-limit mode ON (pause at %d/60 calls/hr)${RST}\n" "$RATE_LIMIT_THRESHOLD"
    else
      printf "  ${Y}${BOLD}  GitHub token : NOT SET (60 req/hr)${RST}\n"
    fi
    printf "\n  ${BOLD}Proceed? [Y/n]: ${RST}"
    read -r yn
    [[ "$yn" =~ ^[Nn]$ ]] && { printf "\n  Aborted.\n\n"; exit 0; }

    START_TIME=$(date +%s)
    QUOTE_IDX=$(( (RANDOM + $$) % ${#QUOTES[@]} )) || true
    QUOTE_LAST_CHANGE=0; QUOTE_CHANGED=0; QUOTE_PREV_IDX=$QUOTE_IDX
    tui_init

    for mod in "${SELECTED_MODULES[@]}"; do
      case "$mod" in
        ad)        install_ad ;;        adcs)      install_adcs ;;
        coercion)  install_coercion ;;  windows)   install_windows ;;
        linux)     install_linux ;;     web)       install_web ;;
        pivoting)  install_pivoting ;;  recon)     install_recon ;;
        passwords) install_passwords ;; rules)     install_rules ;;
        wordlists) install_wordlists ;; exploit)   install_exploit ;;
        shells)    install_shells ;;    bof)       install_bof ;;
        osint)     install_osint ;;     reporting) install_reporting ;;
        utils)     install_utils ;;
      esac
    done

    # chmod sweep
    find "$TOOLS_BASE" -maxdepth 6 -type f \
      \( -name "*.sh" -o -name "*.py" -o -name "*.pl" -o -name "*.rb" \) \
      -exec chmod +x {} \; >> "$LOG_FILE" 2>&1 || true

    tui_teardown
    trap - EXIT
    print_summary
    return
  fi

  # ── --config : re-run post-install config only, no TUI menu ──────────────
  if [[ "$mode" == "config" ]]; then
    mkdir -p "$TOOLS_BASE" "$TOOLS_BASE/Utils" "$TOOLS_BASE/Wordlists"
    check_connectivity
    printf "\n${C}${BOLD}  Re-running post-install configuration...${RST}\n\n" >&2
    TOTAL=$(( TOTAL + 5 )) || true
    QUOTE_IDX=$(( (RANDOM + $$) % ${#QUOTES[@]} )) || true
    QUOTE_LAST_CHANGE=0; QUOTE_CHANGED=0; QUOTE_PREV_IDX=$QUOTE_IDX
    # Append to existing log
    printf "\n[RERUN-CONFIG] %s\n" "$(date)" >> "$LOG_FILE"
    tui_init
    post_install_config
    tui_teardown
    trap - EXIT
    print_summary
    return
  fi

  # ── --module : skip menu, run named modules directly ─────────────────────
  if [[ "$mode" == "module" ]]; then
    if (( ${#CLI_MODULES[@]} == 0 )); then
      printf "  ${R}--module requires at least one module name. Use --list to see options.${RST}\n\n" >&2
      exit 1
    fi
    # Validate all provided module names
    for m in "${CLI_MODULES[@]}"; do
      local found=false
      for valid in "${ALL_MODULES[@]}"; do
        [[ "$m" == "$valid" ]] && found=true && break
      done
      if ! $found; then
        printf "  ${R}Unknown module: '%s'  — use --list to see valid names${RST}\n\n" "$m" >&2
        exit 1
      fi
    done
    SELECTED_MODULES=("${CLI_MODULES[@]}")

    mkdir -p "$TOOLS_BASE" "$TOOLS_BASE/Utils" "$TOOLS_BASE/Wordlists"
    # Append to existing log rather than truncating
    printf "\n[RERUN-MODULE] %s modules=%s\n" "$(date)" "${SELECTED_MODULES[*]}" >> "$LOG_FILE"
    check_connectivity

    # Count ops for selected modules
    for mod in "${SELECTED_MODULES[@]}"; do
      case "$mod" in
        ad)        count_ad ;;        adcs)      count_adcs ;;
        coercion)  count_coercion ;;  windows)   count_windows ;;
        linux)     count_linux ;;     web)       count_web ;;
        pivoting)  count_pivoting ;;  recon)     count_recon ;;
        passwords) count_passwords ;; rules)     count_rules ;;
        wordlists) count_wordlists ;; exploit)   count_exploit ;;
        shells)    count_shells ;;    bof)       count_bof ;;
        osint)     count_osint ;;     reporting) count_reporting ;;
        utils)     count_utils ;;
      esac
    done

    # Create dirs for selected modules only
    local _k
    for mod in "${SELECTED_MODULES[@]}"; do
      local dir_keys="${MOD_DIRS[$mod]:-}"
      for _k in $dir_keys; do
        [[ -n "${DIRS[$_k]+x}" ]] && mkdir -p "${DIRS[$_k]}"
      done
    done
    mkdir -p "$TOOLS_BASE/Utils" "$TOOLS_BASE/Wordlists"

    # Show quick non-interactive confirmation
    clear
    printf "\n${C}${BOLD}  Re-running modules:${RST}\n\n"
    for m in "${SELECTED_MODULES[@]}"; do
      printf "    ${Y}>>  ${RST}%s\n" "${MOD_NAME[$m]}"
    done
    printf "\n  ${BOLD}Operations: ${Y}%d${RST}\n" "$TOTAL"
    if [[ -n "$GITHUB_TOKEN" ]]; then
      printf "  ${G}${BOLD}  GitHub token : SET${RST}\n"
    else
      printf "  ${Y}${BOLD}  GitHub token : NOT SET (60 req/hr)${RST}\n"
    fi
    printf "\n  ${BOLD}Proceed? [Y/n]: ${RST}"
    read -r yn
    [[ "$yn" =~ ^[Nn]$ ]] && { printf "\n  Aborted.\n\n"; exit 0; }

    START_TIME=$(date +%s)
    QUOTE_IDX=$(( (RANDOM + $$) % ${#QUOTES[@]} )) || true
    QUOTE_LAST_CHANGE=0; QUOTE_CHANGED=0; QUOTE_PREV_IDX=$QUOTE_IDX
    tui_init

    for mod in "${SELECTED_MODULES[@]}"; do
      case "$mod" in
        ad)        install_ad ;;        adcs)      install_adcs ;;
        coercion)  install_coercion ;;  windows)   install_windows ;;
        linux)     install_linux ;;     web)       install_web ;;
        pivoting)  install_pivoting ;;  recon)     install_recon ;;
        passwords) install_passwords ;; rules)     install_rules ;;
        wordlists) install_wordlists ;; exploit)   install_exploit ;;
        shells)    install_shells ;;    bof)       install_bof ;;
        osint)     install_osint ;;     reporting) install_reporting ;;
        utils)     install_utils ;;
      esac
    done

    # chmod sweep on affected dirs
    find "$TOOLS_BASE" -maxdepth 6 -type f \
      \( -name "*.sh" -o -name "*.py" -o -name "*.pl" -o -name "*.rb" \) \
      -exec chmod +x {} \; >> "$LOG_FILE" 2>&1 || true

    tui_teardown
    trap - EXIT
    print_summary
    return
  fi

  # ── interactive (default) ─────────────────────────────────────────────────
  mkdir -p "$TOOLS_BASE" "$TOOLS_BASE/Utils" "$TOOLS_BASE/Wordlists"

  # Log rotation — keep last 3 runs as install.log.1 install.log.2 install.log.3
  if [[ -f "$LOG_FILE" ]]; then
    if [[ -f "${LOG_FILE}.2" ]]; then mv -f "${LOG_FILE}.2" "${LOG_FILE}.3" || true; fi
    if [[ -f "${LOG_FILE}.1" ]]; then mv -f "${LOG_FILE}.1" "${LOG_FILE}.2" || true; fi
    mv -f "$LOG_FILE" "${LOG_FILE}.1" || true
  fi
  : > "$LOG_FILE"
  printf "[RUN] %s\n" "$(date)" >> "$LOG_FILE"

  # Pre-flight: connectivity check before anything else
  check_connectivity

  # Step 1: pick modules (directory creation deferred until after selection)
  pick_modules

  # Step 2: count total ops
  for mod in "${SELECTED_MODULES[@]}"; do
    case "$mod" in
      ad)        count_ad ;;        adcs)      count_adcs ;;
      coercion)  count_coercion ;;  windows)   count_windows ;;
      linux)     count_linux ;;     web)       count_web ;;
      pivoting)  count_pivoting ;;  recon)     count_recon ;;
      passwords) count_passwords ;; rules)     count_rules ;;
      wordlists) count_wordlists ;; exploit)   count_exploit ;;
      shells)    count_shells ;;    bof)       count_bof ;;
      osint)     count_osint ;;     reporting) count_reporting ;;
      utils)     count_utils ;;
    esac
  done

  # Step 3: confirm
  confirm_selection

  # Step 3b: create only the directories needed by selected modules
  local _k
  for mod in "${SELECTED_MODULES[@]}"; do
    local dir_keys="${MOD_DIRS[$mod]:-}"
    for _k in $dir_keys; do
      [[ -n "${DIRS[$_k]+x}" ]] && mkdir -p "${DIRS[$_k]}"
    done
  done
  mkdir -p "$TOOLS_BASE/Utils" "$TOOLS_BASE/Wordlists"

  # Add post_install_config ops to total
  TOTAL=$(( TOTAL + 5 )) || true

  START_TIME=$(date +%s)

  # Guaranteed apt-get update before any apt installs
  if (( ! DRY_RUN )); then
    printf "  ${DIM}Updating apt package lists...${RST} "
    if DEBIAN_FRONTEND=noninteractive apt-get update -qq >> "$LOG_FILE" 2>&1; then
      printf "${G}done${RST}\n\n"
    else
      printf "${Y}failed (cached lists will be used)${RST}\n\n"
    fi
    sleep 1
  fi

  # Initialise quote state
  QUOTE_IDX=$(( (RANDOM + $$) % ${#QUOTES[@]} )) || true
  QUOTE_LAST_CHANGE=0; QUOTE_CHANGED=0; QUOTE_PREV_IDX=$QUOTE_IDX

  # Step 4: start TUI
  tui_init

  # Step 5: install
  for mod in "${SELECTED_MODULES[@]}"; do
    case "$mod" in
      ad)        install_ad ;;        adcs)      install_adcs ;;
      coercion)  install_coercion ;;  windows)   install_windows ;;
      linux)     install_linux ;;     web)       install_web ;;
      pivoting)  install_pivoting ;;  recon)     install_recon ;;
      passwords) install_passwords ;; rules)     install_rules ;;
      wordlists) install_wordlists ;; exploit)   install_exploit ;;
      shells)    install_shells ;;    bof)       install_bof ;;
      osint)     install_osint ;;     reporting) install_reporting ;;
      utils)     install_utils ;;
    esac
  done

  # Step 6: chmod sweep
  find "$TOOLS_BASE" -maxdepth 6 -type f \
    \( -name "*.sh" -o -name "*.py" -o -name "*.pl" -o -name "*.rb" \) \
    -exec chmod +x {} \; >> "$LOG_FILE" 2>&1 || true
  for _xdir in "$TOOLS_BASE/Linux" "$TOOLS_BASE/Pivoting" "$TOOLS_BASE/Recon"; do
    if [[ -d "$_xdir" ]]; then
      find "$_xdir" -maxdepth 3 -type f ! -name "*.*" \
        -exec chmod +x {} \; >> "$LOG_FILE" 2>&1 || true
    fi
  done

  # Step 7: post-install configuration
  post_install_config

  # Step 8: teardown + summary
  tui_teardown
  trap - EXIT
  print_summary
}

main "$@"

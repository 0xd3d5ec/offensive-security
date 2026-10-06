#!/usr/bin/env bash
# =============================================================================
#  wallhaven-addon.sh — OPTIONAL add-on for i3-neon
#  wallhaven.cc browser in rofi (thumbnail grid), wallpaper-driven accent
#  palette, and auto-rotation. Lives outside the core config, so re-running
#  i3-neon.sh never removes it.
#
#  Install:    ./wallhaven-addon.sh
#  Uninstall:  ./wallhaven-addon.sh --uninstall   (resets palette, keeps downloads)
# =============================================================================
set -Eeuo pipefail

c_b=$'\e[38;2;0;217;255m'; c_r=$'\e[31m'; c_0=$'\e[0m'
log() { printf '%s[+]%s %s\n' "$c_b" "$c_0" "$*"; }
die() { printf '%s[x]%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "Run as your normal user."
[[ -f "$HOME/.config/i3/config" ]] || die "i3-neon config not found — run i3-neon.sh first."

BIN="$HOME/.local/bin/wallhaven"
ADDON_DIR="$HOME/.config/i3-addons"
ADDON="$ADDON_DIR/wallhaven.conf"
I3CFG="$HOME/.config/i3/config"

# ------------------------------------------------------------- uninstall ---
if [[ "${1:-}" == "--uninstall" ]]; then
  if [[ -x "$BIN" ]]; then
    "$BIN" rotate 0 >/dev/null 2>&1 || true
    "$BIN" palette reset >/dev/null 2>&1 || true
  fi
  rm -f "$BIN" "$ADDON"
  i3-msg reload >/dev/null 2>&1 || true
  log "Removed. Downloads kept in ~/Pictures/wallhaven, settings in ~/.config/wallhaven."
  exit 0
fi

# ------------------------------------------------------------ dependencies ---
log "Installing dependencies (jq, python3-pil, curl, libnotify-bin, xdg-utils)..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  jq python3-pil curl libnotify-bin xdg-utils

mkdir -p "$HOME/.local/bin" "$ADDON_DIR" "$HOME/.config/wallhaven"

# ================================================================ the tool ===
log "Writing $BIN ..."
cat > "$BIN" <<'TOOL'
#!/usr/bin/env bash
# wallhaven — rofi wallpaper browser for i3-neon (optional add-on)
#   wallhaven [menu]                 rofi menu (Mod+Shift+w)
#   wallhaven search <query>         thumbnail grid for a query (Esc closes)
#   wallhaven toplist                thumbnail grid for this month's toplist
#   wallhaven next                   random wallpaper from the last search
#   wallhaven rotate <minutes>       auto-switch every N minutes (0 = off)
#   wallhaven palette on|off|apply|reset
#   wallhaven resume                 run by i3 on login/reload
set -uo pipefail

CONF_DIR="$HOME/.config/wallhaven"; CONF="$CONF_DIR/config"; STATE="$CONF_DIR/state"
CACHE="$HOME/.cache/wallhaven"; LOCK="/tmp/wallhaven-rotate.$UID.lock"; PIDF="$HOME/.cache/wallhaven/rotate.pid"
API="https://wallhaven.cc/api/v1/search"
DEF_BLUE="#00d9ff"; DEF_PURPLE="#b026ff"
# Files whose accent colours follow the wallpaper (paths under ~/.config)
THEMED=(i3/config polybar/config.ini polybar/scripts/vpn.sh rofi/neon.rasi dunst/dunstrc alacritty/alacritty.toml
        gtk-3.0/gtk.css gtk-4.0/gtk.css)

# ---- user settings (override in ~/.config/wallhaven/config) ----
WALL_DIR="$HOME/Pictures/wallhaven"
CATEGORIES="110"; PURITY="100"; ATLEAST="1920x1080"; RATIOS=""; API_KEY=""
PRESETS=("dark" "minimal" "cyberpunk" "anime" "space" "abstract" "nature" "city night" "black and white")
# shellcheck source=/dev/null
[[ -f "$CONF" ]] && source "$CONF"
PURITY="100"   # SFW only, regardless of config

# ---- state ----
LAST_QUERY="dark minimal"; ROTATE_MIN=0; AUTO_PALETTE=1
CUR_BLUE="$DEF_BLUE"; CUR_PURPLE="$DEF_PURPLE"; CURRENT_ID=""
# shellcheck source=/dev/null
[[ -f "$STATE" ]] && source "$STATE"
mkdir -p "$CONF_DIR" "$CACHE/thumbs" "$WALL_DIR"

GRID='window {width: 1080px;} listview {columns: 4; lines: 3; spacing: 10px;} element {orientation: vertical; padding: 8px; spacing: 6px;} element-icon {size: 220px; horizontal-align: 0.5;} element-text {horizontal-align: 0.5;}'

save_state() {
  {
    printf 'LAST_QUERY=%q\n'   "$LAST_QUERY"
    printf 'ROTATE_MIN=%q\n'   "$ROTATE_MIN"
    printf 'AUTO_PALETTE=%q\n' "$AUTO_PALETTE"
    printf 'CUR_BLUE=%q\n'     "$CUR_BLUE"
    printf 'CUR_PURPLE=%q\n'   "$CUR_PURPLE"
    printf 'CURRENT_ID=%q\n'   "$CURRENT_ID"
  } > "$STATE"
}
notify() { notify-send -a wallhaven "$@" 2>/dev/null || true; }
fail()   { notify -u critical "wallhaven" "$*"; echo "wallhaven: $*" >&2; exit 1; }
current_file() { readlink -f "$HOME/.config/wallpaper" 2>/dev/null; }

# ------------------------------------------------------------------ API ---
api_search() {  # $1=query $2=sorting [$3=page] -> JSON
  local a=(-fsS --max-time 20 -G "$API" --data-urlencode "q=$1" -d "page=${3:-1}"
           -d "categories=$CATEGORIES" -d "purity=$PURITY" -d "sorting=$2" -d "atleast=$ATLEAST")
  [[ -n "$RATIOS" ]]  && a+=(-d "ratios=$RATIOS")
  [[ -n "$API_KEY" ]] && a+=(-d "apikey=$API_KEY")
  [[ "$2" == "toplist" ]] && a+=(-d "topRange=1M")
  curl "${a[@]}"
}

fetch_full() {  # $1=id $2=url -> local path
  local f="$WALL_DIR/wallhaven-$1.${2##*.}"
  if [[ ! -s "$f" ]]; then
    curl -fsSL --max-time 180 -o "$f.part" "$2" && mv "$f.part" "$f" || { rm -f "$f.part"; return 1; }
  fi
  printf '%s\n' "$f"
}

# ------------------------------------------------- thumbnail grid picker ---
# Shows one page of results. Sets PICK to: a wallpaper index, "back", "more" or "prev".
# Esc = back. Row 0 is always "« back"; pagination entries appear at the end.
pick_page() {  # $1=json $2=prompt $3=page $4=last_page $5=row to pre-select
  local -a keys=() labels=() icons=()
  local id url th r sel i
  RES_IDS=(); RES_URLS=()
  keys+=("back"); labels+=("« back"); icons+=("")
  while IFS=$'\t' read -r id url th r; do
    [[ -n "$id" ]] || continue
    RES_IDS+=("$id"); RES_URLS+=("$url")
    keys+=("$(( ${#RES_IDS[@]} - 1 ))")
    [[ "$id" == "$CURRENT_ID" ]] && labels+=("● $r") || labels+=("$r")
    icons+=("$CACHE/thumbs/$id.jpg")
    [[ -s "${icons[-1]}" ]] || curl -fsSL --max-time 20 -o "${icons[-1]}" "$th" &
  done < <(jq -r '.data[]? | [.id, .path, .thumbs.small, .resolution] | @tsv' <<<"$1")
  wait
  if (( ${#RES_IDS[@]} == 0 )); then notify "wallhaven" "No results for: $2"; PICK="back"; return; fi
  (( $3 > 1 ))  && { keys+=("prev"); labels+=("‹ prev page"); icons+=(""); }
  (( $3 < $4 )) && { keys+=("more"); labels+=("more ›  page $(( $3 + 1 ))/$4"); icons+=(""); }
  sel="$(for i in "${!keys[@]}"; do
           if [[ -n "${icons[i]}" ]]; then printf '%s\0icon\x1f%s\n' "${labels[i]}" "${icons[i]}"
           else printf '%s\n' "${labels[i]}"; fi
         done | rofi -dmenu -i -no-custom -show-icons -format i -selected-row "${5:-1}" \
                -p "$2 · $3/$4" -mesg "Enter: apply (stays open) · Esc: back" -theme-str "$GRID")"
  if [[ "$sel" =~ ^[0-9]+$ ]]; then PICK="${keys[sel]}"; PICK_ROW="$sel"; else PICK="back"; fi
}

# Grid loop: apply as many wallpapers as you like; Esc / « back returns to the caller.
browse() {  # $1=query $2=sorting
  local q="$1" sort="$2" page=1 last=1 json="" fetch=1 row=1 f
  while :; do
    if (( fetch )); then
      json="$(api_search "$q" "$sort" "$page")" || { notify -u critical "wallhaven" "wallhaven.cc unreachable"; return; }
      last="$(jq -r '.meta.last_page // 1' <<<"$json" 2>/dev/null)"; [[ "$last" =~ ^[0-9]+$ ]] || last=1
      fetch=0; row=1
    fi
    pick_page "$json" "${q:-toplist}" "$page" "$last" "$row"
    case "$PICK" in
      back) return ;;
      more) page=$(( page + 1 )); fetch=1 ;;
      prev) page=$(( page - 1 )); fetch=1 ;;
      *)    row="$PICK_ROW"
            [[ -n "$q" ]] && LAST_QUERY="$q"
            notify -t 1500 "wallhaven" "Downloading ${RES_IDS[PICK]} ..."
            if f="$(fetch_full "${RES_IDS[PICK]}" "${RES_URLS[PICK]}")"; then set_wallpaper "$f" "${RES_IDS[PICK]}"
            else notify -u critical "wallhaven" "Download failed"; fi ;;
    esac
  done
}

# ------------------------------------------------------------- palette ---
# Two most vivid wallpaper colours -> neon accents. Greyscale wallpapers -> mono accents.
extract_palette() {  # $1=image -> "#primary #secondary"
  python3 - "$1" <<'PY'
import sys, colorsys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
im.thumbnail((200, 200))
q = im.quantize(16)
pal, counts = q.getpalette(), q.getcolors()
total = sum(c for c, _ in counts)
cands = []
for c, i in counts:
    r, g, b = pal[i*3:i*3+3]
    h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
    cands.append((c/total, h, s, v))
vivid = [x for x in cands if x[2] >= 0.35 and x[3] >= 0.25 and x[0] >= 0.005]
if not vivid:
    print("#f2f2f2 #8c8c94"); sys.exit()
def neon(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h, min(max(s, 0.70), 1), min(max(v, 0.95), 1))
    return "#%02x%02x%02x" % (round(r*255), round(g*255), round(b*255))
def hue_dist(a, b):
    d = abs(a - b); return min(d, 1 - d)
vivid.sort(key=lambda x: x[2] * x[3] * x[0] ** 0.3, reverse=True)
a = vivid[0]
b = next((x for x in vivid[1:] if hue_dist(x[1], a[1]) >= 0.11), None)
second = neon(*b[1:]) if b else neon((a[1] - 0.08) % 1, a[2], a[3])
print(neon(*a[1:]), second)
PY
}

used_elsewhere() {  # is colour $1 used in a themed file for something other than an accent?
  local f
  for f in "${THEMED[@]}"; do
    [[ -f "$HOME/.config/$f" ]] && grep -qiF "$1" "$HOME/.config/$f" && return 0
  done
  return 1
}
uniq_color() {  # nudge a colour so it never collides with non-accent colours
  local c="${1,,}" n
  while [[ "$c" != "${CUR_BLUE,,}" && "$c" != "${CUR_PURPLE,,}" && "$c" != "$DEF_BLUE" && "$c" != "$DEF_PURPLE" ]] \
        && used_elsewhere "$c"; do
    n=$(( (16#${c:5:2} + 255) % 256 )); c="${c:0:5}$(printf '%02x' "$n")"
  done
  printf '%s' "$c"
}

apply_palette() {  # $1=primary $2=secondary
  local nb np f p before changed=0
  nb="$(uniq_color "$1")"; np="$(uniq_color "$2")"
  for f in "${THEMED[@]}"; do
    p="$HOME/.config/$f"; [[ -f "$p" ]] || continue
    before="$(md5sum < "$p")"
    sed -i -e "s/$DEF_BLUE/@@NB@@/gI"   -e "s/$CUR_BLUE/@@NB@@/gI" \
           -e "s/$DEF_PURPLE/@@NP@@/gI" -e "s/$CUR_PURPLE/@@NP@@/gI" \
           -e "s/@@NB@@/$nb/g" -e "s/@@NP@@/$np/g" "$p"
    [[ "$(md5sum < "$p")" != "$before" ]] && changed=1
  done
  CUR_BLUE="$nb"; CUR_PURPLE="$np"; save_state
  if (( changed )); then     # reload only on real change (prevents reload loops)
    i3-msg reload >/dev/null 2>&1
    "$HOME/.config/polybar/launch.sh" >/dev/null 2>&1
    pkill -x dunst 2>/dev/null; (dunst >/dev/null 2>&1 &)
  fi
}

palette_from() {
  local out
  [[ -f "${1:-}" ]] || { notify "palette" "No current wallpaper"; return 1; }
  out="$(extract_palette "$1")" || { notify "palette" "Could not read colours"; return 1; }
  # shellcheck disable=SC2086
  apply_palette $out
}

# ----------------------------------------------------------- wallpaper ---
set_wallpaper() {  # $1=file $2=id
  local link="$HOME/.config/wallpaper"
  [[ -f "$link" && ! -L "$link" ]] && mv "$link" "$WALL_DIR/previous-$(date +%s)"
  ln -sfn "$1" "$link"
  "$HOME/.config/i3/scripts/wallpaper.sh" >/dev/null 2>&1 &
  CURRENT_ID="$2"; save_state
  (( AUTO_PALETTE )) && palette_from "$1"
  return 0
}

do_next() {  # random from last search; offline -> shuffle local collection
  local json="" id="" url="" f=""
  if json="$(api_search "$LAST_QUERY" random)"; then
    IFS=$'\t' read -r id url < <(jq -r --arg cur "$CURRENT_ID" \
      '[.data[]? | select(.id != $cur)][0] // {} | [.id // "", .path // ""] | @tsv' <<<"$json")
  fi
  if [[ -n "$id" ]] && f="$(fetch_full "$id" "$url")"; then
    set_wallpaper "$f" "$id"
  else
    f="$(find "$WALL_DIR" -maxdepth 1 -type f -name 'wallhaven-*' ! -name '*.part' | shuf -n1)"
    [[ -n "$f" ]] || fail "Offline and no downloaded wallpapers yet"
    id="${f##*/wallhaven-}"; set_wallpaper "$f" "${id%.*}"
  fi
}

# -------------------------------------------------------------- rotation ---
start_daemon() { setsid -f "$0" daemon >/dev/null 2>&1 </dev/null; }
stop_daemon() {  # kill only our own recorded rotation process (never pattern-match)
  local p; p="$(cat "$PIDF" 2>/dev/null)" || return 0
  if [[ "$p" =~ ^[0-9]+$ ]] && tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "wallhaven daemon"; then
    pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null
  fi
  rm -f "$PIDF"
}
daemon() {
  exec 9>"$LOCK"; flock -n 9 || exit 0
  echo "$$" > "$PIDF"
  while :; do
    # 9>&- : children (sleep, polybar relaunch, ...) must not inherit the lock fd,
    # or they keep holding it after this loop dies and block the next start
    sleep "$(( ROTATE_MIN * 60 ))" 9>&-
    # shellcheck source=/dev/null
    source "$STATE"; (( ROTATE_MIN > 0 )) || exit 0
    do_next 9>&-
  done
}
rotate() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || fail "rotate needs minutes (0 = off)"
  ROTATE_MIN="$1"; save_state
  stop_daemon; sleep 0.3
  if (( ROTATE_MIN > 0 )); then start_daemon; notify "wallhaven" "Rotating every ${ROTATE_MIN} min ($LAST_QUERY)"
  else notify "wallhaven" "Rotation off"; fi
}

resume() {  # login / i3 reload: re-apply palette (no-op if already applied) + restart rotation
  if [[ "$CUR_BLUE" != "$DEF_BLUE" || "$CUR_PURPLE" != "$DEF_PURPLE" ]]; then
    apply_palette "$CUR_BLUE" "$CUR_PURPLE"
  fi
  (( ROTATE_MIN > 0 )) && start_daemon
  return 0
}

palette_cmd() {
  case "${1:-}" in
    on)    AUTO_PALETTE=1; save_state; palette_from "$(current_file)" ;;
    off)   AUTO_PALETTE=0; save_state; notify "palette" "Accents no longer follow the wallpaper" ;;
    apply) palette_from "$(current_file)" ;;
    reset) AUTO_PALETTE=0; save_state; apply_palette "$DEF_BLUE" "$DEF_PURPLE"
           notify "palette" "Neon defaults restored (follow-wallpaper off)" ;;
    *)     fail "palette on|off|apply|reset" ;;
  esac
}

# ------------------------------------------------------------------ menu ---
rofi_menu() {  # $1=prompt $2=width $3=lines [$4=mesg], items on stdin
  rofi -dmenu -i -p "$1" ${4:+-mesg "$4"} -theme-str "window {width: $2px;} listview {lines: $3;}"
}

rotate_menu() {
  local q
  q="$(printf '« back\noff\n15\n30\n60\n120\n' | rofi_menu "rotate every (min)" 320 6 "Esc: back")" || return 0
  case "$q" in "« back"|"") return 0 ;; off) rotate 0 ;; *[!0-9]*) return 0 ;; *) rotate "$q" ;; esac
}

menu() {  # loops until Esc on the main level
  local pal rot choice q p
  while :; do
    # shellcheck source=/dev/null
    [[ -f "$STATE" ]] && source "$STATE"
    (( AUTO_PALETTE )) && pal="on" || pal="off"
    (( ROTATE_MIN > 0 )) && rot="every ${ROTATE_MIN} min" || rot="off"
    local items=("search ..." "next      $LAST_QUERY" "toplist   this month")
    for p in "${PRESETS[@]}"; do items+=("browse    $p"); done
    items+=("palette   follow wallpaper: $pal"
            "palette   re-apply from current wallpaper"
            "palette   reset to neon defaults"
            "rotate    $rot"
            "open      current on wallhaven.cc"
            "open      wallpaper folder")
    choice="$(printf '%s\n' "${items[@]}" | rofi_menu "wallhaven" 560 12 "type any search + Enter · Esc: close")" || return 0
    case "$choice" in
      "search ...")
        q="$(rofi -dmenu -p "search" -mesg "Esc: back" -theme-str 'listview {lines: 0;}' </dev/null)" || continue
        [[ -n "$q" ]] && browse "$q" relevance ;;
      "next "*)             do_next ;;
      "toplist "*)          browse "" toplist ;;
      "browse "*)           q="${choice#browse}"; browse "${q#"${q%%[! ]*}"}" relevance ;;
      *"follow wallpaper"*) if [[ "$pal" == "on" ]]; then palette_cmd off; else palette_cmd on; fi ;;
      *"re-apply"*)         palette_cmd apply ;;
      *"neon defaults")     palette_cmd reset ;;
      "rotate "*)           rotate_menu ;;
      *"wallhaven.cc")      [[ -n "$CURRENT_ID" ]] && xdg-open "https://wallhaven.cc/w/$CURRENT_ID" >/dev/null 2>&1 &
                            return 0 ;;
      *"wallpaper folder")  xdg-open "$WALL_DIR" >/dev/null 2>&1 & return 0 ;;
      "")                   return 0 ;;
      *)                    browse "$choice" relevance ;;   # free-typed search
    esac
  done
}

case "${1:-menu}" in
  menu)    menu ;;
  search)  shift; [[ -n "$*" ]] && browse "$*" relevance ;;
  toplist) browse "" toplist ;;
  next)    do_next ;;
  rotate)  rotate "${2:-}" ;;
  palette) palette_cmd "${2:-}" ;;
  resume)  resume ;;
  daemon)  daemon ;;
  *)       sed -n '2,9p' "$0"; exit 1 ;;
esac
TOOL
chmod +x "$BIN"

# --------------------------------------------------------- user settings ---
if [[ ! -f "$HOME/.config/wallhaven/config" ]]; then
  cat > "$HOME/.config/wallhaven/config" <<'EOF'
# wallhaven add-on settings (sourced as bash)

# Categories as 3 bits: general / anime / people
#   100 = general only, 110 = general + anime, 010 = anime only
CATEGORIES="110"

# Minimum resolution and optional aspect ratios (e.g. "16x9,16x10")
ATLEAST="1920x1080"
RATIOS=""

# Optional wallhaven.cc API key (not needed for normal use)
API_KEY=""

WALL_DIR="$HOME/Pictures/wallhaven"

# Shown as "browse ..." entries in the menu
PRESETS=("dark" "minimal" "cyberpunk" "anime" "space" "abstract" "nature" "city night" "black and white")
EOF
fi

# ------------------------------------------------------------ i3 hook-up ---
cat > "$ADDON" <<EOF
# wallhaven add-on (remove with: wallhaven-addon.sh --uninstall)
bindsym \$mod+Shift+w exec --no-startup-id $BIN menu
exec_always --no-startup-id $BIN resume
EOF

if ! grep -q '^include ~/.config/i3-addons/\*.conf' "$I3CFG"; then
  printf '\n# ─── add-ons (optional, survive config regeneration) ─────────────────\ninclude ~/.config/i3-addons/*.conf\n' >> "$I3CFG"
  log "Added add-on include to ~/.config/i3/config"
fi

if command -v i3 >/dev/null && ! i3 -C -c "$I3CFG" >/tmp/i3-check.log 2>&1; then
  die "i3 config check failed — see /tmp/i3-check.log"
fi
i3-msg reload >/dev/null 2>&1 || true

cat <<EOF

${c_b}wallhaven add-on installed.${c_0}
  Alt/Super+Shift+w   open the menu
  Settings            ~/.config/wallhaven/config
  Downloads           ~/Pictures/wallhaven
  CLI                 wallhaven search "neon city" | next | rotate 30 | palette reset
  Uninstall           ./wallhaven-addon.sh --uninstall
EOF

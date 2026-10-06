#!/usr/bin/env bash
# =============================================================================
#  i3-neon.sh — one-shot i3wm desktop for Kali / Debian (VM, laptop or desktop)
#  i3 + polybar + rofi + picom + dunst + alacritty
#  Theme: pure black, solid neon blue + purple accent blocks. No blur, no animations.
#
#  Usage:   ./i3-neon.sh [--alt] [--layouts us,ara] [--kb-toggle OPT] [--configs-only]
#    --alt           Use Alt as $mod instead of Super (handy if the host OS eats Win-key combos)
#    --layouts L     XKB layouts, comma separated (e.g. us,ara)
#    --kb-toggle OPT XKB layout-switch option when >1 layout (default grp:alt_caps_toggle = Alt+CapsLock)
#    --configs-only  Skip apt + session switching; only (re)write dotfiles
#    --laptop / --no-laptop  Force laptop features on/off (default: auto-detected)
#
#  Auto-detected: VM (auto-resize, VMware tools) · bare metal (multi-monitor manager,
#  native resolution at max refresh, DPI scaling) · laptop (battery, Wi-Fi, backlight,
#  touchpad tap-to-click, TLP power saving, Bluetooth, low-battery alerts).
#
#  XFCE is NOT removed. Pick the session at the LightDM login screen,
#  or run ~/.config/i3-neon/rollback.sh to make XFCE the default again.
# =============================================================================
set -Eeuo pipefail

# ---------------------------------------------------------------- options ---
MOD="Mod4"; KB_LAYOUTS="us"; KB_TOGGLE="grp:alt_caps_toggle"; CONFIGS_ONLY=0; LAPTOP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --alt) MOD="Mod1" ;;
    --layouts) KB_LAYOUTS="${2:?--layouts needs a value}"; shift ;;
    --kb-toggle) KB_TOGGLE="${2:?--kb-toggle needs a value}"; shift ;;
    --configs-only) CONFIGS_ONLY=1 ;;
    --laptop) LAPTOP=1 ;;
    --no-laptop) LAPTOP=0 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ----------------------------------------------------------------- palette ---
BG="#000000"; BG_ALT="#000000"; FG="#c9d1d9"; DIM="#4a4a5e"
BLUE="#00d9ff"; PURPLE="#b026ff"; URGENT="#ff2a6d"; GREEN="#39ff14"
TXT="#e6e6e6"; GREY="#7a7a85"; SEP="#3a3a44"        # bar: bold labels / grey details / dim separators
FONT="JetBrainsMono Nerd Font"
TERM_BIN="alacritty"

# Font Awesome glyphs (present in every Nerd Font), as raw UTF-8 bytes
I_CLOCK=$'\xef\x80\x97'; I_CPU=$'\xef\x8b\x9b';  I_MEM=$'\xef\x88\xb3'
I_DISK=$'\xef\x82\xa0';  I_NET=$'\xef\x83\xa8';  I_LOCK=$'\xef\x80\xa3'
I_UNLOCK=$'\xef\x82\x9c'; I_VOL=$'\xef\x80\xa8'; I_MUTE=$'\xef\x80\xa6'
I_POWER=$'\xef\x80\x91'; I_APPS=$'\xef\x80\x89'; I_RUN=$'\xef\x84\xa0'
I_WIN=$'\xef\x8b\x92';   I_SSH=$'\xef\x82\xac';  I_SLEEP=$'\xef\x86\x86'
I_LOGOUT=$'\xef\x82\x8b'; I_REBOOT=$'\xef\x80\xa1'; I_KEY=$'\xef\x84\x9c'
I_SHIELD=$'\xef\x84\xb2'; I_FILE=$'\xef\x85\x9c'

# ----------------------------------------------------------------- helpers ---
c_b=$'\e[38;2;0;217;255m'; c_p=$'\e[38;2;176;38;255m'; c_r=$'\e[31m'; c_0=$'\e[0m'
log()  { printf '%s[+]%s %s\n' "$c_b" "$c_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_p" "$c_0" "$*"; }
die()  { printf '%s[x]%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }
trap 'die "Failed at line $LINENO: $BASH_COMMAND"' ERR
vge() { [[ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }   # $1 >= $2
verof() { "$@" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true; }


[[ $EUID -eq 0 ]] && die "Run as your normal user; sudo is used only where needed."
command -v apt-get >/dev/null || die "apt-based distro (Kali/Debian) required."

VIRT="$(systemd-detect-virt 2>/dev/null)" || true; VIRT="${VIRT:-none}"
OS_ID="$(. /etc/os-release 2>/dev/null; echo "${ID:-unknown}")"
OS_VER="$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-}")"
if [[ "$OS_ID" == "debian" && -n "$OS_VER" ]] && ! vge "$OS_VER" 13; then
  warn "Debian $OS_VER detected: alacritty/polybar here are too old for this config. Debian 13 (trixie) or newer is recommended."
fi

# Laptop detection: a system battery (not a mouse/keyboard battery) on bare metal
BAT=""; ADP=""; BACKLIGHT=""
for p in /sys/class/power_supply/*; do
  [[ -e "$p" ]] || continue
  case "$(cat "$p/type" 2>/dev/null)" in
    Battery) [[ -z "$BAT" && "$(cat "$p/scope" 2>/dev/null)" != "Device" ]] && BAT="${p##*/}" ;;
    Mains)   [[ -z "$ADP" ]] && ADP="${p##*/}" ;;
  esac
done
for p in /sys/class/backlight/*; do [[ -e "$p" ]] && { BACKLIGHT="${p##*/}"; break; }; done
if [[ -z "$LAPTOP" ]]; then [[ "$VIRT" == "none" && -n "$BAT" ]] && LAPTOP=1 || LAPTOP=0; fi
if (( LAPTOP )); then BAT="${BAT:-BAT0}"; ADP="${ADP:-AC}"; fi
if [[ "$VIRT" != "none" ]]; then PLATFORM="VM ($VIRT)"; elif (( LAPTOP )); then PLATFORM="laptop"; else PLATFORM="desktop"; fi
PICOM_BACKEND="xrender"   # no blur, no transparency: cheapest + most stable backend

CFG="$HOME/.config"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config/i3-neon/backup-$STAMP"

# --------------------------------------------------------------- packages ---
if [[ $CONFIGS_ONLY -eq 0 ]]; then
  sudo -v || die "sudo required. On a fresh Debian install: su -c \"usermod -aG sudo $USER\" then log out and back in."
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &

  log "Updating package index..."
  sudo apt-get update -qq

  REQUIRED=(i3 polybar rofi picom dunst alacritty i3lock xss-lock feh x11-xserver-utils)
  OPTIONAL=(libnotify-bin flameshot xclip xdotool arandr lxappearance pavucontrol
            pulseaudio-utils playerctl network-manager-gnome lxpolkit numlockx
            fonts-font-awesome fonts-jetbrains-mono curl xz-utils fontconfig
            qt5-gtk-platformtheme qt6-gtk-platformtheme)
  [[ "$VIRT" == "vmware" ]] && OPTIONAL+=(open-vm-tools-desktop)
  [[ "$VIRT" != "none" ]]   && OPTIONAL+=(x11-utils)          # xev, for the VM auto-resize watcher
  if [[ "$VIRT" == "none" ]]; then
    # bare metal: what a minimal Debian install lacks (already present on Kali)
    OPTIONAL+=(xserver-xorg xinit network-manager thunar gvfs-backends pipewire-audio
               papirus-icon-theme dbus-x11 xdg-user-dirs x11-utils)
    # login screen, unless another display manager (gdm3, sddm ...) is already set up
    [[ -s /etc/X11/default-display-manager ]] || OPTIONAL+=(lightdm lightdm-gtk-greeter)
  fi
  if (( LAPTOP )); then
    OPTIONAL+=(brightnessctl bluez blueman)
    dpkg -s power-profiles-daemon >/dev/null 2>&1 || OPTIONAL+=(tlp)
  fi

  for p in "${REQUIRED[@]}"; do
    apt-cache show "$p" >/dev/null 2>&1 || die "Required package not found in repos: $p"
  done
  AVAIL=()
  for p in "${OPTIONAL[@]}"; do
    if apt-cache show "$p" >/dev/null 2>&1; then AVAIL+=("$p"); else warn "Skipping unavailable package: $p"; fi
  done

  log "Installing packages..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    "${REQUIRED[@]}" "${AVAIL[@]}"

  # Nerd Font (icons in polybar/rofi depend on it)
  if ! fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    log "Installing JetBrainsMono Nerd Font..."
    FDIR="$HOME/.local/share/fonts/JetBrainsMonoNF"; mkdir -p "$FDIR"
    if curl -fsSL --retry 2 -o /tmp/jbm-nf.tar.xz \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz; then
      tar -xJf /tmp/jbm-nf.tar.xz -C "$FDIR" && rm -f /tmp/jbm-nf.tar.xz
      fc-cache -f >/dev/null
    else
      warn "Nerd Font download failed; falling back to JetBrains Mono (some icons may render as boxes)."
      FONT="JetBrains Mono"
    fi
  fi
fi

# ------------------------------------------------------- version detection ---
I3_VER="$(command -v i3 >/dev/null && verof i3 --version || echo 4.23)"
PB_VER="$(command -v polybar >/dev/null && verof polybar --version || echo 3.7.0)"
AL_VER="$(command -v alacritty >/dev/null && verof alacritty --version || echo 0.13.0)"
IFACE="$(ip route 2>/dev/null | awk '/^default/{print $5; exit}' || true)"; IFACE="${IFACE:-eth0}"

# Only add a layout-switch option with 2+ layouts. Always clear stale options first:
# grp:alt_shift_toggle hijacks Alt+Shift and breaks every $mod+Shift binding when $mod=Alt.
if [[ "$KB_LAYOUTS" == *,* ]]; then
  [[ "$MOD" == "Mod1" && "$KB_TOGGLE" == "grp:alt_shift_toggle" ]] && \
    { warn "grp:alt_shift_toggle conflicts with Alt as mod; using grp:alt_caps_toggle"; KB_TOGGLE="grp:alt_caps_toggle"; }
  KB_CMD="setxkbmap -layout $KB_LAYOUTS -option '' -option $KB_TOGGLE"
else
  KB_CMD="setxkbmap -layout $KB_LAYOUTS -option ''"
fi

# DPI-aware bar: sizes in pt follow Xft.dpi (set per display by monitors.sh); 21pt = 28px at 96 DPI
if vge "$PB_VER" 3.6.0; then BAR_HEIGHT="21pt"; BAR_DPI='dpi = ${xrdb:Xft.dpi:96}'; else BAR_HEIGHT="28"; BAR_DPI=""; fi
if (( LAPTOP )); then
  MODULES_RIGHT="fs memory cpu wifi net vpn${BACKLIGHT:+ backlight} pulseaudio battery date"
elif [[ "$VIRT" == "none" ]]; then
  MODULES_RIGHT="fs memory cpu net vpn pulseaudio date"
else
  MODULES_RIGHT="fs memory cpu net vpn date"
fi

if vge "$PB_VER" 3.7.0; then TRAY_MODULE=" tray"; TRAY_LEGACY=""
else TRAY_MODULE=""; TRAY_LEGACY="tray-position = right"; fi

log "platform: $PLATFORM | os: $OS_ID $OS_VER${BAT:+ | battery: $BAT}${BACKLIGHT:+ | backlight: $BACKLIGHT}"
log "i3 $I3_VER | polybar $PB_VER | alacritty $AL_VER | iface $IFACE | virt $VIRT | mod $MOD | kb: $KB_CMD"

# ----------------------------------------------------------------- backups ---
mkdir -p "$BACKUP"
for d in i3 polybar rofi picom dunst alacritty; do
  if [[ -e "$CFG/$d" ]]; then mv "$CFG/$d" "$BACKUP/"; log "Backed up ~/.config/$d"; fi
done
[[ -f "$CFG/gtk-3.0/settings.ini" ]] && cp "$CFG/gtk-3.0/settings.ini" "$BACKUP/gtk3-settings.ini"
for v in 3 4; do   # keep a user's own gtk.css; ours is marked "i3-neon"
  f="$CFG/gtk-$v.0/gtk.css"
  if [[ -f "$f" ]] && ! grep -q 'i3-neon' "$f"; then cp "$f" "$BACKUP/gtk$v-gtk.css"; fi
done
mkdir -p "$CFG"/{i3/scripts,polybar/scripts,rofi,picom,dunst,alacritty,gtk-3.0,gtk-4.0}

# Template renderer: replaces @TOKENS@ in stdin
render() {
  sed -e "s|@BG@|$BG|g"         -e "s|@BG_ALT@|$BG_ALT|g"   -e "s|@FG@|$FG|g" \
      -e "s|@DIM@|$DIM|g"       -e "s|@BLUE@|$BLUE|g"       -e "s|@PURPLE@|$PURPLE|g" \
      -e "s|@URGENT@|$URGENT|g" -e "s|@GREEN@|$GREEN|g"     -e "s|@FONT@|$FONT|g" \
      -e "s|@MOD@|$MOD|g"       -e "s|@TERM@|$TERM_BIN|g"   -e "s|@HOME@|$HOME|g" \
      -e "s|@KB_CMD@|$KB_CMD|g" -e "s|@IFACE@|$IFACE|g"     -e "s|@PICOM_BACKEND@|$PICOM_BACKEND|g" \
      -e "s|@TRAY_MODULE@|$TRAY_MODULE|g" -e "s|@TRAY_LEGACY@|$TRAY_LEGACY|g" \
      -e "s|@I_CLOCK@|$I_CLOCK|g" -e "s|@I_CPU@|$I_CPU|g"   -e "s|@I_MEM@|$I_MEM|g" \
      -e "s|@I_DISK@|$I_DISK|g"   -e "s|@I_NET@|$I_NET|g"   -e "s|@I_LOCK@|$I_LOCK|g" \
      -e "s|@I_UNLOCK@|$I_UNLOCK|g" -e "s|@I_VOL@|$I_VOL|g" -e "s|@I_MUTE@|$I_MUTE|g" \
      -e "s|@I_POWER@|$I_POWER|g" -e "s|@I_APPS@|$I_APPS|g" -e "s|@I_RUN@|$I_RUN|g" \
      -e "s|@I_WIN@|$I_WIN|g"     -e "s|@I_SSH@|$I_SSH|g"   -e "s|@I_SLEEP@|$I_SLEEP|g" \
      -e "s|@I_LOGOUT@|$I_LOGOUT|g" -e "s|@I_REBOOT@|$I_REBOOT|g" -e "s|@I_KEY@|$I_KEY|g" \
      -e "s|@I_SHIELD@|$I_SHIELD|g" -e "s|@I_FILE@|$I_FILE|g" \
      -e "s|@TXT@|$TXT|g"         -e "s|@GREY@|$GREY|g"     -e "s|@SEP@|$SEP|g" \
      -e "s|@BAT@|$BAT|g"         -e "s|@ADP@|$ADP|g"       -e "s|@BACKLIGHT@|$BACKLIGHT|g" \
      -e "s|@MODULES_RIGHT@|$MODULES_RIGHT|g" -e "s|@BAR_HEIGHT@|$BAR_HEIGHT|g" -e "s|@BAR_DPI@|$BAR_DPI|g"
}

# =============================================================== i3 config ===
log "Writing i3 config..."
render > "$CFG/i3/config" <<'EOF'
# ─── i3-neon ─────────────────────────────────────────────────────────────
set $mod @MOD@
set $term @TERM@
set $rofi ~/.config/rofi

font pango:@FONT@ 10
floating_modifier $mod
tiling_drag modifier titlebar
default_border pixel 2
default_floating_border pixel 2
hide_edge_borders smart
focus_follows_mouse no
focus_on_window_activation smart
workspace_auto_back_and_forth yes

gaps inner 6
gaps outer 0
smart_gaps on

# class                 border     bg        text      indicator  child_border
client.focused          @BLUE@     @BG@      @FG@      @PURPLE@   @BLUE@
client.focused_inactive @PURPLE@   @BG@      @DIM@     @PURPLE@   @BG_ALT@
client.unfocused        @BG_ALT@   @BG@      @DIM@     @BG_ALT@   @BG_ALT@
client.urgent           @URGENT@   @BG@      @FG@      @URGENT@   @URGENT@
client.placeholder      @BG_ALT@   @BG@      @DIM@     @BG_ALT@   @BG_ALT@
client.background       @BG@

# ─── autostart ───────────────────────────────────────────────────────────
exec_always --no-startup-id ~/.config/i3/scripts/wallpaper.sh
exec_always --no-startup-id sh -c 'pkill -x picom; sleep 0.3; picom -b --config ~/.config/picom/picom.conf'
exec_always --no-startup-id ~/.config/polybar/launch.sh
exec_always --no-startup-id @KB_CMD@
exec --no-startup-id dunst
exec --no-startup-id nm-applet
exec --no-startup-id lxpolkit
exec --no-startup-id numlockx on
exec --no-startup-id xset s 600 600
exec --no-startup-id xss-lock --transfer-sleep-lock -- ~/.config/i3/scripts/lock.sh
exec --no-startup-id $term --class dropterm,dropterm

# ─── launchers ───────────────────────────────────────────────────────────
bindsym $mod+Return       exec --no-startup-id $term
bindsym $mod+Shift+Return exec --no-startup-id thunar
bindsym $mod+d            exec --no-startup-id rofi -show drun
bindsym $mod+Shift+d      exec --no-startup-id rofi -show run
bindsym $mod+Tab          exec --no-startup-id rofi -show window
bindsym $mod+Escape       exec --no-startup-id $rofi/powermenu.sh
bindsym $mod+Shift+e      exec --no-startup-id $rofi/powermenu.sh
bindsym $mod+x            exec --no-startup-id ~/.config/i3/scripts/lock.sh
bindsym $mod+slash        exec --no-startup-id ~/.config/i3/scripts/keys.sh
bindsym $mod+q            kill

# ─── vim navigation ──────────────────────────────────────────────────────
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right
bindsym $mod+Left  focus left
bindsym $mod+Down  focus down
bindsym $mod+Up    focus up
bindsym $mod+Right focus right

# move/swap tiled windows with their neighbour (floating windows nudge 10px)
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right
bindsym $mod+Shift+Left  move left
bindsym $mod+Shift+Down  move down
bindsym $mod+Shift+Up    move up
bindsym $mod+Shift+Right move right

# workspace prev/next (Ctrl) and carry window along (Ctrl+Shift)
bindsym $mod+Ctrl+h workspace prev_on_output
bindsym $mod+Ctrl+l workspace next_on_output
bindsym $mod+Ctrl+Shift+h move container to workspace prev_on_output; workspace prev_on_output
bindsym $mod+Ctrl+Shift+l move container to workspace next_on_output; workspace next_on_output
# n/p variants avoid Ctrl+Alt, which VMware uses to release input when $mod=Alt
bindsym $mod+n workspace next_on_output
bindsym $mod+p workspace prev_on_output
bindsym $mod+Shift+n move container to workspace next_on_output; workspace next_on_output
bindsym $mod+Shift+p move container to workspace prev_on_output; workspace prev_on_output
bindsym $mod+grave workspace back_and_forth
bindsym $mod+o move workspace to output next
bindsym $mod+Shift+o exec --no-startup-id ~/.config/i3/scripts/new-ws.sh

# vim-style marks:  $mod+m <letter> sets,  $mod+' <letter> jumps
bindsym $mod+m          exec --no-startup-id i3-input -F 'mark --toggle %s' -l 1 -P 'mark: '
bindsym $mod+apostrophe exec --no-startup-id i3-input -F '[con_mark="%s"] focus' -l 1 -P 'goto: '
# swap focused window with a marked one:  $mod+m a (on window A), then $mod+Shift+' a (on window B)
bindsym $mod+Shift+apostrophe exec --no-startup-id i3-input -F 'swap container with mark %s' -l 1 -P 'swap: '

# ─── layout ──────────────────────────────────────────────────────────────
bindsym $mod+b split h
bindsym $mod+v split v
bindsym $mod+e layout toggle split
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+f fullscreen toggle
bindsym $mod+space focus mode_toggle
bindsym $mod+Shift+space floating toggle
bindsym $mod+Shift+s sticky toggle
bindsym $mod+a focus parent
bindsym $mod+Shift+a focus child
bindsym $mod+g gaps inner current toggle 6

# scratchpad + drop-down terminal
bindsym $mod+Shift+minus move scratchpad
bindsym $mod+minus scratchpad show
bindsym $mod+u [instance="dropterm"] scratchpad show, move position center
for_window [instance="dropterm"] floating enable, resize set 1100 600, move scratchpad

# ─── workspaces ──────────────────────────────────────────────────────────
set $ws1 "1: @I_RUN@ term"
set $ws2 "2: @I_SSH@ web"
set $ws3 "3: @I_SHIELD@ burp"
set $ws4 "4: @I_FILE@ notes"
set $ws5 "5"
set $ws6 "6"
set $ws7 "7"
set $ws8 "8"
set $ws9 "9"
set $ws10 "10"
bindsym $mod+1 workspace number $ws1
bindsym $mod+2 workspace number $ws2
bindsym $mod+3 workspace number $ws3
bindsym $mod+4 workspace number $ws4
bindsym $mod+5 workspace number $ws5
bindsym $mod+6 workspace number $ws6
bindsym $mod+7 workspace number $ws7
bindsym $mod+8 workspace number $ws8
bindsym $mod+9 workspace number $ws9
bindsym $mod+0 workspace number $ws10
bindsym $mod+Shift+1 move container to workspace number $ws1
bindsym $mod+Shift+2 move container to workspace number $ws2
bindsym $mod+Shift+3 move container to workspace number $ws3
bindsym $mod+Shift+4 move container to workspace number $ws4
bindsym $mod+Shift+5 move container to workspace number $ws5
bindsym $mod+Shift+6 move container to workspace number $ws6
bindsym $mod+Shift+7 move container to workspace number $ws7
bindsym $mod+Shift+8 move container to workspace number $ws8
bindsym $mod+Shift+9 move container to workspace number $ws9
bindsym $mod+Shift+0 move container to workspace number $ws10

# ─── resize mode (hjkl, Shift = bigger steps) ────────────────────────────
mode "resize" {
    bindsym h resize shrink width 20 px or 2 ppt
    bindsym j resize grow height 20 px or 2 ppt
    bindsym k resize shrink height 20 px or 2 ppt
    bindsym l resize grow width 20 px or 2 ppt
    bindsym Shift+h resize shrink width 80 px or 8 ppt
    bindsym Shift+j resize grow height 80 px or 8 ppt
    bindsym Shift+k resize shrink height 80 px or 8 ppt
    bindsym Shift+l resize grow width 80 px or 8 ppt
    bindsym equal  exec --no-startup-id i3-msg '[con_id="__focused__"] resize set 50 ppt 50 ppt'
    bindsym Return mode "default"
    bindsym Escape mode "default"
    bindsym $mod+r mode "default"
}
bindsym $mod+r mode "resize"

# ─── media / screenshots ─────────────────────────────────────────────────
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute        exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle
bindsym XF86AudioMicMute     exec --no-startup-id pactl set-source-mute @DEFAULT_SOURCE@ toggle
bindsym XF86AudioPlay        exec --no-startup-id playerctl play-pause
bindsym XF86AudioNext        exec --no-startup-id playerctl next
bindsym XF86AudioPrev        exec --no-startup-id playerctl previous
bindsym XF86MonBrightnessUp   exec --no-startup-id brightnessctl set +5%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 5%-
bindsym Print       exec --no-startup-id flameshot gui
bindsym Shift+Print exec --no-startup-id flameshot full -c

# ─── session ─────────────────────────────────────────────────────────────
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart

# ─── window rules ────────────────────────────────────────────────────────
for_window [window_role="pop-up"]  floating enable
for_window [window_role="dialog"]  floating enable
for_window [window_type="dialog"]  floating enable
for_window [window_role="task_dialog"] floating enable
for_window [class="Pavucontrol"]   floating enable, resize set 820 520, move position center
for_window [class="Arandr"]        floating enable
for_window [class="Lxappearance"]  floating enable
for_window [class="Nm-connection-editor"] floating enable
for_window [class="(?i)burp" title="^(?!Burp Suite)"] floating enable
for_window [urgent="latest"] focus

# ─── add-ons (optional, survive config regeneration) ─────────────────
include ~/.config/i3-addons/*.conf
EOF

# Add-on dir lives outside ~/.config/i3 so backups/regeneration never touch it.
mkdir -p "$CFG/i3-addons"
[[ -f "$CFG/i3-addons/00-readme.conf" ]] || \
  echo '# Drop optional *.conf snippets here (e.g. wallhaven-addon.sh). Loaded by ~/.config/i3/config.' \
  > "$CFG/i3-addons/00-readme.conf"
if ! vge "$I3_VER" 4.20; then
  sed -i '/^include ~\/.config\/i3-addons/d' "$CFG/i3/config"; warn "i3 $I3_VER < 4.20: add-on include disabled."
fi

# Strip gaps directives on i3 < 4.22 (gaps were merged upstream in 4.22)
if ! vge "$I3_VER" 4.22; then
  sed -i '/gaps/d' "$CFG/i3/config"; warn "i3 $I3_VER < 4.22: gaps disabled."
fi
# VMware: clipboard sharing + auto-resize
# VMs: host-window auto-resize (+ VMware clipboard/drag-drop agent)
if [[ "$VIRT" != "none" ]]; then
  {
    echo ''
    echo '# ─── VM integration ──────────────────────────────────────────────────────'
    [[ "$VIRT" == "vmware" ]] && echo 'exec --no-startup-id vmware-user-suid-wrapper'
    echo 'exec_always --no-startup-id ~/.config/i3/scripts/vm-autoresize.sh'
  } >> "$CFG/i3/config"
fi

# Bare metal: automatic monitor layout + DPI; laptop extras
if [[ "$VIRT" == "none" ]]; then
  {
    echo ''
    echo '# ─── displays: native resolution @ max refresh, remembered layouts ────────'
    echo 'exec_always --no-startup-id ~/.config/i3/scripts/monitors.sh watch'
    echo 'bindsym $mod+Shift+m exec --no-startup-id ~/.config/i3/scripts/monitors.sh menu'
    echo 'bindsym XF86Display exec --no-startup-id ~/.config/i3/scripts/monitors.sh menu'
  } >> "$CFG/i3/config"
fi
if (( LAPTOP )); then
  {
    echo ''
    echo '# ─── laptop ──────────────────────────────────────────────────────────────'
    echo 'exec --no-startup-id ~/.config/i3/scripts/battery-notify.sh'
    echo 'exec --no-startup-id blueman-applet'
    echo "bindsym XF86KbdBrightnessUp exec --no-startup-id brightnessctl --device='*::kbd_backlight' set +33%"
    echo "bindsym XF86KbdBrightnessDown exec --no-startup-id brightnessctl --device='*::kbd_backlight' set 33%-"
  } >> "$CFG/i3/config"
  render > "$CFG/i3/scripts/battery-notify.sh" <<'EOF'
#!/usr/bin/env bash
# Low-battery alerts: 15% warning, 5% critical. One per i3 session; exits with X.
B="/sys/class/power_supply/@BAT@"; warned=0
while xrandr --current >/dev/null 2>&1; do
  cap="$(cat "$B/capacity" 2>/dev/null || echo 100)"; st="$(cat "$B/status" 2>/dev/null)"
  if [[ "$st" == "Discharging" ]]; then
    if (( cap <= 5 && warned < 2 )); then
      notify-send -u critical "Battery ${cap}%" "Plug in now"; warned=2
    elif (( cap <= 15 && warned < 1 )); then
      notify-send "Battery ${cap}%" "Running low"; warned=1
    fi
  else warned=0; fi
  sleep 60
done
EOF
fi

cat > "$CFG/i3/scripts/monitors.sh" <<'MONITORS'
#!/usr/bin/env bash
# monitors.sh — automatic multi-monitor layout for i3-neon (laptops / desktops)
#   monitors.sh auto    apply the remembered layout for the connected monitors (or the default)
#   monitors.sh watch   re-run auto on plug/unplug and lid open/close (started by i3)
#   monitors.sh menu    rofi menu: choose a layout; remembered for these exact monitors
#   monitors.sh info    print what was detected
# Every monitor gets its native resolution at the highest refresh rate it offers.
set -uo pipefail

CONF_DIR="$HOME/.config/i3-neon"
SETTINGS="$CONF_DIR/monitors.conf"
PROFILES="$CONF_DIR/monitor-profiles"
PIDF="${XDG_RUNTIME_DIR:-/tmp}/i3-neon-monitors.$UID.pid"
LID_GLOB="${LID_GLOB:-/proc/acpi/button/lid/*/state}"
DRY_RUN="${DRY_RUN:-0}"

# ---- settings (override in ~/.config/i3-neon/monitors.conf) ----
DEFAULT_LAYOUT="right"       # right | left | above | external | mirror | laptop
LID_CLOSED_LAYOUT="external" # used when the lid is shut and an external monitor is connected
MAX_RATE=0                   # cap refresh rate in Hz (0 = no cap)
DPI=""                       # force a DPI (96, 120, 144, 192 ...); empty = auto from main display
mkdir -p "$CONF_DIR"; touch "$PROFILES"
if [[ ! -f "$SETTINGS" ]]; then
  cat > "$SETTINGS" <<'EOF'
# i3-neon monitor settings (sourced as bash)
# Layout for monitors you have not chosen a layout for yet:
#   right | left | above | external | mirror | laptop
DEFAULT_LAYOUT="right"
# When the lid is closed and an external monitor is connected:
LID_CLOSED_LAYOUT="external"
# Cap the refresh rate in Hz (0 = use the highest available)
MAX_RATE=0
# Force a DPI for text scaling (e.g. 96, 120, 144, 192). Empty = automatic.
DPI=""
EOF
fi
# shellcheck source=/dev/null
source "$SETTINGS"

notify() { [[ "$DRY_RUN" == 1 ]] || notify-send -a monitors "$@" 2>/dev/null || true; }
is_internal() { [[ "$1" =~ ^(eDP|LVDS|DSI) ]]; }
lid_closed() {
  local f
  for f in $LID_GLOB; do [[ -f "$f" ]] && grep -q closed "$f" && return 0; done
  return 1
}

# ------------------------------------------------------------------ scan ---
# OUTS: connected outputs · DISC: disconnected outputs still holding a mode
# BEST[o]=WxH (native)  RATE[o]=Hz (max at native)  MMW/MMH[o]=size in mm  EDID[o]=md5
scan() {
  OUTS=(); DISC=()
  declare -gA BEST=() RATE=() MMW=() MMH=() EDID=()
  local line cur="" in_edid=0 edid="" res rest tok prev pref_res="" max_area=0 area
  local -A rates_of=()
  _finish() {
    [[ -n "$cur" ]] || return 0
    EDID[$cur]="$( [[ -n "$edid" ]] && md5sum <<<"$edid" | cut -c1-12 || echo none)"
    local r="$pref_res" best_rate=0 x
    [[ -n "$r" ]] || r="$max_res"
    for x in ${rates_of[$r]:-}; do
      if (( MAX_RATE > 0 )) && awk -v a="$x" -v m="$MAX_RATE" 'BEGIN{exit !(a > m + 0.5)}'; then continue; fi
      awk -v a="$x" -v b="$best_rate" 'BEGIN{exit !(a > b)}' && best_rate="$x"
    done
    BEST[$cur]="$r"; RATE[$cur]="$best_rate"
  }
  local max_res=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^([A-Za-z0-9_-]+)\ (connected|disconnected) ]]; then
      _finish
      cur=""; in_edid=0; edid=""; pref_res=""; max_res=""; max_area=0; rates_of=()
      if [[ "${BASH_REMATCH[2]}" == "connected" ]]; then
        cur="${BASH_REMATCH[1]}"; OUTS+=("$cur")
        if [[ "$line" =~ \ ([0-9]+)mm\ x\ ([0-9]+)mm ]]; then
          MMW[$cur]="${BASH_REMATCH[1]}"; MMH[$cur]="${BASH_REMATCH[2]}"
        else MMW[$cur]=0; MMH[$cur]=0; fi
      elif [[ "$line" =~ disconnected\ (primary\ )?[0-9]+x[0-9]+\+ ]]; then
        DISC+=("${line%% *}")
      fi
    elif [[ -z "$cur" ]]; then
      continue
    elif [[ "$line" =~ ^[[:space:]]+EDID: ]]; then
      in_edid=1
    elif (( in_edid )) && [[ "$line" =~ ^[[:space:]]+[0-9a-f]+$ ]]; then
      edid+="${line//[[:space:]]/}"
    elif [[ "$line" =~ ^\ \ \ ([0-9]+)x([0-9]+)\ +(.*)$ ]]; then   # mode line (interlaced "i" modes don't match)
      in_edid=0
      res="${BASH_REMATCH[1]}x${BASH_REMATCH[2]}"; rest="${BASH_REMATCH[3]}"
      area=$(( BASH_REMATCH[1] * BASH_REMATCH[2] ))
      (( area > max_area )) && { max_area=$area; max_res="$res"; }
      prev=""
      for tok in $rest; do
        if [[ "$tok" == "+" ]]; then pref_res="$res"; continue; fi
        [[ "$tok" == *+* ]] && pref_res="$res"
        tok="${tok//[*+]/}"
        [[ "$tok" =~ ^[0-9]+(\.[0-9]+)?$ ]] && rates_of[$res]+="$tok " && prev="$tok"
      done
    else
      in_edid=0
    fi
  done < <(xrandr --current --prop 2>/dev/null)
  _finish
}

ratio_name() {  # $1=WxH -> "16:9"
  awk -v r="$1" 'BEGIN{
    split(r, a, "x"); if (a[2] == 0) { print "?"; exit }
    v = a[1] / a[2]
    n = split("4:3 1.3333 5:4 1.25 3:2 1.5 16:10 1.6 16:9 1.7778 21:9 2.3704 32:9 3.5556", t, " ")
    best = ""; bd = 1
    for (i = 1; i < n; i += 2) { d = v - t[i+1]; if (d < 0) d = -d; if (d < bd) { bd = d; best = t[i] } }
    if (bd < 0.04) print best; else printf "%.2f:1\n", v }'
}

dpi_for() {  # $1=output -> snapped DPI
  local o="$1" w="${BEST[$1]%x*}"
  [[ -n "$DPI" ]] && { echo "$DPI"; return; }
  (( ${MMW[$o]:-0} > 0 )) || { echo 96; return; }
  awk -v px="$w" -v mm="${MMW[$o]}" 'BEGIN{
    d = px / (mm / 25.4)
    if (d < 115) print 96; else if (d < 140) print 120; else if (d < 165) print 144;
    else if (d < 190) print 168; else print 192 }'
}

describe() {  # $1=output
  local o="$1" diag=""
  if (( ${MMW[$o]:-0} > 0 )); then
    diag="$(awk -v w="${MMW[$o]}" -v h="${MMH[$o]}" 'BEGIN{printf " %.1f\"", sqrt(w*w+h*h)/25.4}')"
  fi
  printf '%s  %s @ %.0fHz  %s%s\n' "$o" "${BEST[$o]}" "${RATE[$o]}" "$(ratio_name "${BEST[$o]}")" "$diag"
}

profile_key() {  # identifies the set of external monitors (by EDID)
  local o parts=()
  for o in "${OUTS[@]}"; do is_internal "$o" || parts+=("$o=${EDID[$o]}"); done
  (( ${#parts[@]} )) || { echo "none"; return; }
  printf '%s\n' "${parts[@]}" | sort | md5sum | cut -c1-12
}
saved_layout() { awk -v k="$1" '$1 == k {print $2}' "$PROFILES" | tail -1; }
save_layout()  { local t; t="$(grep -v "^$1 " "$PROFILES")"; { [[ -n "$t" ]] && printf '%s\n' "$t"; echo "$1 $2"; } > "$PROFILES"; }
signature()    { scan; echo "$(profile_key)|$(lid_closed && echo closed || echo open)|${OUTS[*]}"; }

# ----------------------------------------------------------------- apply ---
apply() {  # $1=layout
  local layout="$1" int="" o prev="" main="" dpi
  local -a ext=() cmd=(xrandr)
  for o in "${OUTS[@]}"; do if is_internal "$o"; then int="$o"; else ext+=("$o"); fi; done
  (( ${#OUTS[@]} )) || return 0
  for o in "${DISC[@]}"; do cmd+=(--output "$o" --off); done

  if (( ${#ext[@]} == 0 )); then layout="laptop"
  elif [[ -z "$int" ]]; then layout="external"
  elif lid_closed; then layout="$LID_CLOSED_LAYOUT"; fi
  [[ -z "$int" && "$layout" == "laptop" ]] && layout="external"

  m() { cmd+=(--output "$1" --mode "${BEST[$1]}" --rate "${RATE[$1]}"); }
  case "$layout" in
    laptop)
      m "$int"; cmd+=(--pos 0x0 --primary); main="$int"
      for o in "${ext[@]}"; do cmd+=(--output "$o" --off); done ;;
    external)
      [[ -n "$int" ]] && cmd+=(--output "$int" --off)
      for o in "${ext[@]}"; do
        m "$o"
        if [[ -z "$prev" ]]; then cmd+=(--pos 0x0 --primary); main="$o"; else cmd+=(--right-of "$prev"); fi
        prev="$o"
      done ;;
    mirror)
      main="${ext[0]}"; m "$main"; cmd+=(--pos 0x0 --primary)
      for o in "${ext[@]:1}" "$int"; do
        m "$o"; cmd+=(--same-as "$main" --scale-from "${BEST[$main]}")
      done ;;
    right|left|above|*)
      local rel="--right-of"
      [[ "$layout" == "left" ]] && rel="--left-of"
      [[ "$layout" == "above" ]] && rel="--above"
      m "$int"; cmd+=(--pos 0x0); prev="$int"; main="${ext[0]}"
      for o in "${ext[@]}"; do
        m "$o"; cmd+=("$rel" "$prev"); [[ "$o" == "$main" ]] && cmd+=(--primary)
        [[ "$layout" == "above" ]] || prev="$o"
      done ;;
  esac

  dpi="$(dpi_for "$main")"
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "${cmd[*]}"; echo "DPI $dpi (main: $main, layout: $layout)"; return 0
  fi
  "${cmd[@]}" || { notify -u critical "monitors" "xrandr failed: ${cmd[*]}"; return 1; }
  xrdb -merge <<<"Xft.dpi: $dpi"
  "$HOME/.config/i3/scripts/wallpaper.sh" >/dev/null 2>&1 &
  "$HOME/.config/polybar/launch.sh" >/dev/null 2>&1
  local d; d="$(for o in "${OUTS[@]}"; do [[ "$layout" == "laptop" && "$o" != "$int" ]] && continue
                 [[ "$layout" == "external" && "$o" == "$int" ]] && continue; describe "$o"; done)"
  notify "Display: $layout" "$d"
}

auto() {
  scan
  local key layout
  key="$(profile_key)"
  layout="$(saved_layout "$key")"
  apply "${layout:-$DEFAULT_LAYOUT}"
}

# ----------------------------------------------------------------- watch ---
watch() {  # single instance; reacts to DRM hotplug (udev) and lid changes; exits with X
  local old; old="$(cat "$PIDF" 2>/dev/null)"
  if [[ "$old" =~ ^[0-9]+$ ]] && tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null | grep -q "monitors.sh watch"; then
    exit 0
  fi
  echo "$$" > "$PIDF"
  local sig last line
  auto; last="$(signature)"
  exec 3< <(exec udevadm monitor --udev --subsystem-match=drm 2>/dev/null)
  while :; do
    if read -r -t 2 line <&3; then
      [[ "$line" == *change* ]] || continue
      while read -r -t 1 line <&3; do :; done     # let a burst of events settle
      xrandr --query >/dev/null 2>&1              # one probe, only on real hotplug events
    fi
    xrandr --current >/dev/null 2>&1 || exit 0    # X session ended
    sig="$(signature)"
    if [[ "$sig" != "$last" ]]; then auto; last="$(signature)"; fi
  done
}

# ------------------------------------------------------------------ menu ---
menu() {
  xrandr --query >/dev/null 2>&1
  scan
  local key cur mesg choice layout o
  key="$(profile_key)"; cur="$(saved_layout "$key")"
  mesg="$(for o in "${OUTS[@]}"; do describe "$o"; done)"
  choice="$(printf '%s\n' "detect / re-apply" "extend right" "extend left" "extend above" \
            "external only" "mirror" "laptop only" \
           | rofi -dmenu -i -no-custom -p "display${cur:+ ($cur)}" -mesg "$mesg" \
               -theme-str 'window {width: 560px;} listview {lines: 7;}')" || return 0
  case "$choice" in
    "detect"*)       auto; return ;;
    "extend right")  layout=right ;;
    "extend left")   layout=left ;;
    "extend above")  layout=above ;;
    "external only") layout=external ;;
    "mirror")        layout=mirror ;;
    "laptop only")   layout=laptop ;;
    *)               return 0 ;;
  esac
  [[ "$key" != "none" ]] && save_layout "$key" "$layout"
  apply "$layout"
}

info() { scan; for o in "${OUTS[@]}"; do describe "$o"; done; echo "lid: $(lid_closed && echo closed || echo open)"; echo "profile: $(profile_key) -> $(saved_layout "$(profile_key)")"; }

case "${1:-auto}" in
  auto)  auto ;;
  watch) watch ;;
  menu)  menu ;;
  info)  info ;;
  *)     sed -n '2,7p' "$0"; exit 1 ;;
esac
MONITORS

cat > "$CFG/i3/scripts/vm-autoresize.sh" <<'EOF'
#!/usr/bin/env bash
# Applies the size the hypervisor requests (the "preferred" xrandr mode) whenever the
# VM window is resized, then redraws polybar + wallpaper. XFCE did this via xfsettingsd;
# bare i3 does not. Only acts when preferred != current, so it can't loop on its own events.
exec 9>"/tmp/vm-autoresize.$UID.lock"
flock -n 9 || exit 0                       # one instance only (survives i3 restarts)

apply() {
  local changed=0 out
  while read -r out; do
    # In the output's mode list: '*' = current mode, '+' = preferred mode
    if ! xrandr --current | awk -v o="$out" '
         $1==o {f=1; next} /^[^ ]/ {f=0}
         f && /\+/ && /\*/ {ok=1} END {exit !ok}'; then
      xrandr --output "$out" --auto && changed=1
    fi
  done < <(xrandr --current | awk '/ connected/{print $1}')
  if [[ $changed -eq 1 ]]; then
    ~/.config/i3/scripts/wallpaper.sh &
    ~/.config/polybar/launch.sh
  fi
}

apply
if command -v xev >/dev/null; then
  # React to RandR events; drain bursts (window dragging) for 1s before applying
  xev -root -event randr | grep --line-buffered -E 'XRROutputChangeNotify|RRScreenChangeNotify' |
  while read -r _; do
    while read -r -t 1 _; do :; done
    apply
  done
else
  while sleep 2; do apply; done            # fallback: cheap poll (no reprobe, --current)
fi
EOF

# ---------------------------------------------------------- i3 helper scripts
cat > "$CFG/i3/scripts/lock.sh" <<'EOF'
#!/usr/bin/env bash
# Pause notifications while locked so nothing leaks onto the lock screen
command -v dunstctl >/dev/null && dunstctl set-paused true
i3lock -n -e -f -c 000000
command -v dunstctl >/dev/null && dunstctl set-paused false
EOF

render > "$CFG/i3/scripts/wallpaper.sh" <<'EOF'
#!/usr/bin/env bash
# Drop an image at ~/.config/wallpaper (png/jpg) to use it; otherwise solid black.
for f in ~/.config/wallpaper ~/.config/wallpaper.{png,jpg,jpeg}; do
  [[ -f "$f" ]] && exec feh --no-fehbg --bg-fill "$f"
done
xsetroot -solid "@BG@"
EOF

cat > "$CFG/i3/scripts/new-ws.sh" <<'EOF'
#!/usr/bin/env bash
# Move the focused window to the lowest-numbered empty workspace and follow it
used=$(i3-msg -t get_workspaces | grep -o '"num":[0-9]*' | cut -d: -f2 | sort -n)
n=1; while grep -qx "$n" <<<"$used"; do n=$((n+1)); done
i3-msg "move container to workspace number $n; workspace number $n" >/dev/null
EOF

render > "$CFG/i3/scripts/keys.sh" <<'EOF'
#!/usr/bin/env bash
# Searchable cheat sheet of every bindsym in the i3 config
grep -E '^\s*bindsym' ~/.config/i3/config \
  | sed -E 's/^\s*bindsym\s+//; s/\$mod/MOD/g; s/--no-startup-id //; s/exec //' \
  | awk '{k=$1; $1=""; printf "%-28s %s\n", k, $0}' \
  | rofi -dmenu -i -p "@I_KEY@ keys" -theme-str 'window {width: 900px;} listview {lines: 16;}' >/dev/null
EOF

# ================================================================ polybar ===
log "Writing polybar config..."
render > "$CFG/polybar/config.ini" <<'EOF'
; Flat text bar: solid block for the focused workspace, bold labels, grey details, dim pipes.
[colors]
bg     = @BG@
fg     = @TXT@
grey   = @GREY@
sep    = @SEP@
blue   = @BLUE@
purple = @PURPLE@
urgent = @URGENT@

[bar/main]
monitor = ${env:MONITOR:}
width = 100%
height = @BAR_HEIGHT@
@BAR_DPI@
background = ${colors.bg}
foreground = ${colors.fg}
line-size = 0
border-size = 0
padding-left = 0
padding-right = 1
module-margin = 0
separator = " | "
separator-foreground = ${colors.sep}
font-0 = "@FONT@:size=10;2"
font-1 = "@FONT@:style=Bold:size=10;2"
modules-left = i3 xwindow
modules-right = @MODULES_RIGHT@@TRAY_MODULE@
@TRAY_LEGACY@
tray-background = ${colors.bg}
cursor-click = pointer
enable-ipc = true
wm-restack = i3
override-redirect = false

[module/i3]
type = internal/i3
pin-workspaces = true
index-sort = true
enable-scroll = false
format = <label-state><label-mode>
label-focused = %name%
label-focused-background = ${colors.blue}
label-focused-foreground = ${colors.bg}
label-focused-font = 2
label-focused-padding = 1
label-unfocused = %name%
label-unfocused-foreground = ${colors.grey}
label-unfocused-padding = 1
label-visible = %name%
label-visible-foreground = ${colors.purple}
label-visible-padding = 1
label-urgent = %name%
label-urgent-background = ${colors.urgent}
label-urgent-foreground = ${colors.bg}
label-urgent-font = 2
label-urgent-padding = 1
label-mode = %mode%
label-mode-background = ${colors.purple}
label-mode-foreground = ${colors.bg}
label-mode-font = 2
label-mode-padding = 1

[module/xwindow]
type = internal/xwindow
label = %title:0:70:...%
label-empty =

[module/fs]
type = internal/fs
mount-0 = /
interval = 30
label-mounted = %mountpoint% %percentage_used%%
label-mounted-font = 2

[module/memory]
type = internal/memory
interval = 3
label = RAM %percentage_used%%
label-font = 2

[module/cpu]
type = internal/cpu
interval = 2
label = CPU %percentage:2%%
label-font = 2

[module/net]
type = internal/network
interface = @IFACE@
interval = 2
label-connected = %{T2}%ifname%%{T-} %{F@GREY@}%local_ip% %downspeed% %upspeed%%{F-}
label-disconnected = %{T2}%ifname%%{T-} %{F@GREY@}down%{F-}

[module/vpn]
type = custom/script
exec = ~/.config/polybar/scripts/vpn.sh
click-left = ~/.config/polybar/scripts/vpn.sh --copy
interval = 3

[module/date]
type = internal/date
interval = 1
time = %H:%M
time-alt = %a %d %b  %H:%M:%S
label = %time%
label-font = 2

; not shown by default — add "pulseaudio" to modules-right if you want it
[module/pulseaudio]
type = internal/pulseaudio
label-volume = VOL %percentage%%
label-volume-font = 2
label-muted = VOL muted
label-muted-foreground = ${colors.grey}
click-right = pavucontrol &

[module/tray]
type = internal/tray
tray-spacing = 6px
tray-background = ${colors.bg}
EOF

if (( LAPTOP )); then
  # Wired port: detect any wired interface, and hide the module while unplugged
  sed -i -e 's/^interface = .*/interface-type = wired/' \
         -e 's/^label-disconnected = %{T2}%ifname%.*/label-disconnected =/' "$CFG/polybar/config.ini"
  render >> "$CFG/polybar/config.ini" <<'EOF'

[module/wifi]
type = internal/network
interface-type = wireless
interval = 3
label-connected = %{T2}wifi%{T-} %{F@GREY@}%essid% %signal%%%{F-}
label-disconnected = %{T2}wifi%{T-} %{F@GREY@}off%{F-}

[module/battery]
type = internal/battery
battery = @BAT@
adapter = @ADP@
full-at = 99
low-at = 15
poll-interval = 5
time-format = %H:%M
label-charging = %{T2}BAT%{T-} %{F@BLUE@}+%percentage%%%{F-}
label-discharging = %{T2}BAT%{T-} %percentage%% %{F@GREY@}%time%%{F-}
label-full = %{T2}BAT%{T-} full
format-low = <label-low>
label-low = %{T2}%{F@URGENT@}BAT %percentage%%%{F-}%{T-}

[module/backlight]
type = internal/backlight
card = @BACKLIGHT@
use-actual-brightness = true
enable-scroll = true
label = %{T2}BRI%{T-} %percentage%%
EOF
fi

cat > "$CFG/polybar/launch.sh" <<'EOF'
#!/usr/bin/env bash
killall -q polybar
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 0.2; done
if command -v xrandr >/dev/null; then
  for m in $(xrandr --query | awk '/ connected/{print $1}'); do
    MONITOR="$m" polybar --reload main >>"/tmp/polybar-$m.log" 2>&1 & disown
  done
else
  polybar --reload main >>/tmp/polybar.log 2>&1 & disown
fi
EOF

render > "$CFG/polybar/scripts/vpn.sh" <<'EOF'
#!/usr/bin/env bash
# Shows the first tun*/wg* IPv4 (HTB/THM/OSCP labs). Click copies it.
ip4="$(ip -4 -o addr show 2>/dev/null | awk '$2 ~ /^(tun|wg)/ {split($4,a,"/"); print a[1]; exit}')"
if [[ "${1:-}" == "--copy" ]]; then
  [[ -n "$ip4" ]] && printf '%s' "$ip4" | xclip -selection clipboard && notify-send "VPN IP copied" "$ip4"
  exit 0
fi
# Prints nothing when disconnected, so the module (and its separator) disappears
[[ -n "$ip4" ]] && echo "%{T2}%{F@PURPLE@}VPN%{F-}%{T-} %{F@GREY@}$ip4%{F-}"
exit 0
EOF

# =================================================================== rofi ===
log "Writing rofi config..."
render > "$CFG/rofi/config.rasi" <<'EOF'
configuration {
  modi: "drun,run,window,ssh";
  show-icons: true;
  terminal: "@TERM@";
  drun-display-format: "{name}";
  display-drun: "@I_APPS@ apps";
  display-run: "@I_RUN@ run";
  display-window: "@I_WIN@ win";
  display-ssh: "@I_SSH@ ssh";
  /* vim-ish: Ctrl+j/k move, Ctrl+h/l switch mode */
  kb-row-up: "Up,Control+k";
  kb-row-down: "Down,Control+j";
  kb-accept-entry: "Return,KP_Enter";
  kb-remove-to-eol: "";
  kb-remove-char-back: "BackSpace,Shift+BackSpace";
  kb-mode-complete: "";
  kb-mode-previous: "Shift+Left,Control+h";
  kb-mode-next: "Shift+Right,Control+l";
}
@theme "@HOME@/.config/rofi/neon.rasi"
EOF

render > "$CFG/rofi/neon.rasi" <<'EOF'
* {
  bg:     @BG@;
  bg-alt: @BG_ALT@;
  fg:     @FG@;
  dim:    @DIM@;
  blue:   @BLUE@;
  purple: @PURPLE@;
  urgent: @URGENT@;
  background-color: transparent;
  text-color: @fg;
  font: "@FONT@ 11";
}
window {
  width: 640px;
  background-color: @bg;
  border: 2px;
  border-color: @blue;
  border-radius: 0;
}
mainbox  { children: [ inputbar, message, listview ]; spacing: 0; }
inputbar {
  children: [ prompt, entry ];
  padding: 12px;
  spacing: 10px;
  background-color: @bg-alt;
  border: 0 0 1px 0;
  border-color: @purple;
}
prompt   { background-color: @purple; text-color: @bg; padding: 0 6px; }
entry    { placeholder: "search..."; placeholder-color: @dim; cursor: text; }
message  { padding: 8px 12px; }
textbox  { text-color: @fg; }
listview { lines: 8; columns: 1; fixed-height: true; scrollbar: false; padding: 8px; spacing: 4px; }
element  { padding: 6px 10px; spacing: 10px; border-radius: 0; }
element selected.normal { background-color: @blue; text-color: @bg; }
element normal.active   { text-color: @purple; }
element selected.active { background-color: @purple; text-color: @bg; }
element normal.urgent,  element selected.urgent { text-color: @urgent; }
element-icon { size: 1.2em; }
element-text { text-color: inherit; vertical-align: 0.5; }
EOF

render > "$CFG/rofi/powermenu.sh" <<'EOF'
#!/usr/bin/env bash
confirm() { [[ "$(printf 'no\nyes' | rofi -dmenu -i -p "$1?" -theme-str 'window {width: 220px;} listview {lines: 2;}')" == "yes" ]]; }
choice="$(printf '%s\n' "@I_LOCK@  lock" "@I_SLEEP@  sleep" "@I_LOGOUT@  logout" "@I_REBOOT@  reboot" "@I_POWER@  shutdown" \
  | rofi -dmenu -i -p "@I_POWER@ power" -theme-str 'window {width: 260px;} listview {lines: 5;}')"
case "$choice" in
  *lock)     ~/.config/i3/scripts/lock.sh ;;
  *sleep)    systemctl suspend ;;
  *logout)   confirm logout   && i3-msg exit ;;
  *reboot)   confirm reboot   && systemctl reboot ;;
  *shutdown) confirm shutdown && systemctl poweroff ;;
esac
EOF

# ================================================================== picom ===
log "Writing picom config..."
render > "$CFG/picom/picom.conf" <<'EOF'
# Minimal: no fades, no shadows, no blur, no transparency. Only tear-free compositing.
backend = "@PICOM_BACKEND@";
vsync = true;
use-damage = true;
fading = false;
shadow = false;
inactive-opacity = 1.0;
active-opacity = 1.0;
frame-opacity = 1.0;
detect-rounded-corners = true;
detect-client-opacity = true;
detect-transient = true;
unredir-if-possible = false;
EOF

# ================================================================== dunst ===
render > "$CFG/dunst/dunstrc" <<'EOF'
[global]
    monitor = 0
    follow = mouse
    width = 320
    height = 120
    origin = top-right
    offset = 12x36
    frame_width = 2
    frame_color = "@BLUE@"
    separator_color = frame
    corner_radius = 0
    padding = 10
    horizontal_padding = 12
    font = @FONT@ 10
    format = "<b>%s</b>\n%b"
    icon_position = left
    max_icon_size = 32
    mouse_left_click = close_current
    mouse_right_click = close_all

[urgency_low]
    background = "@BG@"
    foreground = "@DIM@"
    frame_color = "@BG_ALT@"
    timeout = 4

[urgency_normal]
    background = "@BG@"
    foreground = "@FG@"
    frame_color = "@PURPLE@"
    timeout = 6

[urgency_critical]
    background = "@BG@"
    foreground = "@FG@"
    frame_color = "@URGENT@"
    timeout = 0
EOF

# ============================================================== alacritty ===
render > "$CFG/alacritty/alacritty.toml" <<'EOF'
[window]
padding = { x = 8, y = 6 }
opacity = 1.0
dynamic_title = true

[font]
normal = { family = "@FONT@", style = "Regular" }
size = 10.5

[cursor]
style = { shape = "Block", blinking = "Off" }

[selection]
save_to_clipboard = true

[colors.primary]
background = "@BG@"
foreground = "@FG@"

[colors.cursor]
text = "@BG@"
cursor = "@BLUE@"

[colors.selection]
background = "@PURPLE@"
text = "@BG@"

[colors.normal]
black   = "#1a1a24"
red     = "@URGENT@"
green   = "@GREEN@"
yellow  = "#f3e600"
blue    = "#2f7bff"
magenta = "@PURPLE@"
cyan    = "@BLUE@"
white   = "@FG@"

[colors.bright]
black   = "@DIM@"
red     = "#ff5c8a"
green   = "#7dff5c"
yellow  = "#fff35c"
blue    = "#5c9dff"
magenta = "#c95cff"
cyan    = "#5ce6ff"
white   = "#ffffff"
EOF
vge "$AL_VER" 0.13.0 || warn "alacritty $AL_VER < 0.13 does not read TOML; upgrade or convert the config."

# ======================================================= GTK dark + env vars ==
GTK_THEME="Adwaita-dark"; ICONS="Adwaita"
[[ -d /usr/share/themes/Kali-Dark ]] && GTK_THEME="Kali-Dark"
[[ -d /usr/share/icons/Flat-Remix-Blue-Dark ]] && ICONS="Flat-Remix-Blue-Dark"
[[ "$ICONS" == "Adwaita" && -d /usr/share/icons/Papirus-Dark ]] && ICONS="Papirus-Dark"
cat > "$CFG/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=$GTK_THEME
gtk-icon-theme-name=$ICONS
gtk-font-name=Sans 10
gtk-application-prefer-dark-theme=1
gtk-enable-animations=0
EOF
sed -i "s|^  show-icons: true;|  show-icons: true;\n  icon-theme: \"$ICONS\";|" "$CFG/rofi/config.rasi"

log "Writing GTK3/GTK4 colour overrides..."
render > "$CFG/gtk-3.0/gtk.css" <<'EOF'
/* i3-neon — GTK3 colour overrides: pure black + neon accent blocks, square corners.
   Layered on top of the selected GTK theme. Accent colours are rewritten by the
   wallhaven add-on when "palette: follow wallpaper" is on. Restart an app to see changes. */

@define-color neon_bg      @BG@;
@define-color neon_surface #0b0b10;
@define-color neon_hover   #16161e;
@define-color neon_border  #1f1f29;
@define-color neon_fg      @TXT@;
@define-color neon_dim     @GREY@;
@define-color neon_accent  @BLUE@;
@define-color neon_accent2 @PURPLE@;
@define-color neon_urgent  @URGENT@;

/* Named colours that themes and apps read */
@define-color theme_bg_color @neon_bg;
@define-color theme_fg_color @neon_fg;
@define-color theme_base_color @neon_bg;
@define-color theme_text_color @neon_fg;
@define-color theme_selected_bg_color @neon_accent;
@define-color theme_selected_fg_color @neon_bg;
@define-color theme_unfocused_bg_color @neon_bg;
@define-color theme_unfocused_fg_color @neon_fg;
@define-color theme_unfocused_base_color @neon_bg;
@define-color theme_unfocused_text_color @neon_fg;
@define-color theme_unfocused_selected_bg_color @neon_accent;
@define-color theme_unfocused_selected_fg_color @neon_bg;
@define-color insensitive_bg_color @neon_bg;
@define-color insensitive_fg_color @neon_dim;
@define-color insensitive_base_color @neon_bg;
@define-color borders @neon_border;
@define-color unfocused_borders @neon_border;
@define-color error_color @neon_urgent;

/* ── surfaces ─────────────────────────────────────────────────────── */
window, .background, dialog, popover, popover.background, menu, .menu, .context-menu,
menubar, headerbar, .titlebar, toolbar, .toolbar, .inline-toolbar, notebook,
notebook > header, notebook > stack, scrolledwindow, viewport, paned, statusbar,
actionbar, searchbar, .sidebar, placessidebar, stacksidebar, list, row, .view,
treeview.view, iconview, textview, textview text, filechooser {
  background-color: @neon_bg;
  background-image: none;
  color: @neon_fg;
}
window.csd, decoration, headerbar, .titlebar, menu, .menu, .context-menu, popover {
  border-radius: 0;
  box-shadow: none;
}
headerbar, .titlebar { border-bottom: 1px solid @neon_border; }
menu, .menu, .context-menu, popover { border: 1px solid @neon_border; }
separator { background-color: @neon_border; }

/* ── entries ──────────────────────────────────────────────────────── */
entry, spinbutton {
  background-color: @neon_surface;
  background-image: none;
  color: @neon_fg;
  border: 1px solid @neon_border;
  border-radius: 0;
  box-shadow: none;
  caret-color: @neon_accent;
}
entry:focus, spinbutton:focus { border-color: @neon_accent; }
entry image { color: @neon_dim; }

/* ── buttons ──────────────────────────────────────────────────────── */
button {
  background-color: @neon_surface;
  background-image: none;
  color: @neon_fg;
  border: 1px solid @neon_border;
  border-radius: 0;
  box-shadow: none;
  text-shadow: none;
  -gtk-icon-shadow: none;
}
button.flat, headerbar button, toolbar button {
  background-color: transparent;
  border-color: transparent;
}
button:hover, button.flat:hover, headerbar button:hover, toolbar button:hover {
  background-color: @neon_hover;
}
button:checked, button:active, button.suggested-action {
  background-color: @neon_accent;
  border-color: @neon_accent;
  color: @neon_bg;
}
button.destructive-action, button.titlebutton.close:hover {
  background-color: @neon_urgent;
  border-color: @neon_urgent;
  color: @neon_bg;
}
button:disabled { background-color: @neon_bg; color: @neon_dim; }
treeview.view header button {
  background-color: @neon_bg;
  border-color: @neon_border;
  color: @neon_dim;
}

/* ── menus ────────────────────────────────────────────────────────── */
menuitem, modelbutton { color: @neon_fg; background-color: transparent; }
menuitem:hover, menubar > menuitem:hover, modelbutton.flat:hover, .menuitem:hover {
  background-color: @neon_accent;
  color: @neon_bg;
}
menuitem:hover label, menuitem:hover accelerator, modelbutton.flat:hover label { color: @neon_bg; }
menuitem:disabled, menuitem:disabled label { color: @neon_dim; }

/* ── lists & selection (hover first, selected wins) ──────────────── */
row:hover, treeview.view:hover { background-color: @neon_hover; }
*:selected, .view:selected, treeview.view:selected, iconview:selected, row:selected,
flowboxchild:selected, placessidebar row:selected, row:selected:hover {
  background-color: @neon_accent;
  color: @neon_bg;
}
row:selected label, row:selected image { color: @neon_bg; }
selection, entry selection, textview text selection, label selection {
  background-color: @neon_accent2;
  color: @neon_bg;
}

/* ── checks, radios, switches ─────────────────────────────────────── */
check, radio {
  background-color: @neon_surface;
  background-image: none;
  border: 1px solid @neon_border;
  box-shadow: none;
  color: @neon_bg;
}
check:checked, radio:checked, check:indeterminate, radio:indeterminate {
  background-color: @neon_accent;
  border-color: @neon_accent;
  color: @neon_bg;
}
switch {
  background-color: @neon_surface;
  background-image: none;
  border: 1px solid @neon_border;
  border-radius: 0;
  color: @neon_dim;
}
switch:checked { background-color: @neon_accent; border-color: @neon_accent; color: @neon_bg; }
switch slider {
  background-color: @neon_fg;
  background-image: none;
  border: none;
  border-radius: 0;
  box-shadow: none;
}
switch:checked slider { background-color: @neon_bg; }

/* ── progress, scales, level bars ────────────────────────────────── */
progressbar progress, levelbar block.filled, scale highlight {
  background-color: @neon_accent;
  background-image: none;
  border-color: @neon_accent;
}
progressbar trough, scale trough, levelbar trough {
  background-color: @neon_surface;
  background-image: none;
  border-color: @neon_border;
}
scale slider {
  background-color: @neon_fg;
  background-image: none;
  border-color: @neon_fg;
  box-shadow: none;
}

/* ── scrollbars ───────────────────────────────────────────────────── */
scrollbar, scrollbar trough { background-color: @neon_bg; border-color: @neon_bg; }
scrollbar slider { background-color: #2c2c38; border: none; border-radius: 0; }
scrollbar slider:hover { background-color: @neon_dim; }
scrollbar slider:active { background-color: @neon_accent; }

/* ── tabs ─────────────────────────────────────────────────────────── */
notebook > header { border-color: @neon_border; }
notebook > header tab {
  background-color: @neon_bg;
  border: none;
  box-shadow: none;
  color: @neon_dim;
}
notebook > header tab:hover { background-color: @neon_hover; color: @neon_fg; }
notebook > header tab:checked { background-color: @neon_accent; color: @neon_bg; }
notebook > header tab:checked label { color: @neon_bg; }

/* ── tooltips & links ─────────────────────────────────────────────── */
tooltip, tooltip.background {
  background-color: @neon_bg;
  border: 1px solid @neon_border;
  border-radius: 0;
  box-shadow: none;
  color: @neon_fg;
}
tooltip * { background-color: transparent; color: @neon_fg; }
*:link { color: @neon_accent; }
*:visited { color: @neon_accent2; }
EOF

render > "$CFG/gtk-4.0/gtk.css" <<'EOF'
/* i3-neon — GTK4 / libadwaita colour overrides: pure black + neon accents.
   Accent colours are rewritten by the wallhaven add-on when palette sync is on.
   Restart an app to see changes. */

/* libadwaita named colours */
@define-color accent_color @BLUE@;
@define-color accent_bg_color @BLUE@;
@define-color accent_fg_color @BG@;
@define-color destructive_color @URGENT@;
@define-color destructive_bg_color @URGENT@;
@define-color destructive_fg_color @BG@;
@define-color success_color @GREEN@;
@define-color success_bg_color @GREEN@;
@define-color success_fg_color @BG@;
@define-color error_color @URGENT@;
@define-color error_bg_color @URGENT@;
@define-color error_fg_color @BG@;
@define-color window_bg_color @BG@;
@define-color window_fg_color @TXT@;
@define-color view_bg_color @BG@;
@define-color view_fg_color @TXT@;
@define-color headerbar_bg_color @BG@;
@define-color headerbar_fg_color @TXT@;
@define-color headerbar_border_color #1f1f29;
@define-color headerbar_backdrop_color @BG@;
@define-color sidebar_bg_color @BG@;
@define-color sidebar_fg_color @TXT@;
@define-color sidebar_backdrop_color @BG@;
@define-color secondary_sidebar_bg_color @BG@;
@define-color secondary_sidebar_fg_color @TXT@;
@define-color card_bg_color #0b0b10;
@define-color card_fg_color @TXT@;
@define-color dialog_bg_color @BG@;
@define-color dialog_fg_color @TXT@;
@define-color popover_bg_color @BG@;
@define-color popover_fg_color @TXT@;
@define-color thumbnail_bg_color #0b0b10;
@define-color thumbnail_fg_color @TXT@;

/* plain GTK4 apps (non-libadwaita) */
@define-color theme_bg_color @BG@;
@define-color theme_fg_color @TXT@;
@define-color theme_base_color @BG@;
@define-color theme_text_color @TXT@;
@define-color theme_selected_bg_color @BLUE@;
@define-color theme_selected_fg_color @BG@;
@define-color borders #1f1f29;

/* libadwaita >= 1.6 reads CSS variables */
:root {
  --accent-color: @BLUE@;
  --accent-bg-color: @BLUE@;
  --accent-fg-color: @BG@;
  --destructive-bg-color: @URGENT@;
  --window-bg-color: @BG@;
  --window-fg-color: @TXT@;
  --view-bg-color: @BG@;
  --view-fg-color: @TXT@;
  --headerbar-bg-color: @BG@;
  --headerbar-fg-color: @TXT@;
  --sidebar-bg-color: @BG@;
  --sidebar-fg-color: @TXT@;
  --card-bg-color: #0b0b10;
  --dialog-bg-color: @BG@;
  --popover-bg-color: @BG@;
  --window-radius: 0;
}

window.csd, popover > contents, menu { border-radius: 0; }
selection { background-color: @PURPLE@; color: @BG@; }
EOF

# libadwaita/GTK4 dark preference (read through gsettings / the settings portal)
if command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
  gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme "$ICONS" 2>/dev/null || true
fi

# ~/.xprofile is sourced by LightDM for every X session
touch "$HOME/.xprofile"
sed -i '/# >>> i3-neon >>>/,/# <<< i3-neon <<</d' "$HOME/.xprofile"
cat >> "$HOME/.xprofile" <<'EOF'
# >>> i3-neon >>>
# Fixes blank/grey Java windows (Burp, ZAP, Ghidra) under non-reparenting WMs
export _JAVA_AWT_WM_NONREPARENTING=1
export TERMINAL=alacritty
# Qt apps follow the GTK theme; libadwaita apps forced dark even without a settings portal
export QT_QPA_PLATFORMTHEME=gtk3
export ADW_DEBUG_COLOR_SCHEME=prefer-dark
# <<< i3-neon <<<
EOF

chmod +x "$CFG"/i3/scripts/*.sh "$CFG"/polybar/launch.sh "$CFG"/polybar/scripts/*.sh "$CFG"/rofi/powermenu.sh

# ============================================================ validation ===
if command -v i3 >/dev/null; then
  if i3 -C -c "$CFG/i3/config" >/tmp/i3-check.log 2>&1; then log "i3 config validated."
  else warn "i3 config check reported issues — see /tmp/i3-check.log"; fi
fi

# ================================================ bare metal / laptop system ===
NM_WARN=0
if [[ $CONFIGS_ONLY -eq 0 && "$VIRT" == "none" ]]; then
  if dpkg -s lightdm >/dev/null 2>&1 && ! systemctl is-enabled lightdm >/dev/null 2>&1 \
     && [[ ! -s /etc/X11/default-display-manager || "$(cat /etc/X11/default-display-manager)" == *lightdm ]]; then
    log "Enabling the LightDM login screen..."
    sudo systemctl enable lightdm >/dev/null 2>&1 || warn "Could not enable lightdm"
  fi
  sudo systemctl set-default graphical.target >/dev/null 2>&1 || true

  if [[ "$OS_ID" != "kali" ]] && dpkg -s lightdm-gtk-greeter >/dev/null 2>&1; then
    sudo mkdir -p /etc/lightdm/lightdm-gtk-greeter.conf.d
    printf '%s\n' '[greeter]' 'background = #000000' "theme-name = $GTK_THEME" \
      "icon-theme-name = $ICONS" 'font-name = Sans 10' 'clock-format = %a %d %b  %H:%M' \
      'indicators = ~host;~spacer;~clock;~spacer;~session;~power' \
      | sudo tee /etc/lightdm/lightdm-gtk-greeter.conf.d/60-i3-neon.conf >/dev/null
  fi

  # Debian netinst configures Wi-Fi/Ethernet in /etc/network/interfaces, which hides it from NetworkManager
  grep -Eqs '^[[:space:]]*(allow-hotplug|auto|iface)[[:space:]]+(wl|en|eth)' /etc/network/interfaces && NM_WARN=1
fi

if [[ $CONFIGS_ONLY -eq 0 ]] && (( LAPTOP )); then
  log "Laptop: touchpad tap-to-click, backlight access, power saving..."
  sudo mkdir -p /etc/X11/xorg.conf.d
  sudo tee /etc/X11/xorg.conf.d/40-i3-neon-touchpad.conf >/dev/null <<'EOF'
# i3-neon: touchpad (libinput)
Section "InputClass"
    Identifier "i3-neon touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "TappingDrag" "on"
    Option "DisableWhileTyping" "on"
    Option "ClickMethod" "clickfinger"
    Option "NaturalScrolling" "false"
EndSection
EOF
  sudo usermod -aG video "$USER" || true          # brightnessctl without sudo
  if dpkg -s tlp >/dev/null 2>&1; then
    sudo systemctl enable --now tlp >/dev/null 2>&1 || true
    sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket >/dev/null 2>&1 || true  # per TLP docs
  fi
fi

# ======================================================= session switching ===
if [[ $CONFIGS_ONLY -eq 0 ]]; then
  [[ -f /usr/share/xsessions/i3.desktop ]] || die "i3.desktop session file missing."
  log "Setting i3 as the default LightDM session (XFCE stays installed)..."
  sudo mkdir -p /etc/lightdm/lightdm.conf.d
  printf '[Seat:*]\nuser-session=i3\n' | sudo tee /etc/lightdm/lightdm.conf.d/60-i3-neon.conf >/dev/null
  printf '[Desktop]\nSession=i3\n' > "$HOME/.dmrc"
  ASU="/var/lib/AccountsService/users/$USER"
  if sudo test -f "$ASU"; then
    if sudo grep -q '^XSession=' "$ASU"; then sudo sed -i 's/^XSession=.*/XSession=i3/' "$ASU"
    else sudo sed -i '/^\[User\]/a XSession=i3' "$ASU"; fi
  fi

  mkdir -p "$CFG/i3-neon"
  cat > "$CFG/i3-neon/rollback.sh" <<EOF
#!/usr/bin/env bash
# Revert default session to XFCE and restore pre-i3-neon configs
set -e
sudo rm -f /etc/lightdm/lightdm.conf.d/60-i3-neon.conf /etc/lightdm/lightdm-gtk-greeter.conf.d/60-i3-neon.conf \
            /etc/X11/xorg.conf.d/40-i3-neon-touchpad.conf
printf '[Desktop]\nSession=xfce\n' > "\$HOME/.dmrc"
ASU="/var/lib/AccountsService/users/\$USER"
sudo test -f "\$ASU" && sudo sed -i 's/^XSession=.*/XSession=xfce/' "\$ASU" || true
for v in 3 4; do grep -qs 'i3-neon' "\$HOME/.config/gtk-\$v.0/gtk.css" && rm -f "\$HOME/.config/gtk-\$v.0/gtk.css"; done
for d in "$BACKUP"/*; do [ -e "\$d" ] || continue
  case "\$(basename "\$d")" in gtk3-settings.ini) cp "\$d" "\$HOME/.config/gtk-3.0/settings.ini" ;;
    gtk3-gtk.css) cp "\$d" "\$HOME/.config/gtk-3.0/gtk.css" ;;
    gtk4-gtk.css) cp "\$d" "\$HOME/.config/gtk-4.0/gtk.css" ;;
    *) rm -rf "\$HOME/.config/\$(basename "\$d")"; cp -a "\$d" "\$HOME/.config/" ;; esac
done
sed -i '/# >>> i3-neon >>>/,/# <<< i3-neon <<</d' "\$HOME/.xprofile"
echo "Rolled back. Log out and pick Xfce."
EOF
  chmod +x "$CFG/i3-neon/rollback.sh"
fi

# Live reload if we're already inside i3
if [[ -n "${I3SOCK:-}" ]] || pgrep -x i3 >/dev/null 2>&1; then i3-msg restart >/dev/null 2>&1 || true; fi

cat <<EOF

${c_b}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${c_0}
 ${c_p}i3-neon installed.${c_0}  Log out → choose ${c_b}i3${c_0} at LightDM (now default).
 Backups:  $BACKUP
 Rollback: ~/.config/i3-neon/rollback.sh
 Mod key:  $MOD   |   Press  Mod+/  for a searchable keybinding list
 Platform: $PLATFORM$( [[ "$VIRT" == "none" ]] && printf '   |   Displays: Mod+Shift+m')
${c_b}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${c_0}
EOF
if (( NM_WARN )); then
  warn "Your network is configured in /etc/network/interfaces, so NetworkManager (Wi-Fi menu) ignores it."
  warn "After you can log in: sudo nano /etc/network/interfaces → delete the wl*/en* lines (keep 'lo'),"
  warn "then reboot and connect from the Wi-Fi icon in the bar tray (or: nmtui)."
fi
(( LAPTOP )) && warn "Log out and back in once so brightness keys work (you were added to the 'video' group)."
true

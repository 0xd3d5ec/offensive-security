#!/bin/bash
# install-spice-autoresize.sh
# Automates xrandr resizing inside a SPICE/KVM guest on every resolution change.

set -e

BIN_DIR="$HOME/.local/bin"
AUTOSTART_DIR="$HOME/.config/autostart"
SCRIPT_PATH="$BIN_DIR/spice-autoresize.sh"
DESKTOP_PATH="$AUTOSTART_DIR/spice-autoresize.desktop"

echo "[*] Creating $BIN_DIR if it doesn't exist..."
mkdir -p "$BIN_DIR"

echo "[*] Writing autoresize script to $SCRIPT_PATH..."
cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash
# spice-autoresize.sh
# Fires xrandr --auto on every RandR screen change event.

xrandr --output Virtual-1 --auto

xev -root -event randr | while IFS= read -r line; do
    if [[ "$line" == *"RRScreenChangeNotify"* ]]; then
        xrandr --output Virtual-1 --auto
    fi
done
EOF

chmod +x "$SCRIPT_PATH"
echo "[+] Script written and marked executable."

echo "[*] Creating autostart entry at $DESKTOP_PATH..."
mkdir -p "$AUTOSTART_DIR"
cat > "$DESKTOP_PATH" << EOF
[Desktop Entry]
Type=Application
Name=SPICE Autoresize
Exec=$SCRIPT_PATH
Hidden=false
X-GNOME-Autostart-enabled=true
EOF

echo "[+] Autostart entry created."

echo "[*] Checking if xev is installed..."
if ! command -v xev &>/dev/null; then
    echo "[!] xev not found. Installing x11-utils..."
    sudo apt install -y x11-utils
    echo "[+] x11-utils installed."
else
    echo "[+] xev already installed."
fi

echo ""
echo "[+] Done. Starting the autoresize script in the background for this session..."
nohup "$SCRIPT_PATH" &>/dev/null &
echo "[+] Running (PID $!). Will also auto-start on every future login."

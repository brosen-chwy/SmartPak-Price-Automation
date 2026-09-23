#!/bin/zsh

set -euo pipefail

DEFAULT_ROOT="$HOME/Library/CloudStorage/OneDrive-Chewy.com,LLC/SmartPak/Pricing/PriceMatching"
ROOT_PATH="${SMARTPAK_ROOT:-$DEFAULT_ROOT}"
KEYCHAIN_SERVICE='com.chewy.smartpak-price-upload'
LOCAL_SCRIPT_ROOT="$HOME/Library/Application Support/SmartPakPriceAutomation"

for directory in Incoming Processing Archive Failed Logs State Scripts LaunchAgents; do
    /bin/mkdir -p "$ROOT_PATH/$directory"
done

read -r "smartpak_username?SmartPak username (DOMAIN\\alias): "
if [[ -z "$smartpak_username" ]]; then
    print -u2 'A username is required.'
    exit 1
fi

read -rs "smartpak_password?SmartPak password: "
print
if [[ -z "$smartpak_password" ]]; then
    print -u2 'A password is required.'
    exit 1
fi

/usr/bin/security add-generic-password \
    -a "$smartpak_username" \
    -s "$KEYCHAIN_SERVICE" \
    -w "$smartpak_password" \
    -U >/dev/null

print -r -- "$smartpak_username" > "$ROOT_PATH/State/SmartPakUsername"
/bin/chmod 600 "$ROOT_PATH/State/SmartPakUsername"

unset smartpak_password

for script in "$ROOT_PATH"/Scripts/*.zsh(N); do
    /bin/chmod 700 "$script"
done

/bin/mkdir -p "$LOCAL_SCRIPT_ROOT"
if [[ -f "$ROOT_PATH/Scripts/SmartPakPriceUpload.zsh" ]]; then
    /bin/cp "$ROOT_PATH/Scripts/SmartPakPriceUpload.zsh" "$LOCAL_SCRIPT_ROOT/SmartPakPriceUpload.zsh"
    /bin/chmod 700 "$LOCAL_SCRIPT_ROOT/SmartPakPriceUpload.zsh"
fi

print
print "SmartPak macOS automation initialized under: $ROOT_PATH"
print 'The password is stored in macOS Keychain.'
print 'Production submission remains disabled.'

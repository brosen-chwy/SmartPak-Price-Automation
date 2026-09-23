# macOS automation pilot

The macOS pilot uses Chewy OneDrive, `curl --ntlm`, macOS Keychain, and a `launchd` LaunchAgent. Chrome and Power Automate Desktop are not required.

The default runtime root is:

```text
~/Library/CloudStorage/OneDrive-Chewy.com,LLC/SmartPak/Pricing/PriceMatching
```

## Initialize

Copy the two `.zsh` scripts into the runtime `Scripts` folder, then run:

```zsh
/bin/zsh "$HOME/Library/CloudStorage/OneDrive-Chewy.com,LLC/SmartPak/Pricing/PriceMatching/Scripts/Initialize-SmartPakAutomation.zsh"
```

Enter the same `DOMAIN\alias` credential that successfully authenticated with `curl --ntlm`. The password is saved in the user's macOS Keychain; it is not written to OneDrive.

## Dry run

Put exactly one CSV in `Incoming` and run:

```zsh
/bin/zsh "$HOME/Library/CloudStorage/OneDrive-Chewy.com,LLC/SmartPak/Pricing/PriceMatching/Scripts/SmartPakPriceUpload.zsh" --dry-run
```

The dry run validates the CSV, checks duplicate hashes, authenticates, captures session cookies, and verifies the anti-forgery token. It does not upload or move the CSV.

## LaunchAgent

The included property list runs the dry run every 15 minutes. The executable copy is kept in local Application Support because macOS `launchd` cannot reliably execute scripts directly from a File Provider-managed OneDrive folder. OneDrive remains the location for incoming files, archives, state, and logs.

Install the local executable copy and validate the property list:

```zsh
mkdir -p "$HOME/Library/Application Support/SmartPakPriceAutomation"
cp "$HOME/Library/CloudStorage/OneDrive-Chewy.com,LLC/SmartPak/Pricing/PriceMatching/Scripts/SmartPakPriceUpload.zsh" "$HOME/Library/Application Support/SmartPakPriceAutomation/SmartPakPriceUpload.zsh"
chmod 700 "$HOME/Library/Application Support/SmartPakPriceAutomation/SmartPakPriceUpload.zsh"
plutil -lint "$HOME/Library/CloudStorage/OneDrive-Chewy.com,LLC/SmartPak/Pricing/PriceMatching/LaunchAgents/com.chewy.smartpak-price-upload.plist"
```

Install it only after the manual dry run passes:

```zsh
cp "$HOME/Library/CloudStorage/OneDrive-Chewy.com,LLC/SmartPak/Pricing/PriceMatching/LaunchAgents/com.chewy.smartpak-price-upload.plist" "$HOME/Library/LaunchAgents/"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.chewy.smartpak-price-upload.plist"
```

The LaunchAgent continues while the screen is locked, but the Mac must remain powered on, awake, logged in, and connected to OneDrive. It does not run before login after a reboot.

## Production gate

Production requires `--submit` and this exact local flag:

```text
State/EnableProductionUpload.flag
SMARTPAK_PRODUCTION_UPLOAD_ENABLED
```

Keep the LaunchAgent in `--dry-run` mode until a controlled no-op macOS upload succeeds. Changing the LaunchAgent to `--submit` should occur only after that test and an explicit operational decision.

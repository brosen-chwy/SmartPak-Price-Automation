# SmartPak Price Automation

This repository contains the pilot automation for generating, validating, and uploading SmartPak product-price changes.

The intended workflow is:

1. Power Automate or another approved scheduler runs the SQL candidate query.
2. The export is written as a temporary file and renamed into the `Incoming` folder only after the write completes.
3. Windows Task Scheduler runs the PowerShell uploader on a Covetrus-managed Windows host.
4. The uploader validates the CSV, authenticates to WebOffice, retrieves the anti-forgery token, and prepares the SmartPak form submission.
5. Dry run is the default. Production submission requires both `-Mode Submit` and a separate local enablement flag.
6. The uploader logs the outcome and moves submitted or failed files into the appropriate lifecycle folder.

## Repository layout

```text
scripts/
  Initialize-SmartPakAutomation.ps1
  SmartPakPriceUpload.ps1
sql/
  smartpak_price_update_candidates.sql
  market_pricing_clean_parameterized.sql
  legacy/
docs/
templates/
  ProductPriceUpdateTemplate.csv
```

The current production-shaped SQL is `sql/smartpak_price_update_candidates.sql`. It defaults to review output and must be reconciled against an approved human run before unattended use. See `docs/smartpak_price_update_candidates.md` for the remaining business-rule limitations.

## Windows installation

Copy the scripts to:

```text
C:\Users\brian.caudill\OneDrive - Covetrus\PriceMatching\Scripts
```

Initialize the runtime folders and encrypted alias credential using PowerShell 7:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\Users\brian.caudill\OneDrive - Covetrus\PriceMatching\Scripts\Initialize-SmartPakAutomation.ps1"
```

Place exactly one CSV in `PriceMatching\Incoming`, then run the safe default dry run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\Users\brian.caudill\OneDrive - Covetrus\PriceMatching\Scripts\SmartPakPriceUpload.ps1"
```

A successful dry run ends with:

```text
Dry run passed. Submission performed: No.
```

See the operational guide in [`docs/windows-automation.md`](docs/windows-automation.md) for folder behavior, Task Scheduler configuration, safeguards, and controlled production enablement.

## Security

Never commit credentials, cookies, tokens, production price files, logs, response HTML, state ledgers, or production enablement flags. The included `.gitignore` excludes those artifacts.

The SmartPak credential is stored locally using Windows DPAPI and can only be decrypted by the same Windows user on the same computer. The scheduled task must run under that account.

## Current operating constraint

The Covetrus laptop can reach SmartPak only while connected to the Covetrus VPN. Use dry-run scheduling for the laptop pilot. Do not enable unattended production submission until an Always On VPN or a Covetrus-managed Windows VM is available and the first approved no-op production submission confirms SmartPak's success response.

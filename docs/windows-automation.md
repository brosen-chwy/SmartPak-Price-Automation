# Windows automation operating guide

The uploader uses the authenticated SmartPak web form directly. Chrome and Power Automate Desktop are not required.

Production submission is disabled by default. The main script defaults to `DryRun`, and `Submit` additionally requires a local enablement flag that the initializer does not create.

## Folder lifecycle

The initializer creates:

```text
PriceMatching\
  Incoming\
  Processing\
  Archive\
  Failed\
  Logs\
  State\
  Secrets\
  Scripts\
```

The upstream SQL/Power Automate process should write a `.partial` file first and rename it to `.csv` only after the write completes. The uploader ignores non-CSV files and requires exactly one CSV in `Incoming`.

In `DryRun`, the CSV stays in `Incoming`. In `Submit`, it moves through `Processing` and then to `Archive\yyyy-MM` after an HTTP success without detected form-validation errors. A failed submission moves the file to `Failed` and preserves the returned HTML under `Logs`.

## Task Scheduler pilot

Create a task under the same Windows account used by the initializer. Select **Run whether user is logged on or not**, leave **Do not store password** unchecked, and choose **Do not start a new instance** when the task is already running.

```text
Program/script:
C:\Program Files\PowerShell\7\pwsh.exe

Arguments:
-NoProfile -ExecutionPolicy Bypass -File "C:\Users\brian.caudill\OneDrive - Covetrus\PriceMatching\Scripts\SmartPakPriceUpload.ps1" -Mode DryRun

Start in:
C:\Users\brian.caudill\OneDrive - Covetrus\PriceMatching\Scripts
```

The laptop must remain powered on, awake, connected to the Covetrus VPN, and signed into OneDrive. Mark the automation folders **Always keep on this device**.

## Production enablement

The first production test must use a small CSV containing freshly confirmed live OTS and ATS prices, making the upload a no-op. Run it manually with an engineer available to confirm the WebOffice/database result.

After approval, create:

```text
C:\Users\brian.caudill\OneDrive - Covetrus\PriceMatching\State\EnableProductionUpload.flag
```

with exactly:

```text
SMARTPAK_PRODUCTION_UPLOAD_ENABLED
```

Run with `-Mode Submit`. Rename or remove the flag immediately afterward to disable further production submissions.

HTTP 200 plus absence of MVC validation errors is the current success rule. The first approved upload must confirm that rule before unattended production use.

## Safeguards

- Exact headers are required: `ProductID`, `New OTS Price`, `New ATS Price`.
- Product IDs must be numeric and unique.
- Prices must be non-negative with no more than two decimal places.
- Only one CSV may wait in `Incoming`.
- A 30-second stability check prevents reading a partially synchronized file.
- A lock prevents overlapping runs.
- A SHA-256 ledger prevents resubmission of a file already recorded as submitted.
- The effective date is generated as today's local Windows date.
- The two-hour-window field is submitted as checked.
- Logs never contain the password, cookies, or anti-forgery token.

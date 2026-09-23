[CmdletBinding()]
param(
    [string]$RootPath = 'C:\Users\brian.caudill\OneDrive - Covetrus\PriceMatching',

    [ValidateSet('DryRun', 'Submit')]
    [string]$Mode = 'DryRun',

    [ValidateRange(0, 600)]
    [int]$StableSeconds = 30
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$PageUri = [uri]'https://weboffice.smartpak.com/productprice'
$UploadUri = [uri]'https://weboffice.smartpak.com/ProductPrice/Schedule'
$ExpectedHeaders = @('ProductID', 'New OTS Price', 'New ATS Price')
$ProductionFlagText = 'SMARTPAK_PRODUCTION_UPLOAD_ENABLED'

$IncomingPath = Join-Path $RootPath 'Incoming'
$ProcessingDirectory = Join-Path $RootPath 'Processing'
$ArchiveRoot = Join-Path $RootPath 'Archive'
$FailedDirectory = Join-Path $RootPath 'Failed'
$LogsDirectory = Join-Path $RootPath 'Logs'
$StateDirectory = Join-Path $RootPath 'State'
$SecretsDirectory = Join-Path $RootPath 'Secrets'
$CredentialPath = Join-Path $SecretsDirectory 'SmartPakCredential.xml'
$ProductionFlagPath = Join-Path $StateDirectory 'EnableProductionUpload.flag'
$LedgerPath = Join-Path $StateDirectory 'ProcessedFiles.csv'
$LockPath = Join-Path $StateDirectory 'SmartPakPriceUpload.lock'

$RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogPath = Join-Path $LogsDirectory "SmartPakPriceUpload-$RunId.log"
$ResponsePath = Join-Path $LogsDirectory "SmartPakPriceUpload-$RunId-response.html"

$Handler = $null
$Client = $null
$PageResponse = $null
$PostResponse = $null
$Multipart = $null
$FileStream = $null
$FileContent = $null
$LockStream = $null
$LockAcquired = $false
$ProcessingPath = $null
$InputFile = $null
$SubmissionAttempted = $false

function Write-RunLog {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,
        [string]$Message
    )

    $Line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $Line
    Write-Host $Line
}

function Assert-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Required directory is missing: $Path"
    }
}

function Test-PriceText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    if ($Value -notmatch '^\d+(\.\d{1,2})?$') {
        return $false
    }

    $Parsed = [decimal]0
    return [decimal]::TryParse(
        $Value,
        [Globalization.NumberStyles]::Number,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$Parsed
    ) -and $Parsed -ge 0
}

function Assert-ValidCsv {
    param([string]$Path)

    $Rows = @(Import-Csv -LiteralPath $Path)

    if ($Rows.Count -eq 0) {
        throw 'The CSV contains no data rows.'
    }

    $ActualHeaders = @($Rows[0].PSObject.Properties.Name)
    if (($ActualHeaders -join '|') -ne ($ExpectedHeaders -join '|')) {
        throw "Incorrect CSV headers: $($ActualHeaders -join ', ')"
    }

    $Duplicates = @(
        $Rows |
            Group-Object -Property ProductID |
            Where-Object { $_.Count -gt 1 }
    )

    if ($Duplicates.Count -gt 0) {
        throw "Duplicate ProductID values: $($Duplicates.Name -join ', ')"
    }

    $CsvRowNumber = 1
    foreach ($Row in $Rows) {
        $CsvRowNumber++
        $ProductId = [string]$Row.ProductID

        if ($ProductId -notmatch '^\d+$') {
            throw "Invalid ProductID '$ProductId' on CSV row $CsvRowNumber."
        }

        if (-not (Test-PriceText -Value ([string]$Row.'New OTS Price'))) {
            throw "Invalid New OTS Price on CSV row $CsvRowNumber."
        }

        if (-not (Test-PriceText -Value ([string]$Row.'New ATS Price'))) {
            throw "Invalid New ATS Price on CSV row $CsvRowNumber."
        }
    }

    return $Rows
}

function Add-LedgerEntry {
    param(
        [string]$FileName,
        [string]$Sha256,
        [string]$Status,
        [string]$Detail
    )

    [pscustomobject]@{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        FileName = $FileName
        SHA256 = $Sha256
        Status = $Status
        EffectiveDate = Get-Date -Format 'yyyy-MM-dd'
        Detail = $Detail
    } | Export-Csv -LiteralPath $LedgerPath -NoTypeInformation -Append
}

try {
    foreach ($RequiredDirectory in @(
        $IncomingPath,
        $ProcessingDirectory,
        $ArchiveRoot,
        $FailedDirectory,
        $LogsDirectory,
        $StateDirectory,
        $SecretsDirectory
    )) {
        Assert-Directory -Path $RequiredDirectory
    }

    try {
        $LockStream = [IO.File]::Open(
            $LockPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        $LockAcquired = $true
    }
    catch {
        throw "Another SmartPak upload run appears active. Lock file: $LockPath"
    }

    Write-RunLog -Level INFO -Message "Run started. Mode=$Mode"

    if (-not (Test-Path -LiteralPath $CredentialPath -PathType Leaf)) {
        throw "Encrypted credential is missing: $CredentialPath"
    }

    $CandidateFiles = @(
        Get-ChildItem -LiteralPath $IncomingPath -Filter '*.csv' -File |
            Sort-Object LastWriteTimeUtc
    )

    if ($CandidateFiles.Count -eq 0) {
        Write-RunLog -Level INFO -Message 'No CSV file is waiting in Incoming. Nothing to do.'
        exit 0
    }

    if ($CandidateFiles.Count -gt 1) {
        throw "Expected exactly one CSV in Incoming but found $($CandidateFiles.Count)."
    }

    $InputFile = $CandidateFiles[0]
    Write-RunLog -Level INFO -Message "Candidate file: $($InputFile.FullName)"

    $InitialLength = $InputFile.Length
    $InitialWriteTime = $InputFile.LastWriteTimeUtc

    if ($StableSeconds -gt 0) {
        Write-RunLog -Level INFO -Message "Checking file stability for $StableSeconds seconds."
        Start-Sleep -Seconds $StableSeconds
        $InputFile.Refresh()
    }

    if (
        $InputFile.Length -ne $InitialLength -or
        $InputFile.LastWriteTimeUtc -ne $InitialWriteTime
    ) {
        throw 'The incoming CSV changed during the stability check.'
    }

    $Rows = @(Assert-ValidCsv -Path $InputFile.FullName)
    $FileHash = (Get-FileHash -LiteralPath $InputFile.FullName -Algorithm SHA256).Hash
    Write-RunLog -Level INFO -Message "CSV validation passed. Rows=$($Rows.Count), SHA256=$FileHash"

    if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) {
        $PriorSubmission = @(
            Import-Csv -LiteralPath $LedgerPath |
                Where-Object {
                    $_.SHA256 -eq $FileHash -and
                    $_.Status -eq 'Submitted'
                }
        )

        if ($PriorSubmission.Count -gt 0) {
            throw 'This exact CSV was already recorded as submitted.'
        }
    }

    $Credential = Import-Clixml -LiteralPath $CredentialPath
    if ($Credential -isnot [System.Management.Automation.PSCredential]) {
        throw 'The stored credential is invalid or cannot be decrypted by this user.'
    }

    $Handler = [System.Net.Http.HttpClientHandler]::new()
    $Handler.Credentials = $Credential.GetNetworkCredential()
    $Handler.UseCookies = $true
    $Handler.CookieContainer = [System.Net.CookieContainer]::new()
    $Handler.AllowAutoRedirect = $true

    $Client = [System.Net.Http.HttpClient]::new($Handler)
    $Client.Timeout = [TimeSpan]::FromSeconds(120)

    Write-RunLog -Level INFO -Message 'Authenticating and retrieving the SmartPak upload page.'
    $PageResponse = $Client.GetAsync($PageUri).GetAwaiter().GetResult()
    $PageHtml = $PageResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()

    if (-not $PageResponse.IsSuccessStatusCode) {
        throw "SmartPak authentication failed. HTTP status=$([int]$PageResponse.StatusCode)"
    }

    $TokenMatch = [regex]::Match(
        $PageHtml,
        'name="__RequestVerificationToken"[^>]*value="([^"]+)"',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if (-not $TokenMatch.Success) {
        throw 'The SmartPak verification token was not found.'
    }

    if ($PageHtml -notmatch '/ProductPrice/Schedule') {
        throw 'The expected SmartPak upload endpoint was not found.'
    }

    $Token = $TokenMatch.Groups[1].Value
    $CookieCount = $Handler.CookieContainer.GetCookies($PageUri).Count
    $EffectiveDate = Get-Date -Format 'yyyy-MM-dd'

    Write-RunLog -Level INFO -Message "SmartPak preflight passed. Cookies=$CookieCount, EffectiveDate=$EffectiveDate"

    if ($Mode -eq 'DryRun') {
        Write-RunLog -Level INFO -Message 'Dry run passed. Submission performed: No.'
        exit 0
    }

    if (-not (Test-Path -LiteralPath $ProductionFlagPath -PathType Leaf)) {
        throw "Production upload is disabled. Missing flag: $ProductionFlagPath"
    }

    $FlagText = (Get-Content -LiteralPath $ProductionFlagPath -Raw).Trim()
    if ($FlagText -ne $ProductionFlagText) {
        throw 'Production upload flag content is invalid.'
    }

    $ProcessingPath = Join-Path $ProcessingDirectory $InputFile.Name
    if (Test-Path -LiteralPath $ProcessingPath) {
        throw "Processing destination already exists: $ProcessingPath"
    }

    Move-Item -LiteralPath $InputFile.FullName -Destination $ProcessingPath
    Write-RunLog -Level INFO -Message "Moved file to Processing: $ProcessingPath"

    $Multipart = [System.Net.Http.MultipartFormDataContent]::new()
    $Multipart.Add(
        [System.Net.Http.StringContent]::new($Token),
        '__RequestVerificationToken'
    )
    $Multipart.Add(
        [System.Net.Http.StringContent]::new($EffectiveDate),
        'ProductPriceChangeFileModel.EffectiveDate'
    )
    $Multipart.Add(
        [System.Net.Http.StringContent]::new('true'),
        'ProductPriceChangeFileModel.ProcessFrequently'
    )
    $Multipart.Add(
        [System.Net.Http.StringContent]::new('false'),
        'ProductPriceChangeFileModel.ProcessFrequently'
    )

    $FileStream = [IO.File]::OpenRead($ProcessingPath)
    $FileContent = [System.Net.Http.StreamContent]::new($FileStream)
    $FileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('text/csv')
    $Multipart.Add($FileContent, 'file', [IO.Path]::GetFileName($ProcessingPath))

    $Client.DefaultRequestHeaders.Referrer = $PageUri
    $SubmissionAttempted = $true
    Write-RunLog -Level WARN -Message "Submitting production upload: $ProcessingPath"

    $PostResponse = $Client.PostAsync($UploadUri, $Multipart).GetAwaiter().GetResult()
    $PostHtml = $PostResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    Set-Content -LiteralPath $ResponsePath -Value $PostHtml -Encoding UTF8

    if (-not $PostResponse.IsSuccessStatusCode) {
        throw "SmartPak submission returned HTTP $([int]$PostResponse.StatusCode)."
    }

    if (
        $PostHtml -match 'validation-summary-errors' -or
        $PostHtml -match 'field-validation-error'
    ) {
        throw 'SmartPak returned a form-validation error. Review the saved response HTML.'
    }

    $ArchiveDirectory = Join-Path $ArchiveRoot (Get-Date -Format 'yyyy-MM')
    if (-not (Test-Path -LiteralPath $ArchiveDirectory)) {
        New-Item -ItemType Directory -Path $ArchiveDirectory | Out-Null
    }

    $ArchivePath = Join-Path $ArchiveDirectory $InputFile.Name
    if (Test-Path -LiteralPath $ArchivePath) {
        $ArchivePath = Join-Path $ArchiveDirectory (
            '{0}-{1}{2}' -f
                [IO.Path]::GetFileNameWithoutExtension($InputFile.Name),
                $RunId,
                [IO.Path]::GetExtension($InputFile.Name)
        )
    }

    Move-Item -LiteralPath $ProcessingPath -Destination $ArchivePath
    $ProcessingPath = $null

    $SubmittedLedgerEntry = @{
        FileName = $InputFile.Name
        Sha256 = $FileHash
        Status = 'Submitted'
        Detail = "HTTP $([int]$PostResponse.StatusCode); Response=$ResponsePath"
    }
    Add-LedgerEntry @SubmittedLedgerEntry

    Write-RunLog -Level INFO -Message "Submission accepted and file archived: $ArchivePath"
}
catch {
    $FailureMessage = $_.Exception.Message

    if (Test-Path -LiteralPath $LogsDirectory -PathType Container) {
        Write-RunLog -Level ERROR -Message $FailureMessage
    }
    else {
        Write-Error $FailureMessage
    }

    if (
        $null -ne $ProcessingPath -and
        (Test-Path -LiteralPath $ProcessingPath -PathType Leaf)
    ) {
        $FailedName = '{0}-{1}{2}' -f
            [IO.Path]::GetFileNameWithoutExtension($ProcessingPath),
            $RunId,
            [IO.Path]::GetExtension($ProcessingPath)

        $FailedPath = Join-Path $FailedDirectory $FailedName
        Move-Item -LiteralPath $ProcessingPath -Destination $FailedPath

        if ($null -ne $InputFile) {
            $FailedLedgerEntry = @{
                FileName = $InputFile.Name
                Sha256 = $FileHash
                Status = 'Failed'
                Detail = "$FailureMessage; SubmissionAttempted=$SubmissionAttempted"
            }
            Add-LedgerEntry @FailedLedgerEntry
        }
    }

    exit 1
}
finally {
    if ($null -ne $PostResponse) {
        $PostResponse.Dispose()
    }
    if ($null -ne $PageResponse) {
        $PageResponse.Dispose()
    }
    if ($null -ne $Multipart) {
        $Multipart.Dispose()
    }
    if ($null -ne $FileContent) {
        $FileContent.Dispose()
    }
    if ($null -ne $FileStream) {
        $FileStream.Dispose()
    }
    if ($null -ne $Client) {
        $Client.Dispose()
    }
    if ($null -ne $Handler) {
        $Handler.Dispose()
    }
    if ($null -ne $LockStream) {
        $LockStream.Dispose()
    }
    if ($LockAcquired -and (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
        Remove-Item -LiteralPath $LockPath -Force
    }
}

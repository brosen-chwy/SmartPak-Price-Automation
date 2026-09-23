#!/bin/zsh

set -uo pipefail

DEFAULT_ROOT="$HOME/Library/CloudStorage/OneDrive-Chewy.com,LLC/SmartPak/Pricing/PriceMatching"
ROOT_PATH="${SMARTPAK_ROOT:-$DEFAULT_ROOT}"
KEYCHAIN_SERVICE='com.chewy.smartpak-price-upload'
PAGE_URL='https://weboffice.smartpak.com/productprice'
UPLOAD_URL='https://weboffice.smartpak.com/ProductPrice/Schedule'
PRODUCTION_FLAG_TEXT='SMARTPAK_PRODUCTION_UPLOAD_ENABLED'

MODE='DryRun'
if [[ "${1:-}" == '--submit' ]]; then
    MODE='Submit'
elif [[ -n "${1:-}" && "${1:-}" != '--dry-run' ]]; then
    print -u2 'Usage: SmartPakPriceUpload.zsh [--dry-run|--submit]'
    exit 2
fi

INCOMING="$ROOT_PATH/Incoming"
PROCESSING="$ROOT_PATH/Processing"
ARCHIVE_ROOT="$ROOT_PATH/Archive"
FAILED="$ROOT_PATH/Failed"
LOGS="$ROOT_PATH/Logs"
STATE="$ROOT_PATH/State"
USERNAME_FILE="$STATE/SmartPakUsername"
PRODUCTION_FLAG="$STATE/EnableProductionUpload.flag"
LEDGER="$STATE/ProcessedFiles.csv"
LOCK_DIRECTORY="$STATE/SmartPakPriceUpload.lock"

RUN_ID="$(/bin/date '+%Y%m%d-%H%M%S')"
LOG_FILE="$LOGS/SmartPakPriceUpload-$RUN_ID.log"
RESPONSE_FILE="$LOGS/SmartPakPriceUpload-$RUN_ID-response.html"

LOCK_ACQUIRED=0
TEMP_DIRECTORY=''
PROCESSING_FILE=''
INPUT_FILE=''
FILE_HASH=''
SUBMISSION_ATTEMPTED='No'
smartpak_password=''
verification_token=''

log_message() {
    local level="$1"
    shift
    local message="$*"
    local line="$(/bin/date '+%Y-%m-%d %H:%M:%S') [$level] $message"
    print -r -- "$line" | /usr/bin/tee -a "$LOG_FILE"
}

record_ledger() {
    local file_name="$1"
    local sha256="$2"
    local ledger_status="$3"
    local detail="$4"
    local effective_date="$(/bin/date '+%Y-%m-%d')"

    /usr/bin/ruby -rcsv -e '
      path, timestamp, name, hash, status, effective, detail = ARGV
      new_file = !File.exist?(path)
      CSV.open(path, "ab") do |csv|
        csv << %w[Timestamp FileName SHA256 Status EffectiveDate Detail] if new_file
        csv << [timestamp, name, hash, status, effective, detail]
      end
    ' "$LEDGER" "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$file_name" "$sha256" "$ledger_status" "$effective_date" "$detail"
}

cleanup() {
    unset smartpak_password verification_token

    if [[ -n "$TEMP_DIRECTORY" && -d "$TEMP_DIRECTORY" ]]; then
        /bin/rm -f \
            "$TEMP_DIRECTORY/productprice.html" \
            "$TEMP_DIRECTORY/cookies.txt" \
            "$TEMP_DIRECTORY/token.txt"
        /bin/rmdir "$TEMP_DIRECTORY" 2>/dev/null || true
    fi

    if [[ "$LOCK_ACQUIRED" -eq 1 && -d "$LOCK_DIRECTORY" ]]; then
        /bin/rmdir "$LOCK_DIRECTORY" 2>/dev/null || true
    fi
}

fail_run() {
    local message="$1"
    log_message ERROR "$message"

    if [[ -n "$PROCESSING_FILE" && -f "$PROCESSING_FILE" ]]; then
        local extension="${PROCESSING_FILE:e}"
        local base_name="${PROCESSING_FILE:t:r}"
        local failed_path="$FAILED/$base_name-$RUN_ID.$extension"

        if /bin/mv "$PROCESSING_FILE" "$failed_path"; then
            record_ledger \
                "${INPUT_FILE:t}" \
                "$FILE_HASH" \
                'Failed' \
                "$message; SubmissionAttempted=$SUBMISSION_ATTEMPTED"
            PROCESSING_FILE=''
        fi
    fi

    exit 1
}

trap cleanup EXIT INT TERM

for required_directory in "$INCOMING" "$PROCESSING" "$ARCHIVE_ROOT" "$FAILED" "$LOGS" "$STATE"; do
    [[ -d "$required_directory" ]] || {
        print -u2 "Required directory is missing: $required_directory"
        exit 1
    }
done

if ! /bin/mkdir "$LOCK_DIRECTORY" 2>/dev/null; then
    print -u2 "Another SmartPak run appears active: $LOCK_DIRECTORY"
    exit 1
fi
LOCK_ACQUIRED=1

log_message INFO "Run started. Mode=$MODE"

files=("$INCOMING"/*.csv(N))
if [[ "${#files[@]}" -eq 0 ]]; then
    log_message INFO 'No CSV file is waiting in Incoming. Nothing to do.'
    exit 0
fi

if [[ "${#files[@]}" -ne 1 ]]; then
    fail_run "Expected exactly one CSV in Incoming but found ${#files[@]}."
fi

INPUT_FILE="${files[1]}"
log_message INFO "Candidate file: $INPUT_FILE"

initial_state="$(/usr/bin/stat -f '%z|%m' "$INPUT_FILE")" || fail_run 'Unable to read the incoming CSV metadata.'
log_message INFO 'Checking file stability for 30 seconds.'
/bin/sleep 30
final_state="$(/usr/bin/stat -f '%z|%m' "$INPUT_FILE")" || fail_run 'The incoming CSV disappeared during the stability check.'
[[ "$initial_state" == "$final_state" ]] || fail_run 'The incoming CSV changed during the stability check.'

row_count="$(/usr/bin/ruby -rcsv -e '
  rows = CSV.read(ARGV[0], headers: true)
  expected = ["ProductID", "New OTS Price", "New ATS Price"]
  abort "Incorrect CSV headers: #{rows.headers.join(", ")}" unless rows.headers == expected
  abort "The CSV contains no data rows." if rows.empty?
  ids = {}
  rows.each_with_index do |row, index|
    csv_row = index + 2
    product_id = row["ProductID"].to_s
    abort "Invalid ProductID on CSV row #{csv_row}." unless product_id.match?(/\A\d+\z/)
    abort "Duplicate ProductID #{product_id}." if ids[product_id]
    ids[product_id] = true
    ["New OTS Price", "New ATS Price"].each do |header|
      value = row[header].to_s
      valid = value.match?(/\A\d+(\.\d{1,2})?\z/) && value.to_f >= 0
      abort "Invalid #{header} on CSV row #{csv_row}." unless valid
    end
  end
  print rows.length
' "$INPUT_FILE" 2>&1)" || fail_run "$row_count"

FILE_HASH="$(/usr/bin/shasum -a 256 "$INPUT_FILE" | /usr/bin/awk '{print toupper($1)}')" || fail_run 'Unable to calculate the CSV hash.'
log_message INFO "CSV validation passed. Rows=$row_count, SHA256=$FILE_HASH"

if [[ -f "$LEDGER" ]]; then
    /usr/bin/ruby -rcsv -e '
      found = CSV.foreach(ARGV[0], headers: true).any? do |row|
        row["SHA256"] == ARGV[1] && row["Status"] == "Submitted"
      end
      exit(found ? 0 : 1)
    ' "$LEDGER" "$FILE_HASH"
    [[ "$?" -ne 0 ]] || fail_run 'This exact CSV was already recorded as submitted.'
fi

[[ -f "$USERNAME_FILE" ]] || fail_run "SmartPak username file is missing: $USERNAME_FILE"
smartpak_username="$(<"$USERNAME_FILE")"
[[ -n "$smartpak_username" ]] || fail_run 'The stored SmartPak username is empty.'

smartpak_password="$(/usr/bin/security find-generic-password -a "$smartpak_username" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)" || fail_run 'The SmartPak password was not found in macOS Keychain.'

escape_curl_config() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    print -r -- "$value"
}

curl_with_ntlm() {
    local credentials
    credentials="$(escape_curl_config "$smartpak_username:$smartpak_password")"
    print -r -- "user = \"$credentials\"" | /usr/bin/curl --config - --ntlm "$@"
}

TEMP_DIRECTORY="$(/usr/bin/mktemp -d '/tmp/smartpak-upload.XXXXXX')" || fail_run 'Unable to create a temporary directory.'
PAGE_FILE="$TEMP_DIRECTORY/productprice.html"
COOKIE_FILE="$TEMP_DIRECTORY/cookies.txt"
TOKEN_FILE="$TEMP_DIRECTORY/token.txt"

log_message INFO 'Authenticating and retrieving the SmartPak upload page.'
get_result="$(curl_with_ntlm \
    --cookie-jar "$COOKIE_FILE" \
    --location \
    --silent \
    --show-error \
    --output "$PAGE_FILE" \
    --write-out '%{http_code}|%{url_effective}' \
    "$PAGE_URL")" || fail_run 'SmartPak authentication request failed.'

http_status="${get_result%%|*}"
final_url="${get_result#*|}"
[[ "$http_status" == '200' ]] || fail_run "SmartPak authentication failed. HTTP status=$http_status"

verification_token="$(/usr/bin/ruby -e '
  html = File.binread(ARGV[0])
  match = html.match(/name="__RequestVerificationToken"[^>]*value="([^"]+)"/i)
  abort "Verification token not found" unless match
  print match[1]
' "$PAGE_FILE" 2>/dev/null)" || fail_run 'The SmartPak verification token was not found.'

/usr/bin/grep -qi '/ProductPrice/Schedule' "$PAGE_FILE" || fail_run 'The expected SmartPak upload endpoint was not found.'

cookie_count="$(/usr/bin/awk '(/^#HttpOnly_/ || ($0 !~ /^#/ && NF >= 7)) { count++ } END { print count + 0 }' "$COOKIE_FILE")"
effective_date="$(/bin/date '+%Y-%m-%d')"
log_message INFO "SmartPak preflight passed. HTTP=$http_status, Cookies=$cookie_count, EffectiveDate=$effective_date, FinalUrl=$final_url"

if [[ "$MODE" == 'DryRun' ]]; then
    log_message INFO 'Dry run passed. Submission performed: No.'
    exit 0
fi

[[ -f "$PRODUCTION_FLAG" ]] || fail_run "Production upload is disabled. Missing flag: $PRODUCTION_FLAG"
flag_text="$(<"$PRODUCTION_FLAG")"
[[ "$flag_text" == "$PRODUCTION_FLAG_TEXT" ]] || fail_run 'Production upload flag content is invalid.'

PROCESSING_FILE="$PROCESSING/${INPUT_FILE:t}"
[[ ! -e "$PROCESSING_FILE" ]] || fail_run "Processing destination already exists: $PROCESSING_FILE"
/bin/mv "$INPUT_FILE" "$PROCESSING_FILE" || fail_run 'Unable to move the CSV into Processing.'
log_message INFO "Moved file to Processing: $PROCESSING_FILE"

print -rn -- "$verification_token" > "$TOKEN_FILE"
/bin/chmod 600 "$TOKEN_FILE"
SUBMISSION_ATTEMPTED='Yes'
log_message WARN "Submitting production upload: $PROCESSING_FILE"

post_result="$(curl_with_ntlm \
    --cookie "$COOKIE_FILE" \
    --cookie-jar "$COOKIE_FILE" \
    --location \
    --silent \
    --show-error \
    --output "$RESPONSE_FILE" \
    --write-out '%{http_code}|%{url_effective}' \
    --referer "$PAGE_URL" \
    --form "__RequestVerificationToken=<$TOKEN_FILE" \
    --form-string "ProductPriceChangeFileModel.EffectiveDate=$effective_date" \
    --form-string 'ProductPriceChangeFileModel.ProcessFrequently=true' \
    --form-string 'ProductPriceChangeFileModel.ProcessFrequently=false' \
    --form "file=@\"$PROCESSING_FILE\";type=text/csv" \
    "$UPLOAD_URL")" || fail_run 'SmartPak submission request failed. Verify the SmartPak UI before retrying.'

post_status="${post_result%%|*}"
post_url="${post_result#*|}"
[[ "$post_status" == '200' ]] || fail_run "SmartPak submission returned HTTP $post_status. Verify the SmartPak UI before retrying."

if /usr/bin/grep -Eqi 'validation-summary-errors|field-validation-error' "$RESPONSE_FILE"; then
    fail_run 'SmartPak returned a form-validation error. Review the saved response HTML.'
fi

archive_directory="$ARCHIVE_ROOT/$(/bin/date '+%Y-%m')"
/bin/mkdir -p "$archive_directory"
archive_path="$archive_directory/${INPUT_FILE:t}"
if [[ -e "$archive_path" ]]; then
    archive_path="$archive_directory/${INPUT_FILE:t:r}-$RUN_ID.${INPUT_FILE:e}"
fi

/bin/mv "$PROCESSING_FILE" "$archive_path" || fail_run 'SmartPak accepted the request, but the CSV could not be archived.'
PROCESSING_FILE=''

record_ledger \
    "${INPUT_FILE:t}" \
    "$FILE_HASH" \
    'Submitted' \
    "HTTP $post_status; FinalUrl=$post_url; Response=$RESPONSE_FILE"

log_message INFO "Submission accepted and file archived: $archive_path"

#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# --- Redirect stdout and stderr to screen and run.log file ---
LOG_FILE="run.log"
if [[ -t 1 ]]; then
    exec > >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
else
    exec >> "$LOG_FILE"
    exec 2>&1
fi

# --- Banner ---
cat << "EOF"
  █████████   ███   █████              ███████████  █████                            █████
  ███░░░░░███ ░░░   ░░███              ░░███░░░░░███░░███                            ░░███
 ███     ░░░  ████  ███████             ░███    ░███ ░███████    ██████   ████████   ███████    ██████  █████████████
░███         ░░███ ░░░███░              ░██████████  ░███░░███  ░░░░░███ ░░███░░███ ░░░███░    ███░░███░░███░░███░░███
░███    █████ ░███   ░███               ░███░░░░░░   ░███ ░███   ███████  ░███ ░███   ░███    ░███ ░███ ░███ ░███ ░███
░░███  ░░███  ░███   ░███ ███           ░███         ░███ ░███  ███░░███  ░███ ░███   ░███ ███░███ ░███ ░███ ░███ ░███
 ░░█████████  █████  ░░█████  █████████ █████        ████ █████░░████████ ████ █████  ░░█████ ░░██████  █████░███ █████
  ░░░░░░░░░  ░░░░░    ░░░░░  ░░░░░░░░░ ░░░░░        ░░░░ ░░░░░  ░░░░░░░░ ░░░░ ░░░░░    ░░░░░   ░░░░░░  ░░░░░ ░░░ ░░░░░

        By: @Ibraheem7304 and @MohamedAhmedGameel

EOF

echo "======================================================"
echo "Starting new scan run at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# --- Argument Parsing ---
INPUT_FILE=""
while getopts "t:" opt; do
  case $opt in
    t) INPUT_FILE="$OPTARG" ;;
    *) echo "Usage: $0 -t <input_file>"; exit 1 ;;
  esac
done

if [[ -z "$INPUT_FILE" ]]; then
    echo "Error: Input file is required. Usage: $0 -t <path_to_orgs_file>"
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: File '$INPUT_FILE' not found."
    exit 1
fi

# --- Logging Functions with Timestamps ---
_log_timestamp() { date '+%Y-%m-%d %H:%M:%S' || echo "NO_DATE"; }
info()  { printf '[%s] [*] %s\n' "$(_log_timestamp)" "$1"; }
good()  { printf '[%s] [+] %s\n' "$(_log_timestamp)" "$1"; }
warn()  { printf '[%s] [!] %s\n' "$(_log_timestamp)" "$1"; }
err()   { printf '[%s] [-] %s\n' "$(_log_timestamp)" "$1"; }

# --- Configuration ---
# REPLACE THESE PLACEHOLDERS WITH YOUR ACTUAL SECRETS BEFORE RUNNING
export GITHUB_TOKEN="YOUR_GITHUB_TOKEN_HERE"
export WEBHOOK_URL="YOUR_DISCORD_WEBHOOK_URL_HERE"

# Keywords for Trufflehog filtering (detector type only)
IGNORED_KEYWORDS=("openweather" "locationiq" "algolia" "ipdata" "unsplash" "ipinfo" "giphy" "etherscan" "infura" "alchemy" "moralis" "web3" "ethereum" "polygon" "binance" "smartcontract" "solana" "metamask" "ganache" "hardhat" "walletconnect" "crypto" "faucet" "bscscan" "coinmarketcap" "coingecko" "chainlink" "eth" "polygon-rpc" "infura.io" "alchemyapi.io" "nft" "opensea" "pinata" "ipfs" "p2p" "requestbin" "ngrok" "example.com" "localhost" "127.0.0.1" "demo" "test" "testing" "dummy" "public" "default" "canary" "honeybot")

# Prepare lowercase ignored keywords list once
LOWER_IGNORED_KEYWORDS=()
info "Processing ignored keywords list..."
for k in "${IGNORED_KEYWORDS[@]}"; do
    LOWER_IGNORED_KEYWORDS+=( "$(printf '%s' "$k" | tr '[:upper:]' '[:lower:]')" )
done
good "Ignored keywords list processed."

# Filter function
contains_ignored_keyword() {
    local input="$1"
    local lower_input
    lower_input=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' || true)
    local kw
    for kw in "${LOWER_IGNORED_KEYWORDS[@]}"; do
        if [[ -n "$kw" && "$lower_input" == *"$kw"* ]]; then return 0; fi # Match
    done
    return 1 # No match
}

# Check required commands
_required_cmds=(git gh jq trufflehog file strings sha1sum mktemp rm cp tar unzip unrar date tee basename xargs awk grep curl)
_missing=()
info "Checking required commands..."
for c in "${_required_cmds[@]}"; do
    if ! command -v "$c" >/dev/null 2>&1; then _missing+=( "$c" ); fi
done
if [ "${#_missing[@]}" -ne 0 ]; then warn "Missing commands: ${_missing[*]}. Script might fail."; else good "All required commands found."; fi

# Setup directories
BASE_DIR="$(pwd)"; SCAN_DIR="$BASE_DIR/Scanned_Organization"; BACKUP_DIR="$BASE_DIR/Scanned_Backup"
info "Creating directories..."; mkdir -p "$SCAN_DIR" "$BACKUP_DIR"; good "Directories ensured."

# Use array for temporary items, register cleanup
declare -a __TMP_ITEMS=()
cleanup_tmp_dirs() {
    info "Cleaning up temporary items at script exit..."
    local item_count="${#__TMP_ITEMS[@]}"
    if [[ $item_count -gt 0 ]]; then
        info "Attempting removal of $item_count items..."
        printf '%s\0' "${__TMP_ITEMS[@]}" | xargs -0 -r rm -rf -- || warn "Issues during cleanup."
        good "Cleanup attempt finished."
    else info "No temporary items registered."; fi
}
trap cleanup_tmp_dirs EXIT

# Scan archives & binaries (Trufflehog only)
process_extracted_and_binaries() {
    local target_dir="$1"; local context_name="$2"; local base_source_desc="$3"
    local extract_root; local archives_dir; local strings_dir; local f; local rel; local f_hash; local dest
    local bf; local ftype; local hash_part; local rel_path; local safe_rel_path; local outtxt
    local tr_json; local tr_human

    info "[$context_name] Starting extra scan (archives/binaries)..."
    extract_root="$(mktemp -d)"; __TMP_ITEMS+=("$extract_root")

    # Archive Extraction
    archives_dir="$extract_root/archives"
    while IFS= read -r -d $'\0' f; do
        rel="$(basename "$f")" || continue; f_hash=$(printf '%s' "$f" | sha1sum | awk '{print $1}') || continue
        dest="$archives_dir/${f_hash}_${rel%.*}_extracted"; mkdir -p "$dest"
        case "${f,,}" in
            *.zip) if command -v unzip >/dev/null; then unzip -qq -n "$f" -d "$dest" < /dev/null || warn "... zip fail: $f (might be corrupt/password-protected)"; else warn "... unzip missing"; fi ;;
            *.rar) if command -v unrar >/dev/null; then unrar x -inul -o+ -p- "$f" "$dest/" || warn "... rar fail: $f (might be corrupt/password-protected)"; else warn "... unrar missing"; fi ;;
            *.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz) tar -xf "$f" -C "$dest" 2>/dev/null || warn "... tar fail: $f" ;;
            *.7z) if command -v 7z >/dev/null; then 7z x -y -p"" -o"$dest" "$f" >/dev/null 2>&1 || warn "... 7z fail: $f (might be corrupt/password-protected)"; else warn "... 7z missing"; fi ;;
            *) warn "[$context_name] Unsup archive: $f"; rmdir "$dest" 2>/dev/null || true ;;
        esac
    done < <(find "$target_dir" -path "$target_dir/.git" -prune -o -type f \( -iname "*.zip" -o -iname "*.rar" -o -iname "*.tar" -o -iname "*.tar.gz" -o -iname "*.tgz" -o -iname "*.tar.bz2" -o -iname "*.tbz2" -o -iname "*.tar.xz" -o -iname "*.txz" -o -iname "*.7z" \) -print0 2>/dev/null || true)

    # Binary Strings Extraction
    strings_dir="$extract_root/binaries_strings"; mkdir -p "$strings_dir"
    while IFS= read -r -d $'\0' bf; do
        if [[ ! -f "$bf" || ! -s "$bf" ]]; then continue; fi
        ftype=$(file -b --mime-type "$bf" 2>/dev/null || echo "unknown")
        if echo "$ftype" | grep -Eq '^(text/|application/(x-)?(javascript|ecmascript|xml|json|x-sh|x-yaml|toml))'; then continue; fi
        hash_part=$(printf '%s' "$bf" | sha1sum | awk '{print $1}') || continue; rel_path="${bf#$target_dir/}"
        safe_rel_path=$(printf '%s' "$rel_path" | tr '/' '_' | tr -cd '[:alnum:]_.-'); outtxt="$strings_dir/${hash_part}_${safe_rel_path}.txt"
        if command -v strings >/dev/null; then
            strings -a -n 8 "$bf" > "$outtxt" || warn "... strings fail: $bf"
            [[ ! -s "$outtxt" ]] && rm -f -- "$outtxt"
        else warn "... strings missing!"; break; fi
    done < <(find "$target_dir" -path "$target_dir/.git" -prune -o -type f -print0 2>/dev/null || true)

    # Scan Extracted Content
    if [ -d "$archives_dir" ] && find "$archives_dir" -mindepth 1 -print -quit | grep -q .; then
        info "[$context_name] Running Trufflehog (archives)..."
        tr_json=$(trufflehog filesystem "$archives_dir" --no-update --only-verified --json 2>/dev/null || echo "")
        tr_human=$(trufflehog filesystem "$archives_dir" --no-update --only-verified 2>/dev/null || echo "")
        process_truffle_json "$tr_json" "$base_source_desc (extracted archives)" "$context_name" "$tr_human"
    fi

    if [ -d "$strings_dir" ] && find "$strings_dir" -mindepth 1 -print -quit | grep -q .; then
        info "[$context_name] Running Trufflehog (binary strings)..."
        tr_json=$(trufflehog filesystem "$strings_dir" --no-update --only-verified --json 2>/dev/null || echo "")
        tr_human=$(trufflehog filesystem "$strings_dir" --no-update --only-verified 2>/dev/null || echo "")
        process_truffle_json "$tr_json" "$base_source_desc (binary-strings)" "$context_name" "$tr_human"
    fi

    good "[$context_name] Finished extra scan."
}


# --- Processing Function (Trufflehog Only) ---
process_truffle_json() {
    local json_blob="$1"; local source_desc="$2"; local context_name="$3"; local human_output="$4"
    local count=0; local ignored_count=0; local processed_count=0
    local -a ITEMS; local item; local DETECTOR_TYPE; local SECRET_VALUE; local FILE_FIELD; local webhook_payload
    local appended_human_output=false

    [[ -z "${json_blob:-}" || "$json_blob" == "null" || "$json_blob" == "[]" ]] && return 0
    if ! jq -e . >/dev/null 2>&1 <<<"$json_blob"; then warn "[$context_name] Invalid Trufflehog JSON ($source_desc). Skipping."; return 0; fi

    mapfile -t ITEMS < <(printf '%s\n' "$json_blob" | jq -c 'if type=="array" then .[] else (if . == null then empty else . end) end // ""' 2>/dev/null || printf '')

    for item in "${ITEMS[@]}"; do
        [[ -z "$item" ]] && continue; count=$((count + 1))
        DETECTOR_TYPE=$(printf '%s' "$item" | jq -r '.DetectorName // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
        SECRET_VALUE=$(printf '%s' "$item" | jq -r '.Raw // empty' 2>/dev/null || echo "")
        FILE_FIELD=$(printf '%s' "$item" | jq -r '.SourceMetadata.Data.Git.file // .FilePath // .File // "<no file info>"' 2>/dev/null || echo "<no file info>")
        [[ -z "$SECRET_VALUE" ]] && { ignored_count=$((ignored_count + 1)); continue; }

        if contains_ignored_keyword "$DETECTOR_TYPE" ; then
            info "[$context_name] Ignored Trufflehog (detector type): '$DETECTOR_TYPE' in file '$FILE_FIELD'"
            ignored_count=$((ignored_count + 1)); continue
        fi

        processed_count=$((processed_count + 1))
        good "[$context_name] Found valid Trufflehog secret (#$processed_count): Type='$DETECTOR_TYPE', File='$FILE_FIELD', Source='$source_desc'"

        if [[ "$appended_human_output" = false && -n "$human_output" ]]; then
            info "[$context_name] Appending Trufflehog block to $TRUFFLE_FILE"
            printf "=== Findings in %s (%s) ===\n\n%s\n\n" "$context_name" "$source_desc" "$human_output" >> "$TRUFFLE_FILE" || warn "[$context_name] Failed write human output to $TRUFFLE_FILE"
            appended_human_output=true
        fi

        info "[$context_name] Sending Discord notification..."
        webhook_payload="$(jq -n --arg a "**[SECRET - Trufflehog]** Found in: \`$context_name\`" --arg b "**Type**: ${DETECTOR_TYPE:-<unknown>}" --arg f "**File**: ${FILE_FIELD:-<unknown>}" --arg c "**Value**: \`$SECRET_VALUE\`" --arg d "**Source**: $source_desc" '{content: ($a + "\n" + $b + "\n" + $f + "\n" + $c + "\n" + $d)}')"
        curl -s --max-time 10 -X POST -H "Content-Type: application/json" -d "$webhook_payload" "$WEBHOOK_URL" > /dev/null || warn "[$context_name] Failed sending Discord notification."
    done
    if (( count > 0 )); then info "[$context_name] Finished Trufflehog processing ($source_desc): Total $count, Ignored $ignored_count, Reported $processed_count."; fi
}


# --- Main Execution Block ---
info "Starting GitHub secrets scanning..."

info "Reading organizations from $INPUT_FILE...";
mapfile -t ORGS < <(grep -v '^\s*#' "$INPUT_FILE" | grep -v '^\s*$' | tr -d '\r' | xargs -n1 || true)
good "Found ${#ORGS[@]} organization(s)."

org_scan_count=0
ORG_NAME=""; org_scan_dir=""; TRUFFLE_FILE=""; repos_raw=""
declare -a REPOS=(); repo_count=0

for ORG_NAME in "${ORGS[@]}"; do
    org_scan_count=$((org_scan_count + 1))
    info "==================== Starting scan: $ORG_NAME (#$org_scan_count/${#ORGS[@]}) ===================="
    info "[$ORG_NAME] Sending START notification..."
    curl -s --max-time 10 -X POST -H "Content-Type: application/json" -d "{\"content\": \"**[START]** Scanning: \`$ORG_NAME\`\"}" "$WEBHOOK_URL" > /dev/null || warn "... Discord START failed."

    org_scan_dir="$SCAN_DIR/$ORG_NAME"; mkdir -p "$org_scan_dir"
    TRUFFLE_FILE="$org_scan_dir/trufflehog_secrets.txt"
    info "[$ORG_NAME] Trufflehog file: $TRUFFLE_FILE"
    > "$TRUFFLE_FILE" || { err "Cannot write $TRUFFLE_FILE. Skipping org."; continue; }

    # --- Repository Scanning (Excluding Forks) ---
    info "[$ORG_NAME] Fetching repository list (excluding forks)...";
    # Filter to ensure only non-fork repositories are scanned
    repos_raw=$(gh repo list "$ORG_NAME" -L 1000 --json name,isFork --jq '.[] | select(.isFork == false) | .name' 2>/dev/null || { warn "... 'gh repo list' failed."; echo ""; })

    REPOS=(); if [[ -n "$repos_raw" ]]; then IFS=$'\n' read -r -d '' -a REPOS < <(printf '%s\0' "$repos_raw"); good "Found ${#REPOS[@]} non-fork repositories."; else info "No non-fork repositories found."; fi

    repo_count=0
    repo=""; CURRENT_CONTEXT=""; tmp_clone_dir=""; clone_target=""; analysis_dir=""; deleted_dir=""
    deleted_file_count=0; declare -a COMMITS=(); commit_processed_count=0; MAX_FILENAME_LEN=240
    commit=""; parent_commit=""; status=""; file=""; file_path_hash=""; original_basename=""
    safe_basename=""; base_out_file=""; out_file=""; show_exit_code=0
    CURRENT_RESULT_JSON=""; CURRENT_RESULT_HUMAN=""; DELETED_RESULT_JSON=""; DELETED_RESULT_HUMAN=""
    delay=0

    for repo in "${REPOS[@]}"; do
        [[ -z "$repo" ]] && continue; repo_count=$((repo_count + 1)); CURRENT_CONTEXT="$ORG_NAME/$repo"
        info "[$CURRENT_CONTEXT] --- Repo Scan #$repo_count/${#REPOS[@]} ---"

        tmp_clone_dir="$(mktemp -d)"; __TMP_ITEMS+=("$tmp_clone_dir")
        clone_target="$tmp_clone_dir/$repo"
        info "[$CURRENT_CONTEXT] Cloning..."
        if ! git clone --quiet "https://github.com/$ORG_NAME/$repo.git" "$clone_target" 2>/dev/null; then warn "Clone failed. Skipping."; continue; fi
        if ! cd "$clone_target"; then warn "Failed cd. Skipping."; cd "$BASE_DIR" || exit 1; continue; fi
        git fetch --all --tags --quiet || warn "Fetch failed."

        # Deleted File Extraction
        info "[$CURRENT_CONTEXT] Extracting deleted files..."; analysis_dir="$(mktemp -d)"; __TMP_ITEMS+=("$analysis_dir")
        deleted_dir="$analysis_dir/deleted"; mkdir -p "$deleted_dir"
        deleted_file_count=0; mapfile -t COMMITS < <(git log --pretty=format:'%H' --all 2>/dev/null || true); commit_processed_count=0;
        info "[$CURRENT_CONTEXT] Processing ${#COMMITS[@]} commits..."
        for commit in "${COMMITS[@]}"; do
            [[ -z "$commit" ]] && continue; commit_processed_count=$((commit_processed_count + 1))
            if (( commit_processed_count % 1000 == 0 )); then info "... processed $commit_processed_count/${#COMMITS[@]} commits..."; fi
            parent_commit=$(git log --pretty=format:"%P" -n 1 "$commit" 2>/dev/null | awk '{print $1}' || true); [[ -z "$parent_commit" ]] && continue
            while IFS=$'\t' read -r status file || [[ -n "$status" ]]; do
                status=$(printf '%s' "$status" | xargs); file=$(printf '%s' "$file" | xargs); [[ -z "$status" || -z "$file" ]] && continue
                if [ "$status" = "D" ]; then
                    file_path_hash=$(printf '%s' "$file" | sha1sum | awk '{print $1}') || continue; original_basename=$(basename -- "$file") || continue
                    safe_basename=$(printf '%s' "$original_basename" | tr -cd '[:alnum:]_.-'); base_out_file="${commit:0:12}_${file_path_hash:0:12}_${safe_basename}.deleted"
                    if (( ${#base_out_file} > MAX_FILENAME_LEN )); then
                        excess=$(( ${#base_out_file} - MAX_FILENAME_LEN )); basename_len=${#safe_basename}; new_basename_len=$(( basename_len > excess ? basename_len - excess : 0 )); [[ $new_basename_len -lt 5 && $basename_len -gt 0 ]] && new_basename_len=5
                        safe_basename=${safe_basename:0:$new_basename_len}; base_out_file="${commit:0:12}_${file_path_hash:0:12}_${safe_basename}.deleted"
                    fi
                    out_file="$deleted_dir/$base_out_file"; set +e; git show "$parent_commit:$file" > "$out_file" 2>/dev/null; show_exit_code=$?; set -e
                    if [[ $show_exit_code -eq 0 ]]; then [[ ! -s "$out_file" ]] && rm -f -- "$out_file" || deleted_file_count=$((deleted_file_count + 1)); else rm -f -- "$out_file"; fi
                fi
            done < <(git diff --name-status "$parent_commit" "$commit" 2>/dev/null || true)
        done
        good "[$CURRENT_CONTEXT] Deleted extraction complete ($deleted_file_count contents)."

        # Run Extra Scans (Archives/Binaries outside .git)
        info "[$CURRENT_CONTEXT] Running extra scans (archives/binaries)..."
        process_extracted_and_binaries "$clone_target" "$CURRENT_CONTEXT" "repo"

        # Run Primary Scan
        info "[$CURRENT_CONTEXT] Running Trufflehog (full repo scan)..."
        CURRENT_RESULT_JSON=$(trufflehog git "file://$PWD" --no-update --only-verified --json 2>/dev/null || { warn "... Trufflehog git scan failed."; echo ""; })
        CURRENT_RESULT_HUMAN=$(trufflehog git "file://$PWD" --no-update --only-verified 2>/dev/null || { warn "... Trufflehog git (human) failed."; echo ""; })
        process_truffle_json "$CURRENT_RESULT_JSON" "repo (full history scan)" "$CURRENT_CONTEXT" "$CURRENT_RESULT_HUMAN"

        # Scan Deleted Files
        if [ -d "$deleted_dir" ] && find "$deleted_dir" -mindepth 1 -print -quit | grep -q .; then
            info "[$CURRENT_CONTEXT] Running Trufflehog (deleted files)..."
            DELETED_RESULT_JSON=$(trufflehog filesystem "$deleted_dir" --no-update --only-verified --json 2>/dev/null || { warn "... Trufflehog deleted failed."; echo ""; })
            DELETED_RESULT_HUMAN=$(trufflehog filesystem "$deleted_dir" --no-update --only-verified 2>/dev/null || { warn "... Trufflehog deleted (human) failed."; echo ""; })
            process_truffle_json "$DELETED_RESULT_JSON" "deleted files" "$CURRENT_CONTEXT" "$DELETED_RESULT_HUMAN"
        else info "[$CURRENT_CONTEXT] No deleted content to scan."; fi

        cd "$BASE_DIR" || { err "CRITICAL: Failed cd to base dir. Exiting."; exit 1; }
        delay=$(( ( RANDOM % 11 ) + 5 )); info "[$CURRENT_CONTEXT] --- Finished repo scan. Sleeping ${delay}s... ---"; sleep $delay
    done # End repo loop
    good "[$ORG_NAME] Finished repo scan loop (${repo_count})."

    good "==================== Finished scan: $ORG_NAME ===================="
    printf "\n"
    info "[$ORG_NAME] Brief pause..."
    sleep 5
done # End organization loop
good "Finished all ${org_scan_count} organization(s) cycle."

# --- Backup and Cleanup ---
info "Starting backup and cleanup..."; TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
if [ -d "$SCAN_DIR" ] && find "$SCAN_DIR" -mindepth 1 -print -quit | grep -q .; then
    backup_target="$BACKUP_DIR/Backup_$TIMESTAMP"; info "Results found. Backing up to $backup_target..."
    mkdir -p "$backup_target" || { err "Failed backup dir creation. Skipping backup/cleanup."; }
    if cp -a "$SCAN_DIR/." "$backup_target/"; then
        good "Backup successful."
        info "Clearing scan directory: $SCAN_DIR"
        find "$SCAN_DIR/" -mindepth 1 -maxdepth 1 -type d -exec rm -rf -- {} + || warn "Issues during cleanup."
        if find "$SCAN_DIR" -mindepth 1 -print -quit | grep -q .; then warn "$SCAN_DIR not fully cleared!"; else good "Scan directory cleared."; fi
    else err "Backup failed! Scan directory NOT CLEARED."; fi
else info "Scan directory empty. No backup needed."; fi
good "Backup and cleanup finished."

info "Sending COMPLETE notification..."
curl -s --max-time 10 -X POST -H "Content-Type: application/json" -d '{"content": "**[COMPLETE]** Scan cycle done. Exiting."}' "$WEBHOOK_URL" > /dev/null || warn "Failed COMPLETE notification."

info "Script finished."
exit 0

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

echo "======================================================"
echo "Starting new scan run at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# --- Logging Functions with Timestamps ---
_log_timestamp() { date '+%Y-%m-%d %H:%M:%S' || echo "NO_DATE"; }
info()  { printf '[%s] [*] %s\n' "$(_log_timestamp)" "$1"; }
good()  { printf '[%s] [+] %s\n' "$(_log_timestamp)" "$1"; }
warn()  { printf '[%s] [!] %s\n' "$(_log_timestamp)" "$1"; }
err()   { printf '[%s] [-] %s\n' "$(_log_timestamp)" "$1"; }

# --- Main Execution Block ---
echo ""
echo "   █████████   ███   █████       ███████████  █████                            █████                            "
echo "  ███░░░░░███ ░░░   ░░███       ░░███░░░░░███░░███                            ░░███                             "
echo " ███     ░░░  ████  ███████      ░███    ░███ ░███████    ██████   ████████   ███████    ██████  █████████████  "
echo "░███         ░░███ ░░░███░       ░██████████  ░███░░███  ░░░░░███ ░░███░░███ ░░░███░    ███░░███░░███░░███░░███ "
echo "░███    █████ ░███   ░███        ░███░░░░░░   ░███ ░███   ███████  ░███ ░███   ░███    ░███ ░███ ░███ ░███ ░███ "
echo "░░███  ░░███  ░███   ░███ ███    ░███         ░███ ░███  ███░░███  ░███ ░███   ░███ ███░███ ░███ ░███ ░███ ░███ "
echo " ░░█████████  █████  ░░█████     █████        ████ █████░░████████ ████ █████  ░░█████ ░░██████  █████░███ █████"
echo "  ░░░░░░░░░  ░░░░░    ░░░░░     ░░░░░        ░░░░ ░░░░░  ░░░░░░░░ ░░░░ ░░░░░    ░░░░░   ░░░░░░  ░░░░░ ░░░ ░░░░░ "
echo ""
echo "# By: @Ibraheem7304 and @MohamedAhmedGameel"
echo ""

ORG_INPUT_FILE=""
SCRIPT_NAME=$(basename "$0")

usage() {
    err "Usage: ./$SCRIPT_NAME -f <path_to_organization_list_file>"
    err "Example: ./$SCRIPT_NAME -f targets.txt"
    exit 1
}

while getopts "f:" opt; do
    case "$opt" in
        f) ORG_INPUT_FILE="$OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "$ORG_INPUT_FILE" ]; then
    warn "Input file path must be specified using the -f option."
    usage
fi

if [ ! -f "$ORG_INPUT_FILE" ]; then
    err "Input file '$ORG_INPUT_FILE' not found! Exiting.";
    usage
fi

good "Using organization list from: $ORG_INPUT_FILE"

# --- Configuration ---
# REPLACE THESE PLACEHOLDERS WITH YOUR ACTUAL SECRETS BEFORE RUNNING
export GITHUB_TOKEN="YOUR_GITHUB_TOKEN"
export WEBHOOK_URL="YOUR_DISCORD_WEBHOOK"

# Keywords for Trufflehog filtering (detector type only)
IGNORED_KEYWORDS=("openweather" "locationiq" "algolia" "ipdata" "unsplash" "ipinfo" "giphy" "etherscan" "infura" "alchemy" "moralis" "web3" "ethereum" "polygon" "binance" "smartcontract" "solana" "metamask" "ganache" "hardhat" "walletconnect" "crypto" "faucet" "bscscan" "coinmarketcap" "coingecko" "chainlink" "eth" "polygon-rpc" "infura.io" "alchemyapi.io" "nft" "opensea" "pinata" "ipfs" "p2p" "requestbin" "ngrok" "example.com" "localhost" "127.0.0.1" "demo" "test" "testing" "dummy" "public" "default")

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

# Scan Dangling Blobs (Trufflehog Only)
scan_dangling_objects() {
    local context_name="$1"
    local dangling_dir; local blob_sha; local tr_json; local tr_human; local cat_ec

    info "[$context_name] Searching for dangling/unreachable blob objects..."
    dangling_dir="$(mktemp -d)"; __TMP_ITEMS+=("$dangling_dir")

    local dangling_count=0
    while IFS= read -r blob_sha || [[ -n "$blob_sha" ]]; do
        if [[ -n "$blob_sha" ]]; then
            set +e; git cat-file -p "$blob_sha" > "$dangling_dir/$blob_sha.blob" 2>/dev/null; cat_ec=$?; set -e
            if [[ $cat_ec -eq 0 && -s "$dangling_dir/$blob_sha.blob" ]]; then
                dangling_count=$((dangling_count + 1))
            else
                rm -f -- "$dangling_dir/$blob_sha.blob" 2>/dev/null || true
            fi
        fi
    done < <(git fsck --full --unreachable --dangling --no-reflogs 2>/dev/null | grep 'unreachable blob' | awk '{print $3}' || true)

    if [[ $dangling_count -gt 0 ]]; then
        good "[$context_name] Extracted $dangling_count dangling blob contents. Scanning..."
        tr_json=$(trufflehog filesystem "$dangling_dir" --no-update --only-verified --json 2>/dev/null || echo "")
        tr_human=$(trufflehog filesystem "$dangling_dir" --no-update --only-verified 2>/dev/null || echo "")
        process_truffle_json "$tr_json" "dangling blobs" "$context_name" "$tr_human"
        good "[$context_name] Finished scanning dangling blobs."
    else
        info "[$context_name] No reachable dangling blob contents found."
    fi
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
info "Reading organizations from $ORG_INPUT_FILE...";
mapfile -t ORGS < <(grep -v '^\s*#' "$ORG_INPUT_FILE" | grep -v '^\s*$' | tr -d '\r' | xargs -n1 || true)
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
    delay=0; packfile=""; unpack_ec=0

    for repo in "${REPOS[@]}"; do
        [[ -z "$repo" ]] && continue; repo_count=$((repo_count + 1)); CURRENT_CONTEXT="$ORG_NAME/$repo"
        info "[$CURRENT_CONTEXT] --- Repo Scan #$repo_count/${#REPOS[@]} ---"

        tmp_clone_dir="$(mktemp -d)"; __TMP_ITEMS+=("$tmp_clone_dir")
        clone_target="$tmp_clone_dir/$repo"
        info "[$CURRENT_CONTEXT] Cloning..."
        if ! git clone --quiet "https://github.com/$ORG_NAME/$repo.git" "$clone_target" 2>/dev/null; then warn "Clone failed. Skipping."; continue; fi
        if ! cd "$clone_target"; then warn "Failed cd. Skipping."; cd "$BASE_DIR" || exit 1; continue; fi
        git fetch --all --tags --quiet || warn "Fetch failed."

        # Unpack Packfiles
        info "[$CURRENT_CONTEXT] Attempting to unpack .pack files..."
        pack_count=0
        if [ -d ".git/objects/pack" ]; then
            find ".git/objects/pack" -type f -name '*.pack' -print0 | while IFS= read -r -d $'\0' packfile; do
                pack_count=$((pack_count + 1))
                info "[$CURRENT_CONTEXT] Unpacking packfile: $packfile"
                set +e; git unpack-objects < "$packfile" > /dev/null 2>&1; unpack_ec=$?; set -e # Hide output
                if [[ $unpack_ec -ne 0 ]]; then warn "[$CURRENT_CONTEXT] Failed unpack '$packfile' (code $unpack_ec)."; fi
            done
            good "[$CURRENT_CONTEXT] Finished unpacking $pack_count packfile(s)."
        else info "[$CURRENT_CONTEXT] No .git/objects/pack directory."; fi

        # Scan Dangling Blobs
        scan_dangling_objects "$CURRENT_CONTEXT"

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

    # --- Gist Scanning ---
    info "[$ORG_NAME] Fetching Gist list (API)..."
    gists_raw=""; gh_exit_code=0; declare -a GISTS=(); gist_count=0; gist_id=""; tmp_gist_dir=""
    GIST_TRUFFLE_JSON=""; GIST_TRUFFLE_HUMAN=""; delay=0
    set +e; gists_raw=$(gh api --paginate "/gists?per_page=100" --jq '.[] | select(.id != null) | .id' 2>&1); gh_exit_code=$?; set -e
    if [[ $gh_exit_code -ne 0 ]]; then warn "'gh api /gists' failed:\n$gists_raw"; gists_raw="";
    elif [[ -z "$gists_raw" ]]; then info "No gists found."; gists_raw="";
    else if ! printf '%s\n' "$gists_raw" | grep -qE '^[0-9a-f]+$'; then warn "'gh api /gists' invalid output: $gists_raw"; gists_raw=""; else good "Gist list fetched."; fi; fi
    if [[ -n "$gists_raw" ]]; then IFS=$'\n' read -r -d '' -a GISTS < <(printf '%s\0' "$gists_raw"); info "Found ${#GISTS[@]} Gists."; fi

    for gist_id in "${GISTS[@]}"; do
        if ! [[ "$gist_id" =~ ^[0-9a-f]+$ ]]; then warn "Invalid Gist ID '$gist_id'. Skipping."; continue; fi
        gist_count=$((gist_count + 1)); CURRENT_CONTEXT="gist:$gist_id"
        info "[$CURRENT_CONTEXT] --- Gist Scan #$gist_count/${#GISTS[@]} ---"
        tmp_gist_dir="$(mktemp -d)"; __TMP_ITEMS+=("$tmp_gist_dir")
        if ! gh gist clone "$gist_id" "$tmp_gist_dir" > /dev/null 2>&1; then warn "Gist clone failed. Skipping."; continue; fi

        info "[$CURRENT_CONTEXT] Running extra scans..."
        process_extracted_and_binaries "$tmp_gist_dir" "$CURRENT_CONTEXT" "gist"

        info "[$CURRENT_CONTEXT] Running Trufflehog (gist filesystem)..."
        GIST_TRUFFLE_JSON=$(trufflehog filesystem "$tmp_gist_dir" --no-update --only-verified --json 2>/dev/null || { warn "... Trufflehog scan failed."; echo ""; })
        GIST_TRUFFLE_HUMAN=$(trufflehog filesystem "$tmp_gist_dir" --no-update --only-verified 2>/dev/null || { warn "... Trufflehog (human) failed."; echo ""; })
        process_truffle_json "$GIST_TRUFFLE_JSON" "gist content" "$CURRENT_CONTEXT" "$GIST_TRUFFLE_HUMAN"

        delay=$(( ( RANDOM % 6 ) + 2 )); info "[$CURRENT_CONTEXT] --- Finished gist scan. Sleeping ${delay}s... ---"; sleep $delay
    done # End Gist loop
    good "[$ORG_NAME] Finished gist scan loop (${gist_count})."

    # --- Issue Scanning ---
    info "[$ORG_NAME] Fetching Issues (limit 100)..."
    issues_raw=""; gh_exit_code=0; declare -a ISSUES=(); issue_count=0; issue=""; body=""; url=""; issue_num=""; CONTEXT_NAME=""
    issue_temp=""; ISSUE_TRUFFLE_JSON=""; ISSUE_TRUFFLE_HUMAN=""
    set +e; issues_raw=$(gh search issues --owner "$ORG_NAME" --json number,body,url --limit 100 2>&1); gh_exit_code=$?; set -e
    if [[ $gh_exit_code -ne 0 ]]; then warn "'gh search issues' failed:\n$issues_raw"; issues_raw="";
    elif [[ -z "$issues_raw" || "$issues_raw" == "[]" ]]; then info "No issues found."; issues_raw="";
    else if ! jq -e . >/dev/null 2>&1 <<<"$issues_raw"; then warn "'gh search issues' invalid JSON: $issues_raw"; issues_raw=""; else good "Issues fetched."; fi; fi
    if [[ -n "$issues_raw" ]]; then mapfile -t ISSUES < <(printf '%s\n' "$issues_raw" | jq -c '.[]' 2>/dev/null || true); info "Found ${#ISSUES[@]} issues."; fi

    for issue in "${ISSUES[@]}"; do
        [[ -z "$issue" ]] && continue; issue_count=$((issue_count + 1))
        body=$(printf '%s' "$issue" | jq -r '.body // empty' 2>/dev/null || echo ""); url=$(printf '%s' "$issue" | jq -r '.url // empty' 2>/dev/null || echo ""); issue_num=$(printf '%s' "$issue" | jq -r '.number // empty' 2>/dev/null || echo "unknown"); CONTEXT_NAME="$ORG_NAME/issue (#${issue_num})"
        if [[ -z "$body" ]]; then info "[$CONTEXT_NAME] Skipping empty body."; continue; fi
        info "[$CONTEXT_NAME] --- Scanning issue #$issue_count/${#ISSUES[@]} ---"
        issue_temp="$(mktemp)"; __TMP_ITEMS+=("$issue_temp")
        printf '%s\n' "$body" > "$issue_temp"

        info "[$CONTEXT_NAME] Running Trufflehog (issue body)..."
        ISSUE_TRUFFLE_JSON=$(trufflehog filesystem "$issue_temp" --no-update --only-verified --json 2>/dev/null || { warn "... Trufflehog scan failed."; echo ""; })
        ISSUE_TRUFFLE_HUMAN=$(trufflehog filesystem "$issue_temp" --no-update --only-verified 2>/dev/null || { warn "... Trufflehog (human) failed."; echo ""; })
        process_truffle_json "$ISSUE_TRUFFLE_JSON" "issue body" "$CONTEXT_NAME" "$ISSUE_TRUFFLE_HUMAN"

        info "[$CONTEXT_NAME] --- Finished issue scan ---"
    done # End Issue loop
    good "[$ORG_NAME] Finished issue scan loop (${issue_count})."

    # --- Pull Request Scanning ---
    info "[$ORG_NAME] Fetching Pull Requests (limit 100)..."
    prs_raw=""; gh_exit_code=0; declare -a PRS=(); pr_count=0; pr=""; body=""; url=""; pr_num=""; CONTEXT_NAME=""
    pr_temp=""; PR_TRUFFLE_JSON=""; PR_TRUFFLE_HUMAN=""
    set +e; prs_raw=$(gh search prs --owner "$ORG_NAME" --json number,body,url --limit 100 2>&1); gh_exit_code=$?; set -e
    if [[ $gh_exit_code -ne 0 ]]; then warn "'gh search prs' failed:\n$prs_raw"; prs_raw="";
    elif [[ -z "$prs_raw" || "$prs_raw" == "[]" ]]; then info "No PRs found."; prs_raw="";
    else if ! jq -e . >/dev/null 2>&1 <<<"$prs_raw"; then warn "'gh search prs' invalid JSON: $prs_raw"; prs_raw=""; else good "PRs fetched."; fi; fi
    if [[ -n "$prs_raw" ]]; then mapfile -t PRS < <(printf '%s\n' "$prs_raw" | jq -c '.[]' 2>/dev/null || true); info "Found ${#PRS[@]} PRs."; fi

    for pr in "${PRS[@]}"; do
        [[ -z "$pr" ]] && continue; pr_count=$((pr_count + 1))
        body=$(printf '%s' "$pr" | jq -r '.body // empty' 2>/dev/null || echo ""); url=$(printf '%s' "$pr" | jq -r '.url // empty' 2>/dev/null || echo ""); pr_num=$(printf '%s' "$pr" | jq -r '.number // empty' 2>/dev/null || echo "unknown"); CONTEXT_NAME="$ORG_NAME/PR (#${pr_num})"
        if [[ -z "$body" ]]; then info "[$CONTEXT_NAME] Skipping empty body."; continue; fi
        info "[$CURRENT_CONTEXT] --- Scanning PR #$pr_count/${#PRS[@]} ---"
        pr_temp="$(mktemp)"; __TMP_ITEMS+=("$pr_temp")
        printf '%s\n' "$body" > "$pr_temp"

        info "[$CURRENT_CONTEXT] Running Trufflehog (PR body)..."
        PR_TRUFFLE_JSON=$(trufflehog filesystem "$pr_temp" --no-update --only-verified --json 2>/dev/null || { warn "... Trufflehog scan failed."; echo ""; })
        PR_TRUFFLE_HUMAN=$(trufflehog filesystem "$pr_temp" --no-update --only-verified 2>/dev/null || { warn "... Trufflehog (human) failed."; echo ""; })
        process_truffle_json "$PR_TRUFFLE_JSON" "pull request body" "$CURRENT_CONTEXT" "$PR_TRUFFLE_HUMAN"

        info "[$CURRENT_CONTEXT] --- Finished PR scan ---"
    done # End PR loop
    good "[$ORG_NAME] Finished PR scan loop (${pr_count})."

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

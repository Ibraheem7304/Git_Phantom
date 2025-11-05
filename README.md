# 🛡️ Git Phantom

A powerful Bash script designed to aggressively scan GitHub organizations for hardcoded secrets, API keys, and credentials across various vectors, including **repositories**, **dangling Git objects**, **deleted files**, **Gists**, **Issue bodies**, and **Pull Request bodies**.

This script leverages `trufflehog` for deep scanning and utilizes `git`, `gh (GitHub CLI)`, and other standard tools for data extraction and processing. Notifications for discovered secrets are sent directly to a configured **Discord webhook**.

## ✨ Features

* **Deep Repository Scanning:** Uses `trufflehog git` for full history analysis of non-fork repositories.
* **Dangling Blob Analysis:** Extracts and scans unreachable Git blob objects for forgotten secrets.
* **Deleted File Recovery:** Scrapes commit history to recover and scan the content of files that were deleted in subsequent commits.
* **Archive & Binary String Extraction:** Attempts to unpack archives (`.zip`, `.tar`, etc.) and extracts strings from binary files within the repo for extra scanning.
* **Content Scanning:** Searches **Gists**, **Issue Bodies**, and **Pull Request Bodies** for secrets.
* **Discord Notifications:** Immediately notifies a specified webhook upon finding a valid secret.
* **Configurable Ignored Keywords:** Filters out common false positives (e.g., crypto, demo, test keys) using a customizable keyword list.
* **Robust Logging:** Detailed timestamped logs are written to both the screen and a `run.log` file.
* **Automatic Cleanup:** Manages temporary directories and files using `trap` for reliable cleanup upon exit.
* **Results Backup:** Scanned results are backed up before clearing the primary scan directory.

---

## ⚙️ Prerequisites

Before running the script, ensure you have the following tools installed and configured:

| Tool | Purpose | Installation Check |
| :--- | :--- | :--- |
| **Bash** | Script execution environment | `bash --version` |
| **Trufflehog** | Primary secrets scanning engine | `trufflehog version` |
| **GitHub CLI (`gh`)** | Accessing GitHub repositories, Gists, Issues, and PRs | `gh --version` |
| **`git`** | Repository cloning and history inspection | `git --version` |
| **`jq`** | JSON processing for Trufflehog results and API calls | `jq --version` |
| **`unzip`, `unrar`, `tar`, `7z` (optional)** | Archive extraction for deeper scanning | `command -v unzip` (etc.) |
| **Standard Tools** | `file`, `strings`, `sha1sum`, `mktemp`, `curl`, etc. | |

### 🔑 GitHub CLI Setup

The script uses `gh` for accessing organization data, Gists, Issues, and PRs. You must be authenticated and have the necessary scopes.

1.  **Install `gh`** (if not already done).
2.  **Authenticate:**
    ```bash
    gh auth login
    ```
    * Choose **GitHub.com** and log in via your web browser.
    * When prompted for scopes, ensure you grant access for **`gist`** and **`repo`** (at a minimum) to allow the script to fetch all necessary data.

---

## 🚀 Getting Started

### 1. Configuration

Open the script and edit the **`Configuration`** section with your actual secrets and webhook URL:

```bash
# --- Configuration ---
# REPLACE THESE PLACEHOLDERS WITH YOUR ACTUAL SECRETS BEFORE RUNNING
export GITHUB_TOKEN="YOUR_ACTUAL_GITHUB_TOKEN" # Used by gh CLI internally/fallback (optional if gh auth is done)
export WEBHOOK_URL="YOUR_DISCORD_WEBHOOK_URL" # REQUIRED for notifications
```

> ⚠️ **Security Note:** Replace the placeholder `GITHUB_TOKEN` and `WEBHOOK_URL` with your actual values. **Do not commit sensitive tokens/URLs to your public repository\!** Consider using a separate environment file or keeping this script private.

### 2\. Define Target Organizations

Create a file named **`Orgs.txt`** in the same directory as the script. List the GitHub organization usernames you wish to scan, one per line.

**`Orgs.txt` Example:**

```
# Comments start with a hash (#)
MyTargetOrgName
AnotherOrgToScan
```

### 3\. Customize Filters (Optional)

The `IGNORED_KEYWORDS` array filters out results where the `DetectorName` contains one of the listed keywords (case-insensitive). This helps reduce noise from common, public keys or known test-related services.

```bash
# Keywords for Trufflehog filtering (detector type only)
IGNORED_KEYWORDS=("openweather" "locationiq" "algolia" "ipdata" "unsplash" ...) 
```

### 4\. Execution

Make the script executable and run it:

```bash
chmod +x Git_Phantom.sh
./Git_Phantom.sh
```

-----

## 📂 Output Structure

The script organizes all collected data and Trufflehog human-readable output into the `Scanned_Organization` directory.

```
.
├── scan_secrets.sh
├── Orgs.txt
├── run.log                 # Full script execution log
├── Scanned_Organization
│   └── TargetOrgName
│       └── trufflehog_secrets.txt # Combined human-readable findings
└── Scanned_Backup
    └── Backup_YYYYMMDD_HHMMSS
        └── ... (Copy of Scanned_Organization contents)
```

The `trufflehog_secrets.txt` file contains the detailed, human-readable output for all detected secrets that passed the keyword filter.

-----

## 🛑 Important Notes

  * **Rate Limits:** The script interacts heavily with the GitHub API via `gh`. Be aware of [GitHub API rate limits](https://www.google.com/search?q=https://docs.github.com/en/rest/overview/rate-limits) for your user/token. The script includes small random delays to help mitigate this, but extensive scanning may still hit limits.
  * **Resource Usage:** Repository cloning, unpacking, and extensive history analysis (especially for deleted files and dangling blobs) can be resource-intensive and time-consuming.
  * **Legal/Ethical:** Only run this script against organizations and repositories you have explicit authorization to scan (e.g., your own organization, public bug bounty programs).

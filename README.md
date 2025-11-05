# 👻 Git Phantom: The Comprehensive GitHub Secrets Scanner 🔍

**An advanced Bash script leveraging Trufflehog and GitHub CLI to audit your organization's entire GitHub footprint—including deep Git history, deleted files, Gists, and Issue/PR content—ensuring no forgotten secret is left behind.**

-----

## 🧭 Table of Contents

* ✨ [Key Features](#-key-features)
* ⚙️ [Prerequisites and Installation](%EF%B8%8F-prerequisites-and-installation)
    * [1. Installing the Required Tools](#1-installing-the-required-tools)
    * [2. GitHub CLI and PAT Setup](#2-github-cli-and-pat-setup)
* 🚀 [Quick Start and Usage](#-quick-start-and-usage)
* 🔑 [Configuration Guide](#-configuration-guide)
    * [Target Definition (Orgs.txt)](#target-definition-orgstxt)
    * [False Positive Filtering (IGNORED_KEYWORDS)](#false-positive-filtering-ignored_keywords)
* 🔍 [Deep Scanning Mechanisms (How It Works)](#-deep-scanning-mechanisms-how-it-works)
* 📂 [Output Structure and Reporting](#-output-structure-and-reporting)

-----

## ✨ Key Features

Git Phantom is designed for a **full security sweep**, targeting overlooked areas where secrets commonly hide:

| Feature | Description | Benefit |
| :--- | :--- | :--- |
| **🕰️ Full History Scan** | Audits the complete Git history of all non-forked repositories using `trufflehog git`. | Uncovers secrets committed and later removed. |
| **🗑️ Deleted File Recovery** | Extracts the content of files that were deleted in subsequent commits (`git diff` status 'D'). | Essential for finding secrets that developers deleted hastily instead of sanitizing the history. |
| **👻 Dangling Blobs Scan** | Scans Git objects that are unreachable by any branch or commit. | Finds sensitive data that was staged or temporarily stored but never committed. |
| **💬 Content Scanning** | Targets public **Gists**, and the body content of **Issues** and **Pull Requests** via the GitHub API. | Catches common developer mistakes where tokens are pasted into comments or descriptions. |
| **📦 Binary & Archive Scan** | Extracts readable strings from binary files and unpacks archives (`.zip`, `.tar`) within repositories for deeper inspection. | Ensures secrets aren't buried inside configuration or compressed files. |
| **🛡️ Smart Filteration** | Utilizes a customizable list of **`IGNORED_KEYWORDS`** to filter out common benign results (e.g., test keys, demo services) based on the detector name. | **Focuses alerts on genuine threats and reduces noise.** |
| **🔔 Instant Discord Alerts** | Sends detailed, immediate notifications to a configured webhook upon discovering a verified, non-filtered secret. | Enables rapid response to exposed credentials. |
| **🧹 Automatic Cleanup** | Uses Bash `trap` mechanisms to reliably delete all temporary directories and files upon script exit. | Maintains a clean working environment even if the script fails. |

-----

## ⚙️ Prerequisites and Installation

Git Phantom is a Bash script and requires several command-line utilities to be installed in your environment (WSL, Linux, or macOS).

### 1\. Installing the Required Tools

You must ensure these tools are installed and accessible in your system's PATH:

| Tool | Purpose | Suggested Installation (Linux/Ubuntu) |
| :--- | :--- | :--- |
| **Trufflehog** | Core secrets scanning engine. | `go install github.com/trufflesecurity/trufflehog@latest` |
| **GitHub CLI (`gh`)** | Essential for API calls (Gists, Issues, PRs, Org Repos). | *Follow official GitHub instructions.* |
| **`jq`** | JSON processing for API responses and Trufflehog output. | `sudo apt install jq` |
| **`git`** | Repository cloning and history manipulation. | `sudo apt install git` |
| **Archivers (Optional)**| Required for archive extraction. | `sudo apt install unzip unrar p7zip` |

### 2\. GitHub CLI and PAT Setup

The script requires proper GitHub authentication to bypass rate limits and access all data.

1.  **Authenticate with GitHub CLI:**

    ```bash
    gh auth login
    ```

      * Follow the prompts and log in via your web browser.
      * **CRITICAL:** When asked for scopes, ensure you grant access for **`repo`** (for repositories) and **`gist`** (for gists).

2.  **Personal Access Token (PAT):**

      * Generate a **Personal Access Token (PAT)** from your GitHub settings.
      * **Scopes:** Ensure this token has the necessary `repo` scope.
      * This token must be pasted into the `GITHUB_TOKEN` variable in the script file (see Configuration).

-----

## 🚀 Quick Start and Usage

### 1\. Clone the Repository

```bash
git clone https://github.com/Ibraheem7304/Git_Phantom.git
cd Git_Phantom
```

### 2\. Prepare the Targets File

  * Create a file named **`Orgs.txt`** in the root directory.
  * List the GitHub organization usernames or individual usernames "Employees of the Organization" you want to scan, one per line.

```text
# Orgs.txt Example
Company_username
Employee1_username
Employee2_username
```

### 3\. Edit the Script Configuration (Mandatory\!)

**⚠️ SECURITY WARNING:** You **must** edit the script to replace the placeholders with your actual secrets before running.

Open `Git_Phantom.sh` and update the following section:

```bash
# --- Configuration ---
# REPLACE THESE PLACEHOLDERS WITH YOUR ACTUAL SECRETS BEFORE RUNNING
export GITHUB_TOKEN="YOUR_GITHUB_PAT_HERE"      # Your PAT (Required for gh CLI/API)
export WEBHOOK_URL="YOUR_DISCORD_WEBHOOK_URL_HERE" # Your Discord webhook link
```

### 4\. Run the Script

Make the script executable and launch the scan:

```bash
chmod +x Git_Phantom.sh
./Git_Phantom.sh
```

-----

## 🔑 Configuration Guide

### Target Definition (`Orgs.txt`)

  * **Purpose:** Defines the scope of the scan.
  * The script reads this file line-by-line, ignores lines starting with `#`, and proceeds to scan all associated repositories, gists, issues, and PRs for each entry.

### False Positive Filtering (`IGNORED_KEYWORDS`)

This is crucial for focusing on real threats. The script converts the detector name found by Trufflehog to lowercase and checks if it contains any of these keywords.

```bash
IGNORED_KEYWORDS=("openweather" "algolia" "ipdata" "unsplash" "ipinfo" "test" "demo" "public" "default" .....................)
```

  * **How to use:** Add any service names (e.g., `algolia`) or generic terms (`sandbox`, `testing`) that you frequently see as benign findings. Secrets matching these keywords will be logged as ignored but will **not** trigger a Discord alert.

-----

## 🔍 Deep Scanning Mechanisms (How It Works)

To help you understand the power of Git Phantom, here is a detailed breakdown of its advanced features:

### 1\. Deleted Files Extraction

The script performs a commit-by-commit analysis:

  * It iterates through the difference (`git diff`) between every commit and its parent.
  * If a file shows a **'D' (Deletion)** status, the script extracts the file's content **from the parent commit** (where it still existed).
  * This content is saved to a temporary file (e.g., `commitHASH_fileHASH_filename.deleted`) and scanned, effectively recovering secrets deleted from the history.

### 2\. Dangling Blob Object Scan

This targets the raw data storage in Git:

  * It executes `git fsck --unreachable --dangling` to find objects in the `.git/objects` folder that are no longer referenced by any branch or tag.
  * It uses `git cat-file -p` to retrieve the contents of these raw data blobs.
  * These contents are treated as plain files and passed to Trufflehog, catching objects that were never fully committed.

### 3\. Contextual Content Scanning

The script uses the `gh api` and `gh search` commands to pull non-code data:

  * **Gists:** All gists are cloned locally and scanned using `trufflehog filesystem`.
  * **Issues/PRs:** The script searches for the 100 most recent Issues and PRs, extracts the textual **body** of each one, and scans that text file for credentials.

-----

## 📂 Output Structure and Reporting

All scan output and reports are organized and backed up:

| Directory/File | Description | Retention |
| :--- | :--- | :--- |
| **`run.log`** | Detailed log of all script actions, processes, errors, and timestamps. | Kept until next run. |
| **`Scanned_Organization/`** | The working directory for the current scan cycle's results. | Cleared after backup. |
| **`OrgName/trufflehog_secrets.txt`** | The main report file containing all human-readable output for found secrets that passed the keyword filter. | Backed up. |
| **`Scanned_Backup/`** | Contains zipped copies of the entire `Scanned_Organization` folder, timestamped for historical review. | Persists across runs. |

-----

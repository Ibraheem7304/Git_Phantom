# 👻 Git Phantom

```text
  █████████   ███   █████              ███████████  █████                            █████                            
  ███░░░░░███ ░░░   ░░███              ░░███░░░░░███░░███                            ░░███                             
 ███     ░░░  ████  ███████             ░███    ░███ ░███████    ██████   ████████   ███████    ██████  █████████████  
░███         ░░███ ░░░███░              ░██████████  ░███░░███  ░░░░░███ ░░███░░███ ░░░███░    ███░░███░░███░░███░░███ 
░███    █████ ░███   ░███               ░███░░░░░░   ░███ ░███   ███████  ░███ ░███   ░███    ░███ ░███ ░███ ░███ ░███ 
░░███  ░░███  ░███   ░███ ███           ░███         ░███ ░███  ███░░███  ░███ ░███   ░███ ███░███ ░███ ░███ ░███ ░███ 
 ░░█████████  █████  ░░█████  █████████ █████        ████ █████░░████████ ████ █████  ░░█████ ░░██████  █████░███ █████
  ░░░░░░░░░  ░░░░░    ░░░░░  ░░░░░░░░░ ░░░░░        ░░░░ ░░░░░  ░░░░░░░░ ░░░░ ░░░░░    ░░░░░   ░░░░░░  ░░░░░ ░░░ ░░░░░

      By @Ibraheem7304 & @MohamedAhmedGameel
````

**Git Phantom** is an advanced, automated security auditing tool designed to hunt down secrets, credentials, and sensitive information hidden deep within GitHub organizations.

Unlike standard scanners that only look at the current codebase, **Git Phantom** performs deep forensics on git history, deleted files, archives, and binaries to ensure nothing stays hidden.

-----

## 🚀 Key Advantages & Features

Why use Git Phantom over standard scanning tools?

### 1\. 🗑️ Resurrection of Deleted Files

Security mistakes often happen when a developer accidentally commits a secret and then "deletes" the file in a subsequent commit. Standard scanners often miss this.

  * **Git Phantom** iterates through the entire commit history.
  * It identifies files with `D` (Deleted) status.
  * It **reconstructs** these deleted files from the git history and scans them specifically for secrets.

### 2\. 📦 Archive Extraction & Scanning

Secrets are often hidden inside compressed backups or data dumps committed to the repo.

  * **Git Phantom** automatically detects and extracts nested archives (`.zip`, `.tar`, `.rar`, `.7z`, etc.).
  * It performs a deep scan on the *contents* of these archives, not just the file name.

### 3\. 🔢 Binary Forensics

Executables and binaries sometimes contain hardcoded API keys or dev credentials.

  * **Git Phantom** identifies binary files.
  * It uses `strings` to extract readable text from binaries.
  * It scans the extracted text for secrets.

### 4\. 🤖 Automation & Reporting

  * **Batch Processing:** Scans entire organizations at once via an input list.
  * **Discord Integration:** Sends real-time alerts to your Discord channel via Webhook when a secret is found.
  * **Smart Filtering:** Uses an intelligent ignore list to reduce false positives (ignoring common keywords like `test`, `example`, `localhost`).
  * **Clean Logs:** Generates a detailed `run.log` and a dedicated `trufflehog_secrets.txt` report for every organization.

-----

## 🛠️ Installation & Setup

We have simplified the installation process with a dedicated setup script.

### 1\. Get the Tools with `Phantom_setter.sh`

To get started, you don't need to manually install dependencies. We provide **`Phantom_setter.sh`** to handle the heavy lifting.

This script will:

  * Download and install the required binaries (like `trufflehog`, `jq`, `gh`).
  * Help you configure your environment variables.
  * Ensure your system is ready for scanning.

<!-- end list -->

```bash
chmod +x Phantom_setter.sh
./Phantom_setter.sh
```

### 2\. Configuration

Before running the phantom, ensure you have your credentials ready:

1.  **GitHub Token:** A Personal Access Token (classic) with `repo` and `read:org` permissions.
2.  **Discord Webhook:** For real-time notifications (optional but recommended).

-----

## 🕵️ Usage

Once your environment is set up, running Git Phantom is simple.

1.  **Prepare your Target List:**
    Create a text file (e.g., `targets.txt`) containing the names of the GitHub organizations you want to scan, one per line.

    ```text
    target-org-1
    target-org-2
    ```

2.  **Run the Scanner:**
    Execute the script using the `-t` flag to specify your target list.

    ```bash
    chmod +x git_phantom.sh
    ./git_phantom.sh -t targets.txt
    ```

3.  **View Results:**

      * Real-time alerts will appear in your Discord.
      * Logs are saved to `run.log`.
      * Detailed secret findings are stored in `Scanned_Organization/<Org_Name>/trufflehog_secrets.txt`.
      * Backups of scans are automatically created in `Scanned_Backup/`.

-----

## 👥 Creators

| Name | LinkedIn | GitHub |
| :--- | :--- | :--- |
| **Ibraheem El-Mougy** | [![LinkedIn](https://img.shields.io/badge/LinkedIn-%230077B5.svg?&style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/ibraheem0x49/) | [![GitHub](https://img.shields.io/badge/GitHub-100000?style=for-the-badge&logo=github&logoColor=white)](https://github.com/Ibraheem7304) |
| **Mohamed Ahmed Gameel** | [![LinkedIn](https://img.shields.io/badge/LinkedIn-%230077B5.svg?&style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/mohamed-ahmed-gameel-26289a246/) | [![GitHub](https://img.shields.io/badge/GitHub-100000?style=for-the-badge&logo=github&logoColor=white)](https://github.com/MohamedAhmedGameel) |

-----

## ⚠️ Disclaimer

**Git Phantom** is intended for security research, red teaming, and authorized auditing purposes only. Ensure you have permission to scan the organizations and repositories you target. The creators are not responsible for misuse of this tool.

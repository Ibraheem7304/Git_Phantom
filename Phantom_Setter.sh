#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# --- Configurable variables ---
MAIN_SCRIPT="gitaudit.sh"  # Name of your main script file

# --- Functions ---
usage() {
  echo "Usage: $0 [-i] [-e] [-g <github_token>] [-w <webhook_url>]"
  echo
  echo "  -i   Install dependencies (gh, jq, trufflehog, curl)"
  echo "  -e   Edit tokens inside main script"
  echo "  -g   Set GitHub token (used with -e)"
  echo "  -w   Set Discord webhook (used with -e)"
  exit 1
}

install_deps() {
  echo "🔧 Installing dependencies..."
  pkgs=(git gh jq trufflehog file strings sha1sum mktemp rm cp tar unzip unrar date tee basename xargs awk grep curl)
  for pkg in "${pkgs[@]}"; do
    if ! command -v "$pkg" &>/dev/null; then
      echo "➡️ Installing $pkg..."
      sudo apt-get install -y "$pkg"
      echo "✅ $pkg installed."
    else
      echo "✅ $pkg already installed."
    fi
  done
  echo "✅ All dependencies installed."
}

edit_tokens() {
  [[ -f "$MAIN_SCRIPT" ]] || { echo "❌ Main script '$MAIN_SCRIPT' not found."; exit 1; }

  echo "✏️ Editing tokens in $MAIN_SCRIPT..."

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    sed -i "s|^GITHUB_TOKEN=.*|GITHUB_TOKEN=\"$GITHUB_TOKEN\"|" "$MAIN_SCRIPT"
    echo "✅ Updated GitHub token."
  fi

  if [[ -n "${WEBHOOK_TOKEN:-}" ]]; then
    sed -i "s|^WEBHOOK_URL=.*|WEBHOOK_URL=\"$WEBHOOK_TOKEN\"|" "$MAIN_SCRIPT"
    echo "✅ Updated Discord webhook."
  fi

  echo "🎉 Tokens updated successfully."
}

# --- Parse arguments ---
INSTALL=false
EDIT=false
GITHUB_TOKEN=""
WEBHOOK_TOKEN=""

while getopts ":ieg:w:" opt; do
  case $opt in
    i) INSTALL=true ;;
    e) EDIT=true ;;
    g) GITHUB_TOKEN="$OPTARG" ;;
    w) WEBHOOK_TOKEN="$OPTARG" ;;
    *) usage ;;
  esac
done

# --- Execute based on flags ---
if $INSTALL; then
  install_deps
fi

if $EDIT; then
  edit_tokens
fi

if ! $INSTALL && ! $EDIT; then
  usage
fi

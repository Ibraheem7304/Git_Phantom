#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# --- Configurable variables ---
MAIN_SCRIPT="Git_Phantom.sh"  # Name of your main script file

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
  echo "🔧 Updating package index..."
  sudo apt-get update -y >/dev/null 2>&1 || echo "⚠️  Could not update apt index, continuing..."

  echo "🔧 Installing dependencies..."
  pkgs=(git jq trufflehog curl file coreutils tar unzip unrar grep awk sed xargs)

  for pkg in "${pkgs[@]}"; do
    if ! command -v "$pkg" &>/dev/null; then
      echo "➡️  Installing $pkg..."
      sudo apt-get install -y "$pkg" >/dev/null 2>&1 || echo "⚠️  Could not install $pkg automatically."
    else
      echo "✅ $pkg already installed."
    fi
  done

  echo "✅ Dependency installation complete."
}

edit_tokens() {
  if [[ ! -f "$MAIN_SCRIPT" ]]; then
    echo "❌ Main script not found at: $MAIN_SCRIPT"
    exit 1
  fi

  echo "✏️  Editing tokens in $MAIN_SCRIPT..."

  # Use regex that matches both 'export GITHUB_TOKEN=' and 'GITHUB_TOKEN='
  if [[ -n "$GITHUB_TOKEN" ]]; then
    if grep -qE '^export GITHUB_TOKEN=' "$MAIN_SCRIPT"; then
      sed -i "s|^export GITHUB_TOKEN=.*|export GITHUB_TOKEN=\"$GITHUB_TOKEN\"|" "$MAIN_SCRIPT"
    elif grep -qE '^GITHUB_TOKEN=' "$MAIN_SCRIPT"; then
      sed -i "s|^GITHUB_TOKEN=.*|GITHUB_TOKEN=\"$GITHUB_TOKEN\"|" "$MAIN_SCRIPT"
    else
      echo "export GITHUB_TOKEN=\"$GITHUB_TOKEN\"" >> "$MAIN_SCRIPT"
    fi
    echo "✅ Updated GitHub token."
  fi

  if [[ -n "$WEBHOOK_TOKEN" ]]; then
    if grep -qE '^export WEBHOOK_URL=' "$MAIN_SCRIPT"; then
      sed -i "s|^export WEBHOOK_URL=.*|export WEBHOOK_URL=\"$WEBHOOK_TOKEN\"|" "$MAIN_SCRIPT"
    elif grep -qE '^WEBHOOK_URL=' "$MAIN_SCRIPT"; then
      sed -i "s|^WEBHOOK_URL=.*|WEBHOOK_URL=\"$WEBHOOK_TOKEN\"|" "$MAIN_SCRIPT"
    else
      echo "export WEBHOOK_URL=\"$WEBHOOK_TOKEN\"" >> "$MAIN_SCRIPT"
    fi
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




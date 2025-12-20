#!/usr/bin/env bash

set -e

owner="Kingrashy12"
repo="zio"
asset_name="zio-x86_64-windows.exe"
install_name="zio.exe"

echo "Fetching latest version..."

latest_version=$(curl -s "https://api.github.com/repos/$owner/$repo/releases/latest" \
    | grep "tag_name" \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

echo "Latest version: $latest_version"

download_url="https://github.com/$owner/$repo/releases/download/$latest_version/$asset_name"

echo "Downloading: $download_url"

curl -L -o "$asset_name" "$download_url"

echo "Download complete."

# Determine install directory
# Prefer WindowsApps since it's in PATH by default
install_dir="$LOCALAPPDATA/Microsoft/WindowsApps"

# Fallback if running under WSL
if [ -z "$LOCALAPPDATA" ]; then
    install_dir="$HOME/.local/bin"
fi

mkdir -p "$install_dir"

echo "Installing to: $install_dir"

mv -f "$asset_name" "$install_dir/$install_name"

echo "Installed as: $install_dir/$install_name"
echo

# Check if in PATH
if command -v zio >/dev/null 2>&1; then
    echo "✅ Installation successful! Run: zio"
else
    echo "⚠ Installed, but your PATH may require a terminal restart."
fi

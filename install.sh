#!/bin/bash
#
# Termflix Installation Script
# Installs termflix to /usr/local/bin/termflix
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}Termflix Installation${RESET}"
echo ""

# Check if running as root for system-wide install
INSTALL_DIR="/usr/local/bin"
if [ "$EUID" -eq 0 ]; then
    INSTALL_DIR="/usr/local/bin"
else
    # Try user-local install
    if [ -d "$HOME/.local/bin" ]; then
        INSTALL_DIR="$HOME/.local/bin"
    else
        echo -e "${YELLOW}Note:${RESET} Installing to $HOME/.local/bin (creating directory)"
        mkdir -p "$HOME/.local/bin" 2>/dev/null || {
            echo -e "${RED}Error:${RESET} Cannot create $HOME/.local/bin"
            echo "Please run with sudo for system-wide install, or create $HOME/.local/bin manually"
            exit 1
        }
        INSTALL_DIR="$HOME/.local/bin"
    fi
fi

# Find the script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERMFLIX_SCRIPT="$SCRIPT_DIR/termflix"

if [ ! -f "$TERMFLIX_SCRIPT" ]; then
    echo -e "${RED}Error:${RESET} termflix script not found in $SCRIPT_DIR"
    exit 1
fi

# Install
echo -e "${CYAN}Installing termflix to ${INSTALL_DIR}...${RESET}"
cp "$TERMFLIX_SCRIPT" "$INSTALL_DIR/termflix"
chmod +x "$INSTALL_DIR/termflix"

# Check if install directory is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo -e "${YELLOW}Warning:${RESET} $INSTALL_DIR is not in your PATH"
    echo "Add this to your ~/.bashrc or ~/.zshrc:"
    echo -e "${CYAN}export PATH=\"\$PATH:$INSTALL_DIR\"${RESET}"
    echo ""
fi

echo -e "${GREEN}✓ Termflix installed successfully!${RESET}"
echo ""
echo "Run: ${CYAN}termflix${RESET} to get started"
echo "Run: ${CYAN}termflix --help${RESET} for usage information"
echo ""

# Check dependencies
echo -e "${CYAN}Checking dependencies...${RESET}"
MISSING=()

if ! command -v jq &> /dev/null; then
    MISSING+=("jq")
fi

if ! command -v peerflix &> /dev/null && ! command -v webtorrent &> /dev/null; then
    MISSING+=("peerflix or webtorrent")
fi

if ! command -v mpv &> /dev/null && ! command -v vlc &> /dev/null; then
    MISSING+=("mpv or vlc")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing dependencies:${RESET}"
    for dep in "${MISSING[@]}"; do
        echo "  - $dep"
    done
    echo ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Install with: ${CYAN}brew install jq peerflix mpv${RESET}"
    else
        echo "Install with: ${CYAN}sudo apt-get install jq mpv${RESET}"
        echo "And: ${CYAN}npm install -g peerflix${RESET}"
    fi
else
    echo -e "${GREEN}✓ All required dependencies found${RESET}"
fi

echo ""

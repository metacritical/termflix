#!/bin/bash

# Script to run brew update and upgrade once at system startup

# Set the PATH to include Homebrew
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Log file to track execution
LOG_FILE="$HOME/brew_update.log"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "Starting brew update and upgrade"

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    log_message "Error: Homebrew is not installed"
    exit 1
fi

# Check if an update has already been performed today
TODAY=$(date '+%Y-%m-%d')
if [ -f "$HOME/.brew_last_update" ]; then
    LAST_UPDATE=$(cat "$HOME/.brew_last_update")
    if [ "$LAST_UPDATE" = "$TODAY" ]; then
        log_message "Brew already updated today, skipping"
        exit 0
    fi
fi

log_message "Running brew update"
brew update >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log_message "Brew update completed successfully"
    
    log_message "Running brew upgrade"
    brew upgrade >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        log_message "Brew upgrade completed successfully"
        # Record today's date to avoid running again today
        echo "$TODAY" > "$HOME/.brew_last_update"
    else
        log_message "Error: Brew upgrade failed"
    fi
else
    log_message "Error: Brew update failed"
fi

log_message "Brew update and upgrade process completed"
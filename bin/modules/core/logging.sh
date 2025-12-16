#!/usr/bin/env bash
#
# Termflix Logging Module
# File-based logging with levels and rotation
#
# @version 1.0.0
# @updated 2025-12-14
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_LOGGING_LOADED:-}" ]] && return 0
_TERMFLIX_LOGGING_LOADED=1

# ═══════════════════════════════════════════════════════════════
# LOG LEVEL CONSTANTS
# ═══════════════════════════════════════════════════════════════

# Log levels (lower = more verbose)
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_NONE=4

# ═══════════════════════════════════════════════════════════════
# LOG CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Log directory and file
LOG_DIR="${HOME}/.config/termflix/logs"
LOG_FILE=""
LOG_MAX_FILES=5
LOG_CONSOLE_ENABLED=1  # Also log to console (1=enabled, 0=disabled)
LOG_INITIALIZED=0

# Get current log level from environment
_get_log_level() {
    case "${TERMFLIX_LOG_LEVEL:-INFO}" in
        DEBUG|debug|0) echo $LOG_LEVEL_DEBUG ;;
        INFO|info|1)   echo $LOG_LEVEL_INFO ;;
        WARN|warn|2)   echo $LOG_LEVEL_WARN ;;
        ERROR|error|3) echo $LOG_LEVEL_ERROR ;;
        NONE|none|4)   echo $LOG_LEVEL_NONE ;;
        *)             echo $LOG_LEVEL_INFO ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# LOG INITIALIZATION
# ═══════════════════════════════════════════════════════════════

# Initialize logging system
# Call this at the start of your script to enable file logging
init_logging() {
    # Avoid re-initialization
    [[ $LOG_INITIALIZED -eq 1 ]] && return 0
    
    # Create log directory
    mkdir -p "$LOG_DIR" 2>/dev/null
    
    # Check if directory is writable
    if [[ ! -w "$LOG_DIR" ]]; then
        echo "[WARN] Cannot write to log directory: $LOG_DIR" >&2
        return 1
    fi
    
    # Set log file with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    LOG_FILE="${LOG_DIR}/termflix_${timestamp}.log"
    
    # Rotate old logs first
    rotate_logs
    
    # Write header to log file
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "Termflix Log - Started $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Log Level: ${TERMFLIX_LOG_LEVEL:-INFO}"
        echo "PID: $$"
        echo "═══════════════════════════════════════════════════════════════"
    } >> "$LOG_FILE" 2>/dev/null
    
    LOG_INITIALIZED=1
    return 0
}

# ═══════════════════════════════════════════════════════════════
# LOG ROTATION
# ═══════════════════════════════════════════════════════════════

# Rotate logs - keep only last N log files
rotate_logs() {
    local max_files="${LOG_MAX_FILES:-5}"
    
    # Check if log directory exists
    [[ ! -d "$LOG_DIR" ]] && return 0
    
    # Get list of log files sorted by time (newest first)
    local log_files=()
    local f
    for f in "$LOG_DIR"/termflix_*.log; do
        [[ -f "$f" ]] && log_files+=("$f")
    done
    
    local count=${#log_files[@]}
    
    # If we have too many files, remove the oldest ones
    if [[ $count -ge $max_files ]]; then
        # Sort files by modification time (oldest first) and remove excess
        local sorted_files
        sorted_files=$(ls -1t "$LOG_DIR"/termflix_*.log 2>/dev/null)
        
        local to_keep=$((max_files - 1))  # Keep max-1 to make room for new one
        local kept=0
        
        while IFS= read -r file; do
            if [[ $kept -ge $to_keep ]]; then
                rm -f "$file" 2>/dev/null
            fi
            ((kept++))
        done <<< "$sorted_files"
    fi
}

# Set maximum number of log files to keep
set_log_max_files() {
    local max="$1"
    if [[ "$max" =~ ^[0-9]+$ ]] && [[ $max -ge 1 ]]; then
        LOG_MAX_FILES="$max"
    fi
}

# ═══════════════════════════════════════════════════════════════
# CORE LOGGING FUNCTION
# ═══════════════════════════════════════════════════════════════

# Internal log function
# Usage: _log <level_num> <level_name> <message> [color]
_log() {
    local level="$1"
    local level_name="$2"
    local message="$3"
    local color="${4:-}"
    
    # Get current configured log level
    local current_level
    current_level=$(_get_log_level)
    
    # Check if we should log this level
    [[ $level -lt $current_level ]] && return 0
    
    # Format timestamp
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format log line for file (plain text)
    local log_line="[$timestamp] [$level_name] $message"
    
    # Write to file (if initialized and writable)
    if [[ $LOG_INITIALIZED -eq 1 && -n "$LOG_FILE" ]]; then
        echo "$log_line" >> "$LOG_FILE" 2>/dev/null
    fi
    
    # Write to console (if enabled and color provided)
    if [[ $LOG_CONSOLE_ENABLED -eq 1 ]]; then
        if [[ -n "$color" ]]; then
            echo -e "${color}[$level_name]${RESET:-\033[0m} $message" >&2
        else
            echo "[$level_name] $message" >&2
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# PUBLIC LOG FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Debug level logging (most verbose)
# Only shown when TERMFLIX_LOG_LEVEL=DEBUG
log_debug() {
    _log $LOG_LEVEL_DEBUG "DEBUG" "$*" "${C_MUTED:-\033[38;5;241m}"
}

# Info level logging
# Shown when TERMFLIX_LOG_LEVEL=DEBUG or INFO
log_info() {
    _log $LOG_LEVEL_INFO "INFO" "$*" "${C_INFO:-\033[38;5;81m}"
}

# Warning level logging
# Shown when TERMFLIX_LOG_LEVEL=DEBUG, INFO, or WARN
log_warn() {
    _log $LOG_LEVEL_WARN "WARN" "$*" "${C_WARNING:-\033[38;5;220m}"
}

# Error level logging (least verbose)
# Always shown unless TERMFLIX_LOG_LEVEL=NONE
log_error() {
    _log $LOG_LEVEL_ERROR "ERROR" "$*" "${C_ERROR:-\033[38;5;203m}"
}

# Raw log - always writes to file regardless of level
# Use for critical messages that must be logged
log_raw() {
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ $LOG_INITIALIZED -eq 1 && -n "$LOG_FILE" ]]; then
        echo "[$timestamp] $message" >> "$LOG_FILE" 2>/dev/null
    fi
}

# ═══════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Get current log file path
get_log_file() {
    echo "$LOG_FILE"
}

# Get log directory
get_log_dir() {
    echo "$LOG_DIR"
}

# Enable/disable console output
# Usage: set_console_logging 1  # Enable
#        set_console_logging 0  # Disable
set_console_logging() {
    LOG_CONSOLE_ENABLED="${1:-1}"
}

# Check if logging is initialized
is_logging_initialized() {
    [[ $LOG_INITIALIZED -eq 1 ]]
}

# View last N lines of current log
# Usage: tail_log [num_lines]
tail_log() {
    local lines="${1:-50}"
    if [[ -f "$LOG_FILE" ]]; then
        tail -n "$lines" "$LOG_FILE"
    else
        echo "No log file available"
        return 1
    fi
}

# Clear current log file
clear_log() {
    if [[ -f "$LOG_FILE" ]]; then
        > "$LOG_FILE"
        log_info "Log cleared"
        return 0
    fi
    return 1
}

# List all log files
list_logs() {
    if [[ -d "$LOG_DIR" ]]; then
        ls -lht "$LOG_DIR"/termflix_*.log 2>/dev/null || echo "No log files found"
    else
        echo "Log directory does not exist"
    fi
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f init_logging rotate_logs set_log_max_files
export -f log_debug log_info log_warn log_error log_raw
export -f get_log_file get_log_dir set_console_logging is_logging_initialized
export -f tail_log clear_log list_logs

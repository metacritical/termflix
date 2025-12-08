#!/usr/bin/env bash
#
# Termflix Errors Module
# Unified error handling and signal management
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_ERRORS_LOADED:-}" ]] && return 0
_TERMFLIX_ERRORS_LOADED=1

# ═══════════════════════════════════════════════════════════════
# GLOBAL STATE
# ═══════════════════════════════════════════════════════════════

# Cleanup functions to run on exit
# Global arrays (bash 3.x compatible)
TERMFLIX_CLEANUP_FUNCS=()

# Child PIDs to kill on exit
TERMFLIX_CHILD_PIDS=()

# Terminal state backup
TERMFLIX_STTY_BACKUP=""

# ═══════════════════════════════════════════════════════════════
# REGISTRATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Register a cleanup function to run on exit
register_cleanup() {
    local func="$1"
    TERMFLIX_CLEANUP_FUNCS+=("$func")
}

# Register a child PID to kill on exit
register_child_pid() {
    local pid="$1"
    TERMFLIX_CHILD_PIDS+=("$pid")
}

# Remove a child PID from tracking (when it exits normally)
unregister_child_pid() {
    local pid="$1"
    local new_pids=()
    for p in "${TERMFLIX_CHILD_PIDS[@]}"; do
        [[ "$p" != "$pid" ]] && new_pids+=("$p")
    done
    TERMFLIX_CHILD_PIDS=("${new_pids[@]}")
}

# ═══════════════════════════════════════════════════════════════
# TERMINAL STATE MANAGEMENT
# ═══════════════════════════════════════════════════════════════

# Save terminal settings before modifying
save_terminal_state() {
    TERMFLIX_STTY_BACKUP=$(stty -g 2>/dev/null)
}

# Restore terminal settings
restore_terminal_state() {
    if [[ -n "$TERMFLIX_STTY_BACKUP" ]]; then
        stty "$TERMFLIX_STTY_BACKUP" 2>/dev/null
    else
        stty echo icanon 2>/dev/null
    fi
    tput cnorm 2>/dev/null    # Show cursor
    tput rmcup 2>/dev/null    # Exit alternate screen
}

# ═══════════════════════════════════════════════════════════════
# CLEANUP FUNCTION
# ═══════════════════════════════════════════════════════════════

# Master cleanup - run all registered cleanups
termflix_cleanup() {
    # Kill child processes gracefully
    for pid in "${TERMFLIX_CHILD_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
            # Wait briefly for graceful shutdown
            local wait_count=0
            while kill -0 "$pid" 2>/dev/null && [[ $wait_count -lt 10 ]]; do
                sleep 0.1
                ((wait_count++))
            done
            # Force kill if still running
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        fi
    done
    
    # Run registered cleanup functions
    for func in "${TERMFLIX_CLEANUP_FUNCS[@]}"; do
        if declare -f "$func" >/dev/null 2>&1; then
            "$func" 2>/dev/null
        fi
    done
    
    # Restore terminal state
    restore_terminal_state
    
    # Clear arrays
    TERMFLIX_CLEANUP_FUNCS=()
    TERMFLIX_CHILD_PIDS=()
}

# ═══════════════════════════════════════════════════════════════
# SIGNAL HANDLERS
# ═══════════════════════════════════════════════════════════════

# Handle Ctrl+C (SIGINT)
handle_sigint() {
    echo ""
    echo -e "${C_WARNING:-\033[38;5;220m}⚠ Cancelled by user${RESET:-\033[0m}"
    termflix_cleanup
    # Don't exit - return to caller
    # Use return code to indicate cancellation
    return 130
}

# Handle SIGTERM
handle_sigterm() {
    termflix_cleanup
    exit 143
}

# Handle EXIT (normal or abnormal)
handle_exit() {
    termflix_cleanup
}

# Set up all signal handlers
setup_signal_handlers() {
    trap 'handle_sigint' INT
    trap 'handle_sigterm' TERM
    trap 'handle_exit' EXIT
}

# ═══════════════════════════════════════════════════════════════
# MESSAGE FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Show error message (red)
show_error() {
    local msg="$1"
    echo -e "${C_ERROR:-\033[38;5;203m}✗ Error:${RESET:-\033[0m} $msg" >&2
}

# Show warning message (yellow)
show_warning() {
    local msg="$1"
    echo -e "${C_WARNING:-\033[38;5;220m}⚠ Warning:${RESET:-\033[0m} $msg" >&2
}

# Show success message (green)
show_success() {
    local msg="$1"
    echo -e "${C_SUCCESS:-\033[38;5;46m}✓${RESET:-\033[0m} $msg"
}

# Show info message (cyan)
show_info() {
    local msg="$1"
    echo -e "${C_INFO:-\033[38;5;81m}ℹ${RESET:-\033[0m} $msg"
}

# Show debug message (muted, only if TERMFLIX_DEBUG is set)
show_debug() {
    local msg="$1"
    if [[ -n "${TERMFLIX_DEBUG:-}" ]]; then
        echo -e "${C_MUTED:-\033[38;5;241m}[DEBUG]${RESET:-\033[0m} $msg" >&2
    fi
}

# ═══════════════════════════════════════════════════════════════
# ERROR HANDLING UTILITIES
# ═══════════════════════════════════════════════════════════════

# Check if a command exists
require_command() {
    local cmd="$1"
    local pkg="${2:-$cmd}"
    if ! command -v "$cmd" &>/dev/null; then
        show_error "$cmd is required but not installed. Install with: brew install $pkg"
        return 1
    fi
    return 0
}

# Safely run a command with error handling
safe_run() {
    local cmd="$*"
    if ! eval "$cmd" 2>/dev/null; then
        show_error "Command failed: $cmd"
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f register_cleanup register_child_pid unregister_child_pid
export -f save_terminal_state restore_terminal_state termflix_cleanup
export -f handle_sigint handle_sigterm handle_exit setup_signal_handlers
export -f show_error show_warning show_success show_info show_debug
export -f require_command safe_run

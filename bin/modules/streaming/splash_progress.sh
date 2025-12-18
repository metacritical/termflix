#!/usr/bin/env bash
#
# MPV OSD Progress Updater
# Updates splash screen OSD with live buffering progress
#

# Update MPV splash OSD with buffering progress
# Args: $1 = IPC socket path, $2 = status file path, $3 = movie title
update_splash_progress() {
    local ipc_socket="$1"
    local status_file="$2"
    local movie_title="$3"
    
    if [[ ! -S "$ipc_socket" ]] || [[ ! -f "$status_file" ]]; then
        return 1
    fi
    
    # Read buffer status: percent|speed|peers_connected|peers_total|size_mb|status
    local status_line=$(cat "$status_file" 2>/dev/null)
    IFS='|' read -r percent speed peers_conn peers_total size_mb state <<< "$status_line"
    
    # Format progress message
    local speed_mb=$(awk "BEGIN {printf \"%.1f\", $speed/1048576}")
    local osd_text="${movie_title}\nBuffering: ${percent}% | ${speed_mb} MB/s | ${peers_conn}/${peers_total} peers"
    
    # If ready, show "Starting..."
    if [[ "$state" == "READY" ]]; then
        osd_text="${movie_title}\nStarting playback..."
    fi
    
    # Send OSD update via IPC
    echo "{\"command\":[\"show-text\",\"$osd_text\",1000]}" | socat - "$ipc_socket" 2>/dev/null
}

# Monitor and update splash OSD continuously
# Args: $1 = IPC socket, $2 = status file, $3 = movie title
monitor_splash_progress() {
    local ipc_socket="$1"
    local status_file="$2"
    local movie_title="$3"
    
    while [[ -S "$ipc_socket" ]] && kill -0 $(lsof -t "$ipc_socket" 2>/dev/null) 2>/dev/null; do
        update_splash_progress "$ipc_socket" "$status_file" "$movie_title"
        sleep 0.5
        
        # Stop if READY status (video about to start) OR if status file indicates stream URL (meaning start)
        # We must stop updating OSD so mpv_transition can clear it
        if grep -q "READY" "$status_file" 2>/dev/null; then
            # One final clear to be safe
            echo "{\"command\":[\"show-text\",\"\",0]}" | socat - "$ipc_socket" 2>/dev/null
            break
        fi
    done
}

export -f update_splash_progress
export -f monitor_splash_progress

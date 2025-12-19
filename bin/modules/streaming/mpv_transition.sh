#!/usr/bin/env bash
#
# MPV Transition Helper
# Sends loadfile command to MPV IPC socket to transition from splash to video
#

# Transition MPV from splash screen to video
# Args: $1 = IPC socket path, $2 = video URL/path, $3 = subtitle path (optional)
mpv_transition_to_video() {
    local ipc_socket="$1"
    local video_url="$2"
    local subtitle_path="${3:-}"
    
    if [[ ! -S "$ipc_socket" ]]; then
        echo "Error: MPV IPC socket not found: $ipc_socket" >&2
        return 1
    fi
    
    # Clear OSD message and persistent properties before loading
    echo '{ "command": ["show-text", ""] }' | socat - "$ipc_socket" 2>/dev/null
    echo '{ "command": ["set_property", "osd-msg1", ""] }' | socat - "$ipc_socket" 2>/dev/null
    
    # Load video (replace current file)
    local load_cmd="{\"command\": [\"loadfile\", \"$video_url\", \"replace\"]}"
    echo "$load_cmd" | socat - "$ipc_socket" 2>/dev/null
    
    # Configure streaming properties for continuous buffering
    sleep 0.3  # Wait for loadfile to start
    
    # Enable and configure cache for HTTP streaming
    echo '{ "command": ["set_property", "cache", "yes"] }' | socat - "$ipc_socket" 2>/dev/null
    echo '{ "command": ["set_property", "cache-secs", 300] }' | socat - "$ipc_socket" 2>/dev/null
    echo '{ "command": ["set_property", "demuxer-max-bytes", 536870912] }' | socat - "$ipc_socket" 2>/dev/null  # 512MB
    echo '{ "command": ["set_property", "demuxer-max-back-bytes", 268435456] }' | socat - "$ipc_socket" 2>/dev/null  # 256MB
    
    # Set OSD level to minimal
    echo '{ "command": ["set_property", "osd-level", "1"] }' | socat - "$ipc_socket" 2>/dev/null
    
    # Add subtitle if provided
    if [[ -n "$subtitle_path" ]] && [[ -f "$subtitle_path" ]]; then
        sleep 0.2
        local sub_cmd="{\"command\": [\"sub-add\", \"$subtitle_path\"]}"
        echo "$sub_cmd" | socat - "$ipc_socket" 2>/dev/null
    fi
    
    # Reset keep-open so player exits when video ends
    sleep 0.1
    echo '{ "command": ["set_property", "keep-open", "no"] }' | socat - "$ipc_socket" 2>/dev/null
    
    return 0
}

export -f mpv_transition_to_video

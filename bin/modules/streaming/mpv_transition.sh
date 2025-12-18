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
    
    # Clear OSD message before loading
    echo '{ "command": ["show-text", ""] }' | socat - "$ipc_socket" 2>/dev/null
    
    # Load video (replace current file)
    local load_cmd="{\"command\": [\"loadfile\", \"$video_url\", \"replace\"]}"
    echo "$load_cmd" | socat - "$ipc_socket" 2>/dev/null
    
    # Wait for video to start, then set OSD level to minimal
    sleep 0.5
    echo '{ "command": ["set_property", "osd-level", "1"] }' | socat - "$ipc_socket" 2>/dev/null
    
    # Add subtitle if provided
    if [[ -n "$subtitle_path" ]] && [[ -f "$subtitle_path" ]]; then
        sleep 0.2
        local sub_cmd="{\"command\": [\"sub-add\", \"$subtitle_path\"]}"
        echo "$sub_cmd" | socat - "$ipc_socket" 2>/dev/null
    fi
    
    return 0
}

export -f mpv_transition_to_video

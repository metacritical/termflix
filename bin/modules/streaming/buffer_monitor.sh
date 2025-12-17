#!/usr/bin/env bash
#
# Termflix Buffer Monitor Module
# Buffer calculation and progress monitoring for torrent streaming
#
# Functions:
#   - calculate_optimal_buffer(): Calculates buffer size based on video bitrate
#   - monitor_buffer_progress(): Monitors download progress from transmission/peerflix
#   - write_buffer_status(): Writes progress to status file for UI
#   - check_buffer_ready(): Determines if buffering threshold reached
#

# Prevent multiple sourcing
[[ -n "${_TERMFLIX_BUFFER_MONITOR_LOADED:-}" ]] && return 0
_TERMFLIX_BUFFER_MONITOR_LOADED=1

# ═══════════════════════════════════════════════════════════════
# BUFFER CALCULATION
# ═══════════════════════════════════════════════════════════════

# Calculate optimal buffer size based on video bitrate
# Args: $1 = video file path, $2 = download speed (bytes/sec)
# Returns: buffer size in bytes
calculate_optimal_buffer() {
    local video_file="$1"
    local download_speed="${2:-0}"
    
    # Default buffer time (seconds)
    local buffer_time=30
    
    # Try to get video bitrate using ffprobe
    local bitrate_bps=0
    if command -v ffprobe &> /dev/null && [ -f "$video_file" ]; then
        # Get video bitrate in bits per second
        bitrate_bps=$(ffprobe -v quiet -select_streams v:0 \
            -show_entries stream=bit_rate \
            -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
        
        # If no video bitrate, try overall bitrate
        if [ -z "$bitrate_bps" ] || [ "$bitrate_bps" = "N/A" ] || [ "$bitrate_bps" -eq 0 ]; then
            bitrate_bps=$(ffprobe -v quiet \
                -show_entries format=bit_rate \
                -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
        fi
    fi
    
    # Calculate buffer size
    local buffer_size=0
    if [ -n "$bitrate_bps" ] && [ "$bitrate_bps" -gt 0 ]; then
        # Formula: (bitrate_bps × buffer_time) / 8
        buffer_size=$((bitrate_bps * buffer_time / 8))
        
        # Adjust buffer time based on download speed
        if [ "$download_speed" -gt 0 ]; then
            local bitrate_bytes=$((bitrate_bps / 8))
            if [ "$download_speed" -gt $((bitrate_bytes * 3 / 2)) ]; then
                # Fast connection: reduce buffer to 20s
                buffer_time=20
                buffer_size=$((bitrate_bps * buffer_time / 8))
            elif [ "$download_speed" -lt "$bitrate_bytes" ]; then
                # Slow connection: increase buffer to 60s
                buffer_time=60
                buffer_size=$((bitrate_bps * buffer_time / 8))
            fi
        fi
    else
        # Fallback: estimate based on file size
        local file_size=$(stat -f%z "$video_file" 2>/dev/null || stat -c%s "$video_file" 2>/dev/null || echo "0")
        if [ "$file_size" -lt 524288000 ]; then
            # < 500MB: likely 480p/720p
            buffer_size=10485760  # 10MB
        elif [ "$file_size" -lt 1610612736 ]; then
            # 500MB-1.5GB: likely 1080p
            buffer_size=31457280  # 30MB
        else
            # > 1.5GB: likely 4K or high bitrate 1080p
            buffer_size=52428800  # 50MB
        fi
    fi
    
    # Apply min/max bounds
    local min_buffer=10485760   # 10MB minimum
    local max_buffer=209715200  # 200MB maximum
    
    if [ "$buffer_size" -lt "$min_buffer" ]; then
        buffer_size=$min_buffer
    elif [ "$buffer_size" -gt "$max_buffer" ]; then
        buffer_size=$max_buffer
    fi
    
    echo "$buffer_size"
}

# ═══════════════════════════════════════════════════════════════
# PROGRESS MONITORING
# ═══════════════════════════════════════════════════════════════

# Monitor buffer progress and write status updates
# Args: $1 = transmission output file, $2 = status file path, $3 = target progress (%)
# Returns: 0 when target reached, 1 on timeout/error
monitor_buffer_progress() {
    local transmission_output="$1"
    local status_file="$2"
    local target_progress="${3:-10}"
    local max_wait="${4:-300}"  # 5 minutes default
    
    local wait_count=0
    local current_progress=0
    local connected_peers=0
    local total_peers=0
    local download_speed=""
    
    while [ $wait_count -lt $max_wait ]; do
        # Parse progress from transmission output
        if [ -f "$transmission_output" ]; then
            local progress_line=$(grep "Progress:" "$transmission_output" 2>/dev/null | tail -1)
            
            if [ -n "$progress_line" ]; then
                # Extract percentage: "Progress: 18.0%" -> 18.0
                current_progress=$(echo "$progress_line" | grep -oE "Progress: [0-9]+\.[0-9]+%" | grep -oE "[0-9]+\.[0-9]+" | head -1)
                
                # Extract peers: "dl from 18 of 49 peers" -> 18 and 49
                local peer_match=$(echo "$progress_line" | grep -oE "dl from [0-9]+ of [0-9]+ peers" 2>/dev/null)
                if [ -n "$peer_match" ]; then
                    connected_peers=$(echo "$peer_match" | grep -oE "[0-9]+" | head -1)
                    total_peers=$(echo "$peer_match" | grep -oE "[0-9]+" | tail -1)
                fi
                
                # Extract download speed: "(1.38 MB/s)"
                download_speed=$(echo "$progress_line" | grep -oE "\([0-9]+\.[0-9]+ [A-Z]+/s\)" | head -1)
            fi
        fi
        
        # Write status update
        write_buffer_status "$status_file" "$current_progress" "$connected_peers" "$total_peers" "$download_speed"
        
        # Check if target reached
        if [ -n "$current_progress" ]; then
            local progress_int=$(echo "$current_progress" | cut -d. -f1)
            if [ "$progress_int" -ge "$target_progress" ]; then
                return 0
            fi
        fi
        
        sleep 0.5
        wait_count=$((wait_count + 1))
    done
    
    return 1  # Timeout
}

# ═══════════════════════════════════════════════════════════════
# STATUS FILE MANAGEMENT
# ═══════════════════════════════════════════════════════════════

# Write buffer status to file for UI consumption
# Args: $1 = status file, $2 = progress (%), $3 = connected peers, $4 = total peers, $5 = speed
write_buffer_status() {
    local status_file="$1"
    local progress="${2:-0}"
    local connected_peers="${3:-0}"
    local total_peers="${4:-0}"
    local speed="${5:-N/A}"
    
    if [ -n "$status_file" ]; then
        cat > "$status_file" <<EOF
PROGRESS=$progress
CONNECTED_PEERS=$connected_peers
TOTAL_PEERS=$total_peers
DOWNLOAD_SPEED=$speed
TIMESTAMP=$(date +%s)
EOF
    fi
}

# Check if buffer is ready based on file size threshold
# Args: $1 = video file path, $2 = target size (bytes), $3 = target progress (%)
# Returns: 0 if ready, 1 if not ready
check_buffer_ready() {
    local video_file="$1"
    local target_size="${2:-52428800}"  # 50MB default
    local target_progress="${3:-10}"    # 10% default
    
    if [ ! -f "$video_file" ]; then
        return 1
    fi
    
    local current_size=$(stat -f%z "$video_file" 2>/dev/null || stat -c%s "$video_file" 2>/dev/null || echo "0")
    
    # Check size threshold
    if [ "$current_size" -ge "$target_size" ]; then
        return 0
    fi
    
    return 1
}

# ═══════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════

export -f calculate_optimal_buffer
export -f monitor_buffer_progress
export -f write_buffer_status
export -f check_buffer_ready

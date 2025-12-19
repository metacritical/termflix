#!/usr/bin/env bash
# Test script for watch history functionality

# Source the watch history module
source bin/modules/watch_history.sh

echo "=== Testing Watch History Module ==="
echo

# Test hash extraction
test_magnet="magnet:?xt=urn:btih:1234567890abcdef&dn=Test+Movie&tr=udp%3A%2F%2Ftracker.example.com%3A1337"
echo "Testing magnet hash extraction:"
echo "Magnet: ${test_magnet:0:50}..."
hash=$(extract_torrent_hash "$test_magnet")
echo "Extracted hash: $hash"
echo

# Test saving watch progress
echo "Testing save_watch_progress:"
save_watch_progress "$hash" "300" "3600" "1080p" "1.5GB" "Test Movie"
echo "Saved progress for 300s of 3600s (8.33%)"
echo

# Test retrieving watch percentage
echo "Testing get_watch_percentage:"
percentage=$(get_watch_percentage "$hash")
echo "Retrieved percentage: $percentage%"
echo

# Test progress bar generation
echo "Testing generate_progress_bar:"
progress_bar=$(generate_progress_bar "$percentage")
echo "Progress bar: $progress_bar"
echo

# Check if watch history file was created and contains data
echo "Checking watch history file:"
if [[ -f "$WATCH_HISTORY_FILE" ]]; then
    echo "Watch history file exists: $WATCH_HISTORY_FILE"
    echo "Contents:"
    cat "$WATCH_HISTORY_FILE" | jq . 2>/dev/null || cat "$WATCH_HISTORY_FILE"
else
    echo "ERROR: Watch history file not found!"
fi
echo

# Test get_watch_position
echo "Testing get_watch_position:"
position=$(get_watch_position "$hash")
echo "Retrieved position: ${position}s"
echo

echo "=== Test Complete ==="
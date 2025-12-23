#!/usr/bin/env bash
#
# Quick Debug Test - Verify Context Variables
#
# This script will help you verify if environment variables
# are being passed correctly to the preview script.

echo "=== Environment Variable Test ==="
echo 

# Test 1: Direct script execution
echo "Test 1: Calling preview_stage2.sh directly"
echo "-------------------------------------------"

TERMFLIX_STAGE2_CONTEXT="search" \
TERMFLIX_STAGE1_CONTEXT="search" \
STAGE2_TITLE="Test Movie" \
STAGE2_POSTER="" \
STAGE2_SOURCES="[YTS][TPB]" \
STAGE2_AVAIL="1080p, 720p" \
STAGE2_PLOT="Test plot" \
STAGE2_IMDB="8.5" \
/Users/pankajdoharey/Development/termflix/modules/ui/previews/preview_stage2.sh 2>&1 | head -20

echo
echo "=== Expected Debug Output ==="
echo "[DEBUG preview_stage2] TERMFLIX_STAGE2_CONTEXT=search"
echo "[DEBUG preview_stage2] TERMFLIX_STAGE1_CONTEXT=search"
echo "[DEBUG preview_stage2] stage2_context=search"
echo "[DEBUG preview_stage2] Hiding catalog (search context)"
echo
echo "If you see those debug lines above, env vars ARE working!"
echo "If debug lines show empty values, env vars are NOT being passed."

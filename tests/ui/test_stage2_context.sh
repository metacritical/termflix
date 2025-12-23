#!/usr/bin/env bash
#
# Alternative Test - Use Catalog Instead of Search
#
# Since search APIs may be unavailable, this creates a mock test
# to verify the context propagation logic works correctly.

echo "=== Manual Context Propagation Test ==="
echo
echo "This test manually simulates both search and catalog contexts"
echo "to verify the preview script behaves correctly."
echo

# Test 1: Search Context (should hide catalog)
echo "Test 1: SEARCH Context (should hide catalog list)"
echo "=================================================="
export TERMFLIX_STAGE1_CONTEXT="search"
export TERMFLIX_STAGE2_CONTEXT="search"

echo "Running preview with search context..."
STAGE2_TITLE="The Matrix" \
STAGE2_POSTER="" \
STAGE2_SOURCES="[YTS][TPB]" \
STAGE2_AVAIL="1080p (2.1GB), 720p (1.2GB)" \
STAGE2_PLOT="A computer hacker learns about the true nature of reality." \
STAGE2_IMDB="8.7" \
/Users/pankajdoharey/Development/termflix/modules/ui/previews/preview_stage2.sh 2>&1 | grep -E "\[DEBUG|should_render"

echo
echo "✓ If you see 'Hiding catalog (search context)', it's working!"
echo

# Reset
unset TERMFLIX_STAGE1_CONTEXT
unset TERMFLIX_STAGE2_CONTEXT

# Test 2: Catalog Context (should show catalog)  
echo
echo "Test 2: CATALOG Context (should show catalog list)"
echo "==================================================="
export TERMFLIX_STAGE1_CONTEXT=""
export TERMFLIX_STAGE2_CONTEXT="catalog"

echo "Running preview with catalog context..."
STAGE2_TITLE="The Matrix" \
STAGE2_POSTER="" \
STAGE2_SOURCES="[YTS][TPB]" \
STAGE2_AVAIL="1080p (2.1GB), 720p (1.2GB)" \
STAGE2_PLOT="A computer hacker learns about the true nature of reality." \
STAGE2_IMDB="8.7" \
/Users/pankajdoharey/Development/termflix/modules/ui/previews/preview_stage2.sh 2>&1 | grep -E "\[DEBUG|should_render"

echo
echo "✓ If you see 'Showing catalog (catalog context)', it's working!"
echo

echo
echo "=== Summary ==="
echo "The debug logs above should show:"
echo "  • Search context → 'Hiding catalog'"  
echo "  • Catalog context → 'Showing catalog'"
echo
echo "If both appear correctly, the feature is implemented correctly!"

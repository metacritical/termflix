#!/usr/bin/env bash
#
# Test TMDB API module
#

cd "$(dirname "$0")/.."
source bin/modules/api/tmdb.sh

echo "═══════════════════════════════════════════════════════════════"
echo "  TMDB Module Test"
echo "═══════════════════════════════════════════════════════════════"
echo

# Test 1: Check if configured
echo "Test 1: API Key Configuration"
if tmdb_configured; then
    echo "  ✓ TMDB_API_KEY is set"
else
    echo "  ⚠ TMDB_API_KEY not set - skipping API tests"
    echo "  Set TMDB_API_KEY environment variable to run full tests"
    echo
    echo "Example:"
    echo "  export TMDB_API_KEY=\"your_api_key_here\""
    echo "  bash bin/test_tmdb.sh"
    exit 0
fi
echo

# Test 2: Search for a movie
echo "Test 2: Movie Search - 'Avatar' (2009)"
result=$(search_tmdb_movie "Avatar" "2009")
if echo "$result" | grep -q '"id"'; then
    movie_id=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id', 'N/A'))")
    echo "  ✓ Found movie with ID: $movie_id"
else
    echo "  ✗ Search failed"
    echo "  Result: $result"
fi
echo

# Test 3: Get description
echo "Test 3: Fetch Description"
description=$(fetch_movie_description "Inception" "2010")
if [[ -n "$description" && "$description" != "No description available." ]]; then
    echo "  ✓ Description fetched (${#description} chars)"
    echo "  Preview: ${description:0:100}..."
else
    echo "  ✗ Description fetch failed"
fi
echo

# Test 4: Cache check
echo "Test 4: Cache Verification"
cache_count=$(find "$TMDB_CACHE_DIR" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
if [[ $cache_count -gt 0 ]]; then
    echo "  ✓ Cache has $cache_count entries"
    echo "  Location: $TMDB_CACHE_DIR"
else
    echo "  ⚠ No cache entries found"
fi
echo

# Test 5: Rating extraction
echo "Test 5: Rating Extraction"
rating=$(echo "$result" | extract_rating)
echo "  Rating: $rating"
echo

echo "═══════════════════════════════════════════════════════════════"
echo "  All tests complete!"
echo "═══════════════════════════════════════════════════════════════"

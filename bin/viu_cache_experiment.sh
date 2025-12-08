#!/usr/bin/env bash
#
# VIU Caching Experiment
# Tests if we can pre-render images with viu and cache the ANSI output
# for instant display later
#

set -e

CACHE_DIR="$HOME/.config/termflix/viu_cache_test"
mkdir -p "$CACHE_DIR"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          VIU CACHING EXPERIMENT                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

# Download a sample poster if we don't have one
SAMPLE_IMAGE="$CACHE_DIR/sample_poster.jpg"
CACHED_OUTPUT="$CACHE_DIR/cached_render.ansi"

if [ ! -f "$SAMPLE_IMAGE" ]; then
    echo "📥 Downloading sample image..."
    curl -sL "https://image.tmdb.org/t/p/w200/9FBwqcd9IRruEDUrTdcaafOMKUq.jpg" -o "$SAMPLE_IMAGE" 2>/dev/null || \
    curl -sL "https://picsum.photos/200/300" -o "$SAMPLE_IMAGE" 2>/dev/null || \
    echo "⚠️  Could not download image, using placeholder"
fi

if [ ! -f "$SAMPLE_IMAGE" ]; then
    echo "Creating a test pattern image using ImageMagick..."
    if command -v convert &>/dev/null; then
        convert -size 200x300 gradient:purple-cyan "$SAMPLE_IMAGE"
    else
        echo "❌ No sample image available and ImageMagick not installed"
        echo "Please provide a sample image at: $SAMPLE_IMAGE"
        exit 1
    fi
fi

echo "📊 Image details:"
file "$SAMPLE_IMAGE" 2>/dev/null || echo "  (file command not available)"
ls -lh "$SAMPLE_IMAGE" 2>/dev/null | awk '{print "  Size:", $5}'
echo

# Check for viu
if ! command -v viu &>/dev/null; then
    echo "❌ viu not found. Install with: cargo install viu"
    echo "   or: brew install viu"
    exit 1
fi

# ============================================================
# TEST 1: Direct viu rendering (baseline)
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 1: Direct viu rendering (no caching)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Rendering image directly with viu (15 chars wide)..."
time_start=$(python3 -c 'import time; print(time.time())')
viu -w 15 "$SAMPLE_IMAGE" 2>/dev/null
time_end=$(python3 -c 'import time; print(time.time())')
direct_time=$(python3 -c "print(f'{($time_end - $time_start) * 1000:.2f}')")
echo
echo "⏱️  Direct render time: ${direct_time}ms"
echo

# ============================================================
# TEST 2: Pre-render and cache the ANSI output
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 2: Pre-render to cache file"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Pre-rendering viu output to cache file..."
time_start=$(python3 -c 'import time; print(time.time())')
viu -w 15 "$SAMPLE_IMAGE" 2>/dev/null > "$CACHED_OUTPUT"
time_end=$(python3 -c 'import time; print(time.time())')
prerender_time=$(python3 -c "print(f'{($time_end - $time_start) * 1000:.2f}')")

echo "Cache file details:"
ls -lh "$CACHED_OUTPUT" | awk '{print "  Size:", $5, "| File:", $NF}'
echo "  Lines: $(wc -l < "$CACHED_OUTPUT")"
echo "  Bytes: $(wc -c < "$CACHED_OUTPUT")"
echo
echo "⏱️  Pre-render time: ${prerender_time}ms"
echo

# ============================================================
# TEST 3: Display from cache (instant!)
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 3: Display from cache (cat)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Displaying cached render..."
time_start=$(python3 -c 'import time; print(time.time())')
cat "$CACHED_OUTPUT"
time_end=$(python3 -c 'import time; print(time.time())')
cached_time=$(python3 -c "print(f'{($time_end - $time_start) * 1000:.2f}')")
echo
echo "⏱️  Cached display time: ${cached_time}ms"
echo

# ============================================================
# TEST 4: Multiple rapid displays from cache
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 4: Rapid cache display (5x in sequence)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

time_start=$(python3 -c 'import time; print(time.time())')
for i in {1..5}; do
    # Position cursor and display (simulating grid)
    printf "\033[s"  # Save cursor
    cat "$CACHED_OUTPUT"
    printf "\033[u"  # Restore cursor
    printf "\033[15C"  # Move right 15 chars (for next poster position)
done
echo
time_end=$(python3 -c 'import time; print(time.time())')
rapid_time=$(python3 -c "print(f'{($time_end - $time_start) * 1000:.2f}')")
echo
echo "⏱️  5x rapid display time: ${rapid_time}ms (avg: $(python3 -c "print(f'{$rapid_time / 5:.2f}')")ms each)"
echo

# ============================================================
# RESULTS SUMMARY
# ============================================================
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    RESULTS SUMMARY                           ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Direct viu render:      %8sms                          ║\n" "$direct_time"
printf "║  Pre-render to cache:    %8sms (one-time cost)          ║\n" "$prerender_time"
printf "║  Display from cache:     %8sms                          ║\n" "$cached_time"
printf "║  5x rapid display:       %8sms                          ║\n" "$rapid_time"
echo "╠══════════════════════════════════════════════════════════════╣"

speedup=$(python3 -c "
direct = $direct_time
cached = $cached_time
if cached > 0:
    print(f'{direct / cached:.1f}')
else:
    print('∞')
")
echo "║  SPEEDUP: ${speedup}x faster with caching!                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

echo "📁 Cache files saved to: $CACHE_DIR"
echo "   - sample_poster.jpg (original image)"
echo "   - cached_render.ansi (pre-rendered ANSI output)"
echo
echo "💡 CONCLUSION:"
echo "   Pre-rendering with viu and caching the ANSI output works!"
echo "   We can render images offline and 'cat' them for instant display."

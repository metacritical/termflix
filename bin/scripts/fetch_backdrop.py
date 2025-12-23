#!/usr/bin/env python3
"""
Google Images Backdrop Fetcher for Termflix
Searches for movie/show backdrops and returns best widescreen image.

Usage:
    python3 fetch_backdrop.py "Movie Name (2024)"
    python3 fetch_backdrop.py "Movie Name" --output /tmp/backdrop.jpg
"""

import sys
import os
import re
import json
import hashlib
import urllib.request
import urllib.parse
from pathlib import Path

# Minimum aspect ratio for widescreen (16:9 = 1.78, we allow 1.5+)
MIN_WIDESCREEN_RATIO = 1.5
CACHE_DIR = Path(os.environ.get('TMPDIR', '/tmp')) / 'termflix_backdrops'
USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15'


def search_google_images(query: str, num_results: int = 5) -> list[str]:
    """
    Search Google Images and extract image URLs.
    Uses the basic image search page scraping method.
    """
    search_url = f"https://www.google.com/search?q={urllib.parse.quote(query)}&tbm=isch&safe=active"
    
    headers = {
        'User-Agent': USER_AGENT,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
    }
    
    try:
        request = urllib.request.Request(search_url, headers=headers)
        with urllib.request.urlopen(request, timeout=10) as response:
            html = response.read().decode('utf-8', errors='ignore')
    except Exception as e:
        print(f"Error fetching Google Images: {e}", file=sys.stderr)
        return []
    
    # Extract image URLs from the page
    # Google embeds image data in JSON-like structures
    image_urls = []
    
    # Pattern 1: Look for full-size image URLs in data attributes
    # These are typically in ["URL",width,height] format
    pattern1 = r'\["(https?://[^"]+\.(?:jpg|jpeg|png|webp))",[0-9]+,[0-9]+\]'
    matches = re.findall(pattern1, html, re.IGNORECASE)
    
    for url in matches:
        # Skip Google's own URLs and thumbnails
        if 'gstatic.com' in url or 'google.com' in url:
            continue
        if 'encrypted-tbn' in url:
            continue
        if url not in image_urls:
            image_urls.append(url)
            if len(image_urls) >= num_results:
                break
    
    # Pattern 2: Fallback - look for image URLs in data-src or similar
    if len(image_urls) < num_results:
        pattern2 = r'data-src="(https?://[^"]+\.(?:jpg|jpeg|png|webp))"'
        matches2 = re.findall(pattern2, html, re.IGNORECASE)
        for url in matches2:
            if url not in image_urls and 'gstatic.com' not in url:
                image_urls.append(url)
                if len(image_urls) >= num_results:
                    break
    
    # Pattern 3: Another fallback for og:image or similar meta tags
    if len(image_urls) < num_results:
        pattern3 = r'"ou":"(https?://[^"]+)"'
        matches3 = re.findall(pattern3, html)
        for url in matches3:
            if url not in image_urls:
                # Unescape URL
                url = url.replace('\\u003d', '=').replace('\\u0026', '&')
                image_urls.append(url)
                if len(image_urls) >= num_results:
                    break
    
    return image_urls[:num_results]


def get_image_dimensions(image_path: str) -> tuple[int, int]:
    """Get image dimensions without external libraries."""
    try:
        with open(image_path, 'rb') as f:
            data = f.read(32)
            
            # JPEG
            if data[:2] == b'\xff\xd8':
                f.seek(0)
                f.read(2)
                while True:
                    marker = f.read(2)
                    if len(marker) < 2:
                        break
                    if marker[0] != 0xff:
                        break
                    if marker[1] == 0xd9:  # EOI
                        break
                    if marker[1] == 0xda:  # SOS
                        break
                    if 0xc0 <= marker[1] <= 0xcf and marker[1] not in (0xc4, 0xc8, 0xcc):
                        length = int.from_bytes(f.read(2), 'big')
                        f.read(1)  # precision
                        height = int.from_bytes(f.read(2), 'big')
                        width = int.from_bytes(f.read(2), 'big')
                        return (width, height)
                    else:
                        length = int.from_bytes(f.read(2), 'big')
                        f.read(length - 2)
            
            # PNG
            elif data[:8] == b'\x89PNG\r\n\x1a\n':
                width = int.from_bytes(data[16:20], 'big')
                height = int.from_bytes(data[20:24], 'big')
                return (width, height)
            
            # GIF
            elif data[:6] in (b'GIF87a', b'GIF89a'):
                width = int.from_bytes(data[6:8], 'little')
                height = int.from_bytes(data[8:10], 'little')
                return (width, height)
            
            # WebP
            elif data[:4] == b'RIFF' and data[8:12] == b'WEBP':
                f.seek(0)
                full_data = f.read(30)
                if full_data[12:16] == b'VP8 ':
                    width = int.from_bytes(full_data[26:28], 'little') & 0x3fff
                    height = int.from_bytes(full_data[28:30], 'little') & 0x3fff
                    return (width, height)
    except Exception:
        pass
    
    return (0, 0)


def download_image(url: str, output_path: str) -> bool:
    """Download image from URL to file."""
    headers = {'User-Agent': USER_AGENT}
    
    try:
        request = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(request, timeout=15) as response:
            with open(output_path, 'wb') as f:
                f.write(response.read())
        return True
    except Exception as e:
        print(f"Error downloading {url}: {e}", file=sys.stderr)
        return False


def is_widescreen(width: int, height: int) -> bool:
    """Check if dimensions are widescreen (aspect ratio >= 1.5)."""
    if height == 0:
        return False
    ratio = width / height
    return ratio >= MIN_WIDESCREEN_RATIO


def fetch_backdrop(movie_title: str, output_path: str = None, content_type: str = "movie") -> str:
    """
    Fetch backdrop for movie/show from Google Images.
    
    Args:
        movie_title: Title with year (e.g., "Night Always Comes (2025)")
        output_path: Optional output path. If not provided, uses cache.
        content_type: "movie" or "show" - determines search query format
    
    Returns:
        Path to downloaded backdrop image, or empty string on failure.
    """
    # Create cache directory
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    
    # Keep title with year for better search results
    clean_title = movie_title.strip()
    
    # Generate cache key from title + type
    cache_key = hashlib.md5(f"{clean_title}_{content_type}".encode()).hexdigest()[:16]
    
    # Check cache first
    cached_file = CACHE_DIR / f"{cache_key}.jpg"
    if cached_file.exists() and cached_file.stat().st_size > 10000:
        return str(cached_file)
    
    # Remove parentheses from year for cleaner search
    clean_search = re.sub(r'\s*\(([12][0-9]{3})\)\s*', r' \1 ', clean_title).strip()
    
    # Search query format based on content type (single query only)
    if content_type == "show":
        search_queries = [f"{clean_search} show backdrop"]
    else:
        search_queries = [f"{clean_search} movie backdrop"]
    
    image_urls = []
    for query in search_queries:
        print(f"🔍 Searching: {query}")  # stdout so user sees it
        urls = search_google_images(query, num_results=5)
        image_urls.extend(urls)
        if len(image_urls) >= 6:
            break
    
    if not image_urls:
        print("No images found", file=sys.stderr)
        return ""
    
    # Try images 1-4, ONLY use widescreen ones
    wide_image = None
    
    for i, url in enumerate(image_urls[:4]):
        temp_file = CACHE_DIR / f"temp_{cache_key}_{i}.jpg"
        
        if download_image(url, str(temp_file)):
            width, height = get_image_dimensions(str(temp_file))
            print(f"Image {i+1}: {width}x{height}", file=sys.stderr)
            
            if is_widescreen(width, height):
                # Found a widescreen image - use it!
                wide_image = temp_file
                print(f"✓ Wide backdrop found!", file=sys.stderr)
                break
            else:
                # Not wide - delete it
                temp_file.unlink(missing_ok=True)
    
    if wide_image and wide_image.exists():
        # Move to final location
        final_path = Path(output_path) if output_path else cached_file
        wide_image.rename(final_path)
        
        # Cleanup other temp files
        for f in CACHE_DIR.glob(f"temp_{cache_key}_*.jpg"):
            try:
                f.unlink()
            except:
                pass
        
        return str(final_path)
    
    return ""


def main():
    if len(sys.argv) < 2:
        print("Usage: fetch_backdrop.py 'Title (Year)' [--type show|movie] [--output /path/to/file.jpg]", file=sys.stderr)
        sys.exit(1)
    
    title = sys.argv[1]
    output_path = None
    content_type = "movie"  # default
    
    if '--output' in sys.argv:
        idx = sys.argv.index('--output')
        if idx + 1 < len(sys.argv):
            output_path = sys.argv[idx + 1]
    
    if '--type' in sys.argv:
        idx = sys.argv.index('--type')
        if idx + 1 < len(sys.argv):
            content_type = sys.argv[idx + 1].lower()
    
    result = fetch_backdrop(title, output_path, content_type)
    
    if result:
        print(result)  # Output path to stdout for bash integration
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()

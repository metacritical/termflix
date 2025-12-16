#!/usr/bin/env python3
"""
Termflix Poster Cache Module
VIU ANSI caching, poster downloading, and display helpers.
Replaces: posters.sh caching and download logic

Usage:
    # As module
    from poster_cache import PosterCache
    cache = PosterCache()
    ansi_file = cache.prerender_viu("poster.jpg", 20, 15)
    
    # As CLI
    python3 poster_cache.py download <url> [output_path]
    python3 poster_cache.py prerender <image_path> [width] [height]
    python3 poster_cache.py hash <text>
    python3 poster_cache.py cleanup
"""
import sys
import os
import hashlib
import subprocess
import urllib.request
import shutil
from pathlib import Path
from typing import Optional, Tuple, List
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

CACHE_BASE = Path.home() / ".config" / "termflix" / "cache"
VIU_CACHE_DIR = CACHE_BASE / "viu_renders"
POSTER_CACHE_DIR = Path.home() / ".cache" / "termflix" / "posters"
POSTER_URL_CACHE = Path.home() / ".cache" / "termflix" / "poster_urls"
CACHE_TTL_DAYS = 7


class PosterCache:
    """Manages poster downloading and VIU ANSI caching"""
    
    def __init__(self):
        # Ensure directories exist
        VIU_CACHE_DIR.mkdir(parents=True, exist_ok=True)
        POSTER_CACHE_DIR.mkdir(parents=True, exist_ok=True)
        POSTER_URL_CACHE.mkdir(parents=True, exist_ok=True)
    
    @staticmethod
    def hash(text: str) -> str:
        """Generate MD5 hash from text"""
        return hashlib.md5(text.encode()).hexdigest()
    
    @staticmethod
    def viu_cache_key(image_source: str, width: int = 15, height: int = 10) -> str:
        """Generate cache key for VIU rendered image"""
        key_input = f"{image_source}_{width}x{height}"
        full_hash = hashlib.md5(key_input.encode()).hexdigest()
        return full_hash[:16]
    
    @staticmethod
    def viu_available() -> bool:
        """Check if viu is installed"""
        return shutil.which('viu') is not None
    
    @staticmethod
    def chafa_available() -> bool:
        """Check if chafa is installed"""
        return shutil.which('chafa') is not None
    
    @staticmethod
    def kitty_available() -> bool:
        """Check if running in Kitty terminal with icat"""
        if os.environ.get('TERM') != 'xterm-kitty':
            return False
        return shutil.which('kitty') is not None
    
    def viu_cache_exists(self, cache_key: str) -> bool:
        """Check if cached VIU render exists and is valid"""
        cache_file = VIU_CACHE_DIR / f"{cache_key}.ansi"
        if cache_file.exists() and cache_file.stat().st_size > 0:
            # Check age
            file_age_days = (time.time() - cache_file.stat().st_mtime) / 86400
            return file_age_days < CACHE_TTL_DAYS
        return False
    
    def get_viu_cache_path(self, cache_key: str) -> Path:
        """Get path to VIU cache file"""
        return VIU_CACHE_DIR / f"{cache_key}.ansi"
    
    def prerender_viu(self, image_path: str, width: int = 15, height: int = 10,
                      cache_key: Optional[str] = None) -> Optional[Path]:
        """
        Pre-render image with viu and cache the ANSI output.
        Returns path to cached ANSI file or None on failure.
        """
        image_file = Path(image_path)
        if not image_file.exists() or image_file.stat().st_size == 0:
            return None
        
        # Generate cache key if not provided
        if not cache_key:
            cache_key = self.viu_cache_key(str(image_file), width, height)
        
        cache_file = VIU_CACHE_DIR / f"{cache_key}.ansi"
        
        # Return cached if exists
        if cache_file.exists() and cache_file.stat().st_size > 0:
            return cache_file
        
        # Check viu availability
        if not self.viu_available():
            return None
        
        # Render with viu
        try:
            result = subprocess.run(
                ['viu', '-w', str(width), '-h', str(height), str(image_file)],
                capture_output=True,
                timeout=10
            )
            if result.returncode == 0 and result.stdout:
                cache_file.write_bytes(result.stdout)
                return cache_file
        except Exception:
            pass
        
        # Cleanup failed cache
        cache_file.unlink(missing_ok=True)
        return None
    
    def download_poster(self, url: str, output_path: Optional[str] = None) -> Optional[Path]:
        """
        Download poster from URL to cache.
        Returns path to downloaded file or None on failure.
        """
        if not url or url in ('N/A', 'null', ''):
            return None
        
        # Generate output path from URL hash
        url_hash = self.hash(url)
        
        if output_path:
            dest = Path(output_path)
        else:
            # Determine extension from URL
            ext = '.jpg'
            if '.png' in url.lower():
                ext = '.png'
            elif '.webp' in url.lower():
                ext = '.webp'
            dest = POSTER_CACHE_DIR / f"{url_hash}{ext}"
        
        # Return if already cached
        if dest.exists() and dest.stat().st_size > 0:
            return dest
        
        # Download
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=10) as response:
                dest.write_bytes(response.read())
            
            if dest.exists() and dest.stat().st_size > 0:
                return dest
        except Exception:
            pass
        
        dest.unlink(missing_ok=True)
        return None
    
    def get_or_download_poster(self, url: str, width: int = 20, height: int = 15) -> Tuple[Optional[Path], Optional[Path]]:
        """
        Download poster if needed and pre-render with VIU.
        Returns (image_path, ansi_cache_path) tuple.
        """
        # Download poster
        image_path = self.download_poster(url)
        if not image_path:
            return None, None
        
        # Pre-render VIU cache
        ansi_path = self.prerender_viu(str(image_path), width, height)
        
        return image_path, ansi_path
    
    def display_cached_viu(self, cache_path: Path) -> bool:
        """Display cached VIU ANSI to stdout"""
        if cache_path.exists() and cache_path.stat().st_size > 0:
            sys.stdout.buffer.write(cache_path.read_bytes())
            sys.stdout.flush()
            return True
        return False
    
    def cleanup_old_cache(self) -> int:
        """
        Clean up cache files older than TTL.
        Returns number of files deleted.
        """
        deleted = 0
        cutoff = time.time() - (CACHE_TTL_DAYS * 86400)
        
        # Clean VIU cache
        for f in VIU_CACHE_DIR.glob("*.ansi"):
            if f.stat().st_mtime < cutoff:
                f.unlink(missing_ok=True)
                deleted += 1
        
        # Clean poster cache
        for f in POSTER_CACHE_DIR.glob("*"):
            if f.is_file() and f.stat().st_mtime < cutoff:
                f.unlink(missing_ok=True)
                deleted += 1
        
        return deleted
    
    def prerender_batch(self, image_paths: list, width: int = 15, height: int = 10) -> list:
        """Pre-render multiple posters (for background caching)"""
        results = []
        for path in image_paths:
            result = self.prerender_viu(path, width, height)
            if result:
                results.append(result)
        return results
    
    def fetch_poster_url(self, title: str) -> Optional[str]:
        """
        Fetch poster URL for a movie title using api.py.
        Uses cached URLs when available.
        """
        title_hash = self.hash(title.lower())
        cache_file = POSTER_URL_CACHE / f"{title_hash}.txt"
        
        # Check URL cache
        if cache_file.exists():
            url = cache_file.read_text().strip()
            if url and url not in ('N/A', 'null', ''):
                return url
        
        # Try to import and use api module
        try:
            script_dir = Path(__file__).parent
            sys.path.insert(0, str(script_dir))
            from api import TermflixAPI
            
            api = TermflixAPI()
            url = api.get_poster_url(title)
            
            if url and url not in ('N/A', 'null', ''):
                cache_file.write_text(url)
                return url
        except Exception:
            pass
        
        return None
    
    def enrich_missing_posters(self, items: List[str], max_enrich: int = 20) -> List[str]:
        """
        Enrich catalog entries with missing posters.
        
        Args:
            items: List of pipe-delimited catalog entries
            max_enrich: Maximum number of items to enrich (per call)
        
        Returns:
            Updated list of catalog entries with posters filled in
        """
        enriched_items = items.copy()
        enriched_count = 0
        
        # Find items needing enrichment
        to_enrich = []
        for i, item in enumerate(items):
            if enriched_count >= max_enrich:
                break
            
            parts = item.split('|')
            if len(parts) < 7:
                continue
            
            poster_url = parts[6] if len(parts) > 6 else ''
            if poster_url in ('N/A', '', 'null'):
                name = parts[1]  # Get title from second field
                to_enrich.append((i, name, parts))
                enriched_count += 1
        
        if not to_enrich:
            return enriched_items
        
        # Fetch posters in parallel
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = {
                executor.submit(self.fetch_poster_url, name): (idx, name, parts)
                for idx, name, parts in to_enrich
            }
            
            for future in as_completed(futures):
                idx, name, parts = futures[future]
                try:
                    new_url = future.result()
                    if new_url and new_url not in ('N/A', 'null', ''):
                        parts[6] = new_url
                        enriched_items[idx] = '|'.join(parts)
                except Exception:
                    pass
        
        return enriched_items


# ═══════════════════════════════════════════════════════════════
# CLI INTERFACE
# ═══════════════════════════════════════════════════════════════

def main():
    """CLI interface for bash scripts"""
    if len(sys.argv) < 2:
        print("Usage: poster_cache.py <command> [args...]", file=sys.stderr)
        print("Commands: download, prerender, hash, cleanup, check", file=sys.stderr)
        sys.exit(1)
    
    command = sys.argv[1]
    cache = PosterCache()
    
    if command == 'download':
        if len(sys.argv) < 3:
            print("Usage: poster_cache.py download <url> [output_path]", file=sys.stderr)
            sys.exit(1)
        url = sys.argv[2]
        output = sys.argv[3] if len(sys.argv) > 3 else None
        result = cache.download_poster(url, output)
        if result:
            print(str(result))
        else:
            sys.exit(1)
    
    elif command == 'prerender':
        if len(sys.argv) < 3:
            print("Usage: poster_cache.py prerender <image_path> [width] [height]", file=sys.stderr)
            sys.exit(1)
        image_path = sys.argv[2]
        width = int(sys.argv[3]) if len(sys.argv) > 3 else 15
        height = int(sys.argv[4]) if len(sys.argv) > 4 else 10
        result = cache.prerender_viu(image_path, width, height)
        if result:
            print(str(result))
        else:
            sys.exit(1)
    
    elif command == 'display':
        if len(sys.argv) < 3:
            print("Usage: poster_cache.py display <ansi_cache_path>", file=sys.stderr)
            sys.exit(1)
        cache_path = Path(sys.argv[2])
        if not cache.display_cached_viu(cache_path):
            sys.exit(1)
    
    elif command == 'hash':
        if len(sys.argv) < 3:
            print("Usage: poster_cache.py hash <text>", file=sys.stderr)
            sys.exit(1)
        print(cache.hash(sys.argv[2]))
    
    elif command == 'cache_key':
        if len(sys.argv) < 3:
            print("Usage: poster_cache.py cache_key <image_path> [width] [height]", file=sys.stderr)
            sys.exit(1)
        image_path = sys.argv[2]
        width = int(sys.argv[3]) if len(sys.argv) > 3 else 15
        height = int(sys.argv[4]) if len(sys.argv) > 4 else 10
        print(cache.viu_cache_key(image_path, width, height))
    
    elif command == 'cleanup':
        deleted = cache.cleanup_old_cache()
        print(f"Deleted {deleted} old cache files", file=sys.stderr)
    
    elif command == 'check':
        print(f"VIU available: {cache.viu_available()}")
        print(f"Chafa available: {cache.chafa_available()}")
        print(f"Kitty available: {cache.kitty_available()}")
        print(f"VIU cache dir: {VIU_CACHE_DIR}")
        print(f"Poster cache dir: {POSTER_CACHE_DIR}")
    
    elif command == 'enrich':
        # Read catalog entries from stdin, enrich missing posters, output to stdout
        max_enrich = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 20
        items = [line.strip() for line in sys.stdin if line.strip()]
        enriched = cache.enrich_missing_posters(items, max_enrich)
        for item in enriched:
            print(item)
    
    elif command == 'fetch_url':
        # Fetch poster URL for a single title
        if len(sys.argv) < 3:
            print("Usage: poster_cache.py fetch_url <title>", file=sys.stderr)
            sys.exit(1)
        title = sys.argv[2]
        url = cache.fetch_poster_url(title)
        if url:
            print(url)
        else:
            print("null")
    
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
TPB API Client with proxy rotation, fallbacks, and caching
Robust client for ThePirateBay API interactions
"""
import json
import time
import os
import urllib.request
import urllib.parse
from pathlib import Path
from typing import List, Dict, Optional

# Import config
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tpb_config import (
    TPB_DOMAINS, CATEGORIES, PRECOMPILED_FILES,
    DEFAULT_TIMEOUT, MAX_RETRIES, RETRY_DELAY_BASE, CACHE_TTL
)

CACHE_DIR = Path.home() / ".cache" / "termflix" / "tpb"


class TPBClient:
    """ThePirateBay API Client with fallback support"""
    
    def __init__(self):
        self.working_domain = None
        self.cache_dir = CACHE_DIR
        self.cache_dir.mkdir(parents=True, exist_ok=True)
    
    def _get_cache_path(self, key: str) -> Path:
        safe_key = key.replace('/', '_').replace('?', '_').replace('&', '_')
        return self.cache_dir / f"{safe_key}.json"
    
    def _read_cache(self, key: str) -> Optional[dict]:
        cache_path = self._get_cache_path(key)
        if cache_path.exists():
            age = time.time() - cache_path.stat().st_mtime
            if age < CACHE_TTL:
                try:
                    return json.loads(cache_path.read_text())
                except:
                    pass
        return None
    
    def _write_cache(self, key: str, data):
        try:
            self._get_cache_path(key).write_text(json.dumps(data))
        except:
            pass
    
    def _fetch_with_fallback(self, path: str, use_cache: bool = True) -> dict:
        """Fetch from TPB with domain fallback and exponential backoff"""
        cache_key = path
        if use_cache:
            cached = self._read_cache(cache_key)
            if cached:
                return cached
        
        # Try working domain first
        domains = TPB_DOMAINS.copy()
        if self.working_domain and self.working_domain in domains:
            domains.remove(self.working_domain)
            domains.insert(0, self.working_domain)
        
        last_error = None
        for domain in domains:
            url = f"{domain}/{path}"
            for attempt in range(MAX_RETRIES):
                try:
                    req = urllib.request.Request(url, headers={
                        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
                    })
                    with urllib.request.urlopen(req, timeout=DEFAULT_TIMEOUT) as resp:
                        data = json.loads(resp.read().decode('utf-8'))
                        self.working_domain = domain
                        if use_cache:
                            self._write_cache(cache_key, data)
                        return data
                except Exception as e:
                    last_error = e
                    delay = RETRY_DELAY_BASE * (2 ** attempt)  # Exponential backoff
                    time.sleep(delay)
                    continue
        
        raise RuntimeError(f"All TPB domains failed: {last_error}")
    
    def get_top100(self, category: str = 'hd_movies') -> List[Dict]:
        """Fetch top 100 for a category"""
        file_name = PRECOMPILED_FILES.get(category, PRECOMPILED_FILES['hd_movies'])
        return self._fetch_with_fallback(f"precompiled/{file_name}")
    
    def search(self, query: str, category: int = 0) -> List[Dict]:
        """Search TPB for torrents"""
        encoded = urllib.parse.quote(query)
        path = f"q.php?q={encoded}&cat={category}"
        data = self._fetch_with_fallback(path, use_cache=False)
        
        if isinstance(data, list):
            # Filter out "no results" placeholder
            return [t for t in data 
                    if t.get('id') != '0' 
                    and t.get('info_hash') != '0' * 40]
        return []
    
    def clear_cache(self):
        """Clear all cached responses"""
        for f in self.cache_dir.glob("*.json"):
            try:
                f.unlink()
            except:
                pass


if __name__ == '__main__':
    # Test the client
    client = TPBClient()
    print("Testing TPB Client...")
    
    try:
        results = client.get_top100('hd_movies')
        print(f"✓ Fetched {len(results)} HD movies")
        
        if results:
            first = results[0]
            print(f"  First: {first.get('name', 'N/A')[:50]}...")
            print(f"  Seeds: {first.get('seeders', 0)}")
    except Exception as e:
        print(f"✗ Error: {e}")

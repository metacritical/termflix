#!/usr/bin/env python3
"""
Termflix - YTS Movie Search (Enhanced)
Searches multiple YTS domains for movies by keyword with:
- Retry logic with exponential backoff
- Response caching with configurable TTL
- Clean magnet links
- Graceful fallback handling

Input: YTS_QUERY environment variable
Output: Pipe-delimited torrent results to stdout

Environment Variables:
- YTS_QUERY: Search query (required)
- YTS_CACHE_TTL: Cache TTL in seconds (default: 3600)
- YTS_CACHE_ENABLED: Enable caching (default: true)
- YTS_MAX_RETRIES: Max retry attempts per domain (default: 3)
- YTS_TIMEOUT: Request timeout in seconds (default: 10)
- TERMFLIX_LOG_LEVEL: Logging level (DEBUG|INFO|WARN|ERROR)
"""
import sys
import re
import urllib.request
import urllib.parse
import os
import ssl
import json
import hashlib
import time
import logging
from pathlib import Path
from datetime import datetime

# ═══════════════════════════════════════════════════════════════
# LOGGING SETUP
# ═══════════════════════════════════════════════════════════════

def setup_logging():
    """Configure logging based on environment variable."""
    level_map = {
        'DEBUG': logging.DEBUG,
        'INFO': logging.INFO,
        'WARN': logging.WARNING,
        'WARNING': logging.WARNING,
        'ERROR': logging.ERROR,
        'NONE': logging.CRITICAL + 1
    }
    
    level_name = os.environ.get('TERMFLIX_LOG_LEVEL', 'WARN').upper()
    level = level_map.get(level_name, logging.WARNING)
    
    # Log to stderr so it doesn't interfere with stdout results
    logging.basicConfig(
        level=level,
        format='[YTS] %(levelname)s: %(message)s',
        stream=sys.stderr
    )
    return logging.getLogger('termflix.yts')

logger = setup_logging()

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Default YTS domains (priority ordered)
DEFAULT_YTS_DOMAINS = [
    'https://yts.lt',    # Primary
    'https://yts.rs',    # Fallback 1
    'https://yts.do',    # Fallback 2
    'https://yts.ag',    # Fallback 3
    'https://yts.am',    # Fallback 4
    'https://yts.pm',    # Fallback 5
    'https://yts.hn',    # Fallback 6
    'https://yts.mx',    # Fallback 7 (last)
]

def get_yts_domains():
    """
    Get YTS domains from environment or use defaults.
    
    Environment variable YTS_DOMAINS can be:
    - Comma-separated list of domains to PREPEND to defaults
    - Example: "https://yts.new,https://yts.custom"
    
    To completely REPLACE defaults, set YTS_DOMAINS_REPLACE=true
    """
    custom_domains_str = os.environ.get('YTS_DOMAINS', '').strip()
    replace_mode = os.environ.get('YTS_DOMAINS_REPLACE', '').lower() in ('1', 'true', 'yes')
    
    if not custom_domains_str:
        return DEFAULT_YTS_DOMAINS.copy()
    
    # Parse custom domains
    custom_domains = []
    for domain in custom_domains_str.split(','):
        domain = domain.strip()
        if domain:
            # Ensure https:// prefix
            if not domain.startswith('http'):
                domain = f'https://{domain}'
            custom_domains.append(domain)
    
    if replace_mode:
        # Completely replace defaults with custom domains
        logger.debug(f"Using custom domains (replace mode): {custom_domains}")
        return custom_domains
    else:
        # Prepend custom domains to defaults (avoiding duplicates)
        combined = custom_domains.copy()
        for domain in DEFAULT_YTS_DOMAINS:
            if domain not in combined:
                combined.append(domain)
        logger.debug(f"Using domains: {combined}")
        return combined

# Get configured domains
YTS_DOMAINS = get_yts_domains()

# Default configuration
DEFAULT_CACHE_TTL = 3600  # 1 hour
DEFAULT_MAX_RETRIES = 3
DEFAULT_TIMEOUT = 10

# Request headers
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
}

# ═══════════════════════════════════════════════════════════════
# CACHE MANAGEMENT
# ═══════════════════════════════════════════════════════════════

class ResponseCache:
    """File-based response cache with TTL support."""
    
    def __init__(self, cache_dir=None, ttl=DEFAULT_CACHE_TTL):
        if cache_dir is None:
            cache_dir = Path.home() / '.config' / 'termflix' / 'cache' / 'yts'
        self.cache_dir = Path(cache_dir)
        self.ttl = ttl
        self._ensure_cache_dir()
    
    def _ensure_cache_dir(self):
        """Create cache directory if it doesn't exist."""
        try:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            logger.warning(f"Could not create cache directory: {e}")
    
    def _get_cache_key(self, key):
        """Generate a safe filename from cache key."""
        return hashlib.md5(key.encode('utf-8')).hexdigest()
    
    def _get_cache_path(self, key):
        """Get full path for cache file."""
        return self.cache_dir / f"{self._get_cache_key(key)}.json"
    
    def get(self, key):
        """
        Get cached value if exists and not expired.
        Returns None if cache miss or expired.
        """
        cache_path = self._get_cache_path(key)
        
        try:
            if not cache_path.exists():
                logger.debug(f"Cache miss: {key[:50]}...")
                return None
            
            with open(cache_path, 'r', encoding='utf-8') as f:
                cached = json.load(f)
            
            # Check expiration
            cached_time = cached.get('timestamp', 0)
            age = time.time() - cached_time
            
            if age > self.ttl:
                logger.debug(f"Cache expired ({age:.0f}s > {self.ttl}s): {key[:50]}...")
                cache_path.unlink(missing_ok=True)
                return None
            
            logger.debug(f"Cache hit ({age:.0f}s old): {key[:50]}...")
            return cached.get('data')
            
        except Exception as e:
            logger.warning(f"Cache read error: {e}")
            return None
    
    def set(self, key, value):
        """Save value to cache with current timestamp."""
        cache_path = self._get_cache_path(key)
        
        try:
            cache_entry = {
                'timestamp': time.time(),
                'key': key,
                'data': value
            }
            
            with open(cache_path, 'w', encoding='utf-8') as f:
                json.dump(cache_entry, f, ensure_ascii=False)
            
            logger.debug(f"Cached: {key[:50]}...")
            
        except Exception as e:
            logger.warning(f"Cache write error: {e}")
    
    def clear(self):
        """Clear all cache files."""
        try:
            for cache_file in self.cache_dir.glob('*.json'):
                cache_file.unlink()
            logger.info("Cache cleared")
        except Exception as e:
            logger.warning(f"Cache clear error: {e}")

# ═══════════════════════════════════════════════════════════════
# MAGNET LINK UTILITIES
# ═══════════════════════════════════════════════════════════════

def clean_magnet(magnet):
    """
    Clean magnet link by removing unnecessary parameters.
    Keeps only the essential xt= (info hash) parameter.
    """
    if not magnet or not magnet.startswith('magnet:'):
        return magnet
    
    try:
        # Parse the magnet URI
        # Format: magnet:?xt=urn:btih:HASH&dn=NAME&tr=TRACKER
        query_start = magnet.find('?')
        if query_start == -1:
            return magnet
        
        query_string = magnet[query_start + 1:]
        params = urllib.parse.parse_qs(query_string)
        
        # Keep only the xt parameter (the info hash)
        if 'xt' in params:
            clean_params = {'xt': params['xt']}
            clean_query = urllib.parse.urlencode(clean_params, doseq=True)
            return f"magnet:?{clean_query}"
        
        return magnet
        
    except Exception as e:
        logger.debug(f"Magnet clean error: {e}")
        return magnet

def extract_hash_from_magnet(magnet):
    """Extract the info hash from a magnet link."""
    match = re.search(r'btih:([a-fA-F0-9]{40})', magnet)
    if match:
        return match.group(1).lower()
    return None

# ═══════════════════════════════════════════════════════════════
# HTTP UTILITIES WITH RETRY
# ═══════════════════════════════════════════════════════════════

def create_ssl_context():
    """Create an SSL context that ignores certificate errors."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx

def fetch_with_retry(url, max_retries=DEFAULT_MAX_RETRIES, timeout=DEFAULT_TIMEOUT, 
                     base_delay=1.0, headers=None):
    """
    Fetch URL with exponential backoff retry.
    
    Args:
        url: URL to fetch
        max_retries: Maximum retry attempts
        timeout: Request timeout in seconds
        base_delay: Base delay for exponential backoff
        headers: Optional headers dict
    
    Returns:
        Response content as string, or None on failure
    """
    if headers is None:
        headers = HEADERS
    
    ctx = create_ssl_context()
    last_error = None
    
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(url, headers=headers)
            
            with urllib.request.urlopen(req, context=ctx, timeout=timeout) as response:
                if response.status == 200:
                    content = response.read().decode('utf-8', errors='ignore')
                    logger.debug(f"Fetch success (attempt {attempt + 1}): {url[:60]}...")
                    return content
                else:
                    logger.warning(f"HTTP {response.status} from {url[:60]}...")
                    
        except urllib.error.HTTPError as e:
            last_error = e
            logger.debug(f"HTTP error {e.code} (attempt {attempt + 1}/{max_retries}): {url[:60]}...")
            
        except urllib.error.URLError as e:
            last_error = e
            logger.debug(f"URL error (attempt {attempt + 1}/{max_retries}): {e.reason}")
            
        except TimeoutError:
            last_error = TimeoutError(f"Timeout after {timeout}s")
            logger.debug(f"Timeout (attempt {attempt + 1}/{max_retries}): {url[:60]}...")
            
        except Exception as e:
            last_error = e
            logger.debug(f"Error (attempt {attempt + 1}/{max_retries}): {type(e).__name__}: {e}")
        
        # Exponential backoff before retry (except on last attempt)
        if attempt < max_retries - 1:
            delay = base_delay * (2 ** attempt)  # 1s, 2s, 4s, ...
            logger.debug(f"Retrying in {delay:.1f}s...")
            time.sleep(delay)
    
    logger.warning(f"All {max_retries} attempts failed for {url[:60]}...")
    return None

# ═══════════════════════════════════════════════════════════════
# DOMAIN MANAGEMENT
# ═══════════════════════════════════════════════════════════════

class DomainManager:
    """Manages YTS domain selection with caching of working domain."""
    
    def __init__(self, cache):
        self.cache = cache
        self.domains = YTS_DOMAINS.copy()
    
    def find_working_domain(self, max_retries=1, timeout=5):
        """
        Find a working YTS domain.
        Checks cached working domain first, then tests each domain.
        
        Returns:
            Working domain URL or None
        """
        # Check cached working domain first
        cached_domain = self.cache.get('working_domain')
        if cached_domain and cached_domain in self.domains:
            logger.debug(f"Using cached domain: {cached_domain}")
            # Quick health check
            if self._test_domain(cached_domain, timeout=3):
                return cached_domain
            logger.debug(f"Cached domain failed health check: {cached_domain}")
        
        # Test each domain
        for domain in self.domains:
            logger.debug(f"Testing domain: {domain}")
            if self._test_domain(domain, timeout=timeout):
                # Cache the working domain
                self.cache.set('working_domain', domain)
                logger.info(f"Found working domain: {domain}")
                return domain
        
        logger.error("No working YTS domain found")
        return None
    
    def _test_domain(self, domain, timeout=5):
        """Test if a domain is reachable and returns valid content."""
        try:
            test_url = f"{domain}/browse-movies"
            ctx = create_ssl_context()
            req = urllib.request.Request(test_url, headers=HEADERS)
            
            with urllib.request.urlopen(req, context=ctx, timeout=timeout) as response:
                if response.status == 200:
                    content = response.read().decode('utf-8', errors='ignore')
                    # Check for expected content markers
                    if 'browse-movie' in content or 'yts' in content.lower():
                        return True
        except Exception as e:
            logger.debug(f"Domain test failed for {domain}: {e}")
        
        return False

# ═══════════════════════════════════════════════════════════════
# YTS SCRAPER
# ═══════════════════════════════════════════════════════════════

class YTSScraper:
    """YTS movie scraper with caching and retry logic."""
    
    def __init__(self, cache_enabled=True, cache_ttl=DEFAULT_CACHE_TTL,
                 max_retries=DEFAULT_MAX_RETRIES, timeout=DEFAULT_TIMEOUT):
        self.cache_enabled = cache_enabled
        self.cache = ResponseCache(ttl=cache_ttl) if cache_enabled else None
        self.max_retries = max_retries
        self.timeout = timeout
        self.domain_manager = DomainManager(self.cache) if self.cache else None
        self.base_url = None
    
    def search(self, query):
        """
        Search YTS for movies matching query.
        
        Args:
            query: Search query string
            
        Returns:
            List of result dicts, or empty list on failure
        """
        if not query:
            return []
        
        # Check cache first
        cache_key = f"search:{query}"
        if self.cache_enabled and self.cache:
            cached_results = self.cache.get(cache_key)
            if cached_results is not None:
                logger.info(f"Returning cached results for: {query}")
                return cached_results
        
        # Find a working domain
        if self.domain_manager:
            self.base_url = self.domain_manager.find_working_domain()
        
        if not self.base_url:
            # Fallback: try domains sequentially
            self.base_url = self._find_domain_with_results(query)
        
        if not self.base_url:
            logger.error("Could not connect to any YTS domain")
            return []
        
        # Search for movies
        results = self._search_movies(query)
        
        # Cache results
        if self.cache_enabled and self.cache and results:
            self.cache.set(cache_key, results)
        
        return results
    
    def _find_domain_with_results(self, query):
        """Try each domain until we find one with results."""
        search_path = f"/browse-movies/{urllib.parse.quote(query)}"
        
        for domain in YTS_DOMAINS:
            url = f"{domain}{search_path}"
            html = fetch_with_retry(url, max_retries=1, timeout=self.timeout)
            
            if html and ('browse-movie-wrap' in html or 'browse-movie-link' in html):
                logger.info(f"Found results on: {domain}")
                return domain
        
        return None
    
    def _search_movies(self, query):
        """Search for movies and parse results."""
        search_url = f"{self.base_url}/browse-movies/{urllib.parse.quote(query)}"
        
        html = fetch_with_retry(
            search_url,
            max_retries=self.max_retries,
            timeout=self.timeout
        )
        
        if not html:
            return []
        
        # Extract movie links
        links = re.findall(
            r'<a[^>]+href=["\']([^"\']*?/movies/[^"\']+)["\'][^>]*class=["\'][^"\']*browse-movie-link',
            html
        )
        if not links:
            links = re.findall(r'<a[^>]+href=["\']([^"\']*?/movies/[^"\']+)["\']', html)
        
        # Deduplicate and normalize links
        movie_links = []
        seen = set()
        for link in links:
            if '/movies/' in link and link not in seen:
                if not link.startswith('http'):
                    link = self.base_url + (link if link.startswith('/') else f"/{link}")
                movie_links.append(link)
                seen.add(link)
        
        # Process top 10 results
        results = []
        for link in movie_links[:10]:
            result = self._parse_movie_page(link)
            if result:
                results.append(result)
        
        return results
    
    def _parse_movie_page(self, url):
        """Parse a movie page and extract torrent info."""
        # Check cache for this movie page
        cache_key = f"movie:{url}"
        if self.cache_enabled and self.cache:
            cached = self.cache.get(cache_key)
            if cached:
                return cached
        
        html = fetch_with_retry(
            url,
            max_retries=self.max_retries,
            timeout=self.timeout
        )
        
        if not html:
            return None
        
        try:
            # Title
            title_m = re.search(r'<h1[^>]*>(.*?)</h1>', html)
            if not title_m:
                return None
            title = title_m.group(1).strip()
            
            # Year
            year_m = re.search(r'<h2[^>]*>(\d{4})</h2>', html)
            if not year_m:
                year_m = re.search(r'class="year"[^>]*>(\d{4})', html)
            year = year_m.group(1) if year_m else ""
            year_str = f" ({year})" if year else ""
            
            # Poster
            poster_m = re.search(
                r'<img[^>]+class="[^"]*hero-poster[^"]*"[^>]+src=["\']([^"\']*)["\']',
                html
            )
            if not poster_m:
                poster_m = re.search(
                    r'<img[^>]+src=["\']([^"\']*)["\'][^>]+class="[^"]*hero-poster',
                    html
                )
            if not poster_m:
                poster_m = re.search(
                    r'<img[^>]+class="[^"]*movie-poster[^"]*"[^>]+src=["\']([^"\']*)["\']',
                    html
                )
            
            poster = poster_m.group(1) if poster_m else "N/A"
            if poster.startswith('/'):
                poster = self.base_url + poster
            
            # Extract magnets
            magnets = re.findall(r'href=["\'](magnet:\?xt=urn:btih:[^"\']+)["\']', html)
            
            if not magnets:
                return None
            
            # Take the first (usually highest quality) magnet
            raw_magnet = magnets[0]
            magnet = clean_magnet(raw_magnet)
            
            # Determine quality
            quality = "720p"  # default
            if "2160p" in html:
                quality = "4K"
            elif "1080p" in html:
                quality = "1080p"
            
            # Size
            size = "N/A"
            size_m = re.search(r'(\d+(?:\.\d+)?\s+[KMGT]B)', html)
            if size_m:
                size = size_m.group(1)
            
            result = {
                'source': 'YTS',
                'title': f"{title}{year_str}",
                'magnet': magnet,
                'quality': quality,
                'size': size,
                'seeds': 'N/A',
                'poster': poster
            }
            
            # Cache the result
            if self.cache_enabled and self.cache:
                self.cache.set(cache_key, result)
            
            return result
            
        except Exception as e:
            logger.debug(f"Parse error for {url}: {e}")
            return None

# ═══════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ═══════════════════════════════════════════════════════════════

def get_config():
    """Get configuration from environment variables."""
    def get_bool(name, default=True):
        val = os.environ.get(name, '').lower()
        if val in ('0', 'false', 'no', 'off'):
            return False
        if val in ('1', 'true', 'yes', 'on'):
            return True
        return default
    
    def get_int(name, default):
        try:
            return int(os.environ.get(name, default))
        except (ValueError, TypeError):
            return default
    
    return {
        'query': os.environ.get('YTS_QUERY', ''),
        'cache_enabled': get_bool('YTS_CACHE_ENABLED', True),
        'cache_ttl': get_int('YTS_CACHE_TTL', DEFAULT_CACHE_TTL),
        'max_retries': get_int('YTS_MAX_RETRIES', DEFAULT_MAX_RETRIES),
        'timeout': get_int('YTS_TIMEOUT', DEFAULT_TIMEOUT),
    }

def main():
    """Main entry point."""
    config = get_config()
    
    query = config['query']
    if not query:
        logger.debug("No query provided")
        return
    
    logger.info(f"Searching YTS for: {query}")
    logger.debug(f"Config: cache={config['cache_enabled']}, ttl={config['cache_ttl']}s, "
                 f"retries={config['max_retries']}, timeout={config['timeout']}s")
    
    scraper = YTSScraper(
        cache_enabled=config['cache_enabled'],
        cache_ttl=config['cache_ttl'],
        max_retries=config['max_retries'],
        timeout=config['timeout']
    )
    
    results = scraper.search(query)
    
    # Output results in pipe-delimited format
    # Format: YTS|Title (Year)|magnet|quality|size|seeds|poster
    for result in results:
        print(f"{result['source']}|{result['title']}|{result['magnet']}|"
              f"{result['quality']}|{result['size']}|{result['seeds']}|{result['poster']}")

if __name__ == "__main__":
    main()

import sys, re, json, urllib.parse, urllib.request, os

def scrape_yts_movies(sort='date_added', order='desc', limit=20, page=1, genre=None, quality='1080p', keyword=None):
    """Scrape movies from YTS website - uses working domains: yts.rs and yts.hn"""
    domains = ['https://yts.mx', 'https://yts.ag', 'https://yts.am', 'https://yts.pm', 'https://yts.lt', 'https://yts.rs', 'https://yts.hn']
    base_url = None
    
    # Test which domain works
    for domain in domains:
        try:
            req = urllib.request.Request(f"{domain}/browse-movies", headers={'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'})
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    base_url = domain
                    break
        except: continue
    
    if not base_url: base_url = 'https://yts.rs'
    
    # Build browse URL
    url = f"{base_url}/browse-movies"
    params = []
    if sort: params.append(f"sort_by={sort}")
    if keyword: params.append(f"keyword={urllib.parse.quote(keyword)}")
    
    if params: url += "?" + "&".join(params)
    
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'})
        with urllib.request.urlopen(req, timeout=15) as response:
            html = response.read().decode('utf-8', errors='ignore')
    except: return []
    
    if not html: return []
    
    movie_links = re.findall(r'<a[^>]+href="/movies/([^"]+)"[^>]*class="[^"]*browse-movie-link[^"]*"[^>]*>', html)
    if not movie_links:
        movie_links = re.findall(r'<a[^>]+href="/movies/([^"]+)"[^>]*>', html)
    
    count = 0
    for slug in movie_links[:limit]:
        try:
            movie_url = f"{base_url}/movies/{slug}"
            req = urllib.request.Request(movie_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=10) as response:
                movie_html = response.read().decode('utf-8', errors='ignore')
            
            title_match = re.search(r'<h1[^>]*>([^<]+)</h1>', movie_html)
            if not title_match: continue
            title = title_match.group(1).strip()
            
            year_match = re.search(r'<span[^>]*class="[^"]*year[^"]*"[^>]*>(\d{4})</span>', movie_html)
            year = year_match.group(1) if year_match else None
            
            poster_match = re.search(r'<img[^>]+class="[^"]*movie-poster[^"]*"[^>]+src="([^"]+)"', movie_html)
            poster = poster_match.group(1) if poster_match else 'N/A'
            if poster.startswith('/'): poster = f"{base_url}{poster}"
            
            hash_match = re.search(r'magnet:\?xt=urn:btih:([a-fA-F0-9]{40})', movie_html)
            if not hash_match: hash_match = re.search(r'data-hash="([a-fA-F0-9]{40})"', movie_html)
            if not hash_match: continue
            hash_val = hash_match.group(1)
            
            quality_match = re.search(r'<span[^>]*class="[^"]*quality[^"]*"[^>]*>([^<]+)</span>', movie_html, re.IGNORECASE)
            quality = quality_match.group(1).strip() if quality_match else "1080p"
            
            size_match = re.search(r'<span[^>]*class="[^"]*size[^"]*"[^>]*>([^<]+)</span>', movie_html, re.IGNORECASE)
            size = size_match.group(1).strip() if size_match else 'N/A'
            
            seeds_match = re.search(r'<span[^>]*class="[^"]*seeds[^"]*"[^>]*>(\d+)</span>', movie_html, re.IGNORECASE)
            seeds = int(seeds_match.group(1)) if seeds_match else 0
            
            year_str = f" ({year})" if year else ""
            extra = f"{seeds} seeds"
            print(f"YTS|{title}{year_str}|magnet:?xt=urn:btih:{hash_val}|{quality}|{size}|{extra}|{poster}", flush=True)
            count += 1
        except: continue

if __name__ == '__main__':
    keyword = sys.argv[1] if len(sys.argv) > 1 else None
    scrape_yts_movies(keyword=keyword, sort='seeds', limit=20)

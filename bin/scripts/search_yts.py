#!/usr/bin/env python3
"""
Termflix - YTS Movie Search
Searches multiple YTS domains for movies by keyword.
Input: YTS_QUERY environment variable
Output: Pipe-delimited torrent results to stdout
"""
import sys
import re
import urllib.request
import urllib.parse
import os
import ssl


def scrape():
    """Search YTS for movies matching query."""
    query = os.environ.get('YTS_QUERY', '')
    if not query:
        return
    
    # Try multiple YTS domains
    domains = [
        'https://yts.mx', 'https://yts.rs', 'https://yts.lt', 
        'https://yts.do', 'https://yts.ag', 'https://yts.am', 
        'https://yts.pm', 'https://yts.hn'
    ]
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    }
    
    # Create SSL context that ignores errors
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    html = None
    base_url = None
    
    for domain in domains:
        try:
            url = f"{domain}/browse-movies/{urllib.parse.quote(query)}"
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, context=ctx, timeout=8) as response:
                if response.status == 200:
                    content = response.read().decode('utf-8', errors='ignore')
                    if 'browse-movie-wrap' in content or 'browse-movie-link' in content:
                        html = content
                        base_url = domain
                        break
        except Exception:
            continue
            
    if not html:
        return

    # Extract movie links
    links = re.findall(r'<a[^>]+href=["\'](.*?/movies/[^"\']+)["\'][^>]*class=["\'][^"\']*browse-movie-link', html)
    if not links:
        links = re.findall(r'<a[^>]+href=["\'](.*?/movies/[^"\']+)["\']', html)
        
    # Filter for actual movie pages
    movie_links = []
    seen = set()
    for link in links:
        if '/movies/' in link and link not in seen:
            if not link.startswith('http'):
                link = base_url + link if link.startswith('/') else f"{base_url}/{link}"
            movie_links.append(link)
            seen.add(link)
            
    # Process top 10 results
    for link in movie_links[:10]:
        try:
            req = urllib.request.Request(link, headers=headers)
            with urllib.request.urlopen(req, context=ctx, timeout=8) as response:
                page = response.read().decode('utf-8', errors='ignore')
                
            # Title
            title_m = re.search(r'<h1[^>]*>(.*?)</h1>', page)
            if not title_m:
                continue
            title = title_m.group(1).strip()
            
            # Year
            year_m = re.search(r'<h2[^>]*>(\d{4})</h2>', page)
            if not year_m:
                year_m = re.search(r'class="year"[^>]*>(\d{4})', page)
            year = year_m.group(1) if year_m else ""
            year_str = f" ({year})" if year else ""
            
            # Poster
            poster_m = re.search(r'<img[^>]+class="[^"]*hero-poster[^"]*"[^>]+src=["\'](.*?)["\']', page)
            if not poster_m:
                poster_m = re.search(r'<img[^>]+src=["\'](.*?)["\'][^>]+class="[^"]*hero-poster', page)
            if not poster_m:
                poster_m = re.search(r'<img[^>]+class="[^"]*movie-poster[^"]*"[^>]+src=["\'](.*?)["\']', page)
                
            poster = poster_m.group(1) if poster_m else "N/A"
            if poster.startswith('/'):
                poster = base_url + poster
            
            # Extract magnets
            magnets = re.findall(r'href=["\'](magnet:\?xt=urn:btih:[^"\']+)["\']', page)
            
            if magnets:
                magnet = magnets[0]
                # Determine quality
                quality = "1080p" if "1080p" in page and "720p" not in page else "720p"
                if "2160p" in page:
                    quality = "4K"
                elif "1080p" in page:
                    quality = "1080p"
                
                # Size
                size = "N/A"
                size_m = re.search(r'(\d+(?:\.\d+)?\s+[KMGT]B)', page)
                if size_m:
                    size = size_m.group(1)
                
                # Output: YTS|Title (Year)|magnet|quality|size|seeds|poster
                print(f"YTS|{title}{year_str}|{magnet}|{quality}|{size}|N/A|{poster}")
                
        except Exception:
            continue


if __name__ == "__main__":
    scrape()

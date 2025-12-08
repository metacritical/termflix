#!/usr/bin/env python3
"""
Termflix - Google Images Poster Search
Fetches movie poster URL from Google Images.
Input: GOOGLE_QUERY environment variable
Output: Poster URL to stdout
"""
import sys
import re
import urllib.request
import urllib.parse
import os
import ssl


def scrape_google():
    """Scrape Google Images for movie poster."""
    query = os.environ.get('GOOGLE_QUERY', '')
    if not query:
        return
    
    # Simple User-Agent
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }
    
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    try:
        url = f"https://www.google.com/search?q={urllib.parse.quote(query)}&tbm=isch"
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            html = response.read().decode('utf-8', errors='ignore')
            
        # Look for http/https image URLs ending in jpg/png/jpeg
        urls = re.findall(r'(https?://[^"]+?\.jpg)', html)
        if not urls:
            urls = re.findall(r'(https?://[^"]+?\.jpeg)', html)
             
        # Filter out google domains
        valid_urls = [u for u in urls if 'google' not in u and 'gstatic' not in u]
        
        if valid_urls:
            print(valid_urls[0])
            return
            
        # Fallback to whatever img src we can find that looks real
        img_srcs = re.findall(r'<img[^>]+src=["\'](https?://[^"\']+)["\']', html)
        valid_srcs = [u for u in img_srcs if 'google' not in u and 'gstatic' not in u and len(u) > 50]
        
        if valid_srcs:
            print(valid_srcs[0])
            return
            
        # Last resort: Any non-google image
        if img_srcs and len(img_srcs) > 1:
            for src in img_srcs:
                if 'gstatic' not in src and 'google' not in src:
                    print(src)
                    return

    except Exception:
        pass


if __name__ == "__main__":
    scrape_google()

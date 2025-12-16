#!/usr/bin/env python3
"""
Generic Torrent Scraper for Termflix
Based on DuckieTV's GenericTorrentSearchEngine approach
Scrapes torrent sites using CSS selectors - no APIs needed!
"""
import sys
import re
import urllib.request
import urllib.parse
from html.parser import HTMLParser
from html import unescape

class GenericTorrentScraper:
    """
    Generic scraper that works with any torrent site by defining:
    - mirror: Base URL
    - search_endpoint: Search URL pattern (%s = query)
    - selectors: CSS-like selectors for extracting data
    """
    
    def __init__(self, config):
        self.mirror = config['mirror'].rstrip('/')
        self.search_endpoint = config['search_endpoint']
        self.selectors = config['selectors']
        self.name = config.get('name', 'Unknown')
    
    def search(self, query, limit=20):
        """Search for torrents and return results"""
        url = self.build_search_url(query)
        html = self.fetch_url(url)
        
        if not html:
            return []
        
        results = self.parse_results(html)
        return results[:limit]
    
    def build_search_url(self, query):
        """Build search URL from query"""
        encoded_query = urllib.parse.quote_plus(query)
        url = self.mirror + self.search_endpoint.replace('%s', encoded_query)
        return url
    
    def fetch_url(self, url, timeout=10):
        """Fetch URL with proper headers"""
        try:
            req = urllib.request.Request(url, headers={
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9',
            })
            
            with urllib.request.urlopen(req, timeout=timeout) as response:
                return response.read().decode('utf-8', errors='ignore')
        except Exception as e:
            print(f"Error fetching {url}: {e}", file=sys.stderr)
            return None
    
    def parse_results(self, html):
        """Parse HTML and extract torrent results using selectors"""
        results = []
        
        # Simple regex-based selector parsing (not full CSS, but works for most cases)
        container_selector = self.selectors['result_container']
        
        # Extract result blocks using regex
        # This is a simplified approach - for production, use BeautifulSoup
        result_blocks = self.extract_blocks(html, container_selector)
        
        for block in result_blocks:
            try:
                result = {
                    'title': self.extract_field(block, self.selectors.get('title', '')),
                    'magnet': self.extract_field(block, self.selectors.get('magnet', '')),
                    'size': self.extract_field(block, self.selectors.get('size', '')),
                    'seeders': self.extract_field(block, self.selectors.get('seeders', '')),
                    'leechers': self.extract_field(block, self.selectors.get('leechers', ''))
                }
                
                # Only add if we have at least title and magnet
                if result['title'] and result['magnet']:
                    # Clean up values
                    result['title'] = unescape(result['title']).strip()
                    result['seeders'] = self.parse_number(result['seeders'])
                    result['leechers'] = self.parse_number(result['leechers'])
                    result['size'] = result['size'].strip() if result['size'] else 'N/A'
                    
                    results.append(result)
            except Exception as e:
                # Skip malformed results
                continue
        
        return results
    
    def extract_blocks(self, html, selector):
        """Extract result blocks from HTML"""
        # Simplified: split by common row patterns
        # For <tr>, <div class="result">, etc.
        
        if '<tr' in html.lower():
            # Table-based results
            blocks = re.findall(r'<tr[^>]*>.*?</tr>', html, re.DOTALL | re.IGNORECASE)
        elif 'class="result' in html.lower():
            blocks = re.findall(r'<div[^>]*class="[^"]*result[^"]*"[^>]*>.*?</div>', html, re.DOTALL | re.IGNORECASE)
        else:
            # Fallback: try to find repeating patterns
            blocks = re.findall(r'<div[^>]*>.*?</div>', html, re.DOTALL | re.IGNORECASE)
        
        return blocks[:100]  # Limit to first 100 blocks
    
    def extract_field(self, html_block, pattern):
        """Extract field from HTML block using pattern"""
        if not pattern:
            return ''
        
        # Pattern can be:
        # - 'magnet:' for direct magnet links
        # - 'href="([^"]+)"' for href attributes
        # - '>([^<]+)<' for text content
        
        if pattern == 'magnet:':
            # Extract magnet link
            match = re.search(r'(magnet:\?xt=urn:btih:[A-F0-9]{40}[^"\s<>]*)', html_block, re.IGNORECASE)
            return match.group(1) if match else ''
        
        # Generic pattern matching
        match = re.search(pattern, html_block, re.IGNORECASE | re.DOTALL)
        if match:
            return match.group(1) if match.groups() else match.group(0)
        
        return ''
    
    def parse_number(self, value):
        """Parse number from string (handles '1,234' format)"""
        if not value:
            return 0
        
        # Remove commas and extract first number
        cleaned = re.sub(r'[,\s]', '', str(value))
        match = re.search(r'\d+', cleaned)
        return int(match.group(0)) if match else 0


# Site Configurations
SITE_CONFIGS = {
    '1337x': {
        'name': '1337x',
        'mirror': 'https://1337x.to',
        'search_endpoint': '/search/%s/1/',
        'selectors': {
            'result_container': 'tr',
            'title': r'<td class="coll-1[^>]*>.*?<a[^>]*>([^<]+)</a>',
            'magnet': 'magnet:',
            'size': r'<td class="coll-4[^>]*>([^<]+)<',
            'seeders': r'<td class="coll-2[^>]*>([^<]+)<',
            'leechers': r'<td class="coll-3[^>]*>([^<]+)<'
        }
    },
    'yts_lt': {
        'name': 'YTS.LT',
        'mirror': 'https://yts.lt',
        'search_endpoint': '/browse-movies/%s/all/all/0/latest',
        'selectors': {
            'result_container': 'div class="browse-movie',
            'title': r'<a[^>]*class="browse-movie-title"[^>]*>([^<]+)</a>',
            'magnet': 'magnet:',
            'size': r'<p class="[^"]*">([0-9.]+\s*[KMG]B)</p>',
            'seeders': r'',  # YTS doesn't show seeders on browse page
            'leechers': r''
        }
    },
    'limetorrents': {
        'name': 'LimeTorrents',
        'mirror': 'https://www.limetorrents.lol',
        'search_endpoint': '/search/all/%s/',
        'selectors': {
            'result_container': 'tr',
            'title': r'<div class="tt-name">.*?<a[^>]*>([^<]+)</a>',
            'magnet': 'magnet:',
            'size': r'<td class="tdnormal">([^<]+)</td>',
            'seeders': r'<td class="tdseed">([^<]+)</td>',
            'leechers': r'<td class="tdleech">([^<]+)</td>'
        }
    }
}


def main():
    """Main function - CLI interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Generic Torrent Scraper')
    parser.add_argument('query', help='Search query')
    parser.add_argument('--site', default='1337x', choices=SITE_CONFIGS.keys(), help='Site to scrape')
    parser.add_argument('--limit', type=int, default=20, help='Max results')
    
    args = parser.parse_args()
    
    # Get site config
    config = SITE_CONFIGS[args.site]
    scraper = GenericTorrentScraper(config)
    
    # Search
    results = scraper.search(args.query, args.limit)
    
    # Output in termflix format: SOURCE|NAME|MAGNET|QUALITY|SIZE|SEEDS|POSTER
    for result in results:
        print(f"{config['name']}|{result['title']}|{result['magnet']}|N/A|{result['size']}|{result['seeders']}|N/A")
    
    return 0 if results else 1


if __name__ == '__main__':
    sys.exit(main())

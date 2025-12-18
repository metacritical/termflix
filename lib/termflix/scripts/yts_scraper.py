#!/usr/bin/env python3
"""
YTS Web Scraper - Scrapes movie data from YTS website
Fallback when API fails or has limits
"""

import re
import sys
import urllib.request
import urllib.parse
from typing import List, Dict, Optional
from html.parser import HTMLParser


class YTSMovieParser(HTMLParser):
    """Parse YTS HTML to extract movie data"""
    
    def __init__(self):
        super().__init__()
        self.movies = []
        self.current_movie = {}
        self.in_movie_card = False
        self.in_title = False
        self.in_year = False
        self.in_genres = False
        self.in_rating = False
        
    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        
        # Detect movie card start
        if tag == 'div' and attrs_dict.get('class') == 'movie-card':
            self.in_movie_card = True
            self.current_movie = {}
            
            # Extract from onclick: openModal(ID, "IMDB", "Title", "Year")
            onclick = attrs_dict.get('onclick', '')
            match = re.search(r'openModal\((\d+),\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)"\)', onclick)
            if match:
                self.current_movie['id'] = match.group(1)
                self.current_movie['imdb'] = match.group(2)
                self.current_movie['title'] = match.group(3)
                self.current_movie['year'] = match.group(4)
        
        # Extract poster
        elif self.in_movie_card and tag == 'img' and 'movie-poster' in attrs_dict.get('class', ''):
            self.current_movie['poster'] = attrs_dict.get('src', '')
        
        # Extract quality
        elif self.in_movie_card and tag == 'span' and 'movie-quality' in attrs_dict.get('class', ''):
            # Next data will be quality
            pass
        
        # Extract rating
        elif self.in_movie_card and tag == 'span' and 'movie-rating' in attrs_dict.get('class', ''):
            self.in_rating = True
        
        # Title
        elif self.in_movie_card and tag == 'h3' and 'movie-title' in attrs_dict.get('class', ''):
            self.in_title = True
        
        # Year
        elif self.in_movie_card and tag == 'span' and 'movie-year' in attrs_dict.get('class', ''):
            self.in_year = True
        
        # Genres
        elif self.in_movie_card and tag == 'span' and 'movie-genres' in attrs_dict.get('class', ''):
            self.in_genres = True
    
    def handle_data(self, data):
        data = data.strip()
        if not data or not self.in_movie_card:
            return
        
        # Extract rating (remove star icon, get number)
        if self.in_rating and data and data[0].isdigit():
            self.current_movie['rating'] = data
            self.in_rating = False
        
        # Year
        elif self.in_year and data.isdigit():
            self.current_movie['year'] = data
            self.in_year = False
        
        # Genres
        elif self.in_genres:
            self.current_movie['genres'] = data
            self.in_genres = False
        
        # Quality (look for patterns like 720p, 1080p)
        elif re.match(r'^\d+p$|^3D$|^4K$', data):
            self.current_movie['quality'] = data
    
    def handle_endtag(self, tag):
        if tag == 'div' and self.in_movie_card:
            # Check if we have minimal data
            if 'title' in self.current_movie and 'imdb' in self.current_movie:
                self.movies.append(self.current_movie.copy())
            self.in_movie_card = False
            self.current_movie = {}


def scrape_yts_page(page: int = 1, sort: str = 'date_added', search: str = '', 
                    genre: str = '', quality: str = '', rating: str = '', year: str = '') -> List[Dict]:
    """
    Scrape YTS website for movies with full filter support
    
    Args:
        page: Page number (1-3589)
        sort: Sort by (date_added, year, rating, seeds, download_count, title)
        search: Search query
        genre: Genre filter
        quality: Quality filter (720p, 1080p, 2160p, 3D)
        rating: Minimum rating (1-9)
        year: Year filter
    
    Returns:
        List of movie dicts with: title, imdb, year, rating, genres, quality, poster
    """
    try:
        # Build URL with all params like YTS website
        params = {
            'page': page,
            'search': search,
            'genre': genre,
            'sort': sort,
            'quality': quality,
            'rating': rating,
            'year': year
        }
        url = f"https://en.ytsrs.com/?{urllib.parse.urlencode(params)}"
        headers = {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        }
        
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as response:
            html = response.read().decode('utf-8', errors='ignore')
        
        # Parse HTML
        parser = YTSMovieParser()
        parser.feed(html)
        
        return parser.movies
        
    except Exception as e:
        print(f"Error scraping YTS: {e}", file=sys.stderr)
        return []


def format_for_termflix(movies: List[Dict]) -> None:
    """Format movies for Termflix output (pipe-separated)"""
    for movie in movies:
        # Format: Title|Year|Rating|Genre|Quality|IMDB|Poster
        title = movie.get('title', 'Unknown')
        year = movie.get('year', '')
        rating = movie.get('rating', '0')
        genres = movie.get('genres', '').replace(' • ', '/')
        quality = movie.get('quality', '720p')
        imdb = movie.get('imdb', '')
        poster = movie.get('poster', '')
        
        # Output format compatible with existing catalog
        print(f"{title}|{year}|{rating}|{genres}|{quality}|{imdb}|{poster}")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: yts_scraper.py <page> [sort] [search] [genre] [quality] [rating] [year]", file=sys.stderr)
        sys.exit(1)
    
    page = int(sys.argv[1])
    sort = sys.argv[2] if len(sys.argv) > 2 else 'date_added'
    search = sys.argv[3] if len(sys.argv) > 3 else ''
    genre = sys.argv[4] if len(sys.argv) > 4 else ''
    quality = sys.argv[5] if len(sys.argv) > 5 else ''
    rating = sys.argv[6] if len(sys.argv) > 6 else ''
    year = sys.argv[7] if len(sys.argv) > 7 else ''
    
    movies = scrape_yts_page(page, sort, search, genre, quality, rating, year)
    if movies:
        format_for_termflix(movies)
    else:
        sys.exit(1)

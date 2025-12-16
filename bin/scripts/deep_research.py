#!/usr/bin/env python3
"""
Deep Research Module
For each movie, performs additional searches to find more torrent versions
(4K, BluRay, x265, different encoders, etc.)
"""
import sys
import os
import time
from typing import List, Dict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tpb_client import TPBClient
from tpb_config import CATEGORIES, QUALITY_SEARCH_TERMS
from unified_aggregator import UnifiedAggregator


def deep_research_movie(
    client: TPBClient,
    aggregator: UnifiedAggregator,
    title: str,
    year: str,
    category: int = 0,
    delay: float = 0.5
) -> int:
    """
    Perform deep research for a single movie.
    Searches for various quality versions and adds to aggregator.
    
    Returns: number of new torrents found
    """
    initial_count = len(aggregator.seen_hashes)
    
    # Base search
    base_query = f"{title} {year}" if year else title
    try:
        results = client.search(base_query, category)
        aggregator.add_tpb_results(results, title_override=title, year_override=year)
    except:
        pass
    
    # Quality-specific searches
    for quality in QUALITY_SEARCH_TERMS:
        time.sleep(delay)  # Rate limiting
        try:
            query = f"{title} {year} {quality}"
            results = client.search(query, category)
            aggregator.add_tpb_results(results, title_override=title, year_override=year)
        except:
            continue
    
    new_count = len(aggregator.seen_hashes) - initial_count
    return new_count


def deep_research_catalog(
    movies: List[Dict],
    category: str = 'hd_movies',
    max_movies: int = 50,
    progress_callback=None
) -> UnifiedAggregator:
    """
    Perform deep research on a list of movies.
    
    Args:
        movies: List of movie dicts with 'title' and 'year'
        category: TPB category for searching
        max_movies: Maximum movies to research
        progress_callback: Function(current, total, title) for progress updates
    
    Returns: UnifiedAggregator with all collected torrents
    """
    client = TPBClient()
    aggregator = UnifiedAggregator()
    
    cat_code = CATEGORIES.get(category, 0)
    
    for i, movie in enumerate(movies[:max_movies]):
        title = movie.get('title', '')
        year = movie.get('year', '')
        
        if not title:
            continue
        
        if progress_callback:
            progress_callback(i + 1, min(len(movies), max_movies), title)
        
        # First, add existing torrents from the movie
        for torrent in movie.get('torrents', []):
            aggregator.add_torrent(
                source='TPB',
                title=title,
                year=year,
                name=torrent.get('name', ''),
                info_hash=torrent.get('hash', torrent.get('info_hash', '')),
                seeders=torrent.get('seeders', 0),
                leechers=torrent.get('leechers', 0),
                size_bytes=torrent.get('size_bytes', torrent.get('size', 0)),
                imdb_id=movie.get('imdb_id', ''),
                poster=movie.get('poster', ''),
                rating=movie.get('rating', '')
            )
        
        # Then perform deep research
        deep_research_movie(client, aggregator, title, year, cat_code, delay=0.3)
        
        # Small delay between movies
        time.sleep(0.2)
    
    return aggregator


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Deep research TPB catalog')
    parser.add_argument('--category', '-c', default='hd_movies')
    parser.add_argument('--limit', '-l', type=int, default=5)
    parser.add_argument('--output', '-o', default='json')
    
    args = parser.parse_args()
    
    # Fetch initial catalog
    client = TPBClient()
    print(f"Fetching Top 100 {args.category}...", file=sys.stderr)
    catalog = client.get_top100(args.category)
    
    # Extract movie info
    from fetch_tpb_catalog import extract_movie_info
    
    movies = []
    seen = set()
    for torrent in catalog:
        title, year = extract_movie_info(torrent.get('name', ''))
        if title:
            key = f"{title.lower()}_{year}"
            if key not in seen:
                seen.add(key)
                movies.append({
                    'title': title,
                    'year': year,
                    'torrents': [torrent]
                })
    
    def progress(current, total, title):
        print(f"\r[{current}/{total}] Researching: {title[:40]:<40}", end='', file=sys.stderr)
    
    print(f"Deep researching {len(movies[:args.limit])} movies...", file=sys.stderr)
    
    aggregator = deep_research_catalog(
        movies, 
        category=args.category, 
        max_movies=args.limit,
        progress_callback=progress
    )
    
    print("\n", file=sys.stderr)
    
    stats = aggregator.stats()
    print(f"✓ Found {stats['movies']} movies with {stats['torrents']} total torrents", file=sys.stderr)
    
    if args.output == 'json':
        print(aggregator.to_json())

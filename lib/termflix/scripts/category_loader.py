#!/usr/bin/env python3
"""
Termflix Category Loader
Used by FZF keybinds to reload catalog with different category.

Usage:
    python3 category_loader.py latest [limit]
    python3 category_loader.py trending [limit]
    python3 category_loader.py popular [limit]
    python3 category_loader.py shows [limit]
    python3 category_loader.py genre <genre> [limit]
    python3 category_loader.py search <query> [limit]
"""
import sys
import os

# Add scripts dir to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from catalog import CatalogFetcher


def main():
    if len(sys.argv) < 2:
        print("Usage: category_loader.py <category> [limit]", file=sys.stderr)
        sys.exit(1)
    
    category = sys.argv[1]
    limit = 50
    
    # Parse limit from args
    for arg in sys.argv[2:]:
        if arg.isdigit():
            limit = int(arg)
            break
    
    fetcher = CatalogFetcher()
    items = []
    
    if category == 'latest':
        # Use enriched catalog: gets TPB top 100, then searches TPB+YTS for each movie
        items = fetcher.get_enriched_catalog(limit=min(limit, 20))
    elif category == 'trending':
        items = fetcher.get_trending(limit)
    elif category == 'popular':
        items = fetcher.get_popular(limit)
    elif category == 'shows':
        items = fetcher.get_shows(limit)
    elif category == 'genre':
        genre = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].isdigit() else 'action'
        items = fetcher.get_by_genre(genre, limit)
    elif category == 'search':
        query = sys.argv[2] if len(sys.argv) > 2 else ''
        if query:
            # Search both TPB and YTS
            tpb_items = fetcher.search_tpb(query, limit)
            yts_items = fetcher.search_yts(query, 5)
            items = tpb_items + yts_items
    else:
        # Default to enriched latest
        items = fetcher.get_enriched_catalog(limit=min(limit, 20))
    
    # Output in FZF-compatible format: "idx|source|name|magnet|quality|size|extra|poster"
    for i, item in enumerate(items, 1):
        # Format: "display_line|index|full_data"
        display = f"{i:3d}. {item.name}"
        full_data = item.to_pipe_format()
        print(f"{display}|{i}|{full_data}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Combine and deduplicate results from multiple sources
Groups movies by normalized title and year, combines sources, seeds, and qualities
"""

import sys
import re
from collections import defaultdict

def normalize_title(title):
    """Normalize movie title for matching"""
    # Remove year, special chars, convert to lowercase, remove extra spaces
    title = re.sub(r'\s*\([0-9]{4}\).*', '', title)  # Remove year
    title = re.sub(r'\[.*?\]', '', title)  # Remove brackets
    title = re.sub(r'[^a-zA-Z0-9 ]', '', title)  # Remove special chars
    title = title.lower().strip()
    title = re.sub(r'\s+', ' ', title)  # Normalize spaces
    return title

def extract_year(name):
    """Extract year from movie name"""
    match = re.search(r'\(([0-9]{4})\)', name)
    return match.group(1) if match else ""

def extract_seeds(text):
    """Extract seed count from text"""
    match = re.search(r'(\d+)\s*seeds?', text, re.IGNORECASE)
    return int(match.group(1)) if match else 0

def main():
    results = []
    for line in sys.stdin:
        line = line.strip()
        if not line or '|' not in line:
            continue
        results.append(line)
    
    # Group by normalized title and year
    movie_groups = defaultdict(list)
    
    for result in results:
        parts = result.split('|')
        if len(parts) < 7:
            continue
        
        source = parts[0]
        name = parts[1]
        magnet = parts[2]
        quality = parts[3]
        size = parts[4]
        extra = parts[5]
        poster = parts[6] if len(parts) > 6 else "N/A"
        
        # Extract title and year
        title = re.sub(r'\s*\([0-9]{4}\).*', '', name).strip()
        title = re.sub(r'\[.*?\]', '', title).strip()
        year = extract_year(name)
        normalized = normalize_title(title)
        
        # Extract seeds
        seeds = extract_seeds(extra) or extract_seeds(quality) or 0
        
        # Create key for grouping
        key = f"{normalized}|{year}"
        
        movie_groups[key].append({
            'source': source,
            'name': name,
            'title': title,
            'year': year,
            'magnet': magnet,
            'quality': quality,
            'seeds': seeds,
            'poster': poster
        })
    
    # Build combined results
    combined = []
    for key, movies in movie_groups.items():
        if not movies:
            continue
        
        # Use first movie's name as display name
        display_name = movies[0]['name']
        
        # Collect all sources, seeds, qualities, magnets
        sources = []
        seeds_list = []
        qualities_list = []
        magnets_list = []
        posters = []
        
        for movie in movies:
            sources.append(movie['source'])
            seeds_list.append(str(movie['seeds']))
            qualities_list.append(movie['quality'])
            magnets_list.append(movie['magnet'])
            posters.append(movie['poster'])
        
        # Get best poster (first non-N/A)
        best_poster = "N/A"
        for poster in posters:
            if poster and poster != "N/A" and poster != "null":
                best_poster = poster
                break
        
        # Format: COMBINED|display_name|sources|seeds|qualities|magnets|poster
        combined.append(f"COMBINED|{display_name}|{'|'.join(sources)}|{'|'.join(seeds_list)}|{'|'.join(qualities_list)}|{'|'.join(magnets_list)}|{best_poster}")
    
    # Output combined results
    for line in combined:
        print(line)

if __name__ == '__main__':
    main()

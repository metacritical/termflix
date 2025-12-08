#!/usr/bin/env python3
"""
Termflix - Group Results by Title and Year
Reads pipe-delimited torrent results from stdin and groups duplicates.
"""
import sys
import re
from collections import defaultdict


def extract_year(name):
    """Extract year (19xx-20xx) from torrent name."""
    # Try 4 digits in parens (19xx-20xx)
    match = re.search(r'\((19[2-9][0-9]|20[0-2][0-9])\)', name)
    if match:
        return match.group(1)
    
    # Try just 4 digits 19xx-20xx surrounded by non-alnum or start/end
    match = re.search(r'(?:^|[\W_])(19[2-9][0-9]|20[0-2][0-9])(?:$|[\W_])', name)
    if match:
        return match.group(1)
    
    return ""


def normalize_title(title, year):
    """Normalize title for grouping purposes."""
    # Replace separators with spaces
    t = re.sub(r'[._\-\+]', ' ', title)
    
    if year:
        # Remove the year from the title
        t = t.replace(year, "")
        
    # Remove content in parens/brackets
    t = re.sub(r'\(.*?\)', '', t)
    t = re.sub(r'\[.*?\]', '', t)
    
    # Remove common quality tags to avoid them being part of title
    tags = ['1080p', '720p', '480p', 'bluray', 'web-dl', 'webrip', 'hdr', 'hdrip', 
            'ts', 'tc', 'cam', 'rip', 'x264', 'x265', 'hevc', 'aac', 'yts', 'yify', 
            'rarbg', 'eztv']
    for tag in tags:
        t = re.sub(r'\b' + tag + r'\b', '', t, flags=re.IGNORECASE)

    # Remove version tags like v2, v3
    t = re.sub(r'\bv[0-9]+\b', '', t, flags=re.IGNORECASE)
    
    # Remove non-alphanumeric characters (keep spaces)
    t = re.sub(r'[^a-zA-Z0-9 ]', '', t)
    
    # Collapse multiple spaces and strip
    t = re.sub(r'\s+', ' ', t).strip()
    return t.lower()


def extract_seeds(text):
    """Extract seed count from text."""
    match = re.search(r'(\d+)', str(text))
    return int(match.group(1)) if match else 0


def print_combined(items, preferred_year=""):
    """Print combined result for a group of items."""
    if not items:
        return
    
    if len(items) == 1:
        print(items[0]['original'])
        return

    # Pick best display name
    best_name = items[0]['name']
    
    # Prefer name with the preferred year if available
    if preferred_year:
        for item in items:
            if preferred_year in item['name']:
                best_name = item['name']
                break
    else:
        # Otherwise prefer names with any year
        for item in items:
            if re.search(r'\d{4}', item['name']):
                best_name = item['name']
                break
                
    sources = [i['source'] for i in items]
    qualities = [i['quality'] for i in items]
    sizes = [i['size'] for i in items]
    seeds = [str(i['seeds']) for i in items]
    magnets = [i['magnet'] for i in items]
    
    best_poster = "N/A"
    for item in items:
        if item['poster'] and item['poster'] != "N/A":
            best_poster = item['poster']
            break
            
    # Format: COMBINED|Name|Sources|Qualities|Seeds|Sizes|Magnets|Poster
    # (Note: bash expects qualities before seeds)
    combined_line = f"COMBINED|{best_name}|{'^'.join(sources)}|{'^'.join(qualities)}|{'^'.join(seeds)}|{'^'.join(sizes)}|{'^'.join(magnets)}|{best_poster}"
    print(combined_line)


def main():
    """Main processing - read from stdin, group results, output to stdout."""
    results = []
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line or '|' not in line:
                continue
            results.append(line)
    except Exception:
        pass

    # First pass: Group by Normalized Title
    title_groups = defaultdict(list)

    for line in results:
        parts = line.split('|')
        if len(parts) < 6:
            continue
        
        source = parts[0]
        name = parts[1]
        magnet = parts[2]
        quality = parts[3]
        size = parts[4]
        seeds_text = parts[5] if len(parts) > 5 else "0"
        poster = parts[6] if len(parts) > 6 else "N/A"
        
        year = extract_year(name)
        title = normalize_title(name, year)
        
        if not title:
            continue
        
        item = {
            'original': line,
            'source': source,
            'name': name,
            'magnet': magnet,
            'quality': quality,
            'size': size,
            'seeds': extract_seeds(seeds_text),
            'poster': poster,
            'year': year
        }
        
        title_groups[title].append(item)

    # Second pass: Analyze years within each title group
    for title, items in title_groups.items():
        # Collect all non-empty years found in this group
        known_years = set(i['year'] for i in items if i['year'])
        
        if len(known_years) == 0:
            # No years found, assume all are same movie
            print_combined(items)
            
        elif len(known_years) == 1:
            # One valid year found (e.g. 1973).
            # Assume items with NO year also belong to this movie
            single_year = list(known_years)[0]
            print_combined(items, preferred_year=single_year)
            
        else:
            # Multiple different years found (e.g. "Total Recall" 1990 vs 2012)
            # Split valid years into separate groups.
            by_year = defaultdict(list)
            for i in items:
                y = i['year'] if i['year'] else "unknown"
                by_year[y].append(i)
                
            for y, sub_items in by_year.items():
                print_combined(sub_items, preferred_year=(y if y != "unknown" else ""))


if __name__ == "__main__":
    main()

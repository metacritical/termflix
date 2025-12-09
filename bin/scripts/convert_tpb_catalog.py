#!/usr/bin/env python3
"""
Convert TPB catalog JSON to pipe-delimited COMBINED format
"""
import sys
import json

def main():
    try:
        data = json.load(sys.stdin)
    except:
        sys.exit(1)
    
    for movie in data:
        title = movie.get("title", "Unknown")
        year = movie.get("year", "")
        imdb_rating = movie.get("imdb_rating", "N/A")
        plot = movie.get("plot", "")
        poster = movie.get("poster", "N/A")
        torrents = movie.get("torrents", [])
        
        if not torrents:
            continue
        
        # Build COMBINED format arrays
        sources = "^".join(["TPB"] * len(torrents))
        
        # Extract quality from torrent name
        qualities = []
        for t in torrents:
            name = t.get("name", "")
            parts = name.split(".")
            qual = "1080p"
            for p in parts:
                if p.lower() in ["1080p", "720p", "480p", "2160p", "4k"]:
                    qual = p
                    break
            qualities.append(qual)
        
        seeds = "^".join([str(t.get("seeders", 0)) for t in torrents])
        sizes = "^".join([t.get("size", "N/A") for t in torrents])
        magnets = "^".join(["magnet:?xt=urn:btih:" + t.get("hash", "") for t in torrents])
        
        # Format: COMBINED|Name (Year)|Sources|Qualities|Seeds|Sizes|Magnets|Poster|IMDBRating|Plot
        display_name = f"{title} ({year})" if year else title
        
        # Clean plot - remove pipes and newlines
        clean_plot = plot.replace("|", "-").replace("\n", " ")[:200]
        
        print(f"COMBINED|{display_name}|{sources}|{'^'.join(qualities)}|{seeds}|{sizes}|{magnets}|{poster}|{imdb_rating}|{clean_plot}")

if __name__ == "__main__":
    main()

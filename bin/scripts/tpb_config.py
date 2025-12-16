#!/usr/bin/env python3
"""
TPB API Configuration - Domains, Categories, and Fallbacks
Centralized configuration for ThePirateBay API integration
"""

# Ordered by priority - first working domain is used
TPB_DOMAINS = [
    "https://apibay.org",
    "https://pirateproxy.live",
    "https://piratebay.live",
]

# TPB Category codes
CATEGORIES = {
    'hd_movies': 207,
    'hd_tv_shows': 208,
    'movies': 201,
    'tv_shows': 205,
    'video': 200,
}

# Precompiled data files
PRECOMPILED_FILES = {
    'hd_movies': 'data_top100_207.json',
    'hd_tv_shows': 'data_top100_208.json',
    'movies': 'data_top100_201.json',
    'tv_shows': 'data_top100_205.json',
    'video': 'data_top100_200.json',
    'all': 'data_top100_all.json',
    'recent': 'data_top100_recent.json',
    'last_48h': 'data_top100_48h.json',
}

# Deep search quality suffixes
QUALITY_SEARCH_TERMS = ['4K', '2160p', 'BluRay', 'x265', 'HEVC', '1080p', '720p']

# Request settings
DEFAULT_TIMEOUT = 10
MAX_RETRIES = 3
RETRY_DELAY_BASE = 1.0  # seconds (exponential: 1, 2, 4...)
CACHE_TTL = 300  # 5 minutes

# Progress bar styling (ANSI codes)
COLORS = {
    'watch_progress': '\033[1;38;5;135m',   # Bold purple (glow)
    'buffering': '\033[1;38;5;87m',          # Bold cyan (glow)
    'empty': '\033[38;5;240m',               # Dark gray
    'completed': '\033[1;38;5;46m',          # Bold green
    'tpb': '\033[38;5;220m',                 # Yellow
    'yts': '\033[38;5;46m',                  # Green
    'reset': '\033[0m',
}

# Progress bar unicode
PROGRESS_CHAR = '━'  # U+2501

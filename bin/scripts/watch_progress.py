#!/usr/bin/env python3
"""
Watch Progress Tracker
Tracks mpv/vlc playback position and displays progress bars
"""
import json
import os
import re
import hashlib
from pathlib import Path
from typing import Optional, Dict
from datetime import datetime

# Import config for colors
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tpb_config import COLORS, PROGRESS_CHAR

# Storage paths
CONFIG_DIR = Path.home() / ".config" / "termflix"
HISTORY_FILE = CONFIG_DIR / "watch_history.json"
MPV_WATCH_LATER = Path.home() / ".config" / "mpv" / "watch_later"

# Progress bar settings
BAR_WIDTH = 20


def get_history() -> Dict:
    """Load watch history from file"""
    try:
        if HISTORY_FILE.exists():
            return json.loads(HISTORY_FILE.read_text())
    except:
        pass
    return {}


def save_history(history: Dict):
    """Save watch history to file"""
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        HISTORY_FILE.write_text(json.dumps(history, indent=2))
    except:
        pass


def get_magnet_hash(magnet: str) -> str:
    """Extract info_hash from magnet link"""
    match = re.search(r'btih:([a-fA-F0-9]+)', magnet)
    if match:
        return match.group(1).lower()
    return ""


def get_watch_progress(info_hash: str) -> float:
    """
    Get watch progress for a torrent (0.0 - 1.0)
    First checks local history, then mpv watch_later
    """
    history = get_history()
    
    # Check local history first
    if info_hash.lower() in history:
        return history[info_hash.lower()].get('progress', 0.0)
    
    # Check mpv watch_later files (hash-based filenames)
    # mpv uses MD5 of file path as filename
    if MPV_WATCH_LATER.exists():
        for wl_file in MPV_WATCH_LATER.glob("*"):
            try:
                content = wl_file.read_text()
                # Look for start= line (playback position)
                start_match = re.search(r'^start=(\d+\.?\d*)', content, re.MULTILINE)
                # Would need additional logic to match torrent to file
                # For now, just use our own history
            except:
                continue
    
    return 0.0


def set_watch_progress(info_hash: str, progress: float, title: str = "", duration: float = 0):
    """Set watch progress for a torrent"""
    history = get_history()
    
    history[info_hash.lower()] = {
        'progress': min(1.0, max(0.0, progress)),
        'title': title,
        'duration': duration,
        'updated': datetime.now().isoformat()
    }
    
    save_history(history)


def format_progress_bar(progress: float, mode: str = 'watch', width: int = BAR_WIDTH) -> str:
    """
    Format a progress bar with ANSI colors
    
    Args:
        progress: 0.0 - 1.0
        mode: 'watch' (purple) or 'buffer' (cyan)
        width: bar width in characters
    """
    filled = int(progress * width)
    empty = width - filled
    
    # Select color based on mode
    if mode == 'buffer':
        color = COLORS['buffering']
    else:
        color = COLORS['watch_progress']
    
    empty_color = COLORS['empty']
    reset = COLORS['reset']
    
    # Build bar: bright color for filled, dark gray for empty
    bar = f"{color}{PROGRESS_CHAR * filled}{reset}{empty_color}{PROGRESS_CHAR * empty}{reset}"
    
    # Add percentage
    pct = int(progress * 100)
    
    # Add checkmark for completed
    if progress >= 0.95:
        return f"{bar} {COLORS['completed']}100% ✓{reset}"
    
    return f"{bar} {pct}%"


def format_buffering_bar(progress: float, width: int = 30) -> str:
    """Format a buffering progress bar with 'Buffering' label"""
    filled = int(progress * width)
    empty = width - filled
    
    color = COLORS['buffering']
    empty_color = COLORS['empty']
    reset = COLORS['reset']
    
    bar = f"{color}{PROGRESS_CHAR * filled}{reset}{empty_color}{PROGRESS_CHAR * empty}{reset}"
    pct = int(progress * 100)
    
    return f"Buffering {bar} {pct}%"


if __name__ == '__main__':
    # Demo progress bars
    print("Watch Progress Demo:")
    print("-" * 60)
    
    for pct in [0, 25, 50, 78, 100]:
        bar = format_progress_bar(pct / 100, mode='watch')
        print(f"  Watch:     {bar}")
    
    print()
    print("Buffering Demo:")
    print("-" * 60)
    
    for pct in [0, 25, 47, 75, 100]:
        bar = format_buffering_bar(pct / 100)
        print(f"  {bar}")

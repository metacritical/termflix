#!/usr/bin/env python3
"""
Kitty Terminal Image Renderer with Response Suppression

Uses Kitty's graphics protocol with q=2 flag to suppress terminal responses,
preventing text from leaking into FZF's search bar.

Falls back to viu block graphics for non-Kitty terminals.
"""

import sys
import os
import base64
import subprocess
import shutil
from pathlib import Path

def is_kitty_terminal():
    """Check if we're running in Kitty terminal"""
    return os.environ.get('TERM') == 'xterm-kitty'

def render_kitty_graphics(image_path: str, width: int = 40, height: int = 12) -> bool:
    """
    Render image using Kitty's graphics protocol with q=2 (suppress response).
    Returns True on success, False on failure.
    """
    try:
        # Read image file
        with open(image_path, 'rb') as f:
            image_data = f.read()
        
        # Base64 encode the image
        encoded = base64.standard_b64encode(image_data).decode('ascii')
        
        # Build the Kitty graphics protocol command
        # a=T: action = transmit and display
        # f=100: format = PNG/JPEG auto-detect
        # q=2: quiet mode - NO RESPONSE (this prevents the leak!)
        # c=<width>: columns
        # r=<height>: rows
        
        # For inline images in preview, we use the simpler approach:
        # Send image in chunks with q=2 to suppress all responses
        
        chunk_size = 4096
        first_chunk = True
        
        while encoded:
            chunk = encoded[:chunk_size]
            encoded = encoded[chunk_size:]
            
            # m=1 means more data coming, m=0 means last chunk
            more = 1 if encoded else 0
            
            if first_chunk:
                # First chunk: include all parameters
                # q=2 is the key - suppresses terminal response
                cmd = f'\033_Ga=T,f=100,q=2,c={width},r={height},m={more};{chunk}\033\\'
                first_chunk = False
            else:
                # Subsequent chunks: just m and data
                cmd = f'\033_Gm={more},q=2;{chunk}\033\\'
            
            # Write directly to stdout (not stderr)
            sys.stdout.write(cmd)
            sys.stdout.flush()
        
        # Add newlines to position cursor after image
        for _ in range(height):
            print()
        
        return True
        
    except Exception as e:
        # Silent failure - fall back to block graphics
        return False


def render_block_graphics(image_path: str, width: int = 20, height: int = 15) -> bool:
    """
    Render image using viu block graphics.
    Forces TERM=xterm-256color to avoid Kitty protocol in viu.
    Returns True on success, False on failure.
    """
    # Check for viu
    viu_path = shutil.which('viu')
    if not viu_path:
        return False
    
    try:
        # Force block mode by setting TERM
        env = os.environ.copy()
        env['TERM'] = 'xterm-256color'
        
        result = subprocess.run(
            [viu_path, '-w', str(width), '-h', str(height), image_path],
            env=env,
            capture_output=False,
            timeout=5
        )
        return result.returncode == 0
    except Exception:
        return False


def render_chafa(image_path: str, width: int = 20, height: int = 15) -> bool:
    """
    Render image using chafa block graphics.
    Returns True on success, False on failure.
    """
    chafa_path = shutil.which('chafa')
    if not chafa_path:
        return False
    
    try:
        env = os.environ.copy()
        env['TERM'] = 'xterm-256color'
        
        result = subprocess.run(
            [chafa_path, '--symbols=block', f'--size={width}x{height}', image_path],
            env=env,
            capture_output=False,
            timeout=5
        )
        return result.returncode == 0
    except Exception:
        return False


def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    
    image_path = sys.argv[1]
    width = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    height = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    
    # Check if file exists
    if not os.path.isfile(image_path):
        sys.exit(1)
    
    # Try rendering methods in order of quality
    if is_kitty_terminal():
        # Try Kitty graphics with response suppression
        if render_kitty_graphics(image_path, width, height):
            return
    
    # Fall back to block graphics
    if render_block_graphics(image_path, 20, 15):
        return
    
    # Final fallback to chafa
    if render_chafa(image_path, 20, 15):
        return
    
    # Silent exit if nothing works
    sys.exit(1)


if __name__ == "__main__":
    main()

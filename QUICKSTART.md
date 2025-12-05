# Termflix Quick Start Guide

Get up and running with Termflix in 5 minutes!

## Installation

### Step 1: Install Dependencies

**macOS:**
```bash
brew install jq peerflix mpv transmission-cli python3
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install jq mpv transmission-cli python3
npm install -g peerflix
```

### Step 2: Install Termflix

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/termflix.git
cd termflix

# Run installer
./install.sh
```

### Step 3: Run Termflix

```bash
termflix
```

That's it! Termflix will:
- Ask for your preferred player (mpv or vlc) on first run
- Show you the latest movies and TV shows
- Let you browse, search, and stream!

## First Time Setup

### Set Player Preference

```bash
termflix player mpv    # or 'vlc'
```

### Optional: Add TMDB API Keys (for better posters)

1. Sign up at [themoviedb.org](https://www.themoviedb.org)
2. Get API key and Read Token from Settings → API
3. Add to `~/.config/termflix/config`:

```bash
TMDB_API_KEY=your_key_here
TMDB_READ_TOKEN=your_token_here
```

### Optional: Install viu for Movie Posters

```bash
# macOS
brew install viu

# Linux
cargo install viu
```

## Common Commands

```bash
termflix                    # Browse latest content
termflix search "movie"    # Search for movies/shows
termflix latest movies      # Latest movies only
termflix trending all       # Trending content
```

## Troubleshooting

**"jq not found"**
- Install: `brew install jq` (macOS) or `sudo apt-get install jq` (Linux)

**"peerflix not found"**
- Install: `npm install -g peerflix` or `brew install peerflix`

**"No movie posters"**
- Install viu: `cargo install viu` or `brew install viu`

**Script not found after install**
- Add install directory to PATH: `export PATH="$PATH:$HOME/.local/bin"` (add to ~/.bashrc)

## Need Help?

- Check the full [README.md](README.md) for detailed documentation
- Open an issue on GitHub
- Check existing issues for solutions

Enjoy streaming! 🎬

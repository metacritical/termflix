# Termflix

A powerful terminal-based torrent streaming client that allows you to stream torrents directly to your favorite media player (MPV/VLC) without downloading the entire file first.

## Features

- 🎬 **Direct Streaming**: Stream torrents directly from magnet links or torrent files
- 🔍 **Built-in Search**: Search for torrents from multiple sources
- 🖼️ **Poster Display**: View movie/show posters in the terminal (with viu)
- 📺 **Subtitle Support**: Automatic subtitle loading and selection
- 🎨 **Theme System**: Customizable color themes
- 📊 **Watch History**: Track your viewing history with automatic resume
- 🔧 **Player Selection**: Support for MPV, VLC, and other media players
- ⚡ **Fast & Lightweight**: Written in Bash with Python modules for performance
- 📱 **Responsive UI**: Clean terminal interface with progress indicators

## Installation

### Prerequisites

- **Bash** 4.0+ (or Zsh)
- **Python** 3.7+
- **curl** (required for API calls)
- **jq** (for JSON parsing)
- **mpv** or **vlc** (recommended media player)
- **viu** (optional, for poster display)

### macOS Installation

```bash
# Install required dependencies
brew install python3 curl jq mpv viu

# Install Node.js (required for peerflix)
brew install node

# Clone the repository
git clone https://github.com/metacritical/termflix.git
cd termflix

# Make termflix executable
chmod +x bin/termflix

# Create a symlink for easy access
sudo ln -s "$(pwd)/bin/termflix" /usr/local/bin/termflix
```

### Linux Installation

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y python3 python3-pip curl jq mpv

# Install viu (optional)
cargo install viu

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# Clone and setup
git clone https://github.com/metacritical/termflix.git
cd termflix
chmod +x bin/termflix
sudo ln -s "$(pwd)/bin/termflix" /usr/local/bin/termflix
```

## Usage

### Basic Commands

```bash
# Stream from a magnet link
termflix magnet:?xt=urn:btih:...

# Stream from a torrent file
termflix ./movie.torrent

# Search for content
termflix search "Inception"

# Show watch history
termflix history

# Play from history
termflix play 1

# Show help
termflix help
```

### Interactive Mode

Simply run `termflix` to enter interactive mode with a menu-driven interface.

### Configuration

Configuration files are stored in:
- **macOS**: `~/Library/Application Support/Termflix/`
- **Linux**: `~/.config/termflix/`

### Theme Customization

```bash
# List available themes
termflix theme list

# Set a theme
termflix theme set monokai

# Create a custom theme
termflix theme create mytheme
```

## Modules

Termflix uses a modular architecture:

- **Core**: Basic functionality, configuration, and utilities
- **Commands**: Search, play, history management
- **UI**: Interactive menus and progress displays
- **API**: Integration with torrent providers
- **Theme**: Color scheme management

## Key Dependencies

- **peerflix**: Streaming torrent client
- **mpv**: Media player (recommended)
- **curl**: HTTP requests
- **jq**: JSON processing
- **Python**: Additional functionality modules

## Troubleshooting

### Common Issues

1. **"peerflix not found"**
   ```bash
   npm install -g peerflix
   ```

2. **"viu not found"** (poster display disabled)
   ```bash
   brew install viu  # macOS
   cargo install viu  # Linux
   ```

3. **Permission denied**
   ```bash
   chmod +x bin/termflix
   ```

4. **Port already in use**
   ```bash
   # Kill the process using the port
   lsof -ti:8888 | xargs kill -9
   ```

### Debug Mode

Enable debug logging:
```bash
export TERMFLIX_DEBUG=1
termflix
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Disclaimer

Please ensure you have the right to stream any content. This tool is for educational purposes only. Respect copyright laws in your jurisdiction.

## Support

If you encounter any issues, please:
1. Check the troubleshooting section
2. Search existing issues on GitHub
3. Create a new issue with detailed information

---

**Termflix** - Terminal-based torrent streaming made simple.
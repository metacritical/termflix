# Contributing to Termflix

Thank you for your interest in contributing to Termflix! 🎬

## How to Contribute

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes**
4. **Test thoroughly**: Ensure the script works on both macOS and Linux
5. **Commit your changes**: `git commit -m 'Add amazing feature'`
6. **Push to your fork**: `git push origin feature/amazing-feature`
7. **Open a Pull Request**

## Development Guidelines

### Code Style
- Use 4 spaces for indentation (not tabs)
- Follow existing code style and patterns
- Add comments for complex logic
- Keep functions focused and modular

### Testing
- Test on both macOS and Linux if possible
- Test with different terminal emulators
- Test with and without optional dependencies (viu, kitty, etc.)

### Cross-Platform Compatibility
- Always check for both macOS and Linux command variations
- Use `stat -f` (macOS) with fallback to `stat -c` (Linux)
- Use `md5` (macOS) with fallback to `md5sum` (Linux)
- Provide platform-specific installation instructions

### Dependencies
- Keep external dependencies minimal
- Always check if commands exist before using them
- Provide helpful error messages with installation instructions

## Reporting Issues

When reporting issues, please include:
- Operating system and version
- Terminal emulator (if relevant)
- Error messages or output
- Steps to reproduce
- Expected vs actual behavior

## Feature Requests

We welcome feature requests! Please open an issue describing:
- What you'd like to see
- Why it would be useful
- How it might work

Thank you for contributing! 🚀

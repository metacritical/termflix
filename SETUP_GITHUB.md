# Setting Up Termflix on GitHub

This guide will help you publish termflix as a standalone repository on GitHub.

## Step 1: Initialize Git Repository

```bash
cd /Users/pankajdoharey/termflix-standalone
git init
git add .
git commit -m "Initial commit: Standalone termflix release"
```

## Step 2: Create GitHub Repository

1. Go to [GitHub](https://github.com) and create a new repository
2. Name it `termflix` (or your preferred name)
3. **Don't** initialize with README, .gitignore, or license (we already have them)
4. Copy the repository URL

## Step 3: Connect and Push

```bash
# Add remote (replace YOUR_USERNAME with your GitHub username)
git remote add origin https://github.com/YOUR_USERNAME/termflix.git

# Push to GitHub
git branch -M main
git push -u origin main
```

## Step 4: Update README URLs

After pushing, update the README.md to replace `YOUR_USERNAME` with your actual GitHub username:

```bash
# Edit README.md and replace YOUR_USERNAME with your GitHub username
sed -i '' 's/YOUR_USERNAME/your-actual-username/g' README.md
git add README.md
git commit -m "Update GitHub URLs in README"
git push
```

## Step 5: Create Release

1. Go to your repository on GitHub
2. Click "Releases" → "Create a new release"
3. Tag version: `v1.0.0`
4. Release title: `Termflix v1.0.0 - Initial Release`
5. Description: Copy from README.md features section
6. Publish release

## Step 6: Update Install Script URL

Update `install.sh` in README.md to point to your actual repository URL.

## Optional: Add GitHub Actions

Create `.github/workflows/test.yml` for automated testing (optional):

```yaml
name: Test Termflix

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq bash
      - name: Syntax check
        run: bash -n termflix
```

## Repository Structure

```
termflix/
├── .gitignore
├── CONTRIBUTING.md
├── LICENSE
├── QUICKSTART.md
├── README.md
├── SETUP_GITHUB.md
├── install.sh
└── termflix          # Main script (self-contained)
```

## Verification Checklist

- [ ] Script is self-contained (no external dependencies on oh-my-bash)
- [ ] All functions are defined within the script
- [ ] README.md is complete and accurate
- [ ] install.sh works correctly
- [ ] Script syntax is valid (`bash -n termflix`)
- [ ] Cross-platform compatibility verified
- [ ] GitHub URLs updated in README
- [ ] License file included
- [ ] .gitignore is appropriate

## Next Steps

1. Add a nice repository description on GitHub
2. Add topics/tags: `bash`, `torrent`, `streaming`, `cli`, `terminal`, `movies`
3. Consider adding a logo/banner image
4. Enable GitHub Discussions for community support
5. Add GitHub Actions for CI/CD (optional)

Your standalone termflix is ready to share! 🚀

# Language System

This document explains the Language feature in Termflix, covering data fetching, mapping, and display.

## 1. Data Fetching

Language data is sourced from **TMDB** using the `original_language` field.

### TMDB Integration

In `modules/api/tmdb.sh`, the API wrapper extracts the `original_language` field from the JSON response for both movies and TV shows. This field contains **ISO 639-1** 2-letter codes (e.g., "en", "es", "ko", "ja").

```python
'original_language': r.get('original_language', '')
```

## 2. ISO 639-1 Mapping

To display friendly flags and names, Termflix maps the ISO codes using an internal data file.

### Data Source: `data/languages.json`

This file contains the mapping definitions. It is an internal data file and is **NOT** affected by cache clearing operations (`--clear`).

Format:
```json
{
  "en": { "flag": "🇬🇧", "name": "English" },
  "ko": { "flag": "🇰🇷", "name": "Korean" },
  "ja": { "flag": "🇯🇵", "name": "Japanese" }
}
```

### Helper Module: `modules/core/languages.sh`

This bash module provides functions to query the JSON data:

-   `get_language_flag "ko"` → Returns "🇰🇷"
-   `get_language_name "ko"` → Returns "Korean"
-   `format_language_display "ko"` → Returns "🇰🇷 Korean"

It uses Python for robust JSON parsing.

## 3. Display & Usage

### Preview Window

In `modules/ui/catalog/preview_fzf.sh`:
1.  The script extracts `original_language` from the TMDB metadata.
2.  It calls `get_language_flag` to resolve the emoji.
3.  The flag is displayed next to the title in the preview header (e.g., "🇰🇷 **Parasite**").

### Sorting

In `bin/termflix` header menu (`Ctrl+V`):
-   A "By Language" option allows filtering movies by language code.
-   Selection sets the `CURRENT_LANGUAGE` environment variable, which filters the catalog results.

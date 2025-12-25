# Genre System

This document outlines how the Genre system works in Termflix, from data fetching to display.

## 1. Data Fetching

Movies and TV shows fetch genre data primarily from **TMDB** (The Movie Database), with a fallback to **OMDB**.

### TMDB (Primary)

In `modules/api/tmdb.sh`, the search functions (`search_tmdb_movie`, `find_by_imdb_id`) extract genre information from the API response.

TMDB provides genre data in two formats depending on the endpoint:
1.  **`genres`**: An array of objects found in detailed movie/show endpoints (e.g., `[{"id": 28, "name": "Action"}]`).
2.  **`genre_ids`**: An array of IDs found in search results (e.g., `[28, 12, 53]`).

The API wrapper ensures `genre_ids` are included in the simplified JSON response:

```python
'genre_ids': r.get('genre_ids', [])
```

### OMDB (Fallback)

If TMDB fails or returns no data, `modules/api/omdb.sh` fetches genre strings directly (e.g., "Action, Adventure").

## 2. Genre Mapping (ID → Name)

Since search results often only provide IDs, a mapping logic is implemented in the UI layer (`modules/ui/catalog/preview_fzf.sh`) to convert these IDs into human-readable names.

A hardcoded Python dictionary maps TMDB IDs to names:

```python
GENRE_MAP = {
    28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy', 80: 'Crime',
    99: 'Documentary', 18: 'Drama', 10751: 'Family', 14: 'Fantasy', 36: 'History',
    27: 'Horror', 10402: 'Music', 9648: 'Mystery', 10749: 'Romance', 878: 'Sci-Fi',
    10770: 'TV Movie', 53: 'Thriller', 10752: 'War', 37: 'Western'
}
```

The logic checks for:
1.  **`genres` array**: If present, extracts names directly.
2.  **`genre_ids` array**: If present, maps IDs to names using `GENRE_MAP`.

## 3. Display & Usage

-   **Preview Pane**: The resolved genre string (e.g., "Action, Thriller") is displayed in the movie preview (`preview_fzf.sh`).
-   **Colorization**: Genres are colorized using a hash-based color picker (or `data/genres.json` definitions) to provide visual distinctiveness in the UI.
-   **Filtering**: The `CURRENT_GENRE` variable allows the catalog to filter content by these resolved genre names.

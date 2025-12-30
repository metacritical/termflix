#!/usr/bin/env bash
#
# Guardrail: prevent re-introducing production "direct fzf" calls.
#
# We allow:
# - tests/* and modules/ui/tests/* (test harnesses)
# - modules/ui/scratch/* (backups/experiments)
# - modules/ui/debug/* (debug harnesses)
# - modules/ui/lib/ui_parser.sh (legacy parser kept for docs/tests)
#
# Everything else should use `tml_run_fzf`.

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  echo "SKIP: ripgrep (rg) not available"
  exit 0
fi

allowed_excludes=(
  '^tests/'
  '^docs/'
  '^modules/ui/tests/'
  '^modules/ui/scratch/'
  '^modules/ui/debug/'
  '^modules/ui/lib/ui_parser\.sh$'
)

exclude_re="$(printf '%s|' "${allowed_excludes[@]}")"
exclude_re="${exclude_re%|}"

files="$(
  rg --files bin modules \
    | rg -v --pcre2 "$exclude_re" \
    | rg -e '^bin/termflix$' -e '\\.sh$'
)"

if [[ -z "$files" ]]; then
  echo "No files found to scan."
  exit 0
fi

patterns=(
  '^[[:space:]]*(?!#).*\\bfzf[[:space:]]+--'
  '^[[:space:]]*(?!#).*[|][[:space:]]*fzf\\b'
)

found=0
while IFS= read -r file; do
  for pat in "${patterns[@]}"; do
    if rg -n --pcre2 "$pat" "$file" >/dev/null 2>&1; then
      if [[ "$found" -eq 0 ]]; then
        echo "ERROR: Direct fzf calls found in production files:"
      fi
      echo
      echo "File: $file"
      rg -n --pcre2 "$pat" "$file" || true
      found=1
    fi
  done
done <<<"$files"

if [[ "$found" -ne 0 ]]; then
  echo
  echo 'Fix: replace direct `fzf` invocations with `tml_run_fzf`.'
  exit 1
fi

echo "OK: No production direct fzf calls detected."

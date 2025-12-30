#!/usr/bin/env bash
#
# Termflix Seasonal UI Rules
# Controls date-based branding + festive icon overrides.
#
# - The Termflix brand icon (🍿) is NOT theme-driven.
# - Seasonal prefix is added in specific windows:
#   - Dec 1 → Jan 31: Santa (🎅) prefix
#   - Jan 1: New Year (🎉) prefix (overrides Santa)
#   - Buddha Purnima: Lotus (🪷) prefix (date varies)
# - The bottom help/status label can include seasonal center icons via `TERMFLIX_STATUS_MID_ICON`.
#

[[ -n "${_TERMFLIX_SEASONAL_LOADED:-}" ]] && return 0
_TERMFLIX_SEASONAL_LOADED=1

termflix_today_ymd() {
  date +%Y-%m-%d 2>/dev/null || echo ""
}

termflix_today_month_day() {
  date +%m-%d 2>/dev/null || echo ""
}

termflix_is_new_year_day() {
  [[ "$(termflix_today_month_day)" == "01-01" ]]
}

termflix_is_christmas_season() {
  local md
  md="$(termflix_today_month_day)"
  [[ "$md" == 12-* || "$md" == 01-* ]]
}

# Best-effort Buddha Purnima date table (India). Override supported:
#   TERMFLIX_BUDDHA_PURNIMA_DATE=YYYY-MM-DD
#   TERMFLIX_SPECIAL_DAY=buddha_purnima
termflix_is_buddha_purnima() {
  [[ "${TERMFLIX_SPECIAL_DAY:-}" == "buddha_purnima" ]] && return 0

  local today
  today="$(termflix_today_ymd)"
  [[ -z "$today" ]] && return 1

  local override="${TERMFLIX_BUDDHA_PURNIMA_DATE:-}"
  [[ -n "$override" ]] && [[ "$today" == "$override" ]] && return 0

  local year="${today%%-*}"
  local target=""
  case "$year" in
    2024) target="2024-05-23" ;;
    2025) target="2025-05-12" ;;
    2026) target="2026-05-01" ;;
    2027) target="2027-05-20" ;;
    2028) target="2028-05-08" ;;
    2029) target="2029-04-27" ;;
    2030) target="2030-05-16" ;;
  esac

  [[ -n "$target" && "$today" == "$target" ]]
}

termflix_logo_prefix() {
  if termflix_is_new_year_day; then
    printf "%s" "🎉"
    return 0
  fi

  if termflix_is_buddha_purnima; then
    # Buddha Purnima: Dharma wheel + amulet
    printf "%s" "☸️🪬"
    return 0
  fi

  if termflix_is_christmas_season; then
    printf "%s" "🎅"
    return 0
  fi

  printf "%s" ""
}

termflix_export_logo_icon() {
  local prefix
  prefix="$(termflix_logo_prefix)"
  export TERMFLIX_LOGO_ICON="${prefix}🍿"
}

# Seasonal overrides for non-brand icons (allowed).
termflix_apply_seasonal_icon_overrides() {
  termflix_export_logo_icon
  export TERMFLIX_STATUS_MID_ICON=""

  if termflix_is_buddha_purnima; then
    export TERMFLIX_SEASONAL_MODE="buddha_purnima"
    export TERMFLIX_STATUS_MID_ICON="🪷"
    return 0
  fi

  # Only override icons for the extended festive season (Dec/Jan),
  # with a different feel on Jan 1.
  if termflix_is_new_year_day; then
    export TERMFLIX_SEASONAL_MODE="newyear"
    export TERMFLIX_STATUS_MID_ICON="🎉"
    export THEME_STR_ICON_MOVIE="${THEME_STR_ICON_MOVIE-🎬}🎉"
    export THEME_STR_ICON_DROPDOWN="✨"
    export THEME_STR_ICON_ACTIVE_DOT="🎊"
    export THEME_STR_ICON_BUFFERING="🥂"
    export THEME_STR_ICON_READY="🎊"
    export THEME_STR_ICON_PLAY="🎶"
    return 0
  fi

  if termflix_is_christmas_season; then
    export TERMFLIX_SEASONAL_MODE="christmas"
    export TERMFLIX_STATUS_MID_ICON="🎄🎉"
    export THEME_STR_ICON_MOVIE="🎄"
    export THEME_STR_ICON_DROPDOWN="❄"
    export THEME_STR_ICON_ACTIVE_DOT="⭐"
    export THEME_STR_ICON_BUFFERING="🎁"
    export THEME_STR_ICON_READY="⭐"
    export THEME_STR_ICON_PLAY="🔔"
    return 0
  fi

  export TERMFLIX_SEASONAL_MODE=""
  return 0
}

export -f termflix_today_ymd termflix_today_month_day
export -f termflix_is_new_year_day termflix_is_christmas_season termflix_is_buddha_purnima
export -f termflix_logo_prefix termflix_export_logo_icon termflix_apply_seasonal_icon_overrides

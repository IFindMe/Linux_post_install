# lib/yt-lib.sh — shared helpers for yt-dlp-based media tools.
# Sourced opt-in by yt-* subcommand files. Uses err() from lib/common.sh.

# yt_check_deps [dry_run] [ffmpeg_purpose]
# Check yt-dlp (+ ffmpeg unless dry_run=1 and caller wants dry-run to skip deps).
# ffmpeg_purpose is the parenthetical in the error message (default: "MP3 conversion").
# ytsync overrides this deliberately (needs yt-dlp+jq even in dry-run).
yt_check_deps() {
    local dry="${1:-0}" purpose="${2:-MP3 conversion}"
    command -v yt-dlp &>/dev/null || err "yt-dlp not found — install it with: sudo apt install yt-dlp"
    if [ "$dry" -eq 0 ]; then
        command -v ffmpeg &>/dev/null || err "ffmpeg not found (needed for $purpose) — install it with: sudo apt install ffmpeg"
    fi
}

# yt_validate_url <url>
# Returns 1 (does NOT exit) when URL doesn't start with http:// or https://;
# prints the diagnostic to stderr. Callers surface the error themselves (e.g.
# `yt_validate_url "$url" 2>/dev/null || err "…"` with their own prefix) so a
# helper whose only job is to check can never kill the caller's error path.
yt_validate_url() {
    local url="$1"
    case "$url" in
        http://*|https://*) return 0 ;;
        *) echo "not a valid URL: $url (must start with http:// or https://)" >&2; return 1 ;;
    esac
}

# yt_echo_cmd <args...>
# Prints the yt-dlp command for --dry-run mode
yt_echo_cmd() {
    echo "yt-dlp $*"
}

# classify_url <url>
# Domain classification: music.youtube/soundcloud/bandcamp → audio;
# youtube/youtu.be/vimeo/twitch → video; unknown → ${GRAB_DEFAULT:-video}
# Migrated from bin/pos-media-grab
classify_url() {
    local url="$1" mode="${GRAB_DEFAULT:-video}"
    case "$url" in
        *music.youtube.com*)  echo "audio" ;;
        *soundcloud.com*)     echo "audio" ;;
        *bandcamp.com*)       echo "audio" ;;
        *youtube.com*|*youtu.be*) echo "video" ;;
        *vimeo.com*)          echo "video" ;;
        *twitch.tv*)          echo "video" ;;
        *)                    echo "$mode" ;;
    esac
}

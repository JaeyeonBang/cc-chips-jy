#!/bin/bash

# CC CHIPS-JY — Merged rendering engine for Claude Code status lines
# Combines base engine (path/git/model/context/usage) with custom overlay
# (cost, cache efficiency, API response time, session ID, dynamic color alerts).
#
# Set CC_CHIPS_THEME to pick a theme: claude (default), cool, retro, cyber, minimal
# The minimal theme requires no Nerd Font — it uses ASCII characters only.

# ═══════════════════════════════════════════════════════════════════
# [A] INIT & THEME LOAD
# ═══════════════════════════════════════════════════════════════════
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THEME="${CC_CHIPS_THEME:-claude}"
# Guard against path traversal via CC_CHIPS_THEME (allow only alphanumeric + hyphen/underscore)
THEME="${THEME//[^a-zA-Z0-9_-]/}"
THEME="${THEME:-claude}"
THEME_FILE="${SCRIPT_DIR}/themes/${THEME}.sh"

if [ ! -f "$THEME_FILE" ]; then
    echo "CC CHIPS-JY: theme '${THEME}' not found at ${THEME_FILE}" >&2
    exit 1
fi

# Set STATS chip fallback defaults before sourcing theme
# (so themes that don't define them still render Chip 4)
FG_STATS="\033[38;2;46;125;50m"
BG_STATS="\033[48;2;46;125;50m"
FG_STATS_TEXT="\033[38;2;255;255;255m"

source "$THEME_FILE"

input=$(cat)

# ═══════════════════════════════════════════════════════════════════
# [B] GLYPH / ASCII MODE
# ═══════════════════════════════════════════════════════════════════
# CHIPS_ASCII=1 is set by themes/minimal.sh to activate ASCII mode.
if [ "${CHIPS_ASCII:-0}" = "1" ]; then
    CAP_LEFT="["
    CAP_RIGHT="]"
    CHIP_SEP=" | "
    ICON_FOLDER="#"
    ICON_GITHUB="@"
    ICON_BRANCH=">"
    ICON_BRAIN="~"
    ICON_MONITOR=":"
    ICON_DOLLAR="$"
    ICON_KEY="&"
    ICON_CHART="="
    ICON_BOLT="!"
    ICON_WARN="!!"
    CTX_FILL="#"
    CTX_EMPTY="-"
else
    CAP_LEFT=$(printf '\xee\x82\xb6')           # U+E0B6 left half circle
    CAP_RIGHT=$(printf '\xee\x82\xb4')          # U+E0B4 right half circle
    CHIP_SEP=" "
    ICON_FOLDER=$(printf '\xef\x81\xbc')        # U+F07C  folder-open
    ICON_GITHUB=$(printf '\xef\x82\x9b')        # U+F09B  github
    ICON_BRANCH=$(printf '\xee\x9c\xa5')        # U+E725  dev-git_branch
    ICON_BRAIN=$(printf '\xf3\xb0\xaf\x89')     # U+F0BC9 nf-md-space_invaders
    ICON_MONITOR=$(printf '\xef\x8b\x90')       # U+F2D0  fa-window_maximize
    ICON_DOLLAR=$(printf '\xee\xb7\xa8')        # U+EDE8  fa-coins
    ICON_KEY=$(printf '\xf3\xb0\x8c\xb7')      # U+F0337 nf-md-key
    ICON_CHART=$(printf '\xef\x82\x80')         # U+F080  fa-bar-chart
    ICON_BOLT=$(printf '\xef\x83\xa7')          # U+F0E7  fa-bolt
    ICON_WARN="!!"
    CTX_FILL="■"
    CTX_EMPTY="□"
fi

# ═══════════════════════════════════════════════════════════════════
# [C] ANSI HELPERS & ALERT COLOR CONSTANTS
# ═══════════════════════════════════════════════════════════════════
BOLD="\033[1m"
RESET="\033[0m"
DIM="\033[2m"
COLOR_WHITE="\033[38;2;220;220;220m"

ALERT_FG_RED="\033[38;2;180;30;30m"
ALERT_BG_RED="\033[48;2;180;30;30m"
ALERT_FG_ORANGE="\033[38;2;200;100;0m"
ALERT_BG_ORANGE="\033[48;2;200;100;0m"
ALERT_FG_GREEN="\033[38;2;46;125;50m"
ALERT_BG_GREEN="\033[48;2;46;125;50m"
ALERT_FG_YELLOW="\033[38;2;180;140;0m"
ALERT_BG_YELLOW="\033[48;2;180;140;0m"

# ═══════════════════════════════════════════════════════════════════
# [D] OAUTH TOKEN RESOLUTION
# ═══════════════════════════════════════════════════════════════════
_parse_oauth_token() {
    local blob="$1"
    [ -z "$blob" ] && return 1
    local token
    token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        echo "$token"
        return 0
    fi
    return 1
}

get_oauth_token() {
    # 1. Explicit env var override
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi
    # 2. macOS Keychain
    if command -v security >/dev/null 2>&1; then
        _parse_oauth_token "$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)" && return 0
    fi
    # 3. Linux credentials file
    if [ -f "${HOME}/.claude/.credentials.json" ]; then
        _parse_oauth_token "$(cat "${HOME}/.claude/.credentials.json" 2>/dev/null)" && return 0
    fi
    # 4. GNOME Keyring via secret-tool
    if command -v secret-tool >/dev/null 2>&1; then
        _parse_oauth_token "$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)" && return 0
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════════════════
# [E] USAGE API (5h / weekly) — fetch + cache
# ═══════════════════════════════════════════════════════════════════
USAGE_CACHE="/tmp/claude/statusline-usage-cache.json"
USAGE_CACHE_LOCK="/tmp/claude/statusline-usage-refresh.lock"
USAGE_CACHE_MAX_AGE=60
USAGE_CACHE_HARD_STALE=300  # After 5 min (e.g. sleep/wake), force synchronous refresh

_file_mtime() {
    # Cross-platform file mtime: macOS (BSD stat) and Linux/Git Bash (GNU stat)
    # Validates output is a plain integer before returning (guards against
    # stat implementations that print full stat info to stdout).
    local result
    result=$(stat -f %m "$1" 2>/dev/null)
    [[ "$result" =~ ^[0-9]+$ ]] && echo "$result" && return
    result=$(stat -c %Y "$1" 2>/dev/null)
    [[ "$result" =~ ^[0-9]+$ ]] && echo "$result" && return
    echo 0
}

_refresh_usage_cache() {
    if [ -f "$USAGE_CACHE_LOCK" ]; then
        local lock_mtime now lock_age
        lock_mtime=$(_file_mtime "$USAGE_CACHE_LOCK")
        now=$(date +%s)
        lock_age=$(( now - lock_mtime ))
        [ "$lock_age" -lt 15 ] && return
    fi
    echo $$ > "$USAGE_CACHE_LOCK"
    trap 'rm -f "$USAGE_CACHE_LOCK"' EXIT

    local token
    token=$(get_oauth_token)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        local response
        response=$(curl -s --max-time 5 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
            echo "$response" > "$USAGE_CACHE"
        else
            touch "$USAGE_CACHE" 2>/dev/null
        fi
    else
        touch "$USAGE_CACHE" 2>/dev/null
    fi
    rm -f "$USAGE_CACHE_LOCK"
}

_cache_past_reset() {
    [ ! -f "$USAGE_CACHE" ] && return 1
    local now resets
    now=$(date +%s)
    resets=$(jq -r '[.five_hour.resets_at // "", .seven_day.resets_at // "", .seven_day_sonnet.resets_at // ""] | .[]' "$USAGE_CACHE" 2>/dev/null)
    [ -z "$resets" ] && return 1
    local ts epoch
    while IFS= read -r ts; do
        [ -z "$ts" ] || [ "$ts" = "null" ] && continue
        epoch=$(iso_to_epoch "$ts") || continue
        [ "$now" -ge "$epoch" ] && return 0
    done <<< "$resets"
    return 1
}

fetch_usage_data() {
    mkdir -p /tmp/claude

    if [ -f "$USAGE_CACHE" ]; then
        local cache_mtime now cache_age
        cache_mtime=$(_file_mtime "$USAGE_CACHE")
        now=$(date +%s)
        cache_age=$(( now - cache_mtime ))
        if [ "$cache_age" -ge "$USAGE_CACHE_HARD_STALE" ] || _cache_past_reset; then
            _refresh_usage_cache
        elif [ "$cache_age" -ge "$USAGE_CACHE_MAX_AGE" ]; then
            _refresh_usage_cache &
            disown 2>/dev/null
        fi
        cat "$USAGE_CACHE" 2>/dev/null
        return
    fi

    local token
    token=$(get_oauth_token)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        local response
        response=$(curl -s --max-time 3 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
            echo "$response" > "$USAGE_CACHE"
            echo "$response"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════
# [F] DATE HELPERS
# ═══════════════════════════════════════════════════════════════════
iso_to_epoch() {
    local iso_str="$1"
    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then echo "$epoch"; return 0; fi
    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi
    if [ -n "$epoch" ]; then echo "$epoch"; return 0; fi
    return 1
}

format_reset_time() {
    local iso_str="$1"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return
    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return
    LC_TIME=en_US.UTF-8 date -j -r "$epoch" +"%-H:%M, %A, %Y-%m-%d" 2>/dev/null || \
    LC_TIME=en_US.UTF-8 date -d "@$epoch" +"%-H:%M, %A, %Y-%m-%d" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════
# [G] USAGE BAR BUILDER
# ═══════════════════════════════════════════════════════════════════
build_usage_bar() {
    local pct=$1 width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local filled=$(( pct * width / 100 ))
    local COLOR_GREEN="\033[38;2;0;160;0m"
    local COLOR_ORANGE="\033[38;2;255;176;85m"
    local COLOR_RED="\033[38;2;255;85;85m"
    local COLOR_EMPTY="\033[38;2;80;80;80m"
    local COLOR_FILL
    if   [ "$pct" -lt 50 ]; then COLOR_FILL="$COLOR_GREEN"
    elif [ "$pct" -lt 80 ]; then COLOR_FILL="$COLOR_ORANGE"
    else                          COLOR_FILL="$COLOR_RED"
    fi
    local FILL_CHAR EMPTY_CHAR
    if [ "${CHIPS_ASCII:-0}" = "1" ]; then
        FILL_CHAR="#"; EMPTY_CHAR="-"
    else
        FILL_CHAR="●"; EMPTY_CHAR="○"
    fi
    local bar="" i
    for ((i=1; i<=width; i++)); do
        if [ $i -le $filled ]; then bar+="${COLOR_FILL}${FILL_CHAR}"
        else                        bar+="${COLOR_EMPTY}${EMPTY_CHAR}"
        fi
    done
    printf "%b${RESET}" "$bar"
}

# ═══════════════════════════════════════════════════════════════════
# [H] DATA EXTRACTION — single-pass jq
# ═══════════════════════════════════════════════════════════════════
# All input fields extracted in one jq subprocess call (tab-delimited).
IFS=$'\t' read -r project_dir session_id model_raw \
    input_tokens output_tokens cache_read cache_write context_size api_ms \
    <<< "$(echo "$input" | jq -r '[
        (.workspace.project_dir // .workspace.current_dir // "."),
        (.session_id // "unknown"),
        (if (.model | type) == "object"
         then (.model.display_name // .model.id // "unknown")
         else (.model // "unknown") end),
        (.context_window.current_usage.input_tokens // 0 | tostring),
        (.context_window.current_usage.output_tokens // 0 | tostring),
        (.context_window.current_usage.cache_read_input_tokens // 0 | tostring),
        (.context_window.current_usage.cache_creation_input_tokens // 0 | tostring),
        (.context_window.context_window_size // 0 | tostring),
        (.cost.total_api_duration_ms // 0 | tostring)
    ] | join("\t")' 2>/dev/null)"

# ═══════════════════════════════════════════════════════════════════
# [I] GIT DETECTION
# ═══════════════════════════════════════════════════════════════════
git_branch=""
git_dirty=""
if [ -d "$project_dir/.git" ] || git -C "$project_dir" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$project_dir" branch --show-current 2>/dev/null)
    if [ -n "$git_branch" ]; then
        if ! git -C "$project_dir" diff --quiet 2>/dev/null || \
           ! git -C "$project_dir" diff --cached --quiet 2>/dev/null; then
            git_dirty=" ≠"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════
# [J] DERIVED CALCULATIONS
# ═══════════════════════════════════════════════════════════════════

# Short path (tilde-compress home dir)
short_path=$(echo "$project_dir" | sed "s|$HOME|~|")

# Session short ID (first 8 chars)
session_short="${session_id:0:8}"

# Model display name normalization
case "$model_raw" in
    *opus*4.6*|*opus-4-6*)     model_display="Opus 4.6" ;;
    *opus*4.5*|*opus-4-5*)     model_display="Opus 4.5" ;;
    *opus*4*|*opus-4*)         model_display="Opus 4"   ;;
    *sonnet*4.6*|*sonnet-4-6*) model_display="Sonnet 4.6" ;;
    *sonnet*4.5*|*sonnet-4-5*) model_display="Sonnet 4.5" ;;
    *sonnet*4*|*sonnet-4*)     model_display="Sonnet 4"   ;;
    *sonnet*3.5*|*sonnet-3-5*) model_display="Sonnet 3.5" ;;
    *haiku*4.5*|*haiku-4-5*)   model_display="Haiku 4.5" ;;
    *haiku*3.5*|*haiku-3-5*)   model_display="Haiku 3.5" ;;
    *)                          model_display="$model_raw" ;;
esac

# Context percentage
current_ctx=$(( input_tokens + cache_write + cache_read ))
context_pct=0
if [ "$context_size" -gt 0 ] 2>/dev/null; then
    context_pct=$(( current_ctx * 100 / context_size ))
fi

# Context bar (5 chars)
ctx_filled=$(( context_pct * 5 / 100 ))
ctx_bar=""
for ((i=0; i<5; i++)); do
    if [ $i -lt $ctx_filled ]; then ctx_bar+="$CTX_FILL"
    else                            ctx_bar+="$CTX_EMPTY"
    fi
done

# Cache hit percentage
total_ctx=$(( input_tokens + cache_read + cache_write ))
cache_pct=0
[ "$total_ctx" -gt 0 ] && cache_pct=$(( cache_read * 100 / total_ctx ))

# API response time
api_sec="0.0"
if [ "$api_ms" -gt 0 ] 2>/dev/null; then
    api_sec=$(awk "BEGIN {printf \"%.1f\", $api_ms / 1000}")
fi

# Cost (model-based pricing per 1M tokens, in cents)
#   Opus 4.6:   $5 in, $25 out, $0.50 cache read (0.1x), $6.25 cache write (1.25x)
#   Sonnet 4.6: $3 in, $15 out, $0.30 cache read (0.1x), $3.75 cache write (1.25x)
#   Haiku 4.5:  $1 in,  $5 out, $0.10 cache read (0.1x), $1.25 cache write (1.25x)
case "$model_display" in
    Sonnet*)
        price_input=300;  price_output=1500; price_cache_read=30;  price_cache_write=375  ;;
    Haiku*)
        price_input=100;  price_output=500;  price_cache_read=10;  price_cache_write=125  ;;
    *)
        price_input=500;  price_output=2500; price_cache_read=50;  price_cache_write=625  ;;
esac
total_cents=$(( (input_tokens * price_input + output_tokens * price_output +
                 cache_read * price_cache_read + cache_write * price_cache_write) / 1000000 ))

if   [ $total_cents -eq 0 ];   then cost_display="\$0"
elif [ $total_cents -lt 100 ]; then cost_display="\$0.$(printf '%02d' $total_cents)"
else
    cost_display="\$$(( total_cents / 100 )).$(printf '%02d' $(( total_cents % 100 )))"
fi

# ═══════════════════════════════════════════════════════════════════
# [K] DYNAMIC COLOR ALERTS
# ═══════════════════════════════════════════════════════════════════
# Mutates theme color variables in-place based on metric thresholds.

# Context chip (Chip 3 = RIGHT):
#   >= 80% → red  |  >= 50% → orange  |  < 50% → theme default
if   [ "$context_pct" -ge 80 ]; then
    FG_RIGHT="$ALERT_FG_RED";    BG_RIGHT="$ALERT_BG_RED"
elif [ "$context_pct" -ge 50 ]; then
    FG_RIGHT="$ALERT_FG_ORANGE"; BG_RIGHT="$ALERT_BG_ORANGE"
fi

# Cache chip (Chip 4 = STATS):
#   >= 80% → green  |  < 20% → yellow  |  else → theme default
if   [ "$cache_pct" -ge 80 ]; then
    FG_STATS="$ALERT_FG_GREEN";  BG_STATS="$ALERT_BG_GREEN"
elif [ "$cache_pct" -lt 20 ];  then
    FG_STATS="$ALERT_FG_YELLOW"; BG_STATS="$ALERT_BG_YELLOW"
fi

# API warn prefix: >= 10s or literal "timeout" → prepend warning icon
api_warn_prefix=""
[ "$api_ms" -ge 10000 ] 2>/dev/null && api_warn_prefix="${ICON_WARN} "

# ═══════════════════════════════════════════════════════════════════
# [L] CHIP RENDERING & OUTPUT (responsive to terminal width)
# ═══════════════════════════════════════════════════════════════════
term_width=${COLUMNS:-$(tput cols 2>/dev/null || echo 120)}

# Adaptive path: use leaf-only name when terminal is very narrow
if [ "$term_width" -lt 60 ] 2>/dev/null; then
    display_path=$(basename "$short_path")
else
    display_path="$short_path"
fi

# Adaptive context bar width
if [ "$term_width" -lt 80 ] 2>/dev/null; then
    ctx_filled_r=$(( context_pct * 3 / 100 ))
    ctx_bar_r=""
    for ((i=0; i<3; i++)); do
        if [ $i -lt $ctx_filled_r ]; then ctx_bar_r+="$CTX_FILL"
        else                              ctx_bar_r+="$CTX_EMPTY"
        fi
    done
else
    ctx_bar_r="$ctx_bar"
fi

# CHIP 1: folder + path
printf "${FG_LEFT}${CAP_LEFT}${RESET}"
printf "${BG_LEFT}${BOLD}${FG_LEFT_TEXT} ${ICON_FOLDER} %s ${RESET}" "$display_path"
printf "${FG_LEFT}${CAP_RIGHT}${RESET}"

# CHIP 2: git info (skip in minimal width)
if [ -n "$git_branch" ] && [ "$term_width" -ge 60 ] 2>/dev/null; then
    printf "%s" "$CHIP_SEP"
    printf "${FG_MID}${CAP_LEFT}${RESET}"
    printf "${BG_MID}${BOLD}${FG_MID_TEXT} ${ICON_GITHUB} ${ICON_BRANCH} %s${FG_MID_TEXT}%s${FG_MID_TEXT} ${RESET}" \
        "$git_branch" "$git_dirty"
    printf "${FG_MID}${CAP_RIGHT}${RESET}"
fi

printf "%s" "$CHIP_SEP"

# CHIP 3: model + context + cost (+ session ID when wide enough)
if [ "$term_width" -lt 60 ] 2>/dev/null; then
    chip3_content="${ICON_BRAIN} ${model_display} ${ctx_bar_r} ${context_pct}% ${ICON_DOLLAR} ${cost_display}"
elif [ "$term_width" -lt 80 ] 2>/dev/null; then
    chip3_content="${ICON_BRAIN} ${model_display} ${ICON_MONITOR} ${ctx_bar_r} ${context_pct}% ${ICON_DOLLAR} ${cost_display}"
else
    chip3_content="${ICON_BRAIN} ${model_display} ${ICON_MONITOR} ${ctx_bar_r} ${context_pct}% ${ICON_DOLLAR} ${cost_display} ${ICON_KEY} ${session_short}"
fi
printf "${FG_RIGHT}${CAP_LEFT}${RESET}"
printf "${BG_RIGHT}${BOLD}${FG_RIGHT_TEXT} %s ${RESET}" "$chip3_content"
printf "${FG_RIGHT}${CAP_RIGHT}${RESET}"

# CHIP 4: cache efficiency + API time (hidden when narrow)
if [ "$term_width" -ge 100 ] 2>/dev/null; then
    printf "%s" "$CHIP_SEP"
    chip4_content="${ICON_CHART} ${cache_pct}% ${ICON_BOLT} ${api_warn_prefix}${api_sec}s"
    printf "${FG_STATS}${CAP_LEFT}${RESET}"
    printf "${BG_STATS}${BOLD}${FG_STATS_TEXT} %s ${RESET}" "$chip4_content"
    printf "${FG_STATS}${CAP_RIGHT}${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════
# ROW 2: USAGE BARS (5h / weekly / sonnet / extra) — responsive
# ═══════════════════════════════════════════════════════════════════
render_usage_row() {
    local label="$1" pct="$2" reset_time="$3"
    local width=10
    [ "$term_width" -lt 80 ] 2>/dev/null && width=6
    local usage_bar
    usage_bar=$(build_usage_bar "$pct" "$width")
    printf "\n${COLOR_WHITE}${BOLD}%-8s${RESET} " "$label"
    printf "%b" "$usage_bar"
    if [ "$term_width" -ge 80 ] 2>/dev/null; then
        printf "${COLOR_WHITE}%3s%% used ${DIM}|${RESET} ${COLOR_WHITE}Resets: %s${RESET}" "$pct" "$reset_time"
    else
        printf "${COLOR_WHITE}%3s%%${RESET}" "$pct"
    fi
}

api_usage=""
[ "$term_width" -ge 60 ] 2>/dev/null && api_usage=$(fetch_usage_data)

if [ -n "$api_usage" ]; then
    usage_fields=$(echo "$api_usage" | jq -r '
        [.five_hour.utilization // 0, .five_hour.resets_at // "",
         .seven_day.utilization // 0, .seven_day.resets_at // "",
         .seven_day_sonnet.utilization // -1, .seven_day_sonnet.resets_at // "",
         .extra_usage.is_enabled // false, .extra_usage.utilization // -1,
         .extra_usage.used_credits // "", .extra_usage.monthly_limit // ""]
        | map(tostring) | join("\t")
    ' 2>/dev/null)

    if [ -n "$usage_fields" ]; then
        IFS=$'\t' read -r fh_util fh_reset sd_util sd_reset \
            ss_util ss_reset ex_enabled ex_util ex_used ex_limit <<< "$usage_fields"
        five_hour_pct=$(awk "BEGIN {printf \"%.0f\", $fh_util}")
        seven_day_pct=$(awk "BEGIN {printf \"%.0f\", $sd_util}")

        render_usage_row "Current:" "$five_hour_pct" "$(format_reset_time "$fh_reset")"
        render_usage_row "Weekly:"  "$seven_day_pct" "$(format_reset_time "$sd_reset")"

        # Sonnet-only weekly usage (only when field exists)
        if [ "$ss_util" != "-1" ] && [ -n "$ss_util" ]; then
            sonnet_pct=$(awk "BEGIN {printf \"%.0f\", $ss_util}")
            render_usage_row "Sonnet:" "$sonnet_pct" "$(format_reset_time "$ss_reset")"
        fi

        # Extra usage (add-on) indicator
        if [ "$ex_enabled" = "true" ]; then
            if [ "$ex_util" != "-1" ] && [ -n "$ex_util" ]; then
                extra_pct=$(awk "BEGIN {printf \"%.0f\", $ex_util}")
                render_usage_row "Extra:" "$extra_pct" "${ex_used:-0}/${ex_limit:-?} credits"
            else
                printf "\n${COLOR_WHITE}${BOLD}%-8s${RESET} " "Extra:"
                printf "${COLOR_WHITE}Enabled ${DIM}|${RESET} ${COLOR_WHITE}${ex_used:-0}/${ex_limit:-?} credits used${RESET}"
            fi
        fi
    fi
fi

printf "\n"

#!/bin/bash

# CC CHIPS-JY — Automated install script
# Supports: macOS, Linux, Windows Git Bash (MINGW/MSYS)

set -e

REPO_URL="https://github.com/JaeyeonBang/cc-chips-jy.git"
INSTALL_DIR="${HOME}/.claude/cc-chips"
SETTINGS_FILE="${HOME}/.claude/settings.json"
VALID_THEMES="claude cool retro cyber minimal"

# ── Colors for installer output ──────────────────────────────────
_green()  { printf "\033[32m%s\033[0m\n" "$*"; }
_yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
_red()    { printf "\033[31m%s\033[0m\n" "$*"; }
_bold()   { printf "\033[1m%s\033[0m\n" "$*"; }

# ── Detect platform ───────────────────────────────────────────────
case "$(uname -s)" in
    Darwin)          PLATFORM="macos" ;;
    Linux)           PLATFORM="linux" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="gitbash" ;;
    *)               PLATFORM="unknown" ;;
esac

_bold "CC CHIPS-JY Installer"
echo "Platform: $PLATFORM"
echo ""

# ── Check dependencies ────────────────────────────────────────────
missing_deps=0

if ! command -v git >/dev/null 2>&1; then
    _red "Error: git is not installed."
    case "$PLATFORM" in
        macos)   echo "  Install: brew install git" ;;
        linux)   echo "  Install: sudo apt install git  (or your distro's package manager)" ;;
        gitbash) echo "  Install Git for Windows: https://git-scm.com/download/win" ;;
    esac
    missing_deps=1
fi

if ! command -v jq >/dev/null 2>&1; then
    _red "Error: jq is not installed."
    case "$PLATFORM" in
        macos)   echo "  Install: brew install jq" ;;
        linux)   echo "  Install: sudo apt install jq" ;;
        gitbash) echo "  Install: winget install jqlang.jq  (run in PowerShell/cmd)" ;;
    esac
    missing_deps=1
fi

if ! command -v curl >/dev/null 2>&1; then
    _yellow "Warning: curl is not installed — usage API (Row 2) will not work."
    echo "  Row 2 (Current/Weekly usage bars) requires curl."
fi

[ "$missing_deps" -eq 1 ] && exit 1

# ── Clone or update repo ──────────────────────────────────────────
if [ -d "${INSTALL_DIR}/.git" ]; then
    _yellow "Updating existing installation at ${INSTALL_DIR}..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    echo "Cloning CC CHIPS-JY to ${INSTALL_DIR}..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "${INSTALL_DIR}/engine.sh" \
         "${INSTALL_DIR}/install.sh" \
         "${INSTALL_DIR}/uninstall.sh"

# ── Theme selection ───────────────────────────────────────────────
echo ""
echo "Available themes:"
echo "  claude  — Terracotta + white (default, Anthropic brand)"
echo "  cool    — Blue + orange"
echo "  retro   — Pink + lime"
echo "  cyber   — Yellow + teal (cyberpunk neon)"
echo "  minimal — ASCII only, no Nerd Font required"
echo ""
read -r -p "Choose theme [claude]: " chosen_theme
chosen_theme="${chosen_theme:-claude}"

valid=0
for t in $VALID_THEMES; do
    [ "$t" = "$chosen_theme" ] && valid=1 && break
done
if [ "$valid" -eq 0 ]; then
    _yellow "Unknown theme '${chosen_theme}', defaulting to 'claude'."
    chosen_theme="claude"
fi

# ── Write CC_CHIPS_THEME to shell RC ─────────────────────────────
RC_FILE=""
case "$SHELL" in
    */zsh)  RC_FILE="${HOME}/.zshrc"  ;;
    */bash) RC_FILE="${HOME}/.bashrc" ;;
esac

if [ -n "$RC_FILE" ] && [ -f "$RC_FILE" ]; then
    if ! grep -q "CC_CHIPS_THEME" "$RC_FILE" 2>/dev/null; then
        echo "" >> "$RC_FILE"
        echo "export CC_CHIPS_THEME=${chosen_theme}" >> "$RC_FILE"
        echo "Added CC_CHIPS_THEME=${chosen_theme} to ${RC_FILE}"
    else
        _yellow "CC_CHIPS_THEME already set in ${RC_FILE} — not overwriting."
    fi
fi

# ── Backup existing settings.json ────────────────────────────────
if [ -f "$SETTINGS_FILE" ]; then
    BACKUP_FILE="${SETTINGS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    echo "Backed up settings.json to $(basename "$BACKUP_FILE")"
fi

# ── Write statusLine config to settings.json ─────────────────────
ENGINE_PATH="${INSTALL_DIR}/engine.sh"
mkdir -p "$(dirname "$SETTINGS_FILE")"

if [ -f "$SETTINGS_FILE" ]; then
    jq --arg cmd "$ENGINE_PATH" \
        '.statusLine = {"type": "command", "command": $cmd}' \
        "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" \
        && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
else
    jq -n --arg cmd "$ENGINE_PATH" \
        '{"statusLine": {"type": "command", "command": $cmd}}' \
        > "$SETTINGS_FILE"
fi

# ── Install /cc-chips skill ──────────────────────────────────────
SKILL_DIR="${HOME}/.claude/skills/cc-chips"
if [ ! -d "$SKILL_DIR" ]; then
    mkdir -p "$SKILL_DIR"
fi
cp "${INSTALL_DIR}/skills/cc-chips/SKILL.md" "${SKILL_DIR}/SKILL.md"
echo "Installed /cc-chips skill to ${SKILL_DIR}"

# ── Windows Git Bash path warning ────────────────────────────────
if [ "$PLATFORM" = "gitbash" ]; then
    echo ""
    _yellow "Windows Git Bash detected."
    echo "The engine path was written as: ${ENGINE_PATH}"
    WIN_PATH=$(cygpath -w "$ENGINE_PATH" 2>/dev/null || echo "(unable to convert)")
    echo "Windows-native equivalent:      ${WIN_PATH}"
    echo "If Claude Code doesn't pick up the status line, update settings.json"
    echo "to use the Windows path (with double backslashes)."
fi

# ── Success ───────────────────────────────────────────────────────
echo ""
_green "CC CHIPS-JY installed successfully!"
echo "  Location : ${INSTALL_DIR}"
echo "  Theme    : ${chosen_theme}"
echo "  Settings : ${SETTINGS_FILE}"
echo ""
echo "Restart Claude Code to activate the status line."
echo "  Skill    : /cc-chips  (change theme or mode anytime)"
if [ "$chosen_theme" = "minimal" ]; then
    _yellow "  Minimal theme: no Nerd Font required — ASCII mode is active."
else
    _yellow "  Tip: A Nerd Font (e.g. JetBrains Mono Nerd Font) is required for icons."
fi

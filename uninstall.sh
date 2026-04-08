#!/bin/bash

# CC CHIPS-JY — Uninstall script
# Removes the engine, restores settings.json, and optionally restores backup.

INSTALL_DIR="${HOME}/.claude/cc-chips"
SETTINGS_FILE="${HOME}/.claude/settings.json"

# ── Colors ────────────────────────────────────────────────────────
_green()  { printf "\033[32m%s\033[0m\n" "$*"; }
_yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
_bold()   { printf "\033[1m%s\033[0m\n" "$*"; }

_bold "CC CHIPS-JY Uninstaller"
echo ""

# ── Check if installed ────────────────────────────────────────────
if [ ! -d "$INSTALL_DIR" ]; then
    echo "CC CHIPS-JY is not installed at ${INSTALL_DIR}."
    exit 0
fi

# ── Confirm ───────────────────────────────────────────────────────
read -r -p "Remove CC CHIPS-JY from ${INSTALL_DIR}? [y/N] " confirm
case "$confirm" in
    [Yy]*) ;;
    *) echo "Aborted."; exit 0 ;;
esac

# ── Remove statusLine from settings.json ─────────────────────────
if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
    jq 'del(.statusLine)' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" \
        && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "Removed statusLine from ${SETTINGS_FILE}"
elif [ -f "$SETTINGS_FILE" ]; then
    _yellow "jq not found — could not modify settings.json automatically."
    echo "Please manually remove the 'statusLine' key from ${SETTINGS_FILE}"
fi

# ── Remove CC_CHIPS lines from shell RC ──────────────────────────
RC_FILE=""
if [ -n "$ZSH_VERSION" ] || [[ "$SHELL" == */zsh ]]; then
    RC_FILE="${HOME}/.zshrc"
elif [ -n "$BASH_VERSION" ] || [[ "$SHELL" == */bash ]]; then
    RC_FILE="${HOME}/.bashrc"
fi

if [ -n "$RC_FILE" ] && [ -f "$RC_FILE" ]; then
    if grep -q "CC_CHIPS_THEME\|CC_CHIPS_BILLING" "$RC_FILE" 2>/dev/null; then
        sed -i.bak '/export CC_CHIPS_THEME=/d' "$RC_FILE" \
            || sed -i '/export CC_CHIPS_THEME=/d' "$RC_FILE"
        sed -i.bak '/export CC_CHIPS_BILLING=/d' "$RC_FILE" \
            || sed -i '/export CC_CHIPS_BILLING=/d' "$RC_FILE"
        rm -f "${RC_FILE}.bak"
        echo "Removed CC_CHIPS_THEME and CC_CHIPS_BILLING from ${RC_FILE}"
    fi
fi

# ── Remove skill directory ───────────────────────────────────────
SKILL_DIR="${HOME}/.claude/skills/cc-chips"
[ -d "$SKILL_DIR" ] && rm -rf "$SKILL_DIR" && echo "Removed skill directory ${SKILL_DIR}"

# ── Offer backup restore ──────────────────────────────────────────
latest_backup=$(ls -t "${HOME}/.claude/settings.json.bak."* 2>/dev/null | head -1)
if [ -n "$latest_backup" ]; then
    echo ""
    echo "Found backup: $(basename "$latest_backup")"
    read -r -p "Restore this backup? [y/N] " restore
    case "$restore" in
        [Yy]*)
            cp "$latest_backup" "$SETTINGS_FILE"
            _green "Restored ${latest_backup}"
            ;;
    esac
fi

# ── Remove install directory ──────────────────────────────────────
rm -rf "$INSTALL_DIR"
_green "Removed ${INSTALL_DIR}"

# ── Remove cache files ───────────────────────────────────────────
for f in /tmp/claude/statusline-usage-cache.json \
         /tmp/claude/statusline-usage-refresh.lock \
         /tmp/claude/transcript-cache.json \
         /tmp/claude/config-counts.json \
         /tmp/claude/api-time-delta.json \
         /tmp/claude/ccusage-monthly-cache.json; do
    rm -f "$f" "${f}.tmp"
done
echo "Removed CC CHIPS cache files from /tmp/claude/"

# ── Done ─────────────────────────────────────────────────────────
echo ""
_green "CC CHIPS-JY has been completely uninstalled."
echo "Restart Claude Code to deactivate the status line."

---
name: cc-chips
description: Configure CC CHIPS-JY statusline — change theme, billing mode, or show current status
---

# CC CHIPS-JY Configuration Skill

You are a configuration assistant for the CC CHIPS-JY statusline.

## Parse arguments

The user may invoke this skill with arguments like:
- `/cc-chips` — show current status and menu
- `/cc-chips theme <name>` — switch theme
- `/cc-chips mode <subscription|api>` — switch billing mode (a=api, b=subscription)
- `/cc-chips status` — show current config
- `/cc-chips update` — pull latest from git

If no arguments (or just "status"), run the status block and show a menu.
Parse ARGS from the `<command-args>` tag to determine the action.

## Step 1 — Detect environment

```bash
# Detect RC file
if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = */zsh ]; then
  RC_FILE="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ] || [ "$SHELL" = */bash ]; then
  RC_FILE="$HOME/.bashrc"
else
  RC_FILE="$HOME/.bashrc"
fi

# Detect install dir
INSTALL_DIR="$HOME/.claude/cc-chips"

# Read current config
CURRENT_THEME=$(grep -oP '(?<=CC_CHIPS_THEME=)[^\s"]+' "$RC_FILE" 2>/dev/null || echo "claude")
CURRENT_MODE=$(grep -oP '(?<=CC_CHIPS_BILLING=)[^\s"]+' "$RC_FILE" 2>/dev/null || echo "auto")

echo "RC_FILE: $RC_FILE"
echo "INSTALL_DIR: $INSTALL_DIR"
echo "INSTALLED: $([ -d "$INSTALL_DIR" ] && echo yes || echo no)"
echo "CURRENT_THEME: $CURRENT_THEME"
echo "CURRENT_MODE: $CURRENT_MODE"
```

## Step 2 — Route by action

### action = status (or no args)

Show current config and a menu:

```
CC CHIPS-JY — current config
  Theme   : <CURRENT_THEME>  (claude | cool | retro | cyber | minimal)
  Mode    : <CURRENT_MODE>   (subscription | api)
  Install : <INSTALL_DIR>

Commands:
  /cc-chips theme <name>          — switch theme
  /cc-chips mode <subscription|api>  — switch billing mode
  /cc-chips update                — pull latest from git
```

Explain what each theme looks like (one line each):
- claude — Terracotta + white, Anthropic brand colors
- cool — Blue + orange
- retro — Pink + lime
- cyber — Yellow + teal, cyberpunk neon
- minimal — ASCII only, no Nerd Font required

Explain what each mode does:
- subscription — shows OAuth rate-limit bars (Pro/Max plans, default)
- api — shows monthly cost/token usage via ccusage (pay-per-use API users)

### action = theme <name>

Valid names: claude, cool, retro, cyber, minimal

1. Validate the name. If invalid, list valid options and stop.
2. Run:

```bash
THEME="<name>"
RC_FILE="<detected above>"

if grep -q "CC_CHIPS_THEME" "$RC_FILE" 2>/dev/null; then
  # Update existing line (sed in-place, BSD and GNU compatible)
  sed -i.bak "s/export CC_CHIPS_THEME=.*/export CC_CHIPS_THEME=$THEME/" "$RC_FILE" \
    || sed -i "s/export CC_CHIPS_THEME=.*/export CC_CHIPS_THEME=$THEME/" "$RC_FILE"
else
  echo "" >> "$RC_FILE"
  echo "export CC_CHIPS_THEME=$THEME" >> "$RC_FILE"
fi
echo "Theme set to: $THEME"
grep "CC_CHIPS_THEME" "$RC_FILE"
```

3. Tell user: "Theme changed to `<name>`. Run `source <RC_FILE>` then restart Claude Code to apply."

### action = mode <subscription|api|auto>

Valid values: subscription, api

1. Validate the value. If invalid, list valid options and stop.
2. Run:

```bash
MODE="<value>"
RC_FILE="<detected above>"

if grep -q "CC_CHIPS_BILLING" "$RC_FILE" 2>/dev/null; then
  sed -i.bak "s/export CC_CHIPS_BILLING=.*/export CC_CHIPS_BILLING=$MODE/" "$RC_FILE" \
    || sed -i "s/export CC_CHIPS_BILLING=.*/export CC_CHIPS_BILLING=$MODE/" "$RC_FILE"
else
  echo "" >> "$RC_FILE"
  echo "export CC_CHIPS_BILLING=$MODE" >> "$RC_FILE"
fi
echo "Billing mode set to: $MODE"
grep "CC_CHIPS_BILLING" "$RC_FILE"
```

3. Explain what the mode does (see mode descriptions above).
4. Tell user: "Mode set to `<value>`. Run `source <RC_FILE>` then restart Claude Code to apply."

**Note for api mode**: requires `npx ccusage` (auto-installed). Shows monthly cost and token usage from local Claude Code session logs.

### action = update

```bash
INSTALL_DIR="$HOME/.claude/cc-chips"
if [ ! -d "$INSTALL_DIR/.git" ]; then
  echo "ERROR: CC CHIPS-JY not installed at $INSTALL_DIR"
  echo "Run install.sh first: https://github.com/JaeyeonBang/cc-chips-jy"
  exit 1
fi
git -C "$INSTALL_DIR" pull --ff-only
echo "Updated."
```

Tell user to restart Claude Code to pick up changes.

## Error handling

- If `$RC_FILE` doesn't exist: tell the user which file was expected and suggest creating it.
- If `$INSTALL_DIR` is missing and action is update: explain how to install.
- Always show the final state of the relevant env var after any change.

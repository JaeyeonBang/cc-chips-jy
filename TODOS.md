# TODOS

## Chip rendering DRY refactor
**What:** Extract chip rendering (CAP_LEFT + BG + content + CAP_RIGHT) into a helper function.
**Why:** Chips 2, 4, 5, 6 each duplicate the same rendering pattern in both inline (Row 1) and overflow (Row 3) sections. Any rendering change requires updating 8 places.
**Context:** engine.sh lines 645-648 (chip2 inline), 916-919 (chip2 overflow), and similar for chips 4/5/6. A `render_chip fg bg text_color content` function would reduce this to single calls.
**Depends on:** Nothing. Can be done independently.

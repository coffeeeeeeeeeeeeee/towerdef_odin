# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## 5. Game Domain: Relic Types

There are two types of relics:

- **Passive relics** — applied immediately on purchase. Their effect is permanent and global (stacks tracked in `relic_stacks[.KIND]`). They appear in the passive relic list on the left side of the screen during gameplay. Example: `CRYPTOBRO`.
- **Active relics** — go to the player's hand as a card after purchase. The player selects them from the hand and applies them to a specific tile on the map. They use the `pending_tower_action` system. Example: `LUMBERJACK`, `OVERDRIVE`.

In `shop_perform_buy` (`systems/simulation.odin`), active relics are identified with the `is_action_relic` flag and routed to the hand via `card_add_to_hand`. Passive relics call `apply_relic_card` directly.

---

## 6. Known Trap: Card Hand Sell Button vs. Click Handler (`systems/menus.odin`)

**Symptom:** Active relic cards (LUMBERJACK, OVERDRIVE, GARDENER, and any future active relic) appear unsellable from the hand.

**Root cause:** In `render_card_hand` (pasada 2), the card click handler runs **before** `render_button` for the sell button in the same frame. When the mouse is in the sell button area, the click handler fires first and activates the card's pending mode (`pending_tower_action = .KIND`, `selected_card_idx = i`). Immediately after, `card_is_pending` evaluates to `true` and the sell button is skipped. Additionally, the bottom 8px of the sell button fall outside the hover detection rect (`card_y` to `card_y + CARD_H`), so the card isn't considered hovered there and the sell button is never rendered.

**Fix (already applied):**
1. `sell_rect` is computed before the click handler. A `mouse_on_sell` check guards the entire activation block — if the mouse is over the sell button, the click handler is skipped entirely.
2. Hover detection extended by `HOVER_DETECTION_EXTRA = 8` pixels downward to cover the full sell button height.

**Rule for future active relics:** Any new `Card_Kind` that activates via `pending_tower_action` must be added to the `else if card.kind == .X` chain inside the `!mouse_on_sell` guard. No other changes are needed for sell button compatibility.

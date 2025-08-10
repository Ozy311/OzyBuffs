<!-- Author: Ozy -->

# OzyBuffs (Classic Era)

Auto-quip addon for Mage and Priest buffs in WoW Classic Era. When you cast a supported buff, OzyBuffs posts a randomized, class-appropriate line to the chat channel you choose. No macros needed.

## Features
- Auto mode only: watches your successful buff casts, posts a randomized line
- One-line tokens: `%t` target, `%s` spell, `%c` your class
- Humor categories: Neutral, Snarky, Spicy (toggle any combination)
- Per-buff phrase lists, editable in-game
- Export/import helpers to manage large phrase sets
- Phrase files as simple CSV-like lines per class, easy to share and maintain
- Account-wide settings with optional per-character override
- Chat channel routing: AUTO (raid > party > say), or fixed SAY/PARTY/RAID/YELL/EMOTE

## Installation
1) Place this folder in: `_classic_era_/Interface/AddOns/OzyBuffs`
2) Restart client or reload UI with `/reload`

Saved variables: `WTF/Account/<Account>/SavedVariables/OzyBuffs.lua`

## Quick start
- Type `/ob` or `/ozybuffs` to open options
- Choose a chat channel (or leave on AUTO)
- Cast a supported buff and watch a randomized saying appear

Supported buffs
- Mage: Arcane Intellect, Arcane Brilliance, Amplify Magic, Dampen Magic
- Priest: Power Word: Fortitude, Prayer of Fortitude, Divine Spirit, Prayer of Spirit, Shadow Protection, Prayer of Shadow Protection

## Options overview
Open options: `/ob` or `/ozybuffs options`
- Use per-character settings: store settings per-character instead of account-wide
- Channel: SAY/PARTY/RAID/YELL/EMOTE or AUTO (raid > party > say)
- Restrictions: disable in cities (rested), only in group/raid, only in instances, skip self, skip NPCs
- Humor categories: enable/disable Neutral, Snarky, Spicy
- Edit phrases for buff:
  - Buff dropdown: pick the buff to edit
  - Category dropdown: pick the category (Neutral/Snarky/Spicy)
  - Editor area: one phrase per line; tokens `%t`, `%s`, `%c` are supported
  - Save: writes your lines to SavedVariables (overrides file phrases for this buff/category)
  - Reset to defaults: clears your SavedVariables for this buff/category and shows file phrases again
  - Append defaults: merges file phrases into the editor (skips duplicates)
  - Reload phrases from files: re-parse class files into memory without full reload
  - Export current: opens a popup with CSV and Lua-array lines you can paste back into class files

## Phrase files (class data)
OzyBuffs uses per-class files you can edit directly:
- `OzyBuffs_MagePhrases.lua`
- `OzyBuffs_PriestPhrases.lua`

Each file contains a version number and a list of lines:

```lua
OZY_MAGE_LINES_VERSION = 1
OZY_MAGE_LINES = {
  "1459,neutral,%s for %t. Brain cache warmed.",
  "1459,snarky,%t, your brain needs help; have %s.",
  "1459,spicy,%t, %s engaged. IQ unlocked.",
  -- ...
}
```

Format per line (CSV-like): `spellID,category,phrase`
- `spellID`: numeric SpellID (any rank is fine; it resolves to the correct name)
- `category`: `neutral` | `snarky` | `spicy` (also accepts `n` | `s` | `sp`)
- `phrase`: the rest of the line; you may include commas. Use `%t`, `%s`, `%c` tokens

On login/reload, these files are parsed and loaded into memory. If you never save edits, the addon uses these as defaults. When you Save in the editor, your SavedVariables override the file content for that specific buff/category only.

### Exporting and importing
- Export current (in options): opens a popup with two blocks
  - CSV lines (for external manipulation)
  - Lua-array lines, already quoted and comma-terminated for direct paste back into class files
- Reload phrases from files: re-parse class files (memory phrases cleared before reloading to avoid duplicates)

## Slash commands
- `/ob` or `/ozybuffs`: open options
- `/ob options`: open options
- `/ob list`: print supported buffs for your class
- `/ob test <buff>`: preview a randomized line (no cast), e.g. `/ob test fort`

### Aliases for /ob test
- Mage: `ai|int`, `ab|brilliance`, `amp`, `damp`
- Priest: `fort|pwf`, `pof`, `spirit|ds`, `pos`, `shadow|sp`, `posp`

## Phrase format versioning
- Addon phrase format version: v1
- Mage file: `OZY_MAGE_LINES_VERSION = 1`
- Priest file: `OZY_PRIEST_LINES_VERSION = 1`
If a future release bumps the format, OzyBuffs will warn about mismatches so we can add conversion helpers.

## Troubleshooting
- “Nothing prints when I cast”: ensure at least one humor category is enabled; the addon enforces at least one on, but double-check
- “Repeats too often”: Add more lines per category; the addon rotates through a shuffled bag per buff
- “I made changes to files but don’t see them”: use “Reload phrases from files” (options) or `/reload`
- “I want to disable sayings in cities/solo”: enable the corresponding Restrictions in options

## Development
- Folder: `_classic_era_/Interface/AddOns/OzyBuffs`
- TOC: `OzyBuffs.toc`
- Core: `OzyBuffs.lua`
- Options: `OzyBuffs_Options.lua`
- CSV parser and user phrases: `OzyBuffs_UserPhrases.lua`
- Class phrase data: `OzyBuffs_MagePhrases.lua`, `OzyBuffs_PriestPhrases.lua`

Committing with GitHub CLI
```powershell
# Authenticate once
gh auth login --web --scopes "repo"

# Initialize and push (from addon folder)
git init -b main
git add .
git commit -m "feat: initial OzyBuffs v1.0.0"
gh repo create OzyBuffs --source=. --public --remote=origin --push

# Start next version branch
git switch -c v1.1
```

## License
You decide. If unsure, MIT is a common permissive choice. Replace this section with your chosen license details.



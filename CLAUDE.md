# CLAUDE.md — GuildLottery Addon

This file provides AI assistants with essential context about the GuildLottery codebase, its conventions, and development workflows.

---

## Project Overview

**GuildLottery** is a World of Warcraft (WoW) addon that lets guild officers run an in-game lottery system. Players buy tickets with in-game gold; a random winner is selected from across all issued tickets; prize money is split between the winner and the guild bank according to a configurable percentage cut.

This is a **pure client-side Lua addon** — no server, no build system, no package manager. The full project is approximately 35 KB.

---

## Repository Structure

```
GuildLottery/
├── CLAUDE.md               # This file
├── README.md               # User-facing installation & usage guide
├── GuildLottery.toc        # WoW addon manifest (metadata, load order)
├── GuildLottery.lua        # All core logic and UI (~1008 lines)
└── Locales/
    ├── enUS.lua            # English chat message templates
    └── frFR.lua            # French chat message templates
```

### File Roles

| File | Role |
|------|------|
| `GuildLottery.toc` | Declares addon name, version, author, supported WoW interface versions, saved-variable names, and the file load order |
| `GuildLottery.lua` | Single monolithic file containing all runtime logic: state management, helper functions, GUI construction, tab panels, slash-command registration |
| `Locales/enUS.lua` | Eight format-string templates for every chat announcement (lottery start, rules, player entry, donation, result, payout, no-winner, reset) |
| `Locales/frFR.lua` | French equivalents of the same eight templates |

---

## Technology Stack

- **Language**: Lua 5.1 (the version embedded in the WoW client)
- **Runtime environment**: World of Warcraft game client (Classic/Retail, interface 12.0.x)
- **UI framework**: WoW's built-in XML widget system accessed through Lua APIs (`CreateFrame`, `UIPanelScrollFrameTemplate`, etc.)
- **Persistence**: WoW `SavedVariables` (declared in the .toc file as `GuildLotteryDB`)
- **No external tools**: No Node, npm, Python, or build pipeline of any kind

---

## Architecture & Key Conventions

### Namespace

The global table is named `GuildLottery`; a module-local alias `GL` is used throughout the file:

```lua
GuildLottery = {}
local GL = GuildLottery
```

All addon state and functions live on `GL`. Never use raw globals for addon-internal data.

```lua
GL.participants = {}    -- ordered array of participant entries
GL.nextTicket   = 1     -- monotonically increasing ticket counter
GL.isStarted    = false -- true once the lottery has been announced
GL.donations    = {}    -- ordered array of donation entries (gold without tickets)
GL.settings     = { ... }
```

### Participant Entry Format

Each entry in `GL.participants` is a table with these keys:

```lua
{
    name        = "PlayerName",   -- string, WoW character name
    tickets     = 3,              -- number of tickets purchased
    firstTicket = 5,              -- first ticket number (inclusive)
    lastTicket  = 7,              -- last ticket number (inclusive)
    removed     = false,          -- soft-delete flag (keeps ticket slots reserved)
}
```

Removed participants are **never actually deleted** from the array; their `removed` flag is set to `true` so their ticket numbers stay reserved and cannot be re-issued.

### Donation Entry Format

Each entry in `GL.donations` is a table with these keys:

```lua
{
    name    = "PlayerName",  -- string, donor name
    amount  = 500,           -- gold amount donated
    removed = false,         -- soft-delete flag
}
```

Donations add gold to the pot without issuing tickets. Donors do not participate in the roll.

### Localization / MSG Table

Chat messages come from a module-level `MSG` table populated at file load time:

```lua
local MSG = GuildLotteryLocale and GuildLotteryLocale["frFR"] or {}
```

> **Important**: The locale key is currently **hardcoded to `"frFR"`** on line 29 of `GuildLottery.lua`. This means French templates are always used regardless of the client language. If `GuildLotteryLocale` is nil (locale files not loaded), `MSG` falls back to an empty table and no chat messages will appear.

Each locale file (e.g. `Locales/enUS.lua`) builds the `GuildLotteryLocale` global table:

```lua
GuildLotteryLocale = GuildLotteryLocale or {}
GuildLotteryLocale["enUS"] = { start = "...", rules = "...", ... }
```

There are **8 message keys** in each locale:

| Key | Placeholders | Description |
|-----|-------------|-------------|
| `start` | `%s` price, `%d` min, `%d` max | Lottery open announcement |
| `rules` | (none) | Static rules message |
| `entry` | `%s` name, `%d` count, `%s` plural (`""` or `"s"`), `%s` ticket range | Player entry |

| `result` | `%d` roll, `%d` tickets, `%s` ticket range, `%s` winner name | Winner announcement |
| `payout` | `%s` winner name, `%d` pot, `%d` winner cut, `%d%%` winner pct, `%d` guild cut, `%d%%` guild pct | Prize breakdown |
| `donation` | `%s` name, `%d` gold amount | Donation announcement |
| `noWin` | (none) | No valid winner fallback |
| `reset` | (none) | Lottery reset announcement |

To change the active locale, update the hardcoded key on line 29 of `GuildLottery.lua`, or implement dynamic detection using `GetLocale()`.

To add a new locale:
1. Create `Locales/xxXX.lua` following the same structure as `enUS.lua`.
2. Add the filename to `GuildLottery.toc` (before `GuildLottery.lua`).
3. Change the hardcoded locale key on line 29 of `GuildLottery.lua` to `"xxXX"`.

### WoW Color Codes

Inline chat/UI colors use WoW's `|cffRRGGBB…|r` escape sequences. Colors used in the addon:

| Purpose | Escape |
|---------|--------|
| Gold amounts | `|cffFFD700` |
| Active / positive values | `|cff00ff00` (green) |
| Warning / guild cut | `|cffff9900` (orange) |
| Dimmed / secondary text | `|cffaaaaaa` (gray) |
| Ticket counts in chat | `|cffffff00` (yellow) |

### Slash Commands

```
/lottery   — opens the main window
/gl        — alias for /lottery
```

Both are registered with `SLASH_GUILDLOTTERY1` / `SLASH_GUILDLOTTERY2` globals and point to the same handler (lines 745–747).

### Minimap Button

A complete minimap button implementation exists at the bottom of `GuildLottery.lua` (lines ~750–834) but is **commented out**. To re-enable it, uncomment the block and ensure the `LibStub`/`LibDBIcon` dependency is available, or adapt it to the native `Minimap` frame APIs already partially used there.

---

## Core Logic Reference

### Ticket Assignment

```
GL.nextTicket starts at 1.
When a player is added with N tickets:
    entry.firstTicket = GL.nextTicket
    entry.lastTicket  = GL.nextTicket + N - 1
    GL.nextTicket    += N
```

Ticket numbers are immutable once assigned.

### Winner Selection (`GL:RollWinner`)

1. Validate active tickets exist; if none, announce via `MSG.noWin` and return
2. Announce rolling message via `MSG.rolling` with participant/ticket counts
3. Build a lookup table: `ticketOwner[ticketNum] = participantEntry` (active entries only)
4. Roll `math.random(1, MaxTicket())` — `MaxTicket()` returns `GL.nextTicket - 1`
5. If the rolled ticket belongs to a removed player, re-roll (up to 500 attempts)
6. Announce winner via `SendLotteryMessage` using `MSG.result` and `MSG.payout`
7. On failure (all tickets belong to removed players), announce via `MSG.noWin`
8. Return `(winnerName, rollNumber)`

### Prize Calculation (`CalcPrize`)

```
totalPot     = activeTickets * ticketPriceValue + totalDonations   (gold)
guildCut     = floor(totalPot * guildCutPct / 100)
winnerPrize  = totalPot - guildCut
winnerPct    = 100 - guildCutPct
```

### Chat Channel Routing (`SendLotteryMessage`)

`GL.settings.chatChannel` can be `"GUILD"`, `"RAID"`, `"PARTY"`, `"SAY"`, or `"YELL"`. The helper calls `SendChatMessage(msg, channel)` accordingly.

---

## UI Structure

The main window is a standard `Frame` built inside `GL:CreateGUI()`. It contains four tabbed panels:

| Tab | Purpose |
|-----|---------|
| **Add Player** | Text input + autocomplete list filtered from guild roster (3-column layout, live filtering); validates ticket count against min/max settings |
| **Participants** | Scrollable list of Name / Tickets / Ticket Range with summary header; "Remove Selected" soft-deletes |
| **Controls** | Live prize summary box; donation input (name + gold amount); four buttons: Announce Start, Announce Rules, Roll Winner, Reset |
| **Settings** | Ticket price (label + gold value), min/max ticket counts, guild cut slider (0–100% with − / + buttons), chat channel dropdown |

`GL:RefreshParticipantList()` and `RefreshPrizeSummary()` are the two functions that **must** be called whenever underlying state changes to keep the UI consistent.

### Participants List Details

- Active participants: clickable/selectable rows shown normally
- Removed participants: dimmed rows with a `[removed]` label appended; not selectable for rolling but still displayed
- Header row shows: active participant count, total active tickets, full ticket pool range

---

## Development Workflow

### Testing

There is no automated test suite. All testing is done manually inside the WoW game client:

1. Copy the entire `GuildLottery/` folder into:
   `World of Warcraft/_retail_/Interface/AddOns/GuildLottery/`
2. Log in to WoW (or type `/reload` in-game to reload the UI without restarting).
3. Type `/lottery` to open the addon window.
4. Exercise each tab and button, and observe chat output.

### Making Changes

- **Core logic changes** → edit `GuildLottery.lua`
- **Chat message wording** → edit `Locales/frFR.lua` (the currently active locale); mirror changes to other locale files
- **Active locale** → change the hardcoded key `"frFR"` on line 29 of `GuildLottery.lua`
- **Adding a new WoW interface version** → add the numeric version to the `## Interface:` line in `GuildLottery.toc`
- **Adding a new locale** → create `Locales/xxXX.lua`, register it in the `.toc`, update the locale key in `GuildLottery.lua`

### No Build Step

WoW addons are deployed as plain text files. There is no compilation, minification, or bundling. Changes are effective immediately after `/reload`.

### Pre-PR Documentation Checklist

Before opening a pull request, verify that CLAUDE.md is still accurate:

- **New functions or helpers** → add them to the relevant section (Core Logic Reference, WoW API Conventions, etc.)
- **Renamed/removed fields** → update Participant Entry Format and any references to the old names
- **New settings keys** → document them in the namespace section and the Settings tab description
- **New chat messages** → add rows to the MSG key reference table in the Localization section
- **Locale key changed** → update the hardcoded locale note in the Localization section
- **New slash commands** → add them to the Slash Commands section
- **New UI tabs or panels** → update the UI Structure table
- **New WoW API calls** → add them to the WoW API Conventions table
- **Line count shifts significantly** → update the `~1008 lines` note in the Repository Structure section

If CLAUDE.md needed changes, include them in the same commit (or PR) as the code change — not as a follow-up.

---

## WoW API Conventions

Common WoW Lua APIs used throughout the file:

| API | Purpose |
|-----|---------|
| `CreateFrame(type, name, parent, template)` | Create UI widgets |
| `IsInGuild()` | Check if the player is in a guild |
| `GetNumGuildMembers()` | Count guild roster size |
| `GetGuildRosterInfo(index)` | Fetch data for one guild member |
| `SendChatMessage(msg, channel)` | Send a message to a chat channel |
| `math.random(min, max)` | Generate a random integer (WoW-provided) |
| `math.floor(n)` | Floor a number (Lua standard) |
| `string.format(fmt, ...)` | Standard Lua string formatting |
| `table.insert / table.remove` | Standard Lua table helpers |

Avoid using `print()` for user-visible output; use `SendLotteryMessage()` or `DEFAULT_CHAT_FRAME:AddMessage()` for in-game display.

---

## Adding Features — Checklist

When adding a new feature:

1. **State**: Add any new persistent fields to `GL.settings` (auto-saved via SavedVariables) or to `GL` itself (session-only).
2. **UI**: Add UI elements inside `GL:CreateGUI()` in the appropriate tab section. Follow the existing `CreateFrame` patterns.
3. **Refresh**: Call `GL:RefreshParticipantList()` and/or `RefreshPrizeSummary()` after any state mutation that affects the displayed UI.
4. **Localization**: If the feature produces chat output, add a new key to `MSG` in **each** locale file and use `string.format(MSG.newKey, ...)` rather than hardcoded strings.
5. **Slash commands**: If adding a new command, register it with a new `SLASH_GUILDLOTTERY#` global.

---

## Conventions Summary

- The global is `GuildLottery`; use the module-local alias `GL` for all internal references.
- Never hardcode chat message text; always go through the `MSG` locale table.
- Participant entry keys are `firstTicket` and `lastTicket` (not `start`/`finish`).
- Ticket numbers are monotonically increasing and never reused; use soft-delete (`removed = true`) instead of splicing arrays.
- WoW color codes follow the `|cffRRGGBB…|r` format.
- Keep all logic in `GuildLottery.lua` unless it is purely a locale string, in which case it belongs in the appropriate `Locales/` file.
- No external dependencies; use only WoW built-in APIs and the Lua 5.1 standard library.
- The active locale is currently hardcoded to `"frFR"` on line 29 of `GuildLottery.lua`.

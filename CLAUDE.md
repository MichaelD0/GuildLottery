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
├── GuildLottery.lua        # All core logic and UI (~826 lines)
└── Locales/
    ├── enUS.lua            # English chat message templates
    └── frFR.lua            # French chat message templates
```

### File Roles

| File | Role |
|------|------|
| `GuildLottery.toc` | Declares addon name, version, author, supported WoW interface versions, saved-variable names, and the file load order |
| `GuildLottery.lua` | Single monolithic file containing all runtime logic: state management, helper functions, GUI construction, tab panels, slash-command registration |
| `Locales/enUS.lua` | Eight format-string templates for every chat announcement (lottery start, rules, player entry, rolling, result, payout, no-winner, reset) |
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

All addon state and functions live on the global table `GL` (short for `GuildLottery`):

```lua
GL = {}
GL.participants = {}    -- ordered array of participant entries
GL.nextTicket   = 1     -- monotonically increasing ticket counter
GL.isStarted    = false -- true once the lottery has been announced
GL.settings     = { ... }
```

Never use raw globals for addon-internal data; always attach to `GL`.

### Participant Entry Format

Each entry in `GL.participants` is a table with these keys:

```lua
{
    name     = "PlayerName",   -- string, WoW character name
    tickets  = 3,              -- number of tickets purchased
    start    = 5,              -- first ticket number (inclusive)
    removed  = false,          -- soft-delete flag (keeps ticket slots reserved)
}
```

Removed participants are **never actually deleted** from the array; their `removed` flag is set to `true` so their ticket numbers stay reserved and cannot be re-issued.

### Localization / MSG Table

Chat messages come from a module-level `MSG` table populated by the locale files loaded before `GuildLottery.lua`. Each value is a Lua format string with `%s`/`%d` placeholders. To add a new locale:

1. Create `Locales/xxXX.lua` following the same structure as `enUS.lua`.
2. Add the filename to `GuildLottery.toc` (before `GuildLottery.lua`).
3. Guard the assignment so it only runs when the client locale matches.

### WoW Color Codes

Inline chat colors use WoW's `|cffRRGGBB…|r` escape sequences. Gold-colored text for ticket counts uses `|cffffff00…|r`.

### Slash Commands

```
/lottery   — opens the main window
/gl        — alias for /lottery
```

Both are registered with `SLASH_GUILDLOTTERY1` / `SLASH_GUILDLOTTERY2` globals and point to the same handler.

### Minimap Button

A complete minimap button implementation exists at the bottom of `GuildLottery.lua` (lines ~742–826) but is **commented out**. To re-enable it, uncomment the block and ensure the `LibStub`/`LibDBIcon` dependency is available, or adapt it to the native `Minimap` frame APIs already partially used there.

---

## Core Logic Reference

### Ticket Assignment

```
GL.nextTicket starts at 1.
When a player is added with N tickets:
    entry.start  = GL.nextTicket
    entry.finish = GL.nextTicket + N - 1
    GL.nextTicket += N
```

Ticket numbers are immutable once assigned.

### Winner Selection (`GL:RollWinner`)

1. Build a lookup table: `ticketOwner[ticketNum] = participantEntry`
2. Roll `math.random(1, MaxTicket())` — `MaxTicket()` returns `GL.nextTicket - 1`
3. If the rolled ticket belongs to a removed player, re-roll (up to 500 attempts)
4. Announce winner via `SendLotteryMessage` using `MSG.result` and `MSG.payout`
5. On failure (all tickets belong to removed players), announce via `MSG.noWin`

### Prize Calculation (`CalcPrize`)

```
totalPot     = activeTickets * ticketPriceValue   (gold)
guildCut     = totalPot * (guildCutPct / 100)
winnerPrize  = totalPot - guildCut
```

### Chat Channel Routing (`SendLotteryMessage`)

`GL.settings.chatChannel` can be `"GUILD"`, `"RAID"`, `"PARTY"`, `"SAY"`, or `"YELL"`. The helper calls `SendChatMessage(msg, channel)` accordingly.

---

## UI Structure

The main window is a standard `Frame` built inside `GL:CreateGUI()`. It contains four tabbed panels:

| Tab | Purpose |
|-----|---------|
| **Add Player** | Text input + autocomplete list filtered from guild roster; validates ticket count against min/max settings |
| **Participants** | Scrollable list of Name / Ticket Count / Ticket Range; "Remove Selected" soft-deletes |
| **Controls** | Live prize summary; buttons to announce start, announce rules, roll winner, and reset |
| **Settings** | Ticket price (label + gold value), min/max ticket counts, guild cut slider, chat channel dropdown |

`GL:RefreshParticipantList()` and `RefreshPrizeSummary()` are the two functions that must be called whenever underlying state changes in order to keep the UI consistent.

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
- **Chat message wording** → edit `Locales/enUS.lua` (and mirror changes to other locale files)
- **Adding a new WoW interface version** → add the numeric version to the `## Interface:` line in `GuildLottery.toc`
- **Adding a new locale** → create `Locales/xxXX.lua`, register it in the `.toc`, add a locale guard

### No Build Step

WoW addons are deployed as plain text files. There is no compilation, minification, or bundling. Changes are effective immediately after `/reload`.

---

## WoW API Conventions

Common WoW Lua APIs used throughout the file:

| API | Purpose |
|-----|---------|
| `CreateFrame(type, name, parent, template)` | Create UI widgets |
| `GetNumGuildMembers()` | Count guild roster size |
| `GetGuildRosterInfo(index)` | Fetch data for one guild member |
| `SendChatMessage(msg, channel)` | Send a message to a chat channel |
| `math.random(min, max)` | Generate a random integer (WoW-provided) |
| `string.format(fmt, ...)` | Standard Lua string formatting |
| `table.insert / table.remove` | Standard Lua table helpers |

Avoid using `print()` for user-visible output; use `SendLotteryMessage()` or `DEFAULT_CHAT_FRAME:AddMessage()` for in-game display.

---

## Adding Features — Checklist

When adding a new feature:

1. **State**: Add any new persistent fields to `GL.settings` (auto-saved via SavedVariables) or to `GL` itself (session-only).
2. **UI**: Add UI elements inside `GL:CreateGUI()` in the appropriate tab section. Follow the existing `CreateFrame` patterns.
3. **Refresh**: Call `GL:RefreshParticipantList()` and/or `RefreshPrizeSummary()` after any state mutation that affects the displayed UI.
4. **Localization**: If the feature produces chat output, add a new key to `MSG` in each locale file and use `string.format(MSG.newKey, ...)` rather than hardcoded strings.
5. **Slash commands**: If adding a new command, register it with a new `SLASH_GUILDLOTTERY#` global.

---

## Conventions Summary

- Use the `GL` namespace for all addon state and methods.
- Never hardcode chat message text; always go through the `MSG` locale table.
- Ticket numbers are monotonically increasing and never reused; use soft-delete (`removed = true`) instead of splicing arrays.
- WoW color codes follow the `|cffRRGGBB…|r` format.
- Keep all logic in `GuildLottery.lua` unless it is purely a locale string, in which case it belongs in the appropriate `Locales/` file.
- No external dependencies; use only WoW built-in APIs and the Lua 5.1 standard library.

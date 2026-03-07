# Guild Lottery – WoW Addon

## Installation
1. Copy the `GuildLottery` folder into:
   `World of Warcraft/_retail_/Interface/AddOns/`
2. Restart the game or reload your UI (`/reload`).

## Opening the Addon
- Type `/lottery` or `/gl` in chat.
- Or click the **dice icon** on your minimap.

---

## Tabs

### Add Player
- Type (or start typing) a player's name — guild members auto-suggest below.
- Click a guild member button to fill their name instantly.
- Set ticket count, then click **Add**.
- A chat message is sent announcing their entry and ticket numbers.

### Participants
- Shows everyone currently registered with their ticket count.
- Click a row to select it; use **Remove Selected** to remove them.

### Controls
| Button | Action |
|---|---|
| 📣 Announce Game Started | Sends the start message to chat with price/ticket limits |
| 📜 Announce Rules & Settings | Sends the rules message |
| 🎲 Roll for Winner! | Rolls randomly across all tickets, announces winner |
| 🔄 Reset Lottery | Clears all participants and announces a reset |

### Settings
- **Ticket Price** – cosmetic label used in announcements.
- **Min / Max Tickets** – enforced when adding players.
- **Chat Channel** – GUILD, RAID, PARTY, SAY, or YELL.

---

## Customising Messages
Open `GuildLottery.lua` and edit the `MSG` table near the top:

```lua
local MSG = {
    start   = "🎰 [GuildLottery] The lottery is now OPEN! ...",
    rules   = "📜 [GuildLottery] RULES: ...",
    entry   = "🎟️ [GuildLottery] %s has entered with %d ticket(s)! (Tickets #%d–%d)",
    rolling = "🎲 [GuildLottery] Rolling... %d participants, %d total tickets!",
    result  = "🏆 [GuildLottery] The winning number is %d — Congratulations to %s! (%d ticket(s))",
    noWin   = "❌ [GuildLottery] No winner found.",
    reset   = "🔄 [GuildLottery] The lottery has been reset.",
}
```

The `%s` and `%d` are placeholders (string / number) — keep them in the right order.

---

## How the Roll Works
Every ticket gets a slot in a pool. Example:
- Alice bought 3 tickets → slots 1, 2, 3
- Bob bought 1 ticket → slot 4
- Carol bought 2 tickets → slots 5, 6

The addon rolls `/random 1–6`. Whoever owns that slot wins. More tickets = better odds.

## Interface Version
The `.toc` file currently targets **10.2.7** (`100207`). Update this number if you're on a different patch.

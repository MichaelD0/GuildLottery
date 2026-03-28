-- English (default) chat messages for GuildLottery
GuildLotteryLocale = GuildLotteryLocale or {}

GuildLotteryLocale["enUS"] = {
    start   = "[GuildLottery] ** LOTTERY OPEN ** Buy tickets from the host! Cost: %s each. Min: %d, Max: %d per person.",
    rules   = "[GuildLottery] RULES: Each ticket you buy is one chance to win. The host rolls a number and the matching ticket wins the prize!",
    entry   = "[GuildLottery] %s has entered with %d ticket(s)! (Ticket%s #%s)",

    result  = "[GuildLottery] ** WINNER ** Roll: %d -- (%d ticket(s), #%s) -- Congratulations to %s!",
    payout  = "[GuildLottery] Payout: %s -- Pot: %dg -- Winner: %dg (%d%%) -- Guild: %dg (%d%%)",
    noWin   = "[GuildLottery] No winner found. Is the pool empty?",
    donation = "[GuildLottery] %s has donated %dg to the pot!",
    reset   = "[GuildLottery] The lottery has been reset. Good luck next round!",
}

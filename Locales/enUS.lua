-- English (default) chat messages for GuildLottery
GuildLotteryLocale = GuildLotteryLocale or {}

GuildLotteryLocale["enUS"] = {
    start   = "[GuildLottery] ** LOTTERY OPEN ** Buy tickets from the host! Cost: %s each. Min: %d, Max: %d per person.",
    rules   = "[GuildLottery] RULES: Each ticket you buy is one chance to win. The host rolls a number and the matching ticket wins the prize!",
    entry   = "[GuildLottery] %s has entered with %d ticket(s)! (Ticket%s #%s)",
    rolling = "[GuildLottery] Rolling 1-%d... (%d active participants, %d active tickets)",
    result  = "[GuildLottery] ** WINNER ** Roll: %d -- (%d ticket(s), #%s) -- Congratulations to %s!",
    payout  = "[GuildLottery] Prize breakdown -- Total pot: %dg - Winner gets: %dg (%d%%) - Guild cut: %dg (%d%%)",
    noWin   = "[GuildLottery] No winner found. Is the pool empty?",
    reset   = "[GuildLottery] The lottery has been reset. Good luck next round!",
}

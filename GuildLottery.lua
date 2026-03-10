-- GuildLottery.lua
-- A fully featured lottery addon for World of Warcraft

GuildLottery    = {}
local GL        = GuildLottery

-- ============================================================
-- DATA
-- ============================================================
-- GL.participants: ordered list of entries, each:
--   { name, tickets, firstTicket, lastTicket, removed }
-- Ticket numbers are assigned at add-time and NEVER change.
-- Removed entries are kept so their ticket slots stay reserved.
GL.participants = {}
GL.nextTicket   = 1 -- next ticket number to assign
GL.isStarted    = false
GL.settings     = {
    minTickets       = 1,
    maxTickets       = 10,
    ticketPrice      = "1000g", -- display label
    ticketPriceValue = 1000,    -- numeric gold value used for prize math
    guildCutPct      = 50,      -- 0–100 integer percent that goes to the guild
    chatChannel      = "GUILD", -- GUILD, RAID, PARTY, SAY, YELL
}

-- ============================================================
-- MESSAGES  (locale-aware; see Locales/ folder to add translations)
-- ============================================================
local MSG       = GuildLotteryLocale and GuildLotteryLocale["frFR"]
                  or {}  -- safety fallback

-- ============================================================
-- HELPERS
-- ============================================================
local function SendLotteryMessage(msg)
    SendChatMessage(msg, GL.settings.chatChannel)
end

local function TicketRange(entry)
    if entry.tickets == 1 then
        return tostring(entry.firstTicket)
    else
        return entry.firstTicket .. "-" .. entry.lastTicket
    end
end

local function GetGuildMembers()
    local members = {}
    if IsInGuild() then
        local n = GetNumGuildMembers()
        for i = 1, n do
            local name = GetGuildRosterInfo(i)
            if name then
                tinsert(members, Ambiguate(name, "short"))
            end
        end
    end
    table.sort(members)
    return members
end

-- Returns active participant entry for a name, or nil
local function FindParticipant(name)
    for _, e in ipairs(GL.participants) do
        if e.name == name and not e.removed then
            return e
        end
    end
end

-- Count active participants and their total active tickets
local function ActiveStats()
    local count, total = 0, 0
    for _, e in ipairs(GL.participants) do
        if not e.removed then
            count = count + 1
            total = total + e.tickets
        end
    end
    return count, total
end

-- Highest ticket number currently issued (including removed players)
local function MaxTicket()
    return GL.nextTicket - 1
end

-- Returns total pot, guild cut, and winner cut (all in gold)
local function CalcPrize()
    local _, activeTotal = ActiveStats()
    local pot            = activeTotal * GL.settings.ticketPriceValue
    local guildCut       = math.floor(pot * GL.settings.guildCutPct / 100)
    local winnerCut      = pot - guildCut
    return pot, guildCut, winnerCut
end

-- Refresh the prize summary label wherever it is shown
local function RefreshPrizeSummary()
    if not GL.prizeSummary then return end
    local _, _, activeTotal = ActiveStats()
    local pot, guildCut, winnerCut = CalcPrize()
    local winnerPct = 100 - GL.settings.guildCutPct
    GL.prizeSummary:SetText(
        ("Total pot: |cffFFD700%dg|r     " ..
            "Winner: |cff00ff00%dg|r |cffaaaaaa(%d%%)|r     " ..
            "Guild: |cffff9900%dg|r |cffaaaaaa(%d%%)|r"):format(
            pot, winnerCut, winnerPct, guildCut, GL.settings.guildCutPct
        )
    )
end

-- ============================================================
-- CORE ACTIONS
-- ============================================================
function GL:AddParticipant(name, tickets)
    name    = name:gsub("^%s+", ""):gsub("%s+$", "")
    tickets = tonumber(tickets) or 1

    if name == "" then return false, "Name cannot be empty." end
    if FindParticipant(name) then
        return false, name .. " is already in the lottery."
    end
    if tickets < GL.settings.minTickets then
        return false, ("Minimum tickets is %d."):format(GL.settings.minTickets)
    end
    if tickets > GL.settings.maxTickets then
        return false, ("Maximum tickets is %d."):format(GL.settings.maxTickets)
    end

    local first   = GL.nextTicket
    local last    = first + tickets - 1
    GL.nextTicket = last + 1

    local entry   = { name = name, tickets = tickets, firstTicket = first, lastTicket = last, removed = false }
    tinsert(GL.participants, entry)

    local plural = tickets > 1 and "s" or ""
    SendLotteryMessage(MSG.entry:format(name, tickets, plural, TicketRange(entry)))
    return true, ("Added %s -- tickets #%s"):format(name, TicketRange(entry))
end

function GL:RemoveParticipant(name)
    for _, e in ipairs(GL.participants) do
        if e.name == name and not e.removed then
            e.removed = true
            return true
        end
    end
    return false
end

function GL:AnnounceStart()
    GL.isStarted = true
    SendLotteryMessage(MSG.start:format(
        GL.settings.ticketPrice,
        GL.settings.minTickets,
        GL.settings.maxTickets
    ))
end

function GL:AnnounceRules()
    SendLotteryMessage(MSG.rules)
end

function GL:RollWinner()
    local count, activeTotal = ActiveStats()

    if activeTotal == 0 then
        SendLotteryMessage(MSG.noWin)
        return nil
    end

    -- We roll over the full issued range and re-roll if we land on a
    -- removed player's ticket slot. This keeps all original numbers intact.
    local maxT = MaxTicket()
    SendLotteryMessage(MSG.rolling:format(maxT, count, activeTotal))

    -- Build ticket -> entry lookup (active only)
    local lookup = {}
    for _, e in ipairs(GL.participants) do
        if not e.removed then
            for t = e.firstTicket, e.lastTicket do
                lookup[t] = e
            end
        end
    end

    local roll, winner
    local attempts = 0
    repeat
        roll     = math.random(1, maxT)
        winner   = lookup[roll]
        attempts = attempts + 1
    until winner or attempts > 500

    if not winner then
        SendLotteryMessage(MSG.noWin)
        return nil
    end

    SendLotteryMessage(MSG.result:format(
        roll, winner.name, winner.tickets, TicketRange(winner)
    ))

    -- Announce prize split
    local pot, guildCut, winnerCut = CalcPrize()
    if pot > 0 then
        SendLotteryMessage(MSG.payout:format(
            pot, winnerCut, 100 - GL.settings.guildCutPct, guildCut, GL.settings.guildCutPct
        ))
    end

    return winner.name, roll
end

function GL:Reset()
    GL.participants = {}
    GL.nextTicket   = 1
    GL.isStarted    = false
    SendLotteryMessage(MSG.reset)
    if GL.frame then GL:RefreshParticipantList() end
end

-- ============================================================
-- GUI
-- ============================================================
local FRAME_W, FRAME_H = 560, 600

function GL:CreateGUI()
    if GL.frame then
        GL.frame:Show(); return
    end

    local f = CreateFrame("Frame", "GuildLotteryFrame", UIParent, "BasicFrameTemplateWithInset")
    GL.frame = f
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f.TitleText:SetText("Guild Lottery")

    -- TABS
    local tabY = -30
    local function MakeTab(label, x)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(118, 26)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, tabY)
        btn:SetText(label)
        return btn
    end

    local tabAdd      = MakeTab("Add Player", 8)
    local tabList     = MakeTab("Participants", 130)
    local tabControl  = MakeTab("Controls", 252)
    local tabSettings = MakeTab("Settings", 374)

    -- PANELS
    local function Panel()
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -62)
        p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
        p:Hide()
        return p
    end

    local panelAdd      = Panel()
    local panelList     = Panel()
    local panelControl  = Panel()
    local panelSettings = Panel()

    local function ShowPanel(p)
        panelAdd:Hide(); panelList:Hide(); panelControl:Hide(); panelSettings:Hide()
        p:Show()
    end

    tabAdd:SetScript("OnClick", function() ShowPanel(panelAdd) end)
    tabList:SetScript("OnClick", function()
        ShowPanel(panelList)
        GL:RefreshParticipantList()
    end)
    tabControl:SetScript("OnClick", function() ShowPanel(panelControl) end)
    tabSettings:SetScript("OnClick", function() ShowPanel(panelSettings) end)

    -- --------------------------------------------------------
    -- TAB: ADD PLAYER
    -- --------------------------------------------------------
    do
        local p = panelAdd

        local lName = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lName:SetPoint("TOPLEFT", p, 10, -15)
        lName:SetText("Player Name:")

        local eName = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        GL.nameBox = eName
        eName:SetSize(200, 22)
        eName:SetPoint("TOPLEFT", lName, "BOTTOMLEFT", 0, -4)
        eName:SetAutoFocus(false)
        eName:SetMaxLetters(64)

        local lTick = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lTick:SetPoint("TOPLEFT", eName, "TOPRIGHT", 20, 0)
        lTick:SetText("Tickets:")

        local eTick = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        GL.tickBox = eTick
        eTick:SetSize(55, 22)
        eTick:SetPoint("TOPLEFT", lTick, "BOTTOMLEFT", 0, -4)
        eTick:SetAutoFocus(false)
        eTick:SetNumeric(true)
        eTick:SetMaxLetters(3)
        eTick:SetText("1")

        local btnAdd = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        btnAdd:SetSize(90, 26)
        btnAdd:SetPoint("LEFT", eTick, "RIGHT", 10, 0)
        btnAdd:SetText("Add")

        local status = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        GL.statusText = status
        status:SetPoint("TOPLEFT", eName, "BOTTOMLEFT", 0, -10)
        status:SetWidth(480)

        btnAdd:SetScript("OnClick", function()
            local ok, msg = GL:AddParticipant(eName:GetText(), eTick:GetText())
            if ok then
                eName:SetText("")
                eTick:SetText("1")
                status:SetText("|cff00ff00" .. msg .. "|r")
                GL:RefreshParticipantList()
                RefreshPrizeSummary()
                if GL.RefreshGuildSuggestions then GL.RefreshGuildSuggestions("") end
            else
                status:SetText("|cffff4444Error: " .. msg .. "|r")
            end
        end)

        eTick:SetScript("OnEnterPressed", function() btnAdd:Click() end)

        -- Guild member suggestions
        local lSuggest = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lSuggest:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -14)
        lSuggest:SetText("Guild Members (click to fill; greyed = already entered):")

        local scrollFrame = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", lSuggest, "BOTTOMLEFT", 0, -6)
        scrollFrame:SetSize(500, 330)

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(480, 1)
        scrollFrame:SetScrollChild(content)

        local function RefreshGuildList(filter)
            for _, child in ipairs({ content:GetChildren() }) do
                child:Hide(); child:SetParent(nil)
            end
            local members = GetGuildMembers()
            local row, col = 0, 0
            local BW, BH, PAD = 148, 22, 4
            for _, name in ipairs(members) do
                local already = FindParticipant(name) ~= nil
                if not filter or filter == "" or name:lower():find(filter:lower(), 1, true) then
                    local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
                    btn:SetSize(BW, BH)
                    btn:SetPoint("TOPLEFT", content, col * (BW + PAD), -row * (BH + PAD))
                    btn:SetText(already and ("|cff888888" .. name .. "|r") or name)
                    btn:SetEnabled(not already)
                    btn:SetScript("OnClick", function()
                        eName:SetText(name)
                        eTick:SetFocus()
                    end)
                    col = col + 1
                    if col >= 3 then
                        col = 0; row = row + 1
                    end
                end
            end
            content:SetHeight(math.max(1, (row + 1) * (BH + PAD)))
        end

        eName:SetScript("OnTextChanged", function(self) RefreshGuildList(self:GetText()) end)
        p:SetScript("OnShow", function() RefreshGuildList("") end)
        GL.RefreshGuildSuggestions = RefreshGuildList
    end

    -- --------------------------------------------------------
    -- TAB: PARTICIPANTS LIST
    -- --------------------------------------------------------
    do
        local p = panelList

        -- Column headers
        local hName = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hName:SetPoint("TOPLEFT", p, 10, -10)
        hName:SetText("|cffffcc00Player|r")

        local hTick = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hTick:SetPoint("TOPLEFT", p, 210, -10)
        hTick:SetText("|cffffcc00Tickets|r")

        local hNums = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hNums:SetPoint("TOPLEFT", p, 295, -10)
        hNums:SetText("|cffffcc00Number(s)|r")

        -- Summary line
        local header = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", p, 10, -28)
        GL.participantHeader = header

        local scrollFrame = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", p, 0, -50)
        scrollFrame:SetPoint("BOTTOMRIGHT", p, -20, 38)

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(500, 1)
        scrollFrame:SetScrollChild(content)
        GL.listContent = content

        local btnRemove = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        btnRemove:SetSize(140, 26)
        btnRemove:SetPoint("BOTTOMLEFT", p, 10, 6)
        btnRemove:SetText("Remove Selected")
        btnRemove:SetScript("OnClick", function()
            if GL.selectedParticipant then
                GL:RemoveParticipant(GL.selectedParticipant)
                GL.selectedParticipant = nil
                GL:RefreshParticipantList()
                RefreshPrizeSummary()
                if GL.RefreshGuildSuggestions then GL.RefreshGuildSuggestions("") end
            end
        end)
    end

    -- --------------------------------------------------------
    -- TAB: CONTROLS
    -- --------------------------------------------------------
    do
        local p = panelControl
        local y = -15

        -- Prize summary box at the top of controls
        local boxBg = p:CreateTexture(nil, "BACKGROUND")
        boxBg:SetColorTexture(0, 0, 0, 0.4)
        boxBg:SetPoint("TOPLEFT", p, 8, y)
        boxBg:SetPoint("TOPRIGHT", p, -8, y)
        boxBg:SetHeight(46)

        local lPrizeTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lPrizeTitle:SetPoint("TOPLEFT", p, 14, y - 4)
        lPrizeTitle:SetText("|cffffcc00Prize Pool (live)|r")

        local prizeSummary = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        prizeSummary:SetPoint("TOPLEFT", p, 14, y - 22)
        prizeSummary:SetWidth(510)
        GL.prizeSummary = prizeSummary
        RefreshPrizeSummary()

        y = y - 60

        local function BigButton(label, yOff, onclick)
            local btn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
            btn:SetSize(320, 40)
            btn:SetPoint("TOPLEFT", p, 90, yOff)
            btn:SetText(label)
            btn:SetScript("OnClick", onclick)
            return btn
        end

        BigButton("Announce Game Started", y, function() GL:AnnounceStart() end)
        y = y - 55

        BigButton("Announce Rules & Settings", y, function() GL:AnnounceRules() end)
        y = y - 55

        BigButton("Roll for Winner!", y, function()
            local winner, roll = GL:RollWinner()
            if winner then
                local pot, guildCut, winnerCut = CalcPrize()
                GL.lastWinner:SetText(
                    ("Last winner: |cffFFD700%s|r  (roll #%d)  |cff00ff00+%dg|r"):format(winner, roll, winnerCut)
                )
            end
        end)
        y = y - 55

        local lw = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lw:SetPoint("TOPLEFT", p, 10, y)
        lw:SetText("No winner yet.")
        GL.lastWinner = lw
        y = y - 45

        BigButton("Reset Lottery", y, function()
            GL:Reset()
            GL.lastWinner:SetText("No winner yet.")
            RefreshPrizeSummary()
            if GL.RefreshGuildSuggestions then GL.RefreshGuildSuggestions("") end
        end)

        -- Refresh summary whenever this tab is shown
        p:SetScript("OnShow", RefreshPrizeSummary)
    end

    -- --------------------------------------------------------
    -- TAB: SETTINGS
    -- --------------------------------------------------------
    do
        local p = panelSettings
        local y = -15

        local function SectionLabel(text, yOff)
            local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("TOPLEFT", p, 10, yOff)
            lbl:SetText("|cffffcc00" .. text .. "|r")
        end

        local function LabeledInput(label, yOff, default, width, onchanged)
            local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("TOPLEFT", p, 10, yOff)
            lbl:SetText(label)
            local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
            eb:SetSize(width or 130, 22)
            eb:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
            eb:SetAutoFocus(false)
            eb:SetText(tostring(default))
            eb:SetScript("OnEnterPressed", function(self)
                self:ClearFocus(); onchanged(self:GetText())
            end)
            eb:SetScript("OnEditFocusLost", function(self) onchanged(self:GetText()) end)
            return eb
        end

        -- ---- Ticket settings ----
        SectionLabel("Ticket Settings", y)
        y = y - 22

        LabeledInput("Ticket Price (label):", y, GL.settings.ticketPrice, 100,
            function(v)
                GL.settings.ticketPrice = v; RefreshPrizeSummary()
            end)
        y = y - 36

        LabeledInput("Ticket Price (gold value):", y, GL.settings.ticketPriceValue, 80,
            function(v)
                GL.settings.ticketPriceValue = tonumber(v) or 0
                RefreshPrizeSummary()
            end)
        y = y - 36

        LabeledInput("Min Tickets:", y, GL.settings.minTickets, 60,
            function(v) GL.settings.minTickets = tonumber(v) or 1 end)
        y = y - 36

        LabeledInput("Max Tickets:", y, GL.settings.maxTickets, 60,
            function(v) GL.settings.maxTickets = tonumber(v) or 10 end)
        y = y - 44

        -- ---- Guild Cut ----
        SectionLabel("Guild Cut", y)
        y = y - 22

        -- Description
        local lCutDesc = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lCutDesc:SetPoint("TOPLEFT", p, 10, y)
        lCutDesc:SetText("|cffaaaaaa% of the total pot that goes to the guild bank. Remainder goes to the winner.|r")
        lCutDesc:SetWidth(490)
        y = y - 24

        -- [ − ]  [====slider====]  [ + ]   value label
        local btnMinus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        btnMinus:SetSize(28, 22)
        btnMinus:SetPoint("TOPLEFT", p, 10, y)
        btnMinus:SetText("-")

        local slider = CreateFrame("Slider", "GuildLotteryCutSlider", p, "OptionsSliderTemplate")
        slider:SetPoint("LEFT", btnMinus, "RIGHT", 4, 0)
        slider:SetWidth(340)
        slider:SetMinMaxValues(0, 100)
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        slider:SetValue(GL.settings.guildCutPct)
        -- Hide default min/max labels
        _G[slider:GetName() .. "Low"]:SetText("0%")
        _G[slider:GetName() .. "High"]:SetText("100%")
        _G[slider:GetName() .. "Text"]:SetText("")

        local btnPlus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        btnPlus:SetSize(28, 22)
        btnPlus:SetPoint("LEFT", slider, "RIGHT", 4, 0)
        btnPlus:SetText("+")

        local lCutVal = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lCutVal:SetPoint("LEFT", btnPlus, "RIGHT", 10, 0)
        lCutVal:SetWidth(50)

        -- Live preview line below slider
        y = y - 44
        local lCutPreview = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lCutPreview:SetPoint("TOPLEFT", p, 10, y)
        lCutPreview:SetWidth(500)

        local function UpdateCut(val)
            val = math.max(0, math.min(100, math.floor(val + 0.5)))
            GL.settings.guildCutPct = val
            slider:SetValue(val)
            lCutVal:SetText(val .. "%")
            -- preview
            local pot, guildCut, winnerCut = CalcPrize()
            lCutPreview:SetText(
                ("Preview -- pot: |cffFFD700%dg|r  ->  " ..
                    "Winner: |cff00ff00%dg|r (%d%%)   " ..
                    "Guild: |cffff9900%dg|r (%d%%)"):format(
                    pot, winnerCut, 100 - val, guildCut, val
                )
            )
            RefreshPrizeSummary()
        end

        slider:SetScript("OnValueChanged", function(self, v) UpdateCut(v) end)
        btnMinus:SetScript("OnClick", function() UpdateCut(GL.settings.guildCutPct - 1) end)
        btnPlus:SetScript("OnClick", function() UpdateCut(GL.settings.guildCutPct + 1) end)
        -- init display
        p:SetScript("OnShow", function() UpdateCut(GL.settings.guildCutPct) end)
        y = y - 44

        -- ---- Chat channel ----
        SectionLabel("Chat Channel", y)
        y = y - 24

        local lCh = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lCh:SetPoint("TOPLEFT", p, 10, y)
        lCh:SetText("Send messages to:")

        local channels = { "GUILD", "RAID", "PARTY", "SAY", "YELL" }
        local dd = CreateFrame("Button", nil, p, "UIDropDownMenuTemplate")
        dd:SetPoint("LEFT", lCh, "RIGHT", -10, 0)
        UIDropDownMenu_SetWidth(dd, 120)
        UIDropDownMenu_SetText(dd, GL.settings.chatChannel)
        UIDropDownMenu_Initialize(dd, function(self)
            for _, ch in ipairs(channels) do
                local info = UIDropDownMenu_CreateInfo()
                info.text  = ch
                info.func  = function()
                    GL.settings.chatChannel = ch
                    UIDropDownMenu_SetText(dd, ch)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        y = y - 50

        local note = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        note:SetPoint("TOPLEFT", p, 10, y)
        note:SetText("|cff888888Tip: Edit the MSG table in GuildLottery.lua to customise all chat messages.|r")
        note:SetWidth(490)
        note:SetWordWrap(true)
    end

    ShowPanel(panelAdd)
    f:Show()
end

-- ============================================================
-- REFRESH PARTICIPANT LIST
-- ============================================================
function GL:RefreshParticipantList()
    local content = GL.listContent
    if not content then return end

    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide(); child:SetParent(nil)
    end

    local ROW_H = 24
    local row   = 0

    for _, entry in ipairs(GL.participants) do
        local rowFrame = CreateFrame("Button", nil, content)
        rowFrame:SetSize(500, ROW_H)
        rowFrame:SetPoint("TOPLEFT", content, 0, -row * (ROW_H + 2))

        if entry.removed then
            -- Dimmed row for removed players — their slots are still reserved
            local txt = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            txt:SetPoint("LEFT", rowFrame, 4, 0)
            txt:SetText(
                "|cff555555" .. entry.name ..
                "   " .. entry.tickets .. " ticket(s)" ..
                "   #" .. TicketRange(entry) ..
                "   [removed]|r"
            )
        else
            rowFrame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

            local tName = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tName:SetPoint("LEFT", rowFrame, 4, 0)
            tName:SetWidth(195)
            tName:SetText(entry.name)

            local tCount = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tCount:SetPoint("LEFT", rowFrame, 210, 0)
            tCount:SetWidth(75)
            tCount:SetText("|cff88ccff" .. entry.tickets .. " ticket(s)|r")

            local tNums = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tNums:SetPoint("LEFT", rowFrame, 295, 0)
            tNums:SetWidth(200)
            tNums:SetText("|cffFFD700#" .. TicketRange(entry) .. "|r")

            local name = entry.name
            rowFrame:SetScript("OnClick", function()
                GL.selectedParticipant = name
                tName:SetText("|cffFFFFFF>> " .. name .. "|r")
            end)
        end

        row = row + 1
    end
    content:SetHeight(math.max(1, row * (ROW_H + 2)))

    local count, total = ActiveStats()
    if GL.participantHeader then
        GL.participantHeader:SetText(
            ("Active: |cffFFD700%d|r players   Total: |cff88ccff%d|r tickets   Pool: |cffaaaaaa1-%d|r"):format(
                count, total, MaxTicket()
            )
        )
    end
end

-- ============================================================
-- SLASH COMMAND  /lottery  or  /gl
-- ============================================================
SLASH_GUILDLOTTERY1 = "/lottery"
SLASH_GUILDLOTTERY2 = "/gl"
SlashCmdList["GUILDLOTTERY"] = function() GL:CreateGUI() end

-- ============================================================
-- MINIMAP BUTTON
-- ============================================================
-- MINIMAP BUTTON  (draggable, angle-based, circular icon)
-- ============================================================
-- local minimapAngle = 225 -- starting angle in degrees (bottom-left)

-- local minimapBtn = CreateFrame("Button", "GuildLotteryMinimapBtn", Minimap)
-- minimapBtn:SetSize(31, 31)
-- minimapBtn:SetFrameStrata("MEDIUM")
-- minimapBtn:SetClampedToScreen(false)

-- -- Circular mask so the icon doesn't bleed outside the round button
-- local mask = minimapBtn:CreateMaskTexture()
-- mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
-- --mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask") -- Blizzard's default circle mask
-- mask:SetAllPoints(minimapBtn)


-- -- Add the background circle texture
-- local back = minimapBtn:CreateTexture(nil, "BACKGROUND")
-- back:SetSize(25, 25)
-- back:SetPoint("TOPLEFT", 3, -3)
-- back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

-- -- Icon texture, clipped by the mask
-- local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
-- --icon:SetTexture("Interface\\Icons\\inv_misc_dice_01")
-- icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Bloodstone_01") -- Path to your image
-- icon:SetAllPoints(minimapBtn)
-- icon:SetSize(25, 25)
-- icon:SetPoint("CENTER", 0, 0)
-- icon:AddMaskTexture(mask)

-- -- Circular border overlay (the ring that appears around minimap buttons)
-- local border = minimapBtn:CreateTexture(nil, "OVERLAY")
-- border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
-- border:SetSize(53, 53)
-- border:SetPoint("TOPLEFT", 0, 0)

-- -- Position the button on the minimap edge at a given angle
-- local function UpdateMinimapPos()
--     local rad    = math.rad(minimapAngle)
--     local radius = 80 -- distance from minimap center to button center
--     minimapBtn:ClearAllPoints()
--     minimapBtn:SetPoint(
--         "CENTER", Minimap, "CENTER",
--         math.cos(rad) * radius,
--         math.sin(rad) * radius
--     )
-- end
-- UpdateMinimapPos()

-- -- Drag to orbit around the minimap
-- minimapBtn:RegisterForDrag("LeftButton")
-- minimapBtn:SetScript("OnDragStart", function(self)
--     self:SetScript("OnUpdate", function()
--         local mx, my = Minimap:GetCenter()
--         local cx, cy = GetCursorPosition()
--         local scale  = Minimap:GetEffectiveScale()
--         cx           = cx / scale
--         cy           = cy / scale
--         minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
--         UpdateMinimapPos()
--     end)
-- end)
-- minimapBtn:SetScript("OnDragStop", function(self)
--     self:SetScript("OnUpdate", nil)
-- end)

-- minimapBtn:SetScript("OnClick", function()
--     if GL.frame and GL.frame:IsShown() then
--         GL.frame:Hide()
--     else
--         GL:CreateGUI()
--     end
-- end)
-- minimapBtn:SetScript("OnEnter", function(self)
--     GameTooltip:SetOwner(self, "ANCHOR_LEFT")
--     GameTooltip:SetText("Guild Lottery")
--     GameTooltip:AddLine("/lottery or /gl to open", 1, 1, 1)
--     GameTooltip:Show()
-- end)
-- minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

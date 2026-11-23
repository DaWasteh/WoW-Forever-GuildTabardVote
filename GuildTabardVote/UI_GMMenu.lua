local _, GTV = ...

local UI_GMMenu = {}
GTV.UI_GMMenu = UI_GMMenu

local frame
local rowPool = {}

local function ColorBtnText(btn, r, g, b)
    if btn.GetFontString and btn:GetFontString() then
        btn:GetFontString():SetTextColor(r, g, b)
    end
end

local function AcquireRow(index)
    local row = rowPool[index]
    if row then
        return row
    end

    row = GTV:CreateBackdropFrame(frame.scrollChild, nil, {
        bgColor = { 0.09, 0.10, 0.16, 0.94 },
        borderColor = { 0.48, 0.40, 0.22, 0.88 },
        edgeSize = 10,
    })
    row:SetSize(506, 86)

    -- Rank badge (#1, #2, ...)
    row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.rankText:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.rankText:SetWidth(30)
    row.rankText:SetJustifyH("CENTER")

    -- 2D Tabard Thumbnail
    row.thumb = GTV.TabardSync:Create2DPreview(row, 50, 62)
    row.thumb:SetPoint("LEFT", row.rankText, "RIGHT", 6, 0)

    -- Author & Note
    row.titleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.titleText:SetPoint("TOPLEFT", row.thumb, "TOPRIGHT", 10, 0)
    row.titleText:SetWidth(270)
    row.titleText:SetJustifyH("LEFT")

    row.noteText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.noteText:SetPoint("TOPLEFT", row.titleText, "BOTTOMLEFT", 0, -2)
    row.noteText:SetWidth(270)
    row.noteText:SetJustifyH("LEFT")
    row.noteText:SetTextColor(0.82, 0.86, 0.94)

    -- Big visual Green / Red Split Vote Bar per design
    row.barBg = row:CreateTexture(nil, "BACKGROUND")
    row.barBg:SetSize(256, 12)
    row.barBg:SetPoint("TOPLEFT", row.noteText, "BOTTOMLEFT", 0, -6)
    row.barBg:SetColorTexture(0.17, 0.18, 0.24, 1.0)

    row.barUp = row:CreateTexture(nil, "ARTWORK")
    row.barUp:SetHeight(12)
    row.barUp:SetPoint("LEFT", row.barBg, "LEFT", 0, 0)
    row.barUp:SetColorTexture(0.18, 0.80, 0.36, 1.0)
    row.barUp:Hide()

    row.barDown = row:CreateTexture(nil, "ARTWORK")
    row.barDown:SetHeight(12)
    row.barDown:SetPoint("RIGHT", row.barBg, "RIGHT", 0, 0)
    row.barDown:SetColorTexture(0.86, 0.24, 0.24, 1.0)
    row.barDown:Hide()

    -- Crisp anonymous numbers right below bar
    row.statsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.statsText:SetPoint("TOPLEFT", row.barBg, "BOTTOMLEFT", 0, -4)
    row.statsText:SetWidth(280)
    row.statsText:SetJustifyH("LEFT")

    -- Right-side action buttons (View 3D / Apply / Save / Delete)
    row.viewBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.viewBtn:SetSize(112, 22)
    row.viewBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -34, -10)
    row.viewBtn:SetText(GTV.L.BTN_PREVIEW)

    row.applyBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.applyBtn:SetSize(112, 22)
    row.applyBtn:SetPoint("TOP", row.viewBtn, "BOTTOM", 0, -4)
    row.applyBtn:SetText(GTV.L.BTN_APPLY)
    ColorBtnText(row.applyBtn, 1.0, 0.88, 0.35)

    row.saveBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.saveBtn:SetSize(112, 20)
    row.saveBtn:SetPoint("TOP", row.applyBtn, "BOTTOM", 0, -4)
    row.saveBtn:SetText(GTV.L.BTN_SAVE)

    row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.delBtn:SetSize(22, 22)
    row.delBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -10)
    row.delBtn:SetText(GTV.L.BTN_DELETE)
    ColorBtnText(row.delBtn, 1.0, 0.45, 0.45)

    rowPool[index] = row
    return row
end

local function EnsureFrame()
    if frame then
        return frame
    end

    local f = GTV:CreateBackdropFrame(UIParent, "GuildTabardVoteGMMenu", {
        bgColor = { 0.05, 0.06, 0.10, 0.97 },
        borderColor = { 0.92, 0.74, 0.26, 1.0 },
    })
    f:SetSize(564, 530)
    f:SetPoint("CENTER", UIParent, "CENTER", -120, 0)
    f:SetFrameStrata("HIGH")
    f:Hide()
    GTV:AttachDrag(f)

    if UISpecialFrames then
        table.insert(UISpecialFrames, "GuildTabardVoteGMMenu")
    end

    -- Header
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    icon:SetTexture(GTV.ICON_ADDON)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 4)
    title:SetText(GTV.L.GM_MENU_TITLE)
    title:SetTextColor(1.0, 0.84, 0.28)

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText(GTV.L.GM_MENU_SUBTITLE)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)

    -- KPI Summary Card + Sync Button
    local kpiCard = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.08, 0.10, 0.16, 0.94 },
        borderColor = { 0.55, 0.46, 0.24, 0.9 },
        edgeSize = 10,
    })
    kpiCard:SetSize(536, 62)
    kpiCard:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -50)

    local kpiText = kpiCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    kpiText:SetPoint("TOPLEFT", kpiCard, "TOPLEFT", 12, -10)
    f.kpiText = kpiText

    local pollStatusText = kpiCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pollStatusText:SetPoint("BOTTOMLEFT", kpiCard, "BOTTOMLEFT", 12, 10)
    pollStatusText:SetTextColor(0.75, 0.85, 1.0)
    f.pollStatusText = pollStatusText

    local syncBtn = CreateFrame("Button", nil, kpiCard, "UIPanelButtonTemplate")
    syncBtn:SetSize(134, 24)
    syncBtn:SetPoint("TOPRIGHT", kpiCard, "TOPRIGHT", -10, -8)
    syncBtn:SetText(GTV.L.GM_MENU_SYNC_BTN)
    ColorBtnText(syncBtn, 0.40, 1.0, 0.50)
    syncBtn:SetScript("OnClick", function()
        GTV:PlaySound("IG_MAINMENU_OPTION", 852)
        GTV.Protocol:RequestGuildVoteSync()
        GTV:Print(GTV.L.GM_MENU_SYNC_SENT)
        UI_GMMenu:Refresh()
    end)

    local syncCountText = kpiCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    syncCountText:SetPoint("BOTTOMRIGHT", kpiCard, "BOTTOMRIGHT", -12, 10)
    f.syncCountText = syncCountText

    -- Ranked Scroll List
    local listBox = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.04, 0.05, 0.08, 0.90 },
        borderColor = { 0.40, 0.35, 0.22, 0.85 },
    })
    listBox:SetPoint("TOPLEFT", kpiCard, "BOTTOMLEFT", 0, -8)
    listBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 48)

    local scroll = CreateFrame("ScrollFrame", "GTVGMMenuScroll", listBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listBox, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -26, 6)

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(510, 340)
    scroll:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild

    local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -32)
    emptyText:SetWidth(460)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetText(GTV.L.GM_MENU_EMPTY)
    f.emptyText = emptyText

    -- Bottom GM Quick Action Bar
    local openLiveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    openLiveBtn:SetSize(166, 26)
    openLiveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    openLiveBtn:SetText(GTV.L.GM_MENU_OPEN_LIVE_BTN)
    openLiveBtn:SetScript("OnClick", function()
        GTV:PlaySound("IG_MAINMENU_OPTION", 852)
        if GTV.UI_LeaderPanel then
            GTV.UI_LeaderPanel:ShowStandalone(GTV.Protocol:IsTestModeActive())
        end
    end)

    local announceBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    announceBtn:SetSize(166, 26)
    announceBtn:SetPoint("LEFT", openLiveBtn, "RIGHT", 10, 0)
    announceBtn:SetText(GTV.L.TIMED_ANNOUNCE_BTN)
    ColorBtnText(announceBtn, 1.0, 0.88, 0.35)
    announceBtn:SetScript("OnClick", function()
        GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
        GTV.Protocol:AnnounceTimedPollWinner()
    end)

    local resetBoardBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBoardBtn:SetSize(166, 26)
    resetBoardBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
    resetBoardBtn:SetText(GTV.L.GM_MENU_RESET_BOARD_BTN)
    ColorBtnText(resetBoardBtn, 1.0, 0.50, 0.50)
    resetBoardBtn:SetScript("OnClick", function()
        GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
        GTV.Protocol:ResetBoardVotes()
    end)

    frame = f
    return f
end

function UI_GMMenu:Refresh()
    if not frame or not frame:IsShown() then
        return
    end
    if not GTV:CanSeeLeaderVotes() then
        frame:Hide()
        return
    end

    local dCount, voters, abstained = GTV.Protocol:GetBoardStats()
    frame.kpiText:SetText(string.format(GTV.L.GM_MENU_KPI, dCount, voters, abstained))
    frame.syncCountText:SetText(string.format(GTV.L.GM_MENU_SYNC_COUNT, GTV.Protocol.syncResponseCount or 0))

    local poll = GTV.Protocol:GetActiveTimedPoll()
    if poll then
        local rem, expired = GTV.Storage:FormatRemaining(poll.endsAt)
        if poll.status == "CLOSED" then
            frame.pollStatusText:SetText((poll.title or GTV.L.TIMED_TITLE_DEFAULT) .. " — " .. GTV.L.TIMED_CLOSED)
        elseif expired then
            frame.pollStatusText:SetText((poll.title or GTV.L.TIMED_TITLE_DEFAULT) .. " — " .. GTV.L.TIMED_EXPIRED)
        else
            frame.pollStatusText:SetText((poll.title or GTV.L.TIMED_TITLE_DEFAULT) .. " — " .. string.format(GTV.L.TIMED_REMAINING, rem))
        end
    else
        local gName = GTV:GetGuildName() or "Test"
        frame.pollStatusText:SetText(string.format(GTV.L.STATUS_GUILD_BOARD, gName))
    end

    for _, row in ipairs(rowPool) do
        row:Hide()
    end

    local designs = GTV.Protocol:GetGuildDesigns()
    if #designs == 0 then
        frame.emptyText:Show()
        frame.scrollChild:SetHeight(140)
        return
    end
    frame.emptyText:Hide()

    local ranked = {}
    for idx, d in ipairs(designs) do
        local up, down = GTV.Protocol:GetDesignVotes(d.id)
        table.insert(ranked, { entry = d, idx = idx, up = up, down = down, score = up - down, total = up + down })
    end
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.up ~= b.up then return a.up > b.up end
        return a.idx < b.idx
    end)

    local y = -4
    for i, item in ipairs(ranked) do
        local d = item.entry
        local row = AcquireRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollChild, "TOPLEFT", 2, y)

        local isTop = (i == 1 and item.total > 0) or (poll and poll.winnerDesignId == d.id)
        if isTop then
            row:SetBackdropBorderColor(0.98, 0.82, 0.22, 1.0)
            row.rankText:SetTextColor(1.0, 0.84, 0.25)
        elseif i == 2 then
            row:SetBackdropBorderColor(0.68, 0.72, 0.80, 0.90)
            row.rankText:SetTextColor(0.82, 0.86, 0.92)
        elseif i == 3 then
            row:SetBackdropBorderColor(0.76, 0.50, 0.28, 0.90)
            row.rankText:SetTextColor(0.86, 0.58, 0.34)
        else
            row:SetBackdropBorderColor(0.42, 0.36, 0.22, 0.82)
            row.rankText:SetTextColor(0.72, 0.74, 0.80)
        end

        row.rankText:SetText(string.format(GTV.L.GM_MENU_RANK_FMT, i))
        row.thumb:SetDesign(d.design)
        local prefix = (poll and poll.winnerDesignId == d.id) and GTV.L.TIMED_WINNER_TAG or ""
        row.titleText:SetText(prefix .. d.authorName)
        row.noteText:SetText(d.note ~= "" and ("\"" .. d.note .. "\"") or "")

        local sign = item.score > 0 and "+" or ""
        row.statsText:SetText(string.format(GTV.L.GM_MENU_ROW_STATS, item.up, item.down, sign, item.score, item.total))

        local barW = 256
        if item.total > 0 then
            local upW = math.floor((item.up / item.total) * barW + 0.5)
            local downW = barW - upW
            if upW > 0 then row.barUp:SetWidth(upW); row.barUp:Show() else row.barUp:Hide() end
            if downW > 0 then row.barDown:SetWidth(downW); row.barDown:Show() else row.barDown:Hide() end
        else
            row.barUp:Hide()
            row.barDown:Hide()
        end

        row.viewBtn:SetScript("OnClick", function()
            GTV:PlaySound("IG_MAINMENU_OPTION", 852)
            if GTV.UI_MemberWindow then
                GTV.UI_MemberWindow:OpenAndPreviewDesign(d)
            end
        end)
        row.applyBtn:SetScript("OnClick", function()
            GTV:PlaySound("IG_MAINMENU_OPTION", 852)
            if not GTV.Protocol:ApplyDesignToLeaderModel(d.design) then
                if GTV.UI_LeaderPanel then
                    GTV.UI_LeaderPanel:ShowStandalone(GTV.Protocol:IsTestModeActive())
                    C_Timer.After(0.15, function()
                        GTV.Protocol:ApplyDesignToLeaderModel(d.design)
                    end)
                end
            end
        end)
        row.saveBtn:SetScript("OnClick", function()
            local label = (d.note ~= "" and d.note) or d.authorName
            GTV.Storage:SaveDesign(label, d.design)
            GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
        end)
        row.delBtn:SetScript("OnClick", function()
            GTV.Protocol:DeleteGuildDesign(d.id)
            GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
        end)

        row:Show()
        y = y - 90
    end
    frame.scrollChild:SetHeight(math.max(160, -y + 10))
end

function UI_GMMenu:Open()
    if not GTV:CanSeeLeaderVotes() then
        GTV:Print(GTV.L.GM_ONLY_ERROR)
        return
    end
    local f = EnsureFrame()
    f:Show()
    GTV.Protocol:RequestGuildVoteSync()
    self:Refresh()
    GTV:PlaySound("IG_MAINMENU_OPEN", 850)
end

function UI_GMMenu:IsShown()
    return frame and frame:IsShown() or false
end

function UI_GMMenu:Hide()
    if frame then
        frame:Hide()
    end
end

GTV.Protocol:RegisterCallback(function()
    if frame and frame:IsShown() then
        UI_GMMenu:Refresh()
    end
end)

local _, GTV = ...

local UI_LeaderPanel = {}
GTV.UI_LeaderPanel = UI_LeaderPanel

local panel
local dockedToVendor = false
local isStandaloneMode = false
local leaderTab = "LIVE" -- "LIVE" | "TIMED" | "SAVED"
local forceCreateTimedView = false
local customDurationSeconds = 3 * 86400

local liveDesignRows = {}
local timedDesignRows = {}
local savedRows = {}

-- Strictly anonymous tooltip (Guild Master ONLY — ZERO player names!)
local function ShowAnonymousVoteTooltip(owner)
    if not GameTooltip then
        return
    end
    local up, down, abstain, active = GTV.Protocol:GetVoteCounts()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(GTV.L.TOOLTIP_VOTES_TITLE, 1.0, 0.84, 0.30)
    GameTooltip:AddLine(string.format(GTV.L.VOTE_PARTICIPANTS, active), 0.9, 0.9, 0.9)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(GTV.L.TOOLTIP_UP .. " " .. tostring(up), 0.28, 0.95, 0.42)
    GameTooltip:AddLine(GTV.L.TOOLTIP_DOWN .. " " .. tostring(down), 1.0, 0.36, 0.36)
    GameTooltip:AddLine(GTV.L.TOOLTIP_ABSTAIN .. " " .. tostring(abstain), 0.70, 0.70, 0.70)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(GTV.L.TOOLTIP_ANON_FOOTER, 0.65, 0.78, 0.95, true)
    GameTooltip:Show()
end

local function CreateCustomRow(parent, yOffset, varIndex, labelText, onStep)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(202, 24)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("CENTER", row, "CENTER", 0, 0)
    lbl:SetWidth(124)
    lbl:SetJustifyH("CENTER")
    lbl:SetText(labelText)

    local leftBtn = CreateFrame("Button", nil, row)
    leftBtn:SetSize(26, 26)
    leftBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
    leftBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    leftBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    leftBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    leftBtn:SetScript("OnClick", function()
        GTV:PlaySound("GS_CHARACTER_CREATION_LOOK", 823)
        onStep(varIndex, -1)
    end)

    local rightBtn = CreateFrame("Button", nil, row)
    rightBtn:SetSize(26, 26)
    rightBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    rightBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    rightBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    rightBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    rightBtn:SetScript("OnClick", function()
        GTV:PlaySound("GS_CHARACTER_CREATION_LOOK", 823)
        onStep(varIndex, 1)
    end)

    return row
end

local function StyleLeaderTab(btn, selected)
    if selected then
        btn:LockHighlight()
        if btn.GetFontString and btn:GetFontString() then
            btn:GetFontString():SetTextColor(1.0, 0.88, 0.35)
        end
    else
        btn:UnlockHighlight()
        if btn.GetFontString and btn:GetFontString() then
            btn:GetFontString():SetTextColor(0.82, 0.82, 0.82)
        end
    end
end

function UI_LeaderPanel:GetActiveModel()
    if dockedToVendor and TabardFrame and TabardFrame:IsShown() and TabardModel then
        return TabardModel
    end
    if panel and panel.standaloneModel then
        return panel.standaloneModel
    end
    return TabardModel
end

local function ReadLeaderCurrentDesign()
    local model = UI_LeaderPanel:GetActiveModel()
    if model and model.EnsureReady then
        model:EnsureReady()
    end
    return GTV.TabardSync:ReadModel(model)
end

local function SetLeaderTab(tabName)
    leaderTab = tabName
    if not panel then
        return
    end
    StyleLeaderTab(panel.tabLive, leaderTab == "LIVE")
    StyleLeaderTab(panel.tabTimed, leaderTab == "TIMED")
    StyleLeaderTab(panel.tabSaved, leaderTab == "SAVED")

    panel.livePane:SetShown(leaderTab == "LIVE")
    panel.timedPane:SetShown(leaderTab == "TIMED")
    panel.savedPane:SetShown(leaderTab == "SAVED")
    UI_LeaderPanel:Refresh()
end

local function EnsurePanel()
    if panel then
        return panel
    end

    local f = GTV:CreateBackdropFrame(UIParent, "GuildTabardVoteLeaderPanel", {
        bgColor = { 0.06, 0.07, 0.11, 0.96 },
        borderColor = { 0.80, 0.65, 0.28, 0.95 },
    })
    f:SetSize(316, 474)
    f:SetFrameStrata("HIGH")
    f:Hide()
    GTV:AttachDrag(f)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    icon:SetTexture(GTV.ICON_ADDON)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(GTV.L.LEADER_PANEL_TITLE)
    title:SetTextColor(1.0, 0.84, 0.30)
    f.title = title

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        if isStandaloneMode and GTV.Protocol:IsLeading() then
            GTV.Protocol:EndLeaderSession(false)
        end
        f:Hide()
    end)

    local elapsedAcc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        elapsedAcc = elapsedAcc + elapsed
        if elapsedAcc >= 15 then
            elapsedAcc = 0
            if leaderTab == "TIMED" then
                UI_LeaderPanel:Refresh()
            end
        end
    end)

    -- Standalone Designer sub-pane (hidden when docked to Blizzard TabardFrame)
    local designerPane = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.04, 0.05, 0.08, 0.92 },
        borderColor = { 0.45, 0.38, 0.22, 0.82 },
    })
    designerPane:SetSize(222, 422)
    designerPane:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -40)
    designerPane:Hide()
    f.designerPane = designerPane

    local model = GTV.TabardSync:Create3DModel(designerPane, 206, 232)
    model:SetPoint("TOP", designerPane, "TOP", 0, -8)
    f.standaloneModel = model

    local function onStandaloneStep(varIndex, delta)
        model:EnsureReady()
        model:CycleVariation(varIndex, delta)
        GTV.Protocol:OnLeaderModelChanged(model, varIndex, delta)
    end

    local labels = { GTV.L.CUST_1, GTV.L.CUST_2, GTV.L.CUST_3, GTV.L.CUST_4, GTV.L.CUST_5 }
    for i = 1, 5 do
        CreateCustomRow(designerPane, -246 - (i - 1) * 26, i, labels[i], onStandaloneStep)
    end

    local standaloneHint = designerPane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    standaloneHint:SetPoint("BOTTOMLEFT", designerPane, "BOTTOMLEFT", 8, 8)
    standaloneHint:SetPoint("BOTTOMRIGHT", designerPane, "BOTTOMRIGHT", -8, 8)
    standaloneHint:SetJustifyH("CENTER")
    standaloneHint:SetText(GTV.L.LEADER_STANDALONE_NOTE)

    -- Right/Main Control Column
    local rightCol = CreateFrame("Frame", nil, f)
    rightCol:SetSize(292, 422)
    rightCol:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -40)
    f.rightCol = rightCol

    local tabLive = CreateFrame("Button", nil, rightCol, "UIPanelButtonTemplate")
    tabLive:SetSize(84, 24)
    tabLive:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
    tabLive:SetText(GTV.L.LEADER_TAB_LIVE)
    tabLive:SetScript("OnClick", function()
        GTV:PlaySound("IG_CHARACTER_INFO_TAB", 841)
        SetLeaderTab("LIVE")
    end)
    f.tabLive = tabLive

    local tabTimed = CreateFrame("Button", nil, rightCol, "UIPanelButtonTemplate")
    tabTimed:SetSize(100, 24)
    tabTimed:SetPoint("LEFT", tabLive, "RIGHT", 4, 0)
    tabTimed:SetText(GTV.L.LEADER_TAB_TIMED)
    tabTimed:SetScript("OnClick", function()
        GTV:PlaySound("IG_CHARACTER_INFO_TAB", 841)
        SetLeaderTab("TIMED")
    end)
    f.tabTimed = tabTimed

    local tabSaved = CreateFrame("Button", nil, rightCol, "UIPanelButtonTemplate")
    tabSaved:SetSize(100, 24)
    tabSaved:SetPoint("LEFT", tabTimed, "RIGHT", 4, 0)
    tabSaved:SetText(GTV.L.LEADER_TAB_SAVED)
    tabSaved:SetScript("OnClick", function()
        GTV:PlaySound("IG_CHARACTER_INFO_TAB", 841)
        SetLeaderTab("SAVED")
    end)
    f.tabSaved = tabSaved

    -- =====================================================================
    -- PANE 1: LIVE SESSION + UNIFIED GUILD DESIGNS (ANONYMOUS GM RESULTS)
    -- =====================================================================
    local livePane = CreateFrame("Frame", nil, rightCol)
    livePane:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -30)
    livePane:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
    f.livePane = livePane

    local liveToggleBtn = CreateFrame("Button", nil, livePane, "UIPanelButtonTemplate")
    liveToggleBtn:SetSize(156, 24)
    liveToggleBtn:SetPoint("TOPLEFT", livePane, "TOPLEFT", 0, 0)
    liveToggleBtn:SetScript("OnClick", function()
        if GTV.Protocol:IsLeading() then
            GTV.Protocol:EndLeaderSession(false)
        else
            local targetModel = UI_LeaderPanel:GetActiveModel()
            if targetModel and targetModel.EnsureReady then
                targetModel:EnsureReady()
            end
            GTV.Protocol:StartLeaderSession(targetModel, not dockedToVendor, GTV.Protocol:IsTestModeActive())
        end
        UI_LeaderPanel:Refresh()
    end)
    f.liveToggleBtn = liveToggleBtn

    local reinviteBtn = CreateFrame("Button", nil, livePane, "UIPanelButtonTemplate")
    reinviteBtn:SetSize(128, 24)
    reinviteBtn:SetPoint("TOPRIGHT", livePane, "TOPRIGHT", 0, 0)
    reinviteBtn:SetText(GTV.L.LEADER_REINVITE_BTN)
    reinviteBtn:SetScript("OnClick", function()
        GTV.Protocol:ReinviteGuild()
        GTV:PlaySound("IG_MAINMENU_OPTION", 852)
    end)
    f.reinviteBtn = reinviteBtn

    local voteCard = GTV:CreateBackdropFrame(livePane, nil, {
        bgColor = { 0.09, 0.10, 0.15, 0.92 },
        borderColor = { 0.45, 0.40, 0.25, 0.85 },
    })
    voteCard:SetSize(292, 96)
    voteCard:SetPoint("TOPLEFT", liveToggleBtn, "BOTTOMLEFT", 0, -8)
    voteCard:EnableMouse(true)
    voteCard:SetScript("OnEnter", function(self) ShowAnonymousVoteTooltip(self) end)
    voteCard:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local anonHint = voteCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    anonHint:SetPoint("TOPLEFT", voteCard, "TOPLEFT", 10, -6)
    anonHint:SetText(GTV.L.VOTE_GM_ANON_HINT)

    local upIcon = voteCard:CreateTexture(nil, "ARTWORK")
    upIcon:SetSize(20, 20)
    upIcon:SetPoint("TOPLEFT", voteCard, "TOPLEFT", 12, -24)
    upIcon:SetTexture(GTV.ICON_THUMB_UP)

    local upCountText = voteCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    upCountText:SetPoint("LEFT", upIcon, "RIGHT", 6, 0)
    upCountText:SetTextColor(0.28, 0.95, 0.42)
    upCountText:SetText("0")
    f.upCountText = upCountText

    local downIcon = voteCard:CreateTexture(nil, "ARTWORK")
    downIcon:SetSize(20, 20)
    downIcon:SetPoint("LEFT", upCountText, "RIGHT", 26, 0)
    downIcon:SetTexture(GTV.ICON_THUMB_DOWN)

    local downCountText = voteCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    downCountText:SetPoint("LEFT", downIcon, "RIGHT", 6, 0)
    downCountText:SetTextColor(1.0, 0.36, 0.36)
    downCountText:SetText("0")
    f.downCountText = downCountText

    local partText = voteCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    partText:SetPoint("TOPRIGHT", voteCard, "TOPRIGHT", -10, -28)
    partText:SetTextColor(0.75, 0.78, 0.85)
    f.partText = partText

    local barBg = voteCard:CreateTexture(nil, "BACKGROUND")
    barBg:SetSize(268, 11)
    barBg:SetPoint("TOPLEFT", voteCard, "TOPLEFT", 12, -52)
    barBg:SetColorTexture(0.18, 0.19, 0.24, 1.0)

    local barUp = voteCard:CreateTexture(nil, "ARTWORK")
    barUp:SetHeight(11)
    barUp:SetPoint("LEFT", barBg, "LEFT", 0, 0)
    barUp:SetColorTexture(0.18, 0.78, 0.34, 1.0)
    barUp:Hide()
    f.barUp = barUp

    local barDown = voteCard:CreateTexture(nil, "ARTWORK")
    barDown:SetHeight(11)
    barDown:SetPoint("RIGHT", barBg, "RIGHT", 0, 0)
    barDown:SetColorTexture(0.84, 0.22, 0.22, 1.0)
    barDown:Hide()
    f.barDown = barDown

    local summaryLine = voteCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryLine:SetPoint("BOTTOMLEFT", voteCard, "BOTTOMLEFT", 12, 8)
    summaryLine:SetPoint("BOTTOMRIGHT", voteCard, "BOTTOMRIGHT", -12, 8)
    summaryLine:SetJustifyH("CENTER")
    f.summaryLine = summaryLine

    local autoCheck = CreateFrame("CheckButton", nil, livePane, "UICheckButtonTemplate")
    autoCheck:SetSize(22, 22)
    autoCheck:SetPoint("TOPLEFT", voteCard, "BOTTOMLEFT", -2, -5)
    autoCheck:SetScript("OnClick", function(self) GTV.Protocol:SetAutoReset(self:GetChecked()) end)
    autoCheck:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(GTV.L.AUTO_RESET_CHECK, 1, 0.85, 0.3)
            GameTooltip:AddLine(GTV.L.AUTO_RESET_TIP, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    autoCheck:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.autoCheck = autoCheck

    local autoLabel = livePane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoLabel:SetPoint("LEFT", autoCheck, "RIGHT", 2, 0)
    autoLabel:SetWidth(156)
    autoLabel:SetJustifyH("LEFT")
    autoLabel:SetText(GTV.L.AUTO_RESET_CHECK)

    local resetBtn = CreateFrame("Button", nil, livePane, "UIPanelButtonTemplate")
    resetBtn:SetSize(110, 22)
    resetBtn:SetPoint("TOPRIGHT", voteCard, "BOTTOMRIGHT", 0, -5)
    resetBtn:SetText(GTV.L.VOTE_RESET_BTN)
    resetBtn:SetScript("OnClick", function()
        GTV.Protocol:ResetVotes()
        GTV:PlaySound("IG_MAINMENU_OPTION", 852)
    end)
    f.resetBtn = resetBtn

    local liveSuggHeader = livePane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    liveSuggHeader:SetPoint("TOPLEFT", autoCheck, "BOTTOMLEFT", 2, -8)
    liveSuggHeader:SetTextColor(1.0, 0.84, 0.30)
    f.liveSuggHeader = liveSuggHeader

    local liveScrollBox = GTV:CreateBackdropFrame(livePane, nil, {
        bgColor = { 0.04, 0.05, 0.08, 0.88 },
        borderColor = { 0.35, 0.32, 0.22, 0.75 },
    })
    liveScrollBox:SetPoint("TOPLEFT", liveSuggHeader, "BOTTOMLEFT", 0, -5)
    liveScrollBox:SetPoint("BOTTOMRIGHT", livePane, "BOTTOMRIGHT", 0, 0)

    local liveScroll = CreateFrame("ScrollFrame", "GTVLeaderLiveScroll", liveScrollBox, "UIPanelScrollFrameTemplate")
    liveScroll:SetPoint("TOPLEFT", liveScrollBox, "TOPLEFT", 6, -6)
    liveScroll:SetPoint("BOTTOMRIGHT", liveScrollBox, "BOTTOMRIGHT", -26, 6)

    local liveScrollChild = CreateFrame("Frame", nil, liveScroll)
    liveScrollChild:SetSize(252, 160)
    liveScroll:SetScrollChild(liveScrollChild)
    f.liveScrollChild = liveScrollChild

    local liveEmptyText = liveScrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    liveEmptyText:SetPoint("TOPLEFT", liveScrollChild, "TOPLEFT", 8, -12)
    liveEmptyText:SetWidth(234)
    liveEmptyText:SetJustifyH("CENTER")
    liveEmptyText:SetText(GTV.L.SUGG_EMPTY)
    f.liveEmptyText = liveEmptyText

    -- =====================================================================
    -- PANE 2: TIMED MULTI-DAY POLL MANAGER
    -- =====================================================================
    local timedPane = CreateFrame("Frame", nil, rightCol)
    timedPane:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -30)
    timedPane:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
    timedPane:Hide()
    f.timedPane = timedPane

    local createBox = GTV:CreateBackdropFrame(timedPane, nil, {
        bgColor = { 0.08, 0.09, 0.14, 0.92 },
        borderColor = { 0.45, 0.40, 0.25, 0.85 },
    })
    createBox:SetAllPoints()
    f.timedCreateBox = createBox

    local createHeader = createBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    createHeader:SetPoint("TOPLEFT", createBox, "TOPLEFT", 12, -12)
    createHeader:SetText(GTV.L.TIMED_CREATE_HEADER)
    createHeader:SetTextColor(1.0, 0.84, 0.30)

    local titleLbl = createBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleLbl:SetPoint("TOPLEFT", createHeader, "BOTTOMLEFT", 0, -12)
    titleLbl:SetText(GTV.L.TIMED_TITLE_LABEL)

    local titleEdit = CreateFrame("EditBox", "GTVTimedTitleEdit", createBox, "InputBoxTemplate")
    titleEdit:SetSize(256, 22)
    titleEdit:SetPoint("TOPLEFT", titleLbl, "BOTTOMLEFT", 6, -5)
    titleEdit:SetAutoFocus(false)
    titleEdit:SetMaxLetters(34)
    titleEdit:SetText(GTV.L.TIMED_TITLE_DEFAULT)
    titleEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    titleEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local daysLbl = createBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    daysLbl:SetPoint("TOPLEFT", titleEdit, "BOTTOMLEFT", -6, -12)
    daysLbl:SetText(GTV.L.TIMED_DAYS_LABEL)

    local daysEdit = CreateFrame("EditBox", "GTVTimedDaysEdit", createBox, "InputBoxTemplate")
    daysEdit:SetSize(64, 22)
    daysEdit:SetPoint("LEFT", daysLbl, "RIGHT", 12, 0)
    daysEdit:SetAutoFocus(false)
    daysEdit:SetNumeric(true)
    daysEdit:SetMaxLetters(2)
    daysEdit:SetText("3")
    daysEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    daysEdit:SetScript("OnTextChanged", function(self)
        local n = tonumber(self:GetText())
        if n and n > 0 then
            customDurationSeconds = n * 86400
        end
    end)

    local presets = {
        { label = GTV.L.TIMED_PRESET_1H, secs = 3600, daysText = "" },
        { label = GTV.L.TIMED_PRESET_1D, secs = 86400, daysText = "1" },
        { label = GTV.L.TIMED_PRESET_3D, secs = 3 * 86400, daysText = "3" },
        { label = GTV.L.TIMED_PRESET_7D, secs = 7 * 86400, daysText = "7" },
    }
    local prevPreset = nil
    for _, pr in ipairs(presets) do
        local b = CreateFrame("Button", nil, createBox, "UIPanelButtonTemplate")
        b:SetSize(62, 22)
        if not prevPreset then
            b:SetPoint("TOPLEFT", daysLbl, "BOTTOMLEFT", 0, -10)
        else
            b:SetPoint("LEFT", prevPreset, "RIGHT", 6, 0)
        end
        b:SetText(pr.label)
        b:SetScript("OnClick", function()
            customDurationSeconds = pr.secs
            daysEdit:SetText(pr.daysText)
            GTV:PlaySound("IG_MAINMENU_OPTION", 852)
        end)
        prevPreset = b
    end

    local includeCurCheck = CreateFrame("CheckButton", nil, createBox, "UICheckButtonTemplate")
    includeCurCheck:SetSize(22, 22)
    includeCurCheck:SetPoint("TOPLEFT", daysLbl, "BOTTOMLEFT", -2, -40)
    includeCurCheck:SetChecked(true)

    local includeCurLbl = createBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    includeCurLbl:SetPoint("LEFT", includeCurCheck, "RIGHT", 4, 0)
    includeCurLbl:SetWidth(240)
    includeCurLbl:SetJustifyH("LEFT")
    includeCurLbl:SetText(GTV.L.TIMED_INCLUDE_CUR)

    local keepExistingCheck = CreateFrame("CheckButton", nil, createBox, "UICheckButtonTemplate")
    keepExistingCheck:SetSize(22, 22)
    keepExistingCheck:SetPoint("TOPLEFT", includeCurCheck, "BOTTOMLEFT", 0, -4)
    keepExistingCheck:SetChecked(true)

    local keepExistingLbl = createBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    keepExistingLbl:SetPoint("LEFT", keepExistingCheck, "RIGHT", 4, 0)
    keepExistingLbl:SetWidth(240)
    keepExistingLbl:SetJustifyH("LEFT")
    keepExistingLbl:SetText(GTV.L.TIMED_KEEP_EXISTING)

    local anonInfo = createBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anonInfo:SetPoint("TOPLEFT", keepExistingCheck, "BOTTOMLEFT", 2, -12)
    anonInfo:SetWidth(266)
    anonInfo:SetJustifyH("LEFT")
    anonInfo:SetText(GTV.L.VOTE_ANON_NOTICE)

    local startTimedBtn = CreateFrame("Button", nil, createBox, "UIPanelButtonTemplate")
    startTimedBtn:SetSize(200, 30)
    startTimedBtn:SetPoint("BOTTOM", createBox, "BOTTOM", 0, 18)
    startTimedBtn:SetText(GTV.L.TIMED_START_BTN)
    if startTimedBtn.GetFontString and startTimedBtn:GetFontString() then
        startTimedBtn:GetFontString():SetTextColor(0.35, 1.0, 0.45)
    end
    startTimedBtn:SetScript("OnClick", function()
        local initDesign = includeCurCheck:GetChecked() and ReadLeaderCurrentDesign() or nil
        local daysNum = tonumber(daysEdit:GetText())
        local secs = (daysNum and daysNum > 0) and (daysNum * 86400) or customDurationSeconds
        local poll = GTV.Protocol:CreateTimedPoll(titleEdit:GetText(), secs, initDesign, keepExistingCheck:GetChecked())
        if poll then
            forceCreateTimedView = false
            GTV:PlaySound("IG_QUEST_LIST_OPEN", 844)
            UI_LeaderPanel:Refresh()
        end
    end)

    -- Active/Finished Timed Poll Dashboard
    local activeBox = CreateFrame("Frame", nil, timedPane)
    activeBox:SetAllPoints()
    activeBox:Hide()
    f.timedActiveBox = activeBox

    local pollInfoCard = GTV:CreateBackdropFrame(activeBox, nil, {
        bgColor = { 0.09, 0.10, 0.15, 0.92 },
        borderColor = { 0.45, 0.40, 0.25, 0.85 },
    })
    pollInfoCard:SetSize(292, 86)
    pollInfoCard:SetPoint("TOPLEFT", activeBox, "TOPLEFT", 0, 0)

    local pollTitleText = pollInfoCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pollTitleText:SetPoint("TOPLEFT", pollInfoCard, "TOPLEFT", 10, -8)
    pollTitleText:SetWidth(272)
    pollTitleText:SetJustifyH("LEFT")
    pollTitleText:SetTextColor(1.0, 0.84, 0.30)
    f.pollTitleText = pollTitleText

    local pollTimeText = pollInfoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pollTimeText:SetPoint("TOPLEFT", pollTitleText, "BOTTOMLEFT", 0, -4)
    f.pollTimeText = pollTimeText

    local pollStatsText = pollInfoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pollStatsText:SetPoint("TOPLEFT", pollTimeText, "BOTTOMLEFT", 0, -4)
    pollStatsText:SetTextColor(0.85, 0.88, 0.95)
    f.pollStatsText = pollStatsText

    local pollAnonLabel = pollInfoCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pollAnonLabel:SetPoint("BOTTOMLEFT", pollInfoCard, "BOTTOMLEFT", 10, 8)
    pollAnonLabel:SetText(GTV.L.VOTE_GM_ANON_HINT)

    local addCurBtn = CreateFrame("Button", nil, activeBox, "UIPanelButtonTemplate")
    addCurBtn:SetSize(102, 22)
    addCurBtn:SetPoint("TOPLEFT", pollInfoCard, "BOTTOMLEFT", 0, -6)
    addCurBtn:SetText(GTV.L.TIMED_ADD_CUR_BTN)
    addCurBtn:SetScript("OnClick", function()
        local d = ReadLeaderCurrentDesign()
        if d then
            GTV.Protocol:SubmitGuildDesign(d, "", true)
            GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
            UI_LeaderPanel:Refresh()
        end
    end)
    f.timedAddCurBtn = addCurBtn

    local endOrNewBtn = CreateFrame("Button", nil, activeBox, "UIPanelButtonTemplate")
    endOrNewBtn:SetSize(92, 22)
    endOrNewBtn:SetPoint("LEFT", addCurBtn, "RIGHT", 4, 0)
    endOrNewBtn:SetScript("OnClick", function()
        local poll = GTV.Protocol:GetActiveTimedPoll()
        if poll and GTV.Protocol:IsTimedPollOpen(poll) then
            GTV.Protocol:CloseTimedPoll()
        else
            forceCreateTimedView = true
        end
        UI_LeaderPanel:Refresh()
    end)
    f.timedEndOrNewBtn = endOrNewBtn

    local announceBtn = CreateFrame("Button", nil, activeBox, "UIPanelButtonTemplate")
    announceBtn:SetSize(90, 22)
    announceBtn:SetPoint("LEFT", endOrNewBtn, "RIGHT", 4, 0)
    announceBtn:SetText(GTV.L.TIMED_ANNOUNCE_BTN)
    announceBtn:SetScript("OnClick", function()
        GTV.Protocol:AnnounceTimedPollWinner()
        GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
    end)
    f.timedAnnounceBtn = announceBtn

    local timedScrollBox = GTV:CreateBackdropFrame(activeBox, nil, {
        bgColor = { 0.04, 0.05, 0.08, 0.88 },
        borderColor = { 0.35, 0.32, 0.22, 0.75 },
    })
    timedScrollBox:SetPoint("TOPLEFT", addCurBtn, "BOTTOMLEFT", 0, -6)
    timedScrollBox:SetPoint("BOTTOMRIGHT", activeBox, "BOTTOMRIGHT", 0, 0)

    local timedScroll = CreateFrame("ScrollFrame", "GTVLeaderTimedScroll", timedScrollBox, "UIPanelScrollFrameTemplate")
    timedScroll:SetPoint("TOPLEFT", timedScrollBox, "TOPLEFT", 6, -6)
    timedScroll:SetPoint("BOTTOMRIGHT", timedScrollBox, "BOTTOMRIGHT", -26, 6)

    local timedScrollChild = CreateFrame("Frame", nil, timedScroll)
    timedScrollChild:SetSize(252, 220)
    timedScroll:SetScrollChild(timedScrollChild)
    f.timedScrollChild = timedScrollChild

    local timedEmptyText = timedScrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    timedEmptyText:SetPoint("TOPLEFT", timedScrollChild, "TOPLEFT", 8, -14)
    timedEmptyText:SetWidth(234)
    timedEmptyText:SetJustifyH("CENTER")
    timedEmptyText:SetText(GTV.L.SUGG_EMPTY)
    f.timedEmptyText = timedEmptyText

    -- =====================================================================
    -- PANE 3: SAVED DESIGNS LIBRARY
    -- =====================================================================
    local savedPane = CreateFrame("Frame", nil, rightCol)
    savedPane:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -30)
    savedPane:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
    savedPane:Hide()
    f.savedPane = savedPane

    local saveNameEdit = CreateFrame("EditBox", "GTVLeaderSaveNameEdit", savedPane, "InputBoxTemplate")
    saveNameEdit:SetSize(184, 22)
    saveNameEdit:SetPoint("TOPLEFT", savedPane, "TOPLEFT", 6, -2)
    saveNameEdit:SetAutoFocus(false)
    saveNameEdit:SetMaxLetters(32)
    saveNameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    saveNameEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local savePlaceholder = saveNameEdit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    savePlaceholder:SetPoint("LEFT", saveNameEdit, "LEFT", 6, 0)
    savePlaceholder:SetText(GTV.L.SAVED_NAME_PLACEHOLDER)
    saveNameEdit:SetScript("OnTextChanged", function(self)
        savePlaceholder:SetShown(self:GetText() == "")
    end)

    local saveNowBtn = CreateFrame("Button", nil, savedPane, "UIPanelButtonTemplate")
    saveNowBtn:SetSize(96, 24)
    saveNowBtn:SetPoint("TOPRIGHT", savedPane, "TOPRIGHT", 0, -1)
    saveNowBtn:SetText(GTV.L.BTN_SAVE_LOCAL)
    saveNowBtn:SetScript("OnClick", function()
        local d = ReadLeaderCurrentDesign()
        if not d then
            GTV:Print(GTV.L.SUGG_NO_DESIGN)
            return
        end
        GTV.Storage:SaveDesign(saveNameEdit:GetText(), d)
        saveNameEdit:SetText("")
        saveNameEdit:ClearFocus()
        GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
    end)

    local savedScrollBox = GTV:CreateBackdropFrame(savedPane, nil, {
        bgColor = { 0.04, 0.05, 0.08, 0.88 },
        borderColor = { 0.35, 0.32, 0.22, 0.75 },
    })
    savedScrollBox:SetPoint("TOPLEFT", savedPane, "TOPLEFT", 0, -32)
    savedScrollBox:SetPoint("BOTTOMRIGHT", savedPane, "BOTTOMRIGHT", 0, 0)

    local savedScroll = CreateFrame("ScrollFrame", "GTVLeaderSavedScroll", savedScrollBox, "UIPanelScrollFrameTemplate")
    savedScroll:SetPoint("TOPLEFT", savedScrollBox, "TOPLEFT", 6, -6)
    savedScroll:SetPoint("BOTTOMRIGHT", savedScrollBox, "BOTTOMRIGHT", -26, 6)

    local savedScrollChild = CreateFrame("Frame", nil, savedScroll)
    savedScrollChild:SetSize(252, 260)
    savedScroll:SetScrollChild(savedScrollChild)
    f.savedScrollChild = savedScrollChild

    local savedEmptyText = savedScrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    savedEmptyText:SetPoint("TOPLEFT", savedScrollChild, "TOPLEFT", 8, -16)
    savedEmptyText:SetWidth(234)
    savedEmptyText:SetJustifyH("CENTER")
    savedEmptyText:SetText(GTV.L.SAVED_EMPTY)
    f.savedEmptyText = savedEmptyText

    panel = f
    StyleLeaderTab(tabLive, true)
    StyleLeaderTab(tabTimed, false)
    StyleLeaderTab(tabSaved, false)
    return f
end

local function RenderGuildDesignList(scrollChild, emptyText, rowPool, poll, isOpen)
    local designs = GTV.Protocol:GetGuildDesigns()
    for _, row in ipairs(rowPool) do
        row:Hide()
    end
    if #designs == 0 then
        emptyText:Show()
        scrollChild:SetHeight(80)
        return
    end
    emptyText:Hide()

    local ranked = {}
    for idx, entry in ipairs(designs) do
        local up, down = GTV.Protocol:GetDesignVotes(entry.id)
        table.insert(ranked, { entry = entry, idx = idx, up = up, down = down, score = up - down })
    end
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.up ~= b.up then return a.up > b.up end
        return a.idx < b.idx
    end)

    local y = -4
    for i, item in ipairs(ranked) do
        local d = item.entry
        local row = rowPool[i]
        if not row then
            row = GTV:CreateBackdropFrame(scrollChild, nil, {
                bgColor = { 0.10, 0.11, 0.17, 0.92 },
                borderColor = { 0.42, 0.36, 0.22, 0.8 },
                edgeSize = 10,
            })
            row:SetSize(248, 68)

            row.thumb = GTV.TabardSync:Create2DPreview(row, 42, 52)
            row.thumb:SetPoint("LEFT", row, "LEFT", 6, 0)

            row.titleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.titleText:SetPoint("TOPLEFT", row.thumb, "TOPRIGHT", 8, -1)
            row.titleText:SetWidth(122)
            row.titleText:SetJustifyH("LEFT")

            row.votesText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.votesText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -7)

            row.noteText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.noteText:SetPoint("TOPLEFT", row.titleText, "BOTTOMLEFT", 0, -2)
            row.noteText:SetWidth(182)
            row.noteText:SetJustifyH("LEFT")
            row.noteText:SetTextColor(0.82, 0.85, 0.92)

            row.applyBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.applyBtn:SetSize(84, 20)
            row.applyBtn:SetPoint("BOTTOMLEFT", row.thumb, "BOTTOMRIGHT", 8, 1)
            row.applyBtn:SetText(GTV.L.BTN_APPLY)

            row.saveBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.saveBtn:SetSize(64, 20)
            row.saveBtn:SetPoint("LEFT", row.applyBtn, "RIGHT", 4, 0)
            row.saveBtn:SetText(GTV.L.BTN_SAVE)

            row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.delBtn:SetSize(26, 20)
            row.delBtn:SetPoint("LEFT", row.saveBtn, "RIGHT", 4, 0)
            row.delBtn:SetText(GTV.L.BTN_DELETE)

            rowPool[i] = row
        end

        local isWinner = poll and ((poll.winnerDesignId and poll.winnerDesignId == d.id) or (not isOpen and i == 1))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, y)
        row:SetBackdropBorderColor(isWinner and 0.95 or 0.42, isWinner and 0.78 or 0.36, 0.22, 0.95)
        row.thumb:SetDesign(d.design)
        row.titleText:SetText((isWinner and GTV.L.TIMED_WINNER_TAG or "") .. d.authorName)
        row.noteText:SetText(d.note ~= "" and ("\"" .. d.note .. "\"") or "")
        row.votesText:SetText(string.format(GTV.L.TIMED_GM_COUNTS, item.up, item.down))

        row.applyBtn:SetScript("OnClick", function()
            GTV:PlaySound("IG_MAINMENU_OPTION", 852)
            GTV.Protocol:ApplyDesignToLeaderModel(d.design)
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
        y = y - 72
    end
    scrollChild:SetHeight(math.max(120, -y + 8))
end

local function RefreshTimedPollPane()
    local poll = GTV.Protocol:GetActiveTimedPoll()
    if not poll or forceCreateTimedView then
        panel.timedCreateBox:Show()
        panel.timedActiveBox:Hide()
        return
    end

    panel.timedCreateBox:Hide()
    panel.timedActiveBox:Show()

    local isOpen = GTV.Protocol:IsTimedPollOpen(poll)
    local remStr, expired = GTV.Storage:FormatRemaining(poll.endsAt)
    local dCount, voters, abstained = GTV.Protocol:GetBoardStats()

    panel.pollTitleText:SetText(poll.title or GTV.L.TIMED_TITLE_DEFAULT)
    if poll.status == "CLOSED" then
        panel.pollTimeText:SetText(GTV.L.TIMED_CLOSED)
    elseif expired then
        panel.pollTimeText:SetText(GTV.L.TIMED_EXPIRED)
    else
        panel.pollTimeText:SetText(string.format(GTV.L.TIMED_REMAINING, remStr))
    end
    panel.pollStatsText:SetText(string.format(GTV.L.TIMED_STATS_GM, dCount, voters, abstained))

    if isOpen then
        panel.timedAddCurBtn:Enable()
        panel.timedEndOrNewBtn:SetText(GTV.L.TIMED_END_BTN)
    else
        panel.timedAddCurBtn:Disable()
        panel.timedEndOrNewBtn:SetText(GTV.L.TIMED_NEW_BTN)
    end

    RenderGuildDesignList(panel.timedScrollChild, panel.timedEmptyText, timedDesignRows, poll, isOpen)
end

local function RefreshSavedPane()
    local list = GTV.Storage:GetSavedDesigns()
    local canSubmit = GTV.Protocol:IsGuildBoardOpenForChanges()

    for _, row in ipairs(savedRows) do
        row:Hide()
    end
    if #list == 0 then
        panel.savedEmptyText:Show()
        panel.savedScrollChild:SetHeight(100)
        return
    end
    panel.savedEmptyText:Hide()

    local y = -4
    for i, entry in ipairs(list) do
        local row = savedRows[i]
        if not row then
            row = GTV:CreateBackdropFrame(panel.savedScrollChild, nil, {
                bgColor = { 0.10, 0.11, 0.17, 0.92 },
                borderColor = { 0.42, 0.36, 0.22, 0.8 },
                edgeSize = 10,
            })
            row:SetSize(248, 64)

            row.thumb = GTV.TabardSync:Create2DPreview(row, 42, 52)
            row.thumb:SetPoint("LEFT", row, "LEFT", 6, 0)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameText:SetPoint("TOPLEFT", row.thumb, "TOPRIGHT", 8, -4)
            row.nameText:SetWidth(182)
            row.nameText:SetJustifyH("LEFT")

            row.loadBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.loadBtn:SetSize(72, 20)
            row.loadBtn:SetPoint("BOTTOMLEFT", row.thumb, "BOTTOMRIGHT", 8, 2)
            row.loadBtn:SetText(GTV.L.BTN_LOAD)

            row.pollBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.pollBtn:SetSize(74, 20)
            row.pollBtn:SetPoint("LEFT", row.loadBtn, "RIGHT", 4, 0)
            row.pollBtn:SetText(GTV.L.BTN_ADD_TO_POLL)

            row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.delBtn:SetSize(28, 20)
            row.delBtn:SetPoint("LEFT", row.pollBtn, "RIGHT", 4, 0)
            row.delBtn:SetText(GTV.L.BTN_DELETE)

            savedRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.savedScrollChild, "TOPLEFT", 2, y)
        row.thumb:SetDesign(entry.design)
        row.nameText:SetText(entry.name)

        if canSubmit then row.pollBtn:Enable() else row.pollBtn:Disable() end

        row.loadBtn:SetScript("OnClick", function()
            GTV:PlaySound("IG_MAINMENU_OPTION", 852)
            GTV.Protocol:ApplyDesignToLeaderModel(entry.design, function()
                GTV:Print(string.format(GTV.L.SAVED_LOADED, entry.name))
            end)
        end)
        row.pollBtn:SetScript("OnClick", function()
            GTV.Protocol:SubmitGuildDesign(entry.design, entry.name, true)
            GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
        end)
        row.delBtn:SetScript("OnClick", function()
            GTV.Storage:DeleteSavedDesign(entry.id)
            GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
        end)
        row:Show()
        y = y - 68
    end
    panel.savedScrollChild:SetHeight(math.max(120, -y + 8))
end

function UI_LeaderPanel:Refresh()
    if not panel or not panel:IsShown() then
        return
    end
    local isLeading = GTV.Protocol:IsLeading()
    panel.liveToggleBtn:SetText(isLeading and GTV.L.LEADER_STOP_BTN or GTV.L.LEADER_START_BTN)
    if isLeading then
        panel.reinviteBtn:Enable()
        panel.resetBtn:Enable()
    else
        panel.reinviteBtn:Disable()
        panel.resetBtn:Disable()
    end
    panel.autoCheck:SetChecked(GTV.db and GTV.db.autoResetVotes ~= false)

    local up, down, abstain, active = GTV.Protocol:GetVoteCounts()
    panel.upCountText:SetText(tostring(up))
    panel.downCountText:SetText(tostring(down))
    panel.partText:SetText(string.format(GTV.L.VOTE_PARTICIPANTS, active))
    panel.summaryLine:SetText(string.format(GTV.L.VOTE_SUMMARY, up, down, abstain))

    local totalVotes = up + down
    local barWidth = 268
    if totalVotes > 0 then
        local upW = math.floor((up / totalVotes) * barWidth + 0.5)
        local downW = barWidth - upW
        if upW > 0 then panel.barUp:SetWidth(upW); panel.barUp:Show() else panel.barUp:Hide() end
        if downW > 0 then panel.barDown:SetWidth(downW); panel.barDown:Show() else panel.barDown:Hide() end
    else
        panel.barUp:Hide()
        panel.barDown:Hide()
    end

    local designs = GTV.Protocol:GetGuildDesigns()
    panel.liveSuggHeader:SetText(string.format(GTV.L.TAB_SUGGESTIONS, #designs))
    RenderGuildDesignList(panel.liveScrollChild, panel.liveEmptyText, liveDesignRows, nil, true)

    local savedCount = #GTV.Storage:GetSavedDesigns()
    panel.tabSaved:SetText(GTV.L.LEADER_TAB_SAVED .. " (" .. savedCount .. ")")

    RefreshTimedPollPane()
    RefreshSavedPane()
end

function UI_LeaderPanel:ShowForVendorFrame()
    local f = EnsurePanel()
    dockedToVendor = true
    isStandaloneMode = false
    f.designerPane:Hide()
    f:SetSize(316, 474)
    f:ClearAllPoints()
    if TabardFrame and TabardFrame:IsShown() then
        f:SetPoint("TOPLEFT", TabardFrame, "TOPRIGHT", 6, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
    f.title:SetText(GTV.L.LEADER_PANEL_TITLE)
    f:Show()
    self:Refresh()
end

function UI_LeaderPanel:ShowStandalone(isTestMode)
    local f = EnsurePanel()
    dockedToVendor = false
    isStandaloneMode = true
    f.designerPane:Show()
    f:SetSize(550, 474)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", isTestMode and -260 or 0, 0)
    f.title:SetText(isTestMode and (GTV.L.LEADER_PANEL_TITLE .. " (TEST)") or GTV.L.LEADER_PANEL_TITLE)
    f:Show()

    C_Timer.After(0.05, function()
        if not f:IsShown() then return end
        f.standaloneModel:EnsureReady()
        if not GTV.Protocol:IsLeading() or isTestMode then
            GTV.Protocol:StartLeaderSession(f.standaloneModel, true, isTestMode and true or false)
        end
        self:Refresh()
    end)
end

function UI_LeaderPanel:IsDockedToVendor()
    return dockedToVendor
end

function UI_LeaderPanel:Hide()
    if panel then
        panel:Hide()
    end
end

GTV.Protocol:RegisterCallback(function()
    if panel and panel:IsShown() then
        UI_LeaderPanel:Refresh()
    end
end)

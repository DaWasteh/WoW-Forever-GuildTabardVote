local _, GTV = ...

local UI_MemberWindow = {}
GTV.UI_MemberWindow = UI_MemberWindow

local win
local activeTab = "DESIGN" -- "LIVE" | "TIMED" | "DESIGN" | "SAVED"
local selectedDesignId = nil
local rightRowPool = {}
local toastTimer = nil

local function ShowToast(msg, r, g, b)
    if not win or not win.toastText then
        return
    end
    win.toastText:SetText(msg or "")
    win.toastText:SetTextColor(r or 0.35, g or 1.0, b or 0.50)
    win.toastBar:Show()
    if toastTimer and toastTimer.Cancel then
        toastTimer:Cancel()
    end
    toastTimer = C_Timer.NewTimer and C_Timer.NewTimer(3.5, function()
        toastTimer = nil
        if win and win.toastBar then
            win.toastBar:Hide()
        end
    end) or nil
end

local function CreateCustomRow(parent, yOffset, varIndex, labelText, onStep)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(208, 24)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.11, 0.12, 0.18, 0.72)

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("CENTER", row, "CENTER", 0, 0)
    lbl:SetWidth(134)
    lbl:SetJustifyH("CENTER")
    lbl:SetText(labelText)

    local leftBtn = CreateFrame("Button", nil, row)
    leftBtn:SetSize(26, 26)
    leftBtn:SetPoint("LEFT", row, "LEFT", 2, 0)
    leftBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    leftBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    leftBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    leftBtn:SetScript("OnClick", function()
        GTV:PlaySound("GS_CHARACTER_CREATION_LOOK", 823)
        onStep(varIndex, -1)
    end)

    local rightBtn = CreateFrame("Button", nil, row)
    rightBtn:SetSize(26, 26)
    rightBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    rightBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    rightBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    rightBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    rightBtn:SetScript("OnClick", function()
        GTV:PlaySound("GS_CHARACTER_CREATION_LOOK", 823)
        onStep(varIndex, 1)
    end)

    return row
end

local function StyleTabButton(btn, selected)
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

local function ColorBtnText(btn, r, g, b)
    if btn.GetFontString and btn:GetFontString() then
        btn:GetFontString():SetTextColor(r, g, b)
    end
end

local function SyncModelAnd2D(targetDesign, hintVar, hintDelta)
    if not win or not win:IsShown() then
        return
    end
    win.preview2D:SetDesign(targetDesign)
    if targetDesign then
        win.model:EnsureReady(false)
        win.syncHint:Show()
        GTV.TabardSync:SeekModel(win.model, targetDesign, hintVar, hintDelta, function()
            if win and win.syncHint then
                win.syncHint:Hide()
            end
        end)
    end
end

local function UpdateEditor2DFromModel()
    if not win then
        return
    end
    local d = GTV.TabardSync:ReadModel(win.model)
    if d then
        win.preview2D:SetDesign(d)
    end
end

local function GetSelectedGuildDesign()
    if not selectedDesignId then
        return nil
    end
    local board = GTV.Protocol:GetGuildBoard(false)
    if board and board.designById then
        return board.designById[selectedDesignId]
    end
    return nil
end

local function SelectGuildDesign(entry)
    if not entry then
        selectedDesignId = nil
        if win and win.previewBanner then
            win.previewBanner:Hide()
        end
        return
    end
    selectedDesignId = entry.id
    if win then
        local label = (entry.note and entry.note ~= "") and entry.note or entry.authorName
        win.previewBannerText:SetText(string.format(GTV.L.STATUS_PREVIEWING_SUGG, label))
        win.previewBanner:Show()
        win.returnLiveBtn:SetShown(GTV.Protocol:HasActiveSession())
        SyncModelAnd2D(entry.design, 0, 0)
        UI_MemberWindow:Refresh()
    end
end

local function SetActiveTab(tabName)
    activeTab = tabName
    if not win then
        return
    end

    StyleTabButton(win.tabLiveBtn, activeTab == "LIVE")
    StyleTabButton(win.tabTimedBtn, activeTab == "TIMED")
    StyleTabButton(win.tabDesignBtn, activeTab == "DESIGN")
    StyleTabButton(win.tabSavedBtn, activeTab == "SAVED")

    win.liveControls:SetShown(activeTab == "LIVE")
    win.timedControls:SetShown(activeTab == "TIMED")
    win.designControls:SetShown(activeTab == "DESIGN" or activeTab == "SAVED")

    if activeTab == "LIVE" then
        local s = GTV.Protocol:GetSession()
        if s and s.design and not selectedDesignId then
            win.previewBanner:Hide()
            SyncModelAnd2D(s.design, 0, 0)
        elseif not s then
            local designs = GTV.Protocol:GetGuildDesigns()
            if not GetSelectedGuildDesign() and designs[1] then
                SelectGuildDesign(designs[1])
            end
        end
    elseif activeTab == "TIMED" then
        local designs = GTV.Protocol:GetGuildDesigns()
        if not GetSelectedGuildDesign() and designs[1] then
            SelectGuildDesign(designs[1])
        end
    else
        win.previewBanner:Hide()
        GTV.TabardSync:CancelSeek(win.model)
        win.syncHint:Hide()
        win.model:EnsureReady(false)
        C_Timer.After(0.03, UpdateEditor2DFromModel)
    end

    UI_MemberWindow:Refresh()
end

-- Handles big Thumbs Up / Down click (works on Live Leader design OR any selected Guild Design!)
local function HandleBigVoteClick(vote)
    local s = GTV.Protocol:GetSession()
    local sel = GetSelectedGuildDesign()

    if s and not sel then
        local ok, applied = GTV.Protocol:SendVote(vote)
        if ok then
            GTV:PlaySound(vote == "UP" and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF", 856)
            if applied == "UP" then
                ShowToast(GTV.L.TOAST_VOTED_UP, 0.35, 1.0, 0.45)
            elseif applied == "DOWN" then
                ShowToast(GTV.L.TOAST_VOTED_DOWN, 1.0, 0.45, 0.45)
            else
                ShowToast(GTV.L.TOAST_VOTE_CLEARED, 0.85, 0.85, 0.85)
            end
        end
        return
    end

    if not sel then
        local designs = GTV.Protocol:GetGuildDesigns()
        if designs[1] then
            SelectGuildDesign(designs[1])
            sel = designs[1]
        end
    end

    if sel then
        local ok, applied = GTV.Protocol:VoteGuildDesign(sel.id, vote)
        if ok then
            GTV:PlaySound(vote == "UP" and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF", 856)
            if applied == "UP" then
                ShowToast(GTV.L.TOAST_VOTED_UP, 0.35, 1.0, 0.45)
            elseif applied == "DOWN" then
                ShowToast(GTV.L.TOAST_VOTED_DOWN, 1.0, 0.45, 0.45)
            else
                ShowToast(GTV.L.TOAST_VOTE_CLEARED, 0.85, 0.85, 0.85)
            end
        else
            ShowToast(GTV.L.TIMED_VOTING_LOCKED, 1.0, 0.65, 0.35)
        end
    else
        GTV:PlaySound("IG_MAINMENU_OPTION", 852)
        ShowToast(GTV.L.VOTE_SELECT_HINT, 1.0, 0.85, 0.35)
    end
end

local function EnsureWindow()
    if win then
        return win
    end

    local f = GTV:CreateBackdropFrame(UIParent, "GuildTabardVoteMemberWindow", {
        bgColor = { 0.06, 0.07, 0.11, 0.96 },
        borderColor = { 0.82, 0.67, 0.28, 1.0 },
    })
    f:SetSize(784, 526)
    f:SetPoint("CENTER", UIParent, "CENTER", 140, 0)
    f:SetFrameStrata("HIGH")
    f:Hide()
    GTV:AttachDrag(f)

    if UISpecialFrames then
        table.insert(UISpecialFrames, "GuildTabardVoteMemberWindow")
    end

    f:SetScript("OnHide", function()
        local s = GTV.Protocol:GetSession()
        if s and not s.isLeader then
            GTV.Protocol:SendParticipation("LEAVE")
        end
        GTV.TabardSync:CancelSeek(f.model)
    end)

    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 15 then
            acc = 0
            if activeTab == "TIMED" then
                UI_MemberWindow:Refresh()
            end
        end
    end)

    -- Header
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
    icon:SetTexture(GTV.ICON_ADDON)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 4)
    title:SetText(GTV.L.ADDON_SUBTITLE)
    title:SetTextColor(1.0, 0.84, 0.30)

    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    f.statusText = statusText

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)

    -- Guild Master quick shortcut button to Leader Panel
    local leaderPanelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    leaderPanelBtn:SetSize(108, 22)
    leaderPanelBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    leaderPanelBtn:SetText(GTV.L.BTN_LEADER_PANEL)
    ColorBtnText(leaderPanelBtn, 1.0, 0.88, 0.35)
    leaderPanelBtn:SetScript("OnClick", function()
        GTV:PlaySound("IG_MAINMENU_OPTION", 852)
        if GTV.UI_LeaderPanel then
            GTV.UI_LeaderPanel:ShowStandalone(GTV.Protocol:IsTestModeActive())
        end
    end)
    leaderPanelBtn:Hide()
    f.leaderPanelBtn = leaderPanelBtn

    -- 4 Top Mode Tabs
    local tabLiveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tabLiveBtn:SetSize(134, 26)
    tabLiveBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -48)
    tabLiveBtn:SetText(GTV.L.TAB_LIVE)
    tabLiveBtn:SetScript("OnClick", function()
        GTV:PlaySound("IG_CHARACTER_INFO_TAB", 841)
        SetActiveTab("LIVE")
    end)
    f.tabLiveBtn = tabLiveBtn

    local tabTimedBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tabTimedBtn:SetSize(142, 26)
    tabTimedBtn:SetPoint("LEFT", tabLiveBtn, "RIGHT", 6, 0)
    tabTimedBtn:SetText(GTV.L.TAB_TIMED)
    tabTimedBtn:SetScript("OnClick", function()
        GTV:PlaySound("IG_CHARACTER_INFO_TAB", 841)
        SetActiveTab("TIMED")
    end)
    f.tabTimedBtn = tabTimedBtn

    local tabDesignBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tabDesignBtn:SetSize(132, 26)
    tabDesignBtn:SetPoint("LEFT", tabTimedBtn, "RIGHT", 6, 0)
    tabDesignBtn:SetText(GTV.L.TAB_DESIGN)
    tabDesignBtn:SetScript("OnClick", function()
        GTV:PlaySound("IG_CHARACTER_INFO_TAB", 841)
        SetActiveTab("DESIGN")
    end)
    f.tabDesignBtn = tabDesignBtn

    local tabSavedBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tabSavedBtn:SetSize(146, 26)
    tabSavedBtn:SetPoint("LEFT", tabDesignBtn, "RIGHT", 6, 0)
    tabSavedBtn:SetText(string.format(GTV.L.TAB_SAVED, 0))
    tabSavedBtn:SetScript("OnClick", function()
        GTV:PlaySound("IG_CHARACTER_INFO_TAB", 841)
        SetActiveTab("SAVED")
    end)
    f.tabSavedBtn = tabSavedBtn

    -- Inline Toast Feedback Bar (top right above right panel, unmistakable instant feedback!)
    local toastBar = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.08, 0.14, 0.10, 0.96 },
        borderColor = { 0.35, 0.85, 0.45, 0.95 },
        edgeSize = 10,
    })
    toastBar:SetSize(454, 24)
    toastBar:SetPoint("TOP", f, "TOP", -150, -82)
    toastBar:SetFrameLevel(f:GetFrameLevel() + 20)
    toastBar:Hide()
    f.toastBar = toastBar

    local toastText = toastBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toastText:SetPoint("CENTER", toastBar, "CENTER", 0, 0)
    f.toastText = toastText

    -- LEFT STAGE: 3D TabardModel + 2D Flat Preview
    local stage = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.04, 0.05, 0.08, 0.92 },
        borderColor = { 0.45, 0.38, 0.22, 0.85 },
    })
    stage:SetSize(454, 294)
    stage:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -80)
    f.stage = stage

    local model = GTV.TabardSync:Create3DModel(stage, 308, 264)
    model:SetPoint("TOPLEFT", stage, "TOPLEFT", 8, -8)
    f.model = model

    local rotateHint = stage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rotateHint:SetPoint("BOTTOMLEFT", stage, "BOTTOMLEFT", 10, 6)
    rotateHint:SetText(GTV.L.ROTATE_HINT)

    local syncHint = stage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    syncHint:SetPoint("TOPLEFT", model, "TOPLEFT", 8, -8)
    syncHint:SetTextColor(1.0, 0.85, 0.35)
    syncHint:SetText(GTV.L.STATUS_SYNCING)
    syncHint:Hide()
    f.syncHint = syncHint

    local previewBox = GTV:CreateBackdropFrame(stage, nil, {
        bgColor = { 0.07, 0.08, 0.12, 0.92 },
        borderColor = { 0.55, 0.46, 0.24, 0.85 },
        edgeSize = 10,
    })
    previewBox:SetSize(126, 174)
    previewBox:SetPoint("TOPRIGHT", stage, "TOPRIGHT", -10, -18)

    local previewTitle = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewTitle:SetPoint("TOP", previewBox, "TOP", 0, -8)
    previewTitle:SetText(GTV.L.LABEL_2D_PREVIEW)
    previewTitle:SetTextColor(0.95, 0.82, 0.40)

    local preview2D = GTV.TabardSync:Create2DPreview(previewBox, 100, 124)
    preview2D:SetPoint("BOTTOM", previewBox, "BOTTOM", 0, 14)
    f.preview2D = preview2D

    local previewBanner = GTV:CreateBackdropFrame(stage, nil, {
        bgColor = { 0.08, 0.16, 0.26, 0.94 },
        borderColor = { 0.35, 0.72, 1.0, 0.9 },
        edgeSize = 10,
    })
    previewBanner:SetSize(126, 76)
    previewBanner:SetPoint("TOP", previewBox, "BOTTOM", 0, -8)
    previewBanner:Hide()
    f.previewBanner = previewBanner

    local previewBannerText = previewBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewBannerText:SetPoint("TOPLEFT", previewBanner, "TOPLEFT", 6, -8)
    previewBannerText:SetPoint("TOPRIGHT", previewBanner, "TOPRIGHT", -6, -8)
    previewBannerText:SetJustifyH("CENTER")
    f.previewBannerText = previewBannerText

    local returnLiveBtn = CreateFrame("Button", nil, previewBanner, "UIPanelButtonTemplate")
    returnLiveBtn:SetSize(110, 22)
    returnLiveBtn:SetPoint("BOTTOM", previewBanner, "BOTTOM", 0, 8)
    returnLiveBtn:SetText(GTV.L.BTN_RETURN_LIVE)
    returnLiveBtn:SetScript("OnClick", function()
        selectedDesignId = nil
        previewBanner:Hide()
        local s = GTV.Protocol:GetSession()
        if s and s.design then
            SyncModelAnd2D(s.design, 0, 0)
        end
        UI_MemberWindow:Refresh()
    end)
    f.returnLiveBtn = returnLiveBtn

    -- =====================================================================
    -- BOTTOM-LEFT A: ANONYMOUS VOTING BUTTONS (REAL BUTTON WIDGETS!)
    -- =====================================================================
    local liveControls = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.08, 0.09, 0.14, 0.92 },
        borderColor = { 0.45, 0.38, 0.22, 0.85 },
    })
    liveControls:SetSize(454, 130)
    liveControls:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -8)
    f.liveControls = liveControls

    local upBtn = GTV:CreateBackdropFrame(liveControls, nil, {
        frameType = "Button",
        bgColor = { 0.08, 0.28, 0.13, 0.92 },
        borderColor = { 0.24, 0.80, 0.38, 0.9 },
        edgeSize = 12,
    })
    upBtn:SetSize(202, 46)
    upBtn:SetPoint("TOPLEFT", liveControls, "TOPLEFT", 14, -14)
    upBtn:RegisterForClicks("LeftButtonUp")

    local upBtnIcon = upBtn:CreateTexture(nil, "ARTWORK")
    upBtnIcon:SetSize(30, 30)
    upBtnIcon:SetPoint("LEFT", upBtn, "LEFT", 12, 0)
    upBtnIcon:SetTexture(GTV.ICON_THUMB_UP)

    local upBtnText = upBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    upBtnText:SetPoint("LEFT", upBtnIcon, "RIGHT", 10, 0)
    upBtnText:SetText(GTV.L.VOTE_UP)
    upBtnText:SetTextColor(0.45, 1.0, 0.55)

    upBtn:SetScript("OnClick", function() HandleBigVoteClick("UP") end)
    upBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.45, 1.0, 0.58, 1.0) end)
    upBtn:SetScript("OnLeave", function() UI_MemberWindow:RefreshLiveVoteButtons() end)
    f.upBtn = upBtn

    local downBtn = GTV:CreateBackdropFrame(liveControls, nil, {
        frameType = "Button",
        bgColor = { 0.30, 0.09, 0.09, 0.92 },
        borderColor = { 0.85, 0.25, 0.25, 0.9 },
        edgeSize = 12,
    })
    downBtn:SetSize(202, 46)
    downBtn:SetPoint("TOPRIGHT", liveControls, "TOPRIGHT", -14, -14)
    downBtn:RegisterForClicks("LeftButtonUp")

    local downBtnIcon = downBtn:CreateTexture(nil, "ARTWORK")
    downBtnIcon:SetSize(30, 30)
    downBtnIcon:SetPoint("LEFT", downBtn, "LEFT", 12, 0)
    downBtnIcon:SetTexture(GTV.ICON_THUMB_DOWN)

    local downBtnText = downBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    downBtnText:SetPoint("LEFT", downBtnIcon, "RIGHT", 10, 0)
    downBtnText:SetText(GTV.L.VOTE_DOWN)
    downBtnText:SetTextColor(1.0, 0.48, 0.48)

    downBtn:SetScript("OnClick", function() HandleBigVoteClick("DOWN") end)
    downBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1.0, 0.45, 0.45, 1.0) end)
    downBtn:SetScript("OnLeave", function() UI_MemberWindow:RefreshLiveVoteButtons() end)
    f.downBtn = downBtn

    local yourVoteText = liveControls:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    yourVoteText:SetPoint("TOP", liveControls, "TOP", 0, -70)
    yourVoteText:SetWidth(426)
    yourVoteText:SetJustifyH("CENTER")
    f.yourVoteText = yourVoteText

    local liveAnonNotice = liveControls:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    liveAnonNotice:SetPoint("BOTTOM", liveControls, "BOTTOM", 0, 14)
    liveAnonNotice:SetWidth(426)
    liveAnonNotice:SetJustifyH("CENTER")
    liveAnonNotice:SetText(GTV.L.VOTE_ANON_NOTICE)

    -- =====================================================================
    -- BOTTOM-LEFT B: TIMED MULTI-DAY POLL STATUS & ABSTAIN BAR
    -- =====================================================================
    local timedControls = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.08, 0.09, 0.14, 0.92 },
        borderColor = { 0.45, 0.38, 0.22, 0.85 },
    })
    timedControls:SetSize(454, 130)
    timedControls:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -8)
    timedControls:Hide()
    f.timedControls = timedControls

    local timedTitle = timedControls:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timedTitle:SetPoint("TOPLEFT", timedControls, "TOPLEFT", 14, -12)
    timedTitle:SetTextColor(1.0, 0.84, 0.30)
    f.timedTitle = timedTitle

    local timedRemText = timedControls:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timedRemText:SetPoint("TOPRIGHT", timedControls, "TOPRIGHT", -14, -14)
    f.timedRemText = timedRemText

    local timedSubText = timedControls:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timedSubText:SetPoint("TOPLEFT", timedTitle, "BOTTOMLEFT", 0, -6)
    timedSubText:SetWidth(426)
    timedSubText:SetJustifyH("LEFT")
    f.timedSubText = timedSubText

    local timedAnonText = timedControls:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timedAnonText:SetPoint("TOPLEFT", timedSubText, "BOTTOMLEFT", 0, -6)
    timedAnonText:SetWidth(426)
    timedAnonText:SetJustifyH("LEFT")
    timedAnonText:SetText(GTV.L.VOTE_ANON_NOTICE)

    local timedSubmitMineBtn = CreateFrame("Button", nil, timedControls, "UIPanelButtonTemplate")
    timedSubmitMineBtn:SetSize(206, 26)
    timedSubmitMineBtn:SetPoint("BOTTOMLEFT", timedControls, "BOTTOMLEFT", 14, 12)
    timedSubmitMineBtn:SetText(GTV.L.TIMED_ADD_DESIGN_BTN)
    ColorBtnText(timedSubmitMineBtn, 1.0, 0.88, 0.35)
    timedSubmitMineBtn:SetScript("OnClick", function()
        GTV:PlaySound("IG_CHARACTER_INFO_TAB", 841)
        SetActiveTab("DESIGN")
    end)
    f.timedSubmitMineBtn = timedSubmitMineBtn

    local timedAbstainBtn = CreateFrame("Button", nil, timedControls, "UIPanelButtonTemplate")
    timedAbstainBtn:SetSize(206, 26)
    timedAbstainBtn:SetPoint("BOTTOMRIGHT", timedControls, "BOTTOMRIGHT", -14, 12)
    timedAbstainBtn:SetText(GTV.L.VOTE_ABSTAIN_BTN)
    timedAbstainBtn:SetScript("OnClick", function()
        local board = GTV.Protocol:GetGuildBoard(true)
        if not board then
            ShowToast(GTV.L.SUGG_NEED_GUILD, 1.0, 0.65, 0.35)
            return
        end
        local scopeId = GTV.Storage:GetBoardScopeId(board)
        local myBallot = GTV.Storage:GetMyBallot(scopeId)
        local newVal = not myBallot.abstained
        if GTV.Protocol:SetTimedPollAbstain(newVal) then
            GTV:PlaySound("IG_MAINMENU_OPTION", 852)
            ShowToast(newVal and GTV.L.TOAST_ABSTAINED or GTV.L.TOAST_UNABSTAINED, 0.85, 0.85, 0.95)
        end
    end)
    f.timedAbstainBtn = timedAbstainBtn

    -- =====================================================================
    -- BOTTOM-LEFT C: DESIGNER CONTROLS (SAVE LOCALLY + SUBMIT TO GUILD!)
    -- =====================================================================
    local designControls = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.08, 0.09, 0.14, 0.92 },
        borderColor = { 0.45, 0.38, 0.22, 0.85 },
    })
    designControls:SetSize(454, 130)
    designControls:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -8)
    designControls:Hide()
    f.designControls = designControls

    local function onDesignStep(varIndex, delta)
        f.model:EnsureReady(false)
        f.model:CycleVariation(varIndex, delta)
        UpdateEditor2DFromModel()
    end

    local labels = { GTV.L.CUST_1, GTV.L.CUST_2, GTV.L.CUST_3, GTV.L.CUST_4, GTV.L.CUST_5 }
    local rowPositions = {
        { x = 8, y = -8, w = 208 },
        { x = 8, y = -38, w = 208 },
        { x = 8, y = -68, w = 208 },
        { x = 232, y = -8, w = 212 },
        { x = 232, y = -38, w = 212 },
    }
    for i = 1, 5 do
        local r = CreateCustomRow(designControls, rowPositions[i].y, i, labels[i], onDesignStep)
        r:ClearAllPoints()
        r:SetSize(rowPositions[i].w, 24)
        r:SetPoint("TOPLEFT", designControls, "TOPLEFT", rowPositions[i].x, rowPositions[i].y)
    end

    local copyBtn = CreateFrame("Button", nil, designControls, "UIPanelButtonTemplate")
    copyBtn:SetSize(104, 22)
    copyBtn:SetPoint("TOPLEFT", designControls, "TOPLEFT", 232, -68)
    copyBtn:SetText(GTV.L.BTN_COPY_LEADER)
    copyBtn:SetScript("OnClick", function()
        local s = GTV.Protocol:GetSession()
        local sel = GetSelectedGuildDesign()
        local target = (s and s.design) or (sel and sel.design)
        if target then
            GTV:PlaySound("IG_MAINMENU_OPTION", 852)
            SyncModelAnd2D(target, 0, 0)
        end
    end)

    local randBtn = CreateFrame("Button", nil, designControls, "UIPanelButtonTemplate")
    randBtn:SetSize(102, 22)
    randBtn:SetPoint("LEFT", copyBtn, "RIGHT", 6, 0)
    randBtn:SetText(GTV.L.BTN_RANDOM)
    randBtn:SetScript("OnClick", function()
        GTV:PlaySound("GS_CHARACTER_CREATION_LOOK", 823)
        f.model:EnsureReady(false)
        for v = 1, 5 do
            local steps = math.random(1, v == 1 and 40 or 12)
            for _ = 1, steps do
                f.model:CycleVariation(v, 1)
            end
        end
        UpdateEditor2DFromModel()
    end)

    local noteBox = CreateFrame("EditBox", "GTVNoteEditBox", designControls, "InputBoxTemplate")
    noteBox:SetSize(196, 22)
    noteBox:SetPoint("BOTTOMLEFT", designControls, "BOTTOMLEFT", 14, 8)
    noteBox:SetAutoFocus(false)
    noteBox:SetMaxLetters(34)
    noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    noteBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.noteBox = noteBox

    local notePlaceholder = noteBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    notePlaceholder:SetPoint("LEFT", noteBox, "LEFT", 6, 0)
    notePlaceholder:SetText(GTV.L.NOTE_PLACEHOLDER)
    noteBox:SetScript("OnTextChanged", function(self)
        notePlaceholder:SetShown(self:GetText() == "")
    end)

    local saveLocalBtn = CreateFrame("Button", nil, designControls, "UIPanelButtonTemplate")
    saveLocalBtn:SetSize(108, 24)
    saveLocalBtn:SetPoint("LEFT", noteBox, "RIGHT", 8, 0)
    saveLocalBtn:SetText(GTV.L.BTN_SAVE_LOCAL)
    saveLocalBtn:SetScript("OnClick", function()
        local design = GTV.TabardSync:ReadModel(f.model)
        if not design then
            GTV:Print(GTV.L.SUGG_NO_DESIGN)
            ShowToast(GTV.L.SUGG_NO_DESIGN, 1.0, 0.65, 0.35)
            return
        end
        local saved = GTV.Storage:SaveDesign(noteBox:GetText(), design)
        if saved then
            GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
            ShowToast(string.format(GTV.L.SAVED_CONFIRMED, saved.name), 0.35, 1.0, 0.45)
            noteBox:SetText("")
            noteBox:ClearFocus()
        end
    end)

    local submitBtn = CreateFrame("Button", nil, designControls, "UIPanelButtonTemplate")
    submitBtn:SetSize(116, 24)
    submitBtn:SetPoint("LEFT", saveLocalBtn, "RIGHT", 6, 0)
    submitBtn:SetText(GTV.L.BTN_SUBMIT_SUGG)
    ColorBtnText(submitBtn, 1.0, 0.88, 0.35)
    submitBtn:SetScript("OnClick", function()
        local design = GTV.TabardSync:ReadModel(f.model)
        if not design then
            GTV:Print(GTV.L.SUGG_NO_DESIGN)
            ShowToast(GTV.L.SUGG_NO_DESIGN, 1.0, 0.65, 0.35)
            return
        end
        local ok, resultOrErr = GTV.Protocol:SubmitGuildDesign(design, noteBox:GetText(), false)
        if ok then
            GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
            ShowToast(GTV.L.SUGG_SENT, 0.35, 1.0, 0.45)
            noteBox:SetText("")
            noteBox:ClearFocus()
            selectedDesignId = resultOrErr
            UI_MemberWindow:Refresh()
        else
            ShowToast(resultOrErr or GTV.L.SUGG_NEED_GUILD, 1.0, 0.55, 0.35)
        end
    end)
    f.submitBtn = submitBtn

    -- =====================================================================
    -- RIGHT COLUMN: UNIFIED GUILD DESIGNS BOARD / SAVED DESIGNS
    -- =====================================================================
    local rightPanel = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.05, 0.06, 0.09, 0.92 },
        borderColor = { 0.45, 0.38, 0.22, 0.85 },
    })
    rightPanel:SetSize(294, 432)
    rightPanel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -80)

    local rightTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightTitle:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 10, -10)
    rightTitle:SetTextColor(1.0, 0.84, 0.30)
    f.rightTitle = rightTitle

    local scrollFrame = CreateFrame("ScrollFrame", "GTVMemberRightScroll", rightPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 6, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -26, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(256, 360)
    scrollFrame:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild

    local emptyRight = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyRight:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -16)
    emptyRight:SetWidth(240)
    emptyRight:SetJustifyH("CENTER")
    f.emptyRight = emptyRight

    win = f
    StyleTabButton(tabLiveBtn, false)
    StyleTabButton(tabTimedBtn, false)
    StyleTabButton(tabDesignBtn, true)
    StyleTabButton(tabSavedBtn, false)
    return f
end

function UI_MemberWindow:RefreshLiveVoteButtons()
    if not win then
        return
    end
    local s = GTV.Protocol:GetSession()
    local sel = GetSelectedGuildDesign()
    local myVote = nil

    if s and not sel then
        myVote = s.myVote
    elseif sel then
        local board = GTV.Protocol:GetGuildBoard(false)
        if board then
            local scopeId = GTV.Storage:GetBoardScopeId(board)
            local myBallot = GTV.Storage:GetMyBallot(scopeId)
            if not myBallot.abstained then
                myVote = myBallot.votes[sel.id]
            end
        end
    end

    if myVote == "UP" then
        win.upBtn:SetBackdropColor(0.14, 0.48, 0.22, 1.0)
        win.upBtn:SetBackdropBorderColor(0.45, 1.0, 0.55, 1.0)
        win.downBtn:SetBackdropColor(0.22, 0.08, 0.08, 0.72)
        win.downBtn:SetBackdropBorderColor(0.55, 0.22, 0.22, 0.7)
        win.yourVoteText:SetText(GTV.L.VOTE_YOUR_UP)
    elseif myVote == "DOWN" then
        win.upBtn:SetBackdropColor(0.08, 0.22, 0.11, 0.72)
        win.upBtn:SetBackdropBorderColor(0.22, 0.55, 0.30, 0.7)
        win.downBtn:SetBackdropColor(0.54, 0.14, 0.14, 1.0)
        win.downBtn:SetBackdropBorderColor(1.0, 0.45, 0.45, 1.0)
        win.yourVoteText:SetText(GTV.L.VOTE_YOUR_DOWN)
    else
        win.upBtn:SetBackdropColor(0.08, 0.28, 0.13, 0.92)
        win.upBtn:SetBackdropBorderColor(0.24, 0.80, 0.38, 0.9)
        win.downBtn:SetBackdropColor(0.30, 0.09, 0.09, 0.92)
        win.downBtn:SetBackdropBorderColor(0.85, 0.25, 0.25, 0.9)
        if s or sel then
            win.yourVoteText:SetText(GTV.L.VOTE_YOUR_NONE)
        else
            win.yourVoteText:SetText(GTV.L.VOTE_SELECT_HINT)
        end
    end
end

local function AcquireRightRow(index)
    local row = rightRowPool[index]
    if row then
        return row
    end
    row = GTV:CreateBackdropFrame(win.scrollChild, nil, {
        bgColor = { 0.10, 0.11, 0.17, 0.92 },
        borderColor = { 0.40, 0.35, 0.22, 0.82 },
        edgeSize = 10,
    })
    row:SetSize(252, 82)

    row.thumb = GTV.TabardSync:Create2DPreview(row, 46, 58)
    row.thumb:SetPoint("LEFT", row, "LEFT", 6, 0)

    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.header:SetPoint("TOPLEFT", row.thumb, "TOPRIGHT", 8, -2)
    row.header:SetWidth(134)
    row.header:SetJustifyH("LEFT")

    row.gmBadge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.gmBadge:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)

    row.note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.note:SetPoint("TOPLEFT", row.header, "BOTTOMLEFT", 0, -2)
    row.note:SetWidth(186)
    row.note:SetJustifyH("LEFT")
    row.note:SetTextColor(0.82, 0.85, 0.92)

    row.btn1 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn1:SetSize(52, 20)
    row.btn1:SetPoint("BOTTOMLEFT", row.thumb, "BOTTOMRIGHT", 8, 2)

    row.btn2 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn2:SetSize(42, 20)
    row.btn2:SetPoint("LEFT", row.btn1, "RIGHT", 3, 0)

    row.btn3 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn3:SetSize(44, 20)
    row.btn3:SetPoint("LEFT", row.btn2, "RIGHT", 3, 0)

    row.btn4 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn4:SetSize(44, 20)
    row.btn4:SetPoint("LEFT", row.btn3, "RIGHT", 3, 0)

    row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.delBtn:SetSize(20, 18)
    row.delBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    row.delBtn:SetText(GTV.L.BTN_DELETE)
    ColorBtnText(row.delBtn, 1.0, 0.45, 0.45)

    rightRowPool[index] = row
    return row
end

local function RefreshRightList()
    if not win then
        return
    end
    for _, row in ipairs(rightRowPool) do
        row:Hide()
    end

    -- SAVED DESIGNS TAB
    if activeTab == "SAVED" then
        local saved = GTV.Storage:GetSavedDesigns()
        win.rightTitle:SetText(string.format(GTV.L.TAB_SAVED, #saved))
        if #saved == 0 then
            win.emptyRight:SetText(GTV.L.SAVED_EMPTY)
            win.emptyRight:Show()
            win.scrollChild:SetHeight(120)
            return
        end
        win.emptyRight:Hide()
        local y = -4
        for i, entry in ipairs(saved) do
            local row = AcquireRightRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", win.scrollChild, "TOPLEFT", 2, y)
            row:SetBackdropBorderColor(0.40, 0.35, 0.22, 0.82)
            row.thumb:SetDesign(entry.design)
            row.header:SetText(entry.name)
            row.gmBadge:SetText("")
            row.note:SetText("")
            row.delBtn:Hide()

            row.btn1:SetSize(60, 20)
            row.btn1:SetText(GTV.L.BTN_LOAD)
            ColorBtnText(row.btn1, 0.95, 0.95, 0.95)
            row.btn1:Show()
            row.btn1:Enable()
            row.btn1:SetScript("OnClick", function()
                GTV:PlaySound("IG_MAINMENU_OPTION", 852)
                SyncModelAnd2D(entry.design, 0, 0)
                ShowToast(string.format(GTV.L.SAVED_LOADED, entry.name), 0.55, 0.85, 1.0)
            end)

            row.btn2:SetSize(88, 20)
            row.btn2:SetText(GTV.L.BTN_SUBMIT_SUGG)
            ColorBtnText(row.btn2, 1.0, 0.88, 0.35)
            row.btn2:Show()
            row.btn2:Enable()
            row.btn2:SetScript("OnClick", function()
                local ok, err = GTV.Protocol:SubmitGuildDesign(entry.design, entry.name, false)
                if ok then
                    GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
                    ShowToast(GTV.L.SUGG_SENT, 0.35, 1.0, 0.45)
                else
                    ShowToast(err or GTV.L.SUGG_NEED_GUILD, 1.0, 0.55, 0.35)
                end
            end)

            row.btn3:SetSize(30, 20)
            row.btn3:SetText(GTV.L.BTN_DELETE)
            ColorBtnText(row.btn3, 1.0, 0.45, 0.45)
            row.btn3:Show()
            row.btn3:Enable()
            row.btn3:SetScript("OnClick", function()
                GTV.Storage:DeleteSavedDesign(entry.id)
                GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
                ShowToast(string.format(GTV.L.SAVED_DELETED, entry.name), 1.0, 0.65, 0.45)
            end)

            row.btn4:Hide()
            row:Show()
            y = y - 86
        end
        win.scrollChild:SetHeight(math.max(120, -y + 8))
        return
    end

    -- UNIFIED GUILD DESIGNS BOARD (Visible to EVERY guild member across Live, Timed & Designer tabs!)
    local designs = GTV.Protocol:GetGuildDesigns()
    win.rightTitle:SetText(string.format(GTV.L.TAB_SUGGESTIONS, #designs))
    if #designs == 0 then
        win.emptyRight:SetText(GTV.L.SUGG_EMPTY)
        win.emptyRight:Show()
        win.scrollChild:SetHeight(120)
        return
    end
    win.emptyRight:Hide()

    local board = GTV.Protocol:GetGuildBoard(false)
    local poll = board and board.timedPoll or nil
    local scopeId = GTV.Storage:GetBoardScopeId(board)
    local myBallot = GTV.Storage:GetMyBallot(scopeId)
    local canVote = GTV.Protocol:IsGuildBoardOpenForChanges()
    -- PRIVACY: ONLY the actual Guild Master sees anonymous vote counts (hidden from regular members & member view in test mode!)
    local showGMCounts = (not GTV.Protocol:IsTestModeActive()) and GTV:IsGuildLeader()

    local y = -4
    for i, d in ipairs(designs) do
        local row = AcquireRightRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win.scrollChild, "TOPLEFT", 2, y)

        local isSelected = (selectedDesignId == d.id)
        local isWinner = poll and poll.winnerDesignId and poll.winnerDesignId == d.id
        if isWinner then
            row:SetBackdropBorderColor(0.98, 0.82, 0.22, 1.0)
        elseif isSelected then
            row:SetBackdropBorderColor(0.35, 0.78, 1.0, 1.0)
        else
            row:SetBackdropBorderColor(0.40, 0.35, 0.22, 0.82)
        end

        row.thumb:SetDesign(d.design)
        row.header:SetText((isWinner and GTV.L.TIMED_WINNER_TAG or "") .. d.authorName)
        row.note:SetText(d.note ~= "" and ("\"" .. d.note .. "\"") or "")

        local canDel = GTV.Protocol:CanDeleteDesign(d)
        if showGMCounts then
            local up, down = GTV.Protocol:GetDesignVotes(d.id)
            row.gmBadge:SetText(string.format(GTV.L.TIMED_GM_COUNTS, up, down))
            row.gmBadge:ClearAllPoints()
            row.gmBadge:SetPoint("TOPRIGHT", row, "TOPRIGHT", canDel and -28 or -8, -8)
        else
            row.gmBadge:SetText("")
        end

        if canDel then
            row.delBtn:Show()
            row.delBtn:SetScript("OnClick", function()
                if selectedDesignId == d.id then
                    selectedDesignId = nil
                end
                GTV.Protocol:DeleteGuildDesign(d.id)
                GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
                ShowToast(GTV.L.SUGG_DELETED, 1.0, 0.65, 0.45)
            end)
        else
            row.delBtn:Hide()
        end

        local myV = (not myBallot.abstained) and myBallot.votes[d.id] or nil

        row.btn1:SetSize(52, 20)
        row.btn1:SetText(GTV.L.BTN_PREVIEW)
        ColorBtnText(row.btn1, isSelected and 0.45 or 0.95, isSelected and 0.88 or 0.95, 1.0)
        row.btn1:Show()
        row.btn1:Enable()
        row.btn1:SetScript("OnClick", function()
            GTV:PlaySound("IG_MAINMENU_OPTION", 852)
            SelectGuildDesign(d)
        end)

        row.btn2:SetSize(42, 20)
        row.btn2:SetText(GTV.L.VOTE_UP_SHORT)
        ColorBtnText(row.btn2, myV == "UP" and 0.30 or 0.85, myV == "UP" and 1.0 or 0.85, myV == "UP" and 0.42 or 0.85)
        row.btn2:Show()
        if canVote then row.btn2:Enable() else row.btn2:Disable() end
        row.btn2:SetScript("OnClick", function()
            local ok, applied = GTV.Protocol:VoteGuildDesign(d.id, "UP")
            if ok then
                GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
                ShowToast(applied == "UP" and GTV.L.TOAST_VOTED_UP or GTV.L.TOAST_VOTE_CLEARED, 0.35, 1.0, 0.45)
            end
        end)

        row.btn3:SetSize(44, 20)
        row.btn3:SetText(GTV.L.VOTE_DOWN_SHORT)
        ColorBtnText(row.btn3, myV == "DOWN" and 1.0 or 0.85, myV == "DOWN" and 0.35 or 0.85, myV == "DOWN" and 0.35 or 0.85)
        row.btn3:Show()
        if canVote then row.btn3:Enable() else row.btn3:Disable() end
        row.btn3:SetScript("OnClick", function()
            local ok, applied = GTV.Protocol:VoteGuildDesign(d.id, "DOWN")
            if ok then
                GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
                ShowToast(applied == "DOWN" and GTV.L.TOAST_VOTED_DOWN or GTV.L.TOAST_VOTE_CLEARED, 1.0, 0.45, 0.45)
            end
        end)

        row.btn4:SetSize(44, 20)
        row.btn4:SetText(GTV.L.BTN_SAVE)
        ColorBtnText(row.btn4, 0.85, 0.88, 0.98)
        row.btn4:Show()
        row.btn4:Enable()
        row.btn4:SetScript("OnClick", function()
            local label = (d.note ~= "" and d.note) or d.authorName
            local saved = GTV.Storage:SaveDesign(label, d.design)
            if saved then
                GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
                ShowToast(string.format(GTV.L.SAVED_CONFIRMED, saved.name), 0.35, 1.0, 0.45)
            end
        end)

        row:Show()
        y = y - 86
    end
    win.scrollChild:SetHeight(math.max(120, -y + 8))
end

function UI_MemberWindow:Refresh()
    if not win or not win:IsShown() then
        return
    end
    local s = GTV.Protocol:GetSession()
    local board = GTV.Protocol:GetGuildBoard(false)
    local poll = board and board.timedPoll or nil
    local timedOpen = GTV.Protocol:IsTimedPollOpen(poll)
    local savedCount = #GTV.Storage:GetSavedDesigns()
    local guildName = GTV:GetGuildName()

    win.tabSavedBtn:SetText(string.format(GTV.L.TAB_SAVED, savedCount))
    win.tabTimedBtn:SetText(timedOpen and GTV.L.TAB_TIMED_ACTIVE or GTV.L.TAB_TIMED)
    win.leaderPanelBtn:SetShown(GTV:IsGuildLeader() or GTV.Protocol:IsTestModeActive())

    if s and s.isTestMode then
        win.statusText:SetText(GTV.L.STATUS_TEST)
    elseif s then
        win.statusText:SetText(string.format(GTV.L.STATUS_LIVE, s.leaderName))
    elseif timedOpen then
        local rem = GTV.Storage:FormatRemaining(poll.endsAt)
        win.statusText:SetText(string.format(GTV.L.TIMED_REMAINING, rem))
    elseif guildName then
        win.statusText:SetText(string.format(GTV.L.STATUS_GUILD_BOARD, guildName))
    else
        win.statusText:SetText(GTV.L.STATUS_NO_GUILD)
    end

    -- Refresh Timed Poll bar
    local designs = GTV.Protocol:GetGuildDesigns()
    local scopeId = board and GTV.Storage:GetBoardScopeId(board) or "default"
    local myBallot = GTV.Storage:GetMyBallot(scopeId)
    local boardOpen = GTV.Protocol:IsGuildBoardOpenForChanges()

    if poll then
        local rem, expired = GTV.Storage:FormatRemaining(poll.endsAt)
        win.timedTitle:SetText(poll.title or GTV.L.TIMED_TITLE_DEFAULT)
        if poll.status == "CLOSED" then
            win.timedRemText:SetText(GTV.L.TIMED_CLOSED)
        elseif expired then
            win.timedRemText:SetText(GTV.L.TIMED_EXPIRED)
        else
            win.timedRemText:SetText(string.format(GTV.L.TIMED_REMAINING, rem))
        end
    else
        win.timedTitle:SetText(GTV.L.TAB_TIMED)
        win.timedRemText:SetText("")
    end

    if myBallot.abstained then
        win.timedSubText:SetText(GTV.L.VOTE_ABSTAINED_BADGE)
        ColorBtnText(win.timedAbstainBtn, 1.0, 0.85, 0.35)
    elseif poll then
        win.timedSubText:SetText(string.format(GTV.L.TIMED_STATS_MEMBER, #designs))
        ColorBtnText(win.timedAbstainBtn, 0.90, 0.90, 0.90)
    else
        win.timedSubText:SetText(GTV.L.TIMED_NONE)
        ColorBtnText(win.timedAbstainBtn, 0.90, 0.90, 0.90)
    end

    if boardOpen then
        win.timedSubmitMineBtn:Enable()
        win.timedAbstainBtn:Enable()
    else
        win.timedSubmitMineBtn:Disable()
        win.timedAbstainBtn:Disable()
    end

    self:RefreshLiveVoteButtons()
    RefreshRightList()
end

function UI_MemberWindow:OpenTab(tabName)
    local f = EnsureWindow()
    f:Show()
    SetActiveTab(tabName or "DESIGN")

    C_Timer.After(0.05, function()
        if not f:IsShown() then return end
        f.model:EnsureReady(false)
        if activeTab == "LIVE" then
            local s = GTV.Protocol:GetSession()
            if s and s.design then
                SyncModelAnd2D(s.design, 0, 0)
            else
                UpdateEditor2DFromModel()
            end
        elseif activeTab == "TIMED" then
            local designs = GTV.Protocol:GetGuildDesigns()
            if designs[1] then
                SelectGuildDesign(designs[1])
            else
                UpdateEditor2DFromModel()
            end
        else
            UpdateEditor2DFromModel()
        end
        self:Refresh()
    end)
end

function UI_MemberWindow:OpenLive()
    self:OpenTab("LIVE")
end

function UI_MemberWindow:IsShown()
    return win and win:IsShown() or false
end

GTV.Protocol:RegisterCallback(function(eventName, arg1, arg2, arg3, arg4)
    if not win or not win:IsShown() then
        return
    end
    if eventName == "DESIGN_UPDATED" then
        local session, varIdx, delta, votesCleared = arg1, arg2, arg3, arg4
        if activeTab == "LIVE" and not selectedDesignId and session and session.design then
            SyncModelAnd2D(session.design, varIdx, delta)
        end
        if votesCleared then
            ShowToast(GTV.L.VOTE_RESET_NOTICE, 1.0, 0.85, 0.35)
        end
        UI_MemberWindow:Refresh()
    elseif eventName == "VOTES_RESET" then
        ShowToast(GTV.L.VOTE_RESET_MANUAL, 1.0, 0.85, 0.35)
        GTV:PlaySound("IG_MAINMENU_OPTION", 852)
        UI_MemberWindow:Refresh()
    elseif eventName == "SESSION_ENDED" then
        if win.returnLiveBtn then
            win.returnLiveBtn:Hide()
        end
        UI_MemberWindow:Refresh()
    else
        UI_MemberWindow:Refresh()
    end
end)

local _, GTV = ...

local UI_MemberWindow = {}
GTV.UI_MemberWindow = UI_MemberWindow

local win
local activeTab = "LIVE" -- "LIVE" | "TIMED" | "DESIGN" | "SAVED"
local previewingLabel = nil
local rightRowPool = {}
local voteResetFlashTimer = nil

local function CreateCustomRow(parent, yOffset, varIndex, labelText, onStep)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(204, 24)
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

local function SyncModelAnd2D(targetDesign, hintVar, hintDelta)
    if not win or not win:IsShown() then
        return
    end
    win.preview2D:SetDesign(targetDesign)
    if targetDesign then
        win.model:EnsureReady()
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

local function SetActiveTab(tabName)
    activeTab = tabName
    previewingLabel = nil
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
    win.previewBanner:Hide()

    if activeTab == "LIVE" then
        local s = GTV.Protocol:GetSession()
        if s and s.design then
            SyncModelAnd2D(s.design, 0, 0)
        end
    elseif activeTab == "TIMED" then
        local poll = GTV.Protocol:GetActiveTimedPoll()
        if poll and poll.designs and poll.designs[1] then
            SyncModelAnd2D(poll.designs[1].design, 0, 0)
        end
    else
        GTV.TabardSync:CancelSeek(win.model)
        win.syncHint:Hide()
        win.model:EnsureReady()
        C_Timer.After(0.03, UpdateEditor2DFromModel)
    end

    UI_MemberWindow:Refresh()
end

local function EnsureWindow()
    if win then
        return win
    end

    local f = GTV:CreateBackdropFrame(UIParent, "GuildTabardVoteMemberWindow", {
        bgColor = { 0.06, 0.07, 0.11, 0.96 },
        borderColor = { 0.82, 0.67, 0.28, 1.0 },
    })
    f:SetSize(784, 522)
    f:SetPoint("CENTER", UIParent, "CENTER", 170, 0)
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

    -- Periodic countdown refresh while open
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
        previewingLabel = nil
        previewBanner:Hide()
        local s = GTV.Protocol:GetSession()
        if s and s.design then
            SyncModelAnd2D(s.design, 0, 0)
        end
        UI_MemberWindow:Refresh()
    end)

    -- =====================================================================
    -- BOTTOM-LEFT A: LIVE ANONYMOUS VOTING (NO OTHER PLAYERS' COUNTS SHOWN!)
    -- =====================================================================
    local liveControls = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.08, 0.09, 0.14, 0.92 },
        borderColor = { 0.45, 0.38, 0.22, 0.85 },
    })
    liveControls:SetSize(454, 128)
    liveControls:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -8)
    f.liveControls = liveControls

    local upBtn = GTV:CreateBackdropFrame(liveControls, nil, {
        bgColor = { 0.08, 0.28, 0.13, 0.92 },
        borderColor = { 0.24, 0.80, 0.38, 0.9 },
        edgeSize = 12,
    })
    upBtn:SetSize(202, 46)
    upBtn:SetPoint("TOPLEFT", liveControls, "TOPLEFT", 14, -14)
    upBtn:EnableMouse(true)

    local upBtnIcon = upBtn:CreateTexture(nil, "ARTWORK")
    upBtnIcon:SetSize(30, 30)
    upBtnIcon:SetPoint("LEFT", upBtn, "LEFT", 12, 0)
    upBtnIcon:SetTexture(GTV.ICON_THUMB_UP)

    local upBtnText = upBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    upBtnText:SetPoint("LEFT", upBtnIcon, "RIGHT", 10, 0)
    upBtnText:SetText(GTV.L.VOTE_UP)
    upBtnText:SetTextColor(0.45, 1.0, 0.55)

    upBtn:SetScript("OnMouseDown", function()
        if not GTV.Protocol:HasActiveSession() then return end
        if voteResetFlashTimer and voteResetFlashTimer.Cancel then
            voteResetFlashTimer:Cancel()
            voteResetFlashTimer = nil
        end
        GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
        GTV.Protocol:SendVote("UP")
    end)
    upBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.45, 1.0, 0.58, 1.0) end)
    upBtn:SetScript("OnLeave", function() UI_MemberWindow:RefreshLiveVoteButtons() end)
    f.upBtn = upBtn

    local downBtn = GTV:CreateBackdropFrame(liveControls, nil, {
        bgColor = { 0.30, 0.09, 0.09, 0.92 },
        borderColor = { 0.85, 0.25, 0.25, 0.9 },
        edgeSize = 12,
    })
    downBtn:SetSize(202, 46)
    downBtn:SetPoint("TOPRIGHT", liveControls, "TOPRIGHT", -14, -14)
    downBtn:EnableMouse(true)

    local downBtnIcon = downBtn:CreateTexture(nil, "ARTWORK")
    downBtnIcon:SetSize(30, 30)
    downBtnIcon:SetPoint("LEFT", downBtn, "LEFT", 12, 0)
    downBtnIcon:SetTexture(GTV.ICON_THUMB_DOWN)

    local downBtnText = downBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    downBtnText:SetPoint("LEFT", downBtnIcon, "RIGHT", 10, 0)
    downBtnText:SetText(GTV.L.VOTE_DOWN)
    downBtnText:SetTextColor(1.0, 0.48, 0.48)

    downBtn:SetScript("OnMouseDown", function()
        if not GTV.Protocol:HasActiveSession() then return end
        if voteResetFlashTimer and voteResetFlashTimer.Cancel then
            voteResetFlashTimer:Cancel()
            voteResetFlashTimer = nil
        end
        GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
        GTV.Protocol:SendVote("DOWN")
    end)
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
    timedControls:SetSize(454, 128)
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
    if timedSubmitMineBtn.GetFontString and timedSubmitMineBtn:GetFontString() then
        timedSubmitMineBtn:GetFontString():SetTextColor(1.0, 0.88, 0.35)
    end
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
        local poll = GTV.Protocol:GetActiveTimedPoll()
        if not poll then return end
        local myBallot = GTV.Storage:GetMyBallot(poll.id)
        GTV.Protocol:SetTimedPollAbstain(not myBallot.abstained)
        GTV:PlaySound("IG_MAINMENU_OPTION", 852)
    end)
    f.timedAbstainBtn = timedAbstainBtn

    -- =====================================================================
    -- BOTTOM-LEFT C: DESIGNER CONTROLS (SAVE LOCALLY + SUBMIT TO GUILD!)
    -- =====================================================================
    local designControls = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.08, 0.09, 0.14, 0.92 },
        borderColor = { 0.45, 0.38, 0.22, 0.85 },
    })
    designControls:SetSize(454, 128)
    designControls:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -8)
    designControls:Hide()
    f.designControls = designControls

    local function onDesignStep(varIndex, delta)
        f.model:EnsureReady()
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
        if s and s.design then
            GTV:PlaySound("IG_MAINMENU_OPTION", 852)
            SyncModelAnd2D(s.design, 0, 0)
        end
    end)

    local randBtn = CreateFrame("Button", nil, designControls, "UIPanelButtonTemplate")
    randBtn:SetSize(102, 22)
    randBtn:SetPoint("LEFT", copyBtn, "RIGHT", 6, 0)
    randBtn:SetText(GTV.L.BTN_RANDOM)
    randBtn:SetScript("OnClick", function()
        GTV:PlaySound("GS_CHARACTER_CREATION_LOOK", 823)
        f.model:EnsureReady()
        for v = 1, 5 do
            local steps = math.random(1, v == 1 and 40 or 12)
            for _ = 1, steps do
                f.model:CycleVariation(v, 1)
            end
        end
        UpdateEditor2DFromModel()
    end)

    -- Bottom row: Name/Note input + Save Locally + Submit to Guild!
    local noteBox = CreateFrame("EditBox", "GTVNoteEditBox", designControls, "InputBoxTemplate")
    noteBox:SetSize(202, 22)
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
    saveLocalBtn:SetSize(106, 24)
    saveLocalBtn:SetPoint("LEFT", noteBox, "RIGHT", 8, 0)
    saveLocalBtn:SetText(GTV.L.BTN_SAVE_LOCAL)
    saveLocalBtn:SetScript("OnClick", function()
        local design = GTV.TabardSync:ReadModel(f.model)
        if not design then
            GTV:Print(GTV.L.SUGG_NO_DESIGN)
            return
        end
        GTV.Storage:SaveDesign(noteBox:GetText(), design)
        GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
    end)

    local submitBtn = CreateFrame("Button", nil, designControls, "UIPanelButtonTemplate")
    submitBtn:SetSize(112, 24)
    submitBtn:SetPoint("LEFT", saveLocalBtn, "RIGHT", 6, 0)
    submitBtn:SetText(GTV.L.BTN_SUBMIT_SUGG)
    if submitBtn.GetFontString and submitBtn:GetFontString() then
        submitBtn:GetFontString():SetTextColor(1.0, 0.88, 0.35)
    end
    submitBtn:SetScript("OnClick", function()
        local design = GTV.TabardSync:ReadModel(f.model)
        if not design then
            GTV:Print(GTV.L.SUGG_NO_DESIGN)
            return
        end
        local note = noteBox:GetText()
        local sent = false
        if GTV.Protocol:IsTimedPollOpen() then
            sent = GTV.Protocol:SubmitTimedPollDesign(design, note, false) or sent
        end
        if GTV.Protocol:HasActiveSession() then
            sent = GTV.Protocol:SendSuggestion(design, note) or sent
        end
        if sent then
            GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
            noteBox:SetText("")
            noteBox:ClearFocus()
        else
            GTV:Print(GTV.L.STATUS_NO_SESSION)
        end
    end)
    f.submitBtn = submitBtn

    -- =====================================================================
    -- RIGHT COLUMN: CONTEXTUAL FEED (LIVE DESIGNS / TIMED DESIGNS / SAVED)
    -- =====================================================================
    local rightPanel = GTV:CreateBackdropFrame(f, nil, {
        bgColor = { 0.05, 0.06, 0.09, 0.92 },
        borderColor = { 0.45, 0.38, 0.22, 0.85 },
    })
    rightPanel:SetSize(294, 430)
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
    StyleTabButton(tabLiveBtn, true)
    StyleTabButton(tabTimedBtn, false)
    StyleTabButton(tabDesignBtn, false)
    StyleTabButton(tabSavedBtn, false)
    return f
end

function UI_MemberWindow:RefreshLiveVoteButtons()
    if not win then
        return
    end
    local s = GTV.Protocol:GetSession()
    local myVote = s and s.myVote or nil

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
        if not voteResetFlashTimer then
            win.yourVoteText:SetText(GTV.L.VOTE_YOUR_NONE)
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

    -- 4 compact action buttons along bottom of row
    row.btn1 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn1:SetSize(56, 20)
    row.btn1:SetPoint("BOTTOMLEFT", row.thumb, "BOTTOMRIGHT", 8, 2)

    row.btn2 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn2:SetSize(44, 20)
    row.btn2:SetPoint("LEFT", row.btn1, "RIGHT", 3, 0)

    row.btn3 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn3:SetSize(46, 20)
    row.btn3:SetPoint("LEFT", row.btn2, "RIGHT", 3, 0)

    row.btn4 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.btn4:SetSize(38, 20)
    row.btn4:SetPoint("LEFT", row.btn3, "RIGHT", 3, 0)

    rightRowPool[index] = row
    return row
end

local function ColorBtnText(btn, r, g, b)
    if btn.GetFontString and btn:GetFontString() then
        btn:GetFontString():SetTextColor(r, g, b)
    end
end

local function RefreshRightList()
    if not win then
        return
    end
    for _, row in ipairs(rightRowPool) do
        row:Hide()
    end

    -- Mode 1: SAVED DESIGNS tab
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
        local canSubmit = GTV.Protocol:HasActiveSession() or GTV.Protocol:IsTimedPollOpen()
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

            row.btn1:SetSize(64, 20)
            row.btn1:SetText(GTV.L.BTN_LOAD)
            ColorBtnText(row.btn1, 0.95, 0.95, 0.95)
            row.btn1:Show()
            row.btn1:Enable()
            row.btn1:SetScript("OnClick", function()
                GTV:PlaySound("IG_MAINMENU_OPTION", 852)
                SyncModelAnd2D(entry.design, 0, 0)
                GTV:Print(string.format(GTV.L.SAVED_LOADED, entry.name))
            end)

            row.btn2:SetSize(84, 20)
            row.btn2:SetText(GTV.L.BTN_SUBMIT_SUGG)
            ColorBtnText(row.btn2, 1.0, 0.88, 0.35)
            row.btn2:Show()
            if canSubmit then row.btn2:Enable() else row.btn2:Disable() end
            row.btn2:SetScript("OnClick", function()
                local ok = false
                if GTV.Protocol:IsTimedPollOpen() then
                    ok = GTV.Protocol:SubmitTimedPollDesign(entry.design, entry.name, false) or ok
                end
                if GTV.Protocol:HasActiveSession() then
                    ok = GTV.Protocol:SendSuggestion(entry.design, entry.name) or ok
                end
                if ok then
                    GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
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
            end)

            row.btn4:Hide()
            row:Show()
            y = y - 86
        end
        win.scrollChild:SetHeight(math.max(120, -y + 8))
        return
    end

    -- Mode 2: TIMED POLL DESIGNS (or DESIGN tab when timed poll is active)
    local poll = GTV.Protocol:GetActiveTimedPoll()
    if activeTab == "TIMED" or (activeTab == "DESIGN" and poll and not GTV.Protocol:HasActiveSession()) then
        local designs = (poll and poll.designs) or {}
        win.rightTitle:SetText(string.format(GTV.L.TAB_SUGGESTIONS, #designs))
        if not poll then
            win.emptyRight:SetText(GTV.L.TIMED_NONE)
            win.emptyRight:Show()
            win.scrollChild:SetHeight(120)
            return
        end
        if #designs == 0 then
            win.emptyRight:SetText(GTV.L.SUGG_EMPTY)
            win.emptyRight:Show()
            win.scrollChild:SetHeight(120)
            return
        end
        win.emptyRight:Hide()

        local isOpen = GTV.Protocol:IsTimedPollOpen(poll)
        local myBallot = GTV.Storage:GetMyBallot(poll.id)
        local isGM = (not GTV.Protocol:IsTestModeActive()) and GTV:IsGuildLeader()
        local y = -4

        for i, d in ipairs(designs) do
            local row = AcquireRightRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", win.scrollChild, "TOPLEFT", 2, y)

            local isWinner = poll.winnerDesignId and poll.winnerDesignId == d.id
            row:SetBackdropBorderColor(isWinner and 0.95 or 0.40, isWinner and 0.78 or 0.35, 0.22, 0.92)
            row.thumb:SetDesign(d.design)
            row.header:SetText((isWinner and GTV.L.TIMED_WINNER_TAG or "") .. d.authorName)
            row.note:SetText(d.note ~= "" and ("\"" .. d.note .. "\"") or "")

            -- PRIVACY: ONLY Guild Master sees vote counts (strictly anonymous)!
            if isGM then
                local up, down = GTV.Protocol:GetTimedDesignVotes(poll, d.id)
                row.gmBadge:SetText(string.format(GTV.L.TIMED_GM_COUNTS, up, down))
            else
                row.gmBadge:SetText("")
            end

            local myV = (not myBallot.abstained) and myBallot.votes[d.id] or nil

            row.btn1:SetSize(56, 20)
            row.btn1:SetText(GTV.L.BTN_PREVIEW)
            ColorBtnText(row.btn1, 0.95, 0.95, 0.95)
            row.btn1:Show()
            row.btn1:Enable()
            row.btn1:SetScript("OnClick", function()
                GTV:PlaySound("IG_MAINMENU_OPTION", 852)
                SyncModelAnd2D(d.design, 0, 0)
            end)

            row.btn2:SetSize(44, 20)
            row.btn2:SetText(GTV.L.VOTE_UP_SHORT)
            ColorBtnText(row.btn2, myV == "UP" and 0.30 or 0.85, myV == "UP" and 1.0 or 0.85, myV == "UP" and 0.42 or 0.85)
            row.btn2:Show()
            if isOpen then row.btn2:Enable() else row.btn2:Disable() end
            row.btn2:SetScript("OnClick", function()
                GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
                GTV.Protocol:VoteTimedDesign(d.id, "UP")
            end)

            row.btn3:SetSize(46, 20)
            row.btn3:SetText(GTV.L.VOTE_DOWN_SHORT)
            ColorBtnText(row.btn3, myV == "DOWN" and 1.0 or 0.85, myV == "DOWN" and 0.35 or 0.85, myV == "DOWN" and 0.35 or 0.85)
            row.btn3:Show()
            if isOpen then row.btn3:Enable() else row.btn3:Disable() end
            row.btn3:SetScript("OnClick", function()
                GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
                GTV.Protocol:VoteTimedDesign(d.id, "DOWN")
            end)

            row.btn4:SetSize(38, 20)
            row.btn4:SetText(GTV.L.BTN_SAVE)
            ColorBtnText(row.btn4, 0.85, 0.85, 0.95)
            row.btn4:Show()
            row.btn4:Enable()
            row.btn4:SetScript("OnClick", function()
                local label = (d.note ~= "" and d.note) or d.authorName
                GTV.Storage:SaveDesign(label, d.design)
                GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
            end)

            row:Show()
            y = y - 86
        end
        win.scrollChild:SetHeight(math.max(120, -y + 8))
        return
    end

    -- Mode 3: LIVE SESSION DESIGNS
    local s = GTV.Protocol:GetSession()
    local list = (s and s.suggestions) or {}
    win.rightTitle:SetText(string.format(GTV.L.TAB_SUGGESTIONS, #list))
    if #list == 0 then
        win.emptyRight:SetText(GTV.L.SUGG_EMPTY)
        win.emptyRight:Show()
        win.scrollChild:SetHeight(120)
        return
    end
    win.emptyRight:Hide()

    local myHash = s and GTV.Storage:GetVoterHash(s.id) or ""
    local isGM = (not GTV.Protocol:IsTestModeActive()) and GTV:IsGuildLeader()
    local y = -4

    for i, sugg in ipairs(list) do
        local row = AcquireRightRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win.scrollChild, "TOPLEFT", 2, y)
        row:SetBackdropBorderColor(0.40, 0.35, 0.22, 0.82)
        row.thumb:SetDesign(sugg.design)
        row.header:SetText(sugg.authorName)
        row.note:SetText(sugg.note ~= "" and ("\"" .. sugg.note .. "\"") or "")

        -- PRIVACY: ONLY Guild Master sees vote counts (strictly anonymous)!
        if isGM then
            local up, down = GTV.Protocol:GetLiveSuggestionCounts(sugg)
            row.gmBadge:SetText(string.format(GTV.L.TIMED_GM_COUNTS, up, down))
        else
            row.gmBadge:SetText("")
        end

        local myV = sugg.votes and sugg.votes[myHash] or nil

        row.btn1:SetSize(56, 20)
        row.btn1:SetText(GTV.L.BTN_PREVIEW)
        ColorBtnText(row.btn1, 0.95, 0.95, 0.95)
        row.btn1:Show()
        row.btn1:Enable()
        row.btn1:SetScript("OnClick", function()
            GTV:PlaySound("IG_MAINMENU_OPTION", 852)
            previewingLabel = sugg.authorName
            win.previewBannerText:SetText(string.format(GTV.L.STATUS_PREVIEWING_SUGG, sugg.authorName))
            win.previewBanner:Show()
            SyncModelAnd2D(sugg.design, 0, 0)
        end)

        row.btn2:SetSize(44, 20)
        row.btn2:SetText(GTV.L.VOTE_UP_SHORT)
        ColorBtnText(row.btn2, myV == "UP" and 0.30 or 0.85, myV == "UP" and 1.0 or 0.85, myV == "UP" and 0.42 or 0.85)
        row.btn2:Show()
        row.btn2:Enable()
        row.btn2:SetScript("OnClick", function()
            GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
            GTV.Protocol:VoteLiveSuggestion(sugg.id, "UP")
        end)

        row.btn3:SetSize(46, 20)
        row.btn3:SetText(GTV.L.VOTE_DOWN_SHORT)
        ColorBtnText(row.btn3, myV == "DOWN" and 1.0 or 0.85, myV == "DOWN" and 0.35 or 0.85, myV == "DOWN" and 0.35 or 0.85)
        row.btn3:Show()
        row.btn3:Enable()
        row.btn3:SetScript("OnClick", function()
            GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
            GTV.Protocol:VoteLiveSuggestion(sugg.id, "DOWN")
        end)

        row.btn4:SetSize(38, 20)
        row.btn4:SetText(GTV.L.BTN_SAVE)
        ColorBtnText(row.btn4, 0.85, 0.85, 0.95)
        row.btn4:Show()
        row.btn4:Enable()
        row.btn4:SetScript("OnClick", function()
            local label = (sugg.note ~= "" and sugg.note) or sugg.authorName
            GTV.Storage:SaveDesign(label, sugg.design)
            GTV:PlaySound("IG_QUEST_LIST_COMPLETE", 878)
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
    local poll = GTV.Protocol:GetActiveTimedPoll()
    local timedOpen = GTV.Protocol:IsTimedPollOpen(poll)
    local savedCount = #GTV.Storage:GetSavedDesigns()

    win.tabSavedBtn:SetText(string.format(GTV.L.TAB_SAVED, savedCount))
    win.tabTimedBtn:SetText(timedOpen and GTV.L.TAB_TIMED_ACTIVE or GTV.L.TAB_TIMED)

    if s and s.isTestMode then
        win.statusText:SetText(GTV.L.STATUS_TEST)
    elseif s then
        win.statusText:SetText(string.format(GTV.L.STATUS_LIVE, s.leaderName))
    elseif timedOpen then
        local rem = GTV.Storage:FormatRemaining(poll.endsAt)
        win.statusText:SetText(string.format(GTV.L.TIMED_REMAINING, rem))
    else
        win.statusText:SetText(GTV.L.STATUS_NO_SESSION)
    end

    if s or timedOpen then
        win.submitBtn:Enable()
    else
        win.submitBtn:Disable()
    end

    -- Refresh Timed Poll controls bar
    if poll then
        local rem, expired = GTV.Storage:FormatRemaining(poll.endsAt)
        local myBallot = GTV.Storage:GetMyBallot(poll.id)
        win.timedTitle:SetText(poll.title or GTV.L.TIMED_TITLE_DEFAULT)
        if poll.status == "CLOSED" then
            win.timedRemText:SetText(GTV.L.TIMED_CLOSED)
        elseif expired then
            win.timedRemText:SetText(GTV.L.TIMED_EXPIRED)
        else
            win.timedRemText:SetText(string.format(GTV.L.TIMED_REMAINING, rem))
        end

        if myBallot.abstained then
            win.timedSubText:SetText(GTV.L.VOTE_ABSTAINED_BADGE)
            ColorBtnText(win.timedAbstainBtn, 1.0, 0.85, 0.35)
        else
            win.timedSubText:SetText(string.format(GTV.L.TIMED_STATS_MEMBER, #(poll.designs or {})))
            ColorBtnText(win.timedAbstainBtn, 0.90, 0.90, 0.90)
        end

        if timedOpen then
            win.timedSubmitMineBtn:Enable()
            win.timedAbstainBtn:Enable()
        else
            win.timedSubmitMineBtn:Disable()
            win.timedAbstainBtn:Disable()
        end
    else
        win.timedTitle:SetText(GTV.L.TAB_TIMED)
        win.timedRemText:SetText("")
        win.timedSubText:SetText(GTV.L.TIMED_NONE)
        win.timedSubmitMineBtn:Disable()
        win.timedAbstainBtn:Disable()
    end

    self:RefreshLiveVoteButtons()
    RefreshRightList()
end

function UI_MemberWindow:OpenTab(tabName)
    local f = EnsureWindow()
    f:Show()
    SetActiveTab(tabName or "LIVE")

    C_Timer.After(0.05, function()
        if not f:IsShown() then
            return
        end
        f.model:EnsureReady()
        if activeTab == "LIVE" then
            local s = GTV.Protocol:GetSession()
            if s and s.design then
                SyncModelAnd2D(s.design, 0, 0)
            else
                UpdateEditor2DFromModel()
            end
        elseif activeTab == "TIMED" then
            local poll = GTV.Protocol:GetActiveTimedPoll()
            if poll and poll.designs and poll.designs[1] then
                SyncModelAnd2D(poll.designs[1].design, 0, 0)
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
        if activeTab == "LIVE" and not previewingLabel and session and session.design then
            SyncModelAnd2D(session.design, varIdx, delta)
        end
        if votesCleared then
            if voteResetFlashTimer and voteResetFlashTimer.Cancel then
                voteResetFlashTimer:Cancel()
            end
            win.yourVoteText:SetText("|cffffcc44" .. GTV.L.VOTE_RESET_NOTICE .. "|r")
            voteResetFlashTimer = C_Timer.NewTimer and C_Timer.NewTimer(4.0, function()
                voteResetFlashTimer = nil
                if win and win:IsShown() then
                    UI_MemberWindow:RefreshLiveVoteButtons()
                end
            end) or nil
        end
        UI_MemberWindow:Refresh()
    elseif eventName == "VOTES_RESET" then
        win.yourVoteText:SetText("|cffffcc44" .. GTV.L.VOTE_RESET_MANUAL .. "|r")
        GTV:PlaySound("IG_MAINMENU_OPTION", 852)
        UI_MemberWindow:Refresh()
    elseif eventName == "SESSION_ENDED" then
        previewingLabel = nil
        if win.previewBanner then
            win.previewBanner:Hide()
        end
        UI_MemberWindow:Refresh()
    else
        UI_MemberWindow:Refresh()
    end
end)

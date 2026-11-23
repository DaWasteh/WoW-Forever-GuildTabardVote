local _, GTV = ...

local UI_Prompt = {}
GTV.UI_Prompt = UI_Prompt

local promptFrame
local deferredInvite = nil
local currentMode = "LIVE" -- "LIVE" | "TIMED"

local function EnsureFrame()
    if promptFrame then
        return promptFrame
    end

    local f = GTV:CreateBackdropFrame(UIParent, "GuildTabardVotePrompt", {
        bgColor = { 0.07, 0.08, 0.12, 0.96 },
        borderColor = { 0.85, 0.70, 0.28, 1.0 },
    })
    f:SetSize(392, 160)
    f:SetPoint("TOP", UIParent, "TOP", 0, -135)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    GTV:AttachDrag(f)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(42, 42)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    icon:SetTexture(GTV.ICON_ADDON)
    f.icon = icon

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
    title:SetPoint("RIGHT", f, "RIGHT", -32, 0)
    title:SetJustifyH("LEFT")
    title:SetText(GTV.L.PROMPT_TITLE)
    title:SetTextColor(1.0, 0.84, 0.30)
    f.title = title

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        UI_Prompt:ChooseAbstain()
    end)

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    body:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    body:SetJustifyH("LEFT")
    body:SetSpacing(3)
    f.body = body

    local joinBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    joinBtn:SetSize(166, 30)
    joinBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
    joinBtn:SetText(GTV.L.PROMPT_JOIN)
    if joinBtn.GetFontString and joinBtn:GetFontString() then
        joinBtn:GetFontString():SetTextColor(0.35, 1.0, 0.45)
    end
    joinBtn:SetScript("OnClick", function()
        UI_Prompt:ChooseJoin()
    end)
    f.joinBtn = joinBtn

    local abstainBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    abstainBtn:SetSize(166, 30)
    abstainBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    abstainBtn:SetText(GTV.L.PROMPT_ABSTAIN)
    abstainBtn:SetScript("OnClick", function()
        UI_Prompt:ChooseAbstain()
    end)
    f.abstainBtn = abstainBtn

    promptFrame = f
    return f
end

function UI_Prompt:ShowInvite(leaderName, sessionId)
    if InCombatLockdown and InCombatLockdown() then
        deferredInvite = { mode = "LIVE", leaderName = leaderName, id = sessionId }
        GTV:Print(string.format(GTV.L.PROMPT_COMBAT_DEFERRED, leaderName))
        return
    end

    deferredInvite = nil
    currentMode = "LIVE"
    local f = EnsureFrame()
    f.targetId = sessionId
    f.title:SetText(GTV.L.PROMPT_TITLE)
    f.body:SetText(string.format(GTV.L.PROMPT_BODY, leaderName))
    f:Show()
    GTV:PlaySound("IG_QUEST_LIST_OPEN", 844)
end

function UI_Prompt:ShowTimedInvite(leaderName, pollId, remainingText)
    if InCombatLockdown and InCombatLockdown() then
        deferredInvite = { mode = "TIMED", leaderName = leaderName, id = pollId, remaining = remainingText }
        GTV:Print(string.format(GTV.L.PROMPT_COMBAT_DEFERRED, leaderName))
        return
    end

    deferredInvite = nil
    currentMode = "TIMED"
    local f = EnsureFrame()
    f.targetId = pollId
    f.title:SetText(GTV.L.PROMPT_TIMED_TITLE)
    f.body:SetText(string.format(GTV.L.PROMPT_TIMED_BODY, leaderName, remainingText or ""))
    f:Show()
    GTV:PlaySound("IG_QUEST_LIST_OPEN", 844)
end

function UI_Prompt:ShowDeferredIfNeeded()
    if not deferredInvite then
        return
    end
    local info = deferredInvite
    deferredInvite = nil
    if info.mode == "TIMED" then
        local poll = GTV.Protocol:GetActiveTimedPoll()
        if poll and poll.id == info.id and GTV.Protocol:IsTimedPollOpen(poll) then
            local rem = GTV.Storage:FormatRemaining(poll.endsAt)
            self:ShowTimedInvite(info.leaderName, info.id, rem)
        end
    else
        local s = GTV.Protocol:GetSession()
        if s and s.id == info.id and s.myDecision == nil then
            self:ShowInvite(info.leaderName, info.id)
        end
    end
end

function UI_Prompt:ChooseJoin()
    if promptFrame then
        promptFrame:Hide()
    end
    GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
    if currentMode == "TIMED" then
        if GTV.UI_MemberWindow then
            GTV.UI_MemberWindow:OpenTab("TIMED")
        end
    else
        GTV.Protocol:SendParticipation("JOIN")
        if GTV.UI_MemberWindow then
            GTV.UI_MemberWindow:OpenTab("LIVE")
        end
    end
end

function UI_Prompt:ChooseAbstain()
    if promptFrame then
        promptFrame:Hide()
    end
    GTV:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
    if currentMode == "TIMED" then
        GTV.Protocol:SetTimedPollAbstain(true)
    else
        GTV.Protocol:SendParticipation("ABSTAIN")
    end
    GTV:Print(GTV.L.STATUS_ABSTAINED_HINT)
end

function UI_Prompt:Hide()
    deferredInvite = nil
    if promptFrame then
        promptFrame:Hide()
    end
end

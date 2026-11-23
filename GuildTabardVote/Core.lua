local ADDON_NAME, GTV = ...

GTV.ADDON_NAME = ADDON_NAME
GTV.VERSION = "0.3.0"
GTV.PREFIX = "GTV1"
GTV.MEDIA_PATH = "Interface\\AddOns\\GuildTabardVote\\Media\\"

GTV.ICON_ADDON = GTV.MEDIA_PATH .. "icon"
GTV.ICON_THUMB_UP = GTV.MEDIA_PATH .. "thumb_up"
GTV.ICON_THUMB_DOWN = GTV.MEDIA_PATH .. "thumb_down"

local DEFAULTS = {
    autoOpenSession = true,
    autoResetVotes = true,
    playSounds = true,
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        end
    end
end

function GTV:Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(GTV.L.PREFIX_CHAT .. tostring(msg))
    end
end

function GTV:PlaySound(soundKitKey, fallbackID)
    if not self.db or not self.db.playSounds then
        return
    end
    if PlaySound then
        local id = (SOUNDKIT and SOUNDKIT[soundKitKey]) or fallbackID
        if id then
            pcall(PlaySound, id)
        end
    end
end

function GTV:GetPlayerKey()
    local name, realm = UnitFullName and UnitFullName("player")
    if not name then
        name = UnitName("player") or "Unknown"
    end
    if not realm or realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
        realm = realm:gsub("%s+", "")
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

function GTV:NormalizeName(name)
    if not name or name == "" then
        return "Unknown"
    end
    if name:find("-", 1, true) then
        return name
    end
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    realm = realm:gsub("%s+", "")
    if realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

function GTV:ShortName(name)
    if not name or name == "" then
        return "Unknown"
    end
    if Ambiguate then
        return Ambiguate(name, "short")
    end
    return name:match("^([^%-]+)") or name
end

function GTV:GetGuildName()
    if IsInGuild and IsInGuild() then
        local g = GetGuildInfo and GetGuildInfo("player")
        if g and g ~= "" then
            return g
        end
    end
    return nil
end

function GTV:IsGuildLeader()
    if not IsInGuild or not IsInGuild() then
        return false
    end
    if IsGuildLeader and IsGuildLeader() then
        return true
    end
    local guildName, _, rankIndex = GetGuildInfo("player")
    if guildName ~= nil and rankIndex == 0 then
        return true
    end
    if C_GuildInfo and C_GuildInfo.GetGuildRankOrder and UnitGUID then
        local guid = UnitGUID("player")
        if guid then
            local ok, order = pcall(C_GuildInfo.GetGuildRankOrder, guid)
            if ok and order == 1 then
                return true
            end
        end
    end
    return false
end

function GTV:CanSeeLeaderVotes()
    if self.Protocol and self.Protocol:IsTestModeActive() then
        return true
    end
    return self:IsGuildLeader()
end

function GTV:CreateBackdropFrame(parent, name, opts)
    opts = opts or {}
    local frameType = opts.frameType or "Frame"
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame(frameType, name, parent or UIParent, template)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = opts.bgFile or "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = opts.edgeFile or "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = opts.tileSize or 16,
            edgeSize = opts.edgeSize or 14,
            insets = opts.insets or { left = 3, right = 3, top = 3, bottom = 3 },
        })
        local bg = opts.bgColor or { 0.06, 0.07, 0.10, 0.94 }
        local bd = opts.borderColor or { 0.78, 0.64, 0.28, 0.9 }
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
    else
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.07, 0.10, 0.94)
    end
    return frame
end

function GTV:AttachDrag(frame, handle)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    local target = handle or frame
    target:EnableMouse(true)
    target:RegisterForDrag("LeftButton")
    target:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    target:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)
end

-- Hook Blizzard's TabardFrame & TabardModel safely (zero taint via hooksecurefunc)
local blizzardHooked = false
local vendorTabardSaved = false

local function IsVendorGuildTabardOpen()
    if not TabardFrame or not TabardFrame:IsShown() then
        return false
    end
    if not TabardModel then
        return false
    end
    if TabardModel.IsGuildTabard then
        local ok, isGuild = pcall(TabardModel.IsGuildTabard, TabardModel)
        if ok and not isGuild then
            return false
        end
    end
    return true
end

function GTV:TryHookBlizzardTabardFrame()
    if blizzardHooked or not TabardFrame or not TabardModel then
        return
    end
    blizzardHooked = true

    TabardFrame:HookScript("OnShow", function()
        vendorTabardSaved = false
        C_Timer.After(0.08, function()
            if not IsVendorGuildTabardOpen() then
                return
            end
            if not GTV:IsGuildLeader() then
                return
            end
            if GTV.Protocol then
                GTV.Protocol:ExitTestMode()
            end
            if GTV.UI_LeaderPanel then
                GTV.UI_LeaderPanel:ShowForVendorFrame()
            end
            if GTV.db and GTV.db.autoOpenSession and GTV.Protocol then
                GTV.Protocol:StartLeaderSession(TabardModel, false, false)
            end
        end)
    end)

    TabardFrame:HookScript("OnHide", function()
        if GTV.Protocol and GTV.Protocol:IsLeaderVendorSession() then
            GTV.Protocol:EndLeaderSession(vendorTabardSaved)
        end
        if GTV.UI_LeaderPanel and GTV.UI_LeaderPanel:IsDockedToVendor() then
            GTV.UI_LeaderPanel:Hide()
        end
        vendorTabardSaved = false
    end)

    if type(TabardCustomization_Left) == "function" then
        hooksecurefunc("TabardCustomization_Left", function(id)
            if GTV.Protocol and GTV.Protocol:IsLeaderVendorSession() and not GTV.TabardSync:IsModelSeeking(TabardModel) then
                GTV.Protocol:OnLeaderModelChanged(TabardModel, id, -1)
            end
        end)
    end
    if type(TabardCustomization_Right) == "function" then
        hooksecurefunc("TabardCustomization_Right", function(id)
            if GTV.Protocol and GTV.Protocol:IsLeaderVendorSession() and not GTV.TabardSync:IsModelSeeking(TabardModel) then
                GTV.Protocol:OnLeaderModelChanged(TabardModel, id, 1)
            end
        end)
    end

    if TabardModel.CycleVariation then
        hooksecurefunc(TabardModel, "CycleVariation", function(model, varIndex, delta)
            if model == TabardModel and GTV.Protocol and GTV.Protocol:IsLeaderVendorSession() then
                if not GTV.TabardSync:IsModelSeeking(TabardModel) then
                    GTV.Protocol:OnLeaderModelChanged(TabardModel, varIndex, delta)
                end
            end
        end)
    end

    if TabardModel.Save then
        hooksecurefunc(TabardModel, "Save", function(model)
            if model == TabardModel and GTV.Protocol and GTV.Protocol:IsLeaderVendorSession() then
                vendorTabardSaved = true
            end
        end)
    end
end

GTV.UPDATE_CMD = "irm https://raw.githubusercontent.com/DaWasteh/WoW-Forever-GuildTabardVote/main/update.ps1 | iex"
GTV.RELEASES_URL = "https://github.com/DaWasteh/WoW-Forever-GuildTabardVote/releases/latest"

local updateFrame
function GTV:ShowUpdatePopup()
    if not updateFrame then
        local f = GTV:CreateBackdropFrame(UIParent, "GuildTabardVoteUpdateFrame", {
            bgColor = { 0.06, 0.07, 0.11, 0.97 },
            borderColor = { 0.85, 0.70, 0.28, 1.0 },
        })
        f:SetSize(486, 206)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        GTV:AttachDrag(f)
        if UISpecialFrames then
            table.insert(UISpecialFrames, "GuildTabardVoteUpdateFrame")
        end

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
        title:SetText(GTV.L.UPDATE_TITLE)
        title:SetTextColor(1.0, 0.84, 0.30)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)

        local ver = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        ver:SetText(string.format(GTV.L.UPDATE_CURRENT, GTV.VERSION))

        local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        info:SetPoint("TOPLEFT", ver, "BOTTOMLEFT", 0, -8)
        info:SetWidth(452)
        info:SetJustifyH("LEFT")
        info:SetText(GTV.L.UPDATE_INFO)

        local cmdBox = CreateFrame("EditBox", "GTVUpdateCmdBox", f, "InputBoxTemplate")
        cmdBox:SetSize(446, 24)
        cmdBox:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 6, -10)
        cmdBox:SetAutoFocus(false)
        cmdBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        cmdBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        f.cmdBox = cmdBox

        local linkLbl = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        linkLbl:SetPoint("TOPLEFT", cmdBox, "BOTTOMLEFT", -6, -10)
        linkLbl:SetText(GTV.L.UPDATE_LINK_LABEL)

        local urlBox = CreateFrame("EditBox", "GTVUpdateUrlBox", f, "InputBoxTemplate")
        urlBox:SetSize(446, 22)
        urlBox:SetPoint("TOPLEFT", linkLbl, "BOTTOMLEFT", 6, -4)
        urlBox:SetAutoFocus(false)
        urlBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        urlBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        f.urlBox = urlBox

        updateFrame = f
    end

    updateFrame.cmdBox:SetText(GTV.UPDATE_CMD)
    updateFrame.urlBox:SetText(GTV.RELEASES_URL)
    updateFrame:Show()
    updateFrame.cmdBox:SetFocus()
    updateFrame.cmdBox:HighlightText()
    GTV:PlaySound("IG_MAINMENU_OPEN", 850)
end

-- Slash command handling
local function HandleSlashCommand(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)") or ""

    if cmd == "help" or cmd == "?" then
        GTV:Print(GTV.L.HELP_HEADER)
        GTV:Print(GTV.L.HELP_OPEN)
        GTV:Print(GTV.L.HELP_START)
        GTV:Print(GTV.L.HELP_STOP)
        GTV:Print(GTV.L.HELP_TEST)
        GTV:Print(GTV.L.HELP_AUTO)
        GTV:Print(GTV.L.HELP_UPDATE)
        return
    end

    if cmd == "update" or cmd == "up" then
        GTV:ShowUpdatePopup()
        return
    end

    if cmd == "auto" then
        GTV.db.autoOpenSession = not GTV.db.autoOpenSession
        GTV:Print(GTV.db.autoOpenSession and GTV.L.AUTO_ENABLED or GTV.L.AUTO_DISABLED)
        return
    end

    if cmd == "test" or cmd == "demo" then
        GTV.Protocol:StartSoloTestSession()
        return
    end

    if cmd == "stop" or cmd == "end" then
        if GTV.Protocol:IsLeading() then
            GTV.Protocol:EndLeaderSession(false)
            if GTV.UI_LeaderPanel then
                GTV.UI_LeaderPanel:Hide()
            end
        else
            GTV:Print(GTV.L.STATUS_NO_SESSION)
        end
        return
    end

    if cmd == "start" then
        if not IsInGuild() then
            GTV:Print(GTV.L.LEADER_NO_GUILD)
            return
        end
        if not GTV:IsGuildLeader() then
            GTV:Print(GTV.L.LEADER_NOT_LEADER)
            return
        end
        GTV.Protocol:ExitTestMode()
        GTV.UI_LeaderPanel:ShowStandalone(false)
        return
    end

    -- Default `/wappen`: exit lingering test mode when opening real guild board
    if GTV.Protocol:IsTestModeActive() and not (GTV.UI_LeaderPanel and GTV.UI_LeaderPanel.IsShown and GTV.UI_LeaderPanel:IsShown()) then
        GTV.Protocol:ExitTestMode()
    end
    if GTV.Protocol:IsLeading() then
        if GTV.Protocol:IsLeaderVendorSession() then
            GTV.UI_LeaderPanel:ShowForVendorFrame()
        else
            GTV.UI_LeaderPanel:ShowStandalone(GTV.Protocol:IsTestModeActive())
        end
        return
    end

    if IsInGuild and IsInGuild() then
        GTV.Protocol:RequestSync()
        GTV.Protocol:SendGuildBoardHello()
    end

    if GTV.Protocol:HasActiveSession() then
        GTV.Protocol:SendParticipation("JOIN")
        GTV.UI_MemberWindow:OpenTab("LIVE")
        return
    end

    local poll = GTV.Protocol:GetActiveTimedPoll()
    if poll and GTV.Protocol:IsTimedPollOpen(poll) then
        GTV.UI_MemberWindow:OpenTab("TIMED")
    else
        GTV.UI_MemberWindow:OpenTab("DESIGN")
    end
end

SLASH_GUILDTABARDVOTE1 = "/wappen"
SLASH_GUILDTABARDVOTE2 = "/gwa"
SLASH_GUILDTABARDVOTE3 = "/gtv"
SLASH_GUILDTABARDVOTE4 = "/guildtabardvote"
SlashCmdList["GUILDTABARDVOTE"] = HandleSlashCommand

function GuildTabardVote_OnAddonCompartmentClick()
    HandleSlashCommand("")
end

function GuildTabardVote_OnAddonCompartmentEnter(_, menuButtonFrame)
    if GameTooltip then
        GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
        GameTooltip:AddLine(GTV.L.ADDON_TITLE, 0.85, 0.70, 0.25)
        GameTooltip:AddLine(GTV.L.COMPARTMENT_TIP_1, 1, 1, 1)
        GameTooltip:AddLine(GTV.L.COMPARTMENT_TIP_2, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end
end

function GuildTabardVote_OnAddonCompartmentLeave()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

-- Bootstrap events
local bootFrame = CreateFrame("Frame")
local lastSyncedGuildKey = nil
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
bootFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
bootFrame:RegisterEvent("GUILD_ROSTER_UPDATE")

local function TrySyncGuildIfReady()
    if not GTV.Storage or not GTV.Protocol then
        return
    end
    local gKey = GTV.Storage:GetGuildKey(false)
    if gKey and gKey ~= lastSyncedGuildKey then
        lastSyncedGuildKey = gKey
        GTV.Protocol:OnLoginSync()
    end
end

bootFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        GuildTabardVoteDB = GuildTabardVoteDB or {}
        CopyDefaults(GuildTabardVoteDB, DEFAULTS)
        GTV.db = GuildTabardVoteDB
        if GTV.Storage then
            GTV.Storage:Init()
        end
    elseif event == "PLAYER_LOGIN" then
        if GTV.Storage then
            GTV.Storage:Init()
        end
        if GTV.Protocol then
            GTV.Protocol:Init()
        end
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            pcall(C_GuildInfo.GuildRoster)
        end
        GTV:TryHookBlizzardTabardFrame()
        C_Timer.After(2, function()
            GTV:TryHookBlizzardTabardFrame()
        end)
        C_Timer.After(3.5, TrySyncGuildIfReady)
    elseif event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
        C_Timer.After(0.5, TrySyncGuildIfReady)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if GTV.UI_Prompt and GTV.UI_Prompt.ShowDeferredIfNeeded then
            GTV.UI_Prompt:ShowDeferredIfNeeded()
        end
    end
end)

local ADDON_NAME, GTV = ...

GTV.ADDON_NAME = ADDON_NAME
GTV.VERSION = "0.1.0"
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

function GTV:IsGuildLeader()
    if not IsInGuild or not IsInGuild() then
        return false
    end
    if IsGuildLeader and IsGuildLeader() then
        return true
    end
    local guildName, _, rankIndex = GetGuildInfo("player")
    return guildName ~= nil and rankIndex == 0
end

-- Helper: true if player is the actual Guild Master OR currently in Solo Test Mode
function GTV:CanSeeLeaderVotes()
    if self.Protocol and self.Protocol:IsTestModeActive() then
        return true
    end
    return self:IsGuildLeader()
end

function GTV:CreateBackdropFrame(parent, name, opts)
    opts = opts or {}
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame("Frame", name, parent or UIParent, template)
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
        GTV.UI_LeaderPanel:ShowStandalone(false)
        return
    end

    -- Default `/wappen`: open active session / timed poll / saved designs
    if GTV.Protocol:IsLeading() then
        if GTV.Protocol:IsLeaderVendorSession() then
            GTV.UI_LeaderPanel:ShowForVendorFrame()
        else
            GTV.UI_LeaderPanel:ShowStandalone(GTV.Protocol:IsTestModeActive())
        end
        return
    end

    if GTV.Protocol:HasActiveSession() then
        GTV.Protocol:SendParticipation("JOIN")
        GTV.UI_MemberWindow:OpenTab("LIVE")
        return
    end

    if IsInGuild() then
        GTV:Print(GTV.L.SYNC_REQUESTED)
        GTV.Protocol:RequestSync()
        GTV.Protocol:SendTimedPollHello()
    end

    local poll = GTV.Protocol:GetActiveTimedPoll()
    if poll then
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

-- Addon Compartment integration
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
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

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
        GTV:TryHookBlizzardTabardFrame()
        C_Timer.After(2, function()
            GTV:TryHookBlizzardTabardFrame()
        end)
        -- Auto-sync timed multi-day guild polls shortly after login
        C_Timer.After(4, function()
            if GTV.Protocol then
                GTV.Protocol:OnLoginSync()
            end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if GTV.UI_Prompt and GTV.UI_Prompt.ShowDeferredIfNeeded then
            GTV.UI_Prompt:ShowDeferredIfNeeded()
        end
    end
end)

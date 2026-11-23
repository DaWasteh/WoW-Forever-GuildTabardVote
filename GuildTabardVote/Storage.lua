local _, GTV = ...

local Storage = {}
GTV.Storage = Storage

function Storage:Init()
    GuildTabardVoteDB = GuildTabardVoteDB or {}
    GuildTabardVoteDB.savedDesigns = GuildTabardVoteDB.savedDesigns or {}
    GuildTabardVoteDB.timedPolls = GuildTabardVoteDB.timedPolls or {}
    GuildTabardVoteDB.voterHashes = GuildTabardVoteDB.voterHashes or {}
    GuildTabardVoteDB.myBallots = GuildTabardVoteDB.myBallots or {}
    GuildTabardVoteDB.promptedPolls = GuildTabardVoteDB.promptedPolls or {}
    GTV.db = GuildTabardVoteDB
end

function Storage:Now()
    if GetServerTime then
        return GetServerTime()
    end
    return time()
end

function Storage:GetGuildKey(isTestMode)
    if isTestMode then
        return "__TEST_GUILD__"
    end
    local guildName = IsInGuild and IsInGuild() and GetGuildInfo("player") or nil
    if not guildName or guildName == "" then
        return nil
    end
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    realm = realm:gsub("%s+", "")
    return guildName .. "-" .. realm
end

-- Generates a persistent random anonymous token per poll/session so votes cannot be traced
-- to a character name while still preventing double-voting!
function Storage:GetVoterHash(scopeId)
    self:Init()
    scopeId = tostring(scopeId or "default")
    local existing = GTV.db.voterHashes[scopeId]
    if existing and existing ~= "" then
        return existing
    end
    local chars = "0123456789abcdef"
    local t = {}
    for i = 1, 10 do
        local idx = math.random(1, #chars)
        t[i] = chars:sub(idx, idx)
    end
    local token = table.concat(t)
    GTV.db.voterHashes[scopeId] = token
    return token
end

-- =========================================================================
-- SAVED DESIGNS (Account-wide library, loadable & submittable anytime)
-- =========================================================================
function Storage:GetSavedDesigns()
    self:Init()
    return GTV.db.savedDesigns
end

function Storage:SaveDesign(name, design)
    self:Init()
    if not design then
        return nil
    end
    local list = GTV.db.savedDesigns
    local cleanName = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if cleanName == "" then
        cleanName = string.format(GTV.L.SAVED_DEFAULT_NAME, #list + 1)
    end
    if #cleanName > 32 then
        cleanName = cleanName:sub(1, 32)
    end

    local entry = {
        id = "sd_" .. tostring(self:Now()) .. "_" .. tostring(math.random(100, 999)),
        name = cleanName,
        design = GTV.TabardSync:CopyDesign(design),
        createdAt = self:Now(),
    }
    table.insert(list, 1, entry)
    GTV:Print(string.format(GTV.L.SAVED_CONFIRMED, cleanName))
    if GTV.Protocol and GTV.Protocol.NotifySavedDesignsChanged then
        GTV.Protocol:NotifySavedDesignsChanged()
    end
    return entry
end

function Storage:DeleteSavedDesign(id)
    self:Init()
    local list = GTV.db.savedDesigns
    for i, entry in ipairs(list) do
        if entry.id == id then
            local name = entry.name
            table.remove(list, i)
            GTV:Print(string.format(GTV.L.SAVED_DELETED, name))
            if GTV.Protocol and GTV.Protocol.NotifySavedDesignsChanged then
                GTV.Protocol:NotifySavedDesignsChanged()
            end
            return true
        end
    end
    return false
end

-- =========================================================================
-- TIMED MULTI-DAY POLLS PERSISTENCE
-- =========================================================================
function Storage:GetTimedPoll(guildKey)
    self:Init()
    if not guildKey then
        return nil
    end
    return GTV.db.timedPolls[guildKey]
end

function Storage:SetTimedPoll(guildKey, poll)
    self:Init()
    if not guildKey then
        return
    end
    GTV.db.timedPolls[guildKey] = poll
end

function Storage:GetMyBallot(pollId)
    self:Init()
    if not pollId then
        return nil
    end
    if not GTV.db.myBallots[pollId] then
        GTV.db.myBallots[pollId] = {
            abstained = false,
            votes = {}, -- [designId] = "UP" | "DOWN"
        }
    end
    return GTV.db.myBallots[pollId]
end

function Storage:WasPollPrompted(pollId)
    self:Init()
    return GTV.db.promptedPolls[pollId] == true
end

function Storage:MarkPollPrompted(pollId)
    self:Init()
    if pollId then
        GTV.db.promptedPolls[pollId] = true
    end
end

function Storage:FormatRemaining(endsAt)
    local now = self:Now()
    local diff = (tonumber(endsAt) or 0) - now
    if diff <= 0 then
        return GTV.L.TIME_FMT_ENDED, true
    end
    local days = math.floor(diff / 86400)
    local hours = math.floor((diff % 86400) / 3600)
    local mins = math.max(1, math.floor((diff % 3600) / 60))
    if days > 0 then
        return string.format(GTV.L.TIME_FMT_DAYS, days, hours), false
    elseif hours > 0 then
        return string.format(GTV.L.TIME_FMT_HOURS, hours, mins), false
    else
        return string.format(GTV.L.TIME_FMT_MINS, mins), false
    end
end

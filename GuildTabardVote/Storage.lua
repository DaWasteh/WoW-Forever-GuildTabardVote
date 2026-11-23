local _, GTV = ...

local Storage = {}
GTV.Storage = Storage

Storage.DEFAULT_BOARD_SCOPE = "BOARD"

function Storage:Init()
    GuildTabardVoteDB = GuildTabardVoteDB or {}
    GuildTabardVoteDB.savedDesigns = GuildTabardVoteDB.savedDesigns or {}
    GuildTabardVoteDB.guildBoards = GuildTabardVoteDB.guildBoards or {}
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
    local guildName = GTV:GetGuildName()
    if not guildName then
        return nil
    end
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    realm = realm:gsub("%s+", "")
    return guildName .. "-" .. realm
end

function Storage:NormalizeScopeId(scopeId)
    if not scopeId or scopeId == "" then
        return self.DEFAULT_BOARD_SCOPE
    end
    -- Migrate any legacy v0.2 "<Guild-Realm>_board" scopes to canonical "BOARD"
    if scopeId:sub(-6) == "_board" then
        return self.DEFAULT_BOARD_SCOPE
    end
    return scopeId
end

-- Generates a persistent random anonymous token per scope so votes cannot be traced
-- to a character name while still preventing double-voting.
function Storage:GetVoterHash(scopeKey)
    self:Init()
    scopeKey = tostring(scopeKey or "default")
    local existing = GTV.db.voterHashes[scopeKey]
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
    GTV.db.voterHashes[scopeKey] = token
    return token
end

-- =========================================================================
-- SAVED DESIGNS (Account-wide personal library, always available!)
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
-- UNIFIED PERSISTENT GUILD DESIGN BOARD
-- =========================================================================
function Storage:GetGuildBoard(guildKey, createIfMissing)
    self:Init()
    if not guildKey then
        return nil
    end
    local board = GTV.db.guildBoards[guildKey]
    if not board then
        if not createIfMissing then
            return nil
        end
        board = {
            guildKey = guildKey,
            designs = {},    -- array of { id, authorName, authorKey, note, design, createdAt }
            deletedIds = {}, -- tombstone map { [designId] = true }
            ballots = {},    -- [scopeId] = { [voterHash] = { rev = num, abstained = bool, votes = { [designId] = "UP"|"DOWN" } } }
            timedPoll = nil, -- nil or { id, title, leaderName, createdAt, endsAt, status, winnerDesignId, keepExisting }
        }
        GTV.db.guildBoards[guildKey] = board
    end
    board.designs = board.designs or {}
    board.deletedIds = board.deletedIds or {}
    board.ballots = board.ballots or {}
    board.designById = {}
    for _, d in ipairs(board.designs) do
        board.designById[d.id] = d
    end

    -- Migrate any legacy "<Guild-Realm>_board" ballot maps into canonical "BOARD"
    for k, v in pairs(board.ballots) do
        if type(k) == "string" and k:sub(-6) == "_board" then
            board.ballots[self.DEFAULT_BOARD_SCOPE] = board.ballots[self.DEFAULT_BOARD_SCOPE] or {}
            for h, b in pairs(v) do
                if not board.ballots[self.DEFAULT_BOARD_SCOPE][h] then
                    board.ballots[self.DEFAULT_BOARD_SCOPE][h] = b
                end
            end
            board.ballots[k] = nil
        end
    end

    return board
end

function Storage:GetBoardScopeId(board)
    if board and board.timedPoll and board.timedPoll.id then
        return board.timedPoll.id
    end
    return self.DEFAULT_BOARD_SCOPE
end

function Storage:GetBallotMap(board, scopeId)
    if not board then
        return {}
    end
    scopeId = self:NormalizeScopeId(scopeId or self:GetBoardScopeId(board))
    board.ballots[scopeId] = board.ballots[scopeId] or {}
    return board.ballots[scopeId]
end

function Storage:GetMyBallotKey(board, scopeId)
    scopeId = self:NormalizeScopeId(scopeId or (board and self:GetBoardScopeId(board)) or self.DEFAULT_BOARD_SCOPE)
    local gk = (board and board.guildKey) or "default"
    return gk .. ":" .. scopeId
end

function Storage:GetMyBallot(scopeKey)
    self:Init()
    scopeKey = tostring(scopeKey or "default")
    if not GTV.db.myBallots[scopeKey] then
        GTV.db.myBallots[scopeKey] = {
            rev = 0,
            abstained = false,
            votes = {}, -- [designId] = "UP" | "DOWN"
        }
    end
    GTV.db.myBallots[scopeKey].votes = GTV.db.myBallots[scopeKey].votes or {}
    GTV.db.myBallots[scopeKey].rev = tonumber(GTV.db.myBallots[scopeKey].rev) or 0
    return GTV.db.myBallots[scopeKey]
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

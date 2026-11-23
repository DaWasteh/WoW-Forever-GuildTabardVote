local _, GTV = ...

local Protocol = {}
GTV.Protocol = Protocol

local MSG_THROTTLE = 0.12
local SUGGESTION_COOLDOWN = 2.0

Protocol.session = nil
Protocol.lastSyncReplyAt = 0
Protocol.lastBoardSyncReplyAt = 0
Protocol.lastSuggestionSentAt = 0
Protocol.pendingUpdate = nil
Protocol.updateTimerActive = false
Protocol.suggestionCounter = 0
Protocol.testModeActive = false

local listeners = {}
local versionNotified = false

function Protocol:RegisterCallback(fn)
    table.insert(listeners, fn)
end

local function FireCallbacks(eventName, ...)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, eventName, ...)
        if not ok and geterrorhandler then
            geterrorhandler()(err)
        end
    end
end

function Protocol:NotifySavedDesignsChanged()
    FireCallbacks("SAVED_DESIGNS_CHANGED")
end

local function SanitizeText(text, maxLen)
    text = tostring(text or "")
    text = text:gsub("|", "/")
    text = text:gsub("[\r\n\t]", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    maxLen = maxLen or 36
    if #text > maxLen then
        text = text:sub(1, maxLen)
    end
    return text
end

local function SerializeDesign(d)
    if not d then
        return "0|0|0|0|0|0"
    end
    return string.format("%d|%d|%d|%d|%d|%d",
        tonumber(d.ub) or 0,
        tonumber(d.lb) or 0,
        tonumber(d.ubo) or 0,
        tonumber(d.lbo) or 0,
        tonumber(d.ue) or 0,
        tonumber(d.le) or 0
    )
end

local function ParseDesign(ub, lb, ubo, lbo, ue, le)
    return {
        ub = tonumber(ub) or 0,
        lb = tonumber(lb) or 0,
        ubo = tonumber(ubo) or 0,
        lbo = tonumber(lbo) or 0,
        ue = tonumber(ue) or 0,
        le = tonumber(le) or 0,
    }
end

local function SplitPipe(str)
    local out = {}
    local start = 1
    while true do
        local pos = str:find("|", start, true)
        if not pos then
            table.insert(out, str:sub(start))
            break
        end
        table.insert(out, str:sub(start, pos - 1))
        start = pos + 1
    end
    return out
end

local function CompareVersions(a, b)
    local function parse(v)
        local p1, p2, p3 = tostring(v or "0.0.0"):match("(%d+)%.?(%d*)%.?(%d*)")
        return tonumber(p1) or 0, tonumber(p2) or 0, tonumber(p3) or 0
    end
    local a1, a2, a3 = parse(a)
    local b1, b2, b3 = parse(b)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

-- Tiny deterministic checksum over designs, tombstones, timed poll, and ALL individual votes
local function ComputeBoardSignature(board)
    if not board then
        return "0:0:0:0:0"
    end
    local parts = {}
    for _, d in ipairs(board.designs) do
        table.insert(parts, "D:" .. tostring(d.id))
    end
    local delCount = 0
    for did in pairs(board.deletedIds) do
        delCount = delCount + 1
        table.insert(parts, "X:" .. tostring(did))
    end
    local scopeId = GTV.Storage:GetBoardScopeId(board)
    local ballots = GTV.Storage:GetBallotMap(board, scopeId)
    local voteEntries = 0
    for hash, b in pairs(ballots) do
        if b.abstained then
            voteEntries = voteEntries + 1
            table.insert(parts, "A:" .. tostring(hash) .. ":" .. tostring(b.rev or 0))
        elseif b.votes then
            for did, v in pairs(b.votes) do
                voteEntries = voteEntries + 1
                table.insert(parts, "V:" .. tostring(hash) .. ":" .. tostring(did) .. ":" .. tostring(v))
            end
        end
    end
    table.sort(parts)
    local h = 5381
    for _, s in ipairs(parts) do
        for i = 1, #s do
            h = (h * 33 + string.byte(s, i)) % 2147483647
        end
    end
    local pollSig = (board.timedPoll and (board.timedPoll.id .. "_" .. tostring(board.timedPoll.status))) or "0"
    return string.format("%d:%d:%d:%s:%d", #board.designs, delCount, voteEntries, pollSig, h)
end

-- Serialize a voter's ballot votes into compact "id1=U,id2=D" chunks <= 170 chars
local function EncodeBallotVotes(votes)
    local items = {}
    if votes then
        for did, v in pairs(votes) do
            if v == "UP" or v == "DOWN" then
                table.insert(items, tostring(did) .. "=" .. (v == "UP" and "U" or "D"))
            end
        end
    end
    table.sort(items)
    local str = table.concat(items, ",")
    if #str <= 170 then
        return { str }
    end
    -- Fallback chunking if a guild has huge number of designs
    local chunks, cur = {}, ""
    for _, item in ipairs(items) do
        if #cur > 0 and (#cur + #item + 1) > 170 then
            table.insert(chunks, cur)
            cur = item
        else
            cur = (#cur > 0) and (cur .. "," .. item) or item
        end
    end
    if #cur > 0 then
        table.insert(chunks, cur)
    end
    return chunks
end

local function DecodeBallotVotes(str)
    local out = {}
    if not str or str == "" then
        return out
    end
    for pair in str:gmatch("[^,]+") do
        local did, code = pair:match("^([^=]+)=([UD])$")
        if did and code then
            out[did] = (code == "U") and "UP" or "DOWN"
        end
    end
    return out
end

function Protocol:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(GTV.PREFIX)
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
        if prefix ~= GTV.PREFIX then
            return
        end
        if channel ~= "GUILD" and channel ~= "WHISPER" then
            return
        end
        Protocol:OnMessageReceived(message, sender, false)
    end)
    self.eventFrame = f
end

function Protocol:IsTestModeActive()
    return self.testModeActive == true or (self.session and self.session.isTestMode == true)
end

function Protocol:ExitTestMode()
    if not self.testModeActive and not (self.session and self.session.isTestMode) then
        return
    end
    self.testModeActive = false
    if self.session and self.session.isTestMode then
        self.session = nil
    end
    FireCallbacks("GUILD_BOARD_CHANGED", self:GetGuildBoard(false))
end

function Protocol:SendGuild(payload)
    if not payload or payload == "" then
        return
    end
    if self:IsTestModeActive() then
        local me = GTV:GetPlayerKey()
        C_Timer.After(0.02, function()
            self:OnMessageReceived(payload, me, true)
        end)
        return
    end

    if not IsInGuild or not IsInGuild() then
        return
    end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, GTV.PREFIX, payload, "GUILD")
    end
end

function Protocol:HasActiveSession()
    return self.session ~= nil
end

function Protocol:IsLeading()
    return self.session ~= nil and self.session.isLeader == true
end

function Protocol:IsLeaderVendorSession()
    return self.session ~= nil and self.session.isLeader == true and self.session.isVendor == true
end

function Protocol:GetSession()
    return self.session
end

local function CreateSessionObject(sessionId, leaderKey, leaderDisplay, autoReset, design, isLeader, isVendor, isTestMode)
    return {
        id = sessionId,
        leaderKey = leaderKey,
        leaderName = leaderDisplay,
        rev = 1,
        autoReset = autoReset and true or false,
        design = GTV.TabardSync:CopyDesign(design),
        isLeader = isLeader and true or false,
        isVendor = isVendor and true or false,
        isTestMode = isTestMode and true or false,
        leaderModel = nil,
        participants = {}, -- [voterHash] = "JOIN" | "ABSTAIN"
        votes = {},        -- [voterHash] = "UP" | "DOWN"
        myDecision = nil,
        myVote = nil,
    }
end

-- =========================================================================
-- UNIFIED PERSISTENT GUILD DESIGN BOARD
-- =========================================================================
function Protocol:GetGuildBoard(createIfMissing)
    local gKey = GTV.Storage:GetGuildKey(self:IsTestModeActive())
    if not gKey then
        return nil
    end
    local board = GTV.Storage:GetGuildBoard(gKey, createIfMissing)
    if board and board.timedPoll and board.timedPoll.status == "ACTIVE" then
        if GTV.Storage:Now() >= (board.timedPoll.endsAt or 0) then
            board.timedPoll.status = "EXPIRED"
        end
    end
    return board
end

function Protocol:GetGuildDesigns()
    local board = self:GetGuildBoard(false)
    return (board and board.designs) or {}
end

function Protocol:GetActiveTimedPoll()
    local board = self:GetGuildBoard(false)
    return board and board.timedPoll or nil
end

function Protocol:IsTimedPollOpen(poll)
    poll = poll or self:GetActiveTimedPoll()
    if not poll then
        return false
    end
    if poll.status ~= "ACTIVE" then
        return false
    end
    return GTV.Storage:Now() < (poll.endsAt or 0)
end

function Protocol:IsGuildBoardOpenForChanges()
    local board = self:GetGuildBoard(true)
    if not board then
        return false, GTV.L.SUGG_NEED_GUILD
    end
    local poll = board.timedPoll
    if poll and (poll.status == "CLOSED" or poll.status == "EXPIRED") then
        return false, GTV.L.TIMED_VOTING_LOCKED
    end
    return true, nil
end

function Protocol:SubmitGuildDesign(design, note, bypassCooldown)
    local okOpen, errMsg = self:IsGuildBoardOpenForChanges()
    if not okOpen then
        GTV:Print(errMsg or GTV.L.SUGG_NEED_GUILD)
        return false, errMsg
    end
    if not design then
        GTV:Print(GTV.L.SUGG_NO_DESIGN)
        return false, GTV.L.SUGG_NO_DESIGN
    end

    local nowTick = GetTime and GetTime() or 0
    if not bypassCooldown and (nowTick - self.lastSuggestionSentAt) < SUGGESTION_COOLDOWN then
        GTV:Print(GTV.L.SUGG_COOLDOWN)
        return false, GTV.L.SUGG_COOLDOWN
    end
    self.lastSuggestionSentAt = nowTick
    self.suggestionCounter = self.suggestionCounter + 1

    local board = self:GetGuildBoard(true)
    local meKey = GTV:GetPlayerKey()
    local meShort = GTV:ShortName(meKey)
    local createdAt = GTV.Storage:Now()
    local designId = "gd_" .. tostring(createdAt) .. "_" .. tostring(math.random(100, 999)) .. "_" .. tostring(self.suggestionCounter)
    local cleanNote = SanitizeText(note, 34)

    self:AddGuildDesignLocal(board, designId, meShort, meKey, createdAt, design, cleanNote)

    self:SendGuild(table.concat({
        "GB_ADD",
        designId,
        SanitizeText(meShort, 24),
        tostring(createdAt),
        SerializeDesign(design),
        cleanNote,
    }, "|"))

    if not bypassCooldown then
        GTV:Print(GTV.L.SUGG_SENT)
    end
    return true, designId
end

function Protocol:AddGuildDesignLocal(board, designId, authorName, authorKey, createdAt, design, note)
    if not board or not designId then
        return false
    end
    if board.deletedIds[designId] or board.designById[designId] then
        return false
    end
    local entry = {
        id = designId,
        authorName = authorName or "Unknown",
        authorKey = authorKey or "",
        createdAt = tonumber(createdAt) or GTV.Storage:Now(),
        note = note or "",
        design = GTV.TabardSync:CopyDesign(design),
    }
    table.insert(board.designs, 1, entry)
    board.designById[designId] = entry
    FireCallbacks("GUILD_BOARD_CHANGED", board, entry)
    return true
end

function Protocol:CanDeleteDesign(entry)
    if not entry then
        return false
    end
    if self:IsTestModeActive() or GTV:IsGuildLeader() then
        return true
    end
    local meKey = GTV:GetPlayerKey()
    local meShort = GTV:ShortName(meKey)
    return (entry.authorKey and entry.authorKey == meKey) or (entry.authorName == meShort)
end

function Protocol:DeleteGuildDesign(designId)
    local board = self:GetGuildBoard(false)
    if not board or not board.designById[designId] then
        return false
    end
    if not self:CanDeleteDesign(board.designById[designId]) then
        return false
    end
    self:RemoveGuildDesignLocal(board, designId)
    self:SendGuild(table.concat({ "GB_DEL", designId }, "|"))
    GTV:Print(GTV.L.SUGG_DELETED)
    return true
end

function Protocol:RemoveGuildDesignLocal(board, designId)
    if not board or not designId then
        return false
    end
    board.deletedIds[designId] = true
    board.designById[designId] = nil
    for i, d in ipairs(board.designs) do
        if d.id == designId then
            table.remove(board.designs, i)
            break
        end
    end
    FireCallbacks("GUILD_BOARD_CHANGED", board)
    return true
end

local function GetVoterHashForBoard(board, scopeId)
    local key = GTV.Storage:GetMyBallotKey(board, scopeId)
    return GTV.Storage:GetVoterHash(key)
end

function Protocol:GetMyCurrentBallot(board)
    board = board or self:GetGuildBoard(false)
    if not board then
        return GTV.Storage:GetMyBallot("default")
    end
    local scopeId = GTV.Storage:GetBoardScopeId(board)
    return GTV.Storage:GetMyBallot(GTV.Storage:GetMyBallotKey(board, scopeId))
end

local function BroadcastSingleBallot(self, scopeId, hash, ballot)
    local rev = tonumber(ballot.rev) or GTV.Storage:Now()
    if ballot.abstained then
        self:SendGuild(table.concat({ "GB_BALLOT", scopeId, hash, tostring(rev), "1", "" }, "|"))
        return
    end
    local chunks = EncodeBallotVotes(ballot.votes)
    if #chunks == 1 then
        self:SendGuild(table.concat({ "GB_BALLOT", scopeId, hash, tostring(rev), "0", chunks[1] }, "|"))
    else
        -- Multi-chunk fallback: send individual GB_VOTE packets after clearing
        self:SendGuild(table.concat({ "GB_BALLOT", scopeId, hash, tostring(rev), "0", chunks[1] }, "|"))
        for i = 2, #chunks do
            local ch = chunks[i]
            C_Timer.After((i - 1) * 0.12, function()
                self:SendGuild(table.concat({ "GB_BALLOT_ADD", scopeId, hash, tostring(rev), ch }, "|"))
            end)
        end
    end
end

-- Cast an anonymous UP/DOWN vote on ANY design on the Guild Board
function Protocol:VoteGuildDesign(designId, vote)
    local okOpen, errMsg = self:IsGuildBoardOpenForChanges()
    if not okOpen then
        GTV:Print(errMsg or GTV.L.TIMED_VOTING_LOCKED)
        return false, nil
    end
    local board = self:GetGuildBoard(true)
    if not board or not board.designById[designId] then
        return false, nil
    end

    local scopeId = GTV.Storage:GetBoardScopeId(board)
    local myBallot = self:GetMyCurrentBallot(board)
    local hash = GetVoterHashForBoard(board, scopeId)
    local ballots = GTV.Storage:GetBallotMap(board, scopeId)

    if myBallot.votes[designId] == vote then
        vote = "NONE"
    end
    myBallot.rev = math.max((myBallot.rev or 0) + 1, GTV.Storage:Now())
    myBallot.abstained = false
    myBallot.votes[designId] = (vote ~= "NONE") and vote or nil

    ballots[hash] = ballots[hash] or { rev = 0, abstained = false, votes = {} }
    ballots[hash].rev = myBallot.rev
    ballots[hash].abstained = false
    ballots[hash].votes = {}
    for k, v in pairs(myBallot.votes) do
        ballots[hash].votes[k] = v
    end

    BroadcastSingleBallot(self, scopeId, hash, ballots[hash])
    FireCallbacks("GUILD_BOARD_CHANGED", board)
    return true, vote
end

function Protocol:SetTimedPollAbstain(abstain)
    local okOpen, errMsg = self:IsGuildBoardOpenForChanges()
    if not okOpen then
        GTV:Print(errMsg or GTV.L.TIMED_VOTING_LOCKED)
        return false
    end
    local board = self:GetGuildBoard(true)
    if not board then
        return false
    end

    local scopeId = GTV.Storage:GetBoardScopeId(board)
    local myBallot = self:GetMyCurrentBallot(board)
    local hash = GetVoterHashForBoard(board, scopeId)
    local ballots = GTV.Storage:GetBallotMap(board, scopeId)

    myBallot.rev = math.max((myBallot.rev or 0) + 1, GTV.Storage:Now())
    myBallot.abstained = abstain and true or false
    if myBallot.abstained then
        wipe(myBallot.votes)
    end

    ballots[hash] = ballots[hash] or { rev = 0, abstained = false, votes = {} }
    ballots[hash].rev = myBallot.rev
    ballots[hash].abstained = myBallot.abstained
    if myBallot.abstained then
        wipe(ballots[hash].votes)
    end

    BroadcastSingleBallot(self, scopeId, hash, ballots[hash])
    FireCallbacks("GUILD_BOARD_CHANGED", board)
    return true
end

-- GM-Only anonymous vote counts per design
function Protocol:GetDesignVotes(designId)
    local up, down = 0, 0
    local board = self:GetGuildBoard(false)
    if not board then
        return up, down
    end
    local scopeId = GTV.Storage:GetBoardScopeId(board)
    local ballots = GTV.Storage:GetBallotMap(board, scopeId)
    for _, b in pairs(ballots) do
        if not b.abstained and b.votes then
            local v = b.votes[designId]
            if v == "UP" then
                up = up + 1
            elseif v == "DOWN" then
                down = down + 1
            end
        end
    end
    return up, down
end

function Protocol:GetBoardStats()
    local designCount, voters, abstained = 0, 0, 0
    local board = self:GetGuildBoard(false)
    if not board then
        return designCount, voters, abstained
    end
    designCount = #board.designs
    local scopeId = GTV.Storage:GetBoardScopeId(board)
    local ballots = GTV.Storage:GetBallotMap(board, scopeId)
    for _, b in pairs(ballots) do
        if b.abstained then
            abstained = abstained + 1
        elseif b.votes and next(b.votes) ~= nil then
            voters = voters + 1
        end
    end
    return designCount, voters, abstained
end

-- Copy existing BOARD ballots into a new keepExisting timed poll scope so zero votes are lost!
local function CarryOverBoardBallots(board, newPollId)
    local src = GTV.Storage:GetBallotMap(board, GTV.Storage.DEFAULT_BOARD_SCOPE)
    local dst = GTV.Storage:GetBallotMap(board, newPollId)
    for h, b in pairs(src) do
        if not dst[h] then
            local copyVotes = {}
            if b.votes then
                for did, v in pairs(b.votes) do
                    if board.designById[did] then
                        copyVotes[did] = v
                    end
                end
            end
            dst[h] = {
                rev = tonumber(b.rev) or 1,
                abstained = b.abstained and true or false,
                votes = copyVotes,
            }
        end
    end

    -- Also carry over local player's own ballot & hash
    local oldMy = GTV.Storage:GetMyBallot(GTV.Storage:GetMyBallotKey(board, GTV.Storage.DEFAULT_BOARD_SCOPE))
    local newMy = GTV.Storage:GetMyBallot(GTV.Storage:GetMyBallotKey(board, newPollId))
    if next(newMy.votes) == nil and not newMy.abstained then
        newMy.abstained = oldMy.abstained and true or false
        newMy.rev = oldMy.rev or 1
        for did, v in pairs(oldMy.votes) do
            if board.designById[did] then
                newMy.votes[did] = v
            end
        end
    end
end

-- =========================================================================
-- TIMED MULTI-DAY POLLS
-- =========================================================================
function Protocol:CreateTimedPoll(title, durationSeconds, initialDesign, keepExisting)
    local isTest = self:IsTestModeActive()
    if not isTest then
        if not IsInGuild() then
            GTV:Print(GTV.L.LEADER_NO_GUILD)
            return nil
        end
        if not GTV:IsGuildLeader() then
            GTV:Print(GTV.L.LEADER_NOT_LEADER)
            return nil
        end
    end

    local board = self:GetGuildBoard(true)
    if not board then
        return nil
    end

    local keep = (keepExisting ~= false)
    if not keep then
        for _, d in ipairs(board.designs) do
            board.deletedIds[d.id] = true
        end
        wipe(board.designs)
        wipe(board.designById)
    end

    local now = GTV.Storage:Now()
    durationSeconds = math.max(300, tonumber(durationSeconds) or (3 * 86400))
    local cleanTitle = SanitizeText(title, 34)
    if cleanTitle == "" then
        cleanTitle = GTV.L.TIMED_TITLE_DEFAULT
    end

    local meShort = GTV:ShortName(GTV:GetPlayerKey())
    local pollId = "tp_" .. tostring(now) .. "_" .. tostring(math.random(100, 999))
    board.timedPoll = {
        id = pollId,
        title = cleanTitle,
        leaderName = meShort,
        createdAt = now,
        endsAt = now + durationSeconds,
        status = "ACTIVE",
        winnerDesignId = nil,
        keepExisting = keep,
    }
    if keep then
        CarryOverBoardBallots(board, pollId)
    end
    GTV.Storage:MarkPollPrompted(pollId)

    self:SendGuild(table.concat({
        "TP_META",
        pollId,
        tostring(now),
        tostring(now + durationSeconds),
        "ACTIVE",
        SanitizeText(meShort, 24),
        cleanTitle,
        keep and "1" or "0",
    }, "|"))

    if initialDesign then
        self:SubmitGuildDesign(initialDesign, cleanTitle, true)
    end

    local remText = GTV.Storage:FormatRemaining(board.timedPoll.endsAt)
    GTV:Print(string.format(GTV.L.TIMED_STARTED_CHAT, remText))
    FireCallbacks("GUILD_BOARD_CHANGED", board)
    return board.timedPoll
end

function Protocol:CloseTimedPoll(winnerDesignId)
    local board = self:GetGuildBoard(false)
    if not board or not board.timedPoll then
        return
    end
    if not self:IsTestModeActive() and not GTV:IsGuildLeader() then
        return
    end
    local poll = board.timedPoll
    poll.status = "CLOSED"
    if winnerDesignId and winnerDesignId ~= "" then
        poll.winnerDesignId = winnerDesignId
    else
        local bestId, bestScore = nil, -999999
        for _, d in ipairs(board.designs) do
            local up, down = self:GetDesignVotes(d.id)
            if (up - down) > bestScore then
                bestScore = up - down
                bestId = d.id
            end
        end
        poll.winnerDesignId = bestId
    end
    self:SendGuild(table.concat({ "TP_CLOSE", poll.id, poll.winnerDesignId or "" }, "|"))
    GTV:Print(GTV.L.TIMED_ENDED_CHAT)
    FireCallbacks("GUILD_BOARD_CHANGED", board)
end

function Protocol:AnnounceTimedPollWinner()
    local board = self:GetGuildBoard(false)
    if not board or #board.designs == 0 then
        return
    end
    local poll = board.timedPoll
    local winner = poll and poll.winnerDesignId and board.designById[poll.winnerDesignId]
    if not winner then
        local best, bestScore = nil, -999999
        for _, d in ipairs(board.designs) do
            local up, down = self:GetDesignVotes(d.id)
            if (up - down) > bestScore then
                bestScore = up - down
                best = d
            end
        end
        winner = best
    end
    if not winner then
        return
    end
    local label = (winner.note and winner.note ~= "") and winner.note or winner.id
    local text = string.format(GTV.L.TIMED_WINNER_CHAT, label, winner.authorName)
    if not self:IsTestModeActive() and IsInGuild() and SendChatMessage then
        pcall(SendChatMessage, "[GuildTabardVote] " .. text, "GUILD")
    else
        GTV:Print(text)
    end
end

-- Checksum-based peer-to-peer sync: detects ANY difference in designs, deletions, or individual votes!
function Protocol:SendGuildBoardHello()
    if not self:IsTestModeActive() and not (IsInGuild and IsInGuild()) then
        return
    end
    local board = self:GetGuildBoard(true)
    local sig = ComputeBoardSignature(board)
    self:SendGuild(table.concat({ "GB_HELLO", sig, GTV.VERSION }, "|"))
end

function Protocol:BroadcastGuildBoardSnapshot(board)
    if not board then
        return
    end
    local now = GetTime and GetTime() or 0
    if (now - self.lastBoardSyncReplyAt) < 2.0 then
        return
    end
    self.lastBoardSyncReplyAt = now

    local delay = 0.05
    if board.timedPoll then
        local p = board.timedPoll
        self:SendGuild(table.concat({
            "TP_META",
            p.id,
            tostring(p.createdAt),
            tostring(p.endsAt),
            p.status,
            SanitizeText(p.leaderName, 24),
            SanitizeText(p.title, 34),
            p.keepExisting == false and "0" or "1",
        }, "|"))
        delay = delay + 0.14
    end

    for _, d in ipairs(board.designs) do
        local entry = d
        C_Timer.After(delay, function()
            self:SendGuild(table.concat({
                "GB_ADD",
                entry.id,
                SanitizeText(entry.authorName, 24),
                tostring(entry.createdAt or 0),
                SerializeDesign(entry.design),
                SanitizeText(entry.note, 34),
            }, "|"))
        end)
        delay = delay + 0.12
    end

    -- Sync deletions (tombstones, capped to last 20 to avoid spam)
    local delSent = 0
    for did in pairs(board.deletedIds) do
        if delSent >= 20 then break end
        delSent = delSent + 1
        local idToDel = did
        C_Timer.After(delay, function()
            self:SendGuild(table.concat({ "GB_DEL", idToDel }, "|"))
        end)
        delay = delay + 0.08
    end

    -- Sync all anonymous ballots in compact 1-packet-per-voter format
    local scopeId = GTV.Storage:GetBoardScopeId(board)
    local ballots = GTV.Storage:GetBallotMap(board, scopeId)
    for hash, b in pairs(ballots) do
        local h, ballot = hash, b
        C_Timer.After(delay, function()
            BroadcastSingleBallot(self, scopeId, h, ballot)
        end)
        delay = delay + 0.12
    end

    if board.timedPoll and board.timedPoll.status == "CLOSED" then
        local p = board.timedPoll
        C_Timer.After(delay, function()
            self:SendGuild(table.concat({ "TP_CLOSE", p.id, p.winnerDesignId or "" }, "|"))
        end)
    end
end

function Protocol:OnLoginSync()
    if not IsInGuild or not IsInGuild() then
        return
    end
    self:SendGuildBoardHello()
    local poll = self:GetActiveTimedPoll()
    if poll and self:IsTimedPollOpen(poll) and not GTV.Storage:WasPollPrompted(poll.id) and not GTV:IsGuildLeader() then
        GTV.Storage:MarkPollPrompted(poll.id)
        local rem = GTV.Storage:FormatRemaining(poll.endsAt)
        if GTV.UI_Prompt then
            GTV.UI_Prompt:ShowTimedInvite(poll.leaderName, poll.id, rem)
        end
    end
end

-- =========================================================================
-- LIVE SESSION (GUILD LEADER AT TABARD REGISTRAR OR /wappen start)
-- =========================================================================
function Protocol:StartLeaderSession(model, isStandalone, isTestMode)
    if not isTestMode then
        if not IsInGuild() then
            GTV:Print(GTV.L.LEADER_NO_GUILD)
            return false
        end
        if not GTV:IsGuildLeader() then
            GTV:Print(GTV.L.LEADER_NOT_LEADER)
            return false
        end
    end

    self.testModeActive = isTestMode and true or false
    local design = GTV.TabardSync:ReadModel(model) or { ub = 0, lb = 0, ubo = 0, lbo = 0, ue = 0, le = 0 }
    local meKey = GTV:GetPlayerKey()
    local meShort = GTV:ShortName(meKey)
    local sessionId = tostring(GTV.Storage:Now()) .. "_" .. tostring(math.random(100, 999))
    local autoReset = GTV.db and GTV.db.autoResetVotes ~= false

    self.session = CreateSessionObject(sessionId, meKey, meShort, autoReset, design, true, not isStandalone, isTestMode)
    self.session.leaderModel = model
    local myHash = GTV.Storage:GetVoterHash(sessionId)
    self.session.participants[myHash] = "JOIN"
    self.session.myDecision = "JOIN"

    self:SendGuild(table.concat({
        "OPEN",
        sessionId,
        SanitizeText(meShort, 24),
        autoReset and "1" or "0",
        SerializeDesign(design),
    }, "|"))

    if not isTestMode then
        GTV:Print(GTV.L.LEADER_SESSION_STARTED)
        self:SendGuildBoardHello()
    end
    FireCallbacks("SESSION_STARTED", self.session)
    return true
end

function Protocol:ReinviteGuild()
    if not self:IsLeading() then
        return
    end
    local s = self.session
    local design = (s.leaderModel and GTV.TabardSync:ReadModel(s.leaderModel)) or s.design
    s.design = GTV.TabardSync:CopyDesign(design) or s.design
    self:SendGuild(table.concat({
        "OPEN",
        s.id,
        SanitizeText(s.leaderName, 24),
        s.autoReset and "1" or "0",
        SerializeDesign(s.design),
    }, "|"))
end

function Protocol:SetAutoReset(enabled)
    GTV.db.autoResetVotes = enabled and true or false
    if self:IsLeading() then
        self.session.autoReset = GTV.db.autoResetVotes
        local s = self.session
        self:SendGuild(table.concat({
            "SYNC_STATE",
            s.id,
            SanitizeText(s.leaderName, 24),
            tostring(s.rev),
            s.autoReset and "1" or "0",
            SerializeDesign(s.design),
        }, "|"))
        FireCallbacks("STATE_CHANGED", s)
    end
end

function Protocol:EndLeaderSession(wasSaved)
    if not self:IsLeading() then
        return
    end
    local s = self.session
    self:SendGuild(table.concat({ "CLOSE", s.id, wasSaved and "1" or "0" }, "|"))
    self.pendingUpdate = nil
    self.session = nil
    if s.isTestMode then
        self.testModeActive = false
    else
        GTV:Print(wasSaved and string.format(GTV.L.STATUS_SAVED, s.leaderName) or GTV.L.LEADER_SESSION_STOPPED)
    end
    FireCallbacks("SESSION_ENDED", wasSaved, s.leaderName)
end

function Protocol:OnLeaderModelChanged(model, varIndex, delta, forceImmediate)
    if not self:IsLeading() then
        return
    end
    self.pendingUpdate = {
        model = model,
        varIndex = tonumber(varIndex) or 0,
        delta = tonumber(delta) or 0,
    }

    local function flush()
        self.updateTimerActive = false
        local p = self.pendingUpdate
        self.pendingUpdate = nil
        if not p or not self:IsLeading() then
            return
        end
        local design = GTV.TabardSync:ReadModel(p.model)
        if not design then
            return
        end
        local s = self.session
        if GTV.TabardSync:DesignsEqual(s.design, design) then
            return
        end
        s.design = design
        s.rev = s.rev + 1
        if s.autoReset then
            wipe(s.votes)
            s.myVote = nil
        end

        self:SendGuild(table.concat({
            "UPDATE",
            s.id,
            tostring(s.rev),
            tostring(p.varIndex),
            tostring(p.delta),
            SerializeDesign(design),
        }, "|"))
        FireCallbacks("DESIGN_UPDATED", s, p.varIndex, p.delta, s.autoReset)
    end

    if forceImmediate then
        flush()
    elseif not self.updateTimerActive then
        self.updateTimerActive = true
        C_Timer.After(MSG_THROTTLE, flush)
    end
end

function Protocol:ResetVotes()
    if not self:IsLeading() then
        return
    end
    local s = self.session
    s.rev = s.rev + 1
    wipe(s.votes)
    s.myVote = nil
    self:SendGuild(table.concat({ "RESETV", s.id, tostring(s.rev) }, "|"))
    FireCallbacks("VOTES_RESET", s, true)
end

function Protocol:ApplyDesignToLeaderModel(design, onDone)
    local model = nil
    if self.session and self.session.leaderModel then
        model = self.session.leaderModel
    elseif TabardFrame and TabardFrame:IsShown() and TabardModel then
        model = TabardModel
    elseif GTV.UI_LeaderPanel and GTV.UI_LeaderPanel.GetActiveModel then
        model = GTV.UI_LeaderPanel:GetActiveModel()
    end
    if not model or not design then
        return false
    end
    if model.EnsureReady then
        model:EnsureReady(false)
    end
    GTV.TabardSync:SeekModel(model, design, nil, nil, function(ok)
        if self:IsLeading() then
            self:OnLeaderModelChanged(model, 0, 0, true)
        end
        GTV:Print(GTV.L.SUGG_APPLIED)
        if onDone then
            onDone(ok)
        end
    end)
    return true
end

function Protocol:SendParticipation(status)
    local s = self.session
    if not s then
        return
    end
    local hash = GTV.Storage:GetVoterHash(s.id)
    s.myDecision = status
    if status == "LEAVE" then
        s.participants[hash] = nil
        s.votes[hash] = nil
        s.myVote = nil
    else
        s.participants[hash] = status
        if status == "ABSTAIN" then
            s.votes[hash] = nil
            s.myVote = nil
        end
    end
    self:SendGuild(table.concat({ "PART", s.id, hash, status }, "|"))
    FireCallbacks("VOTES_CHANGED", s)
end

function Protocol:SendVote(vote)
    local s = self.session
    if not s then
        return false, nil
    end
    local hash = GTV.Storage:GetVoterHash(s.id)
    if s.myVote == vote then
        vote = "NONE"
    end
    s.participants[hash] = "JOIN"
    s.myDecision = "JOIN"
    if vote == "NONE" then
        s.votes[hash] = nil
        s.myVote = nil
    else
        s.votes[hash] = vote
        s.myVote = vote
    end
    self:SendGuild(table.concat({ "VOTE", s.id, tostring(s.rev), hash, vote }, "|"))
    FireCallbacks("VOTES_CHANGED", s)
    return true, vote
end

function Protocol:RequestSync()
    local sid = self.session and self.session.id or "0"
    self:SendGuild(table.concat({ "SYNC_REQ", sid }, "|"))
end

function Protocol:GetVoteCounts()
    local up, down, abstain, active = 0, 0, 0, 0
    local s = self.session
    if not s then
        return up, down, abstain, active
    end
    for hash, status in pairs(s.participants) do
        if status == "ABSTAIN" then
            abstain = abstain + 1
        elseif status == "JOIN" then
            active = active + 1
        end
    end
    for hash, v in pairs(s.votes) do
        if not s.participants[hash] then
            active = active + 1
        end
        if v == "UP" then
            up = up + 1
        elseif v == "DOWN" then
            down = down + 1
        end
    end
    return up, down, abstain, active
end

-- Apply an incoming ballot onto canonical scope (and mirror BOARD -> active keepExisting poll if needed)
local function ApplyIncomingBallot(board, rawScopeId, hash, rev, abstained, votesTable, mergeOnly)
    local scopeId = GTV.Storage:NormalizeScopeId(rawScopeId)
    local targetScopes = { scopeId }
    if scopeId == GTV.Storage.DEFAULT_BOARD_SCOPE and board.timedPoll and board.timedPoll.id and board.timedPoll.keepExisting ~= false then
        table.insert(targetScopes, board.timedPoll.id)
    end

    for _, sid in ipairs(targetScopes) do
        local ballots = GTV.Storage:GetBallotMap(board, sid)
        local existing = ballots[hash]
        local existingRev = (existing and tonumber(existing.rev)) or 0
        if (not existing) or (rev >= existingRev) or mergeOnly then
            if not existing or not mergeOnly then
                ballots[hash] = {
                    rev = math.max(rev, existingRev),
                    abstained = abstained and true or false,
                    votes = {},
                }
            end
            if not ballots[hash].abstained and votesTable then
                for did, v in pairs(votesTable) do
                    ballots[hash].votes[did] = v
                end
            end
        end
    end
end

-- =========================================================================
-- INCOMING PROTOCOL DISPATCHER
-- =========================================================================
function Protocol:OnMessageReceived(payload, rawSender, isLocalTestEcho)
    local parts = SplitPipe(payload)
    local cmd = parts[1]
    if not cmd then
        return
    end

    local senderKey = GTV:NormalizeName(rawSender)
    local senderShort = GTV:ShortName(senderKey)
    local myKey = GTV:GetPlayerKey()
    local isSelf = (senderKey == myKey)

    -- ---------------- GUILD DESIGN BOARD MESSAGES ----------------
    if cmd == "GB_ADD" then
        local designId = parts[2]
        local authorName = (parts[3] and parts[3] ~= "") and parts[3] or senderShort
        local createdAt = tonumber(parts[4]) or GTV.Storage:Now()
        local design = ParseDesign(parts[5], parts[6], parts[7], parts[8], parts[9], parts[10])
        local note = parts[11] or ""
        if isSelf then return end
        local board = self:GetGuildBoard(true)
        if board and self:AddGuildDesignLocal(board, designId, authorName, senderKey, createdAt, design, note) then
            GTV:PlaySound("IG_QUEST_LIST_OPEN", 844)
            GTV:Print(string.format(GTV.L.SUGG_RECEIVED, authorName))
        end

    elseif cmd == "GB_DEL" then
        local designId = parts[2]
        if isSelf or not designId then return end
        local board = self:GetGuildBoard(true)
        if board then
            self:RemoveGuildDesignLocal(board, designId)
        end

    elseif cmd == "GB_BALLOT" then
        local scopeId = parts[2]
        local hash = parts[3]
        local rev = tonumber(parts[4]) or 1
        local abstained = (parts[5] == "1")
        local encodedVotes = parts[6] or ""
        if isSelf or not scopeId or not hash then return end
        local board = self:GetGuildBoard(true)
        if not board then return end
        ApplyIncomingBallot(board, scopeId, hash, rev, abstained, DecodeBallotVotes(encodedVotes), false)
        FireCallbacks("GUILD_BOARD_CHANGED", board)

    elseif cmd == "GB_BALLOT_ADD" then
        local scopeId = parts[2]
        local hash = parts[3]
        local rev = tonumber(parts[4]) or 1
        local encodedVotes = parts[5] or ""
        if isSelf or not scopeId or not hash then return end
        local board = self:GetGuildBoard(true)
        if not board then return end
        ApplyIncomingBallot(board, scopeId, hash, rev, false, DecodeBallotVotes(encodedVotes), true)
        FireCallbacks("GUILD_BOARD_CHANGED", board)

    -- Backwards compatibility with v0.2 individual GB_VOTE / GB_ABSTAIN messages!
    elseif cmd == "GB_VOTE" then
        local scopeId, hash, designId, vote = parts[2], parts[3], parts[4], parts[5]
        if isSelf or not scopeId or not hash or not designId then return end
        local board = self:GetGuildBoard(true)
        if not board then return end
        local normScope = GTV.Storage:NormalizeScopeId(scopeId)
        local targetScopes = { normScope }
        if normScope == GTV.Storage.DEFAULT_BOARD_SCOPE and board.timedPoll and board.timedPoll.id and board.timedPoll.keepExisting ~= false then
            table.insert(targetScopes, board.timedPoll.id)
        end
        for _, sid in ipairs(targetScopes) do
            local ballots = GTV.Storage:GetBallotMap(board, sid)
            ballots[hash] = ballots[hash] or { rev = 0, abstained = false, votes = {} }
            ballots[hash].abstained = false
            ballots[hash].votes[designId] = (vote == "UP" or vote == "DOWN") and vote or nil
        end
        FireCallbacks("GUILD_BOARD_CHANGED", board)

    elseif cmd == "GB_ABSTAIN" then
        local scopeId, hash, flag = parts[2], parts[3], parts[4]
        if isSelf or not scopeId or not hash then return end
        local board = self:GetGuildBoard(true)
        if not board then return end
        local normScope = GTV.Storage:NormalizeScopeId(scopeId)
        local ballots = GTV.Storage:GetBallotMap(board, normScope)
        ballots[hash] = ballots[hash] or { rev = 0, abstained = false, votes = {} }
        ballots[hash].abstained = (flag == "1")
        if ballots[hash].abstained then
            wipe(ballots[hash].votes)
        end
        FireCallbacks("GUILD_BOARD_CHANGED", board)

    elseif cmd == "GB_HELLO" then
        if isSelf then return end
        -- Support both v0.3 ("GB_HELLO|<sig>|<version>") and v0.2 ("GB_HELLO|<d>|<p>|<b>|<version>")
        local remoteSig, remoteVersion
        if parts[5] then
            remoteSig = "LEGACY"
            remoteVersion = parts[5]
        else
            remoteSig = parts[2] or ""
            remoteVersion = parts[3]
        end
        if remoteVersion and not versionNotified and CompareVersions(remoteVersion, GTV.VERSION) then
            versionNotified = true
            GTV:Print(string.format(GTV.L.UPDATE_NEWER_FOUND, remoteVersion))
        end
        local board = self:GetGuildBoard(false)
        if not board then return end
        local localSig = ComputeBoardSignature(board)
        local hasData = (#board.designs > 0) or (board.timedPoll ~= nil) or (next(GTV.Storage:GetBallotMap(board)) ~= nil)
        if hasData and remoteSig ~= localSig then
            local jitter = GTV:IsGuildLeader() and 0.2 or (0.5 + math.random() * 1.1)
            C_Timer.After(jitter, function()
                self:BroadcastGuildBoardSnapshot(board)
            end)
        end

    -- ---------------- TIMED POLL MESSAGES ----------------
    elseif cmd == "TP_META" then
        local pollId = parts[2]
        local createdAt = tonumber(parts[3]) or GTV.Storage:Now()
        local endsAt = tonumber(parts[4]) or (createdAt + 86400)
        local status = parts[5] or "ACTIVE"
        local leaderName = parts[6] or senderShort
        local title = parts[7] or GTV.L.TIMED_TITLE_DEFAULT
        local keepExisting = (parts[8] ~= "0")

        if isSelf and not isLocalTestEcho then return end
        if isLocalTestEcho then
            local rem = GTV.Storage:FormatRemaining(endsAt)
            if GTV.UI_Prompt then
                GTV.UI_Prompt:ShowTimedInvite(leaderName, pollId, rem)
            end
            return
        end

        local board = self:GetGuildBoard(true)
        if not board then return end
        local existing = board.timedPoll
        if not existing or (createdAt > (existing.createdAt or 0) and existing.id ~= pollId) then
            if not keepExisting then
                for _, d in ipairs(board.designs) do
                    board.deletedIds[d.id] = true
                end
                wipe(board.designs)
                wipe(board.designById)
            end
            board.timedPoll = {
                id = pollId,
                title = title,
                leaderName = leaderName,
                createdAt = createdAt,
                endsAt = endsAt,
                status = status,
                winnerDesignId = nil,
                keepExisting = keepExisting,
            }
            if keepExisting then
                CarryOverBoardBallots(board, pollId)
            end
            FireCallbacks("GUILD_BOARD_CHANGED", board)
            if self:IsTimedPollOpen(board.timedPoll) and not GTV.Storage:WasPollPrompted(pollId) then
                GTV.Storage:MarkPollPrompted(pollId)
                local rem = GTV.Storage:FormatRemaining(endsAt)
                if GTV.UI_Prompt then
                    GTV.UI_Prompt:ShowTimedInvite(leaderName, pollId, rem)
                end
            end
        elseif existing.id == pollId then
            existing.endsAt = endsAt
            existing.title = title
            if status == "CLOSED" then
                existing.status = "CLOSED"
            end
            FireCallbacks("GUILD_BOARD_CHANGED", board)
        end

    elseif cmd == "TP_CLOSE" then
        local pollId, winnerId = parts[2], parts[3]
        if isSelf then return end
        local board = self:GetGuildBoard(false)
        if not board or not board.timedPoll or board.timedPoll.id ~= pollId then return end
        board.timedPoll.status = "CLOSED"
        if winnerId and winnerId ~= "" then
            board.timedPoll.winnerDesignId = winnerId
        end
        GTV:Print(GTV.L.TIMED_ENDED_CHAT)
        FireCallbacks("GUILD_BOARD_CHANGED", board)

    -- ---------------- LIVE SESSION MESSAGES ----------------
    elseif cmd == "OPEN" then
        local sid = parts[2]
        local leaderName = parts[3] or senderShort
        local autoReset = (parts[4] == "1")
        local design = ParseDesign(parts[5], parts[6], parts[7], parts[8], parts[9], parts[10])
        if isSelf and not isLocalTestEcho then return end
        if isLocalTestEcho then
            if GTV.UI_Prompt then
                GTV.UI_Prompt:ShowInvite(leaderName, sid)
            end
            return
        end

        local alreadySame = self.session and self.session.id == sid
        if not alreadySame then
            self.session = CreateSessionObject(sid, senderKey, leaderName, autoReset, design, false, false, false)
            FireCallbacks("SESSION_STARTED", self.session)
            if GTV.UI_Prompt then
                GTV.UI_Prompt:ShowInvite(leaderName, sid)
            end
        else
            self.session.design = design
            self.session.autoReset = autoReset
            if self.session.myDecision ~= "JOIN" and GTV.UI_Prompt then
                GTV.UI_Prompt:ShowInvite(leaderName, sid)
            end
            FireCallbacks("DESIGN_UPDATED", self.session, 0, 0, false)
        end

    elseif cmd == "SYNC_STATE" then
        local sid = parts[2]
        local leaderName = parts[3] or senderShort
        local rev = tonumber(parts[4]) or 1
        local autoReset = (parts[5] == "1")
        local design = ParseDesign(parts[6], parts[7], parts[8], parts[9], parts[10], parts[11])
        if isSelf then return end

        if not self.session or self.session.id ~= sid then
            self.session = CreateSessionObject(sid, senderKey, leaderName, autoReset, design, false, false, false)
            self.session.rev = rev
            FireCallbacks("SESSION_STARTED", self.session)
            if GTV.UI_MemberWindow and GTV.UI_MemberWindow:IsShown() then
                self:SendParticipation("JOIN")
            elseif GTV.UI_Prompt then
                GTV.UI_Prompt:ShowInvite(leaderName, sid)
            end
        else
            self.session.rev = rev
            self.session.autoReset = autoReset
            self.session.design = design
            FireCallbacks("DESIGN_UPDATED", self.session, 0, 0, false)
        end

    elseif cmd == "UPDATE" then
        local sid = parts[2]
        local rev = tonumber(parts[3]) or 1
        local varIdx = tonumber(parts[4]) or 0
        local delta = tonumber(parts[5]) or 0
        local design = ParseDesign(parts[6], parts[7], parts[8], parts[9], parts[10], parts[11])
        if isSelf and not isLocalTestEcho then return end

        if not self.session or self.session.id ~= sid then
            self.session = CreateSessionObject(sid, senderKey, senderShort, true, design, false, false, false)
            self.session.rev = rev
            FireCallbacks("SESSION_STARTED", self.session)
            if GTV.UI_Prompt then
                GTV.UI_Prompt:ShowInvite(senderShort, sid)
            end
            return
        end
        if isLocalTestEcho then
            FireCallbacks("DESIGN_UPDATED", self.session, varIdx, delta, self.session.autoReset)
            return
        end

        local votesCleared = false
        if rev > self.session.rev then
            self.session.rev = rev
            if self.session.autoReset then
                wipe(self.session.votes)
                self.session.myVote = nil
                votesCleared = true
            end
        end
        self.session.design = design
        FireCallbacks("DESIGN_UPDATED", self.session, varIdx, delta, votesCleared)

    elseif cmd == "CLOSE" then
        local sid = parts[2]
        local saved = (parts[3] == "1")
        if isSelf and not isLocalTestEcho then return end
        if self.session and self.session.id == sid then
            local leaderName = self.session.leaderName
            self.session = nil
            if GTV.UI_Prompt then GTV.UI_Prompt:Hide() end
            GTV:Print(saved and string.format(GTV.L.STATUS_SAVED, leaderName) or string.format(GTV.L.STATUS_ENDED, leaderName))
            FireCallbacks("SESSION_ENDED", saved, leaderName)
        end

    elseif cmd == "PART" then
        local sid, hash, status = parts[2], parts[3], parts[4]
        if isSelf or not self.session or self.session.id ~= sid or not hash then return end
        if status == "LEAVE" then
            self.session.participants[hash] = nil
            self.session.votes[hash] = nil
        elseif status == "JOIN" or status == "ABSTAIN" then
            self.session.participants[hash] = status
            if status == "ABSTAIN" then
                self.session.votes[hash] = nil
            end
        end
        FireCallbacks("VOTES_CHANGED", self.session)

    elseif cmd == "VOTE" then
        local sid = parts[2]
        local rev = tonumber(parts[3]) or 0
        local hash = parts[4]
        local vote = parts[5]
        if isSelf or not self.session or self.session.id ~= sid or not hash then return end
        if rev < self.session.rev then return end
        self.session.participants[hash] = "JOIN"
        if vote == "UP" or vote == "DOWN" then
            self.session.votes[hash] = vote
        else
            self.session.votes[hash] = nil
        end
        FireCallbacks("VOTES_CHANGED", self.session)

    elseif cmd == "RESETV" then
        local sid = parts[2]
        local rev = tonumber(parts[3]) or 1
        if isSelf and not isLocalTestEcho then return end
        if not self.session or self.session.id ~= sid then return end
        self.session.rev = math.max(self.session.rev, rev)
        wipe(self.session.votes)
        self.session.myVote = nil
        FireCallbacks("VOTES_RESET", self.session, true)

    elseif cmd == "SYNC_REQ" then
        if not self:IsLeading() or isSelf then return end
        local now = GetTime and GetTime() or 0
        if (now - self.lastSyncReplyAt) < 1.5 then return end
        self.lastSyncReplyAt = now
        local s = self.session
        self:SendGuild(table.concat({
            "SYNC_STATE",
            s.id,
            SanitizeText(s.leaderName, 24),
            tostring(s.rev),
            s.autoReset and "1" or "0",
            SerializeDesign(s.design),
        }, "|"))
    end
end

function Protocol:StartSoloTestSession()
    self.testModeActive = true
    GTV:Print(GTV.L.TEST_STARTED)
    if GTV.UI_LeaderPanel then
        GTV.UI_LeaderPanel:ShowStandalone(true)
    end
end

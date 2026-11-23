local _, GTV = ...

local Protocol = {}
GTV.Protocol = Protocol

local MSG_THROTTLE = 0.12
local SUGGESTION_COOLDOWN = 3.0

-- Live session state
Protocol.session = nil
Protocol.lastSyncReplyAt = 0
Protocol.lastTimedSyncReplyAt = 0
Protocol.lastSuggestionSentAt = 0
Protocol.pendingUpdate = nil
Protocol.updateTimerActive = false
Protocol.suggestionCounter = 0
Protocol.testModeActive = false

local listeners = {}

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
        -- Strictly anonymous maps keyed by voterHash (NEVER player names!)
        participants = {},   -- [voterHash] = "JOIN" | "ABSTAIN"
        votes = {},          -- [voterHash] = "UP" | "DOWN"
        suggestions = {},    -- array of { id, authorName, note, design, votes = { [voterHash] = "UP"|"DOWN" } }
        suggestionById = {},
        myDecision = nil,    -- "JOIN" | "ABSTAIN" | nil
        myVote = nil,        -- "UP" | "DOWN" | nil
    }
end

-- =========================================================================
-- LIVE SESSION (GUILD LEADER)
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

    local msg = table.concat({
        "OPEN",
        sessionId,
        SanitizeText(meShort, 24),
        autoReset and "1" or "0",
        SerializeDesign(design),
    }, "|")

    self:SendGuild(msg)

    if not isTestMode then
        GTV:Print(GTV.L.LEADER_SESSION_STARTED)
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
    local msg = table.concat({
        "OPEN",
        s.id,
        SanitizeText(s.leaderName, 24),
        s.autoReset and "1" or "0",
        SerializeDesign(s.design),
    }, "|")
    self:SendGuild(msg)
end

function Protocol:SetAutoReset(enabled)
    GTV.db.autoResetVotes = enabled and true or false
    if self:IsLeading() then
        self.session.autoReset = GTV.db.autoResetVotes
        local s = self.session
        local msg = table.concat({
            "SYNC_STATE",
            s.id,
            SanitizeText(s.leaderName, 24),
            tostring(s.rev),
            s.autoReset and "1" or "0",
            SerializeDesign(s.design),
        }, "|")
        self:SendGuild(msg)
        FireCallbacks("STATE_CHANGED", s)
    end
end

function Protocol:EndLeaderSession(wasSaved)
    if not self:IsLeading() then
        return
    end
    local s = self.session
    local msg = table.concat({
        "CLOSE",
        s.id,
        wasSaved and "1" or "0",
    }, "|")
    self:SendGuild(msg)
    self.pendingUpdate = nil
    self.session = nil
    if not s.isTestMode then
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

        local msg = table.concat({
            "UPDATE",
            s.id,
            tostring(s.rev),
            tostring(p.varIndex),
            tostring(p.delta),
            SerializeDesign(design),
        }, "|")
        self:SendGuild(msg)
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
    local msg = table.concat({ "RESETV", s.id, tostring(s.rev) }, "|")
    self:SendGuild(msg)
    FireCallbacks("VOTES_RESET", s, true)
end

-- Apply any design directly to the Guild Master's active TabardModel (vendor or standalone)
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
        model:EnsureReady()
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

function Protocol:ApplySuggestion(suggId)
    local s = self.session
    if not s then
        return
    end
    local sugg = s.suggestionById[suggId]
    if not sugg then
        return
    end
    self:ApplyDesignToLeaderModel(sugg.design)
end

-- =========================================================================
-- LIVE SESSION (MEMBER ACTIONS — ANONYMOUS)
-- =========================================================================
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
        return
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
end

function Protocol:SendSuggestion(design, note)
    local s = self.session
    if not s or not design then
        return false
    end
    local now = GetTime and GetTime() or 0
    if (now - self.lastSuggestionSentAt) < SUGGESTION_COOLDOWN then
        GTV:Print(GTV.L.SUGG_COOLDOWN)
        return false
    end
    self.lastSuggestionSentAt = now
    self.suggestionCounter = self.suggestionCounter + 1

    local meShort = GTV:ShortName(GTV:GetPlayerKey())
    local suggId = SanitizeText(meShort, 14) .. "-" .. tostring(GTV.Storage:Now()) .. "-" .. tostring(self.suggestionCounter)
    local cleanNote = SanitizeText(note, 36)

    self:AddSuggestionLocal(suggId, meShort, design, cleanNote)

    local msg = table.concat({
        "SUGG",
        s.id,
        suggId,
        SanitizeText(meShort, 24),
        SerializeDesign(design),
        cleanNote,
    }, "|")
    self:SendGuild(msg)
    GTV:Print(GTV.L.SUGG_SENT)
    return true
end

function Protocol:VoteLiveSuggestion(suggId, vote)
    local s = self.session
    if not s then
        return
    end
    local sugg = s.suggestionById[suggId]
    if not sugg then
        return
    end
    local hash = GTV.Storage:GetVoterHash(s.id)
    if sugg.votes[hash] == vote then
        vote = "NONE"
    end
    sugg.votes[hash] = (vote ~= "NONE") and vote or nil
    self:SendGuild(table.concat({ "SVOTE", s.id, suggId, hash, vote }, "|"))
    FireCallbacks("SUGGESTIONS_CHANGED", s)
end

function Protocol:RequestSync()
    local sid = self.session and self.session.id or "0"
    self:SendGuild(table.concat({ "SYNC_REQ", sid }, "|"))
end

function Protocol:AddSuggestionLocal(suggId, authorName, design, note)
    local s = self.session
    if not s or s.suggestionById[suggId] then
        return false
    end
    local entry = {
        id = suggId,
        authorName = authorName,
        note = note or "",
        design = GTV.TabardSync:CopyDesign(design),
        votes = {}, -- [voterHash] = "UP" | "DOWN"
    }
    table.insert(s.suggestions, entry)
    s.suggestionById[suggId] = entry
    FireCallbacks("SUGGESTIONS_CHANGED", s, entry)
    return true
end

-- Strictly anonymous vote counts (returns numbers only — NO player names!)
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

function Protocol:GetLiveSuggestionCounts(sugg)
    local up, down = 0, 0
    if sugg and sugg.votes then
        for _, v in pairs(sugg.votes) do
            if v == "UP" then
                up = up + 1
            elseif v == "DOWN" then
                down = down + 1
            end
        end
    end
    return up, down
end

-- =========================================================================
-- TIMED MULTI-DAY POLLS (PERSISTENT, ANONYMOUS, GM-ONLY RESULTS)
-- =========================================================================
local function EnsureTimedPollIndexes(poll)
    if not poll then
        return nil
    end
    poll.designs = poll.designs or {}
    poll.designById = {}
    for _, d in ipairs(poll.designs) do
        poll.designById[d.id] = d
    end
    poll.ballots = poll.ballots or {} -- [voterHash] = { abstained = bool, votes = { [designId] = "UP"|"DOWN" } }
    return poll
end

function Protocol:GetActiveTimedPoll()
    local gKey = GTV.Storage:GetGuildKey(self:IsTestModeActive())
    if not gKey then
        return nil
    end
    local poll = EnsureTimedPollIndexes(GTV.Storage:GetTimedPoll(gKey))
    if not poll then
        return nil
    end
    -- Auto-check expiration
    if poll.status == "ACTIVE" and GTV.Storage:Now() >= (poll.endsAt or 0) then
        poll.status = "EXPIRED"
        GTV.Storage:SetTimedPoll(gKey, poll)
    end
    return poll
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

-- Guild Master creates a new X-day (or X-seconds) timed poll
function Protocol:CreateTimedPoll(title, durationSeconds, initialDesign)
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

    local gKey = GTV.Storage:GetGuildKey(isTest)
    if not gKey then
        return nil
    end

    local now = GTV.Storage:Now()
    durationSeconds = math.max(300, tonumber(durationSeconds) or (3 * 86400))
    local cleanTitle = SanitizeText(title, 34)
    if cleanTitle == "" then
        cleanTitle = GTV.L.TIMED_TITLE_DEFAULT
    end

    local meShort = GTV:ShortName(GTV:GetPlayerKey())
    local pollId = "tp_" .. tostring(now) .. "_" .. tostring(math.random(100, 999))
    local poll = EnsureTimedPollIndexes({
        id = pollId,
        title = cleanTitle,
        leaderName = meShort,
        createdAt = now,
        endsAt = now + durationSeconds,
        status = "ACTIVE",
        winnerDesignId = nil,
        designs = {},
        ballots = {},
    })

    GTV.Storage:SetTimedPoll(gKey, poll)
    GTV.Storage:MarkPollPrompted(pollId)

    -- Broadcast poll metadata
    local metaMsg = table.concat({
        "TP_META",
        poll.id,
        tostring(poll.createdAt),
        tostring(poll.endsAt),
        poll.status,
        SanitizeText(poll.leaderName, 24),
        poll.title,
    }, "|")
    self:SendGuild(metaMsg)

    -- Optionally include leader's current tabard as first design
    if initialDesign then
        self:SubmitTimedPollDesign(initialDesign, cleanTitle, true)
    end

    local remText = GTV.Storage:FormatRemaining(poll.endsAt)
    GTV:Print(string.format(GTV.L.TIMED_STARTED_CHAT, remText))
    FireCallbacks("TIMED_POLL_CHANGED", poll)
    return poll
end

function Protocol:SubmitTimedPollDesign(design, note, bypassCooldown)
    local poll = self:GetActiveTimedPoll()
    if not poll then
        return false
    end
    if not self:IsTimedPollOpen(poll) then
        GTV:Print(GTV.L.TIMED_VOTING_LOCKED)
        return false
    end
    if not design then
        return false
    end

    local nowTick = GetTime and GetTime() or 0
    if not bypassCooldown and (nowTick - self.lastSuggestionSentAt) < SUGGESTION_COOLDOWN then
        GTV:Print(GTV.L.SUGG_COOLDOWN)
        return false
    end
    self.lastSuggestionSentAt = nowTick
    self.suggestionCounter = self.suggestionCounter + 1

    local meShort = GTV:ShortName(GTV:GetPlayerKey())
    local designId = "td_" .. tostring(GTV.Storage:Now()) .. "_" .. tostring(math.random(100, 999)) .. "_" .. tostring(self.suggestionCounter)
    local cleanNote = SanitizeText(note, 34)
    local createdAt = GTV.Storage:Now()

    self:AddTimedDesignLocal(poll, designId, meShort, createdAt, design, cleanNote)

    local msg = table.concat({
        "TP_DESIGN",
        poll.id,
        designId,
        SanitizeText(meShort, 24),
        tostring(createdAt),
        SerializeDesign(design),
        cleanNote,
    }, "|")
    self:SendGuild(msg)

    if not bypassCooldown then
        GTV:Print(GTV.L.SUGG_SENT)
    end
    return true
end

function Protocol:AddTimedDesignLocal(poll, designId, authorName, createdAt, design, note)
    EnsureTimedPollIndexes(poll)
    if poll.designById[designId] then
        return false
    end
    local entry = {
        id = designId,
        authorName = authorName or "Unknown",
        createdAt = tonumber(createdAt) or GTV.Storage:Now(),
        note = note or "",
        design = GTV.TabardSync:CopyDesign(design),
    }
    table.insert(poll.designs, entry)
    poll.designById[designId] = entry
    local gKey = GTV.Storage:GetGuildKey(self:IsTestModeActive())
    if gKey then
        GTV.Storage:SetTimedPoll(gKey, poll)
    end
    FireCallbacks("TIMED_POLL_CHANGED", poll)
    return true
end

-- Cast an anonymous Thumbs Up / Down vote on a specific design in the Timed Poll
function Protocol:VoteTimedDesign(designId, vote)
    local poll = self:GetActiveTimedPoll()
    if not poll or not self:IsTimedPollOpen(poll) then
        GTV:Print(GTV.L.TIMED_VOTING_LOCKED)
        return
    end
    EnsureTimedPollIndexes(poll)
    if not poll.designById[designId] then
        return
    end

    local myBallot = GTV.Storage:GetMyBallot(poll.id)
    local hash = GTV.Storage:GetVoterHash(poll.id)

    -- Toggle off if same vote clicked again
    if myBallot.votes[designId] == vote then
        vote = "NONE"
    end
    myBallot.abstained = false
    myBallot.votes[designId] = (vote ~= "NONE") and vote or nil

    -- Store under anonymous voterHash in local poll cache
    poll.ballots[hash] = poll.ballots[hash] or { abstained = false, votes = {} }
    poll.ballots[hash].abstained = false
    poll.ballots[hash].votes[designId] = myBallot.votes[designId]

    local gKey = GTV.Storage:GetGuildKey(self:IsTestModeActive())
    if gKey then
        GTV.Storage:SetTimedPoll(gKey, poll)
    end

    self:SendGuild(table.concat({ "TP_VOTE", poll.id, hash, designId, vote }, "|"))
    FireCallbacks("TIMED_POLL_CHANGED", poll)
end

-- Toggle "Enthalten" (Abstain) for the entire Timed Poll (anonymous)
function Protocol:SetTimedPollAbstain(abstain)
    local poll = self:GetActiveTimedPoll()
    if not poll or not self:IsTimedPollOpen(poll) then
        return
    end
    EnsureTimedPollIndexes(poll)

    local myBallot = GTV.Storage:GetMyBallot(poll.id)
    local hash = GTV.Storage:GetVoterHash(poll.id)

    myBallot.abstained = abstain and true or false
    if myBallot.abstained then
        wipe(myBallot.votes)
    end

    poll.ballots[hash] = poll.ballots[hash] or { abstained = false, votes = {} }
    poll.ballots[hash].abstained = myBallot.abstained
    if myBallot.abstained then
        wipe(poll.ballots[hash].votes)
    end

    local gKey = GTV.Storage:GetGuildKey(self:IsTestModeActive())
    if gKey then
        GTV.Storage:SetTimedPoll(gKey, poll)
    end

    self:SendGuild(table.concat({ "TP_ABSTAIN", poll.id, hash, myBallot.abstained and "1" or "0" }, "|"))
    FireCallbacks("TIMED_POLL_CHANGED", poll)
end

function Protocol:CloseTimedPoll(winnerDesignId)
    local poll = self:GetActiveTimedPoll()
    if not poll then
        return
    end
    if not self:IsTestModeActive() and not GTV:IsGuildLeader() then
        return
    end
    poll.status = "CLOSED"
    if winnerDesignId and winnerDesignId ~= "" then
        poll.winnerDesignId = winnerDesignId
    else
        -- Pick highest score automatically if none passed
        local bestId, bestScore = nil, -999999
        for _, d in ipairs(poll.designs) do
            local up, down = self:GetTimedDesignVotes(poll, d.id)
            local score = up - down
            if score > bestScore then
                bestScore = score
                bestId = d.id
            end
        end
        poll.winnerDesignId = bestId
    end
    local gKey = GTV.Storage:GetGuildKey(self:IsTestModeActive())
    if gKey then
        GTV.Storage:SetTimedPoll(gKey, poll)
    end

    self:SendGuild(table.concat({ "TP_CLOSE", poll.id, poll.winnerDesignId or "" }, "|"))
    GTV:Print(GTV.L.TIMED_ENDED_CHAT)
    FireCallbacks("TIMED_POLL_CHANGED", poll)
end

function Protocol:AnnounceTimedPollWinner()
    local poll = self:GetActiveTimedPoll()
    if not poll then
        return
    end
    EnsureTimedPollIndexes(poll)
    local winner = poll.winnerDesignId and poll.designById[poll.winnerDesignId]
    if not winner then
        local best, bestScore = nil, -999999
        for _, d in ipairs(poll.designs) do
            local up, down = self:GetTimedDesignVotes(poll, d.id)
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

-- GM-only anonymous vote tallies per design in Timed Poll
function Protocol:GetTimedDesignVotes(poll, designId)
    local up, down = 0, 0
    if not poll or not poll.ballots then
        return up, down
    end
    for _, b in pairs(poll.ballots) do
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

function Protocol:GetTimedPollStats(poll)
    local designCount, voters, abstained = 0, 0, 0
    if not poll then
        return designCount, voters, abstained
    end
    designCount = #(poll.designs or {})
    if poll.ballots then
        for _, b in pairs(poll.ballots) do
            if b.abstained then
                abstained = abstained + 1
            elseif b.votes and next(b.votes) ~= nil then
                voters = voters + 1
            end
        end
    end
    return designCount, voters, abstained
end

-- Peer-to-peer multi-day sync on login / open
function Protocol:SendTimedPollHello()
    if not self:IsTestModeActive() and not IsInGuild() then
        return
    end
    local poll = self:GetActiveTimedPoll()
    local pid = poll and poll.id or "0"
    local dCount = poll and #(poll.designs or {}) or 0
    local _, vCount, aCount = self:GetTimedPollStats(poll)
    self:SendGuild(table.concat({ "TP_HELLO", pid, tostring(dCount), tostring(vCount + aCount) }, "|"))
end

function Protocol:BroadcastTimedPollSnapshot(poll)
    if not poll then
        return
    end
    local now = GetTime and GetTime() or 0
    if (now - self.lastTimedSyncReplyAt) < 3.0 then
        return
    end
    self.lastTimedSyncReplyAt = now

    local metaMsg = table.concat({
        "TP_META",
        poll.id,
        tostring(poll.createdAt),
        tostring(poll.endsAt),
        poll.status,
        SanitizeText(poll.leaderName, 24),
        SanitizeText(poll.title, 34),
    }, "|")
    self:SendGuild(metaMsg)

    local delay = 0.2
    for _, d in ipairs(poll.designs or {}) do
        local entry = d
        C_Timer.After(delay, function()
            local smsg = table.concat({
                "TP_DESIGN",
                poll.id,
                entry.id,
                SanitizeText(entry.authorName, 24),
                tostring(entry.createdAt or 0),
                SerializeDesign(entry.design),
                SanitizeText(entry.note, 34),
            }, "|")
            self:SendGuild(smsg)
        end)
        delay = delay + 0.18
    end

    -- Relay anonymous cached ballots (so votes cast while GM was offline reach the GM!)
    for hash, b in pairs(poll.ballots or {}) do
        local h = hash
        local ballot = b
        if ballot.abstained then
            C_Timer.After(delay, function()
                self:SendGuild(table.concat({ "TP_ABSTAIN", poll.id, h, "1" }, "|"))
            end)
            delay = delay + 0.15
        elseif ballot.votes then
            for did, v in pairs(ballot.votes) do
                local designId, val = did, v
                C_Timer.After(delay, function()
                    self:SendGuild(table.concat({ "TP_VOTE", poll.id, h, designId, val }, "|"))
                end)
                delay = delay + 0.15
            end
        end
    end

    if poll.status == "CLOSED" then
        C_Timer.After(delay, function()
            self:SendGuild(table.concat({ "TP_CLOSE", poll.id, poll.winnerDesignId or "" }, "|"))
        end)
    end
end

function Protocol:OnLoginSync()
    if not IsInGuild or not IsInGuild() then
        return
    end
    self:SendTimedPollHello()
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

    -- ---------------- LIVE SESSION MESSAGES ----------------
    if cmd == "OPEN" then
        local sid = parts[2]
        local leaderName = parts[3] or senderShort
        local autoReset = (parts[4] == "1")
        local design = ParseDesign(parts[5], parts[6], parts[7], parts[8], parts[9], parts[10])

        if isSelf and not isLocalTestEcho then
            return
        end
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

    elseif cmd == "SUGG" then
        local sid = parts[2]
        local suggId = parts[3]
        local authorDisplay = (parts[4] and parts[4] ~= "") and parts[4] or senderShort
        local design = ParseDesign(parts[5], parts[6], parts[7], parts[8], parts[9], parts[10])
        local note = parts[11] or ""
        if isSelf or not self.session or self.session.id ~= sid then return end
        if self:AddSuggestionLocal(suggId, authorDisplay, design, note) then
            GTV:PlaySound("IG_QUEST_LIST_OPEN", 844)
            GTV:Print(string.format(GTV.L.SUGG_RECEIVED, authorDisplay))
        end

    elseif cmd == "SVOTE" then
        local sid, suggId, hash, vote = parts[2], parts[3], parts[4], parts[5]
        if isSelf or not self.session or self.session.id ~= sid or not hash then return end
        local sugg = self.session.suggestionById[suggId]
        if not sugg then return end
        sugg.votes[hash] = (vote == "UP" or vote == "DOWN") and vote or nil
        FireCallbacks("SUGGESTIONS_CHANGED", self.session)

    elseif cmd == "SYNC_REQ" then
        if not self:IsLeading() or isSelf then return end
        local now = GetTime and GetTime() or 0
        if (now - self.lastSyncReplyAt) < 1.5 then return end
        self.lastSyncReplyAt = now
        local s = self.session
        local msg = table.concat({
            "SYNC_STATE",
            s.id,
            SanitizeText(s.leaderName, 24),
            tostring(s.rev),
            s.autoReset and "1" or "0",
            SerializeDesign(s.design),
        }, "|")
        self:SendGuild(msg)
        for i, sugg in ipairs(s.suggestions) do
            C_Timer.After(i * 0.2, function()
                if self:IsLeading() and self.session.id == s.id then
                    self:SendGuild(table.concat({
                        "SUGG",
                        s.id,
                        sugg.id,
                        SanitizeText(sugg.authorName, 24),
                        SerializeDesign(sugg.design),
                        SanitizeText(sugg.note, 36),
                    }, "|"))
                end
            end)
        end

    -- ---------------- TIMED MULTI-DAY POLL MESSAGES ----------------
    elseif cmd == "TP_META" then
        local pollId = parts[2]
        local createdAt = tonumber(parts[3]) or GTV.Storage:Now()
        local endsAt = tonumber(parts[4]) or (createdAt + 86400)
        local status = parts[5] or "ACTIVE"
        local leaderName = parts[6] or senderShort
        local title = parts[7] or GTV.L.TIMED_TITLE_DEFAULT

        if isSelf and not isLocalTestEcho then return end
        if isLocalTestEcho then
            -- In solo test mode, show the timed poll invite popup!
            local rem = GTV.Storage:FormatRemaining(endsAt)
            if GTV.UI_Prompt then
                GTV.UI_Prompt:ShowTimedInvite(leaderName, pollId, rem)
            end
            return
        end

        local gKey = GTV.Storage:GetGuildKey(false)
        if not gKey then return end
        local existing = EnsureTimedPollIndexes(GTV.Storage:GetTimedPoll(gKey))
        if not existing or (createdAt > (existing.createdAt or 0) and existing.id ~= pollId) then
            local poll = EnsureTimedPollIndexes({
                id = pollId,
                title = title,
                leaderName = leaderName,
                createdAt = createdAt,
                endsAt = endsAt,
                status = status,
                designs = {},
                ballots = {},
            })
            GTV.Storage:SetTimedPoll(gKey, poll)
            FireCallbacks("TIMED_POLL_CHANGED", poll)
            if self:IsTimedPollOpen(poll) and not GTV.Storage:WasPollPrompted(poll.id) then
                GTV.Storage:MarkPollPrompted(poll.id)
                local rem = GTV.Storage:FormatRemaining(poll.endsAt)
                if GTV.UI_Prompt then
                    GTV.UI_Prompt:ShowTimedInvite(poll.leaderName, poll.id, rem)
                end
            end
        elseif existing.id == pollId then
            existing.endsAt = endsAt
            existing.title = title
            if status == "CLOSED" then
                existing.status = "CLOSED"
            end
            GTV.Storage:SetTimedPoll(gKey, existing)
            FireCallbacks("TIMED_POLL_CHANGED", existing)
        end

    elseif cmd == "TP_DESIGN" then
        local pollId = parts[2]
        local designId = parts[3]
        local authorName = (parts[4] and parts[4] ~= "") and parts[4] or senderShort
        local createdAt = tonumber(parts[5]) or GTV.Storage:Now()
        local design = ParseDesign(parts[6], parts[7], parts[8], parts[9], parts[10], parts[11])
        local note = parts[12] or ""
        if isSelf then return end

        local poll = self:GetActiveTimedPoll()
        if not poll or poll.id ~= pollId then return end
        if self:AddTimedDesignLocal(poll, designId, authorName, createdAt, design, note) then
            GTV:Print(string.format(GTV.L.SUGG_RECEIVED, authorName))
        end

    elseif cmd == "TP_VOTE" then
        local pollId, hash, designId, vote = parts[2], parts[3], parts[4], parts[5]
        if isSelf or not hash or not designId then return end
        local poll = self:GetActiveTimedPoll()
        if not poll or poll.id ~= pollId then return end
        EnsureTimedPollIndexes(poll)
        poll.ballots[hash] = poll.ballots[hash] or { abstained = false, votes = {} }
        poll.ballots[hash].abstained = false
        poll.ballots[hash].votes[designId] = (vote == "UP" or vote == "DOWN") and vote or nil
        local gKey = GTV.Storage:GetGuildKey(self:IsTestModeActive())
        if gKey then GTV.Storage:SetTimedPoll(gKey, poll) end
        FireCallbacks("TIMED_POLL_CHANGED", poll)

    elseif cmd == "TP_ABSTAIN" then
        local pollId, hash, flag = parts[2], parts[3], parts[4]
        if isSelf or not hash then return end
        local poll = self:GetActiveTimedPoll()
        if not poll or poll.id ~= pollId then return end
        EnsureTimedPollIndexes(poll)
        poll.ballots[hash] = poll.ballots[hash] or { abstained = false, votes = {} }
        poll.ballots[hash].abstained = (flag == "1")
        if poll.ballots[hash].abstained then
            wipe(poll.ballots[hash].votes)
        end
        local gKey = GTV.Storage:GetGuildKey(self:IsTestModeActive())
        if gKey then GTV.Storage:SetTimedPoll(gKey, poll) end
        FireCallbacks("TIMED_POLL_CHANGED", poll)

    elseif cmd == "TP_CLOSE" then
        local pollId, winnerId = parts[2], parts[3]
        if isSelf then return end
        local poll = self:GetActiveTimedPoll()
        if not poll or poll.id ~= pollId then return end
        poll.status = "CLOSED"
        if winnerId and winnerId ~= "" then
            poll.winnerDesignId = winnerId
        end
        local gKey = GTV.Storage:GetGuildKey(self:IsTestModeActive())
        if gKey then GTV.Storage:SetTimedPoll(gKey, poll) end
        GTV:Print(GTV.L.TIMED_ENDED_CHAT)
        FireCallbacks("TIMED_POLL_CHANGED", poll)

    elseif cmd == "TP_HELLO" then
        local remotePollId = parts[2] or "0"
        local remoteDesigns = tonumber(parts[3]) or 0
        local remoteVotes = tonumber(parts[4]) or 0
        if isSelf then return end

        local poll = self:GetActiveTimedPoll()
        if not poll then return end
        local localDesigns, localV, localA = self:GetTimedPollStats(poll)
        local localVotes = localV + localA

        -- Reply if we have a poll they don't, or more designs/votes than they have
        local shouldReply = (remotePollId ~= poll.id) or (localDesigns > remoteDesigns) or (localVotes > remoteVotes)
        if shouldReply then
            -- Guild Master replies fast; other peers jitter slightly so only 1 responds
            local jitter = GTV:IsGuildLeader() and 0.25 or (0.8 + math.random() * 1.2)
            C_Timer.After(jitter, function()
                self:BroadcastTimedPollSnapshot(poll)
            end)
        end
    end
end

function Protocol:StartSoloTestSession()
    self.testModeActive = true
    GTV:Print(GTV.L.TEST_STARTED)
    if GTV.UI_LeaderPanel then
        GTV.UI_LeaderPanel:ShowStandalone(true)
    end
end

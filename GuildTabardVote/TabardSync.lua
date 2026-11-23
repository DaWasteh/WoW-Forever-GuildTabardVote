local _, GTV = ...

local TabardSync = {}
GTV.TabardSync = TabardSync

-- Active async seek jobs keyed by model frame
local activeSeeks = {}

-- Safe helper to read the 6 defining tabard fileIDs from any TabardModel
function TabardSync:ReadModel(model)
    if not model then
        return nil
    end
    local ok1, ub = pcall(model.GetUpperBackgroundFileName, model)
    local ok2, lb = pcall(model.GetLowerBackgroundFileName, model)
    local ok3, ubo = pcall(model.GetUpperBorderFile, model)
    local ok4, lbo = pcall(model.GetLowerBorderFile, model)
    local ok5, ue = pcall(model.GetUpperEmblemFile, model)
    local ok6, le = pcall(model.GetLowerEmblemFile, model)

    if not (ok1 and ok2 and ok3 and ok4 and ok5 and ok6) then
        return nil
    end
    ub = tonumber(ub) or 0
    lb = tonumber(lb) or 0
    ubo = tonumber(ubo) or 0
    lbo = tonumber(lbo) or 0
    ue = tonumber(ue) or 0
    le = tonumber(le) or 0

    if ub == 0 and ubo == 0 and ue == 0 then
        return nil
    end

    return {
        ub = ub,
        lb = lb,
        ubo = ubo,
        lbo = lbo,
        ue = ue,
        le = le,
    }
end

function TabardSync:DesignsEqual(a, b)
    if not a or not b then
        return false
    end
    return a.ub == b.ub
        and a.lb == b.lb
        and a.ubo == b.ubo
        and a.lbo == b.lbo
        and a.ue == b.ue
        and a.le == b.le
end

function TabardSync:CopyDesign(d)
    if not d then
        return nil
    end
    return {
        ub = tonumber(d.ub) or 0,
        lb = tonumber(d.lb) or 0,
        ubo = tonumber(d.ubo) or 0,
        lbo = tonumber(d.lbo) or 0,
        ue = tonumber(d.ue) or 0,
        le = tonumber(d.le) or 0,
    }
end

function TabardSync:IsModelSeeking(model)
    return activeSeeks[model] ~= nil
end

function TabardSync:CancelSeek(model)
    local job = activeSeeks[model]
    if job and job.driver then
        job.driver:SetScript("OnUpdate", nil)
    end
    activeSeeks[model] = nil
end

-- Fast synchronous match for Background (var 5, ~51 colors)
local function MatchBackground(model, target)
    local cur = TabardSync:ReadModel(model)
    if not cur then
        return false
    end
    if cur.ub == target.ub and cur.lb == target.lb then
        return true
    end
    local startUb, startLb = cur.ub, cur.lb
    for i = 1, 80 do
        model:CycleVariation(5, 1)
        cur = TabardSync:ReadModel(model)
        if not cur then
            return false
        end
        if cur.ub == target.ub and cur.lb == target.lb then
            return true
        end
        if i > 1 and cur.ub == startUb and cur.lb == startLb then
            break
        end
    end
    return false
end

-- Fast synchronous match for Border style (var 3, ~6 styles) & Border color (var 4, ~17 colors)
local function MatchBorder(model, target)
    local cur = TabardSync:ReadModel(model)
    if not cur then
        return false
    end
    if cur.ubo == target.ubo and cur.lbo == target.lbo then
        return true
    end

    local startStyleUbo, startStyleLbo = cur.ubo, cur.lbo
    for s = 1, 14 do
        local startColUbo, startColLbo = cur.ubo, cur.lbo
        for c = 1, 28 do
            if cur.ubo == target.ubo and cur.lbo == target.lbo then
                return true
            end
            model:CycleVariation(4, 1)
            cur = TabardSync:ReadModel(model)
            if not cur then
                return false
            end
            if cur.ubo == target.ubo and cur.lbo == target.lbo then
                return true
            end
            if c > 1 and cur.ubo == startColUbo and cur.lbo == startColLbo then
                break
            end
        end
        model:CycleVariation(3, 1)
        cur = TabardSync:ReadModel(model)
        if not cur then
            return false
        end
        if cur.ubo == target.ubo and cur.lbo == target.lbo then
            return true
        end
        if s > 1 and cur.ubo == startStyleUbo and cur.lbo == startStyleLbo then
            break
        end
    end
    return false
end

-- Fast 1-axis check for Emblem color (var 2) or Emblem style (var 1)
local function TryFastEmblemMatch(model, target)
    local cur = TabardSync:ReadModel(model)
    if not cur then
        return false
    end
    if cur.ue == target.ue and cur.le == target.le then
        return true
    end

    -- 1. Try color-only change (max ~24 steps)
    local startUe, startLe = cur.ue, cur.le
    for i = 1, 28 do
        model:CycleVariation(2, 1)
        cur = TabardSync:ReadModel(model)
        if not cur then
            return false
        end
        if cur.ue == target.ue and cur.le == target.le then
            return true
        end
        if i > 1 and cur.ue == startUe and cur.le == startLe then
            break
        end
    end

    -- 2. Try style-only change at current color (max ~240 steps)
    startUe, startLe = cur.ue, cur.le
    for i = 1, 260 do
        model:CycleVariation(1, 1)
        cur = TabardSync:ReadModel(model)
        if not cur then
            return false
        end
        if cur.ue == target.ue and cur.le == target.le then
            return true
        end
        if i > 1 and cur.ue == startUe and cur.le == startLe then
            break
        end
    end

    return false
end

-- Seek any TabardModel to an exact 6-fileID target design.
-- Instant (1 call) on live arrow clicks; zero-stutter multi-frame async fallback for full jumps!
function TabardSync:SeekModel(model, target, hintVar, hintDelta, onDone)
    if not model or not target then
        if onDone then onDone(false) end
        return
    end

    self:CancelSeek(model)

    local job = {
        model = model,
        target = self:CopyDesign(target),
        onDone = onDone,
    }
    activeSeeks[model] = job

    local function finish(success)
        if activeSeeks[model] == job then
            if job.driver then
                job.driver:SetScript("OnUpdate", nil)
            end
            activeSeeks[model] = nil
        end
        if model == TabardModel and TabardFrame_UpdateTextures then
            pcall(TabardFrame_UpdateTextures)
        end
        if onDone then
            onDone(success)
        end
    end

    local cur = self:ReadModel(model)
    if not cur then
        finish(false)
        return
    end

    -- Already exact match
    if self:DesignsEqual(cur, job.target) then
        finish(true)
        return
    end

    -- Ultra-fast path: apply hint delta from live click (1 single call!)
    if hintVar and hintVar >= 1 and hintVar <= 5 and hintDelta and hintDelta ~= 0 then
        local step = hintDelta > 0 and 1 or -1
        for _ = 1, 6 do
            model:CycleVariation(hintVar, step)
            cur = self:ReadModel(model)
            if cur and self:DesignsEqual(cur, job.target) then
                finish(true)
                return
            end
        end
    end

    -- Fast synchronous background & border sync
    MatchBackground(model, job.target)
    MatchBorder(model, job.target)

    -- Fast 1-axis emblem sync (covers all single-axis changes instantly)
    if TryFastEmblemMatch(model, job.target) then
        finish(true)
        return
    end

    -- Both emblem style AND color differ: step 2 emblem colors per frame so client never stutters
    local driver = CreateFrame("Frame")
    job.driver = driver
    job.colorSteps = 0
    job.maxColors = 26

    driver:SetScript("OnUpdate", function()
        if activeSeeks[model] ~= job then
            driver:SetScript("OnUpdate", nil)
            return
        end

        -- Process 2 emblem colors per frame (~400 CycleVariation calls/frame -> <10ms, zero stutter)
        for _ = 1, 2 do
            job.colorSteps = job.colorSteps + 1
            if job.colorSteps > job.maxColors then
                finish(false)
                return
            end

            model:CycleVariation(2, 1)
            local c = TabardSync:ReadModel(model)
            if not c then
                finish(false)
                return
            end
            if c.ue == job.target.ue and c.le == job.target.le then
                finish(true)
                return
            end

            local startUe, startLe = c.ue, c.le
            for i = 1, 260 do
                model:CycleVariation(1, 1)
                c = TabardSync:ReadModel(model)
                if not c then
                    finish(false)
                    return
                end
                if c.ue == job.target.ue and c.le == job.target.le then
                    finish(true)
                    return
                end
                if i > 1 and c.ue == startUe and c.le == startLe then
                    break
                end
            end
        end
    end)
end

-- Create a crisp 2D Flat Tabard Preview widget (works anywhere at 0ms latency using the 6 fileIDs!)
-- Mirrors Blizzard's exact TabardFrame.xml UV layout: Left half (0.5..0), Right half (0..0.5),
-- Upper height ratio ~119/193, Lower height ratio ~74/193.
function TabardSync:Create2DPreview(parent, width, height)
    width = width or 96
    height = height or 118

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)

    local halfW = width * 0.5
    local upperH = math.floor(height * (119 / 193) + 0.5)
    local lowerH = height - upperH

    -- Subtle dark backing so transparent edges look sharp
    local backdrop = frame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.05, 0.05, 0.07, 0.55)

    local function makeLayerSet(sublevel)
        local tl = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
        tl:SetSize(halfW, upperH)
        tl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        tl:SetTexCoord(0.5, 0, 0, 1)

        local tr = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
        tr:SetSize(halfW, upperH)
        tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        tr:SetTexCoord(0, 0.5, 0, 1)

        local bl = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
        bl:SetSize(halfW, lowerH)
        bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        bl:SetTexCoord(0.5, 0, 0, 1)

        local br = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
        br:SetSize(halfW, lowerH)
        br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        br:SetTexCoord(0, 0.5, 0, 1)

        return { tl = tl, tr = tr, bl = bl, br = br }
    end

    frame.bgLayer = makeLayerSet(0)
    frame.borderLayer = makeLayerSet(1)
    frame.emblemLayer = makeLayerSet(2)

    local function applyPair(layer, upperFile, lowerFile)
        if upperFile and upperFile ~= 0 then
            layer.tl:SetTexture(upperFile)
            layer.tr:SetTexture(upperFile)
            layer.tl:Show()
            layer.tr:Show()
        else
            layer.tl:Hide()
            layer.tr:Hide()
        end

        if lowerFile and lowerFile ~= 0 then
            layer.bl:SetTexture(lowerFile)
            layer.br:SetTexture(lowerFile)
            layer.bl:Show()
            layer.br:Show()
        else
            layer.bl:Hide()
            layer.br:Hide()
        end
    end

    function frame:SetDesign(design)
        if not design then
            applyPair(self.bgLayer, 0, 0)
            applyPair(self.borderLayer, 0, 0)
            applyPair(self.emblemLayer, 0, 0)
            return
        end
        applyPair(self.bgLayer, design.ub, design.lb)
        applyPair(self.borderLayer, design.ubo, design.lbo)
        applyPair(self.emblemLayer, design.ue, design.le)
    end

    return frame
end

-- Helper to configure a standalone interactive 3D TabardModel
-- Fixes Blizzard's hardcoded TabardFrame lower-left camera offset, enlarges the character,
-- and adds smooth Left-Drag rotate, Right-Drag pan, Mouse-Wheel zoom, and a Reset button.
function TabardSync:Create3DModel(parent, width, height)
    local model = CreateFrame("TabardModel", nil, parent)
    model:SetSize(width or 260, height or 280)
    if model.SetKeepModelOnHide then
        pcall(model.SetKeepModelOnHide, model, true)
    end

    model.rotation = 0
    model.defaultZoomX = 0.85
    model.defaultPanY = 0.34
    model.defaultPanZ = 0.16
    model.zoomX = model.defaultZoomX
    model.panY = model.defaultPanY
    model.panZ = model.defaultPanZ
    model.cameraCalibrated = false
    model.initialized = false

    -- Single unified transform: SetPosition(zoomX, panY, panZ) handles BOTH zoom and pan
    -- without fighting SetPortraitZoom or SetCamDistanceScale!
    local function applyPositionOnly()
        if not model:IsVisible() then
            return
        end
        if model.SetPosition then
            pcall(model.SetPosition, model, model.zoomX, model.panY, model.panZ)
        end
    end

    local function applyCamera()
        if not model:IsVisible() then
            return
        end
        applyPositionOnly()
        if model.SetRotation then
            pcall(model.SetRotation, model, model.rotation or 0)
        end
    end

    local function calibrateAndApply()
        if not model:IsVisible() then
            return
        end
        if not model.cameraCalibrated then
            model.cameraCalibrated = true
            -- Reset portrait zoom & camera distance scale ONCE at init so SetPosition owns zoom+pan cleanly
            if model.SetPortraitZoom then
                pcall(model.SetPortraitZoom, model, 0)
            end
            if model.SetCamDistanceScale then
                pcall(model.SetCamDistanceScale, model, 1.0)
            end
            if model.RefreshCamera then
                pcall(model.RefreshCamera, model)
            end
            if model.GetPosition then
                local ok, _, py, pz = pcall(model.GetPosition, model)
                if ok and py and pz and (math.abs(py) > 0.05 or math.abs(pz) > 0.05) then
                    model.defaultPanY = 0
                    model.defaultPanZ = 0
                    model.panY = 0
                    model.panZ = 0
                end
            end
        end
        applyCamera()
    end

    local function ensureUnit(forceRefresh)
        if not model:IsVisible() then
            return
        end
        if forceRefresh or not model.unitInitialized then
            model.unitInitialized = true
            pcall(model.SetUnit, model, "player")
            if not model.initialized then
                pcall(model.InitializeTabardColors, model)
                model.initialized = true
            end
            calibrateAndApply()
            C_Timer.After(0.05, function()
                if model:IsVisible() then
                    applyCamera()
                end
            end)
        end
    end

    model.EnsureReady = ensureUnit
    model.ApplyCamera = applyCamera

    model:SetScript("OnShow", function()
        ensureUnit(false)
        applyCamera()
    end)

    model:SetScript("OnModelLoaded", function()
        applyCamera()
    end)

    model:RegisterEvent("UNIT_MODEL_CHANGED")
    model:RegisterEvent("DISPLAY_SIZE_CHANGED")
    model:RegisterEvent("UI_SCALE_CHANGED")
    model:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_MODEL_CHANGED" and unit and unit ~= "player" then
            return
        end
        if model:IsVisible() then
            local prev = TabardSync:ReadModel(model)
            pcall(model.SetUnit, model, "player")
            applyCamera()
            if prev then
                C_Timer.After(0.05, function()
                    if model:IsVisible() then
                        TabardSync:SeekModel(model, prev, 0, 0)
                    end
                end)
            end
        end
    end)

    -- Interactive controls: Left-Drag = Rotate, Right-Drag = Pan, Mouse Wheel = Zoom
    model:EnableMouse(true)
    model:EnableMouseWheel(true)

    local dragMode = nil -- "ROTATE" | "PAN"
    local lastX, lastY = 0, 0

    model:SetScript("OnMouseDown", function(_, button)
        lastX, lastY = GetCursorPosition()
        if button == "LeftButton" then
            dragMode = "ROTATE"
        elseif button == "RightButton" then
            dragMode = "PAN"
        end
    end)

    model:SetScript("OnMouseUp", function()
        dragMode = nil
    end)

    model:SetScript("OnMouseWheel", function(_, delta)
        model.zoomX = math.max(-0.80, math.min(2.40, (model.zoomX or 0.85) + delta * 0.22))
        applyPositionOnly()
    end)

    model:SetScript("OnUpdate", function()
        if not dragMode then
            return
        end
        local x, y = GetCursorPosition()
        local dx = x - lastX
        local dy = y - lastY
        lastX, lastY = x, y
        if dragMode == "ROTATE" then
            model.rotation = (model.rotation or 0) + (dx * 0.015)
            if model.SetRotation then
                pcall(model.SetRotation, model, model.rotation)
            end
        elseif dragMode == "PAN" then
            local effScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            local zoomDamp = math.max(0.35, 1.0 - ((model.zoomX or 0) * 0.22))
            local factor = (0.0045 * zoomDamp) / effScale
            model.panY = math.max(-1.6, math.min(1.6, (model.panY or 0) + dx * factor))
            model.panZ = math.max(-1.4, math.min(1.4, (model.panZ or 0) + dy * factor))
            applyPositionOnly()
        end
    end)

    -- Left / Right rotate buttons + Reset camera button
    local rotLeft = CreateFrame("Button", nil, model)
    rotLeft:SetSize(24, 24)
    rotLeft:SetPoint("BOTTOMLEFT", model, "BOTTOMLEFT", 4, 4)
    rotLeft:SetNormalTexture("Interface\\Buttons\\UI-RotationLeft-Button-Up")
    rotLeft:SetPushedTexture("Interface\\Buttons\\UI-RotationLeft-Button-Down")
    rotLeft:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round", "ADD")
    rotLeft:SetScript("OnClick", function()
        model.rotation = (model.rotation or 0) - 0.55
        if model.SetRotation then
            pcall(model.SetRotation, model, model.rotation)
        end
    end)

    local rotRight = CreateFrame("Button", nil, model)
    rotRight:SetSize(24, 24)
    rotRight:SetPoint("LEFT", rotLeft, "RIGHT", 2, 0)
    rotRight:SetNormalTexture("Interface\\Buttons\\UI-RotationRight-Button-Up")
    rotRight:SetPushedTexture("Interface\\Buttons\\UI-RotationRight-Button-Down")
    rotRight:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round", "ADD")
    rotRight:SetScript("OnClick", function()
        model.rotation = (model.rotation or 0) + 0.55
        if model.SetRotation then
            pcall(model.SetRotation, model, model.rotation)
        end
    end)

    local resetCam = CreateFrame("Button", nil, model, "UIPanelButtonTemplate")
    resetCam:SetSize(44, 18)
    resetCam:SetPoint("LEFT", rotRight, "RIGHT", 4, 0)
    resetCam:SetText(GTV.L.BTN_RESET_CAM)
    resetCam:SetScript("OnClick", function()
        model.rotation = 0
        model.zoomX = model.defaultZoomX
        model.panY = model.defaultPanY
        model.panZ = model.defaultPanZ
        applyCamera()
    end)

    return model
end

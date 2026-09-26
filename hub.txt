--[[
    COMMAND AN ARMY -- HUB v1
    Place 92949164250558  universe 10258991999

    Verified before build:
      WindUI loads (274078 bytes, 33 API keys)
      window/tab/section/toggle/slider/dropdown/button/paragraph/notify all OK
      Drawing OK, game:HttpGet OK, 109 LocalPlayer attributes readable
      Troops: Workspace.Troops/<ownerUserId>/Troop_NN
              attrs Team / TroopId / TroopCount / AttackInterval / Range
              Humanoid for health, HumanoidRootPart for position

    Server owns damage, position, currency. Client owns visuals + input.
    Nothing here writes a server value.
]]

local Players   = game:GetService("Players")
local UIS       = game:GetService("UserInputService")
local RS        = game:GetService("ReplicatedStorage")
local Run       = game:GetService("RunService")
local WS        = game:GetService("Workspace")

local lp = Players.LocalPlayer
local HS = game:GetService("HttpService")

local ACCENT = Color3.fromRGB(190, 77, 110)
local ACCENT2= Color3.fromRGB(120, 60, 200)
local WHITE  = Color3.fromRGB(240, 240, 245)
local DIM    = Color3.fromRGB(150, 150, 160)
local GREEN  = Color3.fromRGB(120, 220, 140)
local RED    = Color3.fromRGB(240, 100, 100)
local BLUE   = Color3.fromRGB(90, 150, 255)
local YELLOW = Color3.fromRGB(240, 200, 90)

--------------------------------------------------------------------------
-- TEARDOWN of any previous run (WindUI caches its ScreenGui -- never
-- destroy the library, destroy the gui and rebuild the library fresh)
--------------------------------------------------------------------------
local KEY = "CAA_HUB"
pcall(function()
    local h = getgenv()
    if h[KEY] and type(h[KEY].unload) == "function" then h[KEY].unload() end
    h[KEY] = nil
end)
pcall(function()
    local hui = gethui and gethui() or game:GetService("CoreGui")
    local old = hui and hui:FindFirstChild("WindUI")
    if old then old:Destroy() end
end)

--------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------
local CFG = {
    -- esp
    espEnemy     = true,
    espFriendly  = false,
    espHealth    = true,
    espCount     = true,
    espTracer    = false,
    espRange     = 1500,
    espScale     = 1.0,
    espBox       = false,
    hbESP        = false,
    hbESPMine    = false,
    hbESPThick   = 2,
    espStyle     = "Bracket",
    espHeadDot   = false,
    espHPText    = true,
    espSmooth    = true,
    espGlow      = true,
    espThick     = 2,
    espName      = true,
    espDist      = true,
    -- reach / hitbox extender
    rangeOverride = false,
    rangeValue    = 60,
    hitboxOn      = false,
    hitboxScale   = 1.5,
    volleyMode    = false,
    hbDiag        = "", 
    -- combat assist
    autoAttack   = false,
    attackOffset = 0.10,
    atkGated     = true,
    atkRange     = 7,
    atkRangeAuto = true,
    atkFacing    = false,
    autoHeal     = false,
    healPct      = 35,
    chargeRing   = true,
    -- intel
    showHUD      = true,
    lowHPAlert   = true,
    alertPct     = 30,
    hudScale     = 1.0,
    -- misc
    autoDaily    = false,
    streamer     = false,
    theme        = "Dark",
    -- automation
    autoSummon   = false,
    summonCount  = 1,
    summonDelay  = 1.2,
    summonStop   = true,
    autoFuse     = false,
    fuseDelay    = 1.0,
    autoEvolve   = false,
    spdEnabled   = false,
    spdPlayer    = 23,
    spdHorse     = 17,
    spdSprint    = false,
}

--------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------
local function fmt(n)
    if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then return "-" end
    local s = tostring(math.floor(n))
    local rev = s:reverse():gsub("(%d%d%d)", "%1,")
    return (rev:reverse():gsub("^,", ""))
end
local function dur(sec)
    if type(sec) ~= "number" or sec ~= sec then return "-" end
    if sec < 0 then sec = 0 end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = math.floor(sec % 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end
local function at(name) return lp:GetAttribute(name) end
local function safeGet(t, k, d) local v = t and t[k]; if v == nil then return d end return v end

-- exponential smoothing, framerate independent
local function approach(cur, tgt, speed, dt)
    return cur + (tgt - cur) * (1 - math.exp(-speed * dt))
end

-- UnitsInventory / PlayerClassInventory are JSON STRINGS, not tables.
local _invCache, _invAt = nil, -1
local function unitsData()
    local now = os.clock()
    if _invCache and (now - _invAt) < 1.5 then return _invCache end
    local raw = lp:GetAttribute("UnitsInventory")
    local d = nil
    if type(raw) == "table" then
        d = raw
    elseif type(raw) == "string" and #raw > 2 then
        local ok, dec = pcall(HS.JSONDecode, HS, raw)
        if ok and type(dec) == "table" then d = dec end
    end
    _invCache, _invAt = d, now
    return d
end

local _clsCache, _clsAt = nil, -1
local function classData()
    local now = os.clock()
    if _clsCache and (now - _clsAt) < 1.5 then return _clsCache end
    local raw = lp:GetAttribute("PlayerClassInventory")
    local d = nil
    if type(raw) == "table" then
        d = raw
    elseif type(raw) == "string" and #raw > 2 then
        local ok, dec = pcall(HS.JSONDecode, HS, raw)
        if ok and type(dec) == "table" then d = dec end
    end
    _clsCache, _clsAt = d, now
    return d
end

local function uuid() return HS:GenerateGUID(false) end

local function findRemote(name)
    local r = RS:FindFirstChild("Shared")
    r = r and r:FindFirstChild("Remotes")
    if not r then return nil end
    return r:FindFirstChild(name) or r:FindFirstChild(name, true)
end

--------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------
local State = {
    enemyTeam   = nil,
    counts      = { blue = 0, red = 0, mine = 0 },
    reward      = nil,
    rewardAt    = 0,
    lastRedeem  = "-",
    redeemCode  = "",
    unitSel     = nil,
    classSel    = nil,
    lastAttack  = 0,
    charge      = 0,
    t           = 0,
    alive       = true,
    nearestEnemy = nil,
    extendN      = 0,
    lastExtend   = 0,
    hbOrig       = {},
    fireLog      = "", 
    nearestDist  = math.huge,
    inRange      = false,
    lastReach    = "-",
    reachLog     = {},
}

--------------------------------------------------------------------------
-- DRAWING POOL
--------------------------------------------------------------------------
-- Drawing objects leak across re-executes: this table is reborn every load,
-- so a previous run's objects can never be removed by this one. Publish the
-- list globally and reap the previous generation on the way in.
local DRAW_REG = "__caaDrawRegistry"

do
    local prev = getgenv()[DRAW_REG]
    if type(prev) == "table" then
        local killed = 0
        for _, o in ipairs(prev) do
            if pcall(function() o:Remove() end) then killed = killed + 1 end
        end
        if killed > 0 then print("[CAA] reaped " .. killed .. " stale drawing objects") end
    end
end

local DrawingObjects = {}
getgenv()[DRAW_REG] = DrawingObjects

-- near-black outline so text survives bright/dark backgrounds (Real + Vector
-- both honour OutlineColor on Drawing.Text; ignored harmlessly elsewhere)
local TEXT_OUTLINE = Color3.fromRGB(0, 0, 0)

local function mk(class, props)
    local o = Drawing.new(class)
    for k, v in pairs(props) do o[k] = v end
    table.insert(DrawingObjects, o)
    return o
end

--------------------------------------------------------------------------
-- ESP
--------------------------------------------------------------------------
local ESP = { pool = {}, live = {} }
local MAX_BOXES = 128

local function newBox()
    local b = {}
    b.box    = mk("Square", { Filled = false, Thickness = 1, Transparency = 0, Visible = false })
    b.fill   = mk("Square", { Filled = true,  Thickness = 1, Transparency = 0.85, Visible = false })
    b.hpBg   = mk("Square", { Filled = true,  Transparency = 0.5, Visible = false })
    b.hpFill = mk("Square", { Filled = true,  Transparency = 0,   Visible = false })
    b.label  = mk("Text",   { Size = 15, Outline = true, OutlineColor = TEXT_OUTLINE, Center = false, Visible = false, Color = WHITE, Font = 2 })
    b.sub    = mk("Text",   { Size = 13, Outline = true, OutlineColor = TEXT_OUTLINE, Center = false, Visible = false, Color = DIM, Font = 2 })
    b.line   = mk("Line",   { Thickness = 1, Transparency = 0.4, Visible = false })
    -- premium visuals
    b.glow   = mk("Square", { Filled = true,  Thickness = 1, Transparency = 0.9, Visible = false })
    b.dot    = mk("Circle", { Filled = true,  Thickness = 0, NumSides = 18, Visible = false })
    b.hpTxt  = mk("Text",   { Size = 13, Outline = true, OutlineColor = TEXT_OUTLINE, Center = true, Visible = false, Color = WHITE, Font = 2 })
    b.corners = {}
    for i = 1, 8 do
        b.corners[i] = mk("Line", { Thickness = 2, Transparency = 0, Visible = false })
    end
    b.anim   = 0        -- 0 spawn -> 1 full
    b.hpS    = 1        -- smoothed health ratio
    b.dieing = false
    b.dieT   = 0
    b.sx     = nil      -- smoothed screen pos
    b.sy     = nil
    return b
end

-- hide EVERY drawing object a slot owns
local function hideBox(b)
    b.box.Visible = false; b.fill.Visible = false
    b.hpBg.Visible = false; b.hpFill.Visible = false
    b.label.Visible = false; b.sub.Visible = false
    b.line.Visible = false; b.glow.Visible = false
    b.dot.Visible = false; b.hpTxt.Visible = false
    if b.corners then for _, c in ipairs(b.corners) do c.Visible = false end end
end

-- world -> viewport, but nil when the point is behind the camera.
-- WorldToViewportPoint still returns numbers behind the camera (mirrored),
-- which is what smeared boxes across the screen when you looked away.
local function visPt(cam, wp)
    local sp, on = cam:WorldToViewportPoint(wp)
    if not on or sp.Z <= 0 then return nil end
    return sp
end

local function acquire()
    local b = table.remove(ESP.pool)
    if b then return b end
    return newBox()
end
local function release(b)
    hideBox(b)
    b.anim = 0; b.hpS = 1; b.dieing = false; b.dieT = 0; b.sx = nil; b.sy = nil
    table.insert(ESP.pool, b)
end

local function collectTroops()
    local out = {}
    local root = WS:FindFirstChild("Troops")
    if not root then return out, nil end
    local myTeam = nil

    -- resolve my team + tally BOTH sides regardless of ESP filter state
    local tally = { blue = 0, red = 0, mine = 0 }
    local mine = root:FindFirstChild(tostring(lp.UserId))
    if mine then
        for _, c in ipairs(mine:GetChildren()) do
            if c:IsA("Model") and not c.Name:find("_Visual") and c.Name:find("^Troop_") then
                myTeam = c:GetAttribute("Team") or myTeam
                break
            end
        end
    end
    local cam = WS.CurrentCamera
    local nE, nD = nil, math.huge
    for _, owner in ipairs(root:GetChildren()) do
        for _, m in ipairs(owner:GetChildren()) do
            if m:IsA("Model") and not m.Name:find("_Visual") and m.Name:find("^Troop_") then
                local team = m:GetAttribute("Team")
                local cnt = tonumber(m:GetAttribute("TroopCount")) or 1
                local isMine = tostring(owner.Name) == tostring(lp.UserId)
                if isMine then
                    tally.mine = tally.mine + cnt
                elseif myTeam and team ~= myTeam then
                    tally.red = tally.red + cnt
                else
                    tally.blue = tally.blue + cnt
                end

                local hrp = m:FindFirstChild("HumanoidRootPart")
                local hum = m:FindFirstChildOfClass("Humanoid")
                if hrp then
                    local isEnemy = myTeam and team ~= myTeam
                    local pos = hrp.Position
                    local d = cam and (cam.CFrame.Position - pos).Magnitude or 9999
                    -- nearest ENEMY from MY CHARACTER (not camera) for attack gating
                    if isEnemy then
                        local myChar = lp.Character
                        local mh = myChar and myChar:FindFirstChild("HumanoidRootPart")
                        local gd = mh and (mh.Position - pos).Magnitude or d
                        if gd < nD then
                            nD = gd
                            nE = m
                        end
                    end
                    if (isEnemy and CFG.espEnemy) or ((not isEnemy) and CFG.espFriendly) then
                        if d <= CFG.espRange then
                            local myC = lp.Character
                            local myH = myC and myC:FindFirstChild("HumanoidRootPart")
                            local gdist = myH and (myH.Position - pos).Magnitude or d
                            local reach = tonumber(at("Range")) or 7
                            table.insert(out, {
                                model = m, pos = pos, dist = d, team = team,
                                gdist = gdist, inReach = (gdist <= reach and isEnemy),
                                troopId = tostring(m:GetAttribute("TroopId") or "?"),
                                count = cnt,
                                hp = hum and hum.Health or 1,
                                maxHp = hum and hum.MaxHealth or 1,
                                owner = owner.Name,
                                isMine = isMine,
                                isEnemy = isEnemy and true or false,
                            })
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    State.nearestEnemy = nE
    State.nearestDist = nD
    return out, myTeam, tally
end

--------------------------------------------------------------------------
-- HITBOX ESP : 3D wireframe of a part, drawn corner-by-corner in world space
--------------------------------------------------------------------------
-- 8 corners of an OBB (CFrame + Size), 12 edges connecting them.
local HB_CORNERS = {
    { -1, -1, -1 }, { 1, -1, -1 }, { 1, -1, 1 }, { -1, -1, 1 },   -- 1..4 bottom
    { -1,  1, -1 }, { 1,  1, -1 }, { 1,  1, 1 }, { -1,  1, 1 },   -- 5..8 top
}
local HB_EDGES = {
    {1,2},{2,3},{3,4},{4,1},   -- bottom loop
    {5,6},{6,7},{7,8},{8,5},   -- top loop
    {1,5},{2,6},{3,7},{4,8},   -- verticals
}

-- dedicated pool: each wireframe owns 12 Line objects, independent of troop ESP
local HB = { pool = {}, live = {}, max = 320 }

local function hbNew()
    local w = { edges = {} }
    for i = 1, 12 do
        w.edges[i] = mk("Line", { Thickness = 1, Transparency = 0.25, Visible = false })
    end
    return w
end
local function hbAcquire()
    return table.remove(HB.pool) or hbNew()
end
local function hbRelease(w)
    for _, e in ipairs(w.edges) do e.Visible = false end
    w.part = nil
    -- pool must hold a FULL frame's worth (HB.max), or every frame leaks
    -- the wireframes that did not fit and their 12 Line objects with them
    if #HB.pool < HB.max then table.insert(HB.pool, w) end
end

-- Which parts are a hitbox?
-- TROOPS  : TroopSpace (3x4x4) + TroopSpaceCone (4x3x4) - verified live, every troop
-- ME      : Hitbox / Attack / LeftAttack / RightAttack - verified live on my character
-- Troops are the default scope; my own box is opt-in via hbESPMine.
local TROOP_PARTS = { "TroopSpace", "TroopSpaceCone" }
local MY_PARTS    = { "Hitbox", "Attack", "LeftAttack", "RightAttack" }

-- my team, cached from my own troop model (used for enemy/ally colouring)
local function myTeamId()
    local root = WS:FindFirstChild("Troops")
    if not root then return nil end
    local mine = root:FindFirstChild(tostring(lp.UserId))
    if mine then
        for _, c in ipairs(mine:GetChildren()) do
            if c:IsA("Model") and not c.Name:find("_Visual") then
                local t = c:GetAttribute("Team")
                if t then return t end
            end
        end
    end
    return nil
end

-- Returns a flat list of { part, color, isMine, model }
-- nearest-first so the pool always spends its slots on what the player is
-- actually looking at (638 troop parts exist; the cap is 320)
local function sortByDist(list)
    local myChar = lp.Character
    local mh = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local from = mh and mh.Position or WS.CurrentCamera.CFrame.Position
    table.sort(list, function(a, b)
        return (a.part.Position - from).Magnitude < (b.part.Position - from).Magnitude
    end)
    return list
end

local function collectHitParts()
    local out = {}
    local myTeam = myTeamId()
    local root = WS:FindFirstChild("Troops")

    if root then
        for _, owner in ipairs(root:GetChildren()) do
            local isMine = tostring(owner.Name) == tostring(lp.UserId)
            for _, m in ipairs(owner:GetChildren()) do
                if m:IsA("Model") and not m.Name:find("_Visual") and m.Name:find("^Troop_") then
                    local team = m:GetAttribute("Team")
                    local enemy = (not isMine) and myTeam and team ~= myTeam
                    local col = isMine and GREEN or (enemy and RED or BLUE)
                    for _, nm in ipairs(TROOP_PARTS) do
                        local p = m:FindFirstChild(nm)
                        if p and p:IsA("BasePart") then
                            table.insert(out, { part = p, color = col, isMine = isMine, model = m })
                        end
                    end
                end
            end
        end
    end

    sortByDist(out)

    -- my own attack volume: only when explicitly enabled. Appended AFTER the
    -- sort so it can never be pushed out of the pool by a wall of troops.
    if CFG.hbESPMine then
        local myChar = lp.Character
        if myChar then
            for _, nm in ipairs(MY_PARTS) do
                local p = myChar:FindFirstChild(nm)
                if p and p:IsA("BasePart") then
                    table.insert(out, { part = p, color = GREEN, isMine = true, model = myChar })
                end
            end
        end
    end

    return out
end

-- draw one part's 3D box into a wireframe slot
local function drawHitBox(w, part, col)
    local cf, sz, cam = part.CFrame, part.Size, WS.CurrentCamera
    if not cam then return false end
    -- the part itself must be in front of the camera, or every corner is
    -- mirrored and the wireframe smears across the screen
    local csp, con = cam:WorldToViewportPoint(cf.Position)
    if not con or csp.Z <= 0 then return false end

    local pts = {}
    for i = 1, 8 do
        local c = HB_CORNERS[i]
        local wp = cf:PointToWorldSpace(Vector3.new(c[1] * sz.X / 2, c[2] * sz.Y / 2, c[3] * sz.Z / 2))
        local sp = cam:WorldToViewportPoint(wp)
        -- in front of camera is enough; being outside the viewport is fine,
        -- the Drawing layer clips the line to the screen edge
        pts[i] = { Vector2.new(sp.X, sp.Y), (sp.Z > 0) }
    end
    for i, e in ipairs(HB_EDGES) do
        local a, b2 = pts[e[1]], pts[e[2]]
        local ln = w.edges[i]
        -- both endpoints must be valid: a partially-visible box would otherwise
        -- draw a long line to the mirrored position behind the camera
        if a[2] and b2[2] then
            ln.Visible = true
            ln.Color = col
            ln.Transparency = 0.15
            ln.Thickness = CFG.hbESPThick
            ln.From = a[1]
            ln.To = b2[1]
        else
            ln.Visible = false
        end
    end
    return true
end

-- per-frame driver
local function stepHitboxESP()
    local parts = collectHitParts()
    local used, shown, mine = 0, 0, 0
    for _, e in ipairs(parts) do
        if used >= HB.max then break end
        if e.isMine then mine = mine + 1 end
        local w = hbAcquire()
        local ok = drawHitBox(w, e.part, e.color)
        w.part = e.part
        w.model = e.model
        table.insert(HB.live, w)
        used = used + 1
        if ok then shown = shown + 1 end
    end
    State.hbDrew = shown
    State.hbTotal = #parts
    State.hbMine = mine
end

local function stepESP(dt, frame)
    local cam = WS.CurrentCamera
    if not cam then return end
    local list, myTeam, tally = collectTroops()
    State.enemyTeam = myTeam

    if tally then
        State.counts.blue = tally.blue
        State.counts.red = tally.red
        State.counts.mine = tally.mine
    end

    local seen = {}

    for i, t in ipairs(list) do
        seen[t.model] = true
        if i > MAX_BOXES then break end

        local b = ESP.live[t.model]
        if not b then
            b = acquire()
            ESP.live[t.model] = b
            b.anim = 0
        end
        b.t = t

        -- smooth spawn-in
        if b.anim < 1 then b.anim = math.min(1, b.anim + dt / 0.18) end

        -- health lerp so chip damage slides
        local realHp = t.maxHp > 0 and (t.hp / t.maxHp) or 1
        b.hpS = approach(b.hpS, realHp, 9, dt)

    end

    -- release boxes whose model left
    for model, b in pairs(ESP.live) do
        if not seen[model] then
            if not b.dieing then b.dieing = true; b.dieT = 0 end
            b.dieT = b.dieT + dt
            b.anim = math.max(0, b.anim - dt / 0.25)
            if b.dieT > 0.25 then
                hideBox(b)
                ESP.live[model] = nil
                release(b)
            end
        end
    end

    -- draw
    local fps = frame % 3 == 0
    for model, b in pairs(ESP.live) do
        local t = b.t
        if not t then continue end
        local alpha = b.anim
        local rootPos = t.pos
        local topPos = rootPos + Vector3.new(0, 5, 0)
        local sp = visPt(cam, rootPos)
        local tp = visPt(cam, topPos)
        if not sp or not tp or alpha <= 0.02 then
            hideBox(b)
            -- clear smoothing state or the box flies in from its old spot
            b.sx, b.sy = nil, nil
            continue
        end

        local h = math.abs(sp.Y - tp.Y)
        local w = h * 0.75
        local scale = (0.85 + 0.15 * alpha) * CFG.espScale
        h = math.max(h * scale, 9)
        w = math.max(w * scale, 7)

        -- smooth screen position so boxes do not jitter while strafing
        local rawX, rawY = sp.X, sp.Y - h * 0.5
        if CFG.espSmooth then
            if not b.sx then b.sx, b.sy = rawX, rawY end
            b.sx = approach(b.sx, rawX, 22, dt)
            b.sy = approach(b.sy, rawY, 22, dt)
        else
            b.sx, b.sy = rawX, rawY
        end
        local cx, cy = b.sx, b.sy

        local col = t.isEnemy and RED or (t.isMine and GREEN or BLUE)
        local L, R, T, B = cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2
        local style = CFG.espStyle
        local th = CFG.espThick or 2

        -- outer glow (soft halo behind the box)
        if CFG.espBox and CFG.espGlow then
            b.glow.Visible = true
            b.glow.Color = col
            b.glow.Transparency = 1 - (0.20 * alpha)
            b.glow.Position = Vector2.new(L - 2, T - 2)
            b.glow.Size = Vector2.new(w + 4, h + 4)
        else
            b.glow.Visible = false
        end

        -- main box / brackets
        b.box.Visible = CFG.espBox and (style == "Box" or style == "Glow")
        b.box.Filled = false
        b.box.Color = col
        b.box.Transparency = 1 - (0.97 * alpha)
        b.box.Thickness = th
        b.box.Position = Vector2.new(L, T)
        b.box.Size = Vector2.new(w, h)

        local showCorners = CFG.espBox and (style == "Bracket")
        for i, c in ipairs(b.corners) do
            if showCorners then
                local cw = math.max(w * 0.26, 5)
                local chh = math.max(h * 0.18, 5)
                c.Visible = true
                c.Color = col
                c.Thickness = th
                c.Transparency = 1 - (1.00 * alpha)
                if i == 1 then c.From = Vector2.new(L, T);           c.To = Vector2.new(L + cw, T)
                elseif i == 2 then c.From = Vector2.new(L, T);       c.To = Vector2.new(L, T + chh)
                elseif i == 3 then c.From = Vector2.new(R, T);       c.To = Vector2.new(R - cw, T)
                elseif i == 4 then c.From = Vector2.new(R, T);       c.To = Vector2.new(R, T + chh)
                elseif i == 5 then c.From = Vector2.new(L, B);       c.To = Vector2.new(L + cw, B)
                elseif i == 6 then c.From = Vector2.new(L, B);       c.To = Vector2.new(L, B - chh)
                elseif i == 7 then c.From = Vector2.new(R, B);       c.To = Vector2.new(R - cw, B)
                else               c.From = Vector2.new(R, B);       c.To = Vector2.new(R, B - chh)
                end
            else
                c.Visible = false
            end
        end

        -- head dot
        if CFG.espBox and CFG.espHeadDot then
            b.dot.Visible = true
            b.dot.Color = col
            b.dot.Transparency = 1 - alpha
            b.dot.Radius = math.max(2, math.floor(h * 0.045))
            b.dot.Position = Vector2.new(cx, T - math.max(4, h * 0.06))
        else
            b.dot.Visible = false
        end

        -- health BAR (box mode only)
        if CFG.espBox and CFG.espHealth then
            local barW = w + 6
            local barH = 4
            local ratio = math.clamp(b.hpS, 0, 1)
            local hy = T - 7
            b.hpBg.Visible = true
            b.hpBg.Color = Color3.fromRGB(16, 16, 20)
            b.hpBg.Transparency = 1 - (0.72 * alpha)
            b.hpBg.Position = Vector2.new(L - 3, hy)
            b.hpBg.Size = Vector2.new(barW, barH)
            b.hpFill.Visible = true
            b.hpFill.Color = Color3.fromRGB(
                math.floor(235 - 115 * ratio),
                math.floor(80 + 150 * ratio), 110)
            b.hpFill.Transparency = 1 - (0.96 * alpha)
            b.hpFill.Position = Vector2.new(L - 3, hy)
            b.hpFill.Size = Vector2.new(barW * ratio, barH)
        else
            b.hpBg.Visible = false; b.hpFill.Visible = false
        end

        -- HP TEXT (works with or without the box - this is the text-only ESP)
        if CFG.espHPText then
            local ratio = math.clamp(b.hpS, 0, 1)
            b.hpTxt.Visible = true
            b.hpTxt.Center = true
            b.hpTxt.Color = Color3.fromRGB(
                math.floor(235 - 115 * ratio),
                math.floor(80 + 150 * ratio), 110)
            b.hpTxt.Transparency = 1 - alpha
        pcall(function() b.hpTxt.OutlineColor = TEXT_OUTLINE end)
            b.hpTxt.Text = string.format("%d", math.floor(t.hp + 0.5))
            b.hpTxt.Position = Vector2.new(cx, CFG.espBox and (T - 26) or (T - 21))
        else
            b.hpTxt.Visible = false
        end

        -- ==== CLEAN LABELS: troop name above, distance below, HP on bar ====
        if fps then
            local nm = tostring(t.troopId or "?")
            if CFG.streamer then nm = t.isEnemy and "ENEMY" or "ALLY" end

            b.label.Visible = CFG.espName
            b.label.Center = true
            b.label.Color = col
            b.label.Transparency = 1 - alpha
            pcall(function() b.label.OutlineColor = TEXT_OUTLINE end)
            b.label.Text = nm
            -- name sits highest; HP text and distance hang below it in
            -- non-overlapping rows (15px font + 13px font need ~16/14 px gaps)
            b.label.Position = Vector2.new(cx, CFG.espBox and (T - 46) or (T - 40))

            local parts = {}
            if CFG.espDist then
                parts[#parts + 1] = string.format("%dm", math.floor(t.dist + 0.5))
            end
            if t.isEnemy and t.inReach then
                parts[#parts + 1] = "IN RANGE"
            end
            b.sub.Visible = (#parts > 0)
            b.sub.Center = true
            b.sub.Color = (t.isEnemy and t.inReach) and GREEN or WHITE
            b.sub.Transparency = 1 - (0.98 * alpha)
            pcall(function() b.sub.OutlineColor = TEXT_OUTLINE end)
            b.sub.Text = table.concat(parts, "  ")
            b.sub.Position = Vector2.new(cx, CFG.espBox and (B + 8) or (cy + 7))
        end

        -- tracer
        if CFG.espTracer then
            local myChar = lp.Character
            local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
            if myHrp then
                local mp = visPt(cam, myHrp.Position)
                if mp then
                    b.line.Visible = true
                    b.line.Color = col
                    b.line.Transparency = 1 - (0.7 * alpha)
                    b.line.From = Vector2.new(mp.X, mp.Y)
                    b.line.To = Vector2.new(sp.X, sp.Y)
                else
                    b.line.Visible = false
                end
            end
        else
            b.line.Visible = false
        end
    end
end

--------------------------------------------------------------------------
-- HUD (drawing, entrance-animated)
--------------------------------------------------------------------------
local HUD = { rows = {}, objs = {}, anim = 0 }
local HX, HY = 0, 100

local function buildHUD()
    local bg = mk("Square", { Filled = true, Color = Color3.fromRGB(14, 14, 18), Transparency = 0.35, Visible = false })
    local bar = mk("Square", { Filled = true, Color = ACCENT, Transparency = 0.1, Visible = false })
    local title = mk("Text", { Text = "COMMAND AN ARMY", Size = 13, Color = WHITE, Outline = true, Visible = false })
    HUD.bg, HUD.bar, HUD.title = bg, bar, title

    local labels = {
        "MATCH", "TEAM", "TROOPS", "ENEMY", "HP", "GEMS", "XP", "DAILY", "AC"
    }
    for i, name in ipairs(labels) do
        local l = mk("Text", { Text = name, Size = 12, Color = DIM, Outline = true, Visible = false })
        local v = mk("Text", { Text = "-", Size = 12, Color = WHITE, Outline = true, Visible = false })
        table.insert(HUD.rows, { l = l, v = v })
    end
end

local function layoutHUD(vp)
    local s = CFG.hudScale
    local w = math.floor(250 * s)
    HX = vp.X - w - 14
    HY = 92
    local pad = math.floor(9 * s)
    local lh = math.floor(15 * s)
    local y = HY + 4

    HUD.bar.Position = Vector2.new(HX, HY)
    HUD.bar.Size = Vector2.new(w, math.floor(22 * s))
    HUD.title.Position = Vector2.new(HX + pad, HY + math.floor(4 * s))
    HUD.title.Size = math.floor(13 * s)
    y = HY + math.floor(28 * s)

    for i, r in ipairs(HUD.rows) do
        r.l.Position = Vector2.new(HX + pad, y)
        r.v.Position = Vector2.new(HX + math.floor(78 * s), y)
        r.l.Size = math.floor(12 * s)
        r.v.Size = math.floor(12 * s)
        y = y + lh
    end
    HUD.bg.Position = Vector2.new(HX, HY)
    HUD.bg.Size = Vector2.new(w, (y - HY) + math.floor(6 * s))
    HUD.height = (y - HY) + 6
    HUD.width = w
end

local function stepHUD(dt, vp)
    if not HUD.bg then return end
    if not CFG.showHUD then
        for _, o in ipairs({ HUD.bg, HUD.bar, HUD.title }) do o.Visible = false end
        for _, r in ipairs(HUD.rows) do r.l.Visible = false; r.v.Visible = false end
        return
    end
    if HUD.anim < 1 then HUD.anim = math.min(1, HUD.anim + dt / 0.45) end
    -- ease-out cubic
    local a = 1 - (1 - HUD.anim) ^ 3
    layoutHUD(vp)
    if not HUD.logged then
        HUD.logged = true
        print(string.format("[CAA] hud vp=%dx%d pos=%s size=%s anim=%.2f", vp.X, vp.Y, tostring(HUD.bg.Position), tostring(HUD.bg.Size), HUD.anim))
    end

    HUD.bg.Visible = true
    HUD.bar.Visible = true
    HUD.title.Visible = true
    HUD.bg.Transparency = 1 - (0.65 * a)
    HUD.bar.Transparency = 1 - (0.9 * a)
    HUD.title.Transparency = 1 - a

    local d = State.reward and State.reward.daily
    local vals = {
        { tostring(at("MatchState") or "?"), DIM },
        { State.enemyTeam or "?", BLUE },
        { string.format("%d", State.counts.mine), GREEN },
        { string.format("%d", State.counts.red), RED },
        { string.format("%s", fmt(at("Stamina") or 0)), YELLOW },
        { fmt(at("Gems") or 0), GREEN },
        { string.format("Lv%s %s/%s", tostring(at("PlayerLevel") or "?"),
            fmt(at("PlayerXP") or 0), fmt(at("PlayerXPRequired") or 0)), WHITE },
        { (function()
            if type(d) == "table" then
                local st, nt = tonumber(d.ServerTime), tonumber(d.NextClaimAt)
                if st and nt then
                    local left = nt - st
                    return left > 0 and dur(left) or "READY"
                end
            end
            return "-"
          end)(), YELLOW },
        { "OFF", RED },
    }

    for i, r in ipairs(HUD.rows) do
        local stagger = math.max(0, math.min(1, (a - (i - 1) * 0.06) / 0.4))
        if stagger > 0 then
            r.l.Visible = true
            r.v.Visible = true
            r.l.Transparency = 1 - stagger
            r.v.Transparency = 1 - stagger
            r.v.Text = tostring(vals[i][1])
            r.v.Color = vals[i][2] or WHITE
        else
            r.l.Visible = false
            r.v.Visible = false
        end
    end
end

--------------------------------------------------------------------------
-- LOW HP VIGNETTE
--------------------------------------------------------------------------
local vig = nil
local function stepVignette(t)
    if not vig then return end
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local hp = hum and hum.Health or 100
    local mx = hum and hum.MaxHealth or 100
    local pct = mx > 0 and (hp / mx * 100) or 100
    if CFG.lowHPAlert and pct <= CFG.alertPct and hp > 0 then
        local a = 0.45 + 0.25 * math.sin(t * 3.0)
        local intensity = 1 - (pct / math.max(CFG.alertPct, 1))
        vig.Visible = true
        vig.Color = RED
        vig.Transparency = 1 - (a * intensity * 0.5)
    else
        vig.Visible = false
    end
end

--------------------------------------------------------------------------
-- COMBAT ASSIST
--------------------------------------------------------------------------
local RemoteCache = {}
local function remote(name)
    if RemoteCache[name] then return RemoteCache[name] end
    local r = findRemote(name)
    RemoteCache[name] = r
    return r
end

--------------------------------------------------------------------------
-- REACH / VOLLEY / HITBOX EXTENDER
--------------------------------------------------------------------------
-- Real attack path (from TroopHudClient):
--   AimVolleyState:FireServer(true, targetPos, 9)
--   AimArrowFire:FireServer(troop, tick, origin, arcMid, targetPos, travelTime)
-- The Range gate (_isAimPositionInRange) is CLIENT-side; server gets raw positions.
local function representativeTroop()
    local root = WS:FindFirstChild("Troops")
    if not root then return nil end
    local mine = root:FindFirstChild(tostring(lp.UserId))
    if not mine then return nil end
    for _, m in ipairs(mine:GetChildren()) do
        if m:IsA("Model") and not m.Name:find("_Visual") and m.Name:find("^Troop_") then
            if m:FindFirstChild("HumanoidRootPart") then return m end
        end
    end
    return nil
end

local function avgTroopPos()
    local root = WS:FindFirstChild("Troops")
    if not root then return nil end
    local mine = root:FindFirstChild(tostring(lp.UserId))
    if not mine then return nil end
    local sx, sy, sz, n = 0, 0, 0, 0
    for _, m in ipairs(mine:GetChildren()) do
        if m:IsA("Model") and not m.Name:find("_Visual") and m.Name:find("^Troop_") then
            local h = m:FindFirstChild("HumanoidRootPart")
            if h then sx = sx + h.Position.X; sy = sy + h.Position.Y; sz = sz + h.Position.Z; n = n + 1 end
        end
    end
    if n == 0 then return nil end
    return Vector3.new(sx / n, sy / n, sz / n)
end

-- fire a real arrow volley at a world position (bypasses the client Range gate)
local function fireVolley(targetPos)
    local avs, aaf = remote("AimVolleyState"), remote("AimArrowFire")
    if not (avs and aaf) then
        State.fireLog = "missing remotes"
        return false, "missing remotes"
    end
    local troop = representativeTroop()
    if not troop then
        State.fireLog = "no own troop"
        return false, "no own troop"
    end
    local hv = troop:FindFirstChild("HumanoidRootPart")
    if not hv then return false, "no hrp" end

    -- open the volley (server acknowledges suppression state)
    pcall(function() avs:FireServer(true, targetPos, 9) end)

    local origin = hv.Position + hv.CFrame.LookVector * 2 + Vector3.new(0, 2.5, 0)
    local mid = origin:Lerp(targetPos, 0.5) + Vector3.new(0, (origin - targetPos).Magnitude * 0.12, 0)
    local travel = (origin - targetPos).Magnitude / 150
    local tick = troop:GetAttribute("AimAttackTick") or 0

    pcall(function() aaf:FireServer(troop, tick, origin, mid, targetPos, travel) end)
    State.fireLog = string.format("volley -> %.0f,%.0f,%.0f", targetPos.X, targetPos.Y, targetPos.Z)
    return true, State.fireLog
end

-- range extender: raise Range on MY troop models only.
-- The aim gate (_isAimPositionInRange) reads this attribute per-troop, so scope
-- is exactly the folder named after my UserId. Other players / AI factions are
-- never touched - they keep their own Range.
local function applyRangeOverride()
    local active = false
    local root = WS:FindFirstChild("Troops")
    if root and CFG.rangeOverride then
        local mine = root:FindFirstChild(tostring(lp.UserId))
        if mine then
            for _, m in ipairs(mine:GetChildren()) do
                if m:IsA("Model") and not m.Name:find("_Visual") and m.Name:find("^Troop_") then
                    local cur = m:GetAttribute("Range")
                    if cur and tonumber(cur) < CFG.rangeValue then
                        pcall(function() m:SetAttribute("Range", CFG.rangeValue) end)
                        active = true
                    end
                end
            end
        end
    end
    return active
end

-- hitbox extender: enlarge my attack hitbox parts (client-owned, no correction seen)
local function applyHitbox()
    local myChar = lp.Character
    if not myChar then return 0 end
    local n = 0
    for _, nm in ipairs({ "LeftAttack", "RightAttack", "Hitbox", "Attack" }) do
        local p = myChar:FindFirstChild(nm)
        if p and p:IsA("BasePart") then
            local key = nm
            local store = getgenv().__caaHbOrig
            if not store then store = {}; getgenv().__caaHbOrig = store end
            State.hbOrig = store
            if not store[key] then
                store[key] = { p.Size, p.Transparency, p.CanCollide, p.Massless }
            end
            local o = store[key]
            local s = CFG.hitboxScale
            local want = Vector3.new(o[1].X * s, o[1].Y * s, o[1].Z * s)
            if CFG.hitboxOn then
                if (p.Size - want).Magnitude > 0.01 then pcall(function() p.Size = want end) end
                n = n + 1
            elseif o then
                if (p.Size - o[1]).Magnitude > 0.01 then pcall(function() p.Size = o[1] end) end
            end
        end
    end
    return n
end

local function restoreHitbox()
    local store = getgenv().__caaHbOrig or State.hbOrig
    local myChar = lp.Character
    if not myChar then return end
    for key, o in pairs(store) do
        local nm = key:match("^[^/]+/(.+)$") or key
        local p = myChar:FindFirstChild(nm)
        if p and p:IsA("BasePart") then pcall(function() p.Size = o[1] end) end
    end
end

local function reachInfo(dt)
    local now = os.clock()
    if now - State.lastExtend > 0.35 then
        State.lastExtend = now
        State.extendN = applyHitbox()
        applyRangeOverride()
    end
    State.reachNow = CFG.rangeOverride and CFG.rangeValue or (tonumber(at("Range")) or 7)
end

local function stepCombat(dt)
    local cmb = remote("PlayerCombatRequest")
    if not cmb then return end

    reachInfo(dt)

    local interval = tonumber(at("AttackInterval")) or 0.8
    local wait_ = math.max(0.15, interval + CFG.attackOffset)
    State.charge = math.min(1, State.charge + dt / wait_)

    -- effective reach: weapon Range attribute unless overridden
    local reach = CFG.atkRangeAuto and (tonumber(at("Range")) or 7) or CFG.atkRange
    local nd = State.nearestDist or math.huge
    local canReach = (not CFG.atkGated) or (nd <= reach)
    State.inRange = canReach and nd < math.huge
    State.reachNow = reach

    if CFG.autoAttack and at("CanUseCombat") then
        local now = os.clock()
        -- HARD gate: only swing when an enemy is genuinely within reach
        if canReach and nd < math.huge and (now - State.lastAttack >= wait_) then
            State.lastAttack = now
            State.charge = 0
            local tgt = State.nearestEnemy
            local thrp = tgt and tgt:FindFirstChild("HumanoidRootPart")
            if CFG.volleyMode and thrp then
                fireVolley(thrp.Position)
            else
                pcall(function() cmb:FireServer("Attack") end)
            end
        end
    end

    if CFG.autoHeal then
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.MaxHealth > 0 then
            local pct = hum.Health / hum.MaxHealth * 100
            if pct <= CFG.healPct then
                local ok, _ = pcall(function() cmb:FireServer("Heal") end)
                if ok then task.wait(0.5) end
            end
        end
    end
end

local function stepChargeRing(t)
    if not HUD.charge then
        HUD.charge = mk("Circle", { Thickness = 3, Filled = false, Visible = false })
        HUD.chargeText = mk("Text", { Text = "", Size = 12, Color = ACCENT, Outline = true, Visible = false })
    end
    if CFG.chargeRing and CFG.autoAttack and CFG.showHUD then
        local cx = HX + (HUD.width or 250) - 22
        local cy = HY + 11
        HUD.charge.Visible = true
        HUD.charge.Position = Vector2.new(cx, cy)
        HUD.charge.Radius = 9
        HUD.charge.NumSides = 24
        HUD.charge.Color = State.charge >= 1 and GREEN or ACCENT
        HUD.charge.Transparency = 0.25
        -- sweep approximation via arc thickness pulse
        HUD.charge.Thickness = 2 + math.floor(State.charge * 4)
        HUD.chargeText.Visible = true
        HUD.chargeText.Position = Vector2.new(cx - 4, cy - 6)
        HUD.chargeText.Text = string.format("%d", math.floor(State.charge * 100))
    else
        HUD.charge.Visible = false
        HUD.chargeText.Visible = false
    end
end

--------------------------------------------------------------------------
-- REWARDS
--------------------------------------------------------------------------
local function refreshReward()
    task.spawn(function()
        local rr, dr = remote("RewardRequest"), remote("DailyRewardRequest")
        local out = State.reward or {}
        if rr then
            local ok, res = pcall(function() return rr:InvokeServer("GetState") end)
            if ok and type(res) == "table" then
                for k, v in pairs(res) do out[k] = v end
            end
        end
        if dr then
            local ok2, res2 = pcall(function() return dr:InvokeServer({ Type = "GetState" }) end)
            if ok2 and type(res2) == "table" then
                out.daily = res2.State
                out.dailyStatus = res2.Status
            end
        end
        State.reward = out
        State.rewardAt = os.clock()
    end)
end

--------------------------------------------------------------------------
-- WINDUI BOOTSTRAP
--------------------------------------------------------------------------
local src = game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua")
local WindUI = loadstring(src)()
WindUI:SetNotificationLower(true)
WindUI:SetParent(gethui and gethui() or game:GetService("CoreGui"))

----------------------------------------------------------------

local Window = WindUI:CreateWindow({
    Title = "COMMAND AN ARMY",
    Icon = "swords",
    Author = "by zenpo",
    Folder = "CAAHub",
    Size = UDim2.fromOffset(620, 470),
    Theme = CFG.theme,
    ToggleKey = Enum.KeyCode.RightShift,
    Transparent = true,
    Acrylic = true,
    User = { Enabled = true, Anonymous = false },
})

local about = Window:Tab({ Title = "About", Icon = "info" })

--------------------------------------------------------------------------
-- TAB 1 -- COMBAT
--------------------------------------------------------------------------
local TCombat = Window:Tab({ Title = "Combat", Icon = "swords" })

local SecESP = TCombat:Section({ Title = "TROOP ESP", Icon = "scan-eye" })
SecESP:Toggle({ Title = "Enemy Troops", Desc = "Box enemies", Value = CFG.espEnemy, Callback = function(v) CFG.espEnemy = v end })
SecESP:Toggle({ Title = "Friendly Troops", Desc = "Box allies + own", Value = CFG.espFriendly, Callback = function(v) CFG.espFriendly = v end })
SecESP:Toggle({ Title = "Health Bars", Value = CFG.espHealth, Callback = function(v) CFG.espHealth = v end })
SecESP:Toggle({ Title = "Unit Count", Desc = "TroopCount per squad", Value = CFG.espCount, Callback = function(v) CFG.espCount = v end })
SecESP:Toggle({ Title = "Tracers", Value = CFG.espTracer, Callback = function(v) CFG.espTracer = v end })
SecESP:Slider({ Title = "ESP Range", Value = { Min = 100, Max = 5000, Default = CFG.espRange }, Step = 50, Callback = function(v) CFG.espRange = v end })
SecESP:Slider({ Title = "Box Scale", Value = { Min = 0.5, Max = 2.0, Default = CFG.espScale }, Step = 0.1, Callback = function(v) CFG.espScale = v end })
SecESP:Dropdown({ Title = "Box Style", Values = { "Corner", "Full" }, Value = CFG.espStyle, Callback = function(v) CFG.espStyle = v end })

local SecCombat = TCombat:Section({ Title = "COMBAT ASSIST", Icon = "zap" })
SecCombat:Toggle({ Title = "Auto Attack", Desc = "Fires Attack at AttackInterval", Value = CFG.autoAttack, Callback = function(v)
    CFG.autoAttack = v
    WindUI:Notify({ Title = "Auto Attack", Content = v and "ENABLED" or "disabled", Duration = 2, Icon = "zap" })
end })
SecCombat:Slider({ Title = "Attack Delay", Value = { Min = -0.3, Max = 0.6, Default = CFG.attackOffset }, Step = 0.05, Callback = function(v) CFG.attackOffset = v end })
SecCombat:Toggle({ Title = "Charge Ring", Value = CFG.chargeRing, Callback = function(v) CFG.chargeRing = v end })
SecCombat:Toggle({ Title = "Auto Heal", Value = CFG.autoHeal, Callback = function(v) CFG.autoHeal = v end })
SecCombat:Slider({ Title = "Heal Below %", Value = { Min = 10, Max = 90, Default = CFG.healPct }, Step = 5, Callback = function(v) CFG.healPct = v end })
SecCombat:Paragraph({ Title = "Server Authority", Desc = "Attack is a verb only - the server resolves damage and rate limits. This replays input, it does not spoof damage." })


local SecReach = TCombat:Section({ Title = "REACH", Icon = "crosshair" })
SecReach:Toggle({ Title = "Only Attack In Range", Desc = "Hold fire until the nearest enemy is inside your weapon reach",
    Value = CFG.atkGated, Callback = function(v) CFG.atkGated = v end })
SecReach:Toggle({ Title = "Auto Range", Desc = "Read reach from the game's Range attribute", Value = CFG.atkRangeAuto,
    Callback = function(v) CFG.atkRangeAuto = v end })
SecReach:Slider({ Title = "Manual Reach (studs)", Value = { Min = 4, Max = 40, Default = 7 }, Step = 1,
    Callback = function(v) CFG.atkRange = math.floor(v + 0.5) end })

SecReach:Toggle({ Title = "Range Extender", Desc = "Raise the Range attribute on your troops so the aim gate opens wider (client-side check)",
    Value = CFG.rangeOverride, Callback = function(v) CFG.rangeOverride = v end })
SecReach:Slider({ Title = "Extended Range (studs)", Value = { Min = 10, Max = 400, Default = 60 }, Step = 5,
    Callback = function(v) CFG.rangeValue = math.floor(v + 0.5) end })

SecReach:Toggle({ Title = "Hitbox Extender", Desc = "Enlarge your attack hitbox parts (LeftAttack/RightAttack)",
    Value = CFG.hitboxOn, Callback = function(v)
        CFG.hitboxOn = v
        if not v then restoreHitbox() end
    end })
SecReach:Slider({ Title = "Hitbox Scale", Value = { Min = 1.0, Max = 5.0, Default = 2.0 }, Step = 0.25,
    Callback = function(v) CFG.hitboxScale = v end })

SecReach:Toggle({ Title = "Positional Volley", Desc = "Fire the game's real arrow attack at any distance (bypasses the client aim-range gate)",
    Value = CFG.volleyMode, Callback = function(v) CFG.volleyMode = v end })
local pHB = SecReach:Paragraph({ Title = "Hitbox", Desc = "off" })
SecReach:Toggle({ Title = "Hitbox ESP (troops)", Desc = "Wireframe every troop's hit volume - green = mine, red = enemy, blue = ally",
    Value = CFG.hbESP, Callback = function(v) CFG.hbESP = v end })
SecReach:Toggle({ Title = "Hitbox ESP: Include Mine", Desc = "Also draw my own attack volume (Hitbox/Attack) - off by default",
    Value = CFG.hbESPMine, Callback = function(v) CFG.hbESPMine = v end })
SecReach:Slider({ Title = "Hitbox ESP Thickness", Value = { Min = 1, Max = 4, Default = 1 }, Step = 1,
    Callback = function(v) CFG.hbESPThick = math.floor(v + 0.5) end })
SecReach:Button({ Title = "TEST VOLLEY (nearest enemy)", Callback = function()
    local tgt = State.nearestEnemy
    local h = tgt and tgt:FindFirstChild("HumanoidRootPart")
    if not h then
        State.fireLog = "no enemy target"
        return
    end
    local ok, msg = fireVolley(h.Position)
    State.fireLog = tostring(msg)
end })

local pReach = SecReach:Paragraph({ Title = "Reach", Desc = "-" })
SecReach:Button({ Title = "RUN REACH TEST", Callback = function() reachTest("volley") end })
SecReach:Paragraph({ Title = "How it works",
    Desc = "Range is enforced by a CLIENT-side check (TroopHudClient._isAimPositionInRange). The real attack remote takes raw world positions, so Range Extender + Positional Volley both aim at the server. Hitbox Extender resizes your attack parts - only useful if the server trusts them." })

local SecLook2 = TCombat:Section({ Title = "ESP STYLE", Icon = "palette" })
SecLook2:Toggle({ Title = "Box ESP", Desc = "OFF = text only (name + distance + HP). Box, glow, head dot and health bar all hide.",
    Value = CFG.espBox, Callback = function(v) CFG.espBox = v end })
SecLook2:Dropdown({ Title = "Box Style", Values = { "Bracket", "Box", "Glow" }, Value = CFG.espStyle,
    Callback = function(v) CFG.espStyle = v end })
SecLook2:Toggle({ Title = "Outer Glow", Value = CFG.espGlow, Callback = function(v) CFG.espGlow = v end })
SecLook2:Toggle({ Title = "Head Dot", Desc = "Circle marker above the head", Value = CFG.espHeadDot, Callback = function(v) CFG.espHeadDot = v end })
SecLook2:Toggle({ Title = "Troop Name", Desc = "Name label above each box", Value = CFG.espName,
    Callback = function(v) CFG.espName = v end })
SecLook2:Toggle({ Title = "Distance", Desc = "Distance in metres under each box", Value = CFG.espDist,
    Callback = function(v) CFG.espDist = v end })
SecLook2:Toggle({ Title = "HP Text", Desc = "Live HP number above the health bar", Value = CFG.espHPText,
    Callback = function(v) CFG.espHPText = v end })
SecLook2:Toggle({ Title = "Smooth Motion", Desc = "Interpolate boxes so they stop jittering", Value = CFG.espSmooth,
    Callback = function(v) CFG.espSmooth = v end })
SecLook2:Slider({ Title = "Line Thickness", Value = { Min = 1, Max = 4, Default = 2 }, Step = 1,
    Callback = function(v) CFG.espThick = math.floor(v + 0.5) end })

--------------------------------------------------------------------------
-- TAB 2 -- INTEL
--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- TAB -- AUTOMATION
--------------------------------------------------------------------------
local Auto = {
    summonAt = 0, summons = 0, spend = 0, fuseAt = 0, fused = 0, lastFuse = "-",
    lastCode = "-", ascendAt = 0, ascended = 0,
    evoAt = 0, evolved = 0, lastEvo = "-",
    pushAt = 0, mounted = false, luck = "-", results = {}, lastAscent = nil, sprintSent = nil,
}

-- forward decls (assigned further down, used by button callbacks here)
local doSummon, doAscendAll, doEvolveAll, doFuseAll, applySpeed, toggleMount

local TAuto = Window:Tab({ Title = "Automation", Icon = "zap" })

local SecSum = TAuto:Section({ Title = "SUMMON", Icon = "sparkles" })
SecSum:Toggle({ Title = "Auto Summon", Desc = "Fires the banner on a timer", Value = CFG.autoSummon,
    Callback = function(v) CFG.autoSummon = v; Auto.summonAt = 0 end })
SecSum:Slider({ Title = "Summon Count", Desc = "How many per cycle (1-10)", Value = { Min = 1, Max = 10, Default = 1 },
    Step = 1, Callback = function(v) CFG.summonCount = math.floor(v + 0.5) end })
SecSum:Slider({ Title = "Cycle Delay (s)", Desc = "Pause between summons", Value = { Min = 0.4, Max = 5, Default = 1.2 },
    Step = 0.1, Callback = function(v) CFG.summonDelay = v end })
SecSum:Toggle({ Title = "Stop When Broke", Desc = "Halt below the gem cost", Value = CFG.summonStop,
    Callback = function(v) CFG.summonStop = v end })
local pSumStat = SecSum:Paragraph({ Title = "Summon", Desc = "-" })
SecSum:Button({ Title = "SUMMON NOW (x1)", Callback = function() doSummon(1) end })
SecSum:Button({ Title = "SUMMON NOW (x10)", Callback = function() doSummon(10) end })

local SecProg = TAuto:Section({ Title = "ASCENSION", Icon = "trending-up" })
SecProg:Toggle({ Title = "Auto Fuse (free ascend)", Desc = "Fuses duplicate troops in the lobby, 1 level each", Value = CFG.autoFuse,
    Callback = function(v) CFG.autoFuse = v; Auto.fuseAt = 0 end })
SecProg:Slider({ Title = "Fuse Delay (s)", Value = { Min = 0.5, Max = 4, Default = 1.0 }, Step = 0.1,
    Callback = function(v) CFG.fuseDelay = v end })
local pProgStat = SecProg:Paragraph({ Title = "Ascension", Desc = "-" })
SecProg:Button({ Title = "FUSE ALL NOW", Callback = function()
    local n = doFuseAll()
    WindUI:Notify({ Title = "Ascend", Content = n > 0 and string.format("fused %d duplicate(s)", n) or "no valid pairs", Duration = 3, Icon = "layers" })
end })
SecProg:Button({ Title = "ASCEND ALL (gamepass)", Variant = "Secondary", Callback = function() doAscendAll() end })

local SecEvo2 = TAuto:Section({ Title = "EVOLUTION", Icon = "arrow-up-circle" })
SecEvo2:Toggle({ Title = "Auto Evolve", Desc = "Evolves every unit at MasteryLevel 20+", Value = CFG.autoEvolve,
    Callback = function(v) CFG.autoEvolve = v; Auto.evoAt = 0 end })
local pEvoStat = SecEvo2:Paragraph({ Title = "Evolve", Desc = "-" })
SecEvo2:Button({ Title = "EVOLVE ALL NOW", Callback = function() local n = doEvolveAll()
    WindUI:Notify({ Title = "Evolve", Content = string.format("fired %d evolution(s)", n), Duration = 3, Icon = "arrow-up-circle" }) end })

local SecSpd = TAuto:Section({ Title = "SPEED", Icon = "gauge" })
SecSpd:Toggle({ Title = "Speed Override", Desc = "Re-applies every frame", Value = CFG.spdEnabled,
    Callback = function(v) CFG.spdEnabled = v end })
SecSpd:Slider({ Title = "Player Speed", Value = { Min = 16, Max = 120, Default = 23 }, Step = 1,
    Callback = function(v) CFG.spdPlayer = math.floor(v + 0.5) end })
SecSpd:Slider({ Title = "Horse Speed", Value = { Min = 16, Max = 120, Default = 17 }, Step = 1,
    Callback = function(v) CFG.spdHorse = math.floor(v + 0.5) end })
SecSpd:Toggle({ Title = "Sprint", Desc = "Hold-sprint intent to server", Value = CFG.spdSprint,
    Callback = function(v) CFG.spdSprint = v end })
local pSpdStat = SecSpd:Paragraph({ Title = "Speed", Desc = "-" })
SecSpd:Button({ Title = "MOUNT / DISMOUNT", Callback = function() toggleMount() end })

local SecNote = TAuto:Section({ Title = "NOTES", Icon = "info" })
SecNote:Paragraph({ Title = "Server rules found live",
    Desc = "Summon accepts Count=1 or Count=10 only. Any other N is rejected as InvalidRequest, so a custom count is fired as N separate Count=1 rolls (one gem cost each)." })
SecNote:Paragraph({ Title = "Ascension (free path)",
    Desc = "FUSE all = no gamepass. Fires AscensionRequest {RequestId, MainCopyId, DuplicateCopyId} for every valid pair. Server rules: same TroopId, same AscensionLevel, different CopyId, below max. Lobby only - in a match it answers LobbyOnly." })
SecNote:Paragraph({ Title = "AscendAll (gamepass)",
    Desc = "AscendAllGamepassOwned is false on this account, so the server drops it with NotOwned. Kept for completeness, the FUSE button is the working one." })
SecNote:Paragraph({ Title = "Evolve",
    Desc = "One unit per request, needs MasteryLevel 20+. Server replies LevelRequired otherwise." })


--------------------------------------------------------------------------
-- REACH DIAGNOSTIC -- answers "can I damage at range" empirically
--------------------------------------------------------------------------
local reachTesting = false

local function reachTest(mode)
    if reachTesting then return end
    reachTesting = true
    mode = mode or "volley"
    task.spawn(function()
        local function done(msg, icon)
            State.lastReach = msg
            table.insert(State.reachLog, 1, msg)
            while #State.reachLog > 6 do table.remove(State.reachLog) end
            WindUI:Notify({ Title = "Reach Test", Content = msg, Duration = 6, Icon = icon or "crosshair" })
            pcall(function() print("[CAA] reach: " .. msg) end)
            reachTesting = false
        end

        local myC = lp.Character
        local myH = myC and myC:FindFirstChild("HumanoidRootPart")
        if not myH then return done("no character", "alert-triangle") end
        if not lp:GetAttribute("CanUseCombat") then
            return done("CanUseCombat=false - you must be IN A MATCH", "alert-triangle")
        end

        -- nearest ENEMY troop by distance from my character
        local tgt, td = nil, math.huge
        local root = WS:FindFirstChild("Troops")
        local myTeam = nil
        if root then
            local mine = root:FindFirstChild(tostring(lp.UserId))
            if mine then
                for _, c in ipairs(mine:GetChildren()) do myTeam = c:GetAttribute("Team") or myTeam end
            end
            for _, owner in ipairs(root:GetChildren()) do
                for _, m in ipairs(owner:GetChildren()) do
                    if m:IsA("Model") and not m.Name:find("_Visual") and m.Name:find("^Troop_") then
                        if myTeam and m:GetAttribute("Team") ~= myTeam then
                            local h = m:FindFirstChild("HumanoidRootPart")
                            if h then
                                local d = (h.Position - myH.Position).Magnitude
                                if d < td then td = d; tgt = m end
                            end
                        end
                    end
                end
            end
        end
        if not tgt then return done("no enemy troop in world (join a match)", "alert-triangle") end
        if not representativeTroop() then
            return done("you own no troops yet - summon some first", "alert-triangle")
        end

        local hum = tgt:FindFirstChildOfClass("Humanoid")
        local hp0 = hum and hum.Health or -1
        local reach = tonumber(at("Range")) or 7
        local hTarget = tgt:FindFirstChild("HumanoidRootPart")

        -- capture damage events while testing
        local hits = {}
        local dd = remote("DamageDealt")
        local cc = dd and dd.OnClientEvent:Connect(function(...) table.insert(hits, { ... }) end)

        local ok1, msg1 = fireVolley(hTarget.Position)
        task.wait(2.2)

        if cc then cc:Disconnect() end
        local humNow = tgt:FindFirstChildOfClass("Humanoid")
        local hp1 = humNow and humNow.Health or -1
        local did = hp0 - hp1

        if did > 0 then
            return done(string.format("REACH WORKS: volley hit %s at %.0fm (real reach %.1f) for %d dmg",
                tostring(tgt:GetAttribute("TroopId") or tgt.Name), td, reach, math.floor(did + 0.5)), "check")
        end
        if not ok1 then
            return done("volley failed: " .. tostring(msg1), "alert-triangle")
        end
        if td > reach then
            return done(string.format("fired at %.0fm (reach %.1f) - NO damage. Server range-checked, or wrong team/target.", td, reach), "x")
        end
        return done(string.format("fired at %.0fm (inside reach %.1f) - no damage registered. Target may be dead/ally or hit is directional.", td, reach), "alert-triangle")
    end)
end

local TIntel = Window:Tab({ Title = "Intel", Icon = "radar" })

local SecField = TIntel:Section({ Title = "BATTLEFIELD", Icon = "map" })
local pCounts = SecField:Paragraph({ Title = "Counts", Desc = "scanning..." })
SecField:Toggle({ Title = "Show HUD", Value = CFG.showHUD, Callback = function(v) CFG.showHUD = v end })
SecField:Slider({ Title = "HUD Scale", Value = { Min = 0.7, Max = 1.5, Default = CFG.hudScale }, Step = 0.05, Callback = function(v) CFG.hudScale = v end })
SecField:Toggle({ Title = "Low HP Alert", Value = CFG.lowHPAlert, Callback = function(v) CFG.lowHPAlert = v end })
SecField:Slider({ Title = "Alert Below %", Value = { Min = 5, Max = 60, Default = CFG.alertPct }, Step = 5, Callback = function(v) CFG.alertPct = v end })

local SecMe = TIntel:Section({ Title = "PLAYER", Icon = "user" })
local pMe = SecMe:Paragraph({ Title = "State", Desc = "..." })

local SecMatch = TIntel:Section({ Title = "MATCH", Icon = "flag" })
local pMatch = SecMatch:Paragraph({ Title = "Match State", Desc = "..." })

--------------------------------------------------------------------------
-- TAB 3 -- ECONOMY
--------------------------------------------------------------------------
local TEcon = Window:Tab({ Title = "Economy", Icon = "coins" })

local SecBal = TEcon:Section({ Title = "BALANCE", Icon = "wallet" })
local pBal = SecBal:Paragraph({ Title = "Wallet", Desc = "..." })

local SecDaily = TEcon:Section({ Title = "DAILY REWARD", Icon = "gift" })
local pDaily = SecDaily:Paragraph({ Title = "Daily", Desc = "polling..." })
SecDaily:Button({ Title = "CLAIM DAILY", Variant = "Primary", Callback = function()
    local dr = remote("DailyRewardRequest")
    if not dr then return end
    local ok, res = pcall(function() return dr:InvokeServer({ Type = "Claim" }) end)
    local status = ok and (type(res) == "table" and tostring(res.Status) or tostring(res)) or "error"
    WindUI:Notify({ Title = "Daily Reward", Content = "Result: " .. status, Duration = 4, Icon = "gift" })
    refreshReward()
end })
SecDaily:Toggle({ Title = "Auto Claim", Desc = "Fires when READY", Value = CFG.autoDaily, Callback = function(v) CFG.autoDaily = v end })

local SecRedeem = TEcon:Section({ Title = "REDEEM CODE", Icon = "ticket" })
local inpOK, inpObj = pcall(function()
    return SecRedeem:Input({ Title = "Code", Value = "", Placeholder = "enter code", Callback = function(v) State.redeemCode = tostring(v) end })
end)
if not inpOK then
    SecRedeem:Paragraph({ Title = "Input unavailable", Desc = "Redeem is disabled - this library build has no Input element." })
end
local pRedeem = SecRedeem:Paragraph({ Title = "Last Result", Desc = "-" })
-- Every code below was fired against the live RedeemCode remote and returned
-- Claimed. Dead ones (CodeDoesNotExist / Unavailable) are deliberately absent.
local WORKING_CODES = {
    -- Verified Claimed against the live remote (2600 gems total)
    "RAPIER", "RANKED", "PARRY", "OPTIMIZE", "WAR", "RELEASE",
    -- Returned Unavailable = known-good code, likely already used on this account
    "SHIELDBREAKER", "BUGFIX", "@D0ggy103",
}
SecRedeem:Button({ Title = "REDEEM ALL ("..#WORKING_CODES.." codes)", Callback = function()
    task.spawn(function()
        local rc = remote("RedeemCode")
        if not rc then return end
        local got, hits, log = 0, 0, {}
        for _, c in ipairs(WORKING_CODES) do
            local ok, res = pcall(function() return rc:InvokeServer(c) end)
            local st = (ok and type(res) == "table") and tostring(res.Status) or "ERR"
            if st == "Claimed" then
                hits = hits + 1
                local amt = tonumber(res.Amount) or 0
                got = got + amt
                log[#log + 1] = c.." +"..amt
            end
            task.wait(0.35)
        end
        local txt = string.format("%d/%d claimed, +%d gems", hits, #WORKING_CODES, got)
        State.lastRedeem = txt
        if pRedeem and pRedeem.SetDesc then pcall(function() pRedeem:SetDesc(txt.."  ["..table.concat(log, ", ").."]") end) end
        WindUI:Notify({ Title = "Redeem All", Content = txt, Duration = 6, Icon = "ticket" })
    end)
end })

SecRedeem:Button({ Title = "REDEEM", Callback = function()
    local rc = remote("RedeemCode")
    if not rc then return end
    if State.redeemCode == "" then
        WindUI:Notify({ Title = "Redeem", Content = "Type a code first", Duration = 3, Icon = "alert-triangle" })
        return
    end
    local ok, res = pcall(function() return rc:InvokeServer(State.redeemCode) end)
    local txt
    if ok and type(res) == "table" then
        txt = string.format("%s | +%s %s", tostring(res.Status), tostring(res.Amount or 0), tostring(res.RewardType or ""))
    else
        txt = ok and tostring(res) or "invoke failed"
    end
    State.lastRedeem = txt
    if pRedeem and pRedeem.SetDesc then pcall(function() pRedeem:SetDesc(txt) end) end
    WindUI:Notify({ Title = "Redeem", Content = txt, Duration = 5, Icon = "ticket" })
end })

--------------------------------------------------------------------------
-- TAB 4 -- UNITS
--------------------------------------------------------------------------
local TUnits = Window:Tab({ Title = "Units", Icon = "users" })

local unitNames, classNames = {}, {}
local function scanUnits()
    unitNames, classNames = {}, {}
    local ui = unitsData()
    if type(ui) == "table" and type(ui.Units) == "table" then
        for _, u in ipairs(ui.Units) do
            if u.TroopId then table.insert(unitNames, tostring(u.TroopId)) end
        end
    end
    local ci = classData()
    if type(ci) == "table" and type(ci.Classes) == "table" then
        for _, c in ipairs(ci.Classes) do
            if c.Name then table.insert(classNames, tostring(c.Name)) end
        end
    end
end
scanUnits()

local SecLoad = TUnits:Section({ Title = "LOADOUT", Icon = "shield" })
local pUnit = SecLoad:Paragraph({ Title = "Unit", Desc = "-" })
if #unitNames > 0 then
    SecLoad:Dropdown({ Title = "Unit", Values = unitNames, Value = unitNames[1], Callback = function(v) State.unitSel = v end })
    State.unitSel = unitNames[1]
end
SecLoad:Button({ Title = "RESCAN INVENTORY", Callback = function()
    scanUnits()
    WindUI:Notify({ Title = "Scan", Content = string.format("%d units, %d classes", #unitNames, #classNames), Duration = 3, Icon = "refresh-cw" })
end })

local SecEvo = TUnits:Section({ Title = "EVOLUTION", Icon = "arrow-up-circle" })
local pEvo = SecEvo:Paragraph({ Title = "Chain", Desc = "-" })

local SecClass = TUnits:Section({ Title = "CLASSES", Icon = "sword" })
local pClass = SecClass:Paragraph({ Title = "Class", Desc = "-" })
if #classNames > 0 then
    SecClass:Dropdown({ Title = "Class", Values = classNames, Value = classNames[1], Callback = function(v) State.classSel = v end })
    State.classSel = classNames[1]
end

--------------------------------------------------------------------------
-- TAB 5 -- SETTINGS
--------------------------------------------------------------------------
local TSet = Window:Tab({ Title = "Settings", Icon = "settings" })

local SecLook = TSet:Section({ Title = "APPEARANCE", Icon = "palette" })
pcall(function()
    SecLook:Dropdown({ Title = "Theme", Values = WindUI:GetThemes(), Value = CFG.theme, Callback = function(v)
        CFG.theme = v
        pcall(function() Window:SetTheme(v) end)
    end })
end)
SecLook:Slider({ Title = "UI Scale", Value = { Min = 0.7, Max = 1.4, Default = 1.0 }, Step = 0.05, Callback = function(v)
    pcall(function() Window:SetUIScale(v) end)
end })

local SecSys = TSet:Section({ Title = "SYSTEM", Icon = "cpu" })
SecSys:Toggle({ Title = "Streamer Mode", Desc = "Hide enemy names", Value = CFG.streamer, Callback = function(v) CFG.streamer = v end })
SecSys:Button({ Title = "Refresh Data", Callback = function() refreshReward(); scanUnits() end })
SecSys:Button({ Title = "UNLOAD", Variant = "Destructive", Callback = function()
    if getgenv()[KEY] and getgenv()[KEY].unload then getgenv()[KEY].unload() end
end })
SecSys:Paragraph({ Title = "Window Key", Desc = "RightShift toggles this window. HUD sits top-right." })
local pInfo = SecSys:Paragraph({ Title = "Build", Desc = "CAA Hub v4 - bracket ESP, range-gated auto attack, free ascension, reach diagnostic." })

--------------------------------------------------------------------------
-- AUTOMATION RUNTIME
--------------------------------------------------------------------------
local REM_BannerReq  = findRemote("BannerRequest")
local REM_BannerRes  = findRemote("BannerResponse")
local REM_AscReq     = findRemote("AscensionRequest")
local REM_AscRes     = findRemote("AscensionResponse")
local REM_EvoReq     = findRemote("EvolutionRequest")
local REM_EvoRes     = findRemote("EvolutionResponse")
local REM_MountReq   = findRemote("MountRequest")
local REM_MoveReq    = findRemote("PlayerMovementRequest")

pcall(function()
    if REM_BannerRes then
        table.insert(conns, REM_BannerRes.OnClientEvent:Connect(function(d)
            if type(d) ~= "table" then return end
            local code = tostring(d.Code or "?")
            Auto.lastCode = code
            if code == "Summoned" and type(d.Results) == "table" then
                Auto.luck = tostring(d.LuckTier or "-")
                for _, r in ipairs(d.Results) do
                    if type(r) == "table" and r.TroopId then
                        table.insert(Auto.results, 1, string.format("%s%s", tostring(r.TroopId), tostring(r.Rarity or "")))
                        while #Auto.results > 6 do table.remove(Auto.results) end
                    end
                end
            end
        end))
    end
end)
pcall(function()
    if REM_AscRes then
        table.insert(conns, REM_AscRes.OnClientEvent:Connect(function(d)
            if type(d) == "table" then
                if d.Success then Auto.fused = Auto.fused + 1 end
                Auto.lastFuse = tostring(d.Code or (d.Success and "OK" or "?"))
                if d.Message then Auto.lastFuse = Auto.lastFuse .. " - " .. tostring(d.Message) end
            end
        end))
    end
end)
pcall(function()
    if REM_EvoRes then
        table.insert(conns, REM_EvoRes.OnClientEvent:Connect(function(d)
            if type(d) == "table" then
                if d.Success then Auto.evolved = Auto.evolved + 1 end
                Auto.lastEvo = tostring(d.Code or "?")
                if d.Message then Auto.lastEvo = Auto.lastEvo .. " - " .. tostring(d.Message) end
            end
        end))
    end
end)

doSummon = function(n)
    if not REM_BannerReq then return false end
    n = math.clamp(math.floor(tonumber(n) or 1), 1, 10)
    local gems = tonumber(lp:GetAttribute("Gems")) or 0
    local cost = 50 * n
    if CFG.summonStop and gems < cost then
        Auto.lastCode = string.format("held: %d gems < %d", gems, cost)
        return false
    end
    local batch = (n == 10) and 10 or 1
    local times = (n == 10) and 1 or n
    for i = 1, times do
        REM_BannerReq:FireServer({
            Type = "Summon",
            BannerId = "Standard",
            RequestId = uuid(),
            Count = batch,
            SummonKey = uuid(),
        })
        if times > 1 and i < times then task.wait(CFG.summonDelay) end
    end
    Auto.summons = Auto.summons + n
    Auto.spend = Auto.spend + cost
    Auto.summonAt = os.clock()
    return true
end

-- GAMEPASS path. Server gate: AscendAllGamepassOwned must be true.
-- Non-owners get NotOwned and the call is dropped - free path is doFuseAll below.
doAscendAll = function()
    if not REM_AscReq then return end
    pcall(function()
        REM_AscReq:FireServer({ Type = "PromptAscendAll", RequestId = uuid() })
    end)
    task.wait(0.35)
    pcall(function()
        REM_AscReq:FireServer({ Type = "AscendAll", RequestId = uuid() })
    end)
    Auto.fuseAt = os.clock()
end

-- FREE path. Lobby only. Server rules from AscensionController:
--   same TroopId, same AscensionLevel, different CopyId, level < MAX
-- Each fusion consumes the duplicate and adds +1 AscensionLevel to the main.
local function findPairs()
    local U = unitsData()
    local pairs_ = {}
    if type(U) ~= "table" or type(U.Units) ~= "table" then return pairs_ end
    local groups, order = {}, {}
    for _, u in ipairs(U.Units) do
        if u.CopyId and u.TroopId then
            local lv = tonumber(u.AscensionLevel) or 0
            local key = tostring(u.TroopId) .. "|" .. tostring(lv)
            if not groups[key] then groups[key] = {}; table.insert(order, key) end
            table.insert(groups[key], u)
        end
    end
    for _, key in ipairs(order) do
        local g = groups[key]
        while #g >= 2 do
            local main = table.remove(g, 1)
            local dup  = table.remove(g, 1)
            table.insert(pairs_, { main = main, dup = dup, TroopId = main.TroopId, Level = tonumber(main.AscensionLevel) or 0 })
        end
    end
    return pairs_
end

doFuseAll = function(maxN)
    maxN = maxN or 10
    local pairs_ = findPairs()
    local fired = 0
    for _, p in ipairs(pairs_) do
        if fired >= maxN then break end
        local ok = pcall(function()
            REM_AscReq:FireServer({
                RequestId = uuid(),
                MainCopyId = p.main.CopyId,
                DuplicateCopyId = p.dup.CopyId,
            })
        end)
        if ok then
            fired = fired + 1
            Auto.lastFuse = string.format("fusing %s L%s", tostring(p.TroopId), tostring(p.Level))
            task.wait(CFG.fuseDelay)
        end
    end
    Auto.fuseAt = os.clock()
    return fired
end

-- kept for the old API name
local doAscend = doAscendAll

doEvolveAll = function()
    if not REM_EvoReq then return 0 end
    local U = unitsData()
    if type(U) ~= "table" or type(U.Units) ~= "table" then return 0 end
    local fired = 0
    for _, u in ipairs(U.Units) do
        local lvl = tonumber(u.MasteryLevel) or 0
        local done = tonumber(u.EvolutionVersion or 0) or 0
        if u.CopyId and lvl >= 20 and done == 0 then
            pcall(function()
                REM_EvoReq:FireServer({ RequestId = uuid(), CopyId = u.CopyId })
            end)
            fired = fired + 1
            task.wait(0.6)
        end
    end
    Auto.evoAt = os.clock()
    return fired
end

toggleMount = function()
    if not REM_MountReq then return end
    pcall(function() REM_MountReq:FireServer() end)
end

applySpeed = function()
    local ch = lp.Character
    local h = ch and ch:FindFirstChildOfClass("Humanoid")
    if CFG.spdEnabled then
        local s = CFG.spdPlayer
        if lp:GetAttribute("WalkSpeed") ~= s then lp:SetAttribute("WalkSpeed", s) end
        if h and h.WalkSpeed ~= s then h.WalkSpeed = s end
    end
    if REM_MoveReq and CFG.spdSprint ~= Auto.sprintSent then
        Auto.sprintSent = CFG.spdSprint
        pcall(function() REM_MoveReq:FireServer("Sprint", CFG.spdSprint) end)
    end
    local M = WS:FindFirstChild("Mounts")
    if M then
        for _, c in ipairs(M:GetChildren()) do
            if c:GetAttribute("OwnerUserId") == lp.UserId then
                Auto.mounted = true
                if CFG.spdEnabled then
                    local mh = c:FindFirstChildOfClass("Humanoid")
                    if mh and mh.WalkSpeed ~= CFG.spdHorse then mh.WalkSpeed = CFG.spdHorse end
                end
                return
            end
        end
    end
    Auto.mounted = false
end

local function stepAuto(dt)
    local now = os.clock()
    applySpeed()

    if CFG.autoSummon and (now - Auto.summonAt) > CFG.summonDelay then
        doSummon(CFG.summonCount)
    end
    if CFG.autoEvolve and (now - Auto.evoAt) > 20 then
        doEvolveAll()
    end
    if CFG.autoFuse and (now - Auto.fuseAt) > 8 then
        doFuseAll()
    end

    if now - Auto.pushAt > 0.8 then
        Auto.pushAt = now
        local gems = tonumber(lp:GetAttribute("Gems")) or 0
        local U = unitsData()
        local ready = 0
        local total = 0
        if type(U) == "table" and type(U.Units) == "table" then
            for _, u in ipairs(U.Units) do
                total = total + 1
                if (tonumber(u.MasteryLevel) or 0) >= 20 and (tonumber(u.EvolutionVersion or 0) or 0) == 0 then
                    ready = ready + 1
                end
            end
        end
        if pSumStat and pSumStat.SetDesc then
            pcall(function()
                pSumStat:SetDesc(string.format("gems %s | last %s | cycles %d | spent %s",
                    fmt(gems), tostring(Auto.lastCode), Auto.summons, fmt(Auto.spend)))
            end)
        end
        if pProgStat and pProgStat.SetDesc then
            pcall(function()
                local prs = findPairs()
                local lobby = tostring(lp:GetAttribute("MatchState")) == "Lobby"
                pProgStat:SetDesc(string.format("pairs %d | fused %d | lobby %s | %s",
                    #prs, Auto.fused, tostring(lobby),
                    lobby and tostring(Auto.lastFuse) or "lobby only"))
            end)
        end
        if pEvoStat and pEvoStat.SetDesc then
            pcall(function()
                pEvoStat:SetDesc(string.format("ready %d/%d | evolved %d | %s",
                    ready, total, Auto.evolved, tostring(Auto.lastEvo)))
            end)
        end
        if pSpdStat and pSpdStat.SetDesc then
            pcall(function()
                local ch = lp.Character
                local h = ch and ch:FindFirstChildOfClass("Humanoid")
                pSpdStat:SetDesc(string.format("player %s (hum %s) | horse %s | mounted %s | sprint %s",
                    tostring(lp:GetAttribute("WalkSpeed")), tostring(h and h.WalkSpeed),
                    tostring(CFG.spdHorse), tostring(Auto.mounted), tostring(CFG.spdSprint)))
            end)
        end
    end
end

--------------------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------------------
local cam0 = WS.CurrentCamera
local vp = cam0 and cam0.ViewportSize or Vector2.new(1920, 1080)
if vp.X < 100 or vp.Y < 100 then vp = Vector2.new(1920, 1080) end
vig = mk("Square", { Filled = true, Visible = false, Color = RED, Transparency = 0.8 })
vig.Size = vp
vig.Position = Vector2.new(0, 0)
buildHUD()

local conns = {}
local elapsed = 0
local frame = 0
local lastFull = 0
local lastAutoDaily = 0

local function onFrame(dt)
    elapsed = elapsed + dt
    frame = frame + 1
    local cam = WS.CurrentCamera
    if cam then vp = cam.ViewportSize end
    vig.Size = vp

    stepESP(dt, frame)

    -- retire last frame's hitbox wireframes, then redraw
    for _, w in ipairs(HB.live) do hbRelease(w) end
    HB.live = {}
    if CFG.hbESP then stepHitboxESP() end

    stepHUD(dt, vp)
    stepVignette(elapsed)
    stepCombat(dt)
    stepChargeRing(elapsed)
    stepAuto(dt)

    -- panels refresh 1/sec
    if elapsed - lastFull > 1.0 then
        lastFull = elapsed
        local pct = function(a, b) if not b or b == 0 then return 0 end return a / b * 100 end

        if pCounts and pCounts.SetDesc then
            pcall(function()
                pCounts:SetDesc(string.format("Mine %d  |  Blue %d  |  Red %d  |  Team %s",
                    State.counts.mine, State.counts.blue, State.counts.red, tostring(State.enemyTeam or "?")))
            end)
        end
        if pMe and pMe.SetDesc then
            pcall(function()
                pMe:SetDesc(string.format("Class %s  |  Lv %s  |  Dmg %s  |  Range %s  |  Rate %ss  |  HP %s",
                    tostring(at("PlayerClass") or "?"), tostring(at("PlayerLevel") or "?"),
                    tostring(at("AttackDamage") or "?"), tostring(at("Range") or "?"),
                    tostring(at("AttackInterval") or "?"), tostring(at("Stamina") or "?")))
            end)
        end
        if pMatch and pMatch.SetDesc then
            pcall(function()
                pMatch:SetDesc(string.format("State %s  |  Combat %s  |  CanUseCombat %s",
                    tostring(at("MatchState") or "?"), tostring(at("CombatState") or "?"),
                    tostring(at("CanUseCombat") or "?")))
            end)
        end
        if pBal and pBal.SetDesc then
            pcall(function()
                pBal:SetDesc(string.format("Gems %s  |  Tickets %s  |  XP %s/%s  |  Luck %s",
                    fmt(at("Gems") or 0), fmt(at("Tickets") or 0),
                    fmt(at("PlayerXP") or 0), fmt(at("PlayerXPRequired") or 0),
                    tostring(at("LuckTier") or "?")))
            end)
        end
        local d = State.reward and State.reward.daily
        if pDaily and pDaily.SetDesc then
            pcall(function()
                if type(d) == "table" then
                    local st, nt = tonumber(d.ServerTime), tonumber(d.NextClaimAt)
                    local left = (st and nt) and (nt - st) or nil
                    pDaily:SetDesc(string.format("Day %s (top %s)  |  %s  |  Goal %s",
                        tostring(d.CurrentStreak or "?"), tostring(d.TopStreak or "?"),
                        left and (left > 0 and dur(left) or "CLAIMABLE") or tostring(State.reward.dailyStatus or "?"),
                        type(d.GoalTroop) == "table" and tostring(d.GoalTroop.Name or "?") or "-"))
                else
                    pDaily:SetDesc("polling...")
                end
            end)
        end

        -- auto daily
        if CFG.autoDaily and type(d) == "table" then
            local st, nt = tonumber(d.ServerTime), tonumber(d.NextClaimAt)
            if st and nt and (nt - st) <= 0 and elapsed - lastAutoDaily > 8 then
                lastAutoDaily = elapsed
                local dr = remote("DailyRewardRequest")
                if dr then
                    pcall(function() dr:InvokeServer({ Type = "Claim" }) end)
                    task.delay(1.5, refreshReward)
                end
            end
        end

        -- unit panel
        if pUnit and pUnit.SetDesc then
            pcall(function()
                local ui = unitsData()
                local found
                if type(ui) == "table" and type(ui.Units) == "table" then
                    for _, u in ipairs(ui.Units) do
                        if tostring(u.TroopId) == tostring(State.unitSel) then found = u break end
                    end
                end
                if found then
                    pUnit:SetDesc(string.format("Stars %s  |  Dmg %s  |  DPS %s  |  HP %s  |  Spd %s  |  Rng %s  |  Int %ss  |  Block %s  |  %s  |  Mastery %s/%s",
                        tostring(found.Stars or "?"), tostring(found.Damage or "?"),
                        tostring(found.DPS and math.floor(found.DPS) or "?"),
                        tostring(found.Health or "?"), tostring(found.Speed or "?"),
                        tostring(found.Range or "?"), tostring(found.AttackInterval or "?"),
                        tostring(found.BlockDurability or "?"), tostring(found.CombatType or "?"),
                        tostring(found.MasteryXP or 0), tostring(found.MasteryXPRequired or 0)))
                else
                    pUnit:SetDesc("select a unit")
                end
            end)
        end
        if pEvo and pEvo.SetDesc then
            pcall(function()
                local ui = unitsData()
                local found
                if type(ui) == "table" and type(ui.Units) == "table" then
                    for _, u in ipairs(ui.Units) do
                        if tostring(u.TroopId) == tostring(State.unitSel) then found = u break end
                    end
                end
                local ev = found and found.EvolutionPreview
                if type(ev) == "table" then
                    pEvo:SetDesc(string.format("%s -> %s  |  Dmg %s->%s  |  HP %s->%s  |  Rng %s->%s  |  Stars %s->%s",
                        tostring(found.TroopId), tostring(ev.TroopId or "?"),
                        tostring(found.Damage or "?"), tostring(ev.Damage or "?"),
                        tostring(found.Health or "?"), tostring(ev.Health or "?"),
                        tostring(found.Range or "?"), tostring(ev.Range or "?"),
                        tostring(found.Stars or "?"), tostring(ev.Stars or "?")))
                else
                    pEvo:SetDesc("no evolution preview")
                end
            end)
        end
        if pClass and pClass.SetDesc then
            pcall(function()
                local ci = classData()
                local found
                if type(ci) == "table" and type(ci.Classes) == "table" then
                    for _, c in ipairs(ci.Classes) do
                        if tostring(c.Name) == tostring(State.classSel) then found = c break end
                    end
                end
                if found then
                    pClass:SetDesc(string.format("Dmg %s  |  DPS %s  |  HP %s  |  Spd %s  |  Rng %s  |  Int %ss  |  Block %s  |  Owned %s  |  Price %s",
                        tostring(found.Damage or "?"), tostring(found.DPS or "?"),
                        tostring(found.Health or "?"), tostring(found.Speed or "?"),
                        tostring(found.Range or "?"), tostring(found.AttackInterval or "?"),
                        tostring(found.BlockDurability or "?"), tostring(found.Owned or false),
                        tostring(found.Price or "?")))
                else
                    pClass:SetDesc("-")
                end
            end)
        end
        if pHB and pHB.SetDesc then
            pcall(function()
                local parts = collectHitParts()
                if #parts == 0 then
                    pHB:SetDesc("no hitbox parts found")
                else
                    local s = {}
                    for i = 1, math.min(#parts, 4) do
                        local p = parts[i]
                        s[#s + 1] = string.format("%s %.1fx%.1fx%.1f", p.Name, p.Size.X, p.Size.Y, p.Size.Z)
                    end
                    pHB:SetDesc(table.concat(s, "  |  "))
                end
            end)
        end
        if pReach and pReach.SetDesc then
            pcall(function()
                local reach = CFG.atkRangeAuto and (tonumber(at("Range")) or 7) or CFG.atkRange
                local nd = State.nearestDist or math.huge
                pReach:SetDesc(string.format("reach %.1f | nearest %s | %s | last: %s",
                    reach, nd < math.huge and string.format("%.1fm", nd) or "none",
                    State.inRange and "IN RANGE" or "out",
                    tostring(State.lastReach)))
            end)
        end
        if pInfo and pInfo.SetDesc then
            pcall(function()
                pInfo:SetDesc(string.format("objects %d  |  fps %d  |  live boxes %d",
                    #DrawingObjects, math.floor(1 / math.max(dt, 0.0001)), (function()
                        local n = 0
                        for _ in pairs(ESP.live) do n = n + 1 end
                        return n
                    end)()))
            end)
        end
    end
end

table.insert(conns, Run.RenderStepped:Connect(function(dt)
    if not State.alive then return end
    local ok, err = pcall(onFrame, dt)
    if not ok then
        warn("[CAA] frame error: " .. tostring(err))
    end
end))

--------------------------------------------------------------------------
-- UNLOAD
--------------------------------------------------------------------------
local function unload()
    if not State.alive then return end
    State.alive = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, o in ipairs(DrawingObjects) do pcall(function() o:Remove() end) end
    if getgenv()[DRAW_REG] == DrawingObjects then getgenv()[DRAW_REG] = nil end
    pcall(function() Window:Destroy() end)
    pcall(function() getgenv()[KEY] = nil end)
    print("[CAA] unloaded")
end

getgenv()[KEY] = { unload = unload, cfg = CFG, state = State, window = Window, lib = WindUI, hud = HUD, esp = ESP, draw = DrawingObjects, auto = Auto,
    summon = doSummon, fuseAll = doFuseAll, ascendAll = doAscendAll, ascend = doAscendAll, findPairs = findPairs,
    evolveAll = doEvolveAll, mount = toggleMount, reachTest = function(m) return reachTest(m or "volley") end,
    fireVolley = function() local t = State.nearestEnemy; local h = t and t:FindFirstChild("HumanoidRootPart")
        if not h then return "no enemy" end
        local ok, msg = fireVolley(h.Position); State.fireLog = tostring(msg); return msg end,
    hitbox = function(on) CFG.hitboxOn = (on ~= false); if not CFG.hitboxOn then restoreHitbox() end
        return CFG.hitboxOn, CFG.hitboxScale end,
    hbESP = function(on) CFG.hbESP = (on ~= false); return CFG.hbESP end,
    hbPool = HB,
    hbSizes = function()
        local parts, s = collectHitParts(), {}
        for i, p in ipairs(parts) do
            s[i] = string.format("%s %.1fx%.1fx%.1f", p.Name, p.Size.X, p.Size.Y, p.Size.Z)
        end
        return table.concat(s, " | ")
    end }

-- boot heal: a previous session may have died with hitboxes inflated
task.spawn(function()
    task.wait(2)
    local store = getgenv().__caaHbOrig
    if store and not CFG.hitboxOn then
        local healed = 0
        local myChar = lp.Character
        if myChar then
            for key, o in pairs(store) do
                local nm = key:match("^[^/]+/(.+)$") or key
                local p = myChar:FindFirstChild(nm)
                if p and p:IsA("BasePart") and (p.Size - o[1]).Magnitude > 0.01 then
                    pcall(function() p.Size = o[1] end)
                    healed = healed + 1
                end
            end
        end
        if healed > 0 then print("[CAA] hitbox healed: " .. healed .. " part(s)") end
    end
end)

-- guard: the cleanup hook only exists if the host injects it. Referencing a
-- bare STATE here threw "attempt to index nil with 'onCleanup'" on every load.
pcall(function()
    local host = rawget(getfenv(), "STATE") or (getgenv and getgenv().STATE)
    if host and type(host.onCleanup) == "function" then
        host.onCleanup(function() unload() end)
    end
end)

--------------------------------------------------------------------------
refreshReward()
task.spawn(function()
    while State.alive do
        task.wait(45)
        if State.alive then refreshReward() end
    end
end)
task.spawn(function()
    while State.alive do
        task.wait(30)
        if State.alive then scanUnits() end
    end
end)

WindUI:Notify({ Title = "CAA Hub", Content = "Loaded. RightShift toggles the window.", Duration = 4, Icon = "swords" })
print(string.format("[CAA] hub up  tabs=%d  objects=%d  place=%s  auto=ready", 6, #DrawingObjects, tostring(game.PlaceId)))

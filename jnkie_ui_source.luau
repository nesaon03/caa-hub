--[[ =======================================================================
     COMMAND AN ARMY  --  JUNKIE "UI-SOURCE" GATE

     Paste THIS file into the dashboard Lua Scripts -> UI-Source field.
     Put hub.luau into the Original Code field.

     It only does the key work:
       cached key (1h) -> else KEY window -> validate -> SCRIPT_KEY set
     The hub itself runs from the Original Code field, which Junkie
     appends after this gate. Do NOT add a hub fetch here.
     ======================================================================= ]]

--------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------
local JCFG = {
    -- Junkie (key system) ------------------------------------------------
    library    = "https://jnkie.com/sdk/library.lua",
    service    = "ONYX HUB",
    provider   = "test",
    identifier = "1177507",  -- Junkie dashboard user id
    -- identifier = "0" runs MOCK mode: any 8+ char key is accepted.

    -- Cache ---------------------------------------------------------------
    key_file   = "CAAHub/key.txt",
    cache_secs = 3600,       -- re-validate a saved key every hour
    remember   = true,       -- offer to save the key
    mock       = nil,        -- nil = auto (true while identifier == "0")
}

JCFG.mock = (JCFG.mock ~= nil) and JCFG.mock or (tostring(JCFG.identifier) == "0")

local THEME = "Dark"
local TITLE = "COMMAND AN ARMY"

local function log(...)
    print("[KEY] " .. table.concat({ ... }, " "))
end

-- only the newest loader instance may act: re-executing retires the old one
local G = (getgenv().__caaLoaderGen or 0) + 1
getgenv().__caaLoaderGen = G
local function current()
    return getgenv().__caaLoaderGen == G
end

-- drop any leftover key window from an earlier run
do
    local ok = pcall(function()
        for _, sg in ipairs(gethui():GetChildren()) do
            if sg.Name == "WindUI" then
                for _, f in ipairs(sg:GetChildren()) do
                    if f.Name == "Window" then
                        for _, w in ipairs(f:GetChildren()) do
                            local t
                            for _, d in ipairs(w:GetDescendants()) do
                                if d:IsA("TextLabel") and d.Text == "KEY REQUIRED" then
                                    t = true break
                                end
                            end
                            if t then w:Destroy() end
                        end
                    end
                end
            end
        end
    end)
    if ok then log("stale key windows cleared") end
end

--------------------------------------------------------------------------
-- WINDUI
--------------------------------------------------------------------------
local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

--------------------------------------------------------------------------
-- KEY CACHE (file backed)
--------------------------------------------------------------------------
local function cache_read()
    local ok, raw = pcall(function()
        if isfile(JCFG.key_file) then return readfile(JCFG.key_file) end
    end)
    if not ok or type(raw) ~= "string" or #raw < 8 then return nil end
    local key, stamp = raw:match("^(.-)\n(%d+)$")
    if not key then return nil end
    if os.time() - tonumber(stamp) > JCFG.cache_secs then return nil end
    return key
end

local function cache_write(key)
    if not JCFG.remember then return end
    pcall(function()
        makefolder("CAAHub")
        writefile(JCFG.key_file, key .. "\n" .. tostring(os.time()))
    end)
end

local function cache_clear()
    pcall(function()
        if isfile(JCFG.key_file) then delfile(JCFG.key_file) end
    end)
end

--------------------------------------------------------------------------
-- JUNKIE
--------------------------------------------------------------------------
local Junkie
do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet(JCFG.library))()
    end)
    if ok and type(lib) == "table" and type(lib.check_key) == "function" then
        lib.service    = JCFG.service
        lib.provider   = JCFG.provider
        lib.identifier = JCFG.identifier
        Junkie = lib
    end
end

-- documented backend errors -> friendly text
local ERRORS = {
    KEY_INVALID       = "Key not found",
    KEY_EXPIRED       = "Key expired",
    KEY_INVALIDATED   = "Key was disabled",
    ALREADY_USED      = "One-time key already used",
    HWID_MISMATCH     = "HWID limit reached",
    SERVICE_NOT_FOUND = "Service misconfigured",
    SERVICE_MISMATCH  = "Key is for a different service",
    PREMIUM_REQUIRED  = "Premium key required",
    RATE_LIMITED      = "Too many tries - wait 5 min",
    ERROR             = "Network error - try again",
}

-- returns ok, message, fatal
local function validate(key)
    if type(key) ~= "string" then return false, "Enter a key", false end
    key = key:gsub("%s+", "")
    if #key < 8 then return false, "Too short", false end

    if JCFG.mock then
        return true, "MOCK OK (identifier unset)", false
    end
    if not Junkie then
        return false, "Cannot reach key server", false
    end

    local ok, res = pcall(function() return Junkie.check_key(key) end)
    if not ok or type(res) ~= "table" then
        return false, "Network error - try again", false
    end
    if res.valid then
        return true, tostring(res.message or "KEY_VALID"), false
    end
    local e = tostring(res.error or "ERROR")
    return false, ERRORS[e] or e, (e == "HWID_BANNED")
end

--------------------------------------------------------------------------
-- HUB
--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------
local function start_hub()
    if not current() then return false end
    -- the hub payload is appended by Junkie AFTER this gate, so all we do
    -- here is mark the session authorised and tear the key window down.
    getgenv().__caaAuthorized = true
    log("authorized - handing off to hub payload")
    pcall(function()
        WindUI:Notify({
            Title = TITLE,
            Content = "Key accepted",
            Duration = 4,
        })
    end)
    return true
end

-- fast path: cached key
local cached = cache_read()
if cached then
    local ok, msg = validate(cached)
    if ok then
        log("saved key ok ->", msg)
        return start_hub()
    end
    log("saved key rejected:", msg)
    cache_clear()
end

--------------------------------------------------------------------------
-- KEY WINDOW
--------------------------------------------------------------------------
local granted, done = false, false

local Win = WindUI:CreateWindow({
    Title       = "KEY REQUIRED",
    Icon        = "key-round",
    Author      = "ONYX HUB",
    Folder      = "CAAKey",
    Size        = UDim2.fromOffset(440, 275),
    Theme       = THEME,
    Transparent = true,
    Acrylic     = true,
    User        = { Enabled = false },
})

local Tab = Win:Tab({ Title = "Access", Icon = "lock-keyhole" })
local Sec = Tab:Section({ Title = "ENTER YOUR KEY", Icon = "key-round" })

Sec:Paragraph({
    Title = "Key Required",
    Desc  = JCFG.mock
        and "MOCK MODE - identifier is unset, any 8+ char key works."
        or  "Paste your ONYX HUB key. It checks automatically as you type.",
})

local status
local function set_status(text)
    if status then status:SetDesc(text) end
end

-- pending holds the newest text seen in the key box; auto-validate reads it.
-- WindUI's Input Callback is NOT trustworthy: it reports its own internal state
-- and fires with an empty string even when the TextBox visibly holds a key, and
-- Input.Value only updates through WindUI's own Set path. So we bind straight to
-- the TextBox the element owns and read its Text.
local pending, pendingAt = nil, 0

local box = Sec:Input({
    Title       = "Key",
    Placeholder = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    Callback    = function(v)
        -- keep this as a fallback only; the TextBox hook below is authoritative
        if type(v) == "string" and #v >= 8 then
            pending   = v:gsub("%s+", "")
            pendingAt = os.clock()
        end
    end,
})

-- bind to the real TextBox (ElementFrame owns it) -------------------------
local function bind_box()
    local ef = box and box.ElementFrame
    if not ef then return false end
    local tb
    for _, c in ipairs(ef:GetDescendants()) do
        if c:IsA("TextBox") then tb = c break end
    end
    if not tb then return false end
    tb:GetPropertyChangedSignal("Text"):Connect(function()
        pending   = (tb.Text or ""):gsub("%s+", "")
        pendingAt = os.clock()
    end)
    -- expose so tests / the VALIDATE button can drive it programmatically
    getgenv().__caaKeyBox = tb
    return true
end

do
    local ok, bound = pcall(bind_box)
    log("key box bound:", tostring(ok and bound or false))
    if not (ok and bound) then
        -- retry a few frames: the element may not be parented yet
        task.spawn(function()
            for _ = 1, 40 do
                task.wait(0.1)
                local o, b = pcall(bind_box)
                if o and b then log("key box bound (late)") break end
            end
        end)
    end
end

local busy = false
local function try_key(key, quiet)
    if busy then return end
    if type(key) ~= "string" or #key < 8 then
        if not quiet then set_status("Enter a key") end
        return
    end
    busy = true
    if not quiet then set_status("Checking...") end

    local ok, msg, fatal = validate(key)
    busy = false

    if ok then
        granted = true
        cache_write(key)
        getgenv().SCRIPT_KEY = key
        set_status("Valid - loading hub")
        pcall(function()
            WindUI:Notify({ Title = "Key Valid", Content = msg, Duration = 4 })
        end)
        task.wait(0.35)
        pcall(function() Win:Destroy() end)
    else
        set_status(msg)
        if fatal then
            pcall(function() game.Players.LocalPlayer:Kick("Hardware banned") end)
        end
    end
end

Sec:Button({
    Title = "VALIDATE",
    Icon  = "check",
    Callback = function()
        local v = pending
        if type(v) ~= "string" or #v < 8 then
            local tb = getgenv().__caaKeyBox
            if tb then v = tb.Text:gsub("%s+", "") end
        end
        if type(v) ~= "string" or #v < 8 then
            v = box and box.Value
        end
        try_key(v)
    end,
})

Sec:Button({
    Title = "GET KEY",
    Icon  = "external-link",
    Callback = function()
        if JCFG.mock then
            set_status("Mock mode - no link needed")
            return
        end
        set_status("Fetching link...")
        local link, err = Junkie and Junkie.get_key_link()
        if link then
            pcall(function() setclipboard(tostring(link)) end)
            set_status("Link copied to clipboard")
            pcall(function()
                WindUI:Notify({ Title = "Key Link", Content = tostring(link), Duration = 12 })
            end)
        else
            set_status("No link available: " .. tostring(err))
        end
    end,
})

status = Sec:Paragraph({ Title = "Status", Desc = "Waiting for a key..." })

--------------------------------------------------------------------------
-- auto-validate on paste / typing (debounced)
--------------------------------------------------------------------------
task.spawn(function()
    local last, seen = nil, {}
    local t0 = os.clock()
    while not granted and not done and (os.clock() - t0) < 900 do
        task.wait(0.25)
        if granted then break end
        if not current() then
            pcall(function() Win:Destroy() end)
            return
        end
        if Win.Destroyed or Win.Closed then done = true break end
        -- read the live TextBox first: the property signal that feeds
        -- `pending` is not always delivered, so never rely on it alone
        local v = pending
        local tb = getgenv().__caaKeyBox
        if tb then
            local t = tb.Text
            if type(t) == "string" then
                t = t:gsub("%s+", "")
                if #t >= #(type(v) == "string" and v or "") then v = t end
            end
        end
        if type(v) == "string" and #v >= 32 and v ~= last
           and not seen[v] and not busy
           and ((os.clock() - pendingAt) >= 0.5 or tb ~= nil) then
            last, seen[v] = v, true
            log("auto-validate:", #v, "chars")
            try_key(v, true)
        end
    end
end)

-- wait for a decision
while not granted and not done do
    task.wait(0.2)
    if not current() then
        pcall(function() Win:Destroy() end)
        return
    end
    if Win.Destroyed or Win.Closed then break end
end

pcall(function() if not Win.Destroyed then Win:Destroy() end end)

if not granted then
    warn("[KEY] no valid key - hub not loaded")
    return
end

start_hub()

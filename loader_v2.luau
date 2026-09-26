--[[ =======================================================================
     COMMAND AN ARMY  --  LOADER  (v2)
     Place 101770480176177   universe 10258991999

     Loads the hub in this order:
       1. Junkie CDN (obfuscated, key-protected)  <- preferred
       2. GitHub raw hub.luau                     <- fallback

     Key gate is ours: WindUI window, validates through the Junkie SDK,
     then hands the key to the Junkie delivery API to fetch the
     obfuscated script. Nothing about the key system is bypassable by
     reading this file - the protected payload is only served by the
     backend after a key check.

     CONFIG IS AT THE TOP. see JCFG.
     ======================================================================= ]]

--------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------
local JCFG = {
    -- Junkie (key system) ------------------------------------------------
    library     = "https://jnkie.com/sdk/library.lua",
    service     = "ONYX HUB",
    provider    = "test",
    identifier  = "1177507",   -- Junkie dashboard user id

    -- Protected delivery -------------------------------------------------
    -- The loader the dashboard generates is read at runtime so the script
    -- hash below never goes stale after a re-obfuscate. To force a value,
    -- set script_hash and clear loader_url.
    loader_url  = "https://jnkie.com/loaders/onxy-hub",
    script_hash = "3aca75960eb60be1144fe4727952badd1199f4a30dd69d1243ced2d19f7dcf9e",
    api_deliver = "https://api.jnkie.com/api/v1/luascripts/delivery/",

    -- Fallback hub -------------------------------------------------------
    hub_local   = "CAAHub/hub.luau",
    hub_url     = "https://raw.githubusercontent.com/nesaon03/caa-hub/main/hub.luau",

    -- Cache ---------------------------------------------------------------
    key_file    = "CAAHub/key.txt",
    cache_secs  = 3600,
    remember    = true,
}

local THEME = "Dark"
local TITLE = "COMMAND AN ARMY"

local function log(...)
    print("[KEY] " .. table.concat({ ... }, " "))
end

-- only the newest loader instance may act
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
-- HTTP
--------------------------------------------------------------------------
local function request_lib()
    return (type(syn) == "table" and syn.request)
        or (type(request) == "function" and request)
        or (type(http_request) == "function" and http_request)
        or (type(http) == "table" and http.request)
end

-- blocking request with a timeout; returns ok, response
local function fetch(tbl, secs)
    local r = request_lib()
    if not r then return false, nil end
    local done, a, b = false, nil, nil
    task.spawn(function()
        a, b = pcall(r, tbl)
        done = true
    end)
    local t0 = os.clock()
    repeat task.wait() until done or (os.clock() - t0) > (secs or 20)
    if not done then return false, nil end
    return a, b
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

local ERRORS = {
    KEY_INVALID       = "Key not found",
    KEY_EXPIRED       = "Key expired",
    KEY_INVALIDATED   = "Key was disabled",
    ALREADY_USED      = "One-time key already used",
    HWID_MISMATCH     = "HWID limit reached",
    HWID_BANNED       = "Hardware banned",
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
    if not Junkie then return false, "Cannot reach key server", false end

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
-- PROTECTED PAYLOAD  (Junkie CDN)
--------------------------------------------------------------------------
-- read the live loader once so a re-obfuscate cannot leave us holding a
-- stale hash; the baked value is only a fallback
local function script_hash()
    if JCFG.loader_url == "" then return JCFG.script_hash end
    local ok, src = pcall(function() return game:HttpGet(JCFG.loader_url) end)
    if ok and type(src) == "string" then
        -- the hash sits in the loader's own table, e.g.
        --   local S,P,G={"3aca..."},{},{[placeId]=1}
        -- so do not anchor on "S=" - match the table head, then fall back
        -- to the first long hex string anywhere in the source
        local h = src:match('S%s*,%s*P[^=]*=%s*{%s*"([0-9a-fA-F]+)"')
              or src:match('"([0-9a-fA-F]{32,64})"')
        if h and #h >= 32 then return h end
    end
    return JCFG.script_hash
end

-- POST the key, get a cdn url back, then pull the obfuscated script.
-- returns source string, or nil + reason
local function fetch_protected(key)
    local hash = script_hash()
    local url = JCFG.api_deliver .. hash .. "?v=2&errors=text"
    local ok, res = fetch({
        Url     = url,
        Method  = "POST",
        Headers = { ["Content-Type"] = "text/plain" },
        Body    = key,
    }, 25)
    if not ok or type(res) ~= "table" or type(res.StatusCode) ~= "number" then
        return nil, "network"
    end

    local body = type(res.Body) == "string" and res.Body or ""

    if res.StatusCode ~= 200 then
        -- LDR-DENIED:CODE \n human readable line
        local code, msg = body:match("^(LDR%-DENIED:[A-Z_]+)\n(.*)$")
        if code then
            local e = code:gsub("^LDR%-DENIED:", "")
            return nil, ERRORS[e] or msg
        end
        if res.StatusCode == 400 or res.StatusCode == 401 or res.StatusCode == 403 then
            return nil, ERRORS.KEY_INVALID
        end
        return nil, "server " .. tostring(res.StatusCode)
    end

    if body:sub(1, 22) ~= "https://cdn.jnkie.com/" then
        return nil, "bad delivery"
    end

    local ok2, res2 = fetch({ Url = body, Method = "GET" }, 40)
    if not ok2 or type(res2) ~= "table" or res2.StatusCode ~= 200
       or type(res2.Body) ~= "string" or #res2.Body == 0 then
        return nil, "cdn fetch failed"
    end
    return res2.Body, nil
end

--------------------------------------------------------------------------
-- HUB
--------------------------------------------------------------------------
local function run_hub(src, from)
    if type(src) ~= "string" or #src < 100 then
        return false, "Hub source too short (" .. tostring(from) .. ")"
    end
    local fn, err = loadstring(src, "CAAHub")
    if not fn then return false, "Hub compile error: " .. tostring(err) end
    local ok, err2 = pcall(fn)
    if ok then log("hub source:", from, #src, "bytes") end
    return ok, err2
end

local function load_hub(key)
    -- 1. obfuscated, key checked server side
    local src, why = fetch_protected(key)
    if src then
        local ok, err = run_hub(src, "jnkie-cdn")
        if ok then return true end
        log("cdn hub failed: " .. tostring(err) .. " - trying github")
    else
        log("delivery unavailable (" .. tostring(why) .. ") - trying github")
    end

    -- 2. github raw, then local file
    if JCFG.hub_url ~= "" then
        local ok, s = pcall(function() return game:HttpGet(JCFG.hub_url) end)
        if ok and type(s) == "string" and #s >= 100 then
            return run_hub(s, "github")
        end
        log("github hub failed - trying local file")
    end

    local ok, s = pcall(function() return readfile(JCFG.hub_local) end)
    if not ok or type(s) ~= "string" or #s < 100 then
        return false, "Hub not found at " .. JCFG.hub_local
    end
    return run_hub(s, "local")
end

--------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------
local function start_hub(key)
    if not current() then return false end
    getgenv().__caaAuthorized = true
    local ok, err = load_hub(key)
    if ok then
        pcall(function()
            WindUI:Notify({ Title = TITLE, Content = "Hub loaded", Duration = 4 })
        end)
        log("hub loaded")
    else
        log("hub failed: " .. tostring(err))
        pcall(function()
            WindUI:Notify({
                Title = TITLE,
                Content = "Hub failed: " .. tostring(err),
                Duration = 8,
            })
        end)
    end
    return ok
end

-- fast path: cached key
local cached = cache_read()
if cached then
    local ok, msg = validate(cached)
    if ok then
        log("saved key ok ->", msg)
        return start_hub(cached)
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
    Desc  = "Paste your ONYX HUB key. It checks automatically as you type.",
})

local status
local function set_status(text)
    if status then status:SetDesc(text) end
end

-- WindUI's Input callback reports its own internal state and can fire with
-- an empty string while the TextBox visibly holds a key, so bind straight
-- to the TextBox and read its Text.
local pending, pendingAt = nil, 0

local box = Sec:Input({
    Title       = "Key",
    Placeholder = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    Callback    = function(v)
        if type(v) == "string" and #v >= 8 then
            pending   = v:gsub("%s+", "")
            pendingAt = os.clock()
        end
    end,
})

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
    getgenv().__caaKeyBox = tb
    return true
end

do
    local ok, bound = pcall(bind_box)
    log("key box bound:", tostring(ok and bound or false))
    if not (ok and bound) then
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

start_hub(getgenv().SCRIPT_KEY)

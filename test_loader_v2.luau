-- Full pipeline test for loader_v2, run inside the live client.
-- Uses an invalid key so we exercise: hash extraction, POST delivery,
-- LDR-DENIED parsing, ERRORS mapping, and the fallback chain - with NO
-- need for a working REST credential.
local out = {}
local function P(t) print('[T] ' .. tostring(t)) end

local JCFG = {
    loader_url  = "https://jnkie.com/loaders/onxy-hub",
    script_hash = "3aca75960eb60be1144fe4727952badd1199f4a30dd69d1243ced2d19f7dcf9e",
    api_deliver = "https://api.jnkie.com/api/v1/luascripts/delivery/",
    hub_local   = "CAAHub/hub.luau",
    hub_url     = "https://raw.githubusercontent.com/nesaon03/caa-hub/main/hub.luau",
}

local ERRORS = {
    KEY_INVALID     = "Key not found",
    KEY_EXPIRED     = "Key expired",
    KEY_INVALIDATED = "Key was disabled",
    ALREADY_USED    = "One-time key already used",
    HWID_MISMATCH   = "HWID limit reached",
    HWID_BANNED     = "Hardware banned",
    SERVICE_MISMATCH= "Key is for a different service",
    PREMIUM_REQUIRED= "Premium key required",
    ERROR           = "Network error - try again",
}

local function request_lib()
    return (type(syn) == "table" and syn.request)
        or (type(request) == "function" and request)
        or (type(http_request) == "function" and http_request)
        or (type(http) == "table" and http.request)
end

local function fetch(tbl, secs)
    local r = request_lib()
    if not r then return false, nil end
    local done, a, b = false, nil, nil
    task.spawn(function() a, b = pcall(r, tbl); done = true end)
    local t0 = os.clock()
    repeat task.wait() until done or (os.clock() - t0) > (secs or 20)
    if not done then return false, nil end
    return a, b
end

-- 1. hash extraction from the live loader
local function script_hash()
    if JCFG.loader_url == "" then return JCFG.script_hash end
    local ok, src = pcall(function() return game:HttpGet(JCFG.loader_url) end)
    if ok and type(src) == "string" then
        local h = src:match('S%s*,%s*P[^=]*=%s*{%s*"([0-9a-fA-F]+)"')
              or src:match('"([0-9a-fA-F]{32,64})"')
        if h and #h >= 32 then return h end
    end
    return JCFG.script_hash
end

local h = script_hash()
out[#out+1] = "1. hash  = " .. tostring(h)
out[#out+1] = "   live? = " .. tostring(h == JCFG.script_hash)

-- 2. delivery POST with a BAD key -> must parse + map, never throw
local function fetch_protected(key)
    local hash = script_hash()
    local url = JCFG.api_deliver .. hash .. "?v=2&errors=text"
    local ok, res = fetch({
        Url = url, Method = "POST",
        Headers = { ["Content-Type"] = "text/plain" },
        Body = key,
    }, 25)
    if not ok or type(res) ~= "table" or type(res.StatusCode) ~= "number" then
        return nil, "network"
    end
    local body = type(res.Body) == "string" and res.Body or ""
    if res.StatusCode ~= 200 then
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

local src, why = fetch_protected("deadbeef-dead-beef-dead-beefdeadbeef")
out[#out+1] = "2. bad key -> src=" .. tostring(src) .. " why=" .. tostring(why)
out[#out+1] = "   mapped correctly? " .. tostring(why == "Key not found")

-- 3. empty key control
local _, why2 = fetch_protected("")
out[#out+1] = "3. empty key -> why=" .. tostring(why2)

-- 4. fallback chain: github raw hub must be fetchable
local okg, s = pcall(function() return game:HttpGet(JCFG.hub_url) end)
out[#out+1] = "4. github hub ok=" .. tostring(okg) .. " bytes=" .. tostring(okg and #s or s)

-- 5. local file fallback
local okl, sl = pcall(function() return readfile(JCFG.hub_local) end)
out[#out+1] = "5. local hub ok=" .. tostring(okl) .. " bytes=" .. tostring(okl and #sl or sl)

-- 6. the extracted source must compile
if okl and type(sl) == "string" then
    local fn, err = loadstring(sl, "CAAHub")
    out[#out+1] = "6. hub compiles = " .. tostring(fn ~= nil) .. (fn and "" or (" err=" .. tostring(err)))
end

for _, l in ipairs(out) do P(l) end

local BASE = "https://raw.githubusercontent.com/AlanDevBrah/vision/main/build/"

local MODULES = {
    [95721658376580] = "mtc/bundled.luau",
}

local function fail(msg)
    warn("[Vision] " .. msg)
end

local placeId = game.PlaceId
local path = MODULES[placeId]

if not path then
    fail(("No module for this game yet (PlaceId %d). Supported: Multicrew Tank Combat. More coming — discord.gg/4p4B2wyTm"):format(placeId))
    return
end

local ok, result = pcall(function()
    return game:HttpGet(BASE .. path)
end)
if not ok then
    fail("Failed to download module: " .. tostring(result))
    return
end

local fn, err = loadstring(result)
if not fn then
    fail("Failed to compile module: " .. tostring(err))
    return
end

fn()

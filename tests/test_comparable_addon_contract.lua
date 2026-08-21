local function read(path)
  local file = assert(io.open(path, "rb"), "missing " .. path)
  local text = file:read("*a")
  file:close()
  return text
end

local toc = read("MDTPullMarker.toc")
local readme = read("README.md")
local audit = read("COMPARABLE_ADDON_AUDIT-2026-08-21.md")
local compartment = read("Core/AddonCompartment.lua")

local version = toc:match("## Version:%s*([^\r\n]+)")
assert(version == "1.0.0-rc62", "unexpected TOC version")
assert(readme:find("# MDT Pull Marker " .. version, 1, true), "README version must match TOC")
assert(readme:find("/mdtpm plan <pull>", 1, true), "safe local preview must be documented")
assert(toc:find("## AddonCompartmentFunc: MDTPullMarker_Open", 1, true), "addon compartment entry must remain registered")
assert(toc:find("Core\\Commands.lua\nCore\\AddonCompartment.lua\n", 1, false), "modern compartment owner must load after legacy command callbacks")
assert(compartment:find("function MDTPullMarker_CompartmentEnter(_, menuButtonFrame)", 1, true), "modern AddOn Compartment enter signature missing")
assert(compartment:find('GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")', 1, true), "tooltip must anchor to the actual compartment frame")
assert(toc:find("## Category: Dungeons & Raids", 1, true), "native addon category missing")
for _, locale in ipairs({ "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
  assert(toc:find("## Category-" .. locale .. ":", 1, true), "localized addon category missing: " .. locale)
end
assert(audit:find("Mythic Dungeon Tools - Next Pull Tracker", 1, true), "comparison evidence missing Next Pull Tracker")
assert(audit:find("WarpDeplete", 1, true), "comparison evidence missing WarpDeplete")
assert(audit:find("Angry Keystones", 1, true), "comparison evidence missing Angry Keystones")
assert(audit:find("MythicPlusTimer", 1, true), "comparison evidence missing MythicPlusTimer")

print("ok - comparable addon metadata/preview/version/compartment contract")

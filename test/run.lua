-- Behavioural tests for PB's CraftMaterialAssistant.
--
--   lua test/run.lua        (from the add-on folder; any Lua 5.1+)
--
-- What is worth testing here is the arithmetic and the picker: how many of a material a batch
-- needs, what is counted as held under each scope, which candidates a search finds, which page
-- they land on, and that a pick survives its indices moving. All of it is decided in Lua from
-- values the client hands over, so all of it can be checked on a laptop -- and every one of
-- these checks is a PS5 session not spent finding out the same thing.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."
dofile(HERE .. "/harness.lua")

local failures = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then failures = failures + 1 end
	print(string.format("%s %-56s got=%s want=%s", ok and "PASS" or "FAIL", label,
		tostring(got), tostring(want)))
end

local function checkContains(label, haystack, needle)
	local ok = type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil
	if not ok then failures = failures + 1 end
	print(string.format("%s %-56s in=%s", ok and "PASS" or "FAIL", label,
		tostring(haystack)))
end

local function Row(label)
	return Panel.byLabel[GetString(_G[label])]
end

local function ColumnText(index)
	return Controls["PBsCraftMaterialAssistantWindow" ..
		({ "Name", "Need", "Have", "Short" })[index]].text
end

local function TitleText()
	return Controls["PBsCraftMaterialAssistantWindowTitle"].text
end

local function Lines(text)
	local lines = {}
	for line in tostring(text or ""):gmatch("[^\n]+") do
		lines[#lines + 1] = (line:gsub("|c%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	return lines
end

print("\n== 1. load ==")
Fire(EVENT_ADD_ON_LOADED, "PBsCraftMaterialAssistant")
local addon = PBS_CRAFT_MATERIAL_ASSISTANT
-- Not a literal: the version is read out of the manifest's Title line by the add-on and out
-- of its Version line by the test, so this also catches the release mistake of editing one of
-- those two adjacent lines and not the other.
check("version read from manifest", addon.version, ManifestLine("Version"))
check("and there is a version to read", (ManifestLine("Version") or ""):match("^%d"), "1")
check("slash command registered", type(SLASH_COMMANDS["/pbcraft"]), "function")
check("short slash registered", type(SLASH_COMMANDS["/pbcm"]), "function")
check("shipped scope", addon:Scope(), "CRAFTBAG")
check("nothing picked at first", addon:HasTarget(), false)

print("\n== 2. first activation ==")
Chat = {}
Fire(EVENT_PLAYER_ACTIVATED)
check("logging in says nothing in chat", #Chat, 0)
check("panel built", Panel ~= nil, true)
check("window created", addon.hud:Available(), true)
checkContains("window says nothing is picked", ColumnText(1), "Nothing picked")

print("\n== 3. searching ==")
check("by name", addon:Search("fish"), 1)
check("first match is the recipe", addon.matches[1].name, "Fish Stew")
check("empty search is everything known", addon:Search(""), 19)
addon.sv.knownOnly = false
check("unlearned recipes when asked for", addon:Search(""), 24)
addon.sv.knownOnly = true
check("case is ignored", addon:Search("FISH STEW"), 1)
check("no match is zero, not nil", addon:Search("zzzz"), 0)

print("\n== 4. categories and pages ==")
check("a category change keeps the search word", addon:SetCategory(2), true)
check("so a word that matched nothing still matches nothing", #addon.matches, 0)
addon:Search("")
addon:SetCategory(2)
check("known plans in that category", #addon.matches, 16)
check("page count", addon:PageCount(), 2)
check("full first page", #addon:PageEntries(), addon.PAGE_SIZE)
addon:SetPage(2)
check("remainder on the last page", #addon:PageEntries(), 4)
addon:SetPage(9)
check("page clamped to what exists", addon:Page(), 2)
addon:SetCursor(99)
check("cursor clamped to a page", addon:Cursor(), addon.PAGE_SIZE)
check("no candidate under a cursor past the end", addon:EntryAt(addon:Cursor()), nil)
addon:SetCategory(0)

print("\n== 5. picking through the slash command ==")
SLASH_COMMANDS["/pbcraft"]("find fish")
check("browse list showing after a search", addon:Showing(), true)
SLASH_COMMANDS["/pbcraft"]("pick 1")
check("picked", addon.sv.target.name, "Fish Stew")
check("browse list put away by the pick", addon:Showing(), false)
check("result item id remembered", addon.sv.target.itemId, 1001)

print("\n== 6. the arithmetic ==")
addon:SetQuantity(3)
local requirements = addon.recipes:Requirements()
check("ingredient rows", #requirements.rows, 2)
check("need is per-craft times the count", requirements.rows[1].need, 6)
check("held is backpack + bank + craft bag", requirements.rows[1].have, 4)
check("shortfall", requirements.rows[1].short, 2)
check("nothing short is zero, not negative", requirements.rows[2].short, 0)
check("materials short of something", requirements.shortCount, 1)
check("batches the held materials cover", requirements.craftable, 2)
check("yield is per-craft stack times the count", requirements.resultCount, 12)

print("\n== 7. what the window draws ==")
addon.hud:Refresh()
checkContains("title names what is being made", TitleText(), "Fish Stew")
checkContains("title carries the count", TitleText(), "x3")
checkContains("title says what comes out", TitleText(), "12 made")
checkContains("title says how many are missing", TitleText(), "Short of 1")
local names, needs, haves, shorts = Lines(ColumnText(1)), Lines(ColumnText(2)),
	Lines(ColumnText(3)), Lines(ColumnText(4))
check("a heading row and one row per ingredient", #names, 3)
check("every column is the same height", #needs .. #haves .. #shorts, "333")
check("first material", names[2], "Fish")
check("its need", needs[2], "6")
check("its held count", haves[2], "4")
check("its shortfall", shorts[2], "2")
check("a material with enough is not a number", shorts[3], "-")

print("\n== 8. the scope changes the answer ==")
addon:SetScope("BACKPACK")
check("backpack only", addon.recipes:Requirements().rows[1].have, 3)
addon:SetScope("BANK")
check("backpack and bank", addon.recipes:Requirements().rows[1].have, 4)
addon:SetScope("ALL")
check("everything counts the house banks", addon.recipes:Requirements().rows[2].have, 40)
addon:SetScope("CRAFTBAG")
check("a nonsense scope is refused", addon:SetScope("POCKETS"), false)

print("\n== 9. a material the client will not count ==")
addon:Search("Alchemy Table")
addon:Select(addon.matches[1])
local mystery = addon.recipes:Requirements()
check("uncounted materials are reported", mystery.unknownCount, 1)
check("and not counted as held", mystery.rows[2].have, nil)
check("and not counted as short", mystery.rows[2].short, nil)
addon.hud:Refresh()
check("drawn as a question mark, never as a zero", Lines(ColumnText(3))[3], "?")
checkContains("and the title says so", TitleText(), "could not be counted")

print("\n== 10. the candidate list in the window ==")
addon:Search("Alinor")
addon:SetShowing(true)
addon:SetCursor(3)
addon.hud:Refresh()
local candidates = Lines(ColumnText(1))
check("a heading and a full page", #candidates, addon.PAGE_SIZE + 1)
check("the marker is on the cursor", candidates[4]:sub(1, 1), ">")
check("and nowhere else", candidates[3]:sub(1, 1), " ")
checkContains("rows are numbered from one on every page", candidates[2], "1. Alinor Plan 01")
checkContains("the count and page are on the title", TitleText(), "page 1 of 2")

print("\n== 11. inventory traffic is coalesced ==")
addon:SetShowing(false)
addon:Select(addon.matches[1])
check("inventory events registered while a pick is up", Registered(EVENT_INVENTORY_SINGLE_SLOT_UPDATE), 1)
for _ = 1, 20 do Fire(EVENT_INVENTORY_SINGLE_SLOT_UPDATE) end
check("twenty events, one redraw asked for", PendingCallLaters(), 1)
FlushCallLater()
check("and the queue is empty afterwards", PendingCallLaters(), 0)
addon:SetShowing(true)
check("not listening while browsing", Registered(EVENT_INVENTORY_SINGLE_SLOT_UPDATE), 0)
addon:SetShowing(false)

print("\n== 12. a pick survives its indices moving ==")
addon:Search("Fish Stew")
addon:Select(addon.matches[1])
check("picked at the index it was found at", addon.sv.target.recipe, 1)
table.insert(Catalogue[1].recipes, 1,
	{ name = "New Chapter Dish", known = true, itemId = 1099, stack = 1,
	  ingredients = { { id = 11, name = "Fish", required = 1 } } })
check("re-found by its result item id", addon.recipes:ResolveTarget(), true)
check("indices rewritten", addon.sv.target.recipe, 2)
check("still the same dish", addon.recipes:Requirements().name, "Fish Stew")
table.remove(Catalogue[1].recipes, 1)

print("\n== 13. a pick that is really gone ==")
addon.sv.target.list, addon.sv.target.recipe = 9, 9
addon.sv.target.itemId = 987654
check("not resolvable", addon.recipes:ResolveTarget(), false)
check("and no requirements are invented", addon.recipes:Requirements(), nil)
addon.hud:Refresh()
checkContains("the window says so", ColumnText(1), "not in this client")

print("\n== 14. the panel ==")
check("category row is there", Row("SI_PBSCMA_CATEGORY") ~= nil, true)
check("no search row without library support", Row("SI_PBSCMA_SEARCH"), nil)
Row("SI_PBSCMA_ENABLED").setFunction(false)
check("master switch takes the window down", Controls["PBsCraftMaterialAssistantWindow"]:IsHidden(), true)
Row("SI_PBSCMA_ENABLED").setFunction(true)
check("and puts it back", Controls["PBsCraftMaterialAssistantWindow"]:IsHidden(), false)

addon:Search("Honey")
addon:SetShowing(true)
Chat = {}
Row("SI_PBSCMA_CURSOR").setFunction(1)
Row("SI_PBSCMA_TAKE").clickHandler()
check("the panel says nothing in chat either", #Chat, 0)
check("the button takes what the marker is on", addon.sv.target.name, "Honey Rolls")
check("and puts the material table back", addon:Showing(), false)

Row("SI_PBSCMA_QUANTITY").setFunction(10)
check("quantity row", addon:Quantity(), 10)
check("and the table follows it", addon.recipes:Requirements().rows[1].need, 30)

Row("SI_PBSCMA_FONT_SIZE").setFunction(40)
check("text size reaches the label", Controls["PBsCraftMaterialAssistantWindowName"].font,
	"$(GAMEPAD_MEDIUM_FONT)|40|soft-shadow-thin")
Row("SI_PBSCMA_WIDTH").setFunction(900)
check("width reaches the window", Controls["PBsCraftMaterialAssistantWindow"].width, 900)
Row("SI_PBSCMA_DRAW").setFunction(nil, nil, { data = "BACK" })
check("draw layer reaches the window", Controls["PBsCraftMaterialAssistantWindow"].drawLayer, DL_BACKGROUND)
check("and the tier with it", Controls["PBsCraftMaterialAssistantWindow"].drawTier, DT_LOW)

print("\n== 15. reset ==")
Row("SI_PBSCMA_RESET").clickHandler()
check("settings back to shipped", addon.sv.window.size, addon.DEFAULTS.window.size)
check("nothing picked", addon:HasTarget(), false)
check("scope back to shipped", addon:Scope(), "CRAFTBAG")
check("window rebuilt at the shipped size", Controls["PBsCraftMaterialAssistantWindow"].width,
	addon.DEFAULTS.window.width)

print("\n== 16. the slash command answers everything ==")
Chat = {}
SLASH_COMMANDS["/pbcraft"]("")
check("status says nothing is picked", #Chat > 0, true)
Chat = {}
SLASH_COMMANDS["/pbcraft"]("qty 500")
checkContains("an out-of-range count is refused", Chat[1], "between")
Chat = {}
SLASH_COMMANDS["/pbcraft"]("wibble")
checkContains("an unknown command says so", Chat[1], "no such command")
Chat = {}
SLASH_COMMANDS["/pbcraft"]("list")
check("categories listed with their numbers", #Chat, 5)
Chat = {}
SLASH_COMMANDS["/pbcraft"]("probe")
checkContains("probe counts the catalogue", Chat[1], "3 lists, 24 recipes, 19 of them learned")
Chat = {}
SLASH_COMMANDS["/pbcraft"]("scope craftbag")
check("scope set from chat", addon:Scope(), "CRAFTBAG")

print("")
if failures == 0 then
	print("all checks passed")
else
	print(failures .. " CHECK(S) FAILED")
end
os.exit(failures == 0 and 0 or 1)

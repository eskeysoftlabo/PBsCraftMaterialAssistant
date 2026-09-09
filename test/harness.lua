-- Stub of just enough ESO client to exercise PBsCraftMaterialAssistant.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload, boot
-- the PS5, log in. What is stubbed here is only what the add-on actually touches -- the recipe
-- functions, GetItemLinkStacks, a LabelControl that records the text put in it, saved
-- variables, and LibHarvensAddonSettings -- so the arithmetic and the picker can be exercised
-- here instead.
local DIR = ADDON_DIR

-- ---- string table -------------------------------------------------------------------
local stringValues = {}
local nextId = 1
function ZO_CreateStringId(id, value)
	if not _G[id] then _G[id] = nextId; nextId = nextId + 1 end
	stringValues[_G[id]] = value
end
function SafeAddVersion() end
function GetString(id) return stringValues[id] or ("<missing " .. tostring(id) .. ">") end

-- ---- chat / misc --------------------------------------------------------------------
Chat = {}
CHAT_ROUTER = { AddSystemMessage = function(_, t) Chat[#Chat + 1] = t end }
function d(t) print("[d] " .. tostring(t)) end
SLASH_COMMANDS = {}

local pendingCallLater = {}
function zo_callLater(fn, ms) pendingCallLater[#pendingCallLater + 1] = fn end
function FlushCallLater()
	local queue = pendingCallLater
	pendingCallLater = {}
	for _, fn in ipairs(queue) do fn() end
end
function PendingCallLaters() return #pendingCallLater end

-- The title line as it really is in the manifest, colour markup and all. Read rather than
-- copied: a test that carries its own idea of the version stops testing the release step the
-- moment somebody edits the manifest and not the harness.
function ManifestLine(field)
	local file = io.open(DIR .. "/PBsCraftMaterialAssistant.addon", "r")
	if not file then return nil end
	local found
	for line in file:lines() do
		found = found or line:match("^## " .. field .. ":%s*(.-)%s*$")
	end
	file:close()
	return found
end

function GetAddOnManager()
	return {
		GetNumAddOns = function() return 1 end,
		GetAddOnInfo = function(_, i)
			return "PBsCraftMaterialAssistant", ManifestLine("Title")
		end,
	}
end

-- ---- events -------------------------------------------------------------------------
EVENT_ADD_ON_LOADED = "EVENT_ADD_ON_LOADED"
EVENT_PLAYER_ACTIVATED = "EVENT_PLAYER_ACTIVATED"
EVENT_INVENTORY_SINGLE_SLOT_UPDATE = "EVENT_INVENTORY_SINGLE_SLOT_UPDATE"
EVENT_INVENTORY_FULL_UPDATE = "EVENT_INVENTORY_FULL_UPDATE"
EVENT_CRAFT_COMPLETED = "EVENT_CRAFT_COMPLETED"
EVENT_RECIPE_LEARNED = "EVENT_RECIPE_LEARNED"

local handlers = {}
EVENT_MANAGER = {
	RegisterForEvent = function(_, name, event, fn)
		handlers[event] = handlers[event] or {}
		handlers[event][name] = fn
	end,
	UnregisterForEvent = function(_, name, event)
		if handlers[event] then handlers[event][name] = nil end
	end,
}
function Fire(event, ...)
	for _, fn in pairs(handlers[event] or {}) do fn(event, ...) end
end
function Registered(event)
	local count = 0
	for _ in pairs(handlers[event] or {}) do count = count + 1 end
	return count
end

-- ---- saved variables ----------------------------------------------------------------
SavedStore = {}
local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = DeepCopy(v) end
	return out
end
ZO_SavedVars = {
	NewAccountWide = function(_, name, version, namespace, defaults)
		SavedStore[name] = SavedStore[name] or {}
		local store = SavedStore[name]
		for k, v in pairs(defaults or {}) do
			if store[k] == nil then store[k] = DeepCopy(v) end
		end
		return store
	end,
}

-- ---- controls -----------------------------------------------------------------------
TOPLEFT, TOP, TOPRIGHT = 1, 2, 3
LEFT, CENTER, RIGHT = 4, 5, 6
BOTTOMLEFT, BOTTOM, BOTTOMRIGHT = 7, 8, 9
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = 1, 2, 3
TEXT_ALIGN_TOP = 1
TEXT_WRAP_MODE_ELLIPSIS = 1
CT_LABEL, CT_BACKDROP = "label", "backdrop"
DL_OVERLAY, DL_CONTROLS, DL_BACKGROUND = 4, 2, 0
DT_HIGH, DT_MEDIUM, DT_LOW = 3, 2, 1
GuiRoot = { name = "GuiRoot" }

local function MakeControl(name)
	local control = { name = name, anchors = {}, hidden = false }
	function control:SetText(text) self.text = text end
	function control:GetText() return self.text end
	function control:SetFont(font) self.font = font end
	function control:GetFont() return self.font end
	function control:SetDimensions(w, h) self.width, self.height = w, h end
	function control:GetWidth() return self.width end
	function control:SetHidden(v) self.hidden = v and true or false end
	function control:IsHidden() return self.hidden end
	function control:SetMouseEnabled(v) self.mouse = v end
	function control:SetMovable(v) self.movable = v end
	function control:SetColor() end
	function control:SetCenterColor(...) self.centerColor = { ... } end
	function control:SetEdgeColor(...) end
	function control:SetHorizontalAlignment(v) self.hAlign = v end
	function control:SetVerticalAlignment(v) self.vAlign = v end
	function control:SetWrapMode(v) self.wrap = v end
	function control:SetMaxLineCount(v) self.maxLines = v end
	function control:ClearAnchors() self.anchors = {} end
	function control:SetAnchor(point, rel, relPoint, x, y)
		self.anchors[#self.anchors + 1] = { point = point, x = x, y = y }
	end
	function control:SetDrawLayer(v) self.drawLayer = v end
	function control:SetDrawTier(v) self.drawTier = v end
	return control
end

Controls = {}
WINDOW_MANAGER = {
	CreateTopLevelWindow = function(_, name)
		Controls[name] = MakeControl(name)
		return Controls[name]
	end,
	CreateControl = function(_, name, parent, controlType)
		Controls[name] = MakeControl(name)
		Controls[name].parent = parent
		Controls[name].controlType = controlType
		return Controls[name]
	end,
}

-- ---- the recipe catalogue -----------------------------------------------------------
--
-- Three lists. The furnishing list is deliberately longer than one page of candidates so that
-- paging is exercised, and one ingredient (item 999) is one the client will not count, so the
-- "?" path is exercised too.

local function Ingredient(id, name, required) return { id = id, name = name, required = required } end

Catalogue = {
	{
		name = "Provisioning",
		recipes = {
			{ name = "Fish Stew", known = true, itemId = 1001, stack = 4, ingredients = {
				Ingredient(11, "Fish", 2), Ingredient(12, "Garlic", 1) } },
			{ name = "Honey Rolls", known = true, itemId = 1002, stack = 1, ingredients = {
				Ingredient(13, "Flour", 3), Ingredient(14, "Honey", 1), Ingredient(12, "Garlic", 2) } },
			{ name = "Dubious Camoran Throne", known = false, itemId = 1003, stack = 1, ingredients = {
				Ingredient(11, "Fish", 1), Ingredient(15, "Rice", 1) } },
		},
	},
	{
		name = "Furnishings",
		recipes = {},
	},
	{
		name = "Alchemy Furnishings",
		recipes = {
			{ name = "Alchemy Table, Rustic", known = true, itemId = 3001, stack = 1, ingredients = {
				Ingredient(21, "Rough Oak", 5), Ingredient(999, "Mystery Part", 1) } },
		},
	},
}

for index = 1, 20 do
	Catalogue[2].recipes[index] = {
		name = string.format("Alinor Plan %02d", index),
		known = index % 5 ~= 0,
		itemId = 2000 + index,
		stack = 1,
		ingredients = { Ingredient(21, "Rough Oak", index), Ingredient(22, "Regulus", 2) },
	}
end

-- What is in the bags. Item 999 is missing on purpose: the client answers nothing for it.
Inventory = {
	[11] = { backpack = 3, bank = 1, craftbag = 0, house = 0 },
	[12] = { backpack = 0, bank = 0, craftbag = 40, house = 0 },
	[13] = { backpack = 2, bank = 0, craftbag = 0, house = 10 },
	[14] = { backpack = 0, bank = 5, craftbag = 0, house = 0 },
	[21] = { backpack = 100, bank = 0, craftbag = 200, house = 0 },
	[22] = { backpack = 1, bank = 0, craftbag = 0, house = 0 },
}

local function Recipe(listIndex, recipeIndex)
	local list = Catalogue[listIndex]
	if not list then error("no such recipe list: " .. tostring(listIndex)) end
	local recipe = list.recipes[recipeIndex]
	if not recipe then error("no such recipe: " .. tostring(recipeIndex)) end
	return recipe, list
end

function GetNumRecipeLists() return #Catalogue end

function GetRecipeListInfo(listIndex)
	local list = Catalogue[listIndex]
	if not list then error("no such recipe list") end
	return list.name, #list.recipes, "", "", "", "", ""
end

function GetRecipeInfo(listIndex, recipeIndex)
	local recipe = Recipe(listIndex, recipeIndex)
	return recipe.known, recipe.name, #recipe.ingredients, 1, 1, 0, 0, recipe.itemId
end

function GetRecipeIngredientItemInfo(listIndex, recipeIndex, index)
	local recipe = Recipe(listIndex, recipeIndex)
	local ingredient = recipe.ingredients[index]
	if not ingredient then error("no such ingredient") end
	return ingredient.name, "icon", ingredient.required, 0, 0
end

function GetRecipeIngredientRequiredQuantity(listIndex, recipeIndex, index)
	local recipe = Recipe(listIndex, recipeIndex)
	return recipe.ingredients[index].required
end

LINK_STYLE_DEFAULT = 0

function GetRecipeIngredientItemLink(listIndex, recipeIndex, index)
	local recipe = Recipe(listIndex, recipeIndex)
	return string.format("|H1:item:%d|h|h", recipe.ingredients[index].id)
end

function GetRecipeResultItemInfo(listIndex, recipeIndex)
	local recipe = Recipe(listIndex, recipeIndex)
	return recipe.name, "icon", recipe.stack, 0, 0
end

function GetRecipeResultQuantity(listIndex, recipeIndex, iterations)
	local recipe = Recipe(listIndex, recipeIndex)
	return recipe.stack * iterations
end

-- Six numbers for one link, exactly as the client answers.
function GetItemLinkStacks(link)
	local id = tonumber(link:match("item:(%d+)"))
	local held = Inventory[id]
	if not held then return nil end
	return held.backpack, held.bank, held.craftbag, held.house, 0, 0
end

-- ---- LibHarvensAddonSettings --------------------------------------------------------
-- Enough of it to build the panel and press its rows from a test.
local panel = {}
panel.__index = panel
function panel:AddSetting(setting)
	self.rows[#self.rows + 1] = setting
	if setting.label then self.byLabel[setting.label] = setting end
	return setting
end
function panel:UpdateControls() self.updates = self.updates + 1 end

LibHarvensAddonSettings = {
	ST_SECTION = "section", ST_LABEL = "label", ST_CHECKBOX = "checkbox",
	ST_SLIDER = "slider", ST_DROPDOWN = "dropdown", ST_BUTTON = "button",
	-- ST_EDIT deliberately absent: the console library this add-on is written against is not
	-- known to have one, and the panel has to be complete without it.
	AddAddon = function(_, title)
		Panel = setmetatable({ title = title, rows = {}, byLabel = {}, updates = 0 }, panel)
		return Panel
	end,
}

-- ---- loading the add-on -------------------------------------------------------------
dofile(DIR .. "/lang/strings.lua")
dofile(DIR .. "/Main.lua")
dofile(DIR .. "/Recipes.lua")
dofile(DIR .. "/Hud.lua")
dofile(DIR .. "/Settings.lua")

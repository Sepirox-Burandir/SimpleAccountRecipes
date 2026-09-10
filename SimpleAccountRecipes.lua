--[[
  SimpleSimpleAccountRecipes — Vanilla WoW 1.12.1 (Build 5875), Lua 5.0
  Account-wide learned-recipe tracker.

  Scan once when the profession window is opened.
  Crafting does not scan (TRADE_SKILL_UPDATE is ignored).
  A later scan on a lower-skill character will only ADD names, never remove.
]]

local ADDON_NAME = "SimpleAccountRecipes"

local db
local initialized = false
local scanning = false
local hinted = false
local pendingKind = nil
local pendingAt = 0

local SCAN_DELAY = 0.4

local L = {
	prefix = "|cff88ff88SimpleAccountRecipes|r: ",
	known = "Account Known",
	scanned = "Scanned",
	help1 = "/ar stats | list [profession] | search <name> | chars",
	help2 = "Opening a profession scans it once. Crafting does not scan.",
	empty = "Database is empty. Open a profession window to scan.",
	wiped = "Database wiped.",
	nowipe = "To wipe the database type: /ar wipe confirm",
	stats = "%d recipes stored across %d professions.",
	none = "No matches.",
	scan = "%s: +%d new (%d visible, %d account total).",
	scan0 = "%s: no new recipes (%d visible, %d account total).",
	chars = "Scanned characters:",
	needinit = "Addon is not ready yet.",
}

if GetLocale() == "deDE" then
	L.known = "Account bekannt"
	L.scanned = "Erfasst"
	L.help1 = "/ar stats | list [beruf] | search <name> | chars"
	L.help2 = "Beruf oeffnen = einmal scannen. Herstellen scannt nicht."
	L.empty = "Datenbank leer. Berufsfenster oeffnen zum Scannen."
	L.wiped = "Datenbank geloescht."
	L.nowipe = "Zum Loeschen der Datenbank: /ar wipe confirm"
	L.stats = "%d Rezepte in %d Berufen gespeichert."
	L.none = "Keine Treffer."
	L.scan = "%s: +%d neu (%d sichtbar, %d Account gesamt)."
	L.scan0 = "%s: keine neuen Rezepte (%d sichtbar, %d Account gesamt)."
	L.chars = "Gescannte Charaktere:"
	L.needinit = "Addon ist noch nicht bereit."
end

local SKIP_CRAFT = {
	["Beast Training"] = true,
	["Wildtierausbildung"] = true,
	["Dressage des betes"] = true,
	["Adiestramiento de bestias"] = true,
}

local RECIPE_PREFIX = {
	["pattern"] = true, ["plans"] = true, ["schematic"] = true,
	["formula"] = true, ["recipe"] = true, ["manual"] = true,
	["design"] = true, ["technique"] = true, ["diagram"] = true,
	["muster"] = true, ["plaene"] = true, ["plane"] = true,
	["bauplan"] = true, ["formel"] = true, ["rezept"] = true,
	["handbuch"] = true, ["entwurf"] = true,
	["patron"] = true, ["recette"] = true, ["schema"] = true,
	["dessin"] = true,
}

local function Print(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(L.prefix .. msg)
	end
end

local function trim(s)
	if not s then return "" end
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

local function Normalize(name)
	if not name then return nil end
	name = trim(name)
	if name == "" then return nil end
	local stripped = string.gsub(name, "^[^:]+:%s*", "")
	stripped = trim(stripped)
	if stripped == "" then stripped = name end
	return string.lower(stripped)
end

local function PrefixWord(name)
	if not name then return nil end
	local _, _, pre = string.find(name, "^([^:]+):")
	if not pre then return nil end
	return string.lower(trim(pre))
end

local function PlayerKey()
	return (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
end

local function CountRecipes()
	local n = 0
	if db and db.recipes then
		for _ in pairs(db.recipes) do
			n = n + 1
		end
	end
	return n
end

local function CountProfessions()
	local seen = {}
	local n = 0
	if db and db.recipes then
		for _, rec in pairs(db.recipes) do
			if rec.profession and not seen[rec.profession] then
				seen[rec.profession] = true
				n = n + 1
			end
		end
	end
	return n
end

local function Lookup(name)
	if not db or not db.recipes or not name then return nil end
	local key = Normalize(name)
	if not key then return nil end
	return db.recipes[key]
end

local function Remember(recipeName, profession, rank)
	local key = Normalize(recipeName)
	if not key then return false end
	if db.recipes[key] then
		return false
	end
	db.recipes[key] = {
		name = recipeName,
		profession = profession or "?",
		by = UnitName("player") or "?",
		realm = GetRealmName() or "?",
		rank = rank,
	}
	return true
end

local function ClearTradeFilters()
	if SetTradeSkillSubClassFilter then
		SetTradeSkillSubClassFilter(0, 1, 1)
	end
	if SetTradeSkillInvSlotFilter then
		SetTradeSkillInvSlotFilter(0, 1, 1)
	end
end

local function ExpandTradeHeaders()
	local i = 1
	local n = GetNumTradeSkills() or 0
	local guard = 0
	while i <= n and guard < 400 do
		guard = guard + 1
		local _, skillType, _, isExpanded = GetTradeSkillInfo(i)
		if skillType == "header" and not isExpanded then
			ExpandTradeSkillSubClass(i)
			n = GetNumTradeSkills() or n
		end
		i = i + 1
	end
end

local function ExpandCraftHeaders()
	local i = 1
	local n = GetNumCrafts() or 0
	local guard = 0
	while i <= n and guard < 400 do
		guard = guard + 1
		local _, _, craftType, _, isExpanded = GetCraftInfo(i)
		if craftType == "header" and not isExpanded then
			ExpandCraftSkillLine(i)
			n = GetNumCrafts() or n
		end
		i = i + 1
	end
end

local function CurrentProfession(kind)
	if kind == "craft" then
		local prof, rank
		if GetCraftDisplaySkillLine then
			prof, rank = GetCraftDisplaySkillLine()
		end
		if (not prof or prof == "") and GetCraftName then
			prof = GetCraftName()
		end
		if not prof or prof == "" or SKIP_CRAFT[prof] then
			return nil, nil
		end
		return prof, rank
	end
	if not GetTradeSkillLine then return nil, nil end
	local prof, rank = GetTradeSkillLine()
	if not prof or prof == "" or prof == "UNKNOWN" then
		return nil, nil
	end
	return prof, rank
end

local function ScanTradeSkill()
	if not GetTradeSkillLine then return 0, 0, nil end
	local prof, rank = GetTradeSkillLine()
	if not prof or prof == "" or prof == "UNKNOWN" then
		return 0, 0, nil
	end
	ClearTradeFilters()
	ExpandTradeHeaders()
	local added = 0
	local visible = 0
	local n = GetNumTradeSkills() or 0
	local i = 1
	while i <= n do
		local skillName, skillType = GetTradeSkillInfo(i)
		if skillName and skillType and skillType ~= "header" then
			visible = visible + 1
			if Remember(skillName, prof, rank) then
				added = added + 1
			end
		end
		i = i + 1
	end
	return added, visible, prof
end

local function ScanCraft()
	if not GetCraftInfo then return 0, 0, nil end
	local prof
	local rank
	if GetCraftDisplaySkillLine then
		prof, rank = GetCraftDisplaySkillLine()
	end
	if (not prof or prof == "") and GetCraftName then
		prof = GetCraftName()
	end
	if not prof or prof == "" or SKIP_CRAFT[prof] then
		return 0, 0, nil
	end
	ExpandCraftHeaders()
	local added = 0
	local visible = 0
	local n = GetNumCrafts() or 0
	local i = 1
	while i <= n do
		local craftName, _, craftType = GetCraftInfo(i)
		if craftName and craftType and craftType ~= "header" then
			visible = visible + 1
			if Remember(craftName, prof, rank) then
				added = added + 1
			end
		end
		i = i + 1
	end
	return added, visible, prof
end

local function NoteScan(prof, visible, rank)
	if not prof then return end
	if not db.scans then db.scans = {} end
	local pk = PlayerKey()
	if not db.scans[pk] then db.scans[pk] = {} end
	db.scans[pk][prof] = {
		visible = visible,
		rank = rank,
		player = UnitName("player"),
		realm = GetRealmName(),
	}
end

local function RunScan(kind)
	if not initialized or not db then return end
	if scanning then return end
	scanning = true
	local prof, rank = CurrentProfession(kind)
	if not prof then
		scanning = false
		return
	end
	local added, visible, scannedProf
	if kind == "craft" then
		added, visible, scannedProf = ScanCraft()
	else
		added, visible, scannedProf = ScanTradeSkill()
	end
	scanning = false
	if not scannedProf then return end
	NoteScan(scannedProf, visible, rank)
	if added > 0 then
		Print(string.format(L.scan, scannedProf, added, visible, CountRecipes()))
	end
end

local function TooltipTitle(tip)
	if not tip or not tip.GetName then return nil end
	local fs = getglobal(tip:GetName() .. "TextLeft1")
	if not fs or not fs.GetText then return nil end
	return fs:GetText()
end

local function TooltipHasText(tip, needle)
	if not tip or not tip.NumLines then return false end
	local n = tip:NumLines() or 0
	local i = 1
	while i <= n do
		local fs = getglobal(tip:GetName() .. "TextLeft" .. i)
		if fs then
			local t = fs:GetText()
			if t and string.find(t, needle, 1, true) then
				return true
			end
		end
		i = i + 1
	end
	return false
end

local function TooltipLooksLikeRecipe(tip, title)
	local pre = PrefixWord(title)
	if pre and RECIPE_PREFIX[pre] then
		return true
	end
	local n = tip:NumLines() or 0
	local i = 2
	while i <= n do
		local fs = getglobal(tip:GetName() .. "TextLeft" .. i)
		if fs then
			local t = fs:GetText()
			if t then
				local low = string.lower(t)
				if string.find(low, "teaches you", 1, true)
					or string.find(low, "unterrichtet euch", 1, true)
					or string.find(low, "lehrt euch", 1, true)
					or string.find(low, "vous apprend", 1, true)
					or string.find(low, "te ensena", 1, true)
					or string.find(low, "ensena", 1, true)
				then
					return true
				end
			end
		end
		i = i + 1
	end
	return false
end

local function AddKnownLine(tip, rec, force)
	if not tip or not rec then return end
	if TooltipHasText(tip, L.known) then return end
	local title = TooltipTitle(tip)
	if not force then
		if not title or not TooltipLooksLikeRecipe(tip, title) then
			return
		end
	end
	tip:AddLine(L.known, 0.2, 1.0, 0.2)
	local extra = rec.by
	if rec.profession and rec.profession ~= "?" then
		if extra then
			extra = extra .. " (" .. rec.profession .. ")"
		else
			extra = rec.profession
		end
	end
	if extra then
		tip:AddLine(L.scanned .. ": " .. extra, 0.55, 0.55, 0.55)
	end
	tip:Show()
end

local function ProcessTooltip(tip, force)
	if not initialized or not db or not tip then return end
	local title = TooltipTitle(tip)
	if not title then return end
	local rec = Lookup(title)
	if rec then
		AddKnownLine(tip, rec, force)
	end
end

local function HookMethod(obj, method, force)
	if not obj or not obj[method] then return end
	local orig = obj[method]
	obj[method] = function(a1, a2, a3, a4, a5, a6, a7)
		local r1, r2, r3, r4 = orig(a1, a2, a3, a4, a5, a6, a7)
		local tip = a1
		if type(tip) ~= "table" or not tip.AddLine then
			tip = obj
		end
		ProcessTooltip(tip, force)
		return r1, r2, r3, r4
	end
end

local function HookTooltips()
	local methods = {
		"SetBagItem", "SetInventoryItem", "SetAuctionItem", "SetAuctionSellItem",
		"SetMerchantItem", "SetBuybackItem", "SetLootItem", "SetLootRollItem",
		"SetQuestItem", "SetQuestLogItem", "SetInboxItem", "SetSendMailItem",
		"SetTradePlayerItem", "SetTradeTargetItem", "SetHyperlink",
		"SetCraftItem", "SetTradeSkillItem",
	}
	local i = 1
	local n = table.getn(methods)
	while i <= n do
		HookMethod(GameTooltip, methods[i], false)
		i = i + 1
	end
	HookMethod(GameTooltip, "SetTrainerService", true)
	if ItemRefTooltip then
		HookMethod(ItemRefTooltip, "SetHyperlink", false)
	end
end

local function CmdStats()
	Print(string.format(L.stats, CountRecipes(), CountProfessions()))
end

local function CmdChars()
	if not db.scans then
		Print(L.empty)
		return
	end
	Print(L.chars)
	for pk, profs in pairs(db.scans) do
		local list = {}
		for pname, info in pairs(profs) do
			local bit = pname
			if info and info.visible then
				bit = pname .. " " .. tostring(info.visible)
			end
			table.insert(list, bit)
		end
		local joined = ""
		local i = 1
		local n = table.getn(list)
		while i <= n do
			if joined ~= "" then joined = joined .. ", " end
			joined = joined .. list[i]
			i = i + 1
		end
		DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff" .. pk .. "|r  " .. joined)
	end
end

local function CmdList(filter)
	filter = trim(filter or "")
	local filterLow = string.lower(filter)
	local shown = 0
	local names = {}
	for _, rec in pairs(db.recipes) do
		local ok = true
		if filterLow ~= "" then
			if string.lower(rec.profession or "") ~= filterLow then
				ok = false
			end
		end
		if ok then
			table.insert(names, rec)
			shown = shown + 1
		end
	end
	if shown == 0 then
		Print(L.none)
		return
	end
	local i = 2
	while i <= shown do
		local j = i
		while j > 1 do
			local a = names[j - 1]
			local b = names[j]
			local ap = a.profession or ""
			local bp = b.profession or ""
			if ap < bp or (ap == bp and (a.name or "") < (b.name or "")) then
				break
			end
			names[j - 1] = b
			names[j] = a
			j = j - 1
		end
		i = i + 1
	end
	Print(string.format("%d:", shown))
	i = 1
	local cap = 80
	while i <= shown and i <= cap do
		local rec = names[i]
		DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaa" .. (rec.profession or "?") .. "|r  " .. (rec.name or "?"))
		i = i + 1
	end
	if shown > cap then
		Print("... " .. tostring(shown - cap) .. " more. Use /ar search <text>.")
	end
end

local function CmdSearch(q)
	q = string.lower(trim(q or ""))
	if q == "" then
		Print(L.help1)
		return
	end
	local shown = 0
	for _, rec in pairs(db.recipes) do
		local n = string.lower(rec.name or "")
		local p = string.lower(rec.profession or "")
		if string.find(n, q, 1, true) or string.find(p, q, 1, true) then
			DEFAULT_CHAT_FRAME:AddMessage("  |cff88ff88" .. L.known .. "|r  |cffaaaaaa" .. (rec.profession or "?") .. "|r  " .. (rec.name or "?"))
			shown = shown + 1
			if shown >= 60 then
				Print("... more matches. Narrow the search.")
				return
			end
		end
	end
	if shown == 0 then
		Print(L.none)
	end
end

local function OnSlash(msg)
	if not initialized then
		Print(L.needinit)
		return
	end
	msg = trim(msg or "")
	local cmd = msg
	local rest = ""
	local s, e = string.find(msg, "%s+")
	if s then
		cmd = string.sub(msg, 1, s - 1)
		rest = trim(string.sub(msg, e + 1))
	end
	cmd = string.lower(cmd)
	if cmd == "" or cmd == "help" then
		Print(L.help1)
		Print(L.help2)
		CmdStats()
	elseif cmd == "stats" or cmd == "stat" then
		CmdStats()
	elseif cmd == "chars" or cmd == "char" or cmd == "characters" then
		CmdChars()
	elseif cmd == "list" then
		CmdList(rest)
	elseif cmd == "search" or cmd == "find" or cmd == "s" then
		CmdSearch(rest)
	elseif cmd == "wipe" then
		if string.lower(rest) == "confirm" then
			SimpleAccountRecipesDB = { version = 1, recipes = {}, scans = {} }
			db = SimpleAccountRecipesDB
			Print(L.wiped)
		else
			Print(L.nowipe)
		end
	else
		CmdSearch(msg)
	end
end

local eventFrame = CreateFrame("Frame", "SimpleAccountRecipesEventFrame")
local timerFrame = CreateFrame("Frame", "SimpleAccountRecipesTimerFrame")
timerFrame:Hide()

timerFrame:SetScript("OnUpdate", function()
	if pendingAt == 0 then
		timerFrame:Hide()
		return
	end
	if GetTime() >= pendingAt then
		local kind = pendingKind
		pendingAt = 0
		pendingKind = nil
		timerFrame:Hide()
		if kind then
			RunScan(kind)
		end
	end
end)

local function QueueScan(kind)
	if scanning then return end
	pendingKind = kind
	pendingAt = GetTime() + SCAN_DELAY
	timerFrame:Show()
end

local function CancelScan()
	pendingKind = nil
	pendingAt = 0
	timerFrame:Hide()
end

local function InitDB()
	if not SimpleAccountRecipesDB or type(SimpleAccountRecipesDB) ~= "table" then
		SimpleAccountRecipesDB = {}
	end
	if not SimpleAccountRecipesDB.recipes then
		SimpleAccountRecipesDB.recipes = {}
	end
	if not SimpleAccountRecipesDB.scans then
		SimpleAccountRecipesDB.scans = {}
	end
	SimpleAccountRecipesDB.version = 1
	db = SimpleAccountRecipesDB
	initialized = true
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_CLOSE")
eventFrame:RegisterEvent("CRAFT_SHOW")
eventFrame:RegisterEvent("CRAFT_CLOSE")

eventFrame:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			InitDB()
			HookTooltips()
			SLASH_SimpleAccountRecipes1 = "/sar"
			SLASH_SimpleAccountRecipes2 = "/SimpleAccountRecipes"
			SlashCmdList["SimpleAccountRecipes"] = OnSlash
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if initialized and (not hinted) and CountRecipes() == 0 then
			hinted = true
			Print(L.help2)
		end
	elseif event == "TRADE_SKILL_SHOW" then
		QueueScan("trade")
	elseif event == "CRAFT_SHOW" then
		QueueScan("craft")
	elseif event == "TRADE_SKILL_CLOSE" then
		CancelScan()
	elseif event == "CRAFT_CLOSE" then
		CancelScan()
	end
end)

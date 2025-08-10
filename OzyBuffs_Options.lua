-- Author: Ozy

local ADDON_NAME = ...

local panel
local settingsCategory -- for Settings UI (modern/SoD clients)

local function makeCheckButton(name, label, parent)
  local b = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  b.Text:SetText(label)
  return b
end

local function makeDropdown(name, parent, width)
  local d = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
  d:SetWidth(width or 160)
  return d
end

-- Deprecated: replaced by scrollable edit box below
local function makeEditBox(name, parent, width, height)
  local e = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
  e:SetAutoFocus(false)
  e:SetMultiLine(true)
  e:SetSize(width, height)
  e:SetFontObject(ChatFontNormal)
  e:SetTextInsets(6, 6, 6, 6)
  e:SetTextColor(1, 1, 1)
  return e
end

local function buildBuffList()
  local _, class = UnitClass("player")
  local spells = {}
  if class == "MAGE" then
    spells = {
      "Arcane Intellect",
      "Arcane Brilliance",
      "Amplify Magic",
      "Dampen Magic",
    }
  elseif class == "PRIEST" then
    spells = {
      "Power Word: Fortitude",
      "Prayer of Fortitude",
      "Divine Spirit",
      "Prayer of Spirit",
      "Shadow Protection",
      "Prayer of Shadow Protection",
    }
  end
  return spells
end

local function luaEscape(s)
  if not s then return "" end
  s = s:gsub("\\", "\\\\")
  s = s:gsub("\"", "\\\"")
  return s
end

-- Simple reusable text popup for exporting data
local function ShowTextPopup(titleText, bodyText)
  if not OZYB_TextPopup then
    local f = CreateFrame("Frame", "OZYB_TextPopup", UIParent, "TooltipBackdropTemplate")
    f:SetSize(620, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local t = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 12, -12)
    t:SetText("OzyBuffs Export")
    f.title = t

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -40)
    scroll:SetPoint("BOTTOMRIGHT", -36, 46)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(560)
    eb:SetTextColor(1,1,1)
    scroll:SetScrollChild(eb)
    f.editBox = eb

    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(80, 22)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)

    OZYB_TextPopup = f
  end
  OZYB_TextPopup.title:SetText(titleText or "OzyBuffs Export")
  OZYB_TextPopup.editBox:SetText(bodyText or "")
  OZYB_TextPopup:Show()
  OZYB_TextPopup.editBox:SetFocus()
  OZYB_TextPopup.editBox:HighlightText()
end

local function refreshPhrasesArea(profile, area, spellName, category)
  local lines = {}
  local srcTbl = profile.phrases[spellName] and profile.phrases[spellName][category]
  local defTbl = nil
  if OZY_USER_PHRASES and OZY_USER_PHRASES[spellName] then
    defTbl = OZY_USER_PHRASES[spellName][category]
  elseif OZY_PHRASES and OZY_PHRASES[spellName] then
    defTbl = OZY_PHRASES[spellName][category]
  end
  if srcTbl and #srcTbl > 0 then for _, s in ipairs(srcTbl) do table.insert(lines, s) end
  elseif defTbl and #defTbl > 0 then for _, s in ipairs(defTbl) do table.insert(lines, s) end end
  area:SetText(table.concat(lines, "\n"))
end

local function savePhrasesFromArea(profile, area, spellName, category)
  local text = area:GetText() or ""
  local lines = {}
  for line in text:gmatch("[^\n]+") do
    local trimmed = strtrim(line)
    if trimmed ~= "" then table.insert(lines, trimmed) end
  end
  if not profile.phrases[spellName] then profile.phrases[spellName] = {} end
  profile.phrases[spellName][category] = lines
end

local function OpenOptions()
  if panel then
    if Settings and Settings.OpenToCategory and settingsCategory then
      Settings.OpenToCategory(settingsCategory.ID or settingsCategory)
    elseif InterfaceOptionsFrame_OpenToCategory then
      InterfaceOptionsFrame_OpenToCategory(panel)
    end
    return
  end

  panel = CreateFrame("Frame", ADDON_NAME .. "OptionsPanel", UIParent)
  panel.name = "OzyBuffs"
  
  -- Scrollable container
  local scroll = CreateFrame("ScrollFrame", ADDON_NAME .. "OptionsScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(800, 1400)
  scroll:SetScrollChild(content)

  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  local version = OzyBuffs_GetVersion and OzyBuffs_GetVersion() or "unknown"
  title:SetText("OzyBuffs Options  |  v" .. version)

  local db = OzyBuffs_GetDB()

  -- Per-account vs per-character
  local perChar = makeCheckButton("OZYB_PerChar", "Use per-character settings", content)
  perChar:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  perChar:SetChecked(db.usePerCharacter)
  perChar:SetScript("OnClick", function(self)
    db.usePerCharacter = self:GetChecked() and true or false
    OzyBuffs_SetDB(db)
  end)

  -- Channel
  local chanLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  chanLabel:SetPoint("TOPLEFT", perChar, "BOTTOMLEFT", 0, -16)
  chanLabel:SetText("Channel")
  local chanDD = makeDropdown("OZYB_Chan", content, 160)
  chanDD:SetPoint("TOPLEFT", chanLabel, "BOTTOMLEFT", -10, -5)
  UIDropDownMenu_SetWidth(chanDD, 140)
  UIDropDownMenu_SetText(chanDD, db.channel)
  chanDD.tooltipText = "Channel used for sayings. AUTO picks RAID > PARTY > SAY."
  UIDropDownMenu_Initialize(chanDD, function(self, level)
    local function add(text, val)
      local info = UIDropDownMenu_CreateInfo()
      info.text = text
      info.func = function()
        db.channel = val
        UIDropDownMenu_SetText(chanDD, val)
        OzyBuffs_SetDB(db)
      end
      UIDropDownMenu_AddButton(info, level)
    end
    add("AUTO", "AUTO"); add("SAY", "SAY"); add("PARTY", "PARTY"); add("RAID", "RAID"); add("YELL", "YELL"); add("EMOTE", "EMOTE")
  end)

  -- Restrictions
  local restTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  restTitle:SetPoint("TOPLEFT", chanDD, "BOTTOMLEFT", 20, -20)
  restTitle:SetText("Restrictions")
  local disableCities = makeCheckButton("OZYB_DisableCities", "Disable in cities (rested)", content)
  disableCities:SetPoint("TOPLEFT", restTitle, "BOTTOMLEFT", 0, -6)
  disableCities:SetChecked(db.restrictions.disableInCities)
  disableCities:SetScript("OnClick", function(self) db.restrictions.disableInCities = self:GetChecked() and true or false; OzyBuffs_SetDB(db) end)
  disableCities.tooltipText = "When checked, sayings won't fire while you are in rested areas (cities/inns)."
  local onlyGroup = makeCheckButton("OZYB_OnlyGroup", "Only when in group/raid", content)
  onlyGroup:SetPoint("TOPLEFT", disableCities, "BOTTOMLEFT", 0, -6)
  onlyGroup:SetChecked(db.restrictions.onlyInGroup)
  onlyGroup:SetScript("OnClick", function(self) db.restrictions.onlyInGroup = self:GetChecked() and true or false; OzyBuffs_SetDB(db) end)
  onlyGroup.tooltipText = "Restrict sayings to when you are in a party or raid."
  local onlyInstance = makeCheckButton("OZYB_OnlyInstance", "Only inside instances", content)
  onlyInstance:SetPoint("TOPLEFT", onlyGroup, "BOTTOMLEFT", 0, -6)
  onlyInstance:SetChecked(db.restrictions.onlyInInstance)
  onlyInstance:SetScript("OnClick", function(self) db.restrictions.onlyInInstance = self:GetChecked() and true or false; OzyBuffs_SetDB(db) end)
  onlyInstance.tooltipText = "Restrict sayings to dungeons/raids/battlegrounds only."
  local skipSelf = makeCheckButton("OZYB_SkipSelf", "Skip self", content)
  skipSelf:SetPoint("TOPLEFT", onlyInstance, "BOTTOMLEFT", 0, -6)
  skipSelf:SetChecked(db.restrictions.skipSelf)
  skipSelf:SetScript("OnClick", function(self) db.restrictions.skipSelf = self:GetChecked() and true or false; OzyBuffs_SetDB(db) end)
  skipSelf.tooltipText = "Don't say a line when you buff yourself."
  local skipNPCs = makeCheckButton("OZYB_SkipNPC", "Skip NPCs", content)
  skipNPCs:SetPoint("TOPLEFT", skipSelf, "BOTTOMLEFT", 0, -6)
  skipNPCs:SetChecked(db.restrictions.skipNPCs)
  skipNPCs:SetScript("OnClick", function(self) db.restrictions.skipNPCs = self:GetChecked() and true or false; OzyBuffs_SetDB(db) end)
  skipNPCs.tooltipText = "Ignore buffs cast on NPCs; only quip on players."

  -- Humor toggles
  local humorTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  humorTitle:SetPoint("TOPLEFT", skipNPCs, "BOTTOMLEFT", 0, -16)
  humorTitle:SetText("Humor categories")
  local hNeutral = makeCheckButton("OZYB_HNeutral", "Neutral", content)
  hNeutral:SetPoint("TOPLEFT", humorTitle, "BOTTOMLEFT", 0, -6)
  hNeutral:SetChecked(db.humor.neutral)
  hNeutral.tooltipText = "Enable neutral tone phrases."
  hNeutral:SetScript("OnClick", function(self)
    db.humor.neutral = self:GetChecked() and true or false
    if not (db.humor.neutral or db.humor.snarky or db.humor.spicy) then
      db.humor.neutral = true
      hNeutral:SetChecked(true)
    end
    OzyBuffs_SetDB(db); OzyBuffs_ResetBags()
  end)
  local hSnarky = makeCheckButton("OZYB_HSnarky", "Snarky", content)
  hSnarky:SetPoint("TOPLEFT", hNeutral, "BOTTOMLEFT", 0, -6)
  hSnarky:SetChecked(db.humor.snarky)
  hSnarky.tooltipText = "Enable cheeky/snarky phrases."
  hSnarky:SetScript("OnClick", function(self)
    db.humor.snarky = self:GetChecked() and true or false
    if not (db.humor.neutral or db.humor.snarky or db.humor.spicy) then
      db.humor.neutral = true
      hNeutral:SetChecked(true)
    end
    OzyBuffs_SetDB(db); OzyBuffs_ResetBags()
  end)
  local hSpicy = makeCheckButton("OZYB_HSpicy", "Spicy", content)
  hSpicy:SetPoint("TOPLEFT", hSnarky, "BOTTOMLEFT", 0, -6)
  hSpicy:SetChecked(db.humor.spicy)
  hSpicy.tooltipText = "Enable spicy/edgier phrases (opt-in)."
  hSpicy:SetScript("OnClick", function(self)
    db.humor.spicy = self:GetChecked() and true or false
    if not (db.humor.neutral or db.humor.snarky or db.humor.spicy) then
      -- Prevent all-off; re-enable neutral as a safety net
      db.humor.neutral = true
      hNeutral:SetChecked(true)
    end
    OzyBuffs_SetDB(db); OzyBuffs_ResetBags()
  end)

  -- Phrases editor per buff
  local buffLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  buffLabel:SetPoint("TOPLEFT", hSpicy, "BOTTOMLEFT", 0, -16)
  buffLabel:SetText("Edit phrases for buff")
  local buffDD = makeDropdown("OZYB_BuffDD", content, 200)
  buffDD:SetPoint("TOPLEFT", buffLabel, "BOTTOMLEFT", -10, -4)
  UIDropDownMenu_SetWidth(buffDD, 180)
  buffDD.tooltipText = "Select the buff to edit phrases for."
  local currentSpell
  local currentCategory = "neutral"
  local phrasesBox -- declare before using inside dropdown callbacks
  UIDropDownMenu_Initialize(buffDD, function(self, level)
    local spells = buildBuffList()
    for _, s in ipairs(spells) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = s
      info.func = function()
        currentSpell = s
        UIDropDownMenu_SetText(buffDD, s)
        refreshPhrasesArea(db, phrasesBox, s, currentCategory)
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  -- Instruction label (separate so it doesn't overlay text)
  -- Category dropdown for phrases
  local catLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  catLabel:SetPoint("TOPLEFT", buffDD, "BOTTOMLEFT", 0, -10)
  catLabel:SetText("Category")
  local catDD = makeDropdown("OZYB_CatDD", content, 160)
  catDD:SetPoint("TOPLEFT", catLabel, "BOTTOMLEFT", -10, -4)
  UIDropDownMenu_SetWidth(catDD, 140)
  UIDropDownMenu_SetText(catDD, "neutral")
  catDD.tooltipText = "Pick which humor category to view/edit. Save updates only this category."
  UIDropDownMenu_Initialize(catDD, function(self, level)
    local function add(text, val)
      local info = UIDropDownMenu_CreateInfo()
      info.text = text
      info.func = function()
        currentCategory = val
        UIDropDownMenu_SetText(catDD, val)
        if currentSpell then
          refreshPhrasesArea(db, phrasesBox, currentSpell, currentCategory)
        end
      end
      UIDropDownMenu_AddButton(info, level)
    end
    add("neutral", "neutral"); add("snarky", "snarky"); add("spicy", "spicy")
  end)

  local hint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", catDD, "BOTTOMLEFT", 6, -6)
  hint:SetText("One phrase per line. Tokens: %t=target, %s=spell, %c=class")

  -- Scrollable edit box with backdrop behind
  local phraseScroll = CreateFrame("ScrollFrame", "OZYB_PhrasesScroll", content, "UIPanelScrollFrameTemplate")
  phraseScroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -6, -6)
  phraseScroll:SetSize(440, 240)
  local phraseBg = CreateFrame("Frame", nil, content, "TooltipBackdropTemplate")
  phraseBg:SetPoint("TOPLEFT", phraseScroll, -4, 4)
  phraseBg:SetPoint("BOTTOMRIGHT", phraseScroll, 28, -4)
  phraseBg:SetFrameLevel(phraseScroll:GetFrameLevel() - 1)

  phrasesBox = CreateFrame("EditBox", "OZYB_Phrases", phraseScroll)
  phrasesBox:SetMultiLine(true)
  phrasesBox:SetAutoFocus(false)
  phrasesBox:SetFontObject(ChatFontNormal)
  phrasesBox:SetWidth(phraseScroll:GetWidth() - 20)
  phrasesBox:SetTextColor(1, 1, 1)
  phrasesBox:SetJustifyH("LEFT")
  phraseScroll:SetScrollChild(phrasesBox)

  local saveBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  saveBtn:SetPoint("TOPLEFT", phraseScroll, "BOTTOMLEFT", 0, -10)
  saveBtn:SetSize(100, 22)
  saveBtn:SetText("Save")
  saveBtn.tooltipText = "Save editor lines (one per row) to SavedVariables for this buff/category."
  saveBtn:SetScript("OnClick", function()
    if currentSpell then
      savePhrasesFromArea(db, phrasesBox, currentSpell, currentCategory)
      OzyBuffs_SetDB(db)
      OzyBuffs_ResetBags()
      print("OzyBuffs: Saved " .. currentCategory .. " phrases for " .. currentSpell)
      phrasesBox:ClearFocus()
    else
      print("OzyBuffs: Choose a buff first")
    end
  end)

  local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  resetBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
  resetBtn:SetSize(120, 22)
  resetBtn:SetText("Reset to defaults")
  resetBtn.tooltipText = "Delete your saved lines for this buff/category and fall back to file phrases."
  resetBtn:SetScript("OnClick", function()
    if currentSpell then
      if db.phrases[currentSpell] then db.phrases[currentSpell][currentCategory] = nil end
      OzyBuffs_SetDB(db)
      OzyBuffs_ResetBags()
      refreshPhrasesArea(db, phrasesBox, currentSpell, currentCategory)
      print("OzyBuffs: Reset " .. currentCategory .. " phrases for " .. currentSpell)
    end
  end)

  local closeBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  closeBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
  closeBtn:SetSize(90, 22)
  closeBtn:SetText("Close")
  closeBtn.tooltipText = "Close this options window."
  closeBtn:SetScript("OnClick", function()
    if Settings and SettingsPanel and SettingsPanel:IsShown() then
      SettingsPanel:Hide()
    elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
      InterfaceOptionsFrame:Hide()
    end
  end)

  local appendBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  appendBtn:SetPoint("LEFT", closeBtn, "RIGHT", 8, 0)
  appendBtn:SetSize(140, 22)
  appendBtn:SetText("Append defaults")
  appendBtn.tooltipText = "Merge file phrases for this buff/category into the editor (skip duplicates)."
  appendBtn:SetScript("OnClick", function()
    if not currentSpell then print("OzyBuffs: Choose a buff first") return end
    local cur = {}
    for line in (phrasesBox:GetText() or ""):gmatch("[^\n]+") do cur[strtrim(line)] = true end
    local def = {}
    if OZY_USER_PHRASES and OZY_USER_PHRASES[currentSpell] and OZY_USER_PHRASES[currentSpell][currentCategory] then
      def = OZY_USER_PHRASES[currentSpell][currentCategory]
    elseif OZY_PHRASES and OZY_PHRASES[currentSpell] and OZY_PHRASES[currentSpell][currentCategory] then
      def = OZY_PHRASES[currentSpell][currentCategory]
    end
    local out = {}
    for k in pairs(cur) do table.insert(out, k) end
    for _, s in ipairs(def) do if not cur[s] then table.insert(out, s) end end
    table.sort(out)
    phrasesBox:SetText(table.concat(out, "\n"))
  end)

  -- Import/Export controls
  local reloadBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  reloadBtn:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -8)
  reloadBtn:SetSize(160, 22)
  reloadBtn:SetText("Reload phrases from files")
  reloadBtn.tooltipText = "Re-parse Mage/Priest class files. Clears memory phrases first to avoid duplicates."
  reloadBtn:SetScript("OnClick", function()
    -- Re-run loader by re-appending text from class arrays if present
    if OZY_MAGE_LINES or OZY_PRIEST_LINES then
      if OzyBuffs_AppendCSV then
        if OZY_MAGE_LINES then OzyBuffs_AppendCSV(table.concat(OZY_MAGE_LINES, "\n")) end
        if OZY_PRIEST_LINES then OzyBuffs_AppendCSV(table.concat(OZY_PRIEST_LINES, "\n")) end
        OzyBuffs_ResetBags()
        if currentSpell then refreshPhrasesArea(db, phrasesBox, currentSpell, currentCategory) end
        print("OzyBuffs: Reloaded phrases from files")
      end
    else
      print("OzyBuffs: No class phrase files detected")
    end
  end)

  local exportBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  exportBtn:SetPoint("LEFT", reloadBtn, "RIGHT", 8, 0)
  exportBtn:SetSize(140, 22)
  exportBtn:SetText("Export current")
  exportBtn.tooltipText = "Print CSV for this buff/category from current settings to copy back to files."
  -- Footer usage + versions
  local footer = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  footer:SetPoint("TOPLEFT", reloadBtn, "BOTTOMLEFT", 0, -16)
  local phraseVer = (OzyBuffs_GetPhraseFormatVersion and OzyBuffs_GetPhraseFormatVersion()) or 1
  footer:SetJustifyH("LEFT")
  footer:SetText("What it does:\n- Watches your successful Mage/Priest buff casts and posts a randomized saying. No macros needed.\n- Channel AUTO chooses RAID > PARTY > SAY.\n\nEditing phrases:\n- Class files: OzyBuffs_MagePhrases.lua / OzyBuffs_PriestPhrases.lua with CSV lines: spellID,category,phrase.\n- Editor: choose Buff + Category, edit one line per phrase, then Save (stores in SavedVariables; overrides file phrases).\n- Append defaults: merge file phrases into the editor.\n- Reload phrases from files: re-parse class files (clears loaded file phrases first).\n- Export current: prints CSV lines for the selected buff/category to chat for copying back into files.\n\nTokens: %t = target, %s = spell, %c = your class.\nVersions: Phrase format v" .. phraseVer .. "; Addon v" .. (version or "unknown"))

  -- Tooltip handlers for checkboxes
  local function attachTooltip(widget)
    if not widget then return end
    local function addHandlers(frame)
      if not frame then return end
      frame:HookScript("OnEnter", function(self)
        if widget.tooltipText then
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(widget.tooltipText, 1, 1, 1, true)
        end
      end)
      frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    addHandlers(widget)
    addHandlers(widget.Button)
  end
  attachTooltip(disableCities); attachTooltip(onlyGroup); attachTooltip(onlyInstance)
  attachTooltip(skipSelf); attachTooltip(skipNPCs)
  attachTooltip(hNeutral); attachTooltip(hSnarky); attachTooltip(hSpicy)
  attachTooltip(chanDD); attachTooltip(buffDD); attachTooltip(catDD)
  attachTooltip(saveBtn); attachTooltip(resetBtn); attachTooltip(closeBtn)
  attachTooltip(appendBtn); attachTooltip(reloadBtn); attachTooltip(exportBtn)
  exportBtn:SetScript("OnClick", function()
    if not currentSpell then print("OzyBuffs: Choose a buff first") return end
    local cat = currentCategory
    local lines = {}
    local sv = (db.phrases[currentSpell] and db.phrases[currentSpell][cat]) or {}
    for _, s in ipairs(sv) do table.insert(lines, s) end
    if #lines == 0 then
      local seed = (OZY_USER_PHRASES and OZY_USER_PHRASES[currentSpell] and OZY_USER_PHRASES[currentSpell][cat]) or {}
      for _, s in ipairs(seed) do table.insert(lines, s) end
    end
    local spellID = select(7, GetSpellInfo(currentSpell)) or 0
    local out = {}
    -- Produce both CSV and Lua-array styles for convenience
    table.insert(out, "-- CSV (one per line):")
    for _, s in ipairs(lines) do table.insert(out, string.format("%d,%s,%s", spellID, cat, s)) end
    table.insert(out, "\n-- Lua array (paste into class file):")
    for _, s in ipairs(lines) do table.insert(out, string.format("\"%d,%s,\"%s\"\",", spellID, cat, luaEscape(s))) end
    ShowTextPopup("Export for " .. currentSpell .. " [" .. cat .. "]", table.concat(out, "\n"))
  end)

  -- Register options in whichever system exists
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    category.ID = category.ID or panel.name
    settingsCategory = category
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  elseif InterfaceOptionsFrame_AddCategory then
    InterfaceOptionsFrame_AddCategory(panel)
  end
  -- Open immediately after first build
  if Settings and Settings.OpenToCategory and settingsCategory then
    Settings.OpenToCategory(settingsCategory.ID or settingsCategory)
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end

function OzyBuffs_OpenOptions()
  OpenOptions()
end



-- Author: Ozy

local ADDON_NAME = ...

local OzyBuffs = CreateFrame("Frame", ADDON_NAME)
OzyBuffs:RegisterEvent("ADDON_LOADED")
OzyBuffs:RegisterEvent("PLAYER_LOGIN")
OzyBuffs:RegisterEvent("PLAYER_LOGOUT")
OzyBuffs:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
OzyBuffs:RegisterEvent("UNIT_SPELLCAST_SENT")

local CLASS_MAGE = "MAGE"
local CLASS_PRIEST = "PRIEST"
local PHRASE_FORMAT_VERSION = 1

local DEFAULTS = {
  profile = {
    usePerCharacter = false,
    channel = "AUTO", -- AUTO|SAY|PARTY|RAID|YELL|EMOTE
    restrictions = {
      disableInCities = false,
      onlyInGroup = false,
      onlyInInstance = false,
      skipSelf = false,
      skipNPCs = true,
    },
    humor = {
      neutral = true,
      snarky = true,
      spicy = false,
    },
    throttle = {
      globalMinSeconds = 0,
      perTargetMinSeconds = 0,
      enabled = false,
    },
    rotation = {
      persistAcrossSessions = true,
    },
    buffsEnabled = {}, -- per-spell toggles
    phrases = {}, -- per-spell phrase overrides by category
    aliases = {},
  }
}

OZY_DEFAULT_ALIASES = {
  -- Mage
  ["ai"] = "Arcane Intellect",
  ["int"] = "Arcane Intellect",
  ["brilliance"] = "Arcane Brilliance",
  ["ab"] = "Arcane Brilliance",
  ["amp"] = "Amplify Magic",
  ["damp"] = "Dampen Magic",
  -- Priest
  ["fort"] = "Power Word: Fortitude",
  ["pwf"] = "Power Word: Fortitude",
  ["pof"] = "Prayer of Fortitude",
  ["spirit"] = "Divine Spirit",
  ["ds"] = "Divine Spirit",
  ["pos"] = "Prayer of Spirit",
  ["shadow"] = "Shadow Protection",
  ["sp"] = "Shadow Protection",
  ["posp"] = "Prayer of Shadow Protection",
}

-- Spell lists per class (friendly buffs only)
local CLASS_SPELLS = {
  [CLASS_MAGE] = {
    "Arcane Intellect",
    "Arcane Brilliance",
    "Amplify Magic",
    "Dampen Magic",
  },
  [CLASS_PRIEST] = {
    "Power Word: Fortitude",
    "Prayer of Fortitude",
    "Divine Spirit",
    "Prayer of Spirit",
    "Shadow Protection",
    "Prayer of Shadow Protection",
  },
}

local function deepcopy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local out = {}
  for k, v in pairs(tbl) do
    out[k] = deepcopy(v)
  end
  return out
end

local function tableShallowCopy(src)
  local t = {}
  for k, v in pairs(src) do t[k] = v end
  return t
end

local function classIsSupported()
  local _, class = UnitClass("player")
  return class == CLASS_MAGE or class == CLASS_PRIEST
end

local function getDB()
  if not OzyBuffsDB then OzyBuffsDB = {} end
  -- Account wide root
  if not OzyBuffsDB.account then OzyBuffsDB.account = deepcopy(DEFAULTS.profile) end
  local charKey = UnitName("player") .. "-" .. (GetRealmName() or "")
  if not OzyBuffsDB.chars then OzyBuffsDB.chars = {} end
  if not OzyBuffsDB.chars[charKey] then
    OzyBuffsDB.chars[charKey] = deepcopy(DEFAULTS.profile)
  end
  local profile = OzyBuffsDB.account.usePerCharacter and OzyBuffsDB.chars[charKey] or OzyBuffsDB.account
  -- Seed aliases if empty
  if not profile.aliases or next(profile.aliases) == nil then
    profile.aliases = tableShallowCopy(OZY_DEFAULT_ALIASES)
  end
  return profile
end

local function saveDB(profile)
  if not OzyBuffsDB then return end
  local charKey = UnitName("player") .. "-" .. (GetRealmName() or "")
  if OzyBuffsDB.account.usePerCharacter then
    OzyBuffsDB.chars[charKey] = profile
  else
    OzyBuffsDB.account = profile
  end
end

local function isStringNonEmpty(s)
  return type(s) == "string" and s:len() > 0
end

local function formatMessage(template, spellName, targetName)
  if not isStringNonEmpty(template) then return nil end
  local _, class = UnitClass("player")
  local m = template
  m = m:gsub("%%t", targetName or "you")
  m = m:gsub("%%s", spellName or "")
  m = m:gsub("%%c", class or "")
  return m
end

local function inGroup()
  return IsInGroup() or IsInRaid()
end

local function inInstance()
  local inInst = IsInInstance()
  return inInst
end

local function inCity()
  -- Classic-compatible: treat resting areas as cities (approximation)
  return IsResting()
end

local function pickChatChannel(profile)
  if profile.channel ~= "AUTO" then return profile.channel end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return "SAY"
end

local randomState = math.random
local function shuffle(t)
  if not t or #t < 2 then return end
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

local rotationState = {
  perSpellBag = {}, -- spellName -> { bag = {lines}, index = 1 }
  lastSaidForTarget = {}, -- fullName -> time
  lastGlobalSayTime = 0,
}

-- Track sent cast targets to pair with SUCCEEDED
local sentTargets = {
  -- key: castGUID if available, else spellID; value: targetName
}

local function buildPhrasePoolForSpell(profile, spellName)
  -- Source phrases exclusively from user-provided tables (class files) and SavedVariables overrides
  local seed = { neutral = {}, snarky = {}, spicy = {} }
  if OZY_USER_PHRASES and OZY_USER_PHRASES[spellName] then
    local up = OZY_USER_PHRASES[spellName]
    seed.neutral = type(up.neutral) == "table" and up.neutral or {}
    seed.snarky  = type(up.snarky)  == "table" and up.snarky  or {}
    seed.spicy   = type(up.spicy)   == "table" and up.spicy   or {}
  end
  local overrides = profile.phrases and profile.phrases[spellName] or {}

  local function mergeCategory(cat)
    local pool = {}
    if profile.humor[cat] then
      if type(seed[cat]) == "table" then for _, s in ipairs(seed[cat]) do table.insert(pool, s) end end
      if type(overrides[cat]) == "table" then for _, s in ipairs(overrides[cat]) do if isStringNonEmpty(s) then table.insert(pool, s) end end end
    end
    return pool
  end

  local merged = {}
  for _, cat in ipairs({"neutral", "snarky", "spicy"}) do
    local pool = mergeCategory(cat)
    for _, s in ipairs(pool) do table.insert(merged, s) end
  end
  return merged
end

local function getBagForSpell(profile, spellName)
  if not rotationState.perSpellBag[spellName] then
    local pool = buildPhrasePoolForSpell(profile, spellName)
    if not pool or #pool == 0 then
      pool = {"%s on %t!"}
    end
    rotationState.perSpellBag[spellName] = { bag = pool, index = 1 }
    shuffle(rotationState.perSpellBag[spellName].bag)
  end
  local bag = rotationState.perSpellBag[spellName]
  if not bag or not bag.bag or #bag.bag == 0 then
    rotationState.perSpellBag[spellName] = { bag = {"%s on %t!"}, index = 1 }
  end
  return rotationState.perSpellBag[spellName]
end

local function nextPhrase(profile, spellName)
  local bag = getBagForSpell(profile, spellName)
  if bag.index > #bag.bag then
    shuffle(bag.bag)
    bag.index = 1
  end
  local phrase = bag.bag[bag.index]
  if not phrase then
    return "%s on %t!"
  end
  bag.index = bag.index + 1
  return phrase
end

local function canSay(profile, targetFullName)
  if profile.restrictions.disableInCities and inCity() then return false end
  if profile.restrictions.onlyInGroup and not inGroup() then return false end
  if profile.restrictions.onlyInInstance and not inInstance() then return false end

  if profile.throttle.enabled then
    local now = GetTime()
    if profile.throttle.globalMinSeconds and profile.throttle.globalMinSeconds > 0 then
      if now - (rotationState.lastGlobalSayTime or 0) < profile.throttle.globalMinSeconds then return false end
    end
    if profile.throttle.perTargetMinSeconds and profile.throttle.perTargetMinSeconds > 0 and targetFullName then
      local last = rotationState.lastSaidForTarget[targetFullName] or 0
      if now - last < profile.throttle.perTargetMinSeconds then return false end
    end
  end
  return true
end

local function markSaid(profile, targetFullName)
  rotationState.lastGlobalSayTime = GetTime()
  if targetFullName then rotationState.lastSaidForTarget[targetFullName] = GetTime() end
end

local function fullNameForUnit(unit)
  local name, realm = UnitName(unit)
  if not name then return nil end
  if realm and realm ~= "" then return name .. "-" .. realm end
  local myRealm = GetRealmName() or ""
  return name .. (myRealm ~= "" and ("-" .. myRealm) or "")
end

local function unitIsPlayer(unit)
  return UnitIsPlayer(unit)
end

local function resolveSpellFromInput(input)
  if not isStringNonEmpty(input) then return nil end
  local profile = getDB()
  local alias = profile.aliases[strlower(input)] or profile.aliases[input]
  if alias then return alias end
  return input
end

local function postSaying(profile, spellName, targetName)
  if not targetName then targetName = UnitName("target") or UnitName("player") end
  local targetFull = targetName
  if not canSay(profile, targetFull) then return end
  local phrase = nextPhrase(profile, spellName)
  local msg = formatMessage(phrase, spellName, targetName)
  if not isStringNonEmpty(msg) then return end

  local chan = pickChatChannel(profile)
  SendChatMessage(msg, chan)
  markSaid(profile, targetFull)
end

local function handleMacroInvocation(args)
  local profile = getDB()
  local input = strtrim(args or "")
  if input == "" then
    if OzyBuffs_OpenOptions then OzyBuffs_OpenOptions() end
    return
  end
  if input == "options" then
    if OzyBuffs_OpenOptions then OzyBuffs_OpenOptions() end
    return
  end
  if input == "list" then
    print("OzyBuffs buffs:")
    local _, class = UnitClass("player")
    for _, n in ipairs(CLASS_SPELLS[class] or {}) do print(" - " .. n) end
    return
  end
  if input:find("^test ") then
    local testSpell = strtrim(input:sub(6))
    local resolved = resolveSpellFromInput(testSpell)
    local targetName = (UnitName("target")) or UnitName("player")
    local phrase = nextPhrase(profile, resolved)
    local msg = formatMessage(phrase, resolved, targetName)
    print("OzyBuffs [preview]: " .. (msg or ""))
    return
  end
  -- Inform user that macro casting is not used
  print("OzyBuffs: No macro needed. Just cast your buff; sayings will trigger automatically. Use '/ob test <buff>' to preview. '/ob options' opens settings.")
end

SlashCmdList["OZYBUFFS"] = handleMacroInvocation
SLASH_OZYBUFFS1 = "/ozybuffs"
SLASH_OZYBUFFS2 = "/ob"

function OzyBuffs:OnAddonLoaded(name)
  if name ~= ADDON_NAME then return end
  -- Warm DB
  local profile = getDB()
  -- Load class phrase files now that all addon files are loaded
  if OZY_MAGE_LINES then
    if OzyBuffs_AppendCSV then OzyBuffs_AppendCSV(table.concat(OZY_MAGE_LINES, "\n")) end
  end
  if OZY_PRIEST_LINES then
    if OzyBuffs_AppendCSV then OzyBuffs_AppendCSV(table.concat(OZY_PRIEST_LINES, "\n")) end
  end
  -- ensure per-class buffs list exists for toggles
  local _, class = UnitClass("player")
  for _, s in ipairs(CLASS_SPELLS[class] or {}) do
    if profile.buffsEnabled[s] == nil then profile.buffsEnabled[s] = true end
  end
  -- If this is a fresh install (no overrides saved), and class files provided phrases,
  -- keep them as defaults via OZY_USER_PHRASES. Editor will show them until user saves.
  -- Additionally, seed a minimal fallback if class files are missing
  if not OZY_USER_PHRASES or next(OZY_USER_PHRASES) == nil then
    OZY_USER_PHRASES = OZY_USER_PHRASES or {}
    for _, spell in ipairs(CLASS_SPELLS[class] or {}) do
      OZY_USER_PHRASES[spell] = OZY_USER_PHRASES[spell] or { neutral = {"%s on %t!"}, snarky = {}, spicy = {} }
    end
  end
end

function OzyBuffs:OnLogin()
  local version = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or nil
  if not version or version == "" then version = "unknown" end
  print("OzyBuffs v" .. version .. " initialized. Type /ob options to configure.")
end

function OzyBuffs:OnLogout()
  -- DB is persisted automatically
end

function OzyBuffs:OnSpellSucceeded(unit, castGUID, spellID)
  local profile = getDB()
  if unit ~= "player" then return end
  local spellName = GetSpellInfo(spellID)
  if not spellName then return end
  local _, class = UnitClass("player")
  local list = CLASS_SPELLS[class] or {}
  local tracked = false
  for _, n in ipairs(list) do if n == spellName then tracked = true break end end
  if not tracked then return end
  local key = castGUID or spellID
  local targetName = sentTargets[key] or UnitName("target") or UnitName("player")
  sentTargets[key] = nil
  postSaying(profile, spellName, targetName)
end

OzyBuffs:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then self:OnAddonLoaded(...)
  elseif event == "PLAYER_LOGIN" then self:OnLogin(...)
  elseif event == "PLAYER_LOGOUT" then self:OnLogout(...)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then self:OnSpellSucceeded(...)
  elseif event == "UNIT_SPELLCAST_SENT" then
    local unit, castGUID, spellID, spellName, spellRank, targetName = ...
    if unit == "player" then
      local name = targetName or (UnitExists("target") and UnitName("target")) or UnitName("player")
      local key = castGUID or spellID
      sentTargets[key] = name
    end
  end
end)

-- Loader helpers for per-class CSV-like phrase files
local function parseAndAppendFile(lines)
  if not lines then return end
  local buffer = table.concat(lines, "\n")
  if OzyBuffs_AppendCSV then OzyBuffs_AppendCSV(buffer) end
end

-- Moved class phrase loading to OnAddonLoaded so files are present

-- Expose for options UI
function OzyBuffs_GetVersion()
  local version = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or nil
  return (version and version ~= "" and version) or "unknown"
end
function OzyBuffs_GetPhraseFormatVersion()
  return PHRASE_FORMAT_VERSION
end

-- Public API for options panel
function OzyBuffs_GetDB()
  return getDB()
end

function OzyBuffs_SetDB(profile)
  saveDB(profile)
end

function OzyBuffs_ResetBags()
  rotationState.perSpellBag = {}
end

function OzyBuffs_ListAliases()
  local profile = getDB()
  return profile.aliases
end



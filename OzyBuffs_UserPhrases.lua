-- Author: Ozy

-- Optional user-editable phrases file.
-- You can edit this file to add/override phrases without touching addon code.
-- Structure mirrors OZY_PHRASES: OZY_USER_PHRASES[spell][category] = { "...", ... }

OZY_USER_PHRASES = OZY_USER_PHRASES or {}

-- Append phrases from a simple CSV-like text blob with lines formatted as:
--   spellID,category,phrase
-- - spellID: numeric SpellID (any rank is fine; we resolve to spell name)
-- - category: neutral|snarky|spicy (case-insensitive; accepts n|s|sp)
-- - phrase: the remaining text (commas allowed)
function OzyBuffs_AppendCSV(csvText)
  if type(csvText) ~= "string" then return end
  for line in csvText:gmatch("([^\n\r]+)") do
    local trimmed = strtrim(line)
    if trimmed ~= "" and not trimmed:match("^#") then
      local idStr, cat, phrase = trimmed:match("^%s*(%d+)%s*,%s*([%a]+)%s*,%s*(.+)$")
      if idStr and cat and phrase then
        local spellID = tonumber(idStr)
        local spellName = GetSpellInfo(spellID)
        if spellName then
          local key = strlower(cat)
          if key == "n" then key = "neutral" end
          if key == "s" then key = "snarky" end
          if key == "sp" then key = "spicy" end
          if key == "neutral" or key == "snarky" or key == "spicy" then
            OZY_USER_PHRASES[spellName] = OZY_USER_PHRASES[spellName] or { neutral = {}, snarky = {}, spicy = {} }
            table.insert(OZY_USER_PHRASES[spellName][key], phrase)
          end
        end
      end
    end
  end
end

-- Example structure (uncomment and edit as desired):
-- OZY_USER_PHRASES["Arcane Intellect"] = {
--   neutral = {
--     "%s for %t. Example user line 1.",
--     "%s for %t. Example user line 2.",
--   },
--   snarky = {
--   },
--   spicy = {
--   },
-- }



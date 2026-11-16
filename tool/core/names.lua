--[[
  names.lua

  Pure Lua string helpers (no Renoise API calls): vendor splitting, plugin
  format detection, name normalization used to match installed plugins with
  catalog entries, and text folding used by the search.
]]

local M = {}

-- UTF-8 accented letters folded to their ASCII base letter.
local ACCENTS = {
  ["à"] = "a", ["á"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["å"] = "a",
  ["ç"] = "c", ["è"] = "e", ["é"] = "e", ["ê"] = "e", ["ë"] = "e",
  ["ì"] = "i", ["í"] = "i", ["î"] = "i", ["ï"] = "i", ["ñ"] = "n",
  ["ò"] = "o", ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["ø"] = "o",
  ["ù"] = "u", ["ú"] = "u", ["û"] = "u", ["ü"] = "u", ["ý"] = "y", ["ÿ"] = "y",
  ["À"] = "a", ["Á"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a", ["Å"] = "a",
  ["Ç"] = "c", ["È"] = "e", ["É"] = "e", ["Ê"] = "e", ["Ë"] = "e",
  ["Ì"] = "i", ["Í"] = "i", ["Î"] = "i", ["Ï"] = "i", ["Ñ"] = "n",
  ["Ò"] = "o", ["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o", ["Ø"] = "o",
  ["Ù"] = "u", ["Ú"] = "u", ["Û"] = "u", ["Ü"] = "u", ["Ý"] = "y",
}

function M.trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Lower case, accents removed. Used for case and accent insensitive search.
function M.fold(s)
  s = tostring(s or "")
  s = s:gsub("[\195][\128-\191]", function(char)
    return ACCENTS[char] or char
  end)
  return s:lower()
end

-- Split a Renoise display name "Vendor: Plugin" into its two parts.
-- Names without ": " have an empty vendor.
function M.split_vendor(name)
  name = tostring(name or "")
  local pos = name:find(": ", 1, true)
  if not pos then
    return "", M.trim(name)
  end
  return M.trim(name:sub(1, pos - 1)), M.trim(name:sub(pos + 2))
end

-- Plugin format from a device path such as "Audio/Effects/VST3/<id>".
-- Only the directory segments are inspected, never the plugin id itself.
-- Returns "VST3", "VST" or nil for anything else (native devices, AU...).
function M.format_of(path)
  if type(path) ~= "string" then
    return nil
  end
  local segments = {}
  for segment in path:gmatch("[^/]+") do
    segments[#segments + 1] = segment
  end
  for i = 1, #segments - 1 do
    local s = segments[i]:upper()
    if s == "VST3" then
      return "VST3"
    elseif s == "VST" or s == "VST2" then
      return "VST"
    end
  end
  return nil
end

-- Channel layout words that plugin vendors append to the plugin name.
local CHANNEL_WORDS = { "mono", "stereo", "dual", "mono/stereo", "m/s", "surround" }

local function strip_trailing_word(s, word)
  local suffix = " " .. word
  if #s > #suffix and s:sub(-#suffix) == suffix then
    return M.trim(s:sub(1, -#suffix - 1)), true
  end
  return s, false
end

--[[
  Normalized plugin name, used as the matching key between an installed
  plugin and a catalog entry. Removes what varies between builds of the
  same plugin: letter case, accents, channel layout ("(Stereo)", "Mono"),
  format markers ("VST3", "x64") and a trailing version ("2", "v2").

    "Blue Cat's Chorus 4 (Stereo)"   -> "blue cat's chorus"
    "RC-20 Retro Color v2"           -> "rc-20 retro color"
    "Aphex Vintage Exciter Stereo"   -> "aphex vintage exciter"
    "API 2500 Stereo"                -> "api 2500"
]]
function M.normalize(name)
  local s = M.fold(name)
  s = s:gsub("%c", " ")
  -- Parenthesized or bracketed qualifiers.
  s = s:gsub("%b()", " "):gsub("%b[]", " ")
  s = M.trim(s:gsub("%s+", " "))

  local changed = true
  while changed do
    changed = false
    local stripped
    for _, word in ipairs(CHANNEL_WORDS) do
      s, stripped = strip_trailing_word(s, word)
      changed = changed or stripped
    end
    for _, word in ipairs({ "vst3", "vst2", "vst", "x64", "64bit", "64-bit" }) do
      s, stripped = strip_trailing_word(s, word)
      changed = changed or stripped
    end
    -- Trailing version: " 2", " 11", " v2", " v2.1", " 2.5". Kept when nothing
    -- else remains. A plain number of three digits or more is a model number
    -- ("API 2500", "dbx 160"), not a version, and is kept.
    local base = s:match("^(.-)%s+v%d+[%d%.]*$")
      or s:match("^(.-)%s+%d%d?$")
      or s:match("^(.-)%s+%d+%.[%d%.]+$")
    if base and base ~= "" then
      s = M.trim(base)
      changed = true
    end
  end
  return s
end

-- Stable identifier shared by all builds of one plugin (VST and VST3, mono
-- and stereo). User data (notes, ratings, usage) is stored under this id.
function M.plugin_id(vendor, plugin_name)
  return M.fold(M.trim(vendor)) .. "|" .. M.normalize(plugin_name)
end

-- Make a string safe to use as one level of a Renoise menu path.
-- ":" separates menu levels, "/" and "\" may be read as path separators,
-- and leading dashes would turn the entry into a separator.
function M.sanitize_menu(s)
  s = tostring(s or "")
  s = s:gsub("%c", " ")
  s = s:gsub("[:/\\]", "-")
  s = s:gsub("%s+", " ")
  s = M.trim(s)
  s = s:gsub("^[-%s]+", "")
  if s == "" then
    s = "Unnamed"
  end
  return s
end

-- Alphabetical order ignoring case and accents, exact order as a tie-break.
function M.less(x, y)
  local fx, fy = M.fold(x), M.fold(y)
  if fx ~= fy then
    return fx < fy
  end
  return x < y
end

return M

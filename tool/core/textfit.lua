--[[
  textfit.lua

  Pure Lua text shortening (no Renoise API calls).

  Renoise text and button views grow to fit their text and never shrink
  back, which breaks the column alignment of the browser list. The browser
  therefore shortens every text to the width of its column before showing
  it, and puts the full text in a tooltip.

  Renoise gives scripts no way to measure text, so widths are estimated
  from character classes, in view units (before Renoise's GUI scaling).
  The estimates were calibrated on screenshots of Renoise 3.5 and err on
  the wide side, so that an estimated fit really fits.
]]

local M = {}

M.ELLIPSIS = "..."

-- Estimated advance of one character, in view units, for the normal font.
local NARROW = 3.0   -- i j l ! | . , : ; ' space
local LOWER = 5.6    -- most lower case letters
local WIDE_LOWER = 8.0 -- m w
local UPPER = 7.0    -- upper case letters and digits
local WIDE_UPPER = 9.0 -- M W

-- 4 % of safety margin on top of the calibrated values.
local FONT_FACTOR = { normal = 1.04, bold = 1.16, big = 1.2 }

local function char_width(c)
  if c:find("^[ijl!|%.,:;' ]$") then
    return NARROW
  elseif c == "m" or c == "w" then
    return WIDE_LOWER
  elseif c == "M" or c == "W" then
    return WIDE_UPPER
  elseif c:find("^[%u%d]$") then
    return UPPER
  end
  -- Other lower case letters, punctuation and multi-byte characters.
  return LOWER
end

-- Iterate over UTF-8 characters.
local function chars(text)
  return text:gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

-- Estimated width of a text, in view units.
function M.width(text, font)
  local factor = FONT_FACTOR[font or "normal"] or 1.04
  local total = 0
  for c in chars(tostring(text or "")) do
    total = total + char_width(c)
  end
  return total * factor
end

--[[
  Returns the text, shortened with "..." so that its estimated width fits
  in max_width view units, and whether it was shortened.
]]
function M.fit(text, max_width, font)
  text = tostring(text or "")
  if M.width(text, font) <= max_width then
    return text, false
  end
  local budget = max_width - M.width(M.ELLIPSIS, font)
  local factor = FONT_FACTOR[font or "normal"] or 1.04
  local parts, used = {}, 0
  for c in chars(text) do
    local w = char_width(c) * factor
    if used + w > budget then
      break
    end
    parts[#parts + 1] = c
    used = used + w
  end
  local shortened = table.concat(parts):gsub("[%s%p]+$", "")
  return shortened .. M.ELLIPSIS, true
end

return M

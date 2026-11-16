--[[
  json.lua

  Small JSON encoder and decoder in pure Lua, used for the user data file
  and for export and import. Data is parsed, never executed.

  Lua tables with consecutive integer keys starting at 1 are written as
  arrays, all other tables as objects with sorted keys. An empty table is
  written as an empty object.
]]

local M = {}

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encode_string(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ESCAPES[c] or ("\\u%04x"):format(c:byte())
  end) .. '"'
end

local function is_array(t)
  local n = #t
  if n == 0 then
    return false
  end
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count == n
end

local function encode_value(value, indent, out)
  local kind = type(value)
  if kind == "nil" then
    out[#out + 1] = "null"
  elseif kind == "boolean" then
    out[#out + 1] = value and "true" or "false"
  elseif kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("cannot encode a non-finite number")
    end
    if value == math.floor(value) and math.abs(value) < 1e15 then
      out[#out + 1] = ("%d"):format(value)
    else
      out[#out + 1] = ("%.14g"):format(value)
    end
  elseif kind == "string" then
    out[#out + 1] = encode_string(value)
  elseif kind == "table" then
    local inner = indent .. "  "
    if is_array(value) then
      out[#out + 1] = "["
      for i, item in ipairs(value) do
        out[#out + 1] = (i > 1 and ",\n" or "\n") .. inner
        encode_value(item, inner, out)
      end
      out[#out + 1] = "\n" .. indent .. "]"
    else
      local keys = {}
      for key in pairs(value) do
        if type(key) ~= "string" then
          error("cannot encode a table with mixed or non-string keys")
        end
        keys[#keys + 1] = key
      end
      if #keys == 0 then
        out[#out + 1] = "{}"
        return
      end
      table.sort(keys)
      out[#out + 1] = "{"
      for i, key in ipairs(keys) do
        out[#out + 1] = (i > 1 and ",\n" or "\n") .. inner .. encode_string(key) .. ": "
        encode_value(value[key], inner, out)
      end
      out[#out + 1] = "\n" .. indent .. "}"
    end
  else
    error("cannot encode a value of type " .. kind)
  end
end

-- Returns the JSON text for a value. Raises an error on unsupported values.
function M.encode(value)
  local out = {}
  encode_value(value, "", out)
  return table.concat(out) .. "\n"
end

--------------------------------------------------------------------------------
-- Decoder

local function utf8_char(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
  end
  return string.char(0xE0 + math.floor(code / 0x1000),
    0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local UNESCAPES = {
  ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f",
  n = "\n", r = "\r", t = "\t",
}

local MAX_DEPTH = 32

local function fail(text, pos, message)
  error(("invalid JSON at character %d: %s"):format(pos, message), 0)
end

local function skip_space(text, pos)
  return text:find("[^ \t\r\n]", pos) or (#text + 1)
end

local decode_value

local function decode_string(text, pos)
  -- pos is the position of the opening quote.
  local parts = {}
  local i = pos + 1
  while true do
    local stop = text:find('["\\]', i)
    if not stop then
      fail(text, pos, "unterminated string")
    end
    parts[#parts + 1] = text:sub(i, stop - 1)
    if text:sub(stop, stop) == '"' then
      return table.concat(parts), stop + 1
    end
    local escape = text:sub(stop + 1, stop + 1)
    if escape == "u" then
      local hex = text:match("^%x%x%x%x", stop + 2)
      if not hex then
        fail(text, stop, "invalid unicode escape")
      end
      parts[#parts + 1] = utf8_char(tonumber(hex, 16))
      i = stop + 6
    elseif UNESCAPES[escape] then
      parts[#parts + 1] = UNESCAPES[escape]
      i = stop + 2
    else
      fail(text, stop, "invalid escape sequence")
    end
  end
end

decode_value = function(text, pos, depth)
  if depth > MAX_DEPTH then
    fail(text, pos, "nesting is too deep")
  end
  pos = skip_space(text, pos)
  local c = text:sub(pos, pos)

  if c == "{" then
    local object = {}
    pos = skip_space(text, pos + 1)
    if text:sub(pos, pos) == "}" then
      return object, pos + 1
    end
    while true do
      pos = skip_space(text, pos)
      if text:sub(pos, pos) ~= '"' then
        fail(text, pos, "expected a string key")
      end
      local key
      key, pos = decode_string(text, pos)
      pos = skip_space(text, pos)
      if text:sub(pos, pos) ~= ":" then
        fail(text, pos, "expected ':'")
      end
      object[key], pos = decode_value(text, pos + 1, depth + 1)
      pos = skip_space(text, pos)
      local sep = text:sub(pos, pos)
      if sep == "}" then
        return object, pos + 1
      elseif sep ~= "," then
        fail(text, pos, "expected ',' or '}'")
      end
      pos = pos + 1
    end
  elseif c == "[" then
    local array = {}
    pos = skip_space(text, pos + 1)
    if text:sub(pos, pos) == "]" then
      return array, pos + 1
    end
    while true do
      array[#array + 1], pos = decode_value(text, pos, depth + 1)
      pos = skip_space(text, pos)
      local sep = text:sub(pos, pos)
      if sep == "]" then
        return array, pos + 1
      elseif sep ~= "," then
        fail(text, pos, "expected ',' or ']'")
      end
      pos = pos + 1
    end
  elseif c == '"' then
    return decode_string(text, pos)
  elseif text:sub(pos, pos + 3) == "true" then
    return true, pos + 4
  elseif text:sub(pos, pos + 4) == "false" then
    return false, pos + 5
  elseif text:sub(pos, pos + 3) == "null" then
    return nil, pos + 4
  else
    local number = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    local value = number and tonumber(number)
    if not value then
      fail(text, pos, "unexpected character")
    end
    return value, pos + #number
  end
end

-- Returns the decoded value, or nil and an error message.
function M.decode(text)
  if type(text) ~= "string" then
    return nil, "invalid JSON: not a string"
  end
  local ok, value, pos = pcall(decode_value, text, 1, 1)
  if not ok then
    return nil, tostring(value)
  end
  if skip_space(text, pos) <= #text then
    return nil, ("invalid JSON at character %d: unexpected trailing text"):format(pos)
  end
  return value
end

return M

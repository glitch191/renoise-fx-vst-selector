--[[
  storage.lua

  Reads and writes the user data file (edits, notes, ratings, usage) and
  handles export and import. Uses only io and os, so it can be tested
  outside of Renoise.

  The data file lives outside the tool bundle, in
    <Renoise configuration folder>/<tool id>/userdata.json
  so that it survives tool updates and Renoise upgrades (the Renoise
  configuration folder is the parent of the versioned "V3.x.x" folders).
]]

local json = require("core.json")
local merge = require("core.merge")

local M = {}

M.FILE_NAME = "userdata.json"

local function split_path(path)
  local parts = {}
  for part in path:gmatch("[^/\\]+") do
    parts[#parts + 1] = part
  end
  return parts
end

--[[
  Derive the data folder from the tool bundle path, which looks like
    <config>/V3.5.4/Scripts/Tools/<tool id>.xrnx/
  Returns <config>/<tool id>/ with the bundle's own separator, or nil when
  the bundle is not installed in the usual place.
]]
function M.data_dir_from_bundle(bundle_path, tool_id)
  if type(bundle_path) ~= "string" or bundle_path == "" then
    return nil
  end
  local separator = bundle_path:find("\\", 1, true) and "\\" or "/"
  local parts = split_path(bundle_path)
  local n = #parts
  if n < 5 or parts[n - 1] ~= "Tools" or parts[n - 2] ~= "Scripts" then
    return nil
  end
  -- Keep everything before the versioned folder.
  local last = n - 4
  local head = table.concat(parts, separator, 1, last)
  if bundle_path:sub(1, 1) == "/" then
    head = "/" .. head
  elseif bundle_path:sub(1, 2) == "\\\\" then
    head = "\\\\" .. head
  end
  return head .. separator .. tool_id .. separator
end

local function file_exists(path)
  if io.exists then
    return io.exists(path)
  end
  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end
  return false
end

local function read_file(path)
  local file, err = io.open(path, "rb")
  if not file then
    return nil, err
  end
  local text = file:read("*a")
  file:close()
  return text
end

local function write_file(path, text)
  local file, err = io.open(path, "wb")
  if not file then
    return false, err
  end
  file:write(text)
  file:close()
  return true
end

-- Choose where the data file lives. Falls back to the bundle folder when
-- the configuration folder cannot be found or created.
function M.init(bundle_path, tool_id)
  local dir = M.data_dir_from_bundle(bundle_path, tool_id)
  if dir then
    if not file_exists(dir) and os.mkdir then
      pcall(os.mkdir, dir)
    end
    local probe = dir .. M.FILE_NAME
    if not file_exists(probe) then
      -- Check that the folder is writable before committing to it.
      local ok = write_file(probe, json.encode(merge.new_user_data()))
      if not ok then
        dir = nil
      end
    end
  end
  M.dir = dir or bundle_path
  M.path = M.dir .. M.FILE_NAME
  return M.path
end

-- Decode and validate user data text. Returns data, or nil and a message.
function M.parse(text)
  local decoded, err = json.decode(text)
  if decoded == nil then
    return nil, err or "the file is empty"
  end
  return merge.sanitize_user(decoded)
end

--[[
  Load the user data. Never raises. Returns data and an optional warning.
  A file that cannot be read as valid data is set aside under a new name
  and fresh data is returned.
]]
function M.load()
  if not file_exists(M.path) then
    return merge.new_user_data()
  end
  local text, read_err = read_file(M.path)
  local data, err
  if text then
    data, err = M.parse(text)
  else
    err = read_err
  end
  if data then
    return data
  end

  local backup = M.dir .. "userdata.corrupt-" .. os.date("%Y%m%d-%H%M%S") .. ".json"
  local moved = os.rename(M.path, backup)
  local warning = ("The data file could not be read (%s). "):format(tostring(err))
  if moved then
    warning = warning .. "It was set aside as " .. backup .. " and the tool restarted from the catalog."
  else
    warning = warning .. "The tool restarted from the catalog."
  end
  return merge.new_user_data(), warning
end

-- Save the user data. Returns true, or false and a message.
function M.save(data)
  local ok, text = pcall(json.encode, data)
  if not ok then
    return false, tostring(text)
  end
  return write_file(M.path, text)
end

-- Write the user data to a file chosen by the user.
function M.export(data, path)
  local ok, text = pcall(json.encode, data)
  if not ok then
    return false, tostring(text)
  end
  return write_file(path, text)
end

-- Read user data from a file chosen by the user. Returns data, or nil and
-- a message. The current data is left untouched.
function M.import(path)
  local text, err = read_file(path)
  if not text then
    return nil, tostring(err)
  end
  return M.parse(text)
end

return M

--[[
  devices.lua

  The two places where the tool talks to the song: listing the effect
  devices Renoise offers for the selected track, and inserting one.
]]

local M = {}

-- Returns the raw available_device_infos list of the selected track, or nil
-- and a message when no song is loaded yet.
function M.fetch_infos()
  local ok, result = pcall(function()
    return renoise.song().selected_track.available_device_infos
  end)
  if not ok then
    return nil, tostring(result)
  end
  return result or {}
end

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

--[[
  Insert the plugin of a record in the DSP chain of the selected track,
  right after the selected device, or at the end of the chain when no
  device is selected. Never before the mixer device at position 1. The new
  device becomes the selected device.

  options (optional):
    at_end       always insert at the end of the chain
    open_editor  open the plugin's editor window after inserting

  Returns true, or false and a message. Never raises.
]]
function M.insert(record, options)
  options = options or {}
  local ok, result, message = pcall(function()
    local song = renoise.song()
    local track = song.selected_track
    local available = track.available_devices

    -- Use the preferred build, or the other one when it is not available.
    local path = nil
    if contains(available, record.path) then
      path = record.path
    else
      for _, other in pairs(record.paths) do
        if contains(available, other) then
          path = other
          break
        end
      end
    end
    if not path then
      return false, ("'%s' is no longer available. Use Rescan Plugins to refresh the list.")
        :format(record.name)
    end

    local device_count = #track.devices
    local selected = song.selected_track_device_index or 0
    local index
    if not options.at_end and selected >= 1 and selected <= device_count then
      index = selected + 1
    else
      index = device_count + 1
    end
    if index < 2 then
      index = 2
    end

    song:describe_undo("Insert " .. record.name)
    local device = track:insert_device_at(path, index)
    -- Selecting can fail when the DSP chain is not the visible one.
    pcall(function()
      song.selected_track_device_index = index
    end)
    if options.open_editor and device then
      -- Renoise shows a generic editor for plugins without their own GUI.
      pcall(function()
        device.external_editor_visible = true
      end)
    end
    return true
  end)

  if not ok then
    return false, ("Could not insert '%s': %s"):format(record.name, tostring(result))
  end
  return result, message
end

return M

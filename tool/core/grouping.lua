--[[
  grouping.lua

  Pure Lua logic (no Renoise API calls) that turns the list returned by
  renoise.Track.available_device_infos into the list of effect plugins shown
  by the tool.

  Only VST and VST3 devices are kept: native Renoise devices and other
  formats are skipped. The VST and VST3 builds of the same plugin (same
  display name) are merged into one entry that remembers both device paths.
]]

local names = require("core.names")

local M = {}

M.UNKNOWN_VENDOR = "Unknown"

local UNKNOWN_VENDOR_NAMES = {
  [""] = true, ["-"] = true, ["unknown"] = true, ["unknown vendor"] = true,
}

--[[
  Returns a list of plugins sorted by name, and the list of skipped infos.

  Each plugin is:
    {
      id = <stable id shared by all builds, see names.plugin_id>,
      key = <key of this exact entry, used for usage counters>,
      name = <plugin name without vendor>,
      vendor = <vendor or "Unknown">,
      path = <device path of the preferred format>,
      format = "VST3" | "VST",
      paths = { VST3 = <path>, VST = <path> },
      is_favorite = <true when any build is a Renoise favorite>,
      is_bridged = <boolean>,
    }

  preferred_format is "VST3" (default) or "VST".
]]
function M.build(infos, preferred_format)
  preferred_format = (preferred_format == "VST") and "VST" or "VST3"

  local plugins, skipped, by_key = {}, {}, {}

  for _, info in ipairs(infos or {}) do
    local format = names.format_of(info.path)
    if not format then
      skipped[#skipped + 1] = { info = info, reason = "not a VST or VST3 plugin" }
    else
      local vendor, plugin_name = names.split_vendor(info.name)
      if plugin_name == "" then
        plugin_name = names.trim(info.short_name)
      end
      if plugin_name == "" then
        plugin_name = "Unnamed"
      end
      if UNKNOWN_VENDOR_NAMES[names.fold(vendor)] then
        vendor = M.UNKNOWN_VENDOR
      end

      -- Builds are merged on the full display name, so that "X (Mono)" and
      -- "X (Stereo)" stay two entries while VST and VST3 become one.
      local key = names.fold(vendor) .. "|" .. names.fold(plugin_name)
      local plugin = by_key[key]
      if not plugin then
        plugin = {
          id = names.plugin_id(vendor, plugin_name),
          key = key,
          name = plugin_name,
          vendor = vendor,
          paths = {},
          bridged = {},
          is_favorite = false,
        }
        by_key[key] = plugin
        plugins[#plugins + 1] = plugin
      end
      if not plugin.paths[format] then
        plugin.paths[format] = info.path
        plugin.bridged[format] = (info.is_bridged == true)
      end
      plugin.is_favorite = plugin.is_favorite or (info.is_favorite == true)
    end
  end

  for _, plugin in ipairs(plugins) do
    local other = (preferred_format == "VST3") and "VST" or "VST3"
    if plugin.paths[preferred_format] then
      plugin.format = preferred_format
    else
      plugin.format = other
    end
    plugin.path = plugin.paths[plugin.format]
    plugin.is_bridged = plugin.bridged[plugin.format]
    plugin.bridged = nil
  end

  table.sort(plugins, function(a, b)
    if a.name ~= b.name then
      return names.less(a.name, b.name)
    end
    return names.less(a.vendor, b.vendor)
  end)

  return plugins, skipped
end

return M

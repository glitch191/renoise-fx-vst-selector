--[[
  FX VST Selector

  Helps to find the right effect plugin when adding one to a DSP chain:
  a "Load VST..." submenu in the DSP chain context menu (by category and
  by vendor) and a browser window with search, filters (category, need,
  vendor, favorites, rating), descriptions and an editor.

  This file wires the pure logic (core/), the shipped data (data/), the
  user data (storage.lua) and the Renoise API together.
]]

local grouping = require("core.grouping")
local merge = require("core.merge")
local menu_layout = require("core.menu_layout")
local storage = require("storage")
local devices = require("devices")
local taxonomy = require("data.taxonomy")
local catalog = require("data.catalog")
local keywords = require("data.keywords")

local TOOL_NAME = "FX VST Selector"
local TOOL_ID = "com.glitch191.RenoiseFxVstSelecta"
local MENU_LABEL = "Load VST..."
local MENU_ROOTS = { "DSP Chain:" .. MENU_LABEL, "DSP Device:" .. MENU_LABEL }
local MAIN_MENU = "Main Menu:Tools:" .. TOOL_NAME

local tool = renoise.tool()

-- Shared state and actions, used by this file and by the browser window.
local app = {
  name = TOOL_NAME,
  version = "",
  taxonomy = taxonomy,
  records = {},
  user = merge.new_user_data(),
  listeners = {},
}

local catalog_index = merge.index_catalog(catalog)
local last_infos = {}
local added_entries = {}
local rebuild_pending = false
local browser = nil

local function status(message)
  renoise.app():show_status(TOOL_NAME .. ": " .. message)
end

local function read_version()
  local file = io.open(tool.bundle_path .. "manifest.xml", "r")
  if not file then
    return ""
  end
  local text = file:read("*a")
  file:close()
  return text:match("<Version>%s*(.-)%s*</Version>") or ""
end

local function save_user()
  local ok, err = storage.save(app.user)
  if not ok then
    status("could not save your data (" .. tostring(err) .. ").")
  end
end

local function notify()
  for _, listener in ipairs(app.listeners) do
    listener()
  end
end

--------------------------------------------------------------------------------
-- Context menu

local function remove_menu_entries()
  for _, name in ipairs(added_entries) do
    if tool:has_menu_entry(name) then
      tool:remove_menu_entry(name)
    end
  end
  added_entries = {}
end

local function add_menu_entry(name, invoke, selected)
  if tool:has_menu_entry(name) then
    return
  end
  tool:add_menu_entry { name = name, invoke = invoke, selected = selected }
  added_entries[#added_entries + 1] = name
end

local function build_menus()
  remove_menu_entries()
  for _, root in ipairs(MENU_ROOTS) do
    for _, entry in ipairs(menu_layout.build(app.records, taxonomy, root, app.user.settings)) do
      local record = entry.record
      if entry.action == "insert" then
        add_menu_entry(entry.name, function() app.insert(record) end)
      elseif entry.action == "browser" then
        add_menu_entry(entry.name, function() app.open_browser() end)
      elseif entry.action == "rescan" then
        add_menu_entry(entry.name, function() app.rescan() end)
      elseif entry.action == "toggle_vendor" then
        add_menu_entry(entry.name,
          function() app.set_show_vendor(not app.user.settings.show_vendor) end,
          function() return app.user.settings.show_vendor == true end)
      end
    end
  end
end

local function rebuild_menus_now()
  local ok, err = pcall(build_menus)
  if not ok then
    status("could not build the context menu (" .. tostring(err) .. ").")
  end
end

-- Menus are rebuilt on the next idle tick rather than immediately: a
-- rebuild may be requested from inside a menu entry of this same menu.
-- The idle notifier removes itself, so nothing runs while the tool is idle.
local function on_idle()
  if tool.app_idle_observable:has_notifier(on_idle) then
    tool.app_idle_observable:remove_notifier(on_idle)
  end
  rebuild_pending = false
  rebuild_menus_now()
end

local function schedule_menu_rebuild()
  if not rebuild_pending then
    rebuild_pending = true
    tool.app_idle_observable:add_notifier(on_idle)
  end
end

--------------------------------------------------------------------------------
-- Records

-- Recompute the records from the last scanned device list and user data.
local function update_records()
  local plugins = grouping.build(last_infos, app.user.settings.preferred_format)
  app.records = merge.resolve(plugins, catalog_index, app.user, taxonomy, keywords)
end

local function refresh()
  update_records()
  schedule_menu_rebuild()
  notify()
end

-- Read the device list again. Renoise gives no notification for a plugin
-- rescan, so this runs on every new song and from "Rescan Plugins".
function app.rescan(silent)
  local infos = devices.fetch_infos()
  if not infos then
    -- No song yet (early in startup): app_new_document will scan.
    return
  end
  last_infos = infos
  refresh()
  if not silent then
    status(("%d effect plugins found."):format(#app.records))
  end
end

--------------------------------------------------------------------------------
-- Actions

function app.insert(record)
  local ok, message = devices.insert(record)
  if not ok then
    status(message)
    return false
  end
  merge.record_use(app.user, record.key, os.date("%Y-%m-%d %H:%M:%S"))
  save_user()
  refresh()
  status("inserted " .. record.name .. ".")
  return true
end

function app.set_field(record, field, value)
  merge.set_field(app.user, record.id, field, value)
  save_user()
  refresh()
end

function app.reset(record)
  merge.reset(app.user, record.id)
  save_user()
  refresh()
end

function app.set_preferred_format(format)
  app.user.settings.preferred_format = (format == "VST") and "VST" or "VST3"
  save_user()
  refresh()
end

-- Show plugins as "Vendor - Name" in the context menu.
function app.set_show_vendor(enabled)
  app.user.settings.show_vendor = (enabled == true)
  save_user()
  refresh()
end

function app.export_data()
  local path = renoise.app():prompt_for_filename_to_write("json", "Export " .. TOOL_NAME .. " data")
  if not path or path == "" then
    return
  end
  local ok, err = storage.export(app.user, path)
  if ok then
    status("data exported to " .. path)
  else
    renoise.app():show_error(("Could not export the data to:\n%s\n\n%s\n\nChoose a folder you can write to.")
      :format(path, tostring(err)))
  end
end

function app.import_data()
  local path = renoise.app():prompt_for_filename_to_read({ "*.json" }, "Import " .. TOOL_NAME .. " data")
  if not path or path == "" then
    return
  end
  local data, err = storage.import(path)
  if not data then
    renoise.app():show_error(("Could not import:\n%s\n\n%s\n\nChoose a file created with Export Data.")
      :format(path, tostring(err)))
    return
  end
  local choice = renoise.app():show_prompt("Import data",
    "Replace your current edits, notes, ratings and usage counters with the imported file?",
    { "Replace", "Cancel" })
  if choice ~= "Replace" then
    return
  end
  app.user = data
  save_user()
  refresh()
  status("data imported.")
end

function app.open_browser()
  if not browser then
    browser = require("browser")
    browser.init(app)
  end
  if #app.records == 0 then
    app.rescan(true)
  end
  browser.show()
end

--------------------------------------------------------------------------------
-- Startup

app.version = read_version()

storage.init(tool.bundle_path, TOOL_ID)
do
  local data, warning = storage.load()
  app.user = data
  if warning then
    renoise.app():show_warning(TOOL_NAME .. "\n\n" .. warning)
  end
end

tool:add_menu_entry { name = MAIN_MENU .. ":Open Browser...", invoke = function() app.open_browser() end }
tool:add_menu_entry { name = MAIN_MENU .. ":Rescan Plugins", invoke = function() app.rescan() end }
tool:add_menu_entry { name = "--- " .. MAIN_MENU .. ":Export Data...", invoke = function() app.export_data() end }
tool:add_menu_entry { name = MAIN_MENU .. ":Import Data...", invoke = function() app.import_data() end }

-- Assignable in Renoise's preferences, Keys tab. The second binding only
-- fires while the DSP chain has the keyboard focus.
tool:add_keybinding {
  name = "Global:Tools:Open " .. TOOL_NAME .. " Browser",
  invoke = function() app.open_browser() end,
}
tool:add_keybinding {
  name = "DSPs Chain:Tools:Open " .. TOOL_NAME .. " Browser",
  invoke = function() app.open_browser() end,
}

local function on_song_available()
  app.rescan(true)
end

tool.tool_finished_loading_observable:add_notifier(on_song_available)
tool.app_new_document_observable:add_notifier(on_song_available)

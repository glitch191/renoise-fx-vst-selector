--[[
  Smoke test of main.lua and browser.lua against a minimal fake of the
  Renoise API. It cannot prove that the tool works in Renoise, but it runs
  every code path once and catches Lua errors: startup, scan, menu build,
  insertion, browser window, search, editing, export and import.

    luajit tests/smoke.lua

  The plugin list is made up for the test.
]]

package.path = "tool/?.lua;" .. package.path

local separator = package.config:sub(1, 1)
local temp = (os.getenv("TEMP") or os.getenv("TMPDIR") or ".") .. separator
local failures = 0

local function check(condition, label)
  if not condition then
    failures = failures + 1
    print("FAIL: " .. label)
  end
end

--------------------------------------------------------------------------------
-- Fake Renoise API

local function observable()
  local notifiers = {}
  return {
    add_notifier = function(_, fn) notifiers[#notifiers + 1] = fn end,
    remove_notifier = function(_, fn)
      for i, other in ipairs(notifiers) do
        if other == fn then
          table.remove(notifiers, i)
          return
        end
      end
    end,
    has_notifier = function(_, fn)
      for _, other in ipairs(notifiers) do
        if other == fn then
          return true
        end
      end
      return false
    end,
    fire = function()
      for _, fn in ipairs({ unpack(notifiers) }) do
        fn()
      end
    end,
    count = function() return #notifiers end,
  }
end

local infos = {}
local function add_info(path, name, favorite)
  infos[#infos + 1] = {
    path = path, name = name, short_name = name, favorite_name = name,
    is_favorite = favorite == true, is_bridged = false,
  }
end
add_info("Audio/Effects/Native/Delay", "Delay")
add_info("Audio/Effects/VST3/A1", "Eventide: Blackhole", true)
add_info("Audio/Effects/VST3/A2", "UVI: Tape Delay")
add_info("Audio/Effects/VST3/A3", "UVI: Tape Color")
add_info("Audio/Effects/VST/Kotelnikov", "Tokyo Dawn Labs: TDR Kotelnikov")
add_info("Audio/Effects/VST3/A4", "Tokyo Dawn Labs: TDR Kotelnikov")
add_info("Audio/Effects/VST3/A5", "Nobody: Mystery Box")
for i = 1, 30 do
  add_info("Audio/Effects/VST3/B" .. i, ("Filler Co: Filler %d"):format(i))
end

local track = { devices = { "mixer" }, available_device_infos = infos, available_devices = {} }
for _, item in ipairs(infos) do
  track.available_devices[#track.available_devices + 1] = item.path
end
local last_device = nil
function track:insert_device_at(path, index)
  assert(index >= 2 and index <= #self.devices + 1, "invalid device index " .. tostring(index))
  table.insert(self.devices, index, path)
  last_device = { path = path, external_editor_visible = false }
  return last_device
end

local song = { selected_track = track, selected_track_device_index = 0 }
function song:describe_undo() end

local menu_entries, keybindings, statuses, messages = {}, {}, {}, {}
local tool = {
  bundle_path = temp .. "selecta-smoke" .. separator,
  app_idle_observable = observable(),
  app_new_document_observable = observable(),
  tool_finished_loading_observable = observable(),
}
function tool:add_menu_entry(entry)
  assert(not menu_entries[entry.name], "duplicate menu entry " .. entry.name)
  menu_entries[entry.name] = entry.invoke
end
function tool:has_menu_entry(name) return menu_entries[name] ~= nil end
function tool:remove_menu_entry(name)
  assert(menu_entries[name], "removing a missing menu entry " .. name)
  menu_entries[name] = nil
end
function tool:add_keybinding(binding) keybindings[binding.name] = binding.invoke end

-- Views are plain tables; a notifier is kept so the test can call it.
local view_meta = {}
view_meta.__index = view_meta
function view_meta:add_child(child) self.children[#self.children + 1] = child end

-- Known view constructors. Like in Renoise, an instance only offers these:
-- anything else (such as the DEFAULT_* constants, which live on the
-- renoise.ViewBuilder class) raises an error.
local VIEW_KINDS = {
  column = true, row = true, horizontal_aligner = true, vertical_aligner = true,
  stack = true, space = true, text = true, multiline_text = true, textfield = true,
  multiline_textfield = true, button = true, checkbox = true, switch = true,
  popup = true, chooser = true, valuebox = true, scrollbar = true, slider = true,
  minislider = true, bitmap = true,
}

local vb_meta = {
  __index = function(_, key)
    if not VIEW_KINDS[key] then
      error(("unknown property or function '%s' for an object of type 'ViewBuilder'"):format(key), 2)
    end
    return function(_, properties)
      local view = setmetatable({ kind = key, children = {} }, view_meta)
      for name, value in pairs(properties or {}) do
        if type(name) == "number" then
          view.children[#view.children + 1] = value
        else
          view[name] = value
        end
      end
      return view
    end
  end,
}

local dialog = nil
local prompt_answer = "Replace"
local write_path, read_path

renoise = {
  API_VERSION = 6.2,
  tool = function() return tool end,
  song = function() return song end,
  ViewBuilder = setmetatable({
    DEFAULT_CONTROL_MARGIN = 4, DEFAULT_CONTROL_SPACING = 2, DEFAULT_CONTROL_HEIGHT = 18,
    DEFAULT_MINI_CONTROL_HEIGHT = 14, DEFAULT_DIALOG_MARGIN = 8, DEFAULT_DIALOG_SPACING = 8,
    DEFAULT_DIALOG_BUTTON_HEIGHT = 22,
  }, {
    __call = function() return setmetatable({}, vb_meta) end,
  }),
  app = function()
    return {
      show_status = function(_, message) statuses[#statuses + 1] = message end,
      show_warning = function(_, message) messages[#messages + 1] = message end,
      show_error = function(_, message) messages[#messages + 1] = message end,
      show_prompt = function() return prompt_answer end,
      prompt_for_filename_to_write = function() return write_path end,
      prompt_for_filename_to_read = function() return read_path end,
      show_custom_dialog = function(_, title, content, key_handler)
        dialog = { visible = true, title = title, content = content, key_handler = key_handler }
        function dialog:show() end
        function dialog:close() self.visible = false end
        return dialog
      end,
    }
  end,
}

--------------------------------------------------------------------------------
-- Run

-- Start from a clean data file. The bundle path is not in the usual place,
-- so the data file falls back to the bundle folder.
os.execute((separator == "\\" and 'mkdir "%s" 2>nul' or 'mkdir -p "%s"'):format(tool.bundle_path))
os.remove(tool.bundle_path .. "userdata.json")
do
  local manifest = io.open("tool/manifest.xml", "rb"):read("*a")
  local copy = io.open(tool.bundle_path .. "manifest.xml", "wb")
  copy:write(manifest)
  copy:close()
end

dofile("tool/main.lua")

local function count_entries(prefix)
  local n = 0
  for name in pairs(menu_entries) do
    if name:find(prefix, 1, true) then
      n = n + 1
    end
  end
  return n
end

check(menu_entries["Main Menu:Tools:FX VST Selector:Open Browser..."], "main menu entry")
check(keybindings["Global:Tools:Open FX VST Selector Browser"], "global key binding")

tool.tool_finished_loading_observable.fire()
check(tool.app_idle_observable.count() == 1, "menu rebuild is scheduled")
tool.app_idle_observable.fire()
check(tool.app_idle_observable.count() == 0, "no idle notifier remains after the rebuild")

local root = "DSP Chain:Load VST..."
check(menu_entries[root .. ":Reverb and Space:Blackhole"], "category menu entry")
check(menu_entries[root .. ":Compressor:TDR Kotelnikov"], "compressor menu entry")
check(menu_entries[root .. ":By Vendor:UVI:Tape Delay"], "by vendor menu entry")
check(menu_entries[root .. ":Uncategorized:Mystery Box"], "uncategorized menu entry")
check(menu_entries[root .. ":VST SELECTOR:Open Browser..."], "open browser menu entry")
check(menu_entries["DSP Device:Load VST...:VST SELECTOR:Rescan Plugins"], "DSP Device menu")
check(count_entries(":By Need:") + count_entries(":Favorites:") == 0, "no need or favorites submenu")

-- Insert from the menu: end of chain when nothing is selected.
menu_entries[root .. ":Reverb and Space:Blackhole"]()
check(track.devices[2] == "Audio/Effects/VST3/A1", "inserted at the end of the chain")
check(song.selected_track_device_index == 2, "inserted device is selected")
menu_entries[root .. ":By Vendor:UVI:Tape Delay"]()
check(track.devices[3] == "Audio/Effects/VST3/A2", "inserted after the selected device")
song.selected_track_device_index = 2
menu_entries[root .. ":Compressor:TDR Kotelnikov"]()
check(track.devices[3] == "Audio/Effects/VST3/A4", "inserted in the middle, preferred VST3 build")
tool.app_idle_observable.fire()
check(count_entries(":Recent:") + count_entries(":Most Used:") == 0, "no recent or most used submenu")
local before = count_entries("")
tool.app_new_document_observable.fire()
tool.app_idle_observable.fire()
check(count_entries("") == before, "rebuild leaves no duplicate or orphan entry")

-- Options.
local function toggle(label)
  local name = root .. ":VST SELECTOR:" .. label
  -- An option preceded by a separator has "--- " in front of its name.
  local invoke = menu_entries[name] or menu_entries["--- " .. name]
  invoke()
  tool.app_idle_observable.fire()
end
toggle("Show Vendor Names")
check(menu_entries[root .. ":Reverb and Space:Eventide - Blackhole"], "vendor names shown")
check(not menu_entries[root .. ":Reverb and Space:Blackhole"], "plain names removed")
toggle("Show Vendor Names")
check(menu_entries[root .. ":Reverb and Space:Blackhole"], "vendor names hidden again")

toggle("Show Short Descriptions")
local hinted = 0
for name in pairs(menu_entries) do
  if name:find("^" .. root:gsub("%p", "%%%0") .. ":Reverb and Space:Blackhole  %(") then
    hinted = hinted + 1
  end
end
check(hinted == 1, "short description shown")
toggle("Show Short Descriptions")

toggle("Favorites Only")
check(menu_entries[root .. ":Reverb and Space:Blackhole"], "a favorite stays")
check(not menu_entries[root .. ":Delay and Echo:Tape Delay"], "a non favorite is hidden")
toggle("Favorites Only")
check(menu_entries[root .. ":Delay and Echo:Tape Delay"], "non favorites are back")

toggle("Hide Uncategorized")
check(not menu_entries[root .. ":Uncategorized:Mystery Box"], "uncategorized hidden")
toggle("Hide Uncategorized")
check(menu_entries[root .. ":Uncategorized:Mystery Box"], "uncategorized shown again")

toggle("Insert at End of Chain")
toggle("Open Editor After Insert")
song.selected_track_device_index = 2
menu_entries[root .. ":Delay and Echo:Tape Delay"]()
check(track.devices[#track.devices] == "Audio/Effects/VST3/A2", "inserted at the end of the chain")
check(last_device.external_editor_visible == true, "editor opened after insertion")
toggle("Insert at End of Chain")
toggle("Open Editor After Insert")
song.selected_track_device_index = 2
menu_entries[root .. ":Delay and Echo:Tape Delay"]()
check(track.devices[3] == "Audio/Effects/VST3/A2", "inserted after the selection again")
check(last_device.external_editor_visible == false, "editor not opened when the option is off")

-- Unavailable plugin: a clear status, no error.
local saved = track.available_devices
track.available_devices = {}
menu_entries[root .. ":Reverb and Space:Blackhole"]()
check(statuses[#statuses]:find("no longer available", 1, true), "unavailable plugin message")
track.available_devices = saved

-- Browser window.
menu_entries["Main Menu:Tools:FX VST Selector:Open Browser..."]()
check(dialog and dialog.visible, "browser opens")
check(dialog.title:find("FX VST Selector 0.", 1, true), "title shows the version")

local function find_views(view, kind, found)
  found = found or {}
  if type(view) == "table" then
    if view.kind == kind then
      found[#found + 1] = view
    end
    for _, child in ipairs(view.children or {}) do
      find_views(child, kind, found)
    end
  end
  return found
end

local function type_text(text)
  for char in text:gmatch(".") do
    dialog.key_handler(dialog, { name = char, character = char, modifier_flags = {} })
  end
end
local function press(name)
  return dialog.key_handler(dialog, { name = name, modifier_flags = {} })
end

local buttons = find_views(dialog.content, "button")

-- No text may be wider than its view: Renoise would grow the view.
do
  local textfit = require("core.textfit")
  local too_wide = 0
  for _, kind in ipairs({ "button", "text" }) do
    for _, view in ipairs(find_views(dialog.content, kind)) do
      if type(view.width) == "number" and type(view.text) == "string"
        and textfit.width(view.text, view.font) > view.width then
        too_wide = too_wide + 1
        print("  too wide: " .. view.text)
      end
    end
  end
  check(too_wide == 0, "every text fits its view")
end
local texts = find_views(dialog.content, "text")
local function text_starting(prefix)
  for _, view in ipairs(texts) do
    if type(view.text) == "string" and view.text:sub(1, #prefix) == prefix then
      return view
    end
  end
end
local function button(text)
  for _, view in ipairs(buttons) do
    if view.text == text then
      return view
    end
  end
end

check(text_starting("35 of 35 plugins"), "all plugins listed")
type_text("tape")
check(text_starting("2 of 35 plugins"), "typing filters the list")
local popups = find_views(dialog.content, "popup")
local need_popup
for _, popup in ipairs(popups) do
  if popup.items[1] == "Any need" then
    need_popup = popup
  end
end
need_popup.notifier(2) -- "warmth" is the first tag
check(text_starting("2 of 35 plugins"), "tape plugins tagged warmth")
press("down")
press("return")
check(track.devices[#track.devices] == "Audio/Effects/VST3/A2"
  or track.devices[song.selected_track_device_index] == "Audio/Effects/VST3/A2", "Enter inserts the selection")
type_text("zzz")
check(text_starting("No plugin matches these filters"), "empty state message")
press("back")
press("esc")
check(dialog.visible, "Esc clears the search first")
button("Clear filters").notifier()
check(text_starting("35 of 35 plugins"), "filters cleared")

-- Scroll, select and edit.
find_views(dialog.content, "scrollbar")[1].notifier(10)
for _, view in ipairs(buttons) do
  if view.align == "left" and view.text ~= "" then
    view.notifier()
    break
  end
end
local fields = find_views(dialog.content, "multiline_textfield")
fields[1].notifier("A new\ndescription")
fields[2].notifier("my note")
for _, popup in ipairs(popups) do
  if popup.items[1] == "No rating" then
    popup.notifier(5)
  elseif popup.items[1] == "Uncategorized" then
    popup.notifier(3)
  end
end
find_views(dialog.content, "checkbox")[3].value = true
find_views(dialog.content, "checkbox")[3].notifier(true)
check(button("Reset to catalog").active, "edited entry can be reset")
button("Reset to catalog").notifier()

-- Export, then import into the running tool.
write_path = temp .. "selecta-smoke-export.json"
read_path = write_path
button("Export data").notifier()
check(io.open(write_path, "rb") ~= nil, "export writes a file")
button("Import data").notifier()
button("Rescan plugins").notifier()
read_path = "tool/manifest.xml"
button("Import data").notifier()
check(messages[#messages] and messages[#messages]:find("Could not import", 1, true), "bad import is refused")
os.remove(write_path)

press("esc")
check(not dialog.visible, "Esc closes the window")
check(tool.app_idle_observable.count() <= 1, "at most one pending idle notifier")
tool.app_idle_observable.fire()
check(tool.app_idle_observable.count() == 0, "no idle notifier while idle")

os.remove(tool.bundle_path .. "userdata.json")
os.remove(tool.bundle_path .. "manifest.xml")

print(failures == 0 and "smoke test passed" or (failures .. " smoke checks failed"))
os.exit(failures == 0 and 0 or 1)

--[[
  menu_layout.lua

  Pure Lua logic (no Renoise API calls) that turns plugin records into the
  ordered list of context menu entries:

    <root>:<Category>[:<Sub-category>]:<Plugin>
    <root>:By Vendor:<Vendor>:<Plugin>
    <root>:Open Browser...
    <root>:Rescan Plugins
    <root>:Options:<Option>          (check marks, see M.OPTIONS)

  Categories sit directly under the root so that a plugin is never more than
  three levels deep. Entry names are unique, ignoring letter case.

  Needs, recent and most used plugins are only offered in the browser
  window, to keep the context menu short.
]]

local names = require("core.names")

local M = {}

M.OPEN_BROWSER = "Open Browser..."
M.RESCAN = "Rescan Plugins"
M.OPTIONS_MENU = "Options"
M.HINT_WIDTH = 32

-- Options shown with a check mark in the Options submenu, in display
-- order. setting is the key in the user data settings; all are off by
-- default.
M.OPTIONS = {
  { setting = "show_vendor", label = "Show Vendor Names" },
  { setting = "show_hints", label = "Show Short Descriptions" },
  { setting = "favorites_only", label = "Favorites Only" },
  { setting = "hide_uncategorized", label = "Hide Uncategorized" },
  { setting = "open_editor", label = "Open Editor After Insert", separator = true },
  { setting = "insert_at_end", label = "Insert at End of Chain" },
}

--[[
  Short hint from a description: its first sentence or clause, cut on a
  word boundary to at most max_length characters ("..." marks a cut).
    "Huge, otherworldly reverb. Endless ambient tails." -> "Huge, otherworldly reverb"
]]
function M.hint(description, max_length)
  max_length = max_length or M.HINT_WIDTH
  local text = names.trim(description)
  if text == "" then
    return ""
  end
  -- First sentence or clause.
  local first = text:match("^(.-)[%.:;]%s") or text:match("^(.-)[%.:;]$") or text
  first = names.trim(first)
  if #first <= max_length then
    return first
  end
  local cut = ""
  for word in first:gmatch("%S+") do
    local candidate = (cut == "") and word or (cut .. " " .. word)
    if #candidate + 3 > max_length then
      break
    end
    cut = candidate
  end
  if cut == "" then
    cut = first:sub(1, max_length - 3)
  end
  return (cut:gsub("[%s%p]+$", "")) .. "..."
end

--[[
  Menu label of a record: its name, followed by its star rating if any.
  options.show_vendor: "Vendor - Name" (plugins without a known vendor keep
  their name alone). options.show_hints: a short hint from the description
  in parentheses. A boolean is accepted in place of options, meaning
  show_vendor only.
]]
function M.label(record, options)
  if type(options) ~= "table" then
    options = { show_vendor = options == true }
  end
  local label = names.sanitize_menu(record.name)
  if options.show_vendor and record.vendor and record.vendor ~= "" and record.vendor ~= "Unknown" then
    label = names.sanitize_menu(record.vendor) .. " - " .. label
  end
  if record.rating and record.rating > 0 then
    label = label .. "  " .. ("*"):rep(record.rating)
  end
  if options.show_hints then
    local hint = M.hint(record.description)
    if hint ~= "" then
      label = label .. "  (" .. names.sanitize_menu(hint) .. ")"
    end
  end
  return label
end

--[[
  Returns a list of entries in display order. Each entry is:
    { name = <full menu entry name>, action = "insert", record = <record> }
    { name = ..., action = "browser" }
    { name = ..., action = "rescan" }
    { name = ..., action = "toggle", setting = <settings key> }
  An entry name starting with "--- " draws a separator above it.
  options are the user settings (see M.OPTIONS); nil means all off.
]]
function M.build(records, taxonomy, root, options)
  options = options or {}
  local entries, used = {}, {}

  local function add(prefix, label, action, record, separator, setting)
    local name = prefix .. ":" .. label
    local n = 1
    while used[name:lower()] do
      n = n + 1
      name = prefix .. ":" .. label .. " (" .. n .. ")"
    end
    used[name:lower()] = true
    entries[#entries + 1] = {
      name = (separator and "--- " or "") .. name,
      action = action,
      record = record,
      setting = setting,
    }
  end

  -- with_vendor is false inside "By Vendor", where it would be redundant.
  local function add_plugins(prefix, list, with_vendor)
    local label_options = { show_vendor = with_vendor, show_hints = options.show_hints }
    local labelled = {}
    for i, record in ipairs(list) do
      labelled[i] = { label = M.label(record, label_options), record = record }
    end
    table.sort(labelled, function(a, b) return names.less(a.label, b.label) end)
    for _, item in ipairs(labelled) do
      add(prefix, item.label, "insert", item.record)
    end
  end

  local function select(keep)
    local list = {}
    for _, record in ipairs(records) do
      if (not options.favorites_only or record.is_favorite) and keep(record) then
        list[#list + 1] = record
      end
    end
    return list
  end

  local show_vendor = options.show_vendor == true

  -- Categories, in taxonomy order, then the uncategorized plugins.
  for _, category in ipairs(taxonomy.categories) do
    local prefix = root .. ":" .. names.sanitize_menu(category.name)
    for _, sub in ipairs(category.subs or {}) do
      add_plugins(prefix .. ":" .. names.sanitize_menu(sub), select(function(r)
        return r.category == category.name and r.sub == sub
      end), show_vendor)
    end
    add_plugins(prefix, select(function(r)
      return (r.category == category.name and r.sub == "")
        or r.secondary == category.name
    end), show_vendor)
  end
  if not options.hide_uncategorized then
    add_plugins(root .. ":" .. names.sanitize_menu(taxonomy.uncategorized), select(function(r)
      return r.category == taxonomy.uncategorized
    end), show_vendor)
  end

  -- By vendor.
  local by_vendor, vendors = {}, {}
  for _, record in ipairs(select(function() return true end)) do
    if not by_vendor[record.vendor] then
      by_vendor[record.vendor] = {}
      vendors[#vendors + 1] = record.vendor
    end
    table.insert(by_vendor[record.vendor], record)
  end
  table.sort(vendors, names.less)
  for _, vendor in ipairs(vendors) do
    add_plugins(root .. ":By Vendor:" .. names.sanitize_menu(vendor), by_vendor[vendor], false)
  end

  add(root, M.OPEN_BROWSER, "browser", nil, true)
  add(root, M.RESCAN, "rescan")
  for _, option in ipairs(M.OPTIONS) do
    add(root .. ":" .. M.OPTIONS_MENU, option.label, "toggle", nil, option.separator, option.setting)
  end

  return entries
end

return M

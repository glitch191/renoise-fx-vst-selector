--[[
  menu_layout.lua

  Pure Lua logic (no Renoise API calls) that turns plugin records into the
  ordered list of context menu entries:

    <root>:<Category>[:<Sub-category>]:<Plugin>
    <root>:By Vendor:<Vendor>:<Plugin>
    <root>:Open Browser...
    <root>:Show Vendor Names
    <root>:Rescan Plugins

  Categories sit directly under the root so that a plugin is never more than
  three levels deep. Entry names are unique, ignoring letter case.

  Needs, favorites, recent and most used plugins are only offered in the
  browser window, to keep the context menu short.
]]

local names = require("core.names")

local M = {}

M.OPEN_BROWSER = "Open Browser..."
M.RESCAN = "Rescan Plugins"
M.SHOW_VENDOR = "Show Vendor Names"

-- Menu label of a record: its name, followed by its star rating if any.
-- With show_vendor, the label is "Vendor - Name" (plugins without a known
-- vendor keep their name alone).
function M.label(record, show_vendor)
  local label = names.sanitize_menu(record.name)
  if show_vendor and record.vendor and record.vendor ~= "" and record.vendor ~= "Unknown" then
    label = names.sanitize_menu(record.vendor) .. " - " .. label
  end
  if record.rating > 0 then
    label = label .. "  " .. ("*"):rep(record.rating)
  end
  return label
end

--[[
  Returns a list of entries in display order. Each entry is:
    { name = <full menu entry name>, action = "insert", record = <record> }
    { name = ..., action = "browser" }
    { name = ..., action = "rescan" }
    { name = ..., action = "toggle_vendor" }   (shown with a check mark)
  An entry name starting with "--- " draws a separator above it.
]]
function M.build(records, taxonomy, root, options)
  local show_vendor = options ~= nil and options.show_vendor == true
  local entries, used = {}, {}

  local function add(prefix, label, action, record, separator)
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
    }
  end

  -- with_vendor is false inside "By Vendor", where it would be redundant.
  local function add_plugins(prefix, list, with_vendor)
    local labelled = {}
    for i, record in ipairs(list) do
      labelled[i] = { label = M.label(record, with_vendor), record = record }
    end
    table.sort(labelled, function(a, b) return names.less(a.label, b.label) end)
    for _, item in ipairs(labelled) do
      add(prefix, item.label, "insert", item.record)
    end
  end

  local function select(keep)
    local list = {}
    for _, record in ipairs(records) do
      if keep(record) then
        list[#list + 1] = record
      end
    end
    return list
  end

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
  add_plugins(root .. ":" .. names.sanitize_menu(taxonomy.uncategorized), select(function(r)
    return r.category == taxonomy.uncategorized
  end), show_vendor)

  -- By vendor.
  local by_vendor, vendors = {}, {}
  for _, record in ipairs(records) do
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
  add(root, M.SHOW_VENDOR, "toggle_vendor")

  return entries
end

return M

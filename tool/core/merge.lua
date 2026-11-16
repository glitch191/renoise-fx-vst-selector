--[[
  merge.lua

  Pure Lua logic (no Renoise API calls) that combines three sources into the
  records shown by the tool:

    1. the installed plugins (see grouping.lua),
    2. the shipped catalog (data/catalog.lua),
    3. the user data (edits, notes, ratings, usage counters).

  User edits always win over the catalog. User data layout:

    {
      version = 1,
      settings = { preferred_format = "VST3" | "VST", show_vendor = false },
      plugins = {
        [plugin id] = {
          overrides = { vendor, category, sub, secondary, tags, description },
          note = "", rating = 0,
        },
      },
      usage = { [plugin key] = { count = 3, last = "2026-11-15 21:04:11" } },
    }
]]

local names = require("core.names")
local guess = require("core.guess")

local M = {}

M.DATA_VERSION = 1
M.MAX_DESCRIPTION = 120

local OVERRIDE_FIELDS = {
  vendor = "string", category = "string", sub = "string",
  secondary = "string", tags = "table", description = "string",
}

--------------------------------------------------------------------------------
-- Taxonomy helpers

-- Returns lookup tables for a taxonomy: categories[name] = { subs set },
-- tags[name] = true.
function M.index_taxonomy(taxonomy)
  local index = { categories = {}, tags = {} }
  for _, category in ipairs(taxonomy.categories) do
    local subs = {}
    for _, sub in ipairs(category.subs or {}) do
      subs[sub] = true
    end
    index.categories[category.name] = subs
  end
  for _, tag in ipairs(taxonomy.tags) do
    index.tags[tag] = true
  end
  return index
end

--------------------------------------------------------------------------------
-- Catalog

-- Returns a lookup table from normalized plugin name to catalog entry, and
-- the list of problems found (duplicate names).
function M.index_catalog(catalog)
  local index, problems = {}, {}
  for position, entry in ipairs(catalog) do
    for _, name in ipairs(entry.names or {}) do
      local key = names.normalize(name)
      if index[key] and index[key] ~= entry then
        problems[#problems + 1] =
          ("duplicate catalog name '%s' (entry %d)"):format(name, position)
      else
        index[key] = entry
      end
    end
  end
  return index, problems
end

--------------------------------------------------------------------------------
-- User data

function M.new_user_data()
  return {
    version = M.DATA_VERSION,
    settings = { preferred_format = "VST3", show_vendor = false },
    plugins = {},
    usage = {},
  }
end

local function clean_tags(tags)
  local result, seen = {}, {}
  if type(tags) == "table" then
    for _, tag in ipairs(tags) do
      if type(tag) == "string" and tag ~= "" and not seen[tag] then
        seen[tag] = true
        result[#result + 1] = tag
      end
    end
  end
  return result
end

-- Returns a clean copy of decoded user data: unknown fields and values of
-- the wrong type are dropped. Never raises. Returns nil and a message when
-- the data is not usable at all.
function M.sanitize_user(data)
  if type(data) ~= "table" then
    return nil, "the data is not an object"
  end
  if type(data.version) ~= "number" or data.version > M.DATA_VERSION then
    return nil, "the data version is missing or newer than this tool"
  end

  local clean = M.new_user_data()

  if type(data.settings) == "table" and data.settings.preferred_format == "VST" then
    clean.settings.preferred_format = "VST"
  end
  if type(data.settings) == "table" and data.settings.show_vendor == true then
    clean.settings.show_vendor = true
  end

  if type(data.plugins) == "table" then
    for id, entry in pairs(data.plugins) do
      if type(id) == "string" and type(entry) == "table" then
        local item = { overrides = {} }
        if type(entry.overrides) == "table" then
          for field, kind in pairs(OVERRIDE_FIELDS) do
            local value = entry.overrides[field]
            if type(value) == kind then
              if field == "tags" then
                value = clean_tags(value)
              elseif field == "description" then
                value = value:sub(1, M.MAX_DESCRIPTION)
              end
              item.overrides[field] = value
            end
          end
        end
        if type(entry.note) == "string" and entry.note ~= "" then
          item.note = entry.note
        end
        if type(entry.rating) == "number" then
          local rating = math.floor(entry.rating)
          if rating >= 1 and rating <= 5 then
            item.rating = rating
          end
        end
        if next(item.overrides) or item.note or item.rating then
          clean.plugins[id] = item
        end
      end
    end
  end

  if type(data.usage) == "table" then
    for key, entry in pairs(data.usage) do
      if type(key) == "string" and type(entry) == "table"
        and type(entry.count) == "number" and entry.count >= 1 then
        clean.usage[key] = {
          count = math.floor(entry.count),
          last = type(entry.last) == "string" and entry.last or "",
        }
      end
    end
  end

  return clean
end

local function plugin_entry(user, id)
  local entry = user.plugins[id]
  if not entry then
    entry = { overrides = {} }
    user.plugins[id] = entry
  end
  return entry
end

local function prune(user, id)
  local entry = user.plugins[id]
  if entry and not next(entry.overrides) and not entry.note and not entry.rating then
    user.plugins[id] = nil
  end
end

-- Set one editable field of a plugin. Catalog fields (vendor, category,
-- sub, secondary, tags, description) are stored as overrides, note and
-- rating as plain values. Returns true when the field name is valid.
function M.set_field(user, id, field, value)
  local entry = plugin_entry(user, id)
  if field == "note" then
    value = names.trim(value)
    entry.note = (value ~= "") and value or nil
  elseif field == "rating" then
    local rating = math.floor(tonumber(value) or 0)
    entry.rating = (rating >= 1 and rating <= 5) and rating or nil
  elseif field == "tags" then
    entry.overrides.tags = clean_tags(value)
  elseif field == "description" then
    entry.overrides.description = names.trim(value):sub(1, M.MAX_DESCRIPTION)
  elseif OVERRIDE_FIELDS[field] then
    entry.overrides[field] = names.trim(value)
  else
    prune(user, id)
    return false
  end
  prune(user, id)
  return true
end

-- Drop the catalog overrides of a plugin. Note and rating are kept.
function M.reset(user, id)
  local entry = user.plugins[id]
  if entry then
    entry.overrides = {}
    prune(user, id)
  end
end

-- Count one insertion. stamp is a sortable "YYYY-MM-DD HH:MM:SS" string.
function M.record_use(user, key, stamp)
  local usage = user.usage[key]
  if not usage then
    usage = { count = 0, last = "" }
    user.usage[key] = usage
  end
  usage.count = usage.count + 1
  usage.last = stamp
end

--------------------------------------------------------------------------------
-- Records

local function build_haystack(record)
  return names.fold(table.concat({
    record.name, record.vendor, record.description, record.note,
    record.category, record.sub, record.secondary,
    table.concat(record.tags, " "),
  }, " "))
end

--[[
  Returns one record per installed plugin:
    {
      id, key, name, vendor, path, format, paths, is_favorite, is_bridged,
      category, sub, secondary, tags, description, needs_review,
      note, rating, use_count, last_used,
      in_catalog, guessed, edited, haystack,
    }
  sub and secondary are "" when unset. Categories, sub-categories and tags
  that do not exist in the taxonomy are dropped; a plugin without a valid
  category lands in taxonomy.uncategorized.
]]
--
-- keywords (optional, see data/keywords.lua): when given, a plugin that is
-- not in the catalog gets a category guessed from its name. Such a record
-- has guessed = true and needs_review = true until the user edits it.
function M.resolve(plugins, catalog_index, user, taxonomy, keywords)
  local tax = M.index_taxonomy(taxonomy)
  local records = {}

  for _, plugin in ipairs(plugins) do
    local entry = catalog_index[names.normalize(plugin.name)]
    local stored = user.plugins[plugin.id] or { overrides = {} }
    local over = stored.overrides
    local usage = user.usage[plugin.key]

    -- Without a catalog entry, fall back on a guess from the name.
    local guessed = nil
    if not entry then
      guessed = guess.from_name(plugin.name, keywords)
    end
    local source = entry or guessed

    local function pick(field, fallback)
      if over[field] ~= nil then
        return over[field]
      end
      if source and source[field] ~= nil then
        return source[field]
      end
      return fallback
    end

    local vendor = over.vendor
    if not vendor or vendor == "" then
      vendor = plugin.vendor
      if vendor == "Unknown" and entry and entry.vendor then
        vendor = entry.vendor
      end
    end

    local category = pick("category", "")
    local sub = pick("sub", "")
    local secondary = pick("secondary", "")
    if not tax.categories[category] then
      category, sub = taxonomy.uncategorized, ""
    elseif not tax.categories[category][sub] then
      sub = ""
    end
    if not tax.categories[secondary] or secondary == category then
      secondary = ""
    end

    local tags = {}
    for _, tag in ipairs(pick("tags", {})) do
      if tax.tags[tag] then
        tags[#tags + 1] = tag
      end
    end

    local edited = next(over) ~= nil
    local record = {
      id = plugin.id,
      key = plugin.key,
      name = plugin.name,
      vendor = vendor,
      path = plugin.path,
      format = plugin.format,
      paths = plugin.paths,
      is_favorite = plugin.is_favorite,
      is_bridged = plugin.is_bridged,
      category = category,
      sub = sub,
      secondary = secondary,
      tags = tags,
      description = pick("description", ""),
      -- An entry edited by the user counts as reviewed.
      needs_review = (not edited)
        and ((entry ~= nil and entry.needs_review == true) or guessed ~= nil),
      note = stored.note or "",
      rating = stored.rating or 0,
      use_count = usage and usage.count or 0,
      last_used = usage and usage.last or "",
      in_catalog = entry ~= nil,
      guessed = guessed ~= nil and over.category == nil,
      edited = edited,
    }
    record.haystack = build_haystack(record)
    records[#records + 1] = record
  end

  return records
end

local function top(records, n, keep, before)
  local list = {}
  for _, record in ipairs(records) do
    if keep(record) then
      list[#list + 1] = record
    end
  end
  table.sort(list, before)
  for i = #list, n + 1, -1 do
    list[i] = nil
  end
  return list
end

-- The n most recently inserted plugins, most recent first.
function M.recent(records, n)
  return top(records, n, function(r) return r.use_count > 0 end, function(a, b)
    if a.last_used ~= b.last_used then
      return a.last_used > b.last_used
    end
    return names.less(a.name, b.name)
  end)
end

-- The n most inserted plugins, most used first.
function M.most_used(records, n)
  return top(records, n, function(r) return r.use_count > 0 end, function(a, b)
    if a.use_count ~= b.use_count then
      return a.use_count > b.use_count
    end
    return names.less(a.name, b.name)
  end)
end

return M

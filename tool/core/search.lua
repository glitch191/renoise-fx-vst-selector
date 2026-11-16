--[[
  search.lua

  Pure Lua filtering of plugin records (no Renoise API calls).
]]

local names = require("core.names")

local M = {}

-- Split a query into folded words.
function M.tokens(query)
  local tokens = {}
  for word in names.fold(query):gmatch("%S+") do
    tokens[#tokens + 1] = word
  end
  return tokens
end

--[[
  Returns the records that match every criterion, in their original order.

  criteria (all optional):
    query          text; every word must be found (name, vendor, description,
                   note, tags, categories), ignoring case and accents
    category       category name; matches the primary or secondary category
    sub            sub-category name (used together with category)
    tag            need tag
    vendor         exact vendor name
    favorites_only boolean
    min_rating     1 to 5
    needs_review   boolean
]]
function M.filter(records, criteria)
  criteria = criteria or {}
  local tokens = M.tokens(criteria.query or "")
  local category = criteria.category
  local sub = criteria.sub
  local tag = criteria.tag
  local vendor = criteria.vendor
  local min_rating = criteria.min_rating or 0

  local result = {}
  for _, record in ipairs(records) do
    local keep = true

    if category and category ~= "" then
      if sub and sub ~= "" then
        keep = record.category == category and record.sub == sub
      else
        keep = record.category == category or record.secondary == category
      end
    end
    if keep and vendor and vendor ~= "" then
      keep = record.vendor == vendor
    end
    if keep and criteria.favorites_only then
      keep = record.is_favorite
    end
    if keep and min_rating > 0 then
      keep = record.rating >= min_rating
    end
    if keep and criteria.needs_review then
      keep = record.needs_review
    end
    if keep and tag and tag ~= "" then
      keep = false
      for _, record_tag in ipairs(record.tags) do
        if record_tag == tag then
          keep = true
          break
        end
      end
    end
    if keep then
      for _, token in ipairs(tokens) do
        if not record.haystack:find(token, 1, true) then
          keep = false
          break
        end
      end
    end

    if keep then
      result[#result + 1] = record
    end
  end
  return result
end

-- Sorted list of the distinct vendors of a record list.
function M.vendors(records)
  local seen, list = {}, {}
  for _, record in ipairs(records) do
    if not seen[record.vendor] then
      seen[record.vendor] = true
      list[#list + 1] = record.vendor
    end
  end
  table.sort(list, names.less)
  return list
end

return M

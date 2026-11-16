--[[
  guess.lua

  Pure Lua (no Renoise API calls): guesses the category of a plugin from
  its name, with the rules of data/keywords.lua. Used only for plugins that
  are not in the catalog; such guesses are marked "Needs review".
]]

local names = require("core.names")

local M = {}

--[[
  Returns { category = <name>, tags = { ... }, keyword = <pattern> } for
  the first rule that matches the plugin name, or nil.
]]
function M.from_name(plugin_name, keywords)
  if not keywords then
    return nil
  end
  -- Spaces around the name let patterns use frontiers at both ends.
  local text = " " .. names.normalize(plugin_name) .. " "
  for _, rule in ipairs(keywords.rules) do
    for _, pattern in ipairs(rule.patterns) do
      if text:find(pattern) then
        local tags = {}
        for i, tag in ipairs(keywords.tags[rule.category] or {}) do
          tags[i] = tag
        end
        return { category = rule.category, tags = tags, keyword = pattern }
      end
    end
  end
  return nil
end

return M

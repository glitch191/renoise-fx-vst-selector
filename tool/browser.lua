--[[
  browser.lua

  The browser window: search, filters, result list, and a detail panel
  that also edits the selected plugin.

  ViewBuilder has no list view, so the list is a fixed number of rows built
  once; scrolling and filtering only change the content of those rows.

  Search: a Renoise text field reports its text only when editing ends, so
  typing is also caught by the window's key handler, which filters on every
  key press while no text field is being edited.
]]

local search = require("core.search")
local merge = require("core.merge")
local textfit = require("core.textfit")

local M = {}

-- Sizes in Renoise view units (scaled by Renoise's own GUI scaling).
-- The window stays under about 1250 x 600 units so that it fits a
-- 1920 x 1080 screen with Renoise's scaling at 150 %. The list shows as
-- many rows as the detail panel is tall.
local ROWS = 22
local W_INSERT, W_NAME, W_VENDOR, W_CATEGORY, W_RATING, W_DESC = 48, 200, 120, 150, 44, 310
local W_DETAIL = 310
local W_LABEL = 84
-- Width available for a line of text in the detail panel.
local W_DETAIL_TEXT = W_DETAIL - 16
local SCROLLBAR_WIDTH = 16

-- Room taken by a button's own border and padding around its text.
local BUTTON_PADDING = 14
-- Small margin kept free at the end of a text view.
local TEXT_PADDING = 4

local app
local vb, dialog
local views = {}
local rows = {}
local updating = false

local state = {
  query = "",
  category_index = 1,
  tag_index = 1,
  vendor = "",
  rating_index = 1,
  favorites_only = false,
  needs_review = false,
  results = {},
  offset = 0,
  selected_key = nil,
}

-- Filled in M.init from the taxonomy.
local category_filter_items, category_filter_map = {}, {}
local category_items, secondary_items = {}, {}
local vendor_items = { "All vendors" }

local RATING_FILTER_ITEMS = { "Any rating", "1 star or more", "2 stars or more", "3 stars or more",
  "4 stars or more", "5 stars" }
local RATING_ITEMS = { "No rating", "*", "**", "***", "****", "*****" }

--------------------------------------------------------------------------------
-- Helpers

-- Show a text in a view without letting the view grow: Renoise views grow to
-- fit their text and never shrink back, which breaks the column alignment.
-- The text is shortened to the given width, with the full text as tooltip.
local function set_fitted(view, text, width, font, tooltip)
  local shown, shortened = textfit.fit(text, width, font)
  view.text = shown
  if tooltip ~= nil then
    view.tooltip = tooltip
  else
    view.tooltip = shortened and text or ""
  end
end

local function stars(rating)
  return rating > 0 and ("*"):rep(rating) or ""
end

local function category_label(record)
  if record.sub ~= "" then
    return record.category .. " / " .. record.sub
  end
  return record.category
end

local function index_of(list, value, default)
  for i, item in ipairs(list) do
    if item == value then
      return i
    end
  end
  return default
end

local function sub_items(category)
  local items = { "None" }
  for _, entry in ipairs(app.taxonomy.categories) do
    if entry.name == category then
      for _, sub in ipairs(entry.subs or {}) do
        items[#items + 1] = sub
      end
    end
  end
  return items
end

local function selected_record()
  if not state.selected_key then
    return nil
  end
  for _, record in ipairs(app.records) do
    if record.key == state.selected_key then
      return record
    end
  end
  return nil
end

local function selected_result_index()
  for i, record in ipairs(state.results) do
    if record.key == state.selected_key then
      return i
    end
  end
  return nil
end

-- Run a function that sets view values without triggering the notifiers.
local function quietly(fn)
  local was = updating
  updating = true
  local ok, err = pcall(fn)
  updating = was
  if not ok then
    error(err, 0)
  end
end

--------------------------------------------------------------------------------
-- Filtering and display

local function criteria()
  local filter = category_filter_map[state.category_index] or {}
  return {
    query = state.query,
    category = filter.category,
    sub = filter.sub,
    tag = (state.tag_index > 1) and app.taxonomy.tags[state.tag_index - 1] or nil,
    vendor = state.vendor,
    favorites_only = state.favorites_only,
    min_rating = state.rating_index - 1,
    needs_review = state.needs_review,
  }
end

local function clamp_offset()
  local max_offset = math.max(0, #state.results - ROWS)
  if state.offset > max_offset then
    state.offset = max_offset
  end
  if state.offset < 0 then
    state.offset = 0
  end
end

local function update_rows()
  for i = 1, ROWS do
    local row = rows[i]
    local record = state.results[state.offset + i]
    if record then
      local is_selected = record.key == state.selected_key
      row.insert.active = true
      row.name.active = true
      local font = is_selected and "bold" or "normal"
      row.name.font = font
      set_fitted(row.name, record.name, W_NAME - BUTTON_PADDING, font,
        record.name .. (record.is_favorite and " (Renoise favorite)" or ""))
      set_fitted(row.vendor, record.vendor, W_VENDOR - TEXT_PADDING)
      set_fitted(row.category, category_label(record), W_CATEGORY - TEXT_PADDING)
      row.rating.text = stars(record.rating)
      if record.description ~= "" then
        set_fitted(row.desc, record.description, W_DESC - TEXT_PADDING, nil, record.description)
        row.desc.style = "normal"
      else
        set_fitted(row.desc, "No description yet", W_DESC - TEXT_PADDING)
        row.desc.style = "disabled"
      end
    else
      row.insert.active = false
      row.name.active = false
      row.name.text = ""
      row.name.font = "normal"
      row.name.tooltip = ""
      row.vendor.text = ""
      row.vendor.tooltip = ""
      row.category.text = ""
      row.category.tooltip = ""
      row.rating.text = ""
      row.desc.text = ""
      row.desc.tooltip = ""
    end
  end
end

local function update_scrollbar()
  quietly(function()
    local bar = views.scrollbar
    bar.value = 0
    bar.max = math.max(#state.results, ROWS)
    bar.pagestep = ROWS
    bar.value = state.offset
    bar.active = #state.results > ROWS
  end)
end

local function update_count()
  local total = #app.records
  local shown = #state.results
  if total == 0 then
    views.count.text = "No effect plugin found. Load a song, then use Rescan plugins."
  elseif shown == 0 then
    views.count.text = "No plugin matches these filters. Clear filters to see all."
  else
    views.count.text = ("%d of %d plugins"):format(shown, total)
  end
end

local function update_detail()
  local record = selected_record()
  quietly(function()
    local has = record ~= nil
    views.d_insert.active = has
    views.d_reset.active = has and record.edited
    views.d_vendor.active = has
    views.d_category.active = has
    views.d_sub.active = has
    views.d_secondary.active = has
    views.d_rating.active = has
    views.d_description.active = has
    views.d_note.active = has
    for _, box in ipairs(views.d_tags) do
      box.active = has
    end

    if not has then
      views.d_name.text = "No plugin selected"
      set_fitted(views.d_info, "Select a plugin in the list to edit it.", W_DETAIL_TEXT)
      views.d_path.text = ""
      views.d_path.tooltip = ""
      views.d_vendor.value = ""
      views.d_description.text = ""
      views.d_note.text = ""
      for _, box in ipairs(views.d_tags) do
        box.value = false
      end
      return
    end

    set_fitted(views.d_name, record.name, W_DETAIL_TEXT, "big")
    local formats = record.format
    for format in pairs(record.paths) do
      if format ~= record.format then
        formats = formats .. ", also " .. format
      end
    end
    local origin
    if record.needs_review then
      origin = "Needs review"
    elseif record.edited then
      origin = "Edited by you"
    elseif record.in_catalog then
      origin = "From catalog"
    else
      origin = "Not in catalog"
    end
    local info = ("%s. %s.%s Used %d times."):format(
      formats, origin, record.is_favorite and " Favorite." or "", record.use_count)
    set_fitted(views.d_info, info, W_DETAIL_TEXT)
    set_fitted(views.d_path, record.path, W_DETAIL_TEXT, nil, record.path)

    views.d_vendor.value = record.vendor
    views.d_category.value = index_of(category_items, record.category, 1)
    local subs = sub_items(record.category)
    views.d_sub.items = subs
    views.d_sub.value = index_of(subs, record.sub, 1)
    views.d_secondary.value = index_of(secondary_items, record.secondary, 1)
    views.d_rating.value = record.rating + 1

    local has_tag = {}
    for _, tag in ipairs(record.tags) do
      has_tag[tag] = true
    end
    for i, box in ipairs(views.d_tags) do
      box.value = has_tag[app.taxonomy.tags[i]] == true
    end

    views.d_description.text = record.description
    views.d_note.text = record.note
  end)
end

local function update_vendor_filter()
  quietly(function()
    vendor_items = { "All vendors" }
    for _, vendor in ipairs(search.vendors(app.records)) do
      vendor_items[#vendor_items + 1] = vendor
    end
    local index = index_of(vendor_items, state.vendor, 1)
    if index == 1 then
      state.vendor = ""
    end
    views.f_vendor.items = vendor_items
    views.f_vendor.value = index
  end)
end

-- Filter again and redraw everything. keep_position keeps the scroll offset.
local function update_all(keep_position)
  state.results = search.filter(app.records, criteria())
  if not keep_position then
    state.offset = 0
  end
  clamp_offset()
  if not selected_result_index() then
    local first = state.results[1]
    state.selected_key = first and first.key or nil
  end
  update_rows()
  update_scrollbar()
  update_count()
  update_detail()
end

local function ensure_selected_visible()
  local index = selected_result_index()
  if not index then
    return
  end
  if index <= state.offset then
    state.offset = index - 1
  elseif index > state.offset + ROWS then
    state.offset = index - ROWS
  end
  clamp_offset()
end

local function select_index(index)
  if #state.results == 0 then
    return
  end
  index = math.max(1, math.min(#state.results, index))
  state.selected_key = state.results[index].key
  ensure_selected_visible()
  update_rows()
  update_scrollbar()
  update_detail()
end

local function set_query(text)
  state.query = text
  quietly(function()
    views.search.value = text
  end)
  update_all(false)
end

local function clear_filters()
  state.query = ""
  state.category_index = 1
  state.tag_index = 1
  state.vendor = ""
  state.rating_index = 1
  state.favorites_only = false
  state.needs_review = false
  quietly(function()
    views.search.value = ""
    views.f_category.value = 1
    views.f_tag.value = 1
    views.f_vendor.value = 1
    views.f_rating.value = 1
    views.f_favorites.value = false
    views.f_review.value = false
  end)
  update_all(false)
end

local function insert_selected()
  local record = selected_record()
  if record then
    app.insert(record)
  end
end

--------------------------------------------------------------------------------
-- Editing

local function edit(field, value)
  if updating then
    return
  end
  local record = selected_record()
  if record then
    app.set_field(record, field, value)
  end
end

local function single_line(text)
  return (tostring(text or ""):gsub("%s+", " "))
end

--------------------------------------------------------------------------------
-- Keyboard

local function drop_last_char(text)
  -- Remove one UTF-8 character.
  return (text:gsub("[%z\1-\127\194-\244][\128-\191]*$", ""))
end

local function key_handler(dlg, key)
  local flags = key.modifier_flags or {}
  local plain = not (flags.control or flags.alt or flags.meta)

  if key.name == "esc" then
    if state.query ~= "" then
      set_query("")
    else
      dlg:close()
    end
    return nil
  elseif key.name == "return" then
    insert_selected()
    return nil
  elseif key.name == "up" then
    select_index((selected_result_index() or 1) - 1)
    return nil
  elseif key.name == "down" then
    select_index((selected_result_index() or 0) + 1)
    return nil
  elseif key.name == "prior" then
    select_index((selected_result_index() or 1) - ROWS)
    return nil
  elseif key.name == "next" then
    select_index((selected_result_index() or 0) + ROWS)
    return nil
  elseif key.name == "back" and plain then
    set_query(drop_last_char(state.query))
    return nil
  elseif plain and key.character and key.character ~= "" and not key.character:find("%c") then
    set_query(state.query .. key.character)
    return nil
  end
  -- Anything else goes back to Renoise (global shortcuts keep working).
  return key
end

--------------------------------------------------------------------------------
-- View construction

local function label(text, width)
  return vb:text { text = text, width = width or W_LABEL }
end

local function build_filters()
  views.search = vb:textfield {
    width = 240,
    tooltip = "Search in names, vendors, descriptions, notes and tags. All words must match.",
    notifier = function(value)
      if not updating then
        state.query = value
        update_all(false)
      end
    end,
  }
  views.f_category = vb:popup {
    width = 220, items = category_filter_items,
    notifier = function(index)
      if not updating then
        state.category_index = index
        update_all(false)
      end
    end,
  }
  views.f_tag = vb:popup {
    width = 130, items = (function()
      local items = { "Any need" }
      for _, tag in ipairs(app.taxonomy.tags) do
        items[#items + 1] = tag
      end
      return items
    end)(),
    notifier = function(index)
      if not updating then
        state.tag_index = index
        update_all(false)
      end
    end,
  }
  views.f_vendor = vb:popup {
    width = 170, items = vendor_items,
    notifier = function(index)
      if not updating then
        state.vendor = (index > 1) and vendor_items[index] or ""
        update_all(false)
      end
    end,
  }
  views.f_rating = vb:popup {
    width = 120, items = RATING_FILTER_ITEMS,
    notifier = function(index)
      if not updating then
        state.rating_index = index
        update_all(false)
      end
    end,
  }
  views.f_favorites = vb:checkbox {
    notifier = function(value)
      if not updating then
        state.favorites_only = value
        update_all(false)
      end
    end,
  }
  views.f_review = vb:checkbox {
    notifier = function(value)
      if not updating then
        state.needs_review = value
        update_all(false)
      end
    end,
  }
  views.count = vb:text { text = "", width = 420 }

  return vb:column {
    spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
    vb:row {
      spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
      vb:row {
        label("Search", 44),
        views.search,
        vb:button { text = "Clear", notifier = function() set_query("") end },
      },
      vb:text {
        style = "disabled",
        text = "Type to search, Up and Down to select, Enter to insert, Esc to clear or close.",
      },
    },
    vb:row {
      spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
      views.f_category,
      views.f_tag,
      views.f_vendor,
      views.f_rating,
      vb:row { views.f_favorites, vb:text { text = "Favorites only" } },
      vb:row { views.f_review, vb:text { text = "Needs review" } },
      vb:button { text = "Clear filters", notifier = clear_filters },
    },
    views.count,
  }
end

local function build_list()
  local list = vb:column { spacing = 1 }

  list:add_child(vb:row {
    spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
    vb:space { width = W_INSERT },
    vb:text { text = "Name", font = "bold", width = W_NAME },
    vb:text { text = "Vendor", font = "bold", width = W_VENDOR },
    vb:text { text = "Category", font = "bold", width = W_CATEGORY },
    vb:text { text = "Rating", font = "bold", width = W_RATING },
    vb:text { text = "Description", font = "bold", width = W_DESC },
  })

  for i = 1, ROWS do
    local row = {}
    row.insert = vb:button {
      text = "Insert", width = W_INSERT,
      tooltip = "Insert this plugin after the selected device",
      notifier = function()
        local record = state.results[state.offset + i]
        if record then
          state.selected_key = record.key
          app.insert(record)
        end
      end,
    }
    row.name = vb:button {
      text = "", width = W_NAME, align = "left",
      notifier = function()
        if state.results[state.offset + i] then
          select_index(state.offset + i)
        end
      end,
    }
    row.vendor = vb:text { text = "", width = W_VENDOR }
    row.category = vb:text { text = "", width = W_CATEGORY }
    row.rating = vb:text { text = "", width = W_RATING }
    row.desc = vb:text { text = "", width = W_DESC }
    rows[i] = row
    list:add_child(vb:row {
      spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
      row.insert, row.name, row.vendor, row.category, row.rating, row.desc,
    })
  end

  views.scrollbar = vb:scrollbar {
    width = SCROLLBAR_WIDTH,
    height = (ROWS + 1) * (renoise.ViewBuilder.DEFAULT_CONTROL_HEIGHT + 1),
    min = 0, max = ROWS, pagestep = ROWS, step = 1, value = 0,
    notifier = function(value)
      if not updating then
        state.offset = value
        clamp_offset()
        update_rows()
      end
    end,
  }

  return vb:row {
    background = "group",
    margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN,
    spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
    list,
    views.scrollbar,
  }
end

local function build_detail()
  local field_width = W_DETAIL - W_LABEL - 2 * renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN

  -- The sub-category row is only shown when the taxonomy uses sub-categories.
  local has_subs = false
  for _, category in ipairs(app.taxonomy.categories) do
    has_subs = has_subs or #(category.subs or {}) > 0
  end

  views.d_name = vb:text { text = "", font = "big", width = W_DETAIL - 8 }
  views.d_info = vb:text { text = "", width = W_DETAIL - 8 }
  views.d_path = vb:text { text = "", style = "disabled", width = W_DETAIL - 8 }

  views.d_vendor = vb:textfield {
    width = field_width,
    notifier = function(value) edit("vendor", value) end,
  }
  views.d_category = vb:popup {
    width = field_width, items = category_items,
    notifier = function(index)
      if updating then
        return
      end
      local record = selected_record()
      if record then
        -- A sub-category belongs to its category: clear it on change.
        merge.set_field(app.user, record.id, "sub", "")
        app.set_field(record, "category", category_items[index])
      end
    end,
  }
  views.d_sub = vb:popup {
    width = field_width, items = { "None" },
    notifier = function(index)
      edit("sub", (index > 1) and views.d_sub.items[index] or "")
    end,
  }
  views.d_secondary = vb:popup {
    width = field_width, items = secondary_items,
    notifier = function(index)
      edit("secondary", (index > 1) and secondary_items[index] or "")
    end,
  }
  views.d_rating = vb:popup {
    width = field_width, items = RATING_ITEMS,
    notifier = function(index) edit("rating", index - 1) end,
  }

  -- Need tags, as two columns of check boxes.
  views.d_tags = {}
  local tags = app.taxonomy.tags
  local half = math.ceil(#tags / 2)
  local columns = { vb:column {}, vb:column {} }
  for i, tag in ipairs(tags) do
    local box = vb:checkbox {
      notifier = function()
        if updating then
          return
        end
        local chosen = {}
        for j, other in ipairs(views.d_tags) do
          if other.value then
            chosen[#chosen + 1] = tags[j]
          end
        end
        edit("tags", chosen)
      end,
    }
    views.d_tags[i] = box
    columns[(i <= half) and 1 or 2]:add_child(vb:row {
      box, vb:text { text = tag, width = (W_DETAIL - 8) / 2 - 24 },
    })
  end

  views.d_description = vb:multiline_textfield {
    width = W_DETAIL - 8, height = 50,
    tooltip = ("What the plugin does and when to use it (%d characters at most)"):format(merge.MAX_DESCRIPTION),
    notifier = function(value) edit("description", single_line(value)) end,
  }
  views.d_note = vb:multiline_textfield {
    width = W_DETAIL - 8, height = 50,
    tooltip = "Your own note, for example: perfect on vocals",
    notifier = function(value) edit("note", single_line(value)) end,
  }

  views.d_insert = vb:button {
    text = "Insert", width = 90, height = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT,
    notifier = insert_selected,
  }
  views.d_reset = vb:button {
    text = "Reset to catalog", width = 120, height = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT,
    tooltip = "Drop your edits of the catalog fields. Your note and rating are kept.",
    notifier = function()
      local record = selected_record()
      if record then
        app.reset(record)
      end
    end,
  }

  return vb:column {
    background = "group",
    margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN,
    spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
    width = W_DETAIL,
    views.d_name,
    views.d_info,
    views.d_path,
    vb:row { label("Vendor"), views.d_vendor },
    vb:row { label("Category"), views.d_category },
    vb:row { visible = has_subs, label("Sub-category"), views.d_sub },
    vb:row { label("Also in"), views.d_secondary },
    vb:row { label("Rating"), views.d_rating },
    vb:text { text = "Needs", font = "bold" },
    vb:row { columns[1], columns[2] },
    vb:text { text = "Description", font = "bold" },
    views.d_description,
    vb:text { text = "My note", font = "bold" },
    views.d_note,
    vb:row { spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING, views.d_insert, views.d_reset },
  }
end

local function build_footer()
  views.format = vb:popup {
    width = 70, items = { "VST3", "VST" },
    value = (app.user.settings.preferred_format == "VST") and 2 or 1,
    tooltip = "Build to insert when a plugin is installed as both VST3 and VST",
    notifier = function(index)
      if not updating then
        app.set_preferred_format(index == 2 and "VST" or "VST3")
      end
    end,
  }
  views.show_vendor = vb:checkbox {
    value = app.user.settings.show_vendor == true,
    tooltip = "Show plugins as Vendor - Name in the Load VST... context menu",
    notifier = function(value)
      if not updating then
        app.set_show_vendor(value)
      end
    end,
  }
  return vb:row {
    spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
    vb:button { text = "Rescan plugins", height = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT,
      notifier = function() app.rescan() end },
    vb:button { text = "Export data", height = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT,
      notifier = function() app.export_data() end },
    vb:button { text = "Import data", height = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT,
      notifier = function() app.import_data() end },
    vb:row { vb:text { text = "Preferred format" }, views.format },
    vb:row { views.show_vendor, vb:text { text = "Vendor names in the context menu" } },
  }
end

local function build_content()
  vb = renoise.ViewBuilder()
  views, rows = {}, {}
  return vb:column {
    margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
    spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
    build_filters(),
    vb:row {
      spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
      build_list(),
      build_detail(),
    },
    build_footer(),
  }
end

--------------------------------------------------------------------------------
-- Public

local function is_open()
  return dialog ~= nil and dialog.visible
end

-- Called by the tool whenever the records change.
local function on_records_changed()
  if not is_open() then
    return
  end
  update_vendor_filter()
  quietly(function()
    views.format.value = (app.user.settings.preferred_format == "VST") and 2 or 1
    views.show_vendor.value = app.user.settings.show_vendor == true
  end)
  update_all(true)
end

function M.init(application)
  app = application

  category_filter_items = { "All categories" }
  category_filter_map = { {} }
  category_items = { app.taxonomy.uncategorized }
  secondary_items = { "None" }
  for _, category in ipairs(app.taxonomy.categories) do
    category_filter_items[#category_filter_items + 1] = category.name
    category_filter_map[#category_filter_map + 1] = { category = category.name }
    for _, sub in ipairs(category.subs or {}) do
      category_filter_items[#category_filter_items + 1] = category.name .. " / " .. sub
      category_filter_map[#category_filter_map + 1] = { category = category.name, sub = sub }
    end
    category_items[#category_items + 1] = category.name
    secondary_items[#secondary_items + 1] = category.name
  end
  category_filter_items[#category_filter_items + 1] = app.taxonomy.uncategorized
  category_filter_map[#category_filter_map + 1] = { category = app.taxonomy.uncategorized }

  table.insert(app.listeners, on_records_changed)
end

function M.show()
  if is_open() then
    dialog:show()
    return
  end

  local content = build_content()
  -- Restore the filters of the previous session of the window.
  quietly(function()
    views.search.value = state.query
    views.f_category.value = state.category_index
    views.f_tag.value = state.tag_index
    views.f_rating.value = state.rating_index
    views.f_favorites.value = state.favorites_only
    views.f_review.value = state.needs_review
  end)
  update_vendor_filter()
  update_all(false)

  local title = app.name
  if app.version ~= "" then
    title = title .. " " .. app.version
  end
  dialog = renoise.app():show_custom_dialog(title, content, key_handler)
end

return M

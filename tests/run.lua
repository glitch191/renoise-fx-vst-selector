--[[
  Tests for the pure logic modules. Run from the repository root with a
  standalone Lua 5.1 compatible interpreter:

    luajit tests/run.lua

  All plugin lists used here are made up for the tests.
]]

package.path = "tool/?.lua;" .. package.path

local names = require("core.names")
local grouping = require("core.grouping")
local json = require("core.json")
local merge = require("core.merge")
local search = require("core.search")
local menu_layout = require("core.menu_layout")
local storage = require("storage")
local textfit = require("core.textfit")
local shipped_taxonomy = require("data.taxonomy")
local catalog = require("data.catalog")

-- The logic tests use their own taxonomy, with sub-categories, so that
-- they do not depend on the shipped one.
local taxonomy = {
  categories = {
    { name = "EQ", subs = {} },
    { name = "Dynamics", subs = { "Compressor", "Limiter" } },
    { name = "Modulation", subs = { "Chorus" } },
    { name = "Lo-fi, Tape and Vintage", subs = {} },
    { name = "Mastering", subs = {} },
  },
  uncategorized = "Uncategorized",
  tags = { "warmth", "width", "punch", "glue", "space", "movement" },
}

local passed, failed = 0, 0

local function check(condition, label)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. label)
  end
end

local function equal(actual, expected, label)
  check(actual == expected,
    ("%s (expected %s, got %s)"):format(label, tostring(expected), tostring(actual)))
end

local function info(path, name, favorite)
  return {
    path = path, name = name, short_name = name, favorite_name = name,
    is_favorite = favorite == true, is_bridged = false,
  }
end

--------------------------------------------------------------------------------
-- names

equal(names.normalize("Blue Cat's Chorus 4 (Stereo)"), "blue cat's chorus", "normalize channel and version")
equal(names.normalize("RC-20 Retro Color v2"), "rc-20 retro color", "normalize v2")
equal(names.normalize("Aphex Vintage Exciter Stereo"), "aphex vintage exciter", "normalize trailing Stereo")
equal(names.normalize("Abbey Road TG Mastering Live Mono"), "abbey road tg mastering live", "normalize Live Mono")
equal(names.normalize("UADx 1176 Rev A Compressor"), "uadx 1176 rev a compressor", "normalize keeps inner numbers")
equal(names.normalize("Native Bus Compressor 2"), "native bus compressor", "normalize trailing number")
equal(names.normalize("MF-109S Saturator"), "mf-109s saturator", "normalize keeps model")
equal(names.normalize("2"), "2", "normalize keeps a bare number")
equal(names.normalize("API 2500 Stereo"), "api 2500", "normalize keeps a model number")
equal(names.normalize("dbx 160"), "dbx 160", "normalize keeps a three digit number")
equal(names.normalize("Ozone 11"), "ozone", "normalize strips a two digit version")
equal(names.normalize("Trackspacer 2.5"), "trackspacer", "normalize strips a decimal version")
equal(names.normalize("Thing v12.3"), "thing", "normalize strips a v version")
equal(names.fold("Échó"), "echo", "fold accents")
equal(names.format_of("Audio/Effects/VST3/ABCD"), "VST3", "format VST3")
equal(names.format_of("Audio/Effects/VST/Thing"), "VST", "format VST")
equal(names.format_of("Audio/Effects/Native/Delay"), nil, "native has no format")
equal(names.format_of("Audio/Effects/Native/VST3"), nil, "id is not inspected")
do
  local vendor, plugin = names.split_vendor("Acme Audio: Wobbler: Deluxe")
  equal(vendor, "Acme Audio", "split vendor")
  equal(plugin, "Wobbler: Deluxe", "split plugin name")
  equal(names.sanitize_menu("--- A:B/C"), "A-B-C", "sanitize menu label")
  equal(names.plugin_id("Acme Audio", "Wobbler 2 (Mono)"), "acme audio|wobbler", "plugin id")
end

--------------------------------------------------------------------------------
-- grouping

local infos = {
  info("Audio/Effects/Native/Delay", "Delay"),
  info("Audio/Effects/VST/Wobbler", "Acme Audio: Wobbler", true),
  info("Audio/Effects/VST3/1111", "Acme Audio: Wobbler"),
  info("Audio/Effects/VST3/2222", "Acme Audio: Squash 2 (Stereo)"),
  info("Audio/Effects/VST3/3333", "Acme Audio: Squash 2 (Mono)"),
  info("Audio/Effects/VST/Old", "Old Thing"),
  info("Audio/Effects/VST3/4444", "Tape Co: Tape Warmer"),
  info("Audio/Effects/VST3/5555", "Nobody: Mystery Box"),
}

local plugins, skipped = grouping.build(infos)
equal(#plugins, 6, "VST and VST3 builds are merged, native is skipped")
equal(#skipped, 1, "one skipped device")

local function find(list, name)
  for _, item in ipairs(list) do
    if item.name == name then
      return item
    end
  end
end

do
  local wobbler = find(plugins, "Wobbler")
  equal(wobbler.format, "VST3", "VST3 preferred by default")
  equal(wobbler.path, "Audio/Effects/VST3/1111", "preferred path")
  equal(wobbler.paths.VST, "Audio/Effects/VST/Wobbler", "other path kept")
  check(wobbler.is_favorite, "favorite when any build is a favorite")
  equal(find(plugins, "Old Thing").vendor, "Unknown", "no vendor")
  equal(find(plugins, "Old Thing").format, "VST", "falls back to the available format")
  equal(find(plugins, "Squash 2 (Mono)").id, find(plugins, "Squash 2 (Stereo)").id, "variants share an id")
  check(find(plugins, "Squash 2 (Mono)").key ~= find(plugins, "Squash 2 (Stereo)").key, "variants have their own key")

  local vst_first = grouping.build(infos, "VST")
  equal(find(vst_first, "Wobbler").format, "VST", "preferred format can be VST")
end

--------------------------------------------------------------------------------
-- merge

local test_catalog = {
  { names = { "Wobbler" }, vendor = "Acme Audio", category = "Modulation", sub = "Chorus",
    tags = { "width", "movement", "not a tag" }, description = "Makes things wobble." },
  { names = { "Squash" }, category = "Dynamics", sub = "Compressor", secondary = "Mastering",
    tags = { "punch" }, description = "Squashes.", needs_review = true },
  { names = { "Tape Warmer" }, category = "Lo-fi, Tape and Vintage", sub = "",
    tags = { "warmth" }, description = "Tape saturation for warmth." },
  { names = { "Old Thing" }, vendor = "Old Co", category = "No Such Category", tags = {},
    description = "Old." },
}
local index, problems = merge.index_catalog(test_catalog)
equal(#problems, 0, "no duplicate in the test catalog")

do
  local _, dup = merge.index_catalog({ { names = { "A 2" } }, { names = { "a" } } })
  equal(#dup, 1, "duplicate names are reported")
end

local user = merge.new_user_data()
local records = merge.resolve(plugins, index, user, taxonomy)
equal(#records, 6, "one record per plugin")

do
  local wobbler = find(records, "Wobbler")
  equal(wobbler.category, "Modulation", "catalog category")
  equal(wobbler.sub, "Chorus", "catalog sub-category")
  equal(#wobbler.tags, 2, "unknown tags are dropped")
  check(wobbler.in_catalog and not wobbler.edited, "catalog entry flags")
  local squash = find(records, "Squash 2 (Stereo)")
  check(squash.needs_review, "needs review comes from the catalog")
  equal(squash.secondary, "Mastering", "secondary category")
  equal(find(records, "Mystery Box").category, taxonomy.uncategorized, "unknown plugin is uncategorized")
  equal(find(records, "Old Thing").category, taxonomy.uncategorized, "invalid category is uncategorized")
  equal(find(records, "Old Thing").vendor, "Old Co", "catalog vendor fills an unknown vendor")
end

do
  local id = find(records, "Squash 2 (Stereo)").id
  merge.set_field(user, id, "category", "EQ")
  merge.set_field(user, id, "description", ("x"):rep(200))
  merge.set_field(user, id, "tags", { "glue", "glue", "warmth" })
  merge.set_field(user, id, "note", "  great on vocals ")
  merge.set_field(user, id, "rating", 4)
  check(not merge.set_field(user, id, "nonsense", 1), "unknown field is rejected")

  local edited = merge.resolve(plugins, index, user, taxonomy)
  local squash = find(edited, "Squash 2 (Mono)")
  equal(squash.category, "EQ", "user category wins, shared by variants")
  equal(squash.sub, "", "sub-category of another category is dropped")
  equal(#squash.description, merge.MAX_DESCRIPTION, "description is capped")
  equal(#squash.tags, 2, "tags are deduplicated")
  equal(squash.note, "great on vocals", "note is trimmed")
  equal(squash.rating, 4, "rating")
  check(squash.edited and not squash.needs_review, "an edited entry counts as reviewed")

  merge.reset(user, id)
  local reset = find(merge.resolve(plugins, index, user, taxonomy), "Squash 2 (Mono)")
  equal(reset.category, "Dynamics", "reset restores the catalog")
  equal(reset.rating, 4, "reset keeps the rating")
  equal(reset.note, "great on vocals", "reset keeps the note")

  merge.set_field(user, id, "rating", 0)
  merge.set_field(user, id, "note", "")
  equal(user.plugins[id], nil, "empty entries are pruned")
end

do
  merge.record_use(user, find(records, "Wobbler").key, "2026-01-01 10:00:00")
  merge.record_use(user, find(records, "Tape Warmer").key, "2026-01-01 10:05:00")
  merge.record_use(user, find(records, "Mystery Box").key, "2026-01-01 10:10:00")
  merge.record_use(user, find(records, "Wobbler").key, "2026-01-01 09:00:00")
  local used = merge.resolve(plugins, index, user, taxonomy)
  local recent = merge.recent(used, 10)
  equal(#recent, 3, "three recent plugins")
  equal(recent[1].name, "Mystery Box", "most recent first")
  equal(recent[2].name, "Tape Warmer", "second most recent")
  equal(merge.most_used(used, 10)[1].name, "Wobbler", "most used first")
  equal(#merge.recent(used, 2), 2, "recent list is capped")
  records = used
end

--------------------------------------------------------------------------------
-- search

do
  local function count(criteria)
    return #search.filter(records, criteria)
  end
  equal(count({}), 6, "no criteria keeps everything")
  equal(count({ query = "TAPE warm" }), 1, "all words must match, ignoring case")
  equal(count({ query = "tape squash" }), 0, "words are combined with AND")
  equal(count({ query = "acme" }), 3, "vendor is searched")
  equal(count({ query = "wobble" }), 1, "description is searched")
  equal(count({ category = "Dynamics" }), 2, "category filter")
  equal(count({ category = "Mastering" }), 2, "secondary category matches")
  equal(count({ category = "Dynamics", sub = "Compressor" }), 2, "sub-category filter")
  equal(count({ category = "Dynamics", sub = "Limiter" }), 0, "other sub-category")
  equal(count({ tag = "warmth" }), 1, "tag filter")
  equal(count({ query = "tape", tag = "warmth" }), 1, "query and tag together")
  equal(count({ vendor = "Acme Audio" }), 3, "vendor filter")
  equal(count({ favorites_only = true }), 1, "favorites filter")
  equal(count({ needs_review = true }), 2, "needs review filter")
  equal(count({ min_rating = 1 }), 0, "rating filter")
  equal(#search.vendors(records), 4, "distinct vendors")
end

--------------------------------------------------------------------------------
-- menu layout

do
  local root = "DSP Chain:Test"
  local entries = menu_layout.build(records, taxonomy, root)
  local by_name, duplicates = {}, 0
  for _, entry in ipairs(entries) do
    local key = entry.name:lower()
    if by_name[key] then
      duplicates = duplicates + 1
    end
    by_name[key] = entry
  end
  equal(duplicates, 0, "menu entry names are unique")
  check(by_name[(root .. ":Modulation:Chorus:Wobbler"):lower()], "category, sub-category, plugin")
  check(by_name[(root .. ":Mastering:Squash 2 (Mono)"):lower()], "secondary category entry")
  check(not by_name[(root .. ":By Need:warmth:Tape Warmer"):lower()], "no by need entry")
  check(by_name[(root .. ":By Vendor:Acme Audio:Wobbler"):lower()], "by vendor entry")
  check(not by_name[(root .. ":Favorites:Wobbler"):lower()], "no favorites entry")
  check(not by_name[(root .. ":Recent:Mystery Box"):lower()], "no recent entry")
  check(not by_name[(root .. ":Most Used:Wobbler"):lower()], "no most used entry")
  check(by_name[(root .. ":Uncategorized:Mystery Box"):lower()], "uncategorized entry")
  check(by_name[("--- " .. root .. ":Open Browser..."):lower()], "open browser entry")
  equal(entries[#entries].action, "toggle", "the options are last")
  equal(entries[#entries].name, root .. ":Options:Insert at End of Chain", "last option")
  local deepest = 0
  for _, entry in ipairs(entries) do
    local _, colons = entry.name:gsub(":", "")
    deepest = math.max(deepest, colons)
  end
  check(deepest <= 4, "a plugin is at most three levels under the tool menu")

  local rated = { rating = 3, name = "A:B" }
  equal(menu_layout.label(rated), "A-B  ***", "label with rating")
end

--------------------------------------------------------------------------------
-- json and storage

do
  local value = {
    version = 1, text = 'quote " backslash \\ newline \n accent é',
    list = { 1, 2.5, "three", true, false }, nested = { empty = {}, n = -12 },
  }
  local decoded = json.decode(json.encode(value))
  equal(decoded.text, value.text, "json string round trip")
  equal(decoded.list[2], 2.5, "json number round trip")
  equal(decoded.list[5], false, "json boolean round trip")
  equal(decoded.nested.n, -12, "json nested round trip")
  equal(json.decode('"\\u00e9"'), "é", "json unicode escape")
  check(json.decode("{") == nil, "truncated json is rejected")
  check(json.decode('{"a": 1} x') == nil, "trailing text is rejected")
  check(json.decode("os.exit()") == nil, "code is not executed")
end

do
  equal(storage.data_dir_from_bundle(
    "C:\\Users\\someone\\AppData\\Roaming\\Renoise\\V3.5.4\\Scripts\\Tools\\com.example.Tool.xrnx\\",
    "com.example.Tool"),
    "C:\\Users\\someone\\AppData\\Roaming\\Renoise\\com.example.Tool\\", "data folder on Windows")
  equal(storage.data_dir_from_bundle(
    "/home/someone/.config/Renoise/V3.5.4/Scripts/Tools/com.example.Tool.xrnx/", "com.example.Tool"),
    "/home/someone/.config/Renoise/com.example.Tool/", "data folder on Linux")
  equal(storage.data_dir_from_bundle("/somewhere/else/tool.xrnx/", "x"), nil, "unusual bundle location")

  -- Export, import and a corrupt file, in a temporary folder.
  local dir = os.getenv("TEMP") or os.getenv("TMPDIR") or "."
  local separator = package.config:sub(1, 1)
  storage.dir = dir .. separator
  storage.path = storage.dir .. "selecta-test-userdata.json"
  os.remove(storage.path)

  check(storage.save(user), "save")
  local loaded, warning = storage.load()
  equal(warning, nil, "load without warning")
  equal(json.encode(loaded), json.encode(merge.sanitize_user(user)), "save and load round trip")

  local export_path = storage.dir .. "selecta-test-export.json"
  local id = find(records, "Wobbler").id
  merge.set_field(user, id, "note", "exported note")
  merge.set_field(user, id, "rating", 5)
  merge.set_field(user, id, "tags", { "space" })
  check(#shipped_taxonomy.categories >= 20, "the shipped taxonomy is flat")
  check(storage.export(user, export_path), "export")
  local imported = storage.import(export_path)
  equal(json.encode(imported), json.encode(merge.sanitize_user(user)), "export and import restore everything")
  os.remove(export_path)

  local file = io.open(storage.path, "wb")
  file:write("{ this is not json")
  file:close()
  local fresh, corrupt_warning = storage.load()
  check(corrupt_warning ~= nil, "a corrupt file gives a warning")
  equal(next(fresh.plugins), nil, "a corrupt file gives fresh data")
  check(io.open(storage.path, "rb") == nil, "the corrupt file is set aside")
  local backup = corrupt_warning:match("set aside as (.-%.json)")
  check(backup ~= nil, "the warning names the backup file")
  if backup then
    os.remove(backup)
  end

  check(merge.sanitize_user({ version = 99 }) == nil, "newer data version is rejected")
  check(merge.sanitize_user("text") == nil, "non-object data is rejected")
  local odd = merge.sanitize_user({
    version = 1, plugins = { a = { rating = 9, note = 3, overrides = { tags = "x", category = "EQ" } }, b = 4 },
    usage = { k = { count = "many" } },
  })
  equal(odd.plugins.a.overrides.category, "EQ", "valid override is kept")
  equal(odd.plugins.a.rating, nil, "out of range rating is dropped")
  equal(odd.plugins.a.overrides.tags, nil, "wrong type override is dropped")
  equal(odd.plugins.b, nil, "wrong type entry is dropped")
  equal(next(odd.usage), nil, "wrong type usage is dropped")
end

--------------------------------------------------------------------------------
-- shipped catalog and taxonomy

do
  local taxonomy = shipped_taxonomy
  local tax = merge.index_taxonomy(taxonomy)
  local _, catalog_problems = merge.index_catalog(catalog)
  for _, problem in ipairs(catalog_problems) do
    check(false, problem)
  end
  check(#catalog_problems == 0, "no duplicate name in the catalog")

  for _, category in ipairs(taxonomy.categories) do
    check(not category.name:find(":", 1, true), "category name without colon: " .. category.name)
  end

  for position, entry in ipairs(catalog) do
    local label = ("catalog entry %d (%s)"):format(position, tostring(entry.names and entry.names[1]))
    check(type(entry.names) == "table" and #entry.names > 0, label .. " has names")
    check(tax.categories[entry.category] ~= nil, label .. " has a valid category")
    if tax.categories[entry.category] then
      check(entry.sub == "" or tax.categories[entry.category][entry.sub], label .. " has a valid sub-category")
    end
    check(entry.secondary == nil or tax.categories[entry.secondary] ~= nil, label .. " has a valid secondary category")
    check(type(entry.tags) == "table" and #entry.tags > 0, label .. " has at least one tag")
    for _, tag in ipairs(entry.tags or {}) do
      check(tax.tags[tag], label .. " uses the known tag " .. tostring(tag))
    end
    check(type(entry.description) == "string" and #entry.description > 0
      and #entry.description <= merge.MAX_DESCRIPTION, label .. " description length")
    check(not entry.description:find("[\226][\128][\147\148]"), label .. " has no long dash")
  end

  -- The favorites given as the starting list must all be described.
  local favorites = {
    "Abbey Road TG Mastering Stereo", "Aphex Vintage Exciter Stereo", "APU Loudness Meter", "BEAM",
    "Blackhole", "Blue Cat's Chorus 4 (Stereo)", "Blue Cat's Flanger 3 (Stereo)",
    "Blue Cat's FreqAnalyst 2 (Stereo)", "Blue Cat's Gain 3 (Stereo)", "Blue Cat's Phaser 3 (Stereo)",
    "Blue Cat's Triple EQ 4 (Stereo)", "Crystalline", "de-essr", "Filter Ark", "FilterShaper XL",
    "FIN-NEO", "granulr", "JUNO-60 CHORUS", "Lifeline Console", "MF-109S Saturator", "Motion Fractal",
    "MVibratoMB", "Native Bus Compressor 2", "Native Channel Strip 2", "Portal", "PsychoPan",
    "RC-20 Retro Color v2", "RESO", "Snapback", "Tape Chorus", "Tape Color", "Tape Delay",
    "Tape Flanger", "TDR Kotelnikov", "Tube Modulator", "UADx 1176AE Compressor",
    "UADx 1176LN Rev E Compressor", "UADx 1176 Rev A Compressor", "UADx Cooper Time Cube Delay",
    "UADx Empirical Labs Distressor", "UADx Empirical Labs FATSO Jr", "UADx Empirical Labs FATSO Sr",
    "UADx Galaxy Tape Echo",
  }
  local catalog_index = merge.index_catalog(catalog)
  for _, name in ipairs(favorites) do
    check(catalog_index[names.normalize(name)] ~= nil, "catalog covers " .. name)
  end
end

--------------------------------------------------------------------------------
-- performance: filtering 500 records

do
  local many = {}
  for i = 1, 500 do
    many[i] = info("Audio/Effects/VST3/" .. i, ("Vendor %d: Plugin Number %d"):format(i % 20, i))
  end
  local many_records = merge.resolve(grouping.build(many), {}, merge.new_user_data(), taxonomy)
  equal(#many_records, 500, "500 records")
  local started = os.clock()
  local runs = 20
  for _ = 1, runs do
    search.filter(many_records, { query = "plugin number 4", vendor = "Vendor 4" })
  end
  local per_run_ms = (os.clock() - started) * 1000 / runs
  check(per_run_ms < 50, ("filtering 500 records takes %.2f ms"):format(per_run_ms))
  print(("Filtering 500 records: %.3f ms per run"):format(per_run_ms))
end

do
  local root = "DSP Chain:Test"
  local names_of = {}
  for _, entry in ipairs(menu_layout.build(records, taxonomy, root, { show_vendor = true })) do
    names_of[entry.name] = entry
  end
  check(names_of[root .. ":Modulation:Chorus:Acme Audio - Wobbler"], "vendor shown before the plugin name")
  check(names_of[root .. ":By Vendor:Acme Audio:Wobbler"], "no vendor prefix inside By Vendor")
  check(names_of[root .. ":Options:Show Vendor Names"], "toggle entry")
  equal(names_of[root .. ":Options:Show Vendor Names"].setting, "show_vendor", "toggle setting")
  equal(menu_layout.label({ name = "X", vendor = "Unknown", rating = 0 }, true), "X", "unknown vendor is not shown")
  check(merge.sanitize_user({ version = 1, settings = { show_vendor = true } }).settings.show_vendor,
    "show_vendor setting is kept")
  check(not merge.new_user_data().settings.show_vendor, "vendor names are off by default")

  -- Every option is off by default and kept when on.
  local all_on = { version = 1, settings = {} }
  for _, option in ipairs(menu_layout.OPTIONS) do
    check(merge.new_user_data().settings[option.setting] == false, option.setting .. " is off by default")
    all_on.settings[option.setting] = true
  end
  local kept = merge.sanitize_user(all_on).settings
  for _, option in ipairs(menu_layout.OPTIONS) do
    check(kept[option.setting] == true, option.setting .. " is kept")
  end
  check(merge.sanitize_user({ version = 1, settings = { show_hints = "yes" } }).settings.show_hints == false,
    "a non boolean option is dropped")

  -- Short descriptions.
  equal(menu_layout.hint("Huge, otherworldly reverb. Endless ambient tails."), "Huge, otherworldly reverb",
    "hint keeps the first sentence")
  equal(menu_layout.hint("Simple gain control."), "Simple gain control", "hint drops the final period")
  local long = menu_layout.hint("Transparent wideband compressor for buses and mastering work.")
  check(#long <= menu_layout.HINT_WIDTH, "hint is short")
  equal(long:sub(-3), "...", "a cut hint ends with three dots")
  check(not long:find(" %.%.%.$"), "a cut hint ends on a word")
  equal(menu_layout.hint(""), "", "no description, no hint")
  equal(menu_layout.label({ name = "Thing", vendor = "Acme", rating = 2, description = "Makes noise. Loud." },
    { show_hints = true }), "Thing  **  (Makes noise)", "label with rating and hint")
  equal(menu_layout.label({ name = "Thing", vendor = "Acme", rating = 0, description = "Ratio: 4 to 1." },
    { show_hints = true }), "Thing  (Ratio)", "a colon in a hint is safe")

  local function build(options)
    local by = {}
    for _, entry in ipairs(menu_layout.build(records, taxonomy, root, options)) do
      by[entry.name] = entry
    end
    return by
  end
  local hinted = build({ show_hints = true })
  check(hinted[root .. ":Modulation:Chorus:Wobbler  (Makes things wobble)"], "hint in a category entry")
  check(hinted[root .. ":By Vendor:Acme Audio:Wobbler  (Makes things wobble)"], "hint in a vendor entry")

  local favorites = build({ favorites_only = true })
  check(favorites[root .. ":Modulation:Chorus:Wobbler"], "favorites only keeps a favorite")
  check(not favorites[root .. ":Uncategorized:Mystery Box"], "favorites only drops the others")
  check(not favorites[root .. ":By Vendor:Nobody:Mystery Box"], "favorites only applies to By Vendor")

  local hidden = build({ hide_uncategorized = true })
  check(not hidden[root .. ":Uncategorized:Mystery Box"], "hide uncategorized")
  check(hidden[root .. ":By Vendor:Nobody:Mystery Box"], "an uncategorized plugin stays in By Vendor")
end

--------------------------------------------------------------------------------
-- textfit

do
  local short, cut = textfit.fit("Blackhole", 200)
  equal(short, "Blackhole", "a short text is kept")
  check(not cut, "a short text is not shortened")
  local long = "Synthesizer V Studio 2 Core ARA Plugin"
  local fitted, shortened = textfit.fit(long, 120)
  check(shortened, "a long text is shortened")
  equal(fitted:sub(-3), "...", "a shortened text ends with three dots")
  check(textfit.width(fitted) <= 120, "the shortened text fits")
  check(not fitted:find("[%s%p]%.%.%.$"), "no space or punctuation before the dots")
  check(textfit.width("abc", "bold") > textfit.width("abc"), "bold is wider")
  check(textfit.width("MMM") > textfit.width("iii"), "wide letters are wider")
  equal(textfit.fit("Équipe éèà", 1000), "Équipe éèà", "accents are kept")
  local tiny = textfit.fit("Abcdef", 5)
  equal(tiny, "...", "a very narrow column shows only the dots")
end

--------------------------------------------------------------------------------
-- guessing a category from the name

do
  local guess = require("core.guess")
  local keywords = require("data.keywords")
  local tax = merge.index_taxonomy(shipped_taxonomy)

  for _, rule in ipairs(keywords.rules) do
    check(tax.categories[rule.category] ~= nil, "keyword rule uses the known category " .. rule.category)
    for _, pattern in ipairs(rule.patterns) do
      check(pcall(string.find, "", pattern), "valid keyword pattern " .. pattern)
    end
  end
  for category, tags in pairs(keywords.tags) do
    check(tax.categories[category] ~= nil, "keyword tags use the known category " .. category)
    for _, tag in ipairs(tags) do
      check(tax.tags[tag], "keyword tags use the known tag " .. tag)
    end
  end

  -- Made-up names, and real names written differently from the catalog.
  local cases = {
    { "Acme Tape Delay (Stereo)", "Delay and Echo" },
    { "Space Echo Deluxe", "Delay and Echo" },
    { "Multi Tap Thing", "Delay and Echo" },
    { "Tapestry Pad", nil },
    { "Vintage Tape Machine", "Lo-fi, Tape and Vintage" },
    { "Bitcrusher X", "Lo-fi, Tape and Vintage" },
    { "Great Hall Reverb 2", "Reverb and Space" },
    { "ShimmerVerb Pro", "Reverb and Space" },
    { "Small Room", "Reverb and Space" },
    { "Mushroom Fuzz", "Saturation and Distortion" },
    { "Tube Compressor", "Compressor" },
    { "FET Comp 76", "Compressor" },
    { "Opto Leveler", "Compressor" },
    { "Bus Limiter", "Limiter" },
    { "Loudness Maximizer", "Limiter" },
    { "Loudness Meter", "Metering and Analysis" },
    { "True Peak Maximiser", "Limiter" },
    { "Channel EQ", "EQ" },
    { "SlickEQ Mono", "EQ" },
    { "Freq Shifter", "Modulation" },
    { "FreqAnalyzer", "Metering and Analysis" },
    { "Vocal De-Esser", "De-esser" },
    { "Noise Gate", "Gate and Expander" },
    { "Gatekeeper", nil },
    { "Extreme Thing", nil },
    { "Tremolo Panner", "Tremolo and Vibrato" },
    { "Auto Pan", "Stereo and Imaging" },
    { "Stereo Widener", "Stereo and Imaging" },
    { "Stereo Delay", "Delay and Echo" },
    { "Analog Chorus", "Chorus" },
    { "Jet Flanger", "Flanger" },
    { "Small Phaser", "Phaser" },
    { "Auto Filter", "Filter" },
    { "Granular Cloud", "Pitch, Granular and Glitch" },
    { "Auto-Tune Lite", "Pitch, Granular and Glitch" },
    { "Transient Designer", "Transient Shaper" },
    { "Mastering Suite", "Mastering" },
    { "Console Channel", "Channel Strip and Console" },
    { "Voice De-noise", "Utility" },
    { "Simple Gain", "Utility" },
    { "Spectrum Analyzer", "Metering and Analysis" },
    { "Blackhole", nil },
    { "Portal", nil },
  }
  for _, case in ipairs(cases) do
    local result = guess.from_name(case[1], keywords)
    equal(result and result.category or nil, case[2], "guess for " .. case[1])
  end
  equal(guess.from_name("Anything", nil), nil, "no keywords, no guess")

  -- In records: a guessed category is marked and needs review.
  local unknown = grouping.build({
    info("Audio/Effects/VST3/G1", "Nobody: Dusty Tape Echo"),
    info("Audio/Effects/VST3/G2", "Nobody: Mystery Box"),
  })
  local guessed_user = merge.new_user_data()
  local guessed = merge.resolve(unknown, {}, guessed_user, shipped_taxonomy, keywords)
  local echo, box = find(guessed, "Dusty Tape Echo"), find(guessed, "Mystery Box")
  equal(echo.category, "Delay and Echo", "guessed category in the record")
  check(echo.guessed and echo.needs_review and not echo.in_catalog, "guessed record flags")
  equal(echo.tags[1], "space", "guessed record gets default tags")
  equal(box.category, shipped_taxonomy.uncategorized, "no keyword, uncategorized")
  check(not box.guessed, "no keyword, not guessed")
  merge.set_field(guessed_user, echo.id, "category", "Lo-fi, Tape and Vintage")
  local edited = find(merge.resolve(unknown, {}, guessed_user, shipped_taxonomy, keywords), "Dusty Tape Echo")
  equal(edited.category, "Lo-fi, Tape and Vintage", "a user category wins over a guess")
  check(not edited.guessed and not edited.needs_review, "an edited guess is no longer a guess")

  -- How well the rules do on the catalog itself (information only).
  local hits, tried, total = 0, 0, 0
  for _, entry in ipairs(catalog) do
    for _, name in ipairs(entry.names) do
      total = total + 1
      local result = guess.from_name(name, keywords)
      if result then
        tried = tried + 1
        if result.category == entry.category or result.category == entry.secondary then
          hits = hits + 1
        end
      end
    end
  end
  print(("Keyword guesses on catalog names: %d of %d names guessed, %d correct (%.0f %%)")
    :format(tried, total, hits, 100 * hits / math.max(tried, 1)))
end

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

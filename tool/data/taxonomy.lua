--[[
  taxonomy.lua

  The categories, sub-categories and need tags used by the catalog, the
  context menu and the browser. Edit this file to change them.

  Rules:
    - names must not contain ":" (it separates menu levels);
    - every category, sub-category and tag used in data/catalog.lua must
      exist here (tests/run.lua checks it);
    - a plugin has one primary category, an optional secondary category
      and any number of need tags;
    - the list is flat on purpose: "Compressor" or "De-esser" are categories
      of their own. A category can still declare sub-categories in "subs"
      (the tool supports them), but none is used here.
]]

return {
  categories = {
    { name = "EQ", subs = {} },
    { name = "Compressor", subs = {} },
    { name = "Limiter", subs = {} },
    { name = "Gate and Expander", subs = {} },
    { name = "Transient Shaper", subs = {} },
    { name = "De-esser", subs = {} },
    { name = "Saturation and Distortion", subs = {} },
    { name = "Chorus", subs = {} },
    { name = "Flanger", subs = {} },
    { name = "Phaser", subs = {} },
    { name = "Tremolo and Vibrato", subs = {} },
    { name = "Ensemble", subs = {} },
    { name = "Modulation", subs = {} },
    { name = "Delay and Echo", subs = {} },
    { name = "Reverb and Space", subs = {} },
    { name = "Filter", subs = {} },
    { name = "Stereo and Imaging", subs = {} },
    { name = "Pitch, Granular and Glitch", subs = {} },
    { name = "Lo-fi, Tape and Vintage", subs = {} },
    { name = "Channel Strip and Console", subs = {} },
    { name = "Mastering", subs = {} },
    { name = "Metering and Analysis", subs = {} },
    { name = "Utility", subs = {} },
    { name = "Creative Multi-FX", subs = {} },
  },

  -- Plugins without a valid category are listed under this name.
  uncategorized = "Uncategorized",

  -- Need tags: what you want to achieve rather than what the plugin is.
  tags = {
    "warmth", "width", "punch", "glue", "clean up", "space", "movement",
    "grit", "lo-fi", "color", "loudness", "analysis", "sound design",
  },
}

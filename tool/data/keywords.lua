--[[
  keywords.lua

  Rules used to guess the category of a plugin that is not in the catalog,
  from its name only. Edit this file to improve the guesses.

  The plugin name is first normalized (lower case, no accents, no channel
  layout or trailing version, see core/names.lua). Rules are tried in
  order and the first rule with a matching pattern wins, so put the most
  specific rules first: "tape delay" must reach Delay and Echo before the
  "tape" rule of Lo-fi, Tape and Vintage.

  Patterns are Lua patterns. "%f[%w]eq%f[%W]" means the word "eq" on its
  own, "verb" means "verb" anywhere in the name. Every category used here
  must exist in data/taxonomy.lua (tests/run.lua checks it).

  tags: need tags given to a guessed plugin of that category.
]]

return {
  rules = {
    { category = "De-esser", patterns = { "de%-?ess", "sibilan" } },
    { category = "Metering and Analysis", patterns = {
      "meter", "analy[sz]", "oscillo", "%f[%w]scope%f[%W]", "lufs", "spectrum", "tuner", "correlat",
    } },
    { category = "Limiter", patterns = { "limiter", "limit%f[%W]", "maximi[sz]" } },
    { category = "Transient Shaper", patterns = { "transient" } },
    { category = "Modulation", patterns = { "trance ?gate" } },
    { category = "Gate and Expander", patterns = { "%f[%w]gate%f[%W]", "%f[%w]expander" } },
    { category = "Utility", patterns = {
      "de%-?noise", "de%-?click", "de%-?hum", "noise reduc", "%f[%w]gain%f[%W]", "utility",
      "polarity", "phase align",
    } },
    { category = "Delay and Echo", patterns = { "delay", "echo", "%f[%w]taps?%f[%W]" } },
    { category = "Reverb and Space", patterns = {
      "verb", "%f[%w]hall%f[%W]", "%f[%w]plates?%f[%W]", "%f[%w]room%f[%W]", "chamber",
      "spring", "ambien", "convol",
    } },
    { category = "Ensemble", patterns = { "ensemble", "doubler" } },
    { category = "Chorus", patterns = { "chorus", "dimension" } },
    { category = "Flanger", patterns = { "flang" } },
    { category = "Phaser", patterns = { "phaser", "phasor", "phazer" } },
    { category = "Tremolo and Vibrato", patterns = { "%f[%w]trem", "vibrato" } },
    { category = "Modulation", patterns = {
      "ring ?mod", "freq[%a ]*shift", "rotary", "leslie", "modulat",
    } },
    { category = "Filter", patterns = { "filter", "%f[%w]wah" } },
    { category = "Compressor", patterns = {
      "compress", "%f[%w]comp%f[%W]", "1176", "la%-?2a", "la%-?3a", "%f[%w]opto",
      "%f[%w]fet%f[%W]", "vari%-?mu", "squash", "leveler", "leveling",
    } },
    { category = "EQ", patterns = {
      "%f[%w]eq%f[%W]", "eq%f[%W]", "%f[%w]eq%d", "equali[sz]", "pultec", "%f[%w]geq",
    } },
    { category = "Saturation and Distortion", patterns = {
      "satur", "distort", "%f[%w]drive", "overdrive", "fuzz", "%f[%w]tube", "preamp",
      "exciter", "harmonic", "%f[%w]amp%f[%W]", "%f[%w]warm",
    } },
    { category = "Lo-fi, Tape and Vintage", patterns = {
      "%f[%w]tapes?%f[%W]", "tape%f[%W]", "vinyl", "lo%-?fi", "cassette", "bit ?crush", "crusher", "decimat", "%f[%w]vhs",
    } },
    { category = "Stereo and Imaging", patterns = {
      "stereo", "%f[%w]wide", "widen", "imager", "%f[%w]pan%f[%W]", "panner", "haas",
    } },
    { category = "Pitch, Granular and Glitch", patterns = {
      "pitch", "%f[%w]tune", "harmoniz", "granul", "%f[%w]grains?%f[%W]", "glitch", "stutter",
      "octav", "formant",
    } },
    { category = "Channel Strip and Console", patterns = { "channel", "%f[%w]strip", "console" } },
    { category = "Mastering", patterns = { "master" } },
    { category = "Creative Multi-FX", patterns = { "vocoder", "multi%-?fx", "multi%-?effect" } },
  },

  tags = {
    ["EQ"] = { "clean up" },
    ["Compressor"] = { "punch" },
    ["Limiter"] = { "loudness" },
    ["Gate and Expander"] = { "clean up" },
    ["Transient Shaper"] = { "punch" },
    ["De-esser"] = { "clean up" },
    ["Saturation and Distortion"] = { "warmth", "grit" },
    ["Chorus"] = { "width", "movement" },
    ["Flanger"] = { "movement" },
    ["Phaser"] = { "movement" },
    ["Tremolo and Vibrato"] = { "movement" },
    ["Ensemble"] = { "width" },
    ["Modulation"] = { "movement" },
    ["Delay and Echo"] = { "space" },
    ["Reverb and Space"] = { "space" },
    ["Filter"] = { "movement" },
    ["Stereo and Imaging"] = { "width" },
    ["Pitch, Granular and Glitch"] = { "sound design" },
    ["Lo-fi, Tape and Vintage"] = { "lo-fi" },
    ["Channel Strip and Console"] = { "color" },
    ["Mastering"] = { "loudness" },
    ["Metering and Analysis"] = { "analysis" },
    ["Utility"] = { "clean up" },
    ["Creative Multi-FX"] = { "sound design" },
  },
}

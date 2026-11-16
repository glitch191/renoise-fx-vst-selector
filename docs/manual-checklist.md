# Manual checklist (in Renoise)

The automated tests cannot drive Renoise. After `scripts/install-dev.ps1` and
"Tools > Reload All Tools", check the following. If something fails, open the
scripting terminal (start Renoise with the `--scripting-dev` argument, then
"Tools > Scripting Terminal & Editor") and copy the error message.

1. Loading: no error appears when Renoise starts or when the tools are reloaded.
2. Menu: right-click an empty area of a track's DSP chain. "Load VST..."
   appears next to "Add Favorites", with categories, By Vendor,
   Open Browser... and Rescan Plugins.
3. Insert from each section: a category (for example Compressor)
   and By Vendor. The plugin lands after the selected device,
   or at the end of the chain when no device is selected, and is selected.
4. Undo: Ctrl + Z removes the inserted device.
5. In the browser, the detail panel shows how many times a plugin was used.
6. "Show Vendor Names" in the menu (or the check box at the bottom of the
   browser) switches the menu labels to "Vendor - Plugin"; a check mark shows
   when it is on.
7. Browser: "Open Browser..." opens the window. Type "tape": the list filters
   while typing. Choose the need "warmth". Up and Down change the selection,
   Enter inserts, Esc clears the search and then closes the window.
8. Search field: click the field, type a word, press Enter. The list filters.
9. Editing: select a plugin, change its category, tick a need, type a
   description and a note, set a rating. The list and the context menu follow.
   "Reset to catalog" restores the catalog fields and keeps note and rating.
10. Restart Renoise: the edits, the note and the rating are still there.
11. Export data, change a note, then Import data: the exported state is back.
12. Master track and a send track: insertion works on both.
13. Key binding: in Renoise's preferences, Keys, search "Selector", assign a key
    to "Open FX VST Selector Browser" and use it.
14. Scaling: in Renoise's preferences, GUI, try 125 % and 150 %. The window
    stays fully visible, without clipped or overlapping text.
15. Every effect plugin appears once (VST and VST3 builds merged), with no
    instrument and no native Renoise device.

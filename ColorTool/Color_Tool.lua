-- @description Color Tool: Color Palette & Picker
-- @author drvlat
-- @version 1.0.0
-- @about
--   An ImGui-based color palette viewer for REAPER.
--   Displays organized color swatches for quick visual reference.

local reaper = reaper

if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox('ReaImGui is not installed or the version is too old. Please install/update it via ReaPack.', 'Error', 0)
  return
end

if reaper.set_action_options then
  reaper.set_action_options(1)
end
local _, _, section_id, cmd_id = reaper.get_action_context()
if section_id and cmd_id and section_id ~= -1 and cmd_id ~= -1 then
  reaper.SetToggleCommandState(section_id, cmd_id, 1)
  reaper.RefreshToolbar2(section_id, cmd_id)
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local imgui = require('imgui')('0.9.3')

local script_name = "Color Tool"
local ctx = imgui.CreateContext(script_name)
local script_running = true
local show_pref = false

local info = debug.getinfo(1, 'S')
local script_dir = info.source:match('^@?(.*[/\\])')
local sep = package.config:sub(1,1)
local palettes_dir = script_dir .. 'palettes'

local colors = {}

local cfg = {
  tile_size_x = 36,
  tile_size_y = 36,
  tile_spacing = 4,
  palette = 'default',
  cols_per_row = 12,
}

local palettes_list = {}

local function config_path()
  return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "Walter_ColorTool_Settings.txt"
end

local function load_config()
  local f = io.open(config_path(), "r")
  if not f then return end
  for line in f:lines() do
    line = line:gsub("[\r\n]", "")
    local key, val = line:match("^([^=]+)=(.+)$")
    if key and val then
      local n = tonumber(val)
      if key == "tile_size_x" and n then cfg.tile_size_x = n end
      if key == "tile_size_y" and n then cfg.tile_size_y = n end
      if key == "tile_spacing" and n then cfg.tile_spacing = n end
      if key == "palette" then cfg.palette = val end
      if key == "cols_per_row" and n then cfg.cols_per_row = n end
    end
  end
  f:close()
end

local function save_config()
  local f = io.open(config_path(), "w")
  if not f then return end
  f:write(string.format("tile_size_x=%d\n", cfg.tile_size_x))
  f:write(string.format("tile_size_y=%d\n", cfg.tile_size_y))
  f:write(string.format("tile_spacing=%d\n", cfg.tile_spacing))
  f:write("palette=" .. cfg.palette .. "\n")
  f:write(string.format("cols_per_row=%d\n", cfg.cols_per_row))
  f:close()
end

local function scan_palettes()
  local list = {}
  local i = 0
  while true do
    local file = reaper.EnumerateFiles(palettes_dir, i)
    if not file then break end
    local name = file:match('^(.+)%.colorpalette$')
    if name then
      list[#list + 1] = { name = name, path = palettes_dir .. sep .. file }
    end
    i = i + 1
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function hex_val(ch)
  if ch >= '0' and ch <= '9' then return ch - '0' end
  return ch:upper():byte() - 55  -- A=65->10, etc
end

local function parse_s1_color(hex)
  if #hex ~= 8 then return nil end
  local b1, b2 = hex_val(hex:sub(3,3)), hex_val(hex:sub(4,4))
  local b = (b1 * 16 + b2) / 255
  local g1, g2 = hex_val(hex:sub(5,5)), hex_val(hex:sub(6,6))
  local g = (g1 * 16 + g2) / 255
  local r1, r2 = hex_val(hex:sub(7,7)), hex_val(hex:sub(8,8))
  local r = (r1 * 16 + r2) / 255
  return { r, g, b }
end

local function load_palette(filepath)
  local f = io.open(filepath, "r")
  if not f then return {} end
  local content = f:read("*all")
  f:close()

  local out = {}
  for hex in content:gmatch('"([A-Fa-f0-9]+)"') do
    local c = parse_s1_color(hex)
    if c then out[#out + 1] = c end
  end
  return out
end

local function reload_palette()
  local found = false
  for _, p in ipairs(palettes_list) do
    if p.name == cfg.palette then
      colors = load_palette(p.path)
      found = true
      break
    end
  end
  if not found then
    if #palettes_list > 0 then
      cfg.palette = palettes_list[1].name
      colors = load_palette(palettes_list[1].path)
    else
      colors = {}
    end
  end
end

-- init
palettes_list = scan_palettes()
load_config()
reload_palette()

local WIN_PAD = 8
local TITLE_H = 36
local HEADER_H = 40

local function calc_content_size()
  local cols = cfg.cols_per_row
  local rows = #colors > 0 and math.ceil(#colors / cols) or 1
  local w = cols * cfg.tile_size_x + (cols - 1) * cfg.tile_spacing
  local h = rows * cfg.tile_size_y + (rows - 1) * cfg.tile_spacing
  return w, h
end

local function calc_win_size()
  local cw, ch = calc_content_size()
  return cw + WIN_PAD * 2, ch + WIN_PAD * 2 + TITLE_H + HEADER_H
end

local function color_to_u32(r, g, b, a)
  return reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, a or 1.0)
end

local function apply_color(r, g, b)
  local ctx_mode = reaper.GetCursorContext2(true)

  local r8 = math.floor(r * 255 + 0.5)
  local g8 = math.floor(g * 255 + 0.5)
  local b8 = math.floor(b * 255 + 0.5)

  reaper.Undo_BeginBlock()

  if ctx_mode == 0 then
    local nc = reaper.ColorToNative(r8, g8, b8) | 0x1000000
    local count = reaper.CountSelectedTracks(0)
    for i = 0, count - 1 do
      local track = reaper.GetSelectedTrack(0, i)
      if track then
        reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", nc)
      end
    end
    reaper.Undo_EndBlock("Color Tool: Color Tracks", -1)
  elseif ctx_mode == 1 then
    local nc = reaper.ColorToNative(r8, g8, b8) | 0x1000000
    local count = reaper.CountSelectedMediaItems(0)
    for i = 0, count - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      if item then
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", nc)
      end
    end
    reaper.Undo_EndBlock("Color Tool: Color Items", -1)
  end

  reaper.MarkProjectDirty(0)
  reaper.UpdateArrange()
end

local function render_pref_window()
  reaper.ImGui_SetNextWindowSize(ctx, 280, 220, imgui.Cond_Once)
  local visible, open = reaper.ImGui_Begin(ctx, "Preferences##ColorTool", true, imgui.WindowFlags_NoCollapse | imgui.WindowFlags_AlwaysAutoResize)
  if not open then
    show_pref = false
  end
  if visible then
    local v

    -- palette selector
    if #palettes_list > 0 then
      local current_idx = 1
      for i, p in ipairs(palettes_list) do
        if p.name == cfg.palette then current_idx = i end
      end
      local items = {}
      for _, p in ipairs(palettes_list) do
        items[#items + 1] = p.name
      end
      local changed, new_idx = reaper.ImGui_Combo(ctx, "Palette", current_idx - 1, table.concat(items, "\0") .. "\0")
      if changed then
        cfg.palette = palettes_list[new_idx + 1].name
        reload_palette()
      end

      reaper.ImGui_SameLine(ctx, 0, 4)
      if reaper.ImGui_Button(ctx, "+##import", 24, 0) then
        local ok, fn = reaper.GetUserFileNameForRead("", "Import .colorpalette", "colorpalette")
        if ok and fn ~= "" then
          local f = io.open(fn, "r")
          if f then
            local content = f:read("*all")
            f:close()
            if content:match('"colors"%s*:') and content:match('"[A-Fa-f0-9]+"') then
              local basename = fn:match('^.*[\\/](.+)%.colorpalette$') or fn:match('^.*[\\/](.+)$') or "imported"
              local dest = palettes_dir .. sep .. basename .. ".colorpalette"
              if reaper.file_exists(dest) then
                local i = 1
                while reaper.file_exists(palettes_dir .. sep .. basename .. "_" .. i .. ".colorpalette") do
                  i = i + 1
                end
                dest = palettes_dir .. sep .. basename .. "_" .. i .. ".colorpalette"
              end
              local fo = io.open(dest, "w")
              if fo then
                fo:write(content)
                fo:close()
                palettes_list = scan_palettes()
                cfg.palette = basename
                reload_palette()
              end
            else
              reaper.ShowMessageBox("File does not appear to be a valid .colorpalette (expected JSON with \"colors\" array).", "Import Error", 0)
            end
          end
        end
      end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Import palette file")
      end

      reaper.ImGui_Separator(ctx)
    end

    v = cfg.cols_per_row
    local changed_cr, v = reaper.ImGui_SliderInt(ctx, "Colors in row", v, 4, 48)
    if changed_cr then cfg.cols_per_row = v end

    v = cfg.tile_size_x
    local changed_x, v = reaper.ImGui_SliderInt(ctx, "Tile Size X", v, 16, 80)
    if changed_x then cfg.tile_size_x = v end

    v = cfg.tile_size_y
    local changed_y, v = reaper.ImGui_SliderInt(ctx, "Tile Size Y", v, 16, 80)
    if changed_y then cfg.tile_size_y = v end

    v = cfg.tile_spacing
    local changed_s, v = reaper.ImGui_SliderInt(ctx, "Tile Spacing", v, 0, 20)
    if changed_s then cfg.tile_spacing = v end

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, "Save", 80, 0) then
      save_config()
      show_pref = false
    end
    reaper.ImGui_SameLine(ctx, 0, 8)
    if reaper.ImGui_Button(ctx, "Cancel", 80, 0) then
      show_pref = false
    end
  end
  reaper.ImGui_End(ctx)
end

local function render_ui()
  if #colors == 0 then
    reaper.ImGui_Text(ctx, "No palettes found in " .. palettes_dir)
    return
  end

  local cw, ch = calc_content_size()
  reaper.ImGui_BeginChild(ctx, "grid", cw, ch, 0, imgui.WindowFlags_NoScrollbar)
  reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_ItemSpacing, cfg.tile_spacing, cfg.tile_spacing)

  for idx, c in ipairs(colors) do
      local r, g, b = table.unpack(c)
      local label = "##c" .. idx

      if (idx - 1) % cfg.cols_per_row ~= 0 then
        reaper.ImGui_SameLine(ctx)
      end

      local col_u32 = color_to_u32(r, g, b)
      if reaper.ImGui_ColorButton(ctx, label, col_u32, 0, cfg.tile_size_x, cfg.tile_size_y) then
        apply_color(r, g, b)
      end

      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, string.format("R:%.0f G:%.0f B:%.0f", r * 255, g * 255, b * 255))
        reaper.ImGui_EndTooltip(ctx)
      end
    end

  reaper.ImGui_PopStyleVar(ctx)
  reaper.ImGui_EndChild(ctx)
end

local function loop()
  if not script_running then return end

  local win_w, win_h = calc_win_size()
  reaper.ImGui_SetNextWindowSize(ctx, win_w, win_h, imgui.Cond_Always)
  local window_flags = imgui.WindowFlags_NoCollapse | imgui.WindowFlags_TopMost
  local visible, open = reaper.ImGui_Begin(ctx, script_name, true, window_flags)

  if not open then
    script_running = false
  end

  if visible and script_running then
    reaper.ImGui_Text(ctx, "Color Palette")
    reaper.ImGui_SameLine(ctx, 0, 8)
    if reaper.ImGui_Button(ctx, "Pref", 40, 0) then
      show_pref = true
    end
    reaper.ImGui_Separator(ctx)
    render_ui()
  end

  reaper.ImGui_End(ctx)

  if show_pref then
    render_pref_window()
  end

  if script_running then
    reaper.defer(loop)
  end
end

local function cleanup()
  if section_id and cmd_id and section_id ~= -1 and cmd_id ~= -1 then
    reaper.SetToggleCommandState(section_id, cmd_id, 0)
    reaper.RefreshToolbar2(section_id, cmd_id)
  end
end

reaper.atexit(cleanup)
reaper.defer(loop)

-- @description Color Tool: Color Palette & Picker
-- @author drvlat
-- @version 1.2.0
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
local script_dir = info.source:match('^@?(.*[/\\])') or ""
local sep = package.config:sub(1,1)
local palettes_dir = script_dir .. 'palettes'
local CONFIG_PATH = reaper.GetResourcePath() .. sep .. "Data" .. sep .. "Walter_ColorTool_Settings.txt"

local colors = {}

local cfg = {
  tile_size_x = 36,
  tile_size_y = 36,
  tile_spacing = 4,
  palette = 'default',
  cols_per_row = 12,
  bg_color = 0x000000FF,
}

local palettes_list = {}

local function save_config()
  local f = io.open(CONFIG_PATH, "w")
  if not f then return end
  f:write(string.format("tile_size_x=%d\n", cfg.tile_size_x))
  f:write(string.format("tile_size_y=%d\n", cfg.tile_size_y))
  f:write(string.format("tile_spacing=%d\n", cfg.tile_spacing))
  f:write("palette=" .. cfg.palette .. "\n")
  f:write(string.format("cols_per_row=%d\n", cfg.cols_per_row))
  f:write(string.format("bg_color=%d\n", cfg.bg_color))
  f:close()
end

local function load_config()
  local f = io.open(CONFIG_PATH, "r")
  if not f then
    save_config()
    return
  end
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
      if key == "bg_color" and n then cfg.bg_color = n end
    end
  end
  f:close()
end

local function scan_palettes()
  local list = {}
  local i = 0
  while i < 10000 do
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

local function parse_s1_color(hex)
  if #hex ~= 8 then return nil end
  local b = tonumber(hex:sub(3,4), 16)
  local g = tonumber(hex:sub(5,6), 16)
  local r = tonumber(hex:sub(7,8), 16)
  if r and g and b then
    return r / 255, g / 255, b / 255
  end
  return nil
end

local function load_palette(filepath)
  local f = io.open(filepath, "r")
  if not f then return {} end
  local content = f:read("*all")
  f:close()

  local out = {}
  local idx = 1
  for hex in content:gmatch('"([A-Fa-f0-9]+)"') do
    local r, g, b = parse_s1_color(hex)
    if r then
      out[#out + 1] = {
        r = r,
        g = g,
        b = b,
        u32 = reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 1.0),
        label = "##c" .. idx,
      }
      idx = idx + 1
    end
  end
  return out
end

local cached_cw, cached_ch = 0, 0

local function update_window_size()
  local cols = cfg.cols_per_row
  local rows = #colors > 0 and math.ceil(#colors / cols) or 1
  cached_cw = cols * cfg.tile_size_x + (cols - 1) * cfg.tile_spacing
  cached_ch = rows * cfg.tile_size_y + (rows - 1) * cfg.tile_spacing
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
  update_window_size()
  last_change_count = -1
end

local palettes_combo_string = ""
local palette_name_to_idx = {}

local function update_palettes_cache()
  local items = {}
  palette_name_to_idx = {}
  for i, p in ipairs(palettes_list) do
    items[#items + 1] = p.name
    palette_name_to_idx[p.name] = i
  end
  palettes_combo_string = table.concat(items, "\0") .. "\0"
end

-- init
palettes_list = scan_palettes()
if #palettes_list == 0 then
  reaper.RecursiveCreateDirectory(palettes_dir, 0)
  local default_path = palettes_dir .. sep .. "default.colorpalette"
  local f = io.open(default_path, "w")
  if f then
    f:write([[
{
  "colors": [
    "FF3D14DB", "FF2121B3", "FF5C5CCC", "FF8080F0", "FF7380FA", "FF4763FF",
    "FF008CFF", "FF00A6FF", "FF00D6FF", "FF00FFFF", "FF8CE6F0", "FF4F80FF",
    "FF006300", "FF218C21", "FF578C2E", "FF70B33D", "FF33CC33", "FF99FA99",
    "FF800000", "FFE06940", "FFFF8F1F", "FFED9463", "FFEBCF87", "FFE6D9AD",
    "FF82004A", "FF800080", "FF8C008C", "FFED82ED", "FFB569FF", "FFCCBFFF",
    "FF808000", "FF8C8C00", "FFABB321", "FFCCD147", "FFD1E040", "FFD4FF80",
    "FF000080", "FF2929A6", "FF2E52A1", "FF61A3F5", "FF21A6D9", "FF8CB5D1",
    "FF000000", "FF545454", "FF808080", "FFBFBFBF", "FFD4D4D4", "FFFFFFFF"
  ]
}
]])
    f:close()
  end
  palettes_list = scan_palettes()
end

update_palettes_cache()
load_config()
reload_palette()

local function apply_color(r, g, b)
  local r8 = math.floor(r * 255 + 0.5)
  local g8 = math.floor(g * 255 + 0.5)
  local b8 = math.floor(b * 255 + 0.5)
  local nc = reaper.ColorToNative(r8, g8, b8) | 0x1000000
  local colored = false

  local ctx_mode = reaper.GetCursorContext2(true)

  if ctx_mode == 0 then
    local cnt = reaper.CountSelectedTracks(0)
    if cnt > 0 then
      reaper.Undo_BeginBlock()
      for i = 0, cnt - 1 do
        local tr = reaper.GetSelectedTrack(0, i)
        if tr then reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", nc) end
      end
      reaper.Undo_EndBlock("Color Tool: Color Tracks", -1)
      colored = true
    end

  elseif ctx_mode == 1 then
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt > 0 then
      reaper.Undo_BeginBlock()
      for i = 0, cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
          reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", nc)
          local take = reaper.GetActiveTake(item)
          if take then
            reaper.SetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR", nc)
          end
        end
      end
      reaper.Undo_EndBlock("Color Tool: Color Items+Takes", -1)
      colored = true
    end
  end

  if not colored then
    local curpos = reaper.GetCursorPosition()
    local total = reaper.CountProjectMarkers(0)
    for i = 0, total - 1 do
      local ok, isrgn, pos, rngend, name, idxnum = reaper.EnumProjectMarkers(i)
      if ok and ok > 0 then
        if isrgn then
          if curpos >= pos and curpos <= rngend then
            reaper.Undo_BeginBlock()
            reaper.SetProjectMarkerByIndex(0, i, isrgn, pos, rngend, idxnum, name, nc)
            reaper.Undo_EndBlock("Color Tool: Color Region", -1)
            colored = true
            break
          end
        else
          if math.abs(curpos - pos) < 0.1 then
            reaper.Undo_BeginBlock()
            reaper.SetProjectMarkerByIndex(0, i, isrgn, pos, rngend, idxnum, name, nc)
            reaper.Undo_EndBlock("Color Tool: Color Marker", -1)
            colored = true
            break
          end
        end
      end
    end
  end

  if colored then
    reaper.MarkProjectDirty(0)
    reaper.UpdateArrange()
    last_change_count = -1
  end
end

local function render_palette_selector(combo_width)
  if #palettes_list > 0 then
    local current_idx = palette_name_to_idx[cfg.palette] or 1

    reaper.ImGui_SetNextItemWidth(ctx, combo_width or 120)
    local changed, new_idx = reaper.ImGui_Combo(ctx, "##Palette", current_idx - 1, palettes_combo_string)
    if changed then
      cfg.palette = palettes_list[new_idx + 1].name
      reload_palette()
      save_config()
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
              while i < 1000 and reaper.file_exists(palettes_dir .. sep .. basename .. "_" .. i .. ".colorpalette") do
                i = i + 1
              end
              dest = palettes_dir .. sep .. basename .. "_" .. i .. ".colorpalette"
            end
            local fo = io.open(dest, "w")
            if fo then
              fo:write(content)
              fo:close()
              palettes_list = scan_palettes()
              update_palettes_cache()
              cfg.palette = basename
              reload_palette()
              save_config()
            end
          else
            reaper.ShowMessageBox("File does not appear to be a valid .colorpalette (expected JSON with \"colors\" array).", "Import Error", 0)
          end
        end
      end
    end
  end
end

local function render_pref_window()
  reaper.ImGui_SetNextWindowSize(ctx, 280, 200, imgui.Cond_Once)
  local visible, open = reaper.ImGui_Begin(ctx, "Preferences##ColorTool", true, imgui.WindowFlags_NoCollapse | imgui.WindowFlags_AlwaysAutoResize)
  if not open then
    show_pref = false
  end
  if visible then
    local v

    v = cfg.cols_per_row
    local changed_cr, val = reaper.ImGui_SliderInt(ctx, "Colors in row", v, 4, 48)
    if changed_cr then
      cfg.cols_per_row = val
      update_window_size()
    end

    v = cfg.tile_size_x
    local changed_x, val = reaper.ImGui_SliderInt(ctx, "Tile Size X", v, 16, 80)
    if changed_x then
      cfg.tile_size_x = val
      update_window_size()
    end

    v = cfg.tile_size_y
    local changed_y, val = reaper.ImGui_SliderInt(ctx, "Tile Size Y", v, 16, 80)
    if changed_y then
      cfg.tile_size_y = val
      update_window_size()
    end

    v = cfg.tile_spacing
    local changed_s, val = reaper.ImGui_SliderInt(ctx, "Tile Spacing", v, 0, 20)
    if changed_s then
      cfg.tile_spacing = val
      update_window_size()
    end

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Window Bg")
    reaper.ImGui_SameLine(ctx, 0, 8)
    if reaper.ImGui_ColorButton(ctx, "##BgColorBtn", cfg.bg_color, imgui.ColorEditFlags_NoTooltip, 36, 20) then
      reaper.ImGui_OpenPopup(ctx, "BgColorPopup")
    end

    if reaper.ImGui_BeginPopup(ctx, "BgColorPopup") then
      local changed, new_bg = reaper.ImGui_ColorPicker4(ctx, "##BgPicker", cfg.bg_color)
      if changed then
        cfg.bg_color = new_bg
      end
      reaper.ImGui_EndPopup(ctx)
    end

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

local last_change_count = -1
local last_cursor_pos = -1
local last_ctx_mode = -1
local cached_match_idx = nil

local function get_selected_color()
  local ctx_mode = reaper.GetCursorContext2(true)
  if ctx_mode == 0 then
    local track = reaper.GetSelectedTrack(0, 0)
    if track then
      local nc = reaper.GetTrackColor(track)
      if nc > 0 then
        nc = nc & ~0x1000000
        local r, g, b = reaper.ColorFromNative(nc)
        return r / 255, g / 255, b / 255
      end
    end
  elseif ctx_mode == 1 then
    local item = reaper.GetSelectedMediaItem(0, 0)
    if item then
      local nc = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
      if nc and nc > 0 then
        local nc_int = math.floor(nc + 0.5) & ~0x1000000
        local r, g, b = reaper.ColorFromNative(nc_int)
        return r / 255, g / 255, b / 255
      end
    end
  end

  -- fallback: highlight marker/region at edit cursor
  local curpos = reaper.GetCursorPosition()
  local markeridx, regionidx = reaper.GetLastMarkerAndCurRegion(0, curpos)

  if regionidx >= 0 then
    local ok, isrgn, pos, rngend, name, id, mc = reaper.EnumProjectMarkers3(0, regionidx)
    if ok and ok > 0 and mc and mc > 0 then
      mc = mc & ~0x1000000
      local r, g, b = reaper.ColorFromNative(mc)
      return r / 255, g / 255, b / 255
    end
  end

  if markeridx >= 0 then
    local ok, isrgn, pos, rngend, name, id, mc = reaper.EnumProjectMarkers3(0, markeridx)
    if ok and ok > 0 and mc and mc > 0 and math.abs(curpos - pos) < 0.1 then
      mc = mc & ~0x1000000
      local r, g, b = reaper.ColorFromNative(mc)
      return r / 255, g / 255, b / 255
    end
  end

  -- marker may be at exact cursor (GetLastMarkerAndCurRegion is "before time")
  local markeridx2, _ = reaper.GetLastMarkerAndCurRegion(0, curpos + 0.001)
  if markeridx2 >= 0 and markeridx2 ~= markeridx then
    local ok, isrgn, pos, rngend, name, id, mc = reaper.EnumProjectMarkers3(0, markeridx2)
    if ok and ok > 0 and mc and mc > 0 and math.abs(curpos - pos) < 0.1 then
      mc = mc & ~0x1000000
      local r, g, b = reaper.ColorFromNative(mc)
      return r / 255, g / 255, b / 255
    end
  end
end

local function update_selected_color_cache()
  local change_count = reaper.GetProjectStateChangeCount(0)
  local cursor_pos = reaper.GetCursorPosition()
  local ctx_mode = reaper.GetCursorContext2(true)

  if change_count ~= last_change_count or cursor_pos ~= last_cursor_pos or ctx_mode ~= last_ctx_mode then
    last_change_count = change_count
    last_cursor_pos = cursor_pos
    last_ctx_mode = ctx_mode

    local sr, sg, sb = get_selected_color()
    cached_match_idx = nil
    if sr then
      for idx, c in ipairs(colors) do
        local dr = math.abs(c.r - sr)
        local dg = math.abs(c.g - sg)
        local db = math.abs(c.b - sb)
        if dr < 0.005 and dg < 0.005 and db < 0.005 then
          cached_match_idx = idx
          break
        end
      end
    end
  end
end

local function render_ui()
  if #colors == 0 then
    reaper.ImGui_Text(ctx, "No palettes found in " .. palettes_dir)
    return
  end

  update_selected_color_cache()
  local dl = reaper.ImGui_GetWindowDrawList(ctx)

  reaper.ImGui_BeginChild(ctx, "grid", cached_cw, cached_ch, 0, imgui.WindowFlags_NoScrollbar)
  reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_ItemSpacing, cfg.tile_spacing, cfg.tile_spacing)

  for idx, c in ipairs(colors) do
    if (idx - 1) % cfg.cols_per_row ~= 0 then
      reaper.ImGui_SameLine(ctx)
    end

    if reaper.ImGui_ColorButton(ctx, c.label, c.u32, imgui.ColorEditFlags_NoTooltip, cfg.tile_size_x, cfg.tile_size_y) then
      apply_color(c.r, c.g, c.b)
    end

    if idx == cached_match_idx then
      local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
      local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
      reaper.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, 0xFFFFFFCC, 4, 0, 2.5)
    end
  end

  reaper.ImGui_PopStyleVar(ctx)
  reaper.ImGui_EndChild(ctx)
end

local function loop()
  if not script_running then return end

  reaper.ImGui_PushStyleColor(ctx, imgui.Col_WindowBg, cfg.bg_color)

  local window_flags = imgui.WindowFlags_NoCollapse | imgui.WindowFlags_TopMost | imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoResize
  local visible, open = reaper.ImGui_Begin(ctx, script_name, true, window_flags)

  if not open then
    script_running = false
  end

  if visible and script_running then
    reaper.ImGui_Text(ctx, "Color Palette")
    reaper.ImGui_SameLine(ctx, 0, 8)
    render_palette_selector(120)
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

  reaper.ImGui_PopStyleColor(ctx)

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

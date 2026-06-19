-- @noindex

local reaper = reaper
local imgui = require('imgui')('0.9.3')

local ThemeManager = {}

-- Helper: pack float {r,g,b} table to uint32 in 0xRRGGBBAA format
function ThemeManager.theme_pack(t)
    return reaper.ImGui_ColorConvertDouble4ToU32(t[1], t[2], t[3], 1.0)
end

-- Helper: unpack uint32 to float {r,g,b} table
function ThemeManager.theme_unpack(u)
    local r, g, b = reaper.ImGui_ColorConvertU32ToDouble4(u)
    return {r, g, b}
end

-- Push Theme Custom Colors & Styles
function ThemeManager.push_theme(ctx, themes)
    local bg   = themes.theme_bg
    local ac   = themes.theme_accent
    local theme_text = themes.theme_text
    local theme_frame_bg = themes.theme_frame_bg
    local theme_slider_grab = themes.theme_slider_grab
    local theme_check_mark = themes.theme_check_mark

    -- Helpers: darken / lighten by a factor
    local function dim(c, f)  return {c[1]*f, c[2]*f, c[3]*f} end
    local function mix(c, f)  return {math.min(c[1]+f, 1), math.min(c[2]+f, 1), math.min(c[3]+f, 1)} end

    local bg_title  = mix(dim(bg, 1.0), 0.10)
    local bg_titleA = mix(dim(bg, 1.0), 0.18)
    local bg_frame  = theme_frame_bg
    local bg_frameH = mix(dim(bg_frame, 1.0), 0.05)
    local bg_frameA = mix(dim(bg_frame, 1.0), 0.10)

    local btn      = {ac[1]*0.60, ac[2]*0.50, ac[3]*0.90}
    local btnH     = {ac[1]*0.80, ac[2]*0.70, ac[3]*1.00}
    local btnA     = {ac[1]*1.00, ac[2]*0.90, ac[3]*1.00}
    local sliderG  = theme_slider_grab
    local sliderGA = mix(sliderG, 0.10)
    local hdr      = {ac[1]*0.40, ac[2]*0.36, ac[3]*0.60}
    local hdrH     = {ac[1]*0.60, ac[2]*0.50, ac[3]*0.90}
    local hdrA     = {ac[1]*0.80, ac[2]*0.70, ac[3]*1.00}
    local border   = {bg[1]+0.17, bg[2]+0.17, bg[3]+0.20}

    local function u32(c, a) return reaper.ImGui_ColorConvertDouble4ToU32(c[1], c[2], c[3], a or 1.0) end

    reaper.ImGui_PushStyleColor(ctx, imgui.Col_WindowBg,         u32(bg))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_TitleBg,          u32(bg_title))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_TitleBgActive,    u32(bg_titleA))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_FrameBg,          u32(bg_frame))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_FrameBgHovered,   u32(bg_frameH))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_FrameBgActive,    u32(bg_frameA))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_SliderGrab,       u32(sliderG))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_SliderGrabActive, u32(sliderGA))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,           u32(btn))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered,    u32(btnH))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,     u32(btnA))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text,             reaper.ImGui_ColorConvertDouble4ToU32(theme_text[1], theme_text[2], theme_text[3], 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Header,           u32(hdr))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_HeaderHovered,    u32(hdrH))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_HeaderActive,     u32(hdrA))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Border,           u32(border, 0.5))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_CheckMark,        u32(theme_check_mark))

    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_FrameRounding, 6.0)
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_GrabRounding, 6.0)
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_WindowRounding, 8.0)
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_ItemSpacing, 8.0, 6.0)
end

-- Pop Theme Styles & Colors
function ThemeManager.pop_theme(ctx)
    reaper.ImGui_PopStyleColor(ctx, 17)
    reaper.ImGui_PopStyleVar(ctx, 4)
end

-- Push/pop helpers for semantically-colored buttons (override the theme defaults)
function ThemeManager.push_danger_style(ctx, themes)
    local d = themes.theme_danger
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,        reaper.ImGui_ColorConvertDouble4ToU32(d[1]*0.70, d[2]*0.40, d[3]*0.40, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(d[1]*0.90, d[2]*0.50, d[3]*0.50, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,  reaper.ImGui_ColorConvertDouble4ToU32(d[1]*1.00, d[2]*0.60, d[3]*0.60, 1.0))
end

function ThemeManager.pop_danger_style(ctx)
    reaper.ImGui_PopStyleColor(ctx, 3)
end

function ThemeManager.push_positive_style(ctx, themes)
    local p = themes.theme_positive
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,        reaper.ImGui_ColorConvertDouble4ToU32(p[1]*0.55, p[2]*0.85, p[3]*0.55, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(p[1]*0.70, p[2]*1.00, p[3]*0.70, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,  reaper.ImGui_ColorConvertDouble4ToU32(p[1]*0.40, p[2]*0.70, p[3]*0.40, 1.0))
end

function ThemeManager.pop_positive_style(ctx)
    reaper.ImGui_PopStyleColor(ctx, 3)
end

return ThemeManager

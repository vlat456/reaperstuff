-- @noindex

local reaper = reaper
local imgui = require('imgui')('0.9.3')
local theme_manager = require("theme_manager")

local UISettings = {}

function UISettings.draw_settings_panel(ctx, gui_state, theme_state, defaults, callbacks)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "Settings")
    reaper.ImGui_Spacing(ctx)

    -- Write Keyswitches Option
    local changed_cb, new_cb = reaper.ImGui_Checkbox(ctx, "Write Keyswitches (MIDI notes)", gui_state.write_keyswitches)
    if changed_cb then
        gui_state.write_keyswitches = new_cb
        callbacks.save_settings()
        callbacks.update_targets_list(true)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Colors Header
    reaper.ImGui_Text(ctx, "Custom Colors")
    reaper.ImGui_Spacing(ctx)

    -- Background Color
    reaper.ImGui_TextDisabled(ctx, "Background Color")
    local bg_changed, new_bg_u32 = reaper.ImGui_ColorEdit4(ctx, "##bg_color", theme_state.bg_u32)
    if bg_changed then theme_state.bg_u32 = new_bg_u32 end

    reaper.ImGui_Spacing(ctx)

    -- Accent Color
    reaper.ImGui_TextDisabled(ctx, "Accent Color (General Buttons & Headers)")
    local ac_changed, new_ac_u32 = reaper.ImGui_ColorEdit4(ctx, "##accent_color", theme_state.accent_u32)
    if ac_changed then theme_state.accent_u32 = new_ac_u32 end

    reaper.ImGui_Spacing(ctx)

    -- Slider Pin Color
    reaper.ImGui_TextDisabled(ctx, "Slider Pin Color")
    local sg_changed, new_sg_u32 = reaper.ImGui_ColorEdit4(ctx, "##slider_grab_color", theme_state.slider_grab_u32)
    if sg_changed then theme_state.slider_grab_u32 = new_sg_u32 end

    reaper.ImGui_Spacing(ctx)

    -- Slider Background Color
    reaper.ImGui_TextDisabled(ctx, "Slider Background Color")
    local fb_changed, new_fb_u32 = reaper.ImGui_ColorEdit4(ctx, "##frame_bg_color", theme_state.frame_bg_u32)
    if fb_changed then theme_state.frame_bg_u32 = new_fb_u32 end

    reaper.ImGui_Spacing(ctx)

    -- Apply Button Color
    reaper.ImGui_TextDisabled(ctx, "Apply Button Color")
    local ap_changed, new_ap_u32 = reaper.ImGui_ColorEdit4(ctx, "##apply_btn_color", theme_state.apply_btn_u32)
    if ap_changed then theme_state.apply_btn_u32 = new_ap_u32 end

    reaper.ImGui_Spacing(ctx)

    -- Radio Button Pin Color
    reaper.ImGui_TextDisabled(ctx, "Radio Button Pin Color")
    local cm_changed, new_cm_u32 = reaper.ImGui_ColorEdit4(ctx, "##check_mark_color", theme_state.check_mark_u32)
    if cm_changed then theme_state.check_mark_u32 = new_cm_u32 end

    reaper.ImGui_Spacing(ctx)

    -- Text Color
    reaper.ImGui_TextDisabled(ctx, "Text Color")
    local tx_changed, new_tx_u32 = reaper.ImGui_ColorEdit4(ctx, "##text_color", theme_state.text_u32)
    if tx_changed then theme_state.text_u32 = new_tx_u32 end

    reaper.ImGui_Spacing(ctx)

    -- Danger Color
    reaper.ImGui_TextDisabled(ctx, "Danger Color  (Reset, Delete buttons)")
    local dg_changed, new_dg_u32 = reaper.ImGui_ColorEdit4(ctx, "##danger_color", theme_state.danger_u32)
    if dg_changed then theme_state.danger_u32 = new_dg_u32 end

    reaper.ImGui_Spacing(ctx)

    -- Positive Color
    reaper.ImGui_TextDisabled(ctx, "Positive Color  (Save buttons)")
    local pos_changed, new_pos_u32 = reaper.ImGui_ColorEdit4(ctx, "##positive_color", theme_state.positive_u32)
    if pos_changed then theme_state.positive_u32 = new_pos_u32 end

    reaper.ImGui_Spacing(ctx)

    -- Live preview: unpack from uint32 once per frame → float tables for the theme
    theme_state.theme_bg          = theme_manager.theme_unpack(theme_state.bg_u32)
    theme_state.theme_accent      = theme_manager.theme_unpack(theme_state.accent_u32)
    theme_state.theme_text        = theme_manager.theme_unpack(theme_state.text_u32)
    theme_state.theme_danger      = theme_manager.theme_unpack(theme_state.danger_u32)
    theme_state.theme_positive    = theme_manager.theme_unpack(theme_state.positive_u32)
    theme_state.theme_slider_grab = theme_manager.theme_unpack(theme_state.slider_grab_u32)
    theme_state.theme_apply_btn   = theme_manager.theme_unpack(theme_state.apply_btn_u32)
    theme_state.theme_frame_bg    = theme_manager.theme_unpack(theme_state.frame_bg_u32)
    theme_state.theme_check_mark  = theme_manager.theme_unpack(theme_state.check_mark_u32)

    local show_settings = true

    -- Save button
    theme_manager.push_positive_style(ctx, theme_state)
    if reaper.ImGui_Button(ctx, "Save Settings") then
        callbacks.save_settings()
        show_settings = false
    end
    theme_manager.pop_positive_style(ctx)

    -- Reset to defaults
    reaper.ImGui_SameLine(ctx)
    theme_manager.push_danger_style(ctx, theme_state)
    if reaper.ImGui_Button(ctx, "Reset Defaults") then
        theme_state.bg_u32          = theme_manager.theme_pack(defaults.bg)
        theme_state.accent_u32      = theme_manager.theme_pack(defaults.accent)
        theme_state.text_u32        = theme_manager.theme_pack(defaults.text)
        theme_state.danger_u32      = theme_manager.theme_pack(defaults.danger)
        theme_state.positive_u32    = theme_manager.theme_pack(defaults.positive)
        theme_state.slider_grab_u32 = theme_manager.theme_pack(defaults.slider_grab)
        theme_state.apply_btn_u32   = theme_manager.theme_pack(defaults.apply_btn)
        theme_state.frame_bg_u32    = theme_manager.theme_pack(defaults.frame_bg)
        theme_state.check_mark_u32  = theme_manager.theme_pack(defaults.check_mark)
    end
    theme_manager.pop_danger_style(ctx)

    return show_settings
end

return UISettings

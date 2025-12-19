-- @description Humanize Kontakt Tune Parameter
-- @author drvlat
-- @version 0.0.2
-- @about
--      This package Huamnizes Kontakt #0016 Host parameter (should be assigned to Tune)
-- @changelog
--      0.0.2 - Initial release


local reaper = reaper

-- Seed the random number generator with current time to make it non-deterministic
math.randomseed(os.time())

-- Store the previous value to ensure we don't repeat it
local previous_value = nil

-- Function to check if an FX name contains "kontakt" (case insensitive)
local function is_kontakt_instance(track, fx_index)
    local retval, fx_name = reaper.TrackFX_GetFXName(track, fx_index)
    if retval then
        return string.lower(fx_name):find("kontakt") ~= nil
    end
    return false
end

-- Function to find Kontakt instance on a track
local function find_kontakt_on_track(track)
    local fx_count = reaper.TrackFX_GetCount(track)
    for fx_idx = 0, fx_count - 1 do
        if is_kontakt_instance(track, fx_idx) then
            return fx_idx
        end
    end
    return nil
end

-- Main execution
local selected_track_count = reaper.CountSelectedTracks(0)

if selected_track_count == 0 then
    return
end

-- Iterate through selected tracks
for i = 0, selected_track_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)

    if track then
        -- Find Kontakt instance on this track
        local kontakt_fx_index = find_kontakt_on_track(track)

        if kontakt_fx_index then
            -- Convert desired Kontakt range (-0.15 to +0.15) to normalized range (0.0 to 1.0)
            -- Kontakt's parameter range is -36 to +36
            local kontakt_min = -36
            local kontakt_max = 36
            -- Calculate normalized values for our desired range
            local desired_min = -0.15
            local desired_max = 0.15
            -- Map desired range to normalized range
            local norm_min = (desired_min - kontakt_min) / (kontakt_max - kontakt_min)  -- ≈ 0.4979
            local norm_max = (desired_max - kontakt_min) / (kontakt_max - kontakt_min)  -- ≈ 0.5021

            -- Generate a random value ensuring it's different from the previous value
            local random_value
            local attempts = 0
            repeat
                random_value = norm_min + (math.random() * (norm_max - norm_min))
                attempts = attempts + 1
                -- Limit attempts to avoid infinite loop
            until (previous_value == nil or math.abs(random_value - previous_value) > 0.001) or attempts > 100

            -- Update the previous value
            previous_value = random_value

            -- Set host automation parameter 0016 on the Kontakt FX
            -- Send to parameter 16 directly without adding 0x1000000
            local host_param_idx = 16  -- Host parameter 0016

            -- Send the value to the host automation parameter on the Kontakt instance
            reaper.TrackFX_SetParam(track, kontakt_fx_index, host_param_idx, random_value)
        end
    end
end
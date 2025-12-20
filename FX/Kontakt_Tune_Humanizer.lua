-- @noindex

local reaper = reaper

-- Seed the random number generator with a more precise value to ensure different results
-- even when script runs multiple times in quick succession
local function better_seed()
    -- Combine current time with clock ticks for more entropy
    local time_seed = os.time()
    local clock_seed = math.floor(os.clock() * 1000) % 1000
    -- Use a simple hash function to combine the seeds
    local combined_seed = time_seed * 1000 + clock_seed
    
    -- Add some additional entropy based on memory address (if available)
    local mem_addr_str = tostring({}):match("0x(%x+)")
    if mem_addr_str then
        combined_seed = combined_seed + tonumber(mem_addr_str, 16) % 1000
    else
        -- Fallback entropy if memory address extraction fails
        combined_seed = combined_seed + math.random(1, 999)
    end
    
    return combined_seed
end

math.randomseed(better_seed())

-- Store the previous value to ensure we don't repeat it
local previous_value = nil

-- Function to generate Gaussian distributed random numbers using Box-Muller transform
-- This creates a more natural, bell-curve distribution centered around 0
local function gaussian_random(mean, stddev)
    -- Generate two uniform random numbers with additional entropy
    local u1 = 0.0
    local u2 = 0.0
    
    -- Add some additional entropy by generating a few random numbers first
    for i = 1, 3 do
        math.random()
    end
    
    -- Ensure we don't get 0 (which would cause log(0) issues)
    repeat
        u1 = math.random()
    until u1 > 0.0001
    
    repeat
        u2 = math.random()
    until u2 > 0.0001
    
    -- Add some time-based micro-variations
    local micro_time = (os.clock() % 1.0) * 0.0001
    u1 = (u1 + micro_time) % 1.0
    if u1 <= 0.0001 then u1 = 0.0001 end
    
    -- Box-Muller transform to convert uniform to Gaussian distribution
    local z0 = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)
    
    -- Return the value with the specified mean and standard deviation
    return mean + z0 * stddev
end

-- Function to generate a random value with better distribution
-- Uses Gaussian distribution centered in the middle of our range
local function generate_balanced_random(min_val, max_val)
    local center = (min_val + max_val) / 2
    local range = max_val - min_val
    
    -- Use a smaller standard deviation to keep most values within our desired range
    -- About 95% of values will fall within ±2*stddev of the center
    local stddev = range / 4
    
    local value
    local attempts = 0
    
    repeat
        value = gaussian_random(center, stddev)
        attempts = attempts + 1
        
        -- Clamp to our desired range to ensure we don't exceed limits
        if value < min_val then
            value = min_val
        elseif value > max_val then
            value = max_val
        end
        
        -- Limit attempts to avoid infinite loop
    until (previous_value == nil or math.abs(value - previous_value) > 0.001) or attempts > 100
    
    return value
end

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

            -- Generate a random value using Gaussian distribution for more natural variation
            -- This will center values around the middle of our range with most values close to center
            local random_value = generate_balanced_random(norm_min, norm_max)

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
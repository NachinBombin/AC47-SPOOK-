-- AC-47 Spooky — passby sound aliases + spatial helper
-- Mirrors cl_gau_passby_sounds.lua from the AC-130 addon exactly.
-- All bullet passby + fire sounds live here.
-- cl_init.lua calls AC47EmitSound(); this file defines it.

if not CLIENT then return end

-- ─── Spatial emit helper ─────────────────────────────────────────────────────
-- Plays the sound at the listener eye offset 32 units toward the source.
-- This keeps sounds audible at any distance while staying directional,
-- working around Source's attenuation cutoff at range.
function AC47EmitSound(name, pos, level, pitch, volume)
    local view = GetViewEntity()
    if not IsValid(view) then return end
    local eye = view:EyePos()
    local dir = pos - eye
    dir:Normalize()
    sound.Play(
        name,
        eye + dir * 32,
        level  or 80,
        pitch  or 100,
        volume or 1
    )
end

-- ─── alias helper ────────────────────────────────────────────────────────────
local function FastList(name, ext, num)
    local list = {}
    for i = 1, num do
        list[i] = name .. (i < 10 and "0" .. i or tostring(i)) .. "." .. ext
    end
    return list
end

-- ─── M134 .30-cal passby aliases ─────────────────────────────────────────────
-- Using the same RBO .50cal library as the AC-130 (closest acoustic match).
-- Prefixed with ac47_ to avoid collisions if both addons are loaded.

sound.Add({
    name    = "ac47_passby_close",
    channel = CHAN_STATIC,
    volume  = 1, level = 80, pitch = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_close_", "ogg", 12)
})
sound.Add({
    name    = "ac47_passby_medium",
    channel = CHAN_STATIC,
    volume  = 1, level = 80, pitch = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_mid_", "ogg", 12)
})
sound.Add({
    name    = "ac47_passby_medium_2",
    channel = CHAN_STATIC,
    volume  = 1, level = 80, pitch = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_mid_new_", "ogg", 17)
})
sound.Add({
    name    = "ac47_passby_hiss_far",
    channel = CHAN_STATIC,
    volume  = 1, level = 80, pitch = 100,
    sound   = FastList("rbo/passbys/squad/hiss/passby_crack_hiss_far_", "ogg", 29)
})
sound.Add({
    name    = "ac47_passby_far",
    channel = CHAN_STATIC,
    volume  = 1, level = 80, pitch = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_far_new_", "ogg", 19)
})

-- ─── M134 fire burst (heard from the plane, not per-bullet) ─────────────────
-- Used by the plane init.lua via EmitSpatialSound, which sends it to all
-- clients as a one-shot sound.Play at a position near the player.
-- This is the spatial "BRRT" heard from the ground — same pattern as
-- the AC-130's GAU_BRRT_SOUNDS played via EmitSpatialSound on burst start.
sound.Add({
    name    = "ac47_m134_burst",
    channel = CHAN_STATIC,
    volume  = 1, level = 120, pitch = 100,
    sound   = {
        "lfs/tfre_ac47/m134_shoot.wav",
    }
})

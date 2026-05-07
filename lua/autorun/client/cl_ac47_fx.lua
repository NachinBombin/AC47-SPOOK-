-- cl_ac47_fx.lua
-- Always-loaded client autorun for AC-47 Spooky.
-- Handles muzzle flash rendering and per-gun fire sound stacking.
-- MUST live here (not in cl_init.lua) so hooks are registered
-- before the plane entity enters PVS.

if not CLIENT then return end

-- ============================================================
-- MUZZLE FLASH
-- Server sends "ac47_muzzle_flash" with world position.
-- We draw two additive sprites for one frame in
-- PostDrawTranslucentRenderables. Zero particles, zero effects.
-- ============================================================

local mat_flash_core  = Material("sprites/glow04_noz")
local mat_flash_bloom = Material("sprites/light_glow02_add")

-- Queue: { pos=Vector, expire=number }
local muzzle_flashes = {}

net.Receive("ac47_muzzle_flash", function()
    local pos = net.ReadVector()
    muzzle_flashes[#muzzle_flashes + 1] = {
        pos    = pos,
        expire = UnPredictedCurTime() + 0.05,
    }
end)

hook.Add("PostDrawTranslucentRenderables", "ac47_muzzle_flash_draw", function(depth, skybox)
    if depth or skybox then return end
    local ct    = UnPredictedCurTime()
    local count = #muzzle_flashes
    if count == 0 then return end

    local cam  = EyePos()
    local keep = {}

    for i = 1, count do
        local f = muzzle_flashes[i]
        if ct > f.expire then continue end

        local dist = cam:Distance(f.pos)
        -- Minimum visible size even from 6000u altitude.
        -- Scales gently with distance, hard capped at 80u.
        local sz = math.Clamp(22 + dist * 0.005, 22, 80)

        -- Hot white-yellow core
        render.SetMaterial(mat_flash_core)
        render.DrawSprite(f.pos, sz * 0.55, sz * 0.55, Color(255, 245, 180, 230))

        -- Orange bloom halo
        render.SetMaterial(mat_flash_bloom)
        render.DrawSprite(f.pos, sz, sz, Color(255, 150, 30, 180))

        keep[#keep + 1] = f
    end

    muzzle_flashes = keep
end)

-- ============================================================
-- GUN FIRE SOUNDS  —  3 independent stacking channels
--
-- Problem: CreateSound(ent, path) deduplicates by (entity, path).
-- Calling it for guns 1, 2, 3 on the same entity with the same
-- wav returns/reuses the same DSP channel — only one plays.
--
-- Fix: maintain a table of CSoundPatch handles keyed by
-- [entIndex][gunIdx]. Each slot is its own CreateSound instance
-- on the PLANE entity but we force unique channel allocation by
-- using three different sound-alias names that all point to the
-- same wav. The aliases are defined below with sound.Add so
-- Source treats them as separate sounds.
--
-- Alias trick: sound.Add entries with different names but same
-- wav file. Each name gets its own mixer channel entry.
-- ============================================================

local GUN_SOUND_ALIASES = {
    "ac47_gun1_fire_loop",
    "ac47_gun2_fire_loop",
    "ac47_gun3_fire_loop",
}

-- Register 3 distinct sound aliases pointing to the same wav.
-- CHAN_STATIC lets multiple instances coexist without cutoff.
for i, alias in ipairs(GUN_SOUND_ALIASES) do
    sound.Add({
        name    = alias,
        channel = CHAN_STATIC,
        volume  = 1.0,
        level   = 150,   -- audible radius for a gunship cannon
        pitch   = 100,
        sound   = { "lfs/tfre_ac47/m134_shoot.wav" },
    })
end

local ac47_gun_loops = {}   -- [entIndex][gunIdx] = CSoundPatch

net.Receive("ac47_gun_sound", function()
    local entIndex = net.ReadUInt(16)
    local gunIdx   = net.ReadUInt(8)
    local isStart  = net.ReadBool()

    if isStart then
        local ent = Entity(entIndex)
        if not IsValid(ent) then return end

        ac47_gun_loops[entIndex] = ac47_gun_loops[entIndex] or {}
        -- Already playing this gun slot — do not double-start.
        if ac47_gun_loops[entIndex][gunIdx] then return end

        local alias = GUN_SOUND_ALIASES[gunIdx] or GUN_SOUND_ALIASES[1]
        local snd   = CreateSound(ent, alias)
        if snd then
            snd:SetSoundLevel(150)   -- level 150 = very loud, heard across the map
            snd:PlayEx(1.0, 100)
            ac47_gun_loops[entIndex][gunIdx] = snd
        end
    else
        local slots = ac47_gun_loops[entIndex]
        if not slots then return end
        local snd = slots[gunIdx]
        if snd then
            snd:Stop()
            slots[gunIdx] = nil
        end
    end
end)

hook.Add("EntityRemoved", "ac47_gun_fx_cleanup", function(ent)
    if not IsValid(ent) then return end
    local idx   = ent:EntIndex()
    local slots = ac47_gun_loops[idx]
    if slots then
        for _, snd in pairs(slots) do
            if snd then snd:Stop() end
        end
    end
    ac47_gun_loops[idx] = nil
end)

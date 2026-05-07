-- cl_ac47_fx.lua
-- Always-loaded client autorun for AC-47 Spooky.
-- Muzzle flash + 3-channel stacking gun sounds.
-- Lives in autorun/client so it is loaded unconditionally,
-- regardless of whether the plane entity is in PVS.

if not CLIENT then return end

-- ============================================================
-- MUZZLE FLASH
-- Server broadcasts "ac47_muzzle_flash" with the world-space
-- muzzle position. We draw two additive sprites in
-- PostDrawTranslucentRenderables for ~50ms.
--
-- Material names verified against base HL2/GMod vpk:
--   sprites/glow04        — small hot core glow
--   sprites/light_glow02  — wide soft bloom
-- ============================================================

local mat_core  = Material("sprites/glow04")
local mat_bloom = Material("sprites/light_glow02")

local muzzle_flashes = {}   -- { pos, expire }

net.Receive("ac47_muzzle_flash", function()
    muzzle_flashes[#muzzle_flashes + 1] = {
        pos    = net.ReadVector(),
        expire = UnPredictedCurTime() + 0.05,
    }
end)

hook.Add("PostDrawTranslucentRenderables", "ac47_muzzle_flash_draw", function(depth, skybox)
    if depth or skybox then return end
    if #muzzle_flashes == 0 then return end

    local ct   = UnPredictedCurTime()
    local eye  = EyePos()
    local keep = {}

    for _, f in ipairs(muzzle_flashes) do
        if ct > f.expire then continue end

        -- Scale with distance so flash is visible from altitude
        local dist = eye:Distance(f.pos)
        local sz   = math.Clamp(24 + dist * 0.006, 24, 90)

        render.SetMaterial(mat_core)
        render.DrawSprite(f.pos, sz * 0.5, sz * 0.5, Color(255, 240, 160, 240))

        render.SetMaterial(mat_bloom)
        render.DrawSprite(f.pos, sz, sz, Color(255, 140, 20, 160))

        keep[#keep + 1] = f
    end

    muzzle_flashes = keep
end)

-- ============================================================
-- GUN FIRE SOUNDS  —  3 independent stacking channels
--
-- Root cause: CreateSound(ent, path) deduplicates by
-- (entity, soundpath). All 3 guns on the same entity with the
-- same wav string share one DSP channel — only one plays.
--
-- Fix A: three distinct sound.Add aliases (different names,
--         same wav) so Source allocates 3 separate channels.
-- Fix B: pass "#aliasname" to CreateSound — the # prefix is
--         required to tell GMod to resolve a sound.Add entry
--         instead of treating the string as a raw file path.
--         Without #, CreateSound silently returns nil.
-- ============================================================

local ALIASES = {
    "#ac47_gun1_fire",
    "#ac47_gun2_fire",
    "#ac47_gun3_fire",
}

sound.Add({ name = "ac47_gun1_fire", channel = CHAN_STATIC, volume = 1, level = 150, pitch = 100, sound = { "lfs/tfre_ac47/m134_shoot.wav" } })
sound.Add({ name = "ac47_gun2_fire", channel = CHAN_STATIC, volume = 1, level = 150, pitch = 100, sound = { "lfs/tfre_ac47/m134_shoot.wav" } })
sound.Add({ name = "ac47_gun3_fire", channel = CHAN_STATIC, volume = 1, level = 150, pitch = 100, sound = { "lfs/tfre_ac47/m134_shoot.wav" } })

local gun_loops = {}   -- [entIndex][gunIdx] = CSoundPatch

net.Receive("ac47_gun_sound", function()
    local entIndex = net.ReadUInt(16)
    local gunIdx   = net.ReadUInt(8)
    local isStart  = net.ReadBool()

    if isStart then
        local ent = Entity(entIndex)
        if not IsValid(ent) then return end

        gun_loops[entIndex] = gun_loops[entIndex] or {}
        if gun_loops[entIndex][gunIdx] then return end  -- already running

        local snd = CreateSound(ent, ALIASES[gunIdx] or ALIASES[1])
        if not snd then return end
        snd:SetSoundLevel(150)
        snd:PlayEx(1.0, 100)
        gun_loops[entIndex][gunIdx] = snd
    else
        local slots = gun_loops[entIndex]
        if not slots then return end
        local snd = slots[gunIdx]
        if snd then snd:Stop() end
        slots[gunIdx] = nil
    end
end)

hook.Add("EntityRemoved", "ac47_gun_sound_cleanup", function(ent)
    if not IsValid(ent) then return end
    local idx   = ent:EntIndex()
    local slots = gun_loops[idx]
    if slots then
        for _, snd in pairs(slots) do
            if snd then snd:Stop() end
        end
    end
    gun_loops[idx] = nil
end)

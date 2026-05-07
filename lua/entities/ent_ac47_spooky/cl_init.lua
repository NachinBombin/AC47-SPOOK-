include("shared.lua")
include("cl_trailsystem.lua")

ac47_ambient_loops = ac47_ambient_loops or {}

game.AddParticles("particles/fire_01.pcf")
PrecacheParticleSystem("fire_medium_02")

-- ============================================================
-- GUN FIRE SOUND
-- SetSoundLevel(110) is required — without it CreateSound uses
-- the WAV header default which is too quiet at any distance.
-- ============================================================

local M134_FIRE_SOUND = "lfs/tfre_ac47/m134_shoot.wav"
local ac47_gun_loops  = {}

net.Receive("ac47_gun_sound", function()
    local entIndex = net.ReadUInt(16)
    local gunIdx   = net.ReadUInt(8)
    local isStart  = net.ReadBool()

    if isStart then
        local ent = Entity(entIndex)
        if not IsValid(ent) then return end
        ac47_gun_loops[entIndex] = ac47_gun_loops[entIndex] or {}
        if ac47_gun_loops[entIndex][gunIdx] then return end
        local snd = CreateSound(ent, M134_FIRE_SOUND)
        if snd then
            snd:SetSoundLevel(110)   -- FIX: boost audible radius, was missing entirely
            snd:PlayEx(1.0, 100)
            ac47_gun_loops[entIndex][gunIdx] = snd
        end
    else
        if not ac47_gun_loops[entIndex] then return end
        local snd = ac47_gun_loops[entIndex][gunIdx]
        if snd then
            snd:Stop()
            ac47_gun_loops[entIndex][gunIdx] = nil
        end
    end
end)

hook.Add("EntityRemoved", "ac47_gun_loop_cleanup", function(ent)
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

-- ============================================================
-- MUZZLE FLASH — CLIENT SPRITE RENDERER
-- Receives a world position from the server net message.
-- Stores it in a queue; PostDrawTranslucentRenderables draws
-- each flash as a single additive sprite and expires it after
-- one rendered frame. Zero particles, zero explosion effects.
-- ============================================================

local mat_flash  = Material("sprites/light_glow02_add")
local mat_flash2 = Material("sprites/glow04_noz")

-- Each entry: { pos=Vector, expire=time }
local muzzle_flashes = {}

net.Receive("ac47_muzzle_flash", function()
    local pos = net.ReadVector()
    -- Expire after 1 rendered frame worth of time (~0.033s at 30fps).
    -- We use a short but non-zero window so even low-fps clients see it.
    muzzle_flashes[#muzzle_flashes + 1] = {
        pos    = pos,
        expire = UnPredictedCurTime() + 0.04,
    }
end)

hook.Add("PostDrawTranslucentRenderables", "ac47_muzzle_flash_draw", function(depth, skybox)
    if depth or skybox then return end
    local ct    = UnPredictedCurTime()
    local count = #muzzle_flashes
    if count == 0 then return end

    local cam = EyePos()
    local keep = {}

    for i = 1, count do
        local f = muzzle_flashes[i]
        if ct > f.expire then continue end

        local dist  = cam:Distance(f.pos)
        -- Scale the sprite relative to view distance so it stays visible
        -- from high altitude but doesn't dominate when viewed up close.
        -- Base size 18 units, scales slightly with distance, hard-capped.
        local sz = math.Clamp(18 + dist * 0.003, 18, 40)

        -- Inner hot core — white/yellow additive
        render.SetMaterial(mat_flash2)
        render.DrawSprite(f.pos, sz * 0.6, sz * 0.6, Color(255, 240, 160, 220))

        -- Outer glow bloom
        render.SetMaterial(mat_flash)
        render.DrawSprite(f.pos, sz, sz, Color(255, 160, 40, 160))

        keep[#keep + 1] = f
    end

    muzzle_flashes = keep
end)

-- ============================================================
-- DAMAGE TIERS
-- ============================================================

local TIER_OFFSETS = {
    [1] = {
        Vector(  0,   0,  20),
    },
    [2] = {
        Vector(  0,   0,  20),
        Vector( 80,   0,   5),
        Vector(-80,   0,   5),
    },
    [3] = {
        Vector(  0,   0,  20),
        Vector( 70,   0,   5),
        Vector(-70,   0,   5),
        Vector(  0, 110,  10),
        Vector(  0,-110,  10),
        Vector(  0,   0, -10),
    },
}

local TIER_BURST_DELAY = { [1] = 5.0, [2] = 2.5, [3] = 0.9 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

local PlaneStates = {}

local function BurstAt(wPos, tier)
    local ed = EffectData()
    ed:SetOrigin(wPos)
    ed:SetScale(tier == 3 and math.Rand(0.8, 1.4) or math.Rand(0.4, 0.9))
    ed:SetMagnitude(1) ed:SetRadius(tier * 20)
    util.Effect("Explosion", ed)
    local ed2 = EffectData()
    ed2:SetOrigin(wPos) ed2:SetNormal(Vector(0,0,1))
    ed2:SetScale(tier * 0.3) ed2:SetMagnitude(tier * 0.4) ed2:SetRadius(18)
    util.Effect("ManhackSparks", ed2)
    if tier >= 2 then
        local ed3 = EffectData()
        ed3:SetOrigin(wPos) ed3:SetNormal(VectorRand()) ed3:SetScale(0.6)
        util.Effect("ElectricSpark", ed3)
    end
end

local function SpawnBurstFX(ent, count, tier)
    if not IsValid(ent) then return end
    local pos = ent:GetPos()
    local ang = ent:GetAngles()
    for _ = 1, count do
        local wPos = LocalToWorld(
            Vector(math.Rand(-90,90), math.Rand(-120,70), math.Rand(0,30)),
            Angle(0,0,0), pos, ang
        )
        BurstAt(wPos, tier)
    end
    if tier == 3 then
        for _, side in ipairs({ Vector(110,0,0), Vector(-110,0,0) }) do
            local wPos = LocalToWorld(side, Angle(0,0,0), pos, ang)
            local ed = EffectData()
            ed:SetOrigin(wPos) ed:SetScale(0.7) ed:SetMagnitude(1) ed:SetRadius(25)
            util.Effect("Explosion", ed)
        end
    end
end

local function StopParticles(state)
    if not state.particles then return end
    for _, p in ipairs(state.particles) do
        if IsValid(p) then p:StopEmission() end
    end
    state.particles = {}
end

local function ApplyFlameParticles(ent, state, tier)
    StopParticles(state)
    state.tier = tier
    if not IsValid(ent) or tier == 0 then return end
    for _, off in ipairs(TIER_OFFSETS[tier]) do
        local p = ent:CreateParticleEffect("fire_medium_02", PATTACH_ABSORIGIN_FOLLOW, 0)
        if IsValid(p) then
            p:SetControlPoint(0, ent:LocalToWorld(off))
            table.insert(state.particles, p)
        end
    end
    state.nextBurst = CurTime() + (TIER_BURST_DELAY[tier] or 4)
end

net.Receive("ac47_plane_damage_tier", function()
    local entIndex = net.ReadUInt(16)
    local tier     = net.ReadUInt(2)
    local ent      = Entity(entIndex)

    AC47TrailSystem_SetTier(entIndex, tier)

    if tier == 0 then
        local snd = ac47_ambient_loops[entIndex]
        if snd then snd:Stop() end
        ac47_ambient_loops[entIndex] = nil
        local slots = ac47_gun_loops[entIndex]
        if slots then
            for _, gsnd in pairs(slots) do
                if gsnd then gsnd:Stop() end
            end
        end
        ac47_gun_loops[entIndex] = nil
    end

    local state = PlaneStates[entIndex]
    if not state then
        state = { tier = 0, particles = {}, nextBurst = 0 }
        PlaneStates[entIndex] = state
    end

    if state.tier == tier then return end

    if IsValid(ent) then
        ApplyFlameParticles(ent, state, tier)
        if tier > 0 then SpawnBurstFX(ent, TIER_BURST_COUNT[tier] or 1, tier) end
    else
        state.tier         = tier
        state.pendingApply = true
    end
end)

hook.Add("Think", "ac47_plane_damage_fx", function()
    local ct = CurTime()
    for entIndex, state in pairs(PlaneStates) do
        local ent = Entity(entIndex)
        if not IsValid(ent) then
            StopParticles(state)
            PlaneStates[entIndex] = nil
        else
            if state.pendingApply then
                state.pendingApply = false
                ApplyFlameParticles(ent, state, state.tier)
            end
            if state.tier > 0 then
                local pos     = ent:GetPos()
                local ang     = ent:GetAngles()
                local offsets = TIER_OFFSETS[state.tier]
                for i, p in ipairs(state.particles) do
                    if IsValid(p) and offsets[i] then
                        p:SetControlPoint(0, LocalToWorld(offsets[i], Angle(0,0,0), pos, ang))
                    end
                end
                if ct >= state.nextBurst then
                    SpawnBurstFX(ent, TIER_BURST_COUNT[state.tier] or 1, state.tier)
                    state.nextBurst = ct + (TIER_BURST_DELAY[state.tier] or 4)
                end
            end
        end
    end
end)

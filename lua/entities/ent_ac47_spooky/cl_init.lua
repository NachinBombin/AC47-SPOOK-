include("shared.lua")
include("cl_trailsystem.lua")

ac47_ambient_loops = ac47_ambient_loops or {}

-- Gun sound handles: ac47_gun_sounds[entIndex][gunIdx] = CSoundPatch
-- One CreateSound handle per gun. Each gun has its own wav so Source
-- never confuses them. Start/Stop are called on the exact handle.
ac47_gun_sounds = ac47_gun_sounds or {}

game.AddParticles("particles/fire_01.pcf")
PrecacheParticleSystem("fire_medium_02")

-- Wav files that match each gun index 1/2/3
local GUN_WAVS = {
    "lfs/tfre_ac47/m134_shoot.wav",
    "lfs/tfre_ac47/m134_shoot2.wav",
    "lfs/tfre_ac47/m134_shoot3.wav",
}

-- ============================================================
-- ENGINE AMBIENT LOOP
-- ============================================================

net.Receive("ac47_plane_spatial_sound", function()
    local sndPath  = net.ReadString()
    local nearPos  = net.ReadVector()
    local level    = net.ReadUInt(8)
    local pitch    = net.ReadUInt(8)
    local volume   = net.ReadFloat()
    local entIndex = net.ReadUInt(16)

    local isLoop = string.find(sndPath, "rpm") or string.find(sndPath, "engine_far")

    if isLoop then
        if not ac47_ambient_loops[entIndex] then
            local ent = Entity(entIndex)
            if IsValid(ent) then
                local snd = CreateSound(ent, sndPath)
                if snd then
                    snd:SetSoundLevel(130)
                    snd:PlayEx(volume, pitch)
                    ac47_ambient_loops[entIndex] = snd
                end
            end
        end
    else
        -- One-shot positional sounds (e.g. engine_start)
        sound.Play(sndPath, nearPos, level, pitch, volume)
    end
end)

-- ============================================================
-- GUN SOUNDS
-- Each gun index owns one CreateSound handle on the entity.
-- Server sends isStart=true when the gun begins firing,
-- isStart=false when it stops. The dedup guard in BroadcastGunSound
-- means we only ever receive a real state change.
-- ============================================================

net.Receive("ac47_gun_sound", function()
    local entIndex = net.ReadUInt(16)
    local gunIdx   = net.ReadUInt(8)
    local isStart  = net.ReadBool()

    local ent = Entity(entIndex)
    if not IsValid(ent) then return end

    if not ac47_gun_sounds[entIndex] then
        ac47_gun_sounds[entIndex] = {}
    end
    local handles = ac47_gun_sounds[entIndex]

    if isStart then
        -- Only create a new handle if one isn't already playing
        if not handles[gunIdx] then
            local wav = GUN_WAVS[gunIdx]
            if not wav then return end
            local snd = CreateSound(ent, wav)
            if snd then
                snd:SetSoundLevel(150)
                snd:PlayEx(1.0, 100)
                handles[gunIdx] = snd
            end
        end
    else
        if handles[gunIdx] then
            handles[gunIdx]:Stop()
            handles[gunIdx] = nil
        end
    end
end)

-- Clean up all sound handles when the entity is removed
hook.Add("EntityRemoved", "ac47_gun_sound_cleanup", function(ent)
    if not IsValid(ent) then return end
    local idx     = ent:EntIndex()
    local handles = ac47_gun_sounds[idx]
    if handles then
        for _, snd in pairs(handles) do
            if snd then snd:Stop() end
        end
        ac47_gun_sounds[idx] = nil
    end
end)

hook.Add("EntityRemoved", "ac47_ambient_loop_cleanup", function(ent)
    if not IsValid(ent) then return end
    local idx = ent:EntIndex()
    local snd = ac47_ambient_loops[idx]
    if snd then snd:Stop() end
    ac47_ambient_loops[idx] = nil
end)

-- ============================================================
-- DAMAGE TIERS
-- ============================================================

local TIER_OFFSETS = {
    [1] = { Vector(  0,   0,  20) },
    [2] = { Vector(  0,   0,  20), Vector( 80,   0,   5), Vector(-80,   0,   5) },
    [3] = {
        Vector(  0,   0,  20),
        Vector( 70,   0,   5), Vector(-70,   0,   5),
        Vector(  0, 110,  10), Vector(  0,-110,  10),
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
        -- Stop engine loop
        local snd = ac47_ambient_loops[entIndex]
        if snd then snd:Stop() end
        ac47_ambient_loops[entIndex] = nil
        -- Stop ALL gun sounds (plane is dead/silent)
        local handles = ac47_gun_sounds[entIndex]
        if handles then
            for _, h in pairs(handles) do
                if h then h:Stop() end
            end
            ac47_gun_sounds[entIndex] = nil
        end
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

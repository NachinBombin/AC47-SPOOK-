include("shared.lua")

local mat_beam = Material("effects/laser1")

local MUZZLE_VEL = 56000
local MAX_DIST   = 45000
local MIN_SPEED  = 200

-- Per-bullet ring buffer (client-side projectile simulation for tracers + flyby)
ac47_m134_store = ac47_m134_store or {
    last_idx           = 0,
    buffer_size        = 128,
    buffer             = {},
    active_projectiles = {},
}
if #ac47_m134_store.buffer == 0 then
    for i = 1, ac47_m134_store.buffer_size do
        ac47_m134_store.buffer[i] = {
            hit     = true,
            pos     = Vector(0,0,0),
            old_pos = Vector(0,0,0),
            vel     = Vector(0,0,0),
            speed   = 0,
            flyby_played = false,
        }
    end
end

-- Per-entity ambient loop table: entIndex -> CSoundPatch
-- Managed here so we can stop it when the plane dies or is removed.
-- NOTE: ac47_plane_damage_tier net.Receive lives in ent_ac47_spooky/cl_init.lua only.
-- Do NOT add a second receiver here -- GMod silently overwrites it and only the
-- last-registered handler fires.  Ambient loop teardown is handled there.
ac47_ambient_loops = ac47_ambient_loops or {}

-- ─── Bullet spawn ───────────────────────────────────────────────────────────
net.Receive("ac47_m134_bullet_new", function()
    local pos = net.ReadVector()
    local vel = net.ReadVector()  -- full velocity vector (Dir * MUZZLE_VEL)

    local store = ac47_m134_store
    store.last_idx = (store.last_idx % store.buffer_size) + 1
    local slot = store.buffer[store.last_idx]
    slot.hit          = false
    slot.pos          = pos
    slot.old_pos      = pos
    slot.vel          = vel
    slot.speed        = vel:Length()
    slot.flyby_played = false
    store.active_projectiles[store.last_idx] = slot
end)

-- ─── Bullet impact ───────────────────────────────────────────────────────────
local IMPACT_SOUNDS = {
    "physics/concrete/impact_bullet1.wav",
    "physics/concrete/impact_bullet2.wav",
    "physics/concrete/impact_bullet3.wav",
    "physics/dirt/impact_bullet1.wav",
    "physics/dirt/impact_bullet2.wav",
    "physics/dirt/impact_bullet3.wav",
    "physics/metal/metal_solid_impact_bullet1.wav",
    "physics/metal/metal_solid_impact_bullet2.wav",
    "physics/metal/metal_solid_impact_bullet3.wav",
}

net.Receive("ac47_bullet_impact", function()
    local hitPos    = net.ReadVector()
    local hitNormal = net.ReadVector()
    local sndIdx    = net.ReadUInt(4)
    sndIdx = math.Clamp(sndIdx, 1, #IMPACT_SOUNDS)

    local ed = EffectData()
    ed:SetOrigin(hitPos)
    ed:SetNormal(hitNormal)
    util.Effect("Impact", ed)

    local ed2 = EffectData()
    ed2:SetOrigin(hitPos)
    ed2:SetNormal(hitNormal)
    ed2:SetScale(0.5)
    util.Effect("Ricochet", ed2)

    sound.Play(IMPACT_SOUNDS[sndIdx], hitPos, 75, math.random(95, 110), 1.0)
end)

-- ─── Spatial plane sound + ambient loop management ──────────────────────────────
net.Receive("ac47_plane_spatial_sound", function()
    local sndPath  = net.ReadString()
    local nearPos  = net.ReadVector()
    local level    = net.ReadUInt(8)
    local pitch    = net.ReadUInt(8)
    local volume   = net.ReadFloat()
    local entIndex = net.ReadUInt(16)

    local ent = Entity(entIndex)

    local isLoop = string.find(sndPath, "engine") or
                   string.find(sndPath, "rpm")    or
                   string.find(sndPath, "far")

    if isLoop then
        if not ac47_ambient_loops[entIndex] then
            if IsValid(ent) then
                local snd = CreateSound(ent, sndPath)
                if snd then
                    snd:SetSoundLevel(level)
                    snd:PlayEx(volume, pitch)
                    ac47_ambient_loops[entIndex] = snd
                end
            end
        end
    else
        sound.Play(sndPath, nearPos, level, pitch, volume)
    end
end)

-- Stop ambient loop when plane is removed from the world.
-- Tier-0 (destroy) teardown is handled in ent_ac47_spooky/cl_init.lua.
hook.Add("EntityRemoved", "ac47_ambient_loop_cleanup", function(ent)
    if not IsValid(ent) then return end
    local idx = ent:EntIndex()
    local snd = ac47_ambient_loops[idx]
    if snd then snd:Stop() end
    ac47_ambient_loops[idx] = nil
end)

-- ─── Bullet Think: move projectiles, flyby sounds ──────────────────────────────
local FLYBY_CLOSE  = 256
local FLYBY_MEDIUM = 768
local FLYBY_FAR    = 2500

hook.Add("Think", "ac47_m134_bullet_think", function()
    local store   = ac47_m134_store
    local ft      = FrameTime()
    local view    = GetViewEntity()
    local eyePos  = IsValid(view) and view:EyePos() or Vector(0,0,0)

    for idx, slot in pairs(store.active_projectiles) do
        if slot.hit then
            store.active_projectiles[idx] = nil
            continue
        end

        slot.old_pos = Vector(slot.pos.x, slot.pos.y, slot.pos.z)
        slot.pos     = slot.pos + slot.vel * ft

        if slot.speed < MIN_SPEED then
            slot.hit = true
            store.active_projectiles[idx] = nil
            continue
        end

        local tr = util.QuickTrace(slot.old_pos, slot.pos - slot.old_pos, NULL)
        if tr.Hit then
            slot.hit = true
            store.active_projectiles[idx] = nil
            continue
        end

        if not slot.flyby_played then
            local dist  = slot.pos:Distance(eyePos)
            local toEye = eyePos - slot.pos
            local passing = toEye:Dot(slot.vel) < 0

            if passing then
                slot.flyby_played = true
                local snd
                if dist < FLYBY_CLOSE then
                    snd = "ac47_passby_close"
                elseif dist < FLYBY_MEDIUM then
                    snd = math.random(2) == 1 and "ac47_passby_medium" or "ac47_passby_medium_2"
                elseif dist < FLYBY_FAR then
                    snd = "ac47_passby_hiss_far"
                else
                    snd = "ac47_passby_far"
                end
                AC47EmitSound(snd, slot.pos, 80, 100, 1.0)
            end
        end
    end
end)

-- ─── Tracer render ────────────────────────────────────────────────────────────
hook.Add("PostDrawTranslucentRenderables", "ac47_m134_bullet_draw", function(bDepth, bSkybox)
    if bSkybox then return end
    local store = ac47_m134_store
    if not next(store.active_projectiles) then return end
    render.SetMaterial(mat_beam)
    for _, slot in pairs(store.active_projectiles) do
        if slot.hit then continue end
        render.DrawBeam(slot.old_pos, slot.pos, 2, 0, 1, Color(255, 220, 150, 200))
    end
end)

function ENT:Draw() end
function ENT:Initialize() end

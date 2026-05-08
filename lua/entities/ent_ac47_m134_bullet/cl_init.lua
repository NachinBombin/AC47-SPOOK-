include("shared.lua")

local mat_beam = Material("effects/laser1")
local mat_glow = Material("sprites/light_glow02_add")

local MUZZLE_VEL = 46000
local MAX_DIST   = 45000
local MIN_SPEED  = 200

-- ─── Shared projectile store ──────────────────────────────────────────────────
ac47_m134_store = ac47_m134_store or {
    last_idx           = 0,
    buffer_size        = 128,
    buffer             = {},
    active_projectiles = {},
}
if #ac47_m134_store.buffer == 0 then
    for i = 1, ac47_m134_store.buffer_size do
        ac47_m134_store.buffer[i] = {
            hit               = true,
            pos               = Vector(0,0,0),
            old_pos           = Vector(0,0,0),
            vel               = Vector(0,0,0),
            old_vel           = Vector(0,0,0),
            dir               = Vector(0,0,0),
            speed             = 0,
            distance_traveled = 0,
            m134_wizz         = false,
        }
    end
end

ac47_ambient_loops = ac47_ambient_loops or {}

-- ─── Net: new projectile ──────────────────────────────────────────────────────
net.Receive("ac47_m134_projectile", function()
    local pos = net.ReadVector()
    local dir = net.ReadVector()
    dir:Normalize()

    local store    = ac47_m134_store
    local proj_idx = bit.band(store.last_idx, store.buffer_size - 1) + 1
    local proj     = store.buffer[proj_idx]

    proj.hit               = false
    proj.pos               = Vector(pos.x, pos.y, pos.z)
    proj.old_pos           = Vector(pos.x, pos.y, pos.z)
    proj.dir               = Vector(dir.x, dir.y, dir.z)
    proj.speed             = MUZZLE_VEL
    proj.vel               = proj.dir * proj.speed
    proj.old_vel           = proj.dir * proj.speed
    proj.distance_traveled = 0
    proj.m134_wizz         = false

    store.last_idx = store.last_idx + 1
    store.active_projectiles[#store.active_projectiles + 1] = proj
end)

-- ─── Net: plane spatial sound ─────────────────────────────────────────────────
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

hook.Add("EntityRemoved", "ac47_ambient_loop_cleanup", function(ent)
    if not IsValid(ent) then return end
    local idx = ent:EntIndex()
    local snd = ac47_ambient_loops[idx]
    if snd then snd:Stop() end
    ac47_ambient_loops[idx] = nil
end)

-- ─── Passby logic ─────────────────────────────────────────────────────────────
local M134_PASSBY_COOLDOWN     = 0.22
local M134_MAX_CONSIDER_DISTSQ = 4000 * 4000
local m134_passby_last_time    = -99

local function m134_passby_emit(distance, position)
    if distance < 256 then
        AC47EmitSound("ac47_passby_close", position)
    elseif distance < 768 then
        if math.random(2) == 1 then
            AC47EmitSound("ac47_passby_medium_2", position)
        else
            AC47EmitSound("ac47_passby_medium", position)
        end
    elseif distance < 2500 then
        AC47EmitSound("ac47_passby_hiss_far", position)
    else
        AC47EmitSound("ac47_passby_far", position)
    end
end

local function lateral_sign(bullet_pos, listener_pos, dir)
    local d = listener_pos - bullet_pos
    d:Normalize()
    return dir:Dot(d)
end

local function m134_check_passby(proj)
    if proj.distance_traveled == 0 then return end
    local listener = LocalPlayer()
    if not IsValid(listener) then return end
    local view_ent = GetViewEntity()
    if IsValid(view_ent) and not view_ent:IsPlayer() then return end
    local listen_pos = listener:EyePos()
    local mid_x = (proj.old_pos.x + proj.pos.x) * 0.5
    local mid_y = (proj.old_pos.y + proj.pos.y) * 0.5
    local mid_z = (proj.old_pos.z + proj.pos.z) * 0.5
    local dx = listen_pos.x - mid_x
    local dy = listen_pos.y - mid_y
    local dz = listen_pos.z - mid_z
    if (dx*dx + dy*dy + dz*dz) > M134_MAX_CONSIDER_DISTSQ then return end
    local sign_old = lateral_sign(proj.old_pos, listen_pos, proj.dir)
    local sign_new = lateral_sign(proj.pos,     listen_pos, proj.dir)
    if sign_old <= 0 then proj.m134_wizz = true return end
    if sign_new > 0  then return end
    proj.m134_wizz = true
    local now = UnPredictedCurTime()
    if (now - m134_passby_last_time) < M134_PASSBY_COOLDOWN then return end
    m134_passby_last_time = now
    local dist, closest_pos = util.DistanceToLine(proj.old_pos, proj.pos, listen_pos)
    m134_passby_emit(dist, closest_pos)
end

-- ─── Client movement tick ─────────────────────────────────────────────────────
local tick_interval = engine.TickInterval()
local last_tick     = engine.TickCount()

local function move_cl()
    local active = ac47_m134_store.active_projectiles
    local count  = #active
    local idx    = 1
    while idx <= count do
        local proj = active[idx]
        if proj.hit or proj.distance_traveled >= MAX_DIST or proj.speed <= MIN_SPEED then
            active[idx] = active[count]
            active[count] = nil
            count = count - 1
        else
            local step    = proj.dir * (proj.speed * tick_interval)
            local new_pos = proj.pos + step
            proj.old_vel  = proj.vel
            proj.old_pos  = proj.pos
            proj.vel      = step
            proj.pos      = new_pos
            proj.distance_traveled = proj.distance_traveled + step:Length()
            if not proj.m134_wizz then
                m134_check_passby(proj)
            end
            idx = idx + 1
        end
    end
end

hook.Add("CreateMove", "ac47_m134_move_cl", function()
    local t = engine.TickCount()
    if t > last_tick then
        last_tick = t
        move_cl()
    end
end)

-- ─── Tracer renderer ──────────────────────────────────────────────────────────
-- AC-47 Spooky tracers are RED to visually distinguish from the AC-130's orange.
-- Core beam  : Color(255, 30,  10, 255)  -- bright red
-- Halo beam  : Color(200,  0,   0, 110)  -- deep red, semi-transparent
-- Outer glow : Color(255,  40,  0, 180)  -- red-orange outer bloom
-- Hot core   : Color(255, 200, 180, 255) -- near-white hot tip (unchanged)
local function render_projectiles()
    local active = ac47_m134_store.active_projectiles
    local count  = #active
    if count == 0 then return end

    local cam_pos      = EyePos()
    local real_time    = UnPredictedCurTime()
    local cur_ticktime = engine.TickCount() * tick_interval
    local interp_frac  = math.Clamp((real_time - cur_ticktime) / tick_interval, 0, 2)
    local min_trail    = 120

    for i = 1, count do
        local p = active[i]
        if p.hit then continue end

        local render_pos = p.pos
        if interp_frac <= 1.0 then
            local t  = interp_frac
            local t2 = t * t
            local t3 = t2 * t
            local h1 =  2*t3 - 3*t2 + 1
            local h2 = -2*t3 + 3*t2
            local h3 =  t3 - 2*t2 + t
            local h4 =  t3 - t2
            render_pos = p.old_pos * h1 + p.pos * h2
                       + (p.old_vel or p.vel) * (h3 * tick_interval)
                       + p.vel               * (h4 * tick_interval)
        end

        local tail_end = p.old_pos or render_pos
        if p.vel then
            local vls = p.vel:LengthSqr()
            if vls > 1 then
                local trail_vec = render_pos - tail_end
                if trail_vec:LengthSqr() < min_trail * min_trail then
                    tail_end = render_pos - p.vel * (1.0 / math.sqrt(vls)) * min_trail
                end
            end
        end

        local dist  = math.sqrt(cam_pos:DistToSqr(render_pos))
        local scale = math.Clamp(dist / 1200, 1.5, 5)

        render.SetMaterial(mat_beam)
        if render_pos:DistToSqr(tail_end) > 4 then
            -- Bright red core beam (was orange: 255, 240, 180)
            render.DrawBeam(tail_end, render_pos, 6 * scale, 0, 1, Color(255, 30, 10, 255))
        end
        -- Deep red halo (was orange: 255, 100, 0)
        render.DrawBeam(tail_end, render_pos, 18 * scale, 0, 1, Color(200, 0, 0, 110))

        render.SetMaterial(mat_glow)
        -- Red outer bloom (was orange: 255, 140, 20)
        render.DrawSprite(render_pos, 60 * scale, 60 * scale, Color(255, 40, 0, 180))
        -- Hot near-white core tip (kept similar, slight red shift from 255,255,200)
        render.DrawSprite(render_pos, 16 * scale, 16 * scale, Color(255, 200, 180, 255))
    end
end

hook.Add("PostDrawTranslucentRenderables", "ac47_m134_render", function(depth, skybox)
    if depth or skybox then return end
    render_projectiles()
end)

-- ============================================================
-- IMPACT FX
-- Bullet hole decal  : util.Decal — stamped directly on world geo
-- Dust puff          : ParticleEmitter — 6 manual dust particles,
--                      no PCF dependency, no explosion effects.
-- Impact sound       : sound.Play at hit position.
-- util.Effect is NOT used here at all — every named effect that
-- produced explosions/smoke has been removed.
-- ============================================================

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

-- Dust material: base HL2 smoke puff, always present, no addon needed.
local mat_dust = Material("particle/smokestack")

local function SpawnDustPuff(hitPos, hitNormal)
    -- ParticleEmitter lives in 3D world space.
    -- Third arg false = don't use a 2D screen-space emitter.
    local emitter = ParticleEmitter(hitPos, false)
    if not emitter then return end

    -- 6 dust particles fanning out from the surface normal.
    for _ = 1, 6 do
        local p = emitter:Add("particle/smokestack", hitPos)
        if p then
            -- Base velocity: along the surface normal + random sideways scatter
            local scatter = VectorRand() * 18
            scatter.z     = math.abs(scatter.z)  -- keep upward bias
            local vel     = hitNormal * math.Rand(20, 55) + scatter

            p:SetVelocity(vel)
            p:SetLifeTime(0)
            p:SetDieTime(math.Rand(0.25, 0.55))
            p:SetStartAlpha(math.random(60, 100))
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(4, 9))
            p:SetEndSize(math.Rand(12, 22))
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-1.5, 1.5))
            -- Brownish-gray dust tint
            p:SetColor(
                math.random(140, 190),
                math.random(120, 160),
                math.random(80,  120)
            )
            p:SetGravity(Vector(0, 0, -30))   -- slight gravity drag
            p:SetAirResistance(80)
        end
    end

    emitter:Finish()
end

net.Receive("ac47_bullet_impact", function()
    local hitPos    = net.ReadVector()
    local hitNormal = net.ReadVector()
    local sndIdx    = net.ReadUInt(8)
    sndIdx = math.Clamp(sndIdx, 1, #IMPACT_SOUNDS)

    -- Bullet hole decal stamped on the surface.
    -- "Impact.Concrete" is a standard HL2 decal group that picks a
    -- random bullet hole sprite automatically. Works on world geometry.
    util.Decal("Impact.Concrete", hitPos + hitNormal * 2, hitPos - hitNormal * 4)

    -- Dust puff via ParticleEmitter (no util.Effect, no explosions).
    SpawnDustPuff(hitPos, hitNormal)

    -- Impact sound.
    sound.Play(IMPACT_SOUNDS[sndIdx], hitPos, 75, math.random(95, 110), 1.0)
end)

function ENT:Draw() end
function ENT:Initialize() end

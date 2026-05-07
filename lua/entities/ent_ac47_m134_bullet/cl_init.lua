include("shared.lua")

local mat_beam = Material("effects/laser1")
local mat_glow = Material("sprites/light_glow02_add")

local MUZZLE_VEL = 56000
local MAX_DIST   = 45000
local MIN_SPEED  = 200

-- ─── Shared projectile store ─────────────────────────────────────────────────
-- Declared globally so server init.lua and client cl_init.lua share the same
-- table in single-player; in multiplayer the client populates it via net.
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

-- ─── Engine ambient loop table ───────────────────────────────────────────────
-- Keyed by entIndex. Populated by net.Receive("ac47_plane_spatial_sound").
-- Stopped by net.Receive("ac47_plane_damage_tier") tier==0 in plane cl_init.lua.
-- Also cleaned up by EntityRemoved below.
ac47_ambient_loops = ac47_ambient_loops or {}

-- ─── Net: new projectile ─────────────────────────────────────────────────────
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

-- ─── Net: plane spatial sound → ambient loop management ─────────────────────
-- Engine sounds (loop=true) are started as CSoundPatch on the plane entity.
-- One-shot sounds (loop=false) are played via sound.Play near the player ear.
-- The "is loop" classification is: anything with engine/rpm/far in the path.
net.Receive("ac47_plane_spatial_sound", function()
    local sndPath  = net.ReadString()
    local nearPos  = net.ReadVector()
    local level    = net.ReadUInt(8)
    local pitch    = net.ReadUInt(8)
    local volume   = net.ReadFloat()
    local entIndex = net.ReadUInt(16)

    local isLoop = string.find(sndPath, "engine") or
                   string.find(sndPath, "rpm")    or
                   string.find(sndPath, "far")

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

-- ─── Passby logic (mirrors gau_check_passby exactly) ─────────────────────────
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

-- ─── Client movement tick (mirrors bombin_gau_move_cl via CreateMove) ────────
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

-- ─── Tracer renderer (mirrors bombin_gau render exactly) ─────────────────────
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
            render.DrawBeam(tail_end, render_pos, 6 * scale, 0, 1, Color(255, 240, 180, 255))
        end
        render.DrawBeam(tail_end, render_pos, 18 * scale, 0, 1, Color(255, 100, 0, 100))

        render.SetMaterial(mat_glow)
        render.DrawSprite(render_pos, 60 * scale, 60 * scale, Color(255, 140, 20, 180))
        render.DrawSprite(render_pos, 16 * scale, 16 * scale, Color(255, 255, 200, 255))
    end
end

hook.Add("PostDrawTranslucentRenderables", "ac47_m134_render", function(depth, skybox)
    if depth or skybox then return end
    render_projectiles()
end)

-- ─── Impact FX (client-side: decal + ricochet + sound) ───────────────────────
net.Receive("ac47_bullet_impact", function()
    local hitPos    = net.ReadVector()
    local hitNormal = net.ReadVector()
    local sndIdx    = net.ReadUInt(4)

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
    sndIdx = math.Clamp(sndIdx, 1, #IMPACT_SOUNDS)

    local ed = EffectData()
    ed:SetOrigin(hitPos)
    ed:SetNormal(hitNormal)
    ed:SetScale(0.4)
    ed:SetMagnitude(0.4)
    ed:SetRadius(8)
    util.Effect("Sparks", ed)

    local ed2 = EffectData()
    ed2:SetOrigin(hitPos)
    ed2:SetNormal(hitNormal)
    ed2:SetScale(0.3)
    util.Effect("ManhackSparks", ed2)

    sound.Play(IMPACT_SOUNDS[sndIdx], hitPos, 75, math.random(95, 110), 1.0)
end)

function ENT:Draw() end
function ENT:Initialize() end

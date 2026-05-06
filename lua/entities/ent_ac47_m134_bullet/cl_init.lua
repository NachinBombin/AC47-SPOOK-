include("shared.lua")

local mat_beam = Material("effects/laser1")
local mat_glow = Material("sprites/light_glow02_add")

local MUZZLE_VEL = 56000
local MAX_DIST   = 45000
local MIN_SPEED  = 200

-- ─── Ring buffer (mirrors server) ────────────────────────────────────────────
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
            shooter           = NULL,
            pos               = Vector(0,0,0),
            old_pos           = Vector(0,0,0),
            vel               = Vector(0,0,0),
            old_vel           = Vector(0,0,0),
            dir               = Vector(0,0,0),
            speed             = 0,
            damage            = 0,
            distance_traveled = 0,
            ac47_wizz         = false,
        }
    end
end

-- ─── Passby logic ────────────────────────────────────────────────────────────
-- Mirrors ent_bombin_gau_bullet passby exactly, using AC47EmitSound from the
-- autorun file. Distance thresholds tuned for a smaller-caliber gun.

local AC47_PASSBY_COOLDOWN     = 0.18   -- slightly tighter burst cap vs GAU
local AC47_MAX_CONSIDER_DISTSQ = 3500 * 3500

local ac47_passby_last_time = -99

local function ac47_passby_emit(distance, position)
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

local function ac47_check_passby(proj)
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
    if (dx*dx + dy*dy + dz*dz) > AC47_MAX_CONSIDER_DISTSQ then return end

    local vn = proj.dir

    local sign_old = lateral_sign(proj.old_pos, listen_pos, vn)
    local sign_new = lateral_sign(proj.pos,     listen_pos, vn)

    if sign_old <= 0 then
        proj.ac47_wizz = true
        return
    end

    if sign_new > 0 then return end

    proj.ac47_wizz = true

    local now = UnPredictedCurTime()
    if (now - ac47_passby_last_time) < AC47_PASSBY_COOLDOWN then return end
    ac47_passby_last_time = now

    local dist, closest_pos = util.DistanceToLine(proj.old_pos, proj.pos, listen_pos)
    ac47_passby_emit(dist, closest_pos)
end

-- ─── Net receive ─────────────────────────────────────────────────────────────

net.Receive("ac47_m134_projectile", function()
    local pos = net.ReadVector()
    local dir = net.ReadVector()
    dir:Normalize()

    local store    = ac47_m134_store
    local proj_idx = bit.band(store.last_idx, store.buffer_size - 1) + 1
    local proj     = store.buffer[proj_idx]

    proj.hit               = false
    proj.shooter           = NULL
    proj.pos               = Vector(pos.x, pos.y, pos.z)
    proj.old_pos           = Vector(pos.x, pos.y, pos.z)
    proj.dir               = Vector(dir.x, dir.y, dir.z)
    proj.speed             = MUZZLE_VEL
    proj.damage            = 0
    proj.distance_traveled = 0
    proj.vel               = proj.dir * proj.speed
    proj.old_vel           = proj.dir * proj.speed
    proj.ac47_wizz         = false

    store.last_idx = store.last_idx + 1
    store.active_projectiles[#store.active_projectiles + 1] = proj
end)

-- ─── Movement + passby tick ──────────────────────────────────────────────────

local tick_interval = engine.TickInterval()
local last_tick     = engine.TickCount()

local function ac47_move_cl()
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

            if not proj.ac47_wizz then
                ac47_check_passby(proj)
            end

            idx = idx + 1
        end
    end
end

hook.Add("CreateMove", "ac47_m134_move_cl", function()
    local t = engine.TickCount()
    if t > last_tick then
        last_tick = t
        ac47_move_cl()
    end
end)

-- ─── Renderer ────────────────────────────────────────────────────────────────
-- M134 tracer: thinner and slightly dimmer than the 30mm GAU tracer,
-- yellow-white core (7.62 tracer colour).

local function ac47_render_projectiles()
    local active = ac47_m134_store.active_projectiles
    local count  = #active
    if count == 0 then return end

    local cam_pos      = EyePos()
    local real_time    = UnPredictedCurTime()
    local cur_ticktime = engine.TickCount() * tick_interval
    local interp_frac  = math.Clamp((real_time - cur_ticktime) / tick_interval, 0, 2)
    local min_trail    = 80

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
        local scale = math.Clamp(dist / 1200, 1.0, 4.5)

        render.SetMaterial(mat_beam)
        if render_pos:DistToSqr(tail_end) > 4 then
            -- Thin bright core: yellow-white
            render.DrawBeam(tail_end, render_pos, 5 * scale, 0, 1, Color(255, 255, 200, 255))
        end
        -- Outer glow: warm orange (same family as GAU but smaller)
        render.DrawBeam(tail_end, render_pos, 14 * scale, 0, 1, Color(255, 140, 20, 100))

        render.SetMaterial(mat_glow)
        render.DrawSprite(render_pos, 50 * scale, 50 * scale, Color(255, 200, 60, 180))
        render.DrawSprite(render_pos, 14 * scale, 14 * scale, Color(255, 255, 220, 255))
    end
end

hook.Add("PostDrawTranslucentRenderables", "ac47_m134_render", function(depth, skybox)
    if depth or skybox then return end
    ac47_render_projectiles()
end)

function ENT:Draw() end

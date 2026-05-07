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
            hit     = true,
            shooter = NULL,
            pos     = Vector(0,0,0),
            old_pos = Vector(0,0,0),
            vel     = Vector(0,0,0),
            old_vel = Vector(0,0,0),
            dir     = Vector(0,0,0),
            speed   = 0,
            damage  = 0,
        }
    end
end

-- ─── Net receive: new bullet spawned on server ────────────────────────────────
net.Receive("ac47_m134_bullet_new", function()
    local pos = net.ReadVector()
    local vel = net.ReadVector()

    local store = ac47_m134_store
    store.last_idx = (store.last_idx % store.buffer_size) + 1
    local slot = store.buffer[store.last_idx]
    slot.hit     = false
    slot.pos     = pos
    slot.old_pos = pos
    slot.vel     = vel
    slot.old_vel = vel
    slot.dir     = vel:GetNormalized()
    slot.speed   = vel:Length()
    slot.damage  = 0
    store.active_projectiles[store.last_idx] = slot
end)

-- ─── Net receive: spatial sound from plane ───────────────────────────────────
net.Receive("ac47_plane_spatial_sound", function()
    local sndPath = net.ReadString()
    local nearPos = net.ReadVector()
    local level   = net.ReadUInt(8)
    local pitch   = net.ReadUInt(8)
    local volume  = net.ReadFloat()
    -- BUG2 FIX: nil-guard AC47EmitSound.
    -- On listen-server, entity cl_init files load before autorun/client files,
    -- so the global may not exist yet on the very first net receive.
    -- The sound is cosmetic; silently skip rather than crash the tracer system.
    if AC47EmitSound then
        AC47EmitSound(sndPath, nearPos, level, pitch, volume)
    else
        sound.Play(sndPath, nearPos, level, pitch, volume)
    end
end)

-- ─── Think: move active client-side projectiles ──────────────────────────────
hook.Add("Think", "ac47_m134_bullet_think", function()
    local store = ac47_m134_store
    local ft    = FrameTime()
    for idx, slot in pairs(store.active_projectiles) do
        if slot.hit then
            store.active_projectiles[idx] = nil
            continue
        end
        slot.old_pos = slot.pos
        slot.old_vel = slot.vel
        slot.pos     = slot.pos + slot.vel * ft
        if slot.pos:DistToSqr(slot.old_pos) < 1 or slot.speed < MIN_SPEED then
            slot.hit = true
            store.active_projectiles[idx] = nil
            continue
        end
        -- Simple trace for hit detection
        local tr = util.QuickTrace(slot.old_pos, slot.pos - slot.old_pos, NULL)
        if tr.Hit then
            slot.hit = true
            store.active_projectiles[idx] = nil
        end
    end
end)

-- ─── Render tracer beams ─────────────────────────────────────────────────────
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

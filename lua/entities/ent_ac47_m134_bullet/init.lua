AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ─── Constants ───────────────────────────────────────────────────────────────────
local MUZZLE_VEL = 46000
local MAX_DIST   = 45000
local MIN_SPEED  = 200
local BLAST_DMG  = 18
local BLAST_RAD  = 20
local FORCE_MUL  = 3.0

-- ─── Ricochet ────────────────────────────────────────────────────────────────────
local RICOCHET_CHANCE    = 0.02
local RICOCHET_CONE      = 60
local RICOCHET_DMG_MUL   = 0.35
local RICOCHET_SPEED_MUL = 0.45

-- Pre-allocated flat pending queue. Each ricochet that wins the 2% roll
-- is written here during the move loop and spawned AFTER the loop exits.
-- Capacity: 32 ricochets per tick. At 2% chance with ~200 bullets/tick
-- the expected value is 4; 32 is an 8-sigma ceiling with zero alloc cost.
local RICO_QUEUE_CAP = 32
local rico_queue = {}
local rico_queue_n = 0
do
    -- Pre-fill all slots so no table is ever created at runtime.
    for i = 1, RICO_QUEUE_CAP do
        rico_queue[i] = {
            shooter      = NULL,
            firer_ent    = NULL,
            pos          = Vector(0,0,0),
            dir          = Vector(0,0,0),
            damage       = 0,
            blast_radius = 0,
        }
    end
end

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
for _, s in ipairs(IMPACT_SOUNDS) do util.PrecacheSound(s) end

-- ─── Shared projectile store ─────────────────────────────────────────────────────
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
            firer_ent         = NULL,
            pos               = Vector(0,0,0),
            old_pos           = Vector(0,0,0),
            vel               = Vector(0,0,0),
            old_vel           = Vector(0,0,0),
            dir               = Vector(0,0,0),
            speed             = 0,
            damage            = 0,
            distance_traveled = 0,
            m134_wizz         = false,
        }
    end
end

util.AddNetworkString("ac47_m134_projectile")
util.AddNetworkString("ac47_bullet_impact")

-- ─── Spawn function ──────────────────────────────────────────────────────────────
function ac47_m134_spawn(shooter, firer_ent, pos, dir, damage, blast_radius)
    local store    = ac47_m134_store
    local proj_idx = bit.band(store.last_idx, store.buffer_size - 1) + 1
    local proj     = store.buffer[proj_idx]

    proj.hit               = false
    proj.shooter           = shooter
    proj.firer_ent         = firer_ent
    proj.pos               = Vector(pos.x, pos.y, pos.z)
    proj.old_pos           = Vector(pos.x, pos.y, pos.z)
    proj.dir               = Vector(dir.x, dir.y, dir.z)
    proj.speed             = MUZZLE_VEL
    proj.damage            = damage       or BLAST_DMG
    proj.blast_radius      = blast_radius or BLAST_RAD
    proj.distance_traveled = 0
    proj.vel               = proj.dir * proj.speed
    proj.old_vel           = proj.dir * proj.speed
    proj.m134_wizz         = false

    store.last_idx = store.last_idx + 1
    store.active_projectiles[#store.active_projectiles + 1] = proj

    net.Start("ac47_m134_projectile")
        net.WriteVector(pos)
        net.WriteVector(dir)
    net.SendPVS(pos)
end

local function resolve_attacker(proj)
    if IsValid(proj.firer_ent) then return proj.firer_ent end
    if IsValid(proj.shooter)   then return proj.shooter   end
    return game.GetWorld()
end

-- ─── Ricochet direction (uniform spherical-cap sampling) ─────────────────────────
-- Pre-cache math locals to avoid global table lookups in hot path.
local m_abs    = math.abs
local m_rad    = math.rad
local m_cos    = math.cos
local m_sqrt   = math.sqrt
local m_random = math.random
local m_pi     = math.pi

local CONE_RAD  = m_rad(RICOCHET_CONE)
local CONE_CMAX = m_cos(CONE_RAD)          -- precomputed; cone never changes

local VEC_UP    = Vector(0, 0, 1)
local VEC_RIGHT = Vector(1, 0, 0)

local function ricochet_dir(normal)
    -- Orthonormal basis around the surface normal.
    local helper    = m_abs(normal.z) < 0.9 and VEC_UP or VEC_RIGHT
    local tangent   = normal:Cross(helper)  tangent:Normalize()
    local bitangent = normal:Cross(tangent) bitangent:Normalize()

    -- Uniform spherical-cap sample: cosθ uniform in [CONE_CMAX, 1].
    local cos_theta = CONE_CMAX + m_random() * (1 - CONE_CMAX)
    local sin_theta = m_sqrt(1 - cos_theta * cos_theta)
    local phi       = m_random() * (2 * m_pi)

    local cp = m_cos(phi)
    local sp = m_sqrt(1 - cp * cp) * (m_random() < 0.5 and 1 or -1)  -- sin(phi) with sign

    local dir = normal    * cos_theta
              + tangent   * (sin_theta * cp)
              + bitangent * (sin_theta * sp)
    dir:Normalize()
    return dir
end

-- ─── Queue a ricochet (called inside move loop — NO spawning here) ───────────────
local function queue_ricochet(proj, tr)
    -- 2% roll
    if m_random() > RICOCHET_CHANCE then return end

    -- Skip living entities and other projectiles.
    local hit_ent = tr.Entity
    if IsValid(hit_ent) then
        if hit_ent:IsNPC() or hit_ent:IsPlayer() then return end
        local cls = hit_ent:GetClass()
        if cls == "ent_ac47_m134_bullet" or cls == "ent_bombin_gau_bullet" then return end
    end

    local normal = tr.HitNormal
    if normal:LengthSqr() < 0.5 then return end

    -- Queue cap guard — silently drop if somehow exceeded.
    if rico_queue_n >= RICO_QUEUE_CAP then return end

    rico_queue_n = rico_queue_n + 1
    local slot = rico_queue[rico_queue_n]

    -- Write into the pre-allocated slot. No new tables, no GC.
    slot.shooter      = proj.shooter
    slot.firer_ent    = proj.firer_ent
    slot.damage       = math.max(1, math.floor(proj.damage * RICOCHET_DMG_MUL))
    slot.blast_radius = proj.blast_radius

    -- Compute direction and spawn pos now (while tr is still in scope),
    -- store into the slot's pre-existing Vector objects to avoid allocation.
    local rdir = ricochet_dir(normal)
    slot.dir.x = rdir.x  slot.dir.y = rdir.y  slot.dir.z = rdir.z
    local sp = tr.HitPos + normal * 4
    slot.pos.x = sp.x    slot.pos.y = sp.y    slot.pos.z = sp.z
end

-- ─── Drain the pending ricochet queue (called after move loop) ──────────────────
local function drain_rico_queue()
    if rico_queue_n == 0 then return end
    local active = ac47_m134_store.active_projectiles
    for i = 1, rico_queue_n do
        local s = rico_queue[i]
        ac47_m134_spawn(s.shooter, s.firer_ent, s.pos, s.dir, s.damage, s.blast_radius)
        -- Reduce speed of the just-appended ricochet bullet.
        local rico = active[#active]
        if rico and not rico.hit then
            local spd    = MUZZLE_VEL * RICOCHET_SPEED_MUL
            rico.speed   = spd
            rico.vel.x   = s.dir.x * spd
            rico.vel.y   = s.dir.y * spd
            rico.vel.z   = s.dir.z * spd
            rico.old_vel.x = rico.vel.x
            rico.old_vel.y = rico.vel.y
            rico.old_vel.z = rico.vel.z
        end
    end
    -- Reset counter — slots are reused next tick, no wipe needed.
    rico_queue_n = 0
end

local function apply_impact_fx(proj, tr)
    local hitPos   = tr.HitPos
    local attacker = resolve_attacker(proj)

    util.BlastDamage(attacker, attacker, hitPos, proj.blast_radius, proj.damage)

    local sndIdx = m_random(#IMPACT_SOUNDS)
    net.Start("ac47_bullet_impact")
        net.WriteVector(hitPos)
        net.WriteVector(tr.HitNormal)
        net.WriteUInt(sndIdx, 8)
    net.Broadcast()
end

local function apply_damage(proj, tr)
    local hit_ent = tr.Entity
    if not IsValid(hit_ent) then return end
    local attacker = resolve_attacker(proj)
    local dmg = DamageInfo()
    dmg:SetDamage(proj.damage)
    dmg:SetAttacker(attacker)
    dmg:SetInflictor(attacker)
    dmg:SetDamageType(DMG_BULLET)
    dmg:SetDamagePosition(tr.HitPos)
    dmg:SetDamageForce(proj.dir * proj.damage * FORCE_MUL)
    hit_ent:TakeDamageInfo(dmg)
end

local tick_interval = engine.TickInterval()

local function move_projectile(proj)
    if proj.hit then return true end
    if proj.distance_traveled >= MAX_DIST then proj.hit = true return true end
    if proj.speed <= MIN_SPEED            then proj.hit = true return true end

    local step    = proj.dir * (proj.speed * tick_interval)
    local new_pos = proj.pos + step

    local tr = util.TraceLine({
        start  = proj.pos,
        endpos = new_pos,
        filter = IsValid(proj.shooter) and { proj.shooter } or nil,
        mask   = MASK_SHOT,
    })

    proj.old_vel = proj.vel
    proj.old_pos = proj.pos

    if tr.Hit and not tr.HitSky then
        proj.pos = tr.HitPos
        proj.hit = true
        if IsValid(tr.Entity) then
            apply_damage(proj, tr)
        end
        apply_impact_fx(proj, tr)
        -- Only queued here. Actual spawn happens in drain_rico_queue after loop.
        queue_ricochet(proj, tr)
        return true
    end

    proj.vel               = step
    proj.pos               = new_pos
    proj.distance_traveled = proj.distance_traveled + step:Length()
    return false
end

hook.Add("Tick", "ac47_m134_move_sv", function()
    local active = ac47_m134_store.active_projectiles
    local count  = #active
    local idx    = 1
    while idx <= count do
        if move_projectile(active[idx]) then
            active[idx] = active[count]
            active[count] = nil
            count = count - 1
        else
            idx = idx + 1
        end
    end
    -- Spawn all queued ricochets now that the move loop is finished.
    -- active_projectiles can safely grow here.
    drain_rico_queue()
end)

function ENT:Initialize()
    self:SetModel("models/weapons/bt_762.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:DrawShadow(false)

    local pos = self.MuzzlePos or self:GetPos()
    local dir = self:GetAngles():Forward()

    ac47_m134_spawn(
        IsValid(self.Firer) and self.Firer or self,
        self.Firer,
        pos,
        dir,
        self.BulletDmg,
        nil
    )
    self:Remove()
end

function ENT:Draw() end

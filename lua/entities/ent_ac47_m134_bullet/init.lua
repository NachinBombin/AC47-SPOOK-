AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ─── Constants ───────────────────────────────────────────────────────────────────
local MUZZLE_VEL = 56000
local MAX_DIST   = 45000
local MIN_SPEED  = 200
local BLAST_DMG  = 18
local BLAST_RAD  = 30
local FORCE_MUL  = 3.0

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

-- ─── Shared projectile store (same pattern as bombin_gau_store) ─────────────────
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

util.AddNetworkString("ac47_m134_projectile")  -- pos + dir → client tracer + passby
-- FIX BUG 1: ac47_bullet_impact is broadcast-only (client plays the sound).
-- The server no longer calls sound.Play locally, so the host does NOT hear
-- the impact twice (once from sound.Play server-side + once from net.Receive).
util.AddNetworkString("ac47_bullet_impact")

-- ─── Spawn function (mirrors bombin_gau_spawn) ──────────────────────────────
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

    -- Notify clients: pos + dir (unit vector)
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

local function apply_impact_fx(proj, tr)
    local hitPos   = tr.HitPos
    local attacker = resolve_attacker(proj)

    util.BlastDamage(attacker, attacker, hitPos, proj.blast_radius, proj.damage)

    -- FIX BUG 1 + WARN 1: broadcast the impact to ALL clients (including host);
    -- sound.Play is NOT called server-side anymore — only the net message fires.
    -- Also upgraded to 8-bit sndIdx (was 4-bit, fragile if IMPACT_SOUNDS grows).
    local sndIdx = math.random(#IMPACT_SOUNDS)
    net.Start("ac47_bullet_impact")
        net.WriteVector(hitPos)
        net.WriteVector(tr.HitNormal)
        net.WriteUInt(sndIdx, 8)   -- FIX WARN 1: was WriteUInt(..., 4)
    net.Broadcast()
end

local function apply_damage(proj, tr)
    local hit_ent  = tr.Entity
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
end)

-- ENT:Initialize is a thin trampoline: unpack params, call ac47_m134_spawn, remove self.
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

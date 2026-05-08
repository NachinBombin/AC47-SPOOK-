AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ─── Constants ────────────────────────────────────────────────────────────────────
local MUZZLE_VEL = 46000
local MAX_DIST   = 45000
local MIN_SPEED  = 200
local BLAST_DMG  = 18
local BLAST_RAD  = 20
local FORCE_MUL  = 3.0

-- ─── Ricochet ────────────────────────────────────────────────────────────────────
-- A ricochet bullet spawns in the surface normal hemisphere with a random
-- scatter cone of up to RICOCHET_CONE degrees away from the true normal.
-- It carries reduced damage and speed to feel like a spent deflection.
local RICOCHET_CHANCE    = 0.02   -- 2 %
local RICOCHET_CONE      = 60     -- degrees half-angle; full hemisphere = 90
local RICOCHET_DMG_MUL   = 0.35  -- ricochet bullet does 35 % of original damage
local RICOCHET_SPEED_MUL = 0.45  -- ricochet bullet leaves at 45 % original speed

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

util.AddNetworkString("ac47_m134_projectile")
util.AddNetworkString("ac47_bullet_impact")

-- ─── Spawn function (mirrors bombin_gau_spawn) ────────────────────────────────────
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

-- ─── Ricochet helper ────────────────────────────────────────────────────────────────
-- Generates a unit vector inside a cone of half-angle `cone_deg` centred
-- on `normal`. The cone is always in the normal's hemisphere (dot > 0).
local function ricochet_dir(normal, cone_deg)
    -- Build an arbitrary orthonormal basis around the normal.
    -- Choose a helper vector that is never parallel to `normal`.
    local helper = math.abs(normal.z) < 0.9 and Vector(0, 0, 1) or Vector(1, 0, 0)
    local tangent   = normal:Cross(helper)  tangent:Normalize()
    local bitangent = normal:Cross(tangent) bitangent:Normalize()

    -- Uniform random point inside a disc of radius sin(cone_deg),
    -- then lift to the unit sphere. This gives uniform distribution
    -- over the spherical cap (no polar bunching).
    local cone_rad  = math.rad(cone_deg)
    local cos_max   = math.cos(cone_rad)
    -- Random cosine in [cos_max, 1] gives uniform spherical-cap sampling.
    local cos_theta = cos_max + math.random() * (1 - cos_max)
    local sin_theta = math.sqrt(1 - cos_theta * cos_theta)
    local phi       = math.random() * 2 * math.pi

    local dir = normal    * cos_theta
              + tangent   * (sin_theta * math.cos(phi))
              + bitangent * (sin_theta * math.sin(phi))
    dir:Normalize()
    return dir
end

local function try_spawn_ricochet(proj, tr)
    if math.random() > RICOCHET_CHANCE then return end

    -- Only ricochet off world geometry and static props, not off players/NPCs.
    -- tr.HitWorld is true for BSP world; check classname for non-world.
    local hit_ent = tr.Entity
    if IsValid(hit_ent) then
        local cls = hit_ent:GetClass()
        -- Skip ricochets off living entities (players, NPCs) and projectiles.
        if hit_ent:IsNPC() or hit_ent:IsPlayer() then return end
        if cls == "ent_ac47_m134_bullet" or cls == "ent_bombin_gau_bullet" then return end
    end

    local normal = tr.HitNormal
    -- Ensure the normal is usable; degenerate normals can appear on edge cases.
    if normal:LengthSqr() < 0.5 then return end

    local rico_dir = ricochet_dir(normal, RICOCHET_CONE)

    -- Spawn offset slightly off the surface along the normal to avoid
    -- immediately re-hitting the same face on tick 0.
    local spawn_pos = tr.HitPos + normal * 4

    -- Reuse ac47_m134_spawn so the ricochet gets a client-side tracer too.
    -- It inherits the same shooter/firer for kill credit.
    local rico_damage = math.max(1, math.floor(proj.damage * RICOCHET_DMG_MUL))
    ac47_m134_spawn(
        proj.shooter,
        proj.firer_ent,
        spawn_pos,
        rico_dir,
        rico_damage,
        proj.blast_radius
    )

    -- Override the ricochet bullet's speed after it is pushed into the buffer
    -- (it was just appended at the tail of active_projectiles).
    local active = ac47_m134_store.active_projectiles
    local rico   = active[#active]
    if rico and not rico.hit then
        local reduced_speed = MUZZLE_VEL * RICOCHET_SPEED_MUL
        rico.speed   = reduced_speed
        rico.vel     = rico_dir * reduced_speed
        rico.old_vel = rico.vel
    end
end

local function apply_impact_fx(proj, tr)
    local hitPos   = tr.HitPos
    local attacker = resolve_attacker(proj)

    util.BlastDamage(attacker, attacker, hitPos, proj.blast_radius, proj.damage)

    local sndIdx = math.random(#IMPACT_SOUNDS)
    net.Start("ac47_bullet_impact")
        net.WriteVector(hitPos)
        net.WriteVector(tr.HitNormal)
        net.WriteUInt(sndIdx, 8)
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
        -- Ricochet check runs AFTER impact FX so the impact always fires.
        try_spawn_ricochet(proj, tr)
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

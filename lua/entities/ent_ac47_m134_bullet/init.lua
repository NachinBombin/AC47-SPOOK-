AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ─── Constants ───────────────────────────────────────────────────────────────
local MUZZLE_VEL   = 56000   -- ~850 m/s 7.62x51 NATO, scaled to GMod units
local MAX_DIST     = 45000
local MIN_SPEED    = 200
local BULLET_DMG   = 18      -- M134 7.62mm base damage per round
local FORCE_MUL    = 3.0

local M134_FIRE_SOUNDS = {
    "lfs/tfre_ac47/m134_shoot.wav",
}

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

for _, s in ipairs(M134_FIRE_SOUNDS) do util.PrecacheSound(s) end

-- BUG3 FIX: was "ac47_m134_projectile" — did not match cl_init.lua
-- receiver "ac47_m134_bullet_new". Client never got bullet spawns;
-- zero tracers rendered. Both sides must use the same string.
util.AddNetworkString("ac47_m134_bullet_new")

-- ─── Shared projectile store ─────────────────────────────────────────────────
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
        }
    end
end

-- ─── ENT lifecycle ───────────────────────────────────────────────────────────
function ENT:Initialize()
    self:SetModel("models/weapons/bt_762.mdl")
    self:PhysicsInit(SOLID_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:DrawShadow(false)

    self.Shooter      = self.Firer or NULL
    self.MuzzlePos    = self:GetPos()
    self.BulletDmg    = self.BulletDmg or BULLET_DMG
    self.SpeedVal     = MUZZLE_VEL
    self.Dir          = self:GetForward()
    self.DistTraveled = 0
    self.Dead         = false

    -- BUG3 FIX: renamed to match cl_init.lua net.Receive
    net.Start("ac47_m134_bullet_new")
        net.WriteVector(self:GetPos())
        net.WriteVector(self.Dir)
    net.Broadcast()

    self:NextThink(CurTime())
end

function ENT:Think()
    if self.Dead then return end

    local dt     = engine.TickInterval()
    local vel    = self.Dir * self.SpeedVal
    local newPos = self:GetPos() + vel * dt

    local tr = util.TraceLine({
        start  = self:GetPos(),
        endpos = newPos,
        filter = { self, self.Shooter },
        mask   = MASK_SHOT,
    })

    if tr.Hit then
        local effectData = EffectData()
        effectData:SetOrigin(tr.HitPos)
        effectData:SetNormal(tr.HitNormal)
        util.Effect("Impact", effectData, true, true)

        sound.Play(
            IMPACT_SOUNDS[math.random(#IMPACT_SOUNDS)],
            tr.HitPos, 75, math.random(95, 105), 1.0
        )

        if IsValid(tr.Entity) and (tr.Entity:IsNPC() or tr.Entity:IsPlayer()) then
            local dmginfo = DamageInfo()
            dmginfo:SetDamage(self.BulletDmg)
            dmginfo:SetDamageType(DMG_BULLET)
            dmginfo:SetAttacker(IsValid(self.Shooter) and self.Shooter or self)
            dmginfo:SetInflictor(self)
            dmginfo:SetDamageForce(self.Dir * self.BulletDmg * FORCE_MUL)
            dmginfo:SetDamagePosition(tr.HitPos)
            tr.Entity:TakeDamageInfo(dmginfo)
        elseif IsValid(tr.Entity) and not tr.Entity:IsWorld() then
            local phys = tr.Entity:GetPhysicsObject()
            if IsValid(phys) then
                phys:ApplyForceOffset(self.Dir * self.BulletDmg * FORCE_MUL * 10, tr.HitPos)
            end
            tr.Entity:TakeDamage(self.BulletDmg, IsValid(self.Shooter) and self.Shooter or self, self)
        end

        self.Dead = true
        self:Remove()
        return
    end

    self.DistTraveled = self.DistTraveled + vel:Length() * dt
    self:SetPos(newPos)

    if self.DistTraveled >= MAX_DIST or self.SpeedVal <= MIN_SPEED then
        self.Dead = true
        self:Remove()
        return
    end

    self:NextThink(CurTime())
    return true
end

function ENT:Draw() end

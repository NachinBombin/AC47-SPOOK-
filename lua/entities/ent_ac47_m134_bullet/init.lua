AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ─── Constants ────────────────────────────────────────────────────────────
local MUZZLE_VEL = 56000
local MAX_DIST   = 45000
local MIN_SPEED  = 200
local BULLET_DMG = 18
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
util.PrecacheSound("lfs/tfre_ac47/m134_shoot.wav")

-- Net strings
util.AddNetworkString("ac47_m134_bullet_new")   -- new bullet spawn → client tracers + flyby
util.AddNetworkString("ac47_bullet_impact")      -- bullet hit → client impact FX + sound

-- ─── ENT lifecycle ──────────────────────────────────────────────────────────
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

    -- FIX: send Dir * MUZZLE_VEL so client slot.speed = MUZZLE_VEL, not 1.
    -- Previously sent self.Dir (unit vector), making slot.speed = 1 < MIN_SPEED=200
    -- which killed every client bullet on the first Think tick → zero tracers.
    net.Start("ac47_m134_bullet_new")
        net.WriteVector(self:GetPos())
        net.WriteVector(self.Dir * MUZZLE_VEL)
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
        -- Broadcast impact to clients: position + normal + random sound index.
        -- Clients handle the sound.Play and util.Effect so the world geometry
        -- receives the decal on every client, not just the server.
        net.Start("ac47_bullet_impact")
            net.WriteVector(tr.HitPos)
            net.WriteVector(tr.HitNormal)
            net.WriteUInt(math.random(#IMPACT_SOUNDS), 4)
        net.Broadcast()

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

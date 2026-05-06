AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_trailsystem.lua")
include("shared.lua")

-- ============================================================
-- SOUNDS
-- All paths match the LFS AC-47 content pack exactly.
-- ============================================================

local M134_FIRE_SOUNDS = {
    "lfs/tfre_ac47/m134_shoot.wav",
}

local M134_STOP_SOUND = "lfs/tfre_ac47/m134_stop.wav"

for _, s in ipairs(M134_FIRE_SOUNDS) do util.PrecacheSound(s) end
util.PrecacheSound(M134_STOP_SOUND)
util.PrecacheSound("lfs/tfre_ac47/skytrain_engine_start.wav")
util.PrecacheSound("lfs/tfre_ac47/skytrain_engine_1rpm.wav")
util.PrecacheSound("lfs/tfre_ac47/skytrain_engine_stop.wav")

-- ============================================================
-- NET STRINGS
-- ============================================================

util.AddNetworkString("ac47_plane_damage_tier")
util.AddNetworkString("ac47_plane_spatial_sound")

-- ============================================================
-- SPATIAL SOUND SYSTEM  (same as AC-130, prefixed ac47_)
-- ============================================================

local SOUND_SPEED     = 8200
local MAX_HEAR_DIST   = 88000
local VOL_FALLOFF_EXP = 0.01
local NEAR_OFFSET     = 40
local WEAPON_LEVEL    = 150

local pending_sounds = {}

function ENT:EmitSpatialSound(soundPath, originPos, soundLevel, pitch, baseVol)
    local sendAt = CurTime()
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end
        local plyPos  = ply:GetPos()
        local toPlane = originPos - plyPos
        local dist    = toPlane:Length()
        if dist > MAX_HEAR_DIST then continue end
        local t   = dist / MAX_HEAR_DIST
        local vol = baseVol * (1 - t) ^ VOL_FALLOFF_EXP
        local nearPos
        if dist > 0.1 then
            nearPos = plyPos + (toPlane / dist) * NEAR_OFFSET
        else
            nearPos = plyPos
        end
        local delay = dist / SOUND_SPEED
        pending_sounds[#pending_sounds + 1] = {
            sendTime  = sendAt + delay,
            ply       = ply,
            soundPath = soundPath,
            nearPos   = nearPos,
            level     = soundLevel,
            pitch     = pitch,
            volume    = vol,
        }
    end
end

local function FlushPendingSounds()
    if #pending_sounds == 0 then return end
    local ct   = CurTime()
    local keep = {}
    for _, entry in ipairs(pending_sounds) do
        if ct >= entry.sendTime then
            if IsValid(entry.ply) then
                net.Start("ac47_plane_spatial_sound")
                    net.WriteString(entry.soundPath)
                    net.WriteVector(entry.nearPos)
                    net.WriteUInt(entry.level, 8)
                    net.WriteUInt(entry.pitch, 8)
                    net.WriteFloat(entry.volume)
                net.Send(entry.ply)
            end
        else
            keep[#keep + 1] = entry
        end
    end
    pending_sounds = keep
end

-- ============================================================
-- ENT PROPERTIES
-- Three M134 miniguns, left (port) side, sequentially cycled.
-- Muzzle positions from the original tfre_ac47 entity:
--   fP[1] = Vector(-170, 66, 101.44)
--   fP[2] = Vector(-208, 66, 95)
--   fP[3] = Vector(-259, 66, 85.6)
-- ============================================================

-- M134 burst settings
ENT.M134_BurstCount       = 40      -- bullets per burst
ENT.M134_BurstDelay       = 0.033   -- ~30 rps per barrel (M134 cyclic rate 2000-6000 rpm, 3 guns)
ENT.M134_FirstBurstTime   = 0
ENT.M134_SecondBurstTime  = 4
ENT.M134_SweepHalfLength  = 500
ENT.M134_JitterAmount     = 180
ENT.M134_SpraySoundDelay  = 1.2
ENT.M134_SprayPauseDuration = 0.5
ENT.M134_BulletDamage     = 18
ENT.M134_TargetOffsetMin  = 200
ENT.M134_TargetOffsetMax  = 700

-- Weapon timing
ENT.WeaponWindow          = 10

-- Muzzle positions in local entity space (port side guns)
-- Exactly matching the tfre_ac47 fP table
ENT.MuzzlePoints = {
    Vector(-170, 66, 101.44),
    Vector(-208, 66, 95),
    Vector(-259, 66, 85.6),
}

-- Flight
ENT.Speed        = 280
ENT.OrbitRadius  = 2800
ENT.SkyHeightAdd = 5500
ENT.Lifetime     = 40

-- HP & damage tiers
ENT.MaxHP = 6000
ENT.DamageTierThresholds = { 0.75, 0.50, 0.25 }

ENT.Plane_Ambient_SoundPath = "lfs/tfre_ac47/skytrain_engine_1rpm.wav"

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Debug(msg)
    print("[AC-47 Spooky] " .. tostring(msg))
end

function ENT:Initialize()
    self.CenterPos    = self:GetVar("CenterPos", self:GetPos())
    self.CallDir      = self:GetVar("CallDir",   Vector(1, 0, 0))
    self.Lifetime     = self:GetVar("Lifetime",  self.Lifetime)
    self.Speed        = self:GetVar("Speed",     self.Speed)
    self.OrbitRadius  = self:GetVar("OrbitRadius", self.OrbitRadius)
    self.SkyHeightAdd = self:GetVar("SkyHeightAdd", self.SkyHeightAdd)

    if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1,0,0) end
    self.CallDir.z = 0
    self.CallDir:Normalize()

    local ground = self:FindGround(self.CenterPos)
    if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

    self.sky      = ground + self.SkyHeightAdd
    self.DieTime  = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    local spawnPos = self.CenterPos - self.CallDir * 2000
    spawnPos = Vector(spawnPos.x, spawnPos.y, self.sky)
    if not util.IsInWorld(spawnPos) then
        spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
    end
    if not util.IsInWorld(spawnPos) then self:Debug("spawnPos out of world") self:Remove() return end

    -- Use the exact model path from the LFS addon
    self:SetModel("models/tfre/vehicles/ac47_spooky/ac47_spooky.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
    self:SetPos(spawnPos)
    self.LastPos = spawnPos

    self:SetNWInt("HP",    self.MaxHP)
    self:SetNWInt("MaxHP", self.MaxHP)

    local ang = self.CallDir:Angle()
    self:SetAngles(Angle(0, ang.y - 90, 0))
    self.ang = self:GetAngles()

    -- Altitude drift
    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    self.AltDriftRange    = 250
    self.AltDriftLerp     = 0.001

    -- Banking smoothing
    self.JitterPhase     = math.Rand(0, math.pi * 2)
    self.JitterAmplitude = 4
    self.SmoothedRoll    = 0
    self.SmoothedPitch   = 0
    self.PrevYaw         = self:GetAngles().y

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
    end

    -- Engine ambient loop
    self.EngineLoop = CreateSound(self, self.Plane_Ambient_SoundPath)
    if self.EngineLoop then
        self.EngineLoop:SetSoundLevel(120)
        self.EngineLoop:Play()
    end

    -- Weapon state
    self.CurrentWeapon       = nil
    self.WeaponWindowEnd     = 0
    self.IsPeaceful          = false
    self.PeacefulUntil       = 0
    self._PendingWeapon      = nil
    self.M134_BurstTimes     = {}
    self.M134_BurstsFired    = 0
    self.M134_ActiveBursts   = {}
    self.M134_SweepStartPos  = nil
    self.M134_SweepEndPos    = nil
    self.M134_SprayBurstEnd  = 0
    self.M134_SprayBulletCount = 0
    self.NextShotTimeSpray   = 0
    self.NextSpraySoundTime  = 0
    self.MuzzleIndex         = 1   -- cycles 1→2→3→1 per bullet
    self.IsDestroyed         = false
    self.DamageTier          = 0

    self:Debug("Spawned at " .. tostring(spawnPos))
end

-- ============================================================
-- DAMAGE & DESTRUCTION
-- ============================================================

function ENT:BroadcastDamageTier(tier)
    net.Start("ac47_plane_damage_tier")
        net.WriteUInt(self:EntIndex(), 16)
        net.WriteUInt(tier, 2)
    net.Broadcast()
end

function ENT:CheckDamageTier(hp)
    local fraction = hp / (self.MaxHP or ENT.MaxHP)
    local newTier  = 0
    for i, thresh in ipairs(self.DamageTierThresholds or ENT.DamageTierThresholds) do
        if fraction <= thresh then newTier = i end
    end
    if newTier ~= self.DamageTier then
        self.DamageTier = newTier
        self:BroadcastDamageTier(newTier)
    end
end

function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end
    local hp = self:GetNWInt("HP", self.MaxHP or ENT.MaxHP)
    hp = hp - dmginfo:GetDamage()
    self:SetNWInt("HP", hp)
    self:CheckDamageTier(hp)
    if hp <= 0 then self:DestroyPlane() end
end

function ENT:DestroyPlane()
    if self.IsDestroyed then return end
    self.IsDestroyed = true
    if self.EngineLoop then self.EngineLoop:Stop() self.EngineLoop = nil end
    self:BroadcastDamageTier(0)
    local pos = self.LastPos or self:GetPos()
    local function boom(p, sc)
        local ed = EffectData()
        ed:SetOrigin(p) ed:SetScale(sc) ed:SetMagnitude(sc) ed:SetRadius(sc * 100)
        util.Effect("HelicopterMegaBomb", ed, true, true)
        local ed2 = EffectData()
        ed2:SetOrigin(p) ed2:SetScale(sc) ed2:SetMagnitude(sc) ed2:SetRadius(sc * 100)
        util.Effect("500lb_air", ed2, true, true)
    end
    boom(pos, 6)
    boom(pos + Vector(0,0,80),  4)
    boom(pos + Vector(0,0,160), 3)
    sound.Play("ambient/explosions/explode_8.wav", pos, 140, 90, 1.0)
    sound.Play("weapon_AWP.Single",               pos, 145, 60, 1.0)
    util.BlastDamage(self, self, pos, 350, 180)
    self:Remove()
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
    if not self.DieTime or not self.SpawnTime then self:NextThink(CurTime() + 0.1) return true end
    local ct = CurTime()
    if ct >= self.DieTime then self:Remove() return end
    if not IsValid(self.PhysObj) then self.PhysObj = self:GetPhysicsObject() end
    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then self.PhysObj:Wake() end
    FlushPendingSounds()
    self:HandleWeaponWindow(ct)
    self:UpdateActiveM134Bursts(ct)
    self:NextThink(ct)
    return true
end

-- ============================================================
-- PHYSICS UPDATE (orbit + banking)
-- ============================================================

function ENT:PhysicsUpdate(phys)
    if not self.DieTime or not self.sky then return end
    if CurTime() >= self.DieTime then self:Remove() return end
    local pos = self:GetPos()
    self.LastPos = pos

    if CurTime() >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
        self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    end
    self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)

    self.JitterPhase = self.JitterPhase + 0.02
    local jitter     = math.sin(self.JitterPhase) * self.JitterAmplitude
    local liveAlt    = self.AltDriftCurrent + jitter

    local flatPos    = Vector(pos.x, pos.y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    local dist       = flatPos:Distance(flatCenter)

    local orbitYaw = 0
    if dist > self.OrbitRadius and (self.TurnDelay or 0) < CurTime() then
        orbitYaw = 0.1
        self.TurnDelay = CurTime() + 0.02
    end

    local trSky = util.QuickTrace(self:GetPos(), self:GetForward() * 3000, self)
    local skyYaw = trSky.HitSky and 0.3 or 0

    self.ang = self.ang + Angle(0, orbitYaw + skyYaw, 0)
    local currentYaw  = self.ang.y
    local rawYawDelta = math.NormalizeAngle(currentYaw - (self.PrevYaw or currentYaw))
    self.PrevYaw      = currentYaw

    local targetRoll  = math.Clamp(rawYawDelta * -18, -15, 15)
    local rollLerp    = rawYawDelta ~= 0 and 0.08 or 0.04
    self.SmoothedRoll = Lerp(rollLerp, self.SmoothedRoll, targetRoll)

    local forward    = self.ang:Forward()
    local vel        = forward * self.Speed
    local targetPitch = math.Clamp(-vel.z * 0.02, -8, 8)
    self.SmoothedPitch = Lerp(0.03, self.SmoothedPitch, targetPitch)

    local finalAng = Angle(self.SmoothedPitch, self.ang.y, self.SmoothedRoll)
    phys:SetAngles(finalAng)
    phys:SetPos(Vector(
        pos.x + vel.x * engine.TickInterval(),
        pos.y + vel.y * engine.TickInterval(),
        liveAlt
    ))
    phys:SetVelocity(vel)
end

-- ============================================================
-- WEAPON CYCLE
-- Only weapon: M134 triple minigun. Two modes: burst and spray.
-- ============================================================

local PEACEFUL_MIN = 4
local PEACEFUL_MAX = 7

function ENT:HandleWeaponWindow(ct)
    if self.IsPeaceful then
        if ct >= self.PeacefulUntil then
            self.IsPeaceful = false
            self:ArmWeapon(self._PendingWeapon, ct)
            self._PendingWeapon = nil
        end
        return
    end

    if not self.CurrentWeapon then
        self:EnterPeaceful(ct)
        return
    end

    if ct >= self.WeaponWindowEnd then
        self:EnterPeaceful(ct)
        return
    end

    if     self.CurrentWeapon == "m134_burst" then self:UpdateM134BurstsSchedule(ct)
    elseif self.CurrentWeapon == "m134_spray" then self:UpdateM134Spray(ct) end
end

function ENT:EnterPeaceful(ct)
    self:StopSprayLoop()
    self.CurrentWeapon  = nil
    self.IsPeaceful     = true
    self.PeacefulUntil  = ct + math.Rand(PEACEFUL_MIN, PEACEFUL_MAX)
    self._PendingWeapon = self:RollWeapon()
end

function ENT:RollWeapon()
    -- 60% burst, 40% spray — both use the M134
    return math.random() < 0.6 and "m134_burst" or "m134_spray"
end

function ENT:ArmWeapon(weapon, ct)
    weapon = weapon or self:RollWeapon()
    self.CurrentWeapon   = weapon
    self.WeaponWindowEnd = ct + self.WeaponWindow

    if self.CurrentWeapon == "m134_burst" then
        self.M134_BurstTimes  = { ct + self.M134_FirstBurstTime, ct + self.M134_SecondBurstTime }
        self.M134_BurstsFired = 0
        self.M134_ActiveBursts = {}
    elseif self.CurrentWeapon == "m134_spray" then
        self.NextShotTimeSpray   = ct
        self.NextSpraySoundTime  = ct
        self.M134_SprayBulletCount = 0
        self.M134_SprayBurstEnd  = 0
        local targetPos = self:GetTargetGroundPos()
        local sweepDir  = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
        if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1,0,0) end
        sweepDir:Normalize()
        self.M134_SweepStartPos = targetPos - sweepDir * self.M134_SweepHalfLength
        self.M134_SweepEndPos   = targetPos + sweepDir * self.M134_SweepHalfLength
    end
end

-- ============================================================
-- SPRAY HELPERS
-- ============================================================

function ENT:StopSprayLoop()
    self.NextSpraySoundTime = 0
    self.M134_SprayBurstEnd = 0
end

function ENT:PlaySpraySoundAndFlash(ct)
    self:EmitSpatialSound(
        M134_FIRE_SOUNDS[math.random(#M134_FIRE_SOUNDS)],
        self.CenterPos,
        WEAPON_LEVEL,
        math.random(96, 104),
        1.0
    )
    self:SpawnMuzzleFX()
    local fireDuration        = self.M134_SpraySoundDelay - self.M134_SprayPauseDuration
    self.M134_SprayBurstEnd  = ct + fireDuration
    self.NextShotTimeSpray   = ct
    self.NextSpraySoundTime  = ct + self.M134_SpraySoundDelay
end

-- ============================================================
-- TARGETING
-- ============================================================

function ENT:GetPrimaryTarget()
    local closest, closestDist = nil, math.huge
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = ply:GetPos():DistToSqr(self.CenterPos)
        if d < closestDist then closestDist = d closest = ply end
    end
    return closest
end

function ENT:GetTargetGroundPos()
    local target  = self:GetPrimaryTarget()
    local basePos
    if IsValid(target) then
        basePos = target:GetPos()
    else
        local tr = util.QuickTrace(Vector(self.CenterPos.x, self.CenterPos.y, self.sky), Vector(0,0,-30000), self)
        basePos = tr.HitPos
    end
    local offsetDist = math.Rand(self.M134_TargetOffsetMin, self.M134_TargetOffsetMax)
    local offsetDir  = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
    if offsetDir:LengthSqr() < 0.01 then offsetDir = Vector(1,0,0) end
    offsetDir:Normalize()
    return basePos + offsetDir * offsetDist
end

-- ============================================================
-- MUZZLE
-- Cycles through the three M134 gun positions 1→2→3→1
-- ============================================================

function ENT:GetWeaponMuzzleWorldPos()
    if self.MuzzleIndex < 1 or self.MuzzleIndex > #self.MuzzlePoints then
        self.MuzzleIndex = 1
    end
    local pos = self:LocalToWorld(self.MuzzlePoints[self.MuzzleIndex])
    self.MuzzleIndex = (self.MuzzleIndex % #self.MuzzlePoints) + 1
    return pos
end

function ENT:SpawnMuzzleFX()
    local worldPos = self:LocalToWorld(self.MuzzlePoints[self.MuzzleIndex])
    local ang      = self:GetAngles()
    local ed = EffectData()
    ed:SetOrigin(worldPos) ed:SetAngles(ang) ed:SetScale(0.6)
    util.Effect("cball_explode", ed, true, true)
    for _ = 1, 2 do
        local sp = EffectData()
        sp:SetOrigin(worldPos + Vector(math.Rand(-3,3), math.Rand(-3,3), 0))
        sp:SetNormal(ang:Up()) sp:SetScale(0.6) sp:SetMagnitude(0.6) sp:SetRadius(5)
        util.Effect("ManhackSparks", sp, true, true)
    end
end

-- ============================================================
-- M134 BURST FIRE
-- ============================================================

function ENT:FireM134BulletAt(muzzlePos, impactPos)
    local dir = impactPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    local bullet = ents.Create("ent_ac47_m134_bullet")
    if not IsValid(bullet) then return end
    bullet:SetPos(muzzlePos)
    bullet:SetAngles(dir:Angle())
    bullet.Firer    = self
    bullet.BulletDmg = self.M134_BulletDamage
    bullet:Spawn()
    bullet:Activate()
end

function ENT:UpdateM134BurstsSchedule(ct)
    if not self.M134_BurstTimes then return end
    for i, t in ipairs(self.M134_BurstTimes) do
        if t ~= false and ct >= t and ct < self.WeaponWindowEnd then
            self:StartM134Burst()
            self.M134_BurstTimes[i] = false
            self.M134_BurstsFired   = self.M134_BurstsFired + 1
        end
    end
end

function ENT:StartM134Burst()
    local targetPos = self:GetTargetGroundPos()
    local sweepDir  = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
    if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1,0,0) end
    sweepDir:Normalize()
    self.M134_SweepStartPos = targetPos - sweepDir * self.M134_SweepHalfLength
    self.M134_SweepEndPos   = targetPos + sweepDir * self.M134_SweepHalfLength
    table.insert(self.M134_ActiveBursts, { bulletsFired = 0, nextTime = CurTime() })
    self:SpawnMuzzleFX()
    self:EmitSpatialSound(
        M134_FIRE_SOUNDS[math.random(#M134_FIRE_SOUNDS)],
        self.CenterPos,
        WEAPON_LEVEL,
        math.random(96, 104),
        1.0
    )
end

function ENT:UpdateActiveM134Bursts(ct)
    if not self.M134_ActiveBursts then return end
    for idx = #self.M134_ActiveBursts, 1, -1 do
        local burst = self.M134_ActiveBursts[idx]
        if not burst then
            table.remove(self.M134_ActiveBursts, idx)
        elseif ct >= burst.nextTime then
            burst.bulletsFired = burst.bulletsFired + 1
            burst.nextTime     = ct + self.M134_BurstDelay
            self:FireSingleM134Bullet(burst.bulletsFired)
            if burst.bulletsFired >= self.M134_BurstCount then
                table.remove(self.M134_ActiveBursts, idx)
            end
        end
    end
end

function ENT:FireSingleM134Bullet(bulletIndex)
    if not self.M134_SweepStartPos then return end
    local fraction   = math.Clamp((bulletIndex - 1) / (self.M134_BurstCount - 1), 0, 1)
    local baseImpact = LerpVector(fraction, self.M134_SweepStartPos, self.M134_SweepEndPos)
    local jitter     = Vector(
        math.Rand(-self.M134_JitterAmount, self.M134_JitterAmount),
        math.Rand(-self.M134_JitterAmount, self.M134_JitterAmount),
        0
    )
    local muzzlePos = self:GetWeaponMuzzleWorldPos()
    self:FireM134BulletAt(muzzlePos, baseImpact + jitter)
end

function ENT:UpdateM134Spray(ct)
    if ct >= self.WeaponWindowEnd then self:StopSprayLoop() return end
    if self.NextSpraySoundTime > 0 and ct >= self.NextSpraySoundTime then
        self:PlaySpraySoundAndFlash(ct)
    end
    if ct >= (self.M134_SprayBurstEnd or 0) then return end
    if ct < self.NextShotTimeSpray then return end
    self.NextShotTimeSpray     = ct + self.M134_BurstDelay
    self.M134_SprayBulletCount = self.M134_SprayBulletCount + 1
    local targetPos = self:GetTargetGroundPos()
    local finalImpact = targetPos + Vector(
        math.Rand(-self.M134_JitterAmount * 2, self.M134_JitterAmount * 2),
        math.Rand(-self.M134_JitterAmount * 2, self.M134_JitterAmount * 2),
        0
    )
    local muzzlePos = self:GetWeaponMuzzleWorldPos()
    self:FireM134BulletAt(muzzlePos, finalImpact)
end

-- ============================================================
-- UTILITY
-- ============================================================

function ENT:FindGround(centerPos)
    local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
    local endPos     = Vector(centerPos.x, centerPos.y, -16384)
    local filterList = { self }
    local trace      = { start = startPos, endpos = endPos, filter = filterList }
    local maxN = 0
    while maxN < 100 do
        local tr = util.TraceLine(trace)
        if tr.HitWorld then return tr.HitPos.z end
        if IsValid(tr.Entity) then table.insert(filterList, tr.Entity)
        else break end
        maxN = maxN + 1
    end
    return -1
end

function ENT:OnRemove()
    if self.EngineLoop then self.EngineLoop:Stop() self.EngineLoop = nil end
    if not self.IsDestroyed then self:StopSprayLoop() end
    pending_sounds = {}
end

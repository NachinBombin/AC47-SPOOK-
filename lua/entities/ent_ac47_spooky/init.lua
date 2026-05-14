AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_trailsystem.lua")
include("shared.lua")

-- ============================================================
-- SOUNDS
-- ============================================================

util.PrecacheSound("lfs/tfre_ac47/m134_shoot.wav")
util.PrecacheSound("lfs/tfre_ac47/m134_shoot2.wav")
util.PrecacheSound("lfs/tfre_ac47/m134_shoot3.wav")
util.PrecacheSound("lfs/tfre_ac47/m134_stop.wav")
util.PrecacheSound("lfs/tfre_ac47/skytrain_engine_start.wav")
util.PrecacheSound("lfs/tfre_ac47/skytrain_engine_stop.wav")
util.PrecacheSound("lfs/tfre_ac47/skytrain_engine_1rpm.wav")
util.PrecacheSound("lfs/tfre_ac47/skytrain_engine_2rpm.wav")
util.PrecacheSound("lfs/tfre_ac47/skytrain_engine_3rpm.wav")
util.PrecacheSound("lfs/tfre_ac47/skytrain_engine_4rpm.wav")
util.PrecacheSound("lfs/tfre_ac47/skytrain_engine_far.wav")

-- ============================================================
-- NET STRINGS
-- ============================================================

util.AddNetworkString("ac47_plane_damage_tier")
util.AddNetworkString("ac47_plane_spatial_sound")
util.AddNetworkString("ac47_gun_sound")
util.AddNetworkString("ac47_muzzle_flash")

-- ============================================================
-- SPATIAL SOUND SYSTEM
-- ============================================================

local SOUND_SPEED     = 8200
local MAX_HEAR_DIST   = 88000
local VOL_FALLOFF_EXP = 0.01
local NEAR_OFFSET     = 40

function ENT:EmitSpatialSound(soundPath, originPos, soundLevel, pitch, baseVol)
    local sendAt   = CurTime()
    local entIndex = self:EntIndex()
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
        self.pending_sounds[#self.pending_sounds + 1] = {
            sendTime  = sendAt + delay,
            ply       = ply,
            soundPath = soundPath,
            nearPos   = nearPos,
            level     = soundLevel,
            pitch     = pitch,
            volume    = vol,
            entIndex  = entIndex,
        }
    end
end

function ENT:FlushPendingSounds()
    if #self.pending_sounds == 0 then return end
    local ct   = CurTime()
    local keep = {}
    for _, entry in ipairs(self.pending_sounds) do
        if ct >= entry.sendTime then
            if IsValid(entry.ply) then
                net.Start("ac47_plane_spatial_sound")
                    net.WriteString(entry.soundPath)
                    net.WriteVector(entry.nearPos)
                    net.WriteUInt(entry.level, 8)
                    net.WriteUInt(entry.pitch, 8)
                    net.WriteFloat(entry.volume)
                    net.WriteUInt(entry.entIndex, 16)
                net.Send(entry.ply)
            end
        else
            keep[#keep + 1] = entry
        end
    end
    self.pending_sounds = keep
end

-- ============================================================
-- GUN SOUND BROADCAST
-- ============================================================

function ENT:BroadcastGunSound(gunIdx, isStart)
    if self.GunFiring[gunIdx] == isStart then return end
    self.GunFiring[gunIdx] = isStart
    net.Start("ac47_gun_sound")
        net.WriteUInt(self:EntIndex(), 16)
        net.WriteUInt(gunIdx, 8)
        net.WriteBool(isStart)
    net.Broadcast()
end

-- ============================================================
-- CONSTANTS
-- ============================================================

local MUZZLE_POINTS = {
    Vector(-170, 66, 101.44),
    Vector(-208, 66, 95),
    Vector(-259, 66, 85.6),
}

local GUN_BONES = { 22, 23, 24 }

local BURST_DELAY          = 0.033
local BURST_COUNT          = 40
local BULLET_DAMAGE        = 18
local SWEEP_HALF           = 500
local JITTER               = 180
local TARGET_OFF_MIN       = 200
local TARGET_OFF_MAX       = 700
local PEACEFUL_MIN         = 4
local PEACEFUL_MAX         = 7
local WEAPON_WINDOW        = 10
local SPRAY_SOUND_DELAY    = 1.2
local SPRAY_PAUSE_DURATION = 0.5
local MUZZLE_FLASH_EVERY   = 4

local LINE_APPROACH_DIST  = 3000
local LINE_BULLET_COUNT   = 60
local LINE_JITTER         = 40
local LINE_DELAY          = 0.025

local GUN_BARREL_STEP = 35
local CTRL_SMOOTH     = 10

-- ============================================================
-- TUMBLE / GIB CONSTANTS
-- ============================================================

local TUMBLE_DURATION      = 12       -- seconds of tumble before crash explosion
local TUMBLE_GRAVITY_SCALE = 1.0      -- multiplier applied to physenv gravity
local GIB_LIFETIME         = 40       -- seconds before each gib is removed

-- Same gib models as the AC-130 (b29 parts from the fonv pack)
local GIB_MODELS = {
    "models/fonv/vehicles/b29/parts/b29_partwing.mdl",
    "models/fonv/vehicles/b29/parts/b29_partwing.mdl",
    "models/fonv/vehicles/b29/parts/b29_partnose.mdl",
    "models/fonv/vehicles/b29/parts/b29_partprop.mdl",
    "models/fonv/vehicles/b29/parts/b29_partprop.mdl",
    "models/fonv/vehicles/b29/parts/b29_partprop.mdl",
    "models/fonv/vehicles/b29/parts/b29_parttube.mdl",
}

-- ============================================================
-- ENT PROPERTIES
-- ============================================================

ENT.Speed        = 280
ENT.OrbitRadius  = 2800
ENT.SkyHeightAdd = 5500
ENT.Lifetime     = 40
ENT.MaxHP        = 6000
ENT.DamageTierThresholds = { 0.75, 0.50, 0.25 }

-- ============================================================
-- DEBUG
-- ============================================================

function ENT:Debug(msg)
    print("[AC-47 Spooky] " .. tostring(msg))
end

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
    self.pending_sounds = {}

    self.CenterPos    = self.CenterPos    or self:GetPos()
    self.CallDir      = self.CallDir      or Vector(1, 0, 0)
    self.Lifetime     = self.Lifetime     or ENT.Lifetime
    self.Speed        = self.Speed        or ENT.Speed
    self.OrbitRadius  = self.OrbitRadius  or ENT.OrbitRadius
    self.SkyHeightAdd = self.SkyHeightAdd or ENT.SkyHeightAdd

    if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1, 0, 0) end
    self.CallDir.z = 0
    self.CallDir:Normalize()

    local ground = self:FindGround(self.CenterPos)
    if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

    self.sky       = ground + self.SkyHeightAdd
    self.DieTime   = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    local spawnPos = self.CenterPos - self.CallDir * 2000
    spawnPos = Vector(spawnPos.x, spawnPos.y, self.sky)
    if not util.IsInWorld(spawnPos) then
        spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
    end
    if not util.IsInWorld(spawnPos) then
        self:Debug("spawnPos out of world")
        self:Remove()
        return
    end

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

    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    self.AltDriftRange    = 250
    self.AltDriftLerp     = 0.001

    self.JitterPhase     = math.Rand(0, math.pi * 2)
    self.JitterAmplitude = 4
    self.SmoothedRoll    = 0
    self.SmoothedPitch   = 0
    self.SmoothedYaw     = 0
    self.PrevYaw         = self:GetAngles().y

    self.ctrlSmPitch = 0
    self.ctrlSmYaw   = 0
    self.ctrlSmRoll  = 0

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
    end

    self:EmitSpatialSound("lfs/tfre_ac47/skytrain_engine_4rpm.wav", self:GetPos(), 155, 100, 1.0)
    self:EmitSpatialSound("lfs/tfre_ac47/skytrain_engine_far.wav",  self:GetPos(), 155, 100, 1.0)
    self:EmitSound("lfs/tfre_ac47/skytrain_engine_start.wav", 125, 100, 1.0)

    self.PropAngle     = 0
    self.GunBarrelStep = { 0, 0, 0 }
    self.GunFiring     = { false, false, false }

    self.Guns = {}
    local ct = CurTime()
    for i = 1, 3 do
        self.Guns[i] = {
            MuzzleIndex      = i,
            IsPeaceful       = true,
            PeacefulUntil    = ct + math.Rand(0, PEACEFUL_MAX) * (i - 1),
            PendingWeapon    = nil,
            CurrentWeapon    = nil,
            WeaponWindowEnd  = 0,
            BurstTimes       = {},
            ActiveBursts     = {},
            SweepStart       = nil,
            SweepEnd         = nil,
            NextShotTime     = 0,
            NextSoundTime    = 0,
            SprayBurstEnd    = 0,
            SprayBulletCount = 0,
            LineBulletsFired = 0,
            LineNextShotTime = 0,
            LineStartPos     = nil,
            LineEndPos       = nil,
            AimOffset = Vector(math.Rand(-120, 120), math.Rand(-120, 120), 0),
        }
    end

    self.IsDestroyed    = false
    self.DamageTier     = 0
    -- Tumble state (ported from AN-71)
    self.IsTumbling        = false
    self.TumbleVelocity    = Vector(0, 0, 0)
    self.TumbleAngVelocity = Vector(0, 0, 0)
    self._CrashFired       = false

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

function ENT:StopAllGunSounds()
    for i = 1, 3 do
        self:BroadcastGunSound(i, false)
    end
end

-- ============================================================
-- DESTROY → TUMBLE → CRASH  (ported from AN-71)
-- ============================================================

function ENT:DestroyPlane()
    if self.IsDestroyed then return end
    self.IsDestroyed = true
    self:StopAllGunSounds()
    self:BroadcastDamageTier(3)   -- tier 3 = destroyed, drives heavy smoke on client
    self:EmitSound("lfs/tfre_ac47/skytrain_engine_stop.wav", 125, 100, 1.0)
    self:StartTumble()

    -- Safety-net timer: if CrashExplode hasn't fired yet, call it.
    -- Guards against entity-slot recycling by checking class.
    local entIdx = self:EntIndex()
    timer.Simple(TUMBLE_DURATION + 5, function()
        local ent = Entity(entIdx)
        if IsValid(ent)
            and not ent:IsMarkedForDeletion()
            and ent:GetClass() == "ent_ac47_spooky"
            and not ent._CrashFired
        then
            ent:CrashExplode()
        end
    end)
end

function ENT:StartTumble()
    self.IsTumbling = true

    -- Inherit current forward velocity and begin falling
    local fwd = self:GetAngles():Forward()
    self.TumbleVelocity = fwd * self.Speed
    self.TumbleVelocity.z = -200

    -- Random spin rates (degrees/s) matching AN-71 ranges
    self.TumbleAngVelocity = Vector(
        math.Rand(-300, 300),   -- pitch spin
        math.Rand(150, 400),    -- yaw spin
        math.Rand(-250, 250)    -- roll spin
    )

    -- Immediate impact effect at current position
    local pos = self.LastPos or self:GetPos()
    local ed = EffectData()
    ed:SetOrigin(pos) ed:SetScale(5) ed:SetMagnitude(5) ed:SetRadius(500)
    util.Effect("500lb_air", ed, true, true)
    sound.Play("ambient/explosions/explode_8.wav", pos, 140, 90, 1.0)

    -- Schedule the ground crash
    local entIdx = self:EntIndex()
    timer.Simple(TUMBLE_DURATION, function()
        local ent = Entity(entIdx)
        if IsValid(ent)
            and not ent:IsMarkedForDeletion()
            and ent:GetClass() == "ent_ac47_spooky"
            and not ent._CrashFired
        then
            ent:CrashExplode()
        end
    end)
end

function ENT:CrashExplode()
    if self._CrashFired then return end
    self._CrashFired = true

    local pos = self.LastPos or self:GetPos()

    -- Multi-layer explosion VFX
    local function boom(p, sc)
        local ed = EffectData()
        ed:SetOrigin(p) ed:SetScale(sc) ed:SetMagnitude(sc) ed:SetRadius(sc * 100)
        util.Effect("HelicopterMegaBomb", ed, true, true)
        local ed2 = EffectData()
        ed2:SetOrigin(p) ed2:SetScale(sc) ed2:SetMagnitude(sc) ed2:SetRadius(sc * 100)
        util.Effect("500lb_air", ed2, true, true)
    end
    boom(pos, 8)
    boom(pos + Vector(0, 0,  80), 5)
    boom(pos + Vector(0, 0, 160), 4)
    boom(pos + Vector(0, 0, 260), 3)

    sound.Play("ambient/explosions/explode_8.wav", pos, 145, 80,  1.0)
    sound.Play("weapon_AWP.Single",               pos, 148, 55,  1.0)
    util.BlastDamage(self, self, pos, 450, 220)

    self:SpawnGibs(pos)

    -- Small delay before removing the main hull so gibs have a frame to appear
    local entIdx = self:EntIndex()
    timer.Simple(0.1, function()
        local ent = Entity(entIdx)
        if IsValid(ent) and ent:GetClass() == "ent_ac47_spooky" then
            ent:Remove()
        end
    end)
end

-- ============================================================
-- GIB SPAWNER
-- Each gib is staggered 0.1s apart to avoid a bulk-spawn lag spike.
-- Ignite is deferred one tick (timer.Simple(0)) after Activate so
-- the entity fire system is fully ready -- this is the reliable pattern.
-- ============================================================

function ENT:SpawnGibs(origin)
    for idx, mdl in ipairs(GIB_MODELS) do
        -- Stagger each gib by 0.1 s to avoid a single-frame physics spike
        timer.Simple((idx - 1) * 0.1, function()
            if not origin then return end

            local pos = origin + Vector(
                math.Rand(-150, 150),
                math.Rand(-150, 150),
                math.Rand(  20, 100)
            )

            -- Clamp to world bounds
            if not util.IsInWorld(pos) then pos = origin end

            local gib = ents.Create("prop_physics")
            if not IsValid(gib) then return end

            gib:SetModel(mdl)
            gib:SetPos(pos)
            gib:SetAngles(Angle(
                math.Rand(0, 360),
                math.Rand(0, 360),
                math.Rand(0, 360)
            ))
            gib:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
            gib:Spawn()
            gib:Activate()

            local phys = gib:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetMass(2000)
                phys:SetDragCoefficient(0)
                phys:SetAngleDragCoefficient(0)
                phys:EnableGravity(true)
                -- Outward explosion impulse
                phys:ApplyForceCenter(Vector(
                    math.Rand(-400, 400),
                    math.Rand(-400, 400),
                    math.Rand( 300, 900)
                ) * 2000)
                -- Tumbling torque
                phys:ApplyTorqueCenter(Vector(
                    math.Rand(-2000, 2000),
                    math.Rand(-2000, 2000),
                    math.Rand(-2000, 2000)
                ))
            end

            -- Ignite must be deferred by one tick after Activate()
            timer.Simple(0, function()
                if IsValid(gib) then
                    gib:Ignite(GIB_LIFETIME, 0)
                end
            end)

            -- Auto-remove after lifetime
            timer.Simple(GIB_LIFETIME, function()
                if IsValid(gib) then gib:Remove() end
            end)
        end)
    end
end

function ENT:StopEngineSounds()
    self:BroadcastDamageTier(0)
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
    if not self.DieTime or not self.SpawnTime then
        self:NextThink(CurTime() + 0.1)
        return true
    end
    local ct = CurTime()
    if ct >= self.DieTime then
        self:StopAllGunSounds()
        self:Remove()
        return
    end
    if not IsValid(self.PhysObj) then self.PhysObj = self:GetPhysicsObject() end
    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then self.PhysObj:Wake() end
    self:FlushPendingSounds()

    if self.Guns and not self.IsDestroyed then
        for i = 1, 3 do
            self:HandleGunWindow(i, ct)
        end
    end

    self:NextThink(ct)
    return true
end

-- ============================================================
-- PHYSICS UPDATE
-- ============================================================

function ENT:PhysicsUpdate(phys)
    if not self.DieTime or not self.sky then return end
    if CurTime() >= self.DieTime then self:Remove() return end

    local pos = self:GetPos()
    self.LastPos = pos
    local ft = engine.TickInterval()

    -- ── TUMBLE PATH (ported from AN-71) ──────────────────────────────────────
    if self.IsTumbling then
        -- Integrate gravity into vertical velocity each tick
        local gravZ = physenv.GetGravity().z * TUMBLE_GRAVITY_SCALE
        self.TumbleVelocity.z = self.TumbleVelocity.z + gravZ * ft

        local newPos = pos + self.TumbleVelocity * ft
        if not util.IsInWorld(newPos) then newPos = pos end

        -- Integrate angular velocity into angles
        local curAng  = self:GetAngles()
        local newAng  = Angle(
            curAng.p + self.TumbleAngVelocity.x * ft,
            curAng.y + self.TumbleAngVelocity.y * ft,
            curAng.r + self.TumbleAngVelocity.z * ft
        )

        phys:SetPos(newPos)
        phys:SetAngles(newAng)
        phys:SetVelocity(self.TumbleVelocity)
        return
    end
    -- ── NORMAL ORBIT PATH ────────────────────────────────────────────────────

    if CurTime() >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
        self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    end
    self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)
    self.JitterPhase     = self.JitterPhase + 0.02
    local liveAlt = self.AltDriftCurrent + math.sin(self.JitterPhase) * self.JitterAmplitude

    local flatDist = Vector(pos.x - self.CenterPos.x, pos.y - self.CenterPos.y, 0):Length()
    local orbitYaw = 0
    if flatDist > self.OrbitRadius and (self.TurnDelay or 0) < CurTime() then
        orbitYaw       = 0.1
        self.TurnDelay = CurTime() + 0.02
    end
    local trSky = util.QuickTrace(pos, self:GetForward() * 3000, self)
    local skyYaw = trSky.HitSky and 0.3 or 0

    self.ang = self.ang + Angle(0, orbitYaw + skyYaw, 0)
    local currentYaw  = self.ang.y
    local rawYawDelta = math.NormalizeAngle(currentYaw - (self.PrevYaw or currentYaw))
    self.PrevYaw      = currentYaw

    local targetRoll  = math.Clamp(rawYawDelta * -18, -15, 15)
    local rollLerp    = rawYawDelta ~= 0 and 0.08 or 0.04
    self.SmoothedRoll  = Lerp(rollLerp, self.SmoothedRoll,  targetRoll)
    local forward     = self.ang:Forward()
    local vel         = forward * self.Speed
    self.SmoothedPitch = Lerp(0.03, self.SmoothedPitch, math.Clamp(-vel.z * 0.02, -8, 8))

    local finalAng = Angle(self.SmoothedPitch, self.ang.y, self.SmoothedRoll)
    phys:SetAngles(finalAng)
    phys:SetPos(Vector(
        pos.x + vel.x * ft,
        pos.y + vel.y * ft,
        liveAlt
    ))
    phys:SetVelocity(vel)

    local propDegsPerTick = 36000 * ft
    self.PropAngle = (self.PropAngle + propDegsPerTick) % 360
    local propAng  = Angle(self.PropAngle, 0, 0)
    self:ManipulateBoneAngles(25, propAng)
    self:ManipulateBoneAngles(26, propAng)

    local smooth    = CTRL_SMOOTH * ft
    local ctrlPitch = self.SmoothedPitch * 0.12
    local ctrlRoll  = -self.SmoothedRoll
    local ctrlYaw   = rawYawDelta * 25

    self.ctrlSmPitch = self.ctrlSmPitch + (ctrlPitch - self.ctrlSmPitch) * smooth
    self.ctrlSmYaw   = self.ctrlSmYaw   + (ctrlYaw   - self.ctrlSmYaw)   * smooth
    self.ctrlSmRoll  = self.ctrlSmRoll  + (ctrlRoll  - self.ctrlSmRoll)  * smooth

    self:ManipulateBoneAngles(6, Angle(-self.ctrlSmRoll, 0, 0))
    self:ManipulateBoneAngles(7, Angle(-self.ctrlSmRoll, 0, 0))
    self:ManipulateBoneAngles(3, Angle(self.ctrlSmYaw, 0, 0))
    self:ManipulateBoneAngles(4, Angle(0, 0, self.ctrlSmPitch))
    self:ManipulateBoneAngles(5, Angle(0, 0, self.ctrlSmPitch))
end

-- ============================================================
-- THREE-GUN INDEPENDENT WEAPON CYCLE
-- ============================================================

function ENT:HandleGunWindow(gunIdx, ct)
    local g = self.Guns[gunIdx]
    if not g then return end
    if g.IsPeaceful then
        if self.GunFiring[gunIdx] then
            self:BroadcastGunSound(gunIdx, false)
        end
        if ct >= g.PeacefulUntil then
            g.IsPeaceful = false
            self:ArmGun(gunIdx, g.PendingWeapon, ct)
            g.PendingWeapon = nil
        end
        return
    end
    if not g.CurrentWeapon or ct >= g.WeaponWindowEnd then
        self:EnterGunPeaceful(gunIdx, ct)
        return
    end
    if     g.CurrentWeapon == "burst" then self:UpdateGunBurst(gunIdx, ct)
    elseif g.CurrentWeapon == "spray" then self:UpdateGunSpray(gunIdx, ct)
    elseif g.CurrentWeapon == "line"  then self:UpdateGunLine(gunIdx, ct) end
end

function ENT:EnterGunPeaceful(gunIdx, ct)
    local g = self.Guns[gunIdx]
    self:BroadcastGunSound(gunIdx, false)
    g.CurrentWeapon  = nil
    g.IsPeaceful     = true
    g.PeacefulUntil  = ct + math.Rand(PEACEFUL_MIN, PEACEFUL_MAX)
    local r = math.random(3)
    g.PendingWeapon  = r == 1 and "burst" or r == 2 and "spray" or "line"
    g.AimOffset = Vector(math.Rand(-120, 120), math.Rand(-120, 120), 0)
end

function ENT:ArmGun(gunIdx, weapon, ct)
    local g   = self.Guns[gunIdx]
    local r   = math.random(3)
    weapon    = weapon or (r == 1 and "burst" or r == 2 and "spray" or "line")
    g.CurrentWeapon   = weapon
    g.WeaponWindowEnd = ct + WEAPON_WINDOW
    local targetPos   = self:GetGunTargetPos(gunIdx)

    if weapon == "burst" then
        g.BurstTimes   = { ct, ct + 4 }
        g.ActiveBursts = {}
        g.SweepStart   = nil
        g.SweepEnd     = nil
        self:StartGunBurst(gunIdx, targetPos)
        g.BurstTimes[1] = false

    elseif weapon == "spray" then
        g.NextShotTime     = ct
        g.NextSoundTime    = ct
        g.SprayBulletCount = 0
        g.SprayBurstEnd    = ct + SPRAY_SOUND_DELAY
        local sweepDir = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
        if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1, 0, 0) end
        sweepDir:Normalize()
        g.SweepStart = targetPos - sweepDir * SWEEP_HALF
        g.SweepEnd   = targetPos + sweepDir * SWEEP_HALF
        self:BroadcastGunSound(gunIdx, true)

    elseif weapon == "line" then
        local planePos  = self:GetPos()
        local toTarget  = targetPos - Vector(planePos.x, planePos.y, targetPos.z)
        if toTarget:LengthSqr() < 1 then toTarget = self:GetForward() end
        toTarget.z = 0
        toTarget:Normalize()
        g.LineStartPos     = targetPos - toTarget * LINE_APPROACH_DIST
        g.LineEndPos       = targetPos
        g.LineBulletsFired = 0
        g.LineNextShotTime = ct
        self:BroadcastGunSound(gunIdx, true)
    end
end

function ENT:GetGunTargetPos(gunIdx)
    local g      = self.Guns[gunIdx]
    local target = self:GetPrimaryTarget()
    local basePos
    if IsValid(target) then
        basePos = target:GetPos()
    else
        local tr = util.QuickTrace(
            Vector(self.CenterPos.x, self.CenterPos.y, self.sky),
            Vector(0, 0, -30000), self)
        basePos = tr.HitPos
    end
    local offsetDist = math.Rand(TARGET_OFF_MIN, TARGET_OFF_MAX)
    local offsetDir  = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
    if offsetDir:LengthSqr() < 0.01 then offsetDir = Vector(1, 0, 0) end
    offsetDir:Normalize()
    return basePos + offsetDir * offsetDist + (g and g.AimOffset or Vector(0,0,0))
end

-- ─── BURST ───────────────────────────────────────────────────────────────────

function ENT:UpdateGunBurst(gunIdx, ct)
    local g = self.Guns[gunIdx]
    for i, t in ipairs(g.BurstTimes) do
        if t ~= false and ct >= t and ct < g.WeaponWindowEnd then
            self:StartGunBurst(gunIdx, self:GetGunTargetPos(gunIdx))
            g.BurstTimes[i] = false
        end
    end
    local active    = g.ActiveBursts
    local anyActive = false
    for idx = #active, 1, -1 do
        local burst = active[idx]
        if not burst then table.remove(active, idx) continue end
        if ct >= burst.nextTime then
            burst.bulletsFired = burst.bulletsFired + 1
            burst.nextTime     = ct + BURST_DELAY
            self:FireGunBullet(gunIdx, burst)
            if burst.bulletsFired % MUZZLE_FLASH_EVERY == 0 then
                self:SpawnGunMuzzleFX(gunIdx)
            end
            if burst.bulletsFired >= BURST_COUNT then
                table.remove(active, idx)
            else
                anyActive = true
            end
        else
            anyActive = true
        end
    end
    self:BroadcastGunSound(gunIdx, anyActive)
end

function ENT:StartGunBurst(gunIdx, targetPos)
    local g = self.Guns[gunIdx]
    local sweepDir = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
    if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1, 0, 0) end
    sweepDir:Normalize()
    g.SweepStart = targetPos - sweepDir * SWEEP_HALF
    g.SweepEnd   = targetPos + sweepDir * SWEEP_HALF
    table.insert(g.ActiveBursts, { bulletsFired = 0, nextTime = CurTime() })

    self.GunBarrelStep[gunIdx] = (self.GunBarrelStep[gunIdx] + GUN_BARREL_STEP) % 360
    self:ManipulateBoneAngles(GUN_BONES[gunIdx], Angle(self.GunBarrelStep[gunIdx], 0, 0))
    self:SpawnGunMuzzleFX(gunIdx)
end

function ENT:FireGunBullet(gunIdx, burst)
    local g = self.Guns[gunIdx]
    if not g.SweepStart then return end
    local fraction   = math.Clamp((burst.bulletsFired - 1) / (BURST_COUNT - 1), 0, 1)
    local baseImpact = LerpVector(fraction, g.SweepStart, g.SweepEnd)
    local muzzlePos  = self:LocalToWorld(MUZZLE_POINTS[g.MuzzleIndex])
    self:FireM134BulletAt(muzzlePos, baseImpact + Vector(
        math.Rand(-JITTER, JITTER),
        math.Rand(-JITTER, JITTER),
        0
    ))
end

-- ─── SPRAY ───────────────────────────────────────────────────────────────────

function ENT:UpdateGunSpray(gunIdx, ct)
    local g = self.Guns[gunIdx]
    if ct >= g.WeaponWindowEnd then
        self:BroadcastGunSound(gunIdx, false)
        return
    end
    if g.NextSoundTime > 0 and ct >= g.NextSoundTime then
        self:SpawnGunMuzzleFX(gunIdx)
        self.GunBarrelStep[gunIdx] = (self.GunBarrelStep[gunIdx] + GUN_BARREL_STEP) % 360
        self:ManipulateBoneAngles(GUN_BONES[gunIdx], Angle(self.GunBarrelStep[gunIdx], 0, 0))
        g.SprayBurstEnd = ct + (SPRAY_SOUND_DELAY - SPRAY_PAUSE_DURATION)
        g.NextShotTime  = ct
        g.NextSoundTime = ct + SPRAY_SOUND_DELAY
    end
    if ct >= g.SprayBurstEnd then
        self:BroadcastGunSound(gunIdx, false)
        return
    end
    self:BroadcastGunSound(gunIdx, true)
    if ct < g.NextShotTime then return end
    g.NextShotTime     = ct + BURST_DELAY
    g.SprayBulletCount = g.SprayBulletCount + 1
    if g.SprayBulletCount % MUZZLE_FLASH_EVERY == 0 then
        self:SpawnGunMuzzleFX(gunIdx)
    end
    local muzzlePos = self:LocalToWorld(MUZZLE_POINTS[g.MuzzleIndex])
    local targetPos = self:GetGunTargetPos(gunIdx)
    self:FireM134BulletAt(muzzlePos, targetPos + Vector(
        math.Rand(-JITTER * 2, JITTER * 2),
        math.Rand(-JITTER * 2, JITTER * 2),
        0
    ))
end

-- ─── LINE ────────────────────────────────────────────────────────────────────

function ENT:UpdateGunLine(gunIdx, ct)
    local g = self.Guns[gunIdx]
    if ct >= g.WeaponWindowEnd then
        self:BroadcastGunSound(gunIdx, false)
        return
    end
    if not g.LineStartPos then
        local targetPos = self:GetGunTargetPos(gunIdx)
        local planePos  = self:GetPos()
        local toTarget  = targetPos - Vector(planePos.x, planePos.y, targetPos.z)
        if toTarget:LengthSqr() < 1 then toTarget = self:GetForward() end
        toTarget.z = 0
        toTarget:Normalize()
        g.LineStartPos     = targetPos - toTarget * LINE_APPROACH_DIST
        g.LineEndPos       = targetPos
        g.LineBulletsFired = 0
        g.LineNextShotTime = ct
    end
    if ct < g.LineNextShotTime then return end

    local fraction  = math.Clamp(g.LineBulletsFired / (LINE_BULLET_COUNT - 1), 0, 1)
    local groundPos = LerpVector(fraction, g.LineStartPos, g.LineEndPos)
    local muzzlePos = self:LocalToWorld(MUZZLE_POINTS[g.MuzzleIndex])

    local lineDir = g.LineEndPos - g.LineStartPos
    lineDir.z = 0
    if lineDir:LengthSqr() > 1 then lineDir:Normalize() end
    local perp = Vector(-lineDir.y, lineDir.x, 0)

    self:FireM134BulletAt(muzzlePos,
        groundPos
        + perp    * math.Rand(-LINE_JITTER, LINE_JITTER)
        + lineDir * math.Rand(-LINE_JITTER * 0.5, LINE_JITTER * 0.5)
    )

    if g.LineBulletsFired % MUZZLE_FLASH_EVERY == 0 then
        self:SpawnGunMuzzleFX(gunIdx)
        self.GunBarrelStep[gunIdx] = (self.GunBarrelStep[gunIdx] + GUN_BARREL_STEP) % 360
        self:ManipulateBoneAngles(GUN_BONES[gunIdx], Angle(self.GunBarrelStep[gunIdx], 0, 0))
    end

    g.LineBulletsFired = g.LineBulletsFired + 1
    g.LineNextShotTime = ct + LINE_DELAY

    if g.LineBulletsFired >= LINE_BULLET_COUNT then
        g.LineStartPos = nil
        g.LineEndPos   = nil
        self:BroadcastGunSound(gunIdx, false)
        self:EnterGunPeaceful(gunIdx, ct)
    end
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
    local refPlayer = nil
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then refPlayer = ply break end
    end
    if refPlayer then
        for _, npc in ipairs(ents.FindInSphere(self.CenterPos, 8000)) do
            if not IsValid(npc) or not npc:IsNPC() then continue end
            if npc:Disposition(refPlayer) ~= D_HT then continue end
            local d = npc:GetPos():DistToSqr(self.CenterPos)
            if d < closestDist then closestDist = d closest = npc end
        end
    end
    return closest
end

-- ============================================================
-- MUZZLE FX
-- ============================================================

function ENT:SpawnGunMuzzleFX(gunIdx)
    local g        = self.Guns[gunIdx]
    local worldPos = self:LocalToWorld(MUZZLE_POINTS[g.MuzzleIndex])
    net.Start("ac47_muzzle_flash")
        net.WriteVector(worldPos)
    net.Broadcast()
end

-- ============================================================
-- BULLET SPAWN
-- ============================================================

function ENT:FireM134BulletAt(muzzlePos, impactPos)
    local dir = impactPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()
    if ac47_m134_spawn then
        ac47_m134_spawn(self, self, muzzlePos, dir, BULLET_DAMAGE, nil)
    else
        self:Debug("WARN: ac47_m134_spawn not available -- bullet skipped")
    end
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
    self:StopEngineSounds()
    self.pending_sounds = {}
end

-- AC-47 Spooky | init.lua  (SERVER)
-- Three M134 Minigun barrels mounted on the port (left) side.
-- Each gun is fully independent:
--   * own peaceful timer before first fire and between windows
--   * own weapon window duration
--   * own burst + pause schedule
--   * own muzzle world position
--   * own barrel bone (22, 23, 24)
--
-- Rotor RPM logic: always treated as max (blur forced in cl_init).
-- No .50cal, no 40mm, no JASSM -- those are NOT on this aircraft.

AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )
include( "shared.lua" )

-- ============================================================
-- GUN DEFINITIONS
-- One table per barrel. Order: front, mid, rear (port side).
-- Local-space positions confirmed from original AC-47 source.
-- ============================================================

local GUNS = {
    {
        -- Gun 1: forward barrel
        muzzleLocal  = Vector(-170, 66, 101.44),
        barrelBone   = 22,
        -- Aim: 10 deg nose-down, 90 deg left (port broadside fire)
        aimAngle     = Angle(10, 90, 0),
        spread       = Vector(0.022, 0.022, 0),
        damage       = 18,
        force        = 30,
        hullSize     = 6,
        ammoType     = "Pistol",
        tracerName   = "lfs_tracer_red",
        tracerEvery  = 1,
        -- Timing
        peacefulMin      = 4,    -- min seconds idle between windows
        peacefulMax      = 7,    -- max seconds idle between windows
        windowTime       = 8,    -- seconds the gun is allowed to fire
        shotDelay        = 0.033,-- time between bullets (~900 rpm)
        bulletsPerBurst  = 60,   -- bullets fired before a pause
        pauseBetweenBursts = 0.6,-- silence gap after each burst
    },
    {
        -- Gun 2: mid barrel
        muzzleLocal  = Vector(-208, 66, 95),
        barrelBone   = 23,
        aimAngle     = Angle(10, 90, 0),
        spread       = Vector(0.022, 0.022, 0),
        damage       = 18,
        force        = 30,
        hullSize     = 6,
        ammoType     = "Pistol",
        tracerName   = "lfs_tracer_red",
        tracerEvery  = 1,
        peacefulMin      = 4,
        peacefulMax      = 7,
        windowTime       = 8,
        shotDelay        = 0.033,
        bulletsPerBurst  = 60,
        pauseBetweenBursts = 0.6,
    },
    {
        -- Gun 3: rear barrel
        muzzleLocal  = Vector(-259, 66, 85.6),
        barrelBone   = 24,
        aimAngle     = Angle(10, 90, 0),
        spread       = Vector(0.022, 0.022, 0),
        damage       = 18,
        force        = 30,
        hullSize     = 6,
        ammoType     = "Pistol",
        tracerName   = "lfs_tracer_red",
        tracerEvery  = 1,
        peacefulMin      = 5,    -- slightly longer stagger for rear gun
        peacefulMax      = 9,
        windowTime       = 8,
        shotDelay        = 0.033,
        bulletsPerBurst  = 60,
        pauseBetweenBursts = 0.6,
    },
}

-- ============================================================
-- SPAWN FUNCTION (required by LFS)
-- ============================================================

function ENT:SpawnFunction( ply, tr, ClassName )
    if not tr.Hit then return end
    local ent = ents.Create( ClassName )
    ent:SetPos( tr.HitPos + tr.HitNormal * 200 )
    ent:Spawn()
    ent:Activate()
    return ent
end

-- ============================================================
-- AI BODYGROUP (inherited from original)
-- Bodygroup 1: 0 = no AI mesh, 1 = AI mesh visible
-- ============================================================

function ENT:CreateAI()
    self:SetBodygroup( 1, 1 )
end

function ENT:RemoveAI()
    self:SetBodygroup( 1, 0 )
end

-- ============================================================
-- SEAT SETUP
-- ============================================================

function ENT:RunOnSpawn()
    self:SetGunnerSeat( self:AddPassengerSeat( Vector(127, 18, 135), Angle(0, -90, 11) ) )
end

-- ============================================================
-- ENGINE EVENTS
-- ============================================================

function ENT:OnEngineStarted()
    self:EmitSound( "TFRE_AC47_ENGINESTART" )
end

function ENT:OnEngineStopped()
    self:EmitSound( "TFRE_AC47_ENGINESTOP" )
end

function ENT:OnLandingGearToggled( bOn )
    self:EmitSound( "lfs/bf109/gear.wav" )
end

function ENT:GetMissileOffset()
    return Vector(0, 0, -5)
end

-- ============================================================
-- WEAPON STATE INIT
-- Called once from HandleWeapons on first Think.
-- Each gun gets its own independent state table.
-- Stagger initial peaceful window so all three don't open at once.
-- ============================================================

function ENT:InitGunStates()
    if self._gunsReady then return end
    self._gunsReady = true

    local ct = CurTime()
    -- Stagger offsets (seconds) so the three guns don't all fire together initially.
    local stagger = { 0, 2.5, 5.0 }

    self._gunState = {}
    for i, gun in ipairs( GUNS ) do
        self._gunState[i] = {
            phase            = "peaceful",
            nextPhaseTime    = ct + math.Rand(gun.peacefulMin, gun.peacefulMax) + stagger[i],
            windowStart      = 0,
            -- burst sub-state
            burstBullets     = 0,
            burstPauseEnd    = 0,
            nextShotTime     = 0,
            -- bone spin accumulator
            boneAngle        = 0,
            -- looping fire sound handle
            soundObj         = nil,
            soundActive      = false,
        }
    end
end

-- ============================================================
-- SINGLE-GUN TICK
-- ============================================================

function ENT:TickGun( idx, ct )
    local gun = GUNS[idx]
    local st  = self._gunState[idx]

    -- ---- PEACEFUL PHASE ----
    if st.phase == "peaceful" then
        if ct < st.nextPhaseTime then return end
        -- Open the weapon window
        st.phase         = "window"
        st.windowStart   = ct
        st.nextPhaseTime = ct + gun.windowTime
        st.burstBullets  = 0
        st.burstPauseEnd = 0
        st.nextShotTime  = ct
        return
    end

    -- ---- WINDOW PHASE ----
    if ct >= st.nextPhaseTime then
        -- Window expired; silence the gun and enter peaceful.
        self:GunSoundStop( st, gun )
        st.phase         = "peaceful"
        st.nextPhaseTime = ct + math.Rand(gun.peacefulMin, gun.peacefulMax)
        return
    end

    -- Inside a burst-pause gap: wait silently.
    if st.burstPauseEnd > 0 and ct < st.burstPauseEnd then
        self:GunSoundStop( st, gun )
        return
    end

    -- Burst refill: if we just finished a burst, start the pause.
    if st.burstBullets >= gun.bulletsPerBurst then
        self:GunSoundStop( st, gun )
        st.burstBullets  = 0
        st.burstPauseEnd = ct + gun.pauseBetweenBursts
        return
    end

    -- Rate limiter.
    if ct < st.nextShotTime then return end

    -- ---- FIRE ----
    self:GunSoundStart( st, gun )

    local muzzleWorld = self:LocalToWorld( gun.muzzleLocal )
    local fireDir     = self:LocalToWorldAngles( gun.aimAngle ):Forward()

    local bullet = {}
    bullet.Num        = 1
    bullet.Src        = muzzleWorld
    bullet.Dir        = fireDir
    bullet.Spread     = gun.spread
    bullet.Tracer     = gun.tracerEvery
    bullet.TracerName = gun.tracerName
    bullet.Force      = gun.force
    bullet.HullSize   = gun.hullSize
    bullet.Damage     = gun.damage
    bullet.Attacker   = self:GetDriver()
    bullet.AmmoType   = gun.ammoType
    bullet.Callback   = function( att, tr, dmginfo )
        dmginfo:SetDamageType( DMG_AIRBOAT )
    end
    self:FireBullets( bullet )

    -- Spin THIS gun's barrel bone only.
    st.boneAngle = st.boneAngle + 35
    self:ManipulateBoneAngles( gun.barrelBone, Angle(st.boneAngle, 0, 0) )

    st.burstBullets = st.burstBullets + 1
    st.nextShotTime = ct + gun.shotDelay
end

-- ============================================================
-- SOUND HELPERS
-- ============================================================

function ENT:GunSoundStart( st, gun )
    if st.soundActive then return end
    st.soundObj = CreateSound( self, "TFRE_AC47_M134_LOOP" )
    if st.soundObj then st.soundObj:Play() end
    st.soundActive = true
end

function ENT:GunSoundStop( st, gun )
    if not st.soundActive then return end
    if IsValid( st.soundObj ) then
        st.soundObj:Stop()
    end
    st.soundObj    = nil
    st.soundActive = false
    self:EmitSound( "TFRE_AC47_M134_LASTSHOT" )
end

-- ============================================================
-- HandleWeapons (called every Think by LFS base)
-- All three guns tick independently every frame.
-- Player fire inputs are intentionally left disconnected --
-- this is an autonomous AI gunship; the pilot flies, guns fire on their own.
-- ============================================================

function ENT:HandleWeapons( Fire1, Fire2 )
    self:InitGunStates()
    local ct = CurTime()
    self:TickGun(1, ct)
    self:TickGun(2, ct)
    self:TickGun(3, ct)
end

-- ============================================================
-- LANDING GEAR (full port from original, no changes)
-- ============================================================

function ENT:HandleLandingGear()
    local Driver = self:GetDriver()
    if IsValid( Driver ) then
        local KeyJump = Driver:KeyDown( IN_JUMP )
        if self.OldKeyJump ~= KeyJump then
            self.OldKeyJump = KeyJump
            if KeyJump then
                self:ToggleLandingGear()
                self:PhysWake()
            end
        end
    end

    local TValAuto   = (self:GetStability() > 0.3) and 0 or 1
    local TValManual = self.LandingGearUp and 0 or 1
    local TVal       = self.WheelAutoRetract and TValAuto or TValManual
    local Speed      = FrameTime()
    local Speed2     = Speed * math.abs( math.cos( math.rad( self:GetLGear() * 180 ) ) )

    self:SetLGear( self:GetLGear() + math.Clamp(TVal - self:GetLGear(), -Speed, Speed) )
    self:SetRGear( self:GetRGear() + math.Clamp(TVal - self:GetRGear(), -Speed2, Speed2) )

    if IsValid( self.wheel_R ) then
        local p = self.wheel_R:GetPhysicsObject()
        if IsValid(p) then p:SetMass( 1 + (self.WheelMass - 1) * self:GetRGear() ^ 5 ) end
    end
    if IsValid( self.wheel_L ) then
        local p = self.wheel_L:GetPhysicsObject()
        if IsValid(p) then p:SetMass( 1 + (self.WheelMass - 1) * self:GetLGear() ^ 5 ) end
    end
    if IsValid( self.wheel_C ) then
        local p = self.wheel_C:GetPhysicsObject()
        if IsValid(p) then p:SetMass( 1 + (self.WheelMass - 1) * self:GetRGear() ) end
    end
end

function ENT:ToggleLandingGear()
    self.LandingGearUp = not self.LandingGearUp
    self:OnLandingGearToggled( self.LandingGearUp )
end

function ENT:RaiseLandingGear()
    if not self.LandingGearUp then
        self.LandingGearUp = true
        self:OnLandingGearToggled( self.LandingGearUp )
    end
end

function ENT:DeployLandingGear()
    if self.LandingGearUp then
        self.LandingGearUp = false
        self:OnLandingGearToggled( self.LandingGearUp )
    end
end

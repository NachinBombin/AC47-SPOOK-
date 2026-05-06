-- AC-47 Spooky | init.lua  (SERVER)
-- Three fully-independent weapons:
--   1) M134 Minigun  – rapid spray, bone 22/23/24, left-port
--   2) M2HB .50 cal  – burst mode, left-port, slightly forward
--   3) M75 40mm (custom, NOT the AC-130 Bofors) – slow deliberate shells
--
-- Each weapon has its own:
--   * peaceful timer before first and between windows
--   * weapon window duration
--   * burst / spray schedule and per-shot delay
--   * local-space aim vector (port side, perpendicular)

AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )
include( "shared.lua" )

-- ============================================================
-- PER-WEAPON CONFIG
-- All positions in LOCAL entity space.
-- All three guns are on the left (port) side, negative Y = starboard.
-- y=66 means port side in this model's coordinate frame (confirmed from original muzzles).
-- ============================================================

local WPN = {}

-- ----------------------------
-- WEAPON 1 : M134 Minigun
-- Three barrel positions (bones 22/23/24), cycling sequential fire.
-- peaceful: 4-7 s | window: 8 s | spray: 0.033 s/bullet | 60 bullets per burst
-- ----------------------------
WPN.minigun = {
    -- Muzzle positions in local space (same three as original AC-47)
    muzzles = {
        Vector(-170,  66, 101.44),  -- forward gun
        Vector(-208,  66, 95),      -- mid gun
        Vector(-259,  66, 85.6),    -- rear gun
    },
    -- bone indices for barrel spin (client also reads these; matching cl_init)
    barrelBones = { 22, 23, 24 },
    -- Aim angle in LOCAL space: 10 deg down, 90 deg left (port broadside)
    aimAngle   = Angle(10, 90, 0),
    aimSpread  = Vector(0.022, 0.022, 0),
    damage     = 18,         -- per bullet
    force      = 30,
    hullSize   = 6,
    ammoType   = "Pistol",
    -- timing
    peacefulMin  = 4,
    peacefulMax  = 7,
    windowTime   = 8,        -- seconds the window stays open
    shotDelay    = 0.033,    -- 30 rps (~900 rpm)
    bulletsPerBurst = 60,
    pauseBetweenBursts = 0.6,-- pause after burst before re-triggering
    soundLoop   = "TFRE_AC47_M134_LOOP",
    soundStop   = "TFRE_AC47_M134_LASTSHOT",
    tracerName  = "lfs_tracer_red",
    tracerEvery = 1,
}

-- ----------------------------
-- WEAPON 2 : M2HB .50 Browning
-- Single port-side position, 2 bursts of 15 per window.
-- peaceful: 6-10 s | window: 7 s | 2 scheduled bursts
-- ----------------------------
WPN.browning = {
    muzzles = {
        Vector(-190,  70, 98),  -- single mount, port
    },
    barrelBones = {},           -- no spinning barrel on this gun
    aimAngle  = Angle(8, 90, 0),
    aimSpread = Vector(0.015, 0.015, 0),
    damage    = 55,
    force     = 60,
    hullSize  = 8,
    ammoType  = "Pistol",
    peacefulMin   = 6,
    peacefulMax   = 10,
    windowTime    = 7,
    -- 2 scheduled bursts at t=0 and t=3.5 within the window
    burstSchedule = { 0, 3.5 },
    bulletsPerBurst = 15,
    shotDelay       = 0.12,     -- ~8 rps (~480 rpm)
    soundLoop   = "TFRE_AC47_M134_LOOP",  -- reuse existing; swap when dedicated .50 sound added
    soundStop   = "TFRE_AC47_M134_LASTSHOT",
    tracerName  = "lfs_tracer_red",
    tracerEvery = 3,
}

-- ----------------------------
-- WEAPON 3 : M75 40mm Grenade Launcher
-- Slow deliberate shots, heavy damage, 4 shots per window.
-- peaceful: 8-14 s | window: 10 s | shot every GUN40_Delay seconds
-- Fires rpg_missile as fallback (same pattern as AC-130 Bofors fallback).
-- ----------------------------
WPN.grenade40 = {
    muzzles = {
        Vector(-230,  72, 90),  -- port, rear bay
    },
    barrelBones = {},
    aimAngle  = Angle(5, 90, 0),
    aimSpread = Vector(0.008, 0.008, 0),
    damage    = 400,
    force     = 200,
    hullSize  = 0,
    ammoType  = "RPG_Round",
    peacefulMin = 8,
    peacefulMax = 14,
    windowTime  = 10,
    shotDelay   = 2.0,          -- slow deliberate cadence: ~1 shot per 2 s
    maxShots    = 4,            -- window will close or shots will deplete first
    scatter     = 250,          -- world-units radius jitter on target
    shellVelocity = 1800,
    soundShot   = "killstreak_rewards/ac-130_40mm_fire.wav",  -- reuse existing
}

-- ============================================================
-- HELPERS
-- ============================================================

local function GetTargetNear(pos)
    local best, bestD = nil, math.huge
    for _, ply in ipairs( player.GetAll() ) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = ply:GetPos():DistToSqr(pos)
        if d < bestD then bestD = d best = ply end
    end
    return best
end

-- Returns a world-space aim point near the target with per-weapon scatter.
local function GetAimPoint(ent, scatter)
    local target = GetTargetNear( ent:GetPos() )
    local base
    if IsValid(target) then
        base = target:GetPos()
    else
        -- Aim toward ground below entity
        local tr = util.QuickTrace( ent:GetPos(), Vector(0,0,-30000), ent )
        base = tr.HitPos
    end
    if scatter and scatter > 0 then
        base = base + Vector(
            math.Rand(-scatter, scatter),
            math.Rand(-scatter, scatter),
            0
        )
    end
    return base
end

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
-- AI bodygroup (inherited from original)
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
-- ENGINE SOUNDS (delegated to LFS base)
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
-- WEAPON STATE INITIALISATION
-- Called once in Initialize (LFS base calls Initialize -> RunOnSpawn).
-- We hook into Think instead so LFS has already set up the entity fully.
-- ============================================================

function ENT:InitWeaponState()
    if self._wpnStateReady then return end
    self._wpnStateReady = true

    local ct = CurTime()

    -- Each weapon gets its own independent state table.
    -- wpnState[name].phase: "peaceful" | "window"
    -- wpnState[name].nextPhaseTime: when to switch phase
    -- wpnState[name].* : shot counters, timers, etc.

    self.wpnState = {}

    -- Stagger initial peaceful ends so weapons don't all fire at the same moment.
    local staggers = { 0, 2, 5 }
    for i, name in ipairs({ "minigun", "browning", "grenade40" }) do
        local cfg = WPN[name]
        self.wpnState[name] = {
            phase         = "peaceful",
            nextPhaseTime = ct + math.Rand(cfg.peacefulMin, cfg.peacefulMax) + staggers[i],
            shotCount     = 0,
            burstIdx      = 0,
            burstBullets  = 0,
            nextShotTime  = 0,
            burstPauseEnd = 0,
            muzzleIdx     = 1,
            soundActive   = false,
            soundObj      = nil,
        }
    end
end

-- ============================================================
-- WEAPON FIRING : MINIGUN (spray with burst pauses)
-- ============================================================

function ENT:TickMinigun( st, cfg, ct )
    if ct < st.nextShotTime then return end

    -- If inside a pause gap, wait it out
    if st.burstPauseEnd > 0 and ct < st.burstPauseEnd then return end

    -- Check if we just ended a burst
    if st.burstBullets >= cfg.bulletsPerBurst then
        st.burstBullets  = 0
        st.burstPauseEnd = ct + cfg.pauseBetweenBursts
        -- sound stop
        if st.soundActive and IsValid(st.soundObj) then
            st.soundObj:Stop()
            st.soundObj = nil
            st.soundActive = false
            self:EmitSound( cfg.soundStop )
        end
        return
    end

    -- Start sound if not yet active
    if not st.soundActive then
        st.soundObj = CreateSound( self, cfg.soundLoop )
        if st.soundObj then st.soundObj:Play() end
        st.soundActive = true
    end

    -- Cycle muzzle 1 -> 2 -> 3 -> 1
    st.muzzleIdx = ( (st.muzzleIdx - 1 + 1) % #cfg.muzzles ) + 1
    local muzzleLocal = cfg.muzzles[st.muzzleIdx]
    local muzzleWorld = self:LocalToWorld( muzzleLocal )

    -- Aim: fire perpendicular to fuselage out the left (port) side
    local fireDir = self:LocalToWorldAngles( cfg.aimAngle ):Forward()

    local bullet = {}
    bullet.Num        = 1
    bullet.Src        = muzzleWorld
    bullet.Dir        = fireDir
    bullet.Spread     = cfg.aimSpread
    bullet.Tracer     = cfg.tracerEvery
    bullet.TracerName = cfg.tracerName
    bullet.Force      = cfg.force
    bullet.HullSize   = cfg.hullSize
    bullet.Damage     = cfg.damage
    bullet.Attacker   = self:GetDriver()
    bullet.AmmoType   = cfg.ammoType
    bullet.Callback   = function(att, tr, dmginfo)
        dmginfo:SetDamageType(DMG_AIRBOAT)
    end
    self:FireBullets( bullet )

    -- Spin the three barrel bones proportionally
    self:ManipulateBoneAngles(22, Angle(st.muzzleIdx * 35, 0, 0))
    self:ManipulateBoneAngles(23, Angle(st.muzzleIdx * 35, 0, 0))
    self:ManipulateBoneAngles(24, Angle(st.muzzleIdx * 35, 0, 0))

    st.burstBullets = st.burstBullets + 1
    st.nextShotTime = ct + cfg.shotDelay
end

-- ============================================================
-- WEAPON FIRING : M2HB Browning (scheduled burst)
-- ============================================================

function ENT:TickBrowning( st, cfg, ct, windowStart )
    -- Determine which burst we should be in based on elapsed window time
    local elapsed = ct - windowStart
    local targetBurstIdx = 0
    for i, t in ipairs(cfg.burstSchedule) do
        if elapsed >= t then targetBurstIdx = i end
    end

    -- Advance burst index (don't re-fire a finished burst)
    if targetBurstIdx > st.burstIdx then
        st.burstIdx    = targetBurstIdx
        st.burstBullets = 0
        st.nextShotTime = ct
        -- start sound
        if not st.soundActive then
            st.soundObj = CreateSound( self, cfg.soundLoop )
            if st.soundObj then st.soundObj:Play() end
            st.soundActive = true
        end
    end

    if st.burstIdx == 0 then return end                   -- window opened but first burst not yet scheduled
    if st.burstBullets >= cfg.bulletsPerBurst then        -- burst complete; stop sound
        if st.soundActive and IsValid(st.soundObj) then
            st.soundObj:Stop()
            st.soundObj = nil
            st.soundActive = false
            self:EmitSound( cfg.soundStop )
        end
        return
    end
    if ct < st.nextShotTime then return end

    local muzzleWorld = self:LocalToWorld( cfg.muzzles[1] )
    local fireDir     = self:LocalToWorldAngles( cfg.aimAngle ):Forward()

    local bullet = {}
    bullet.Num        = 1
    bullet.Src        = muzzleWorld
    bullet.Dir        = fireDir
    bullet.Spread     = cfg.aimSpread
    bullet.Tracer     = cfg.tracerEvery
    bullet.TracerName = cfg.tracerName
    bullet.Force      = cfg.force
    bullet.HullSize   = cfg.hullSize
    bullet.Damage     = cfg.damage
    bullet.Attacker   = self:GetDriver()
    bullet.AmmoType   = cfg.ammoType
    bullet.Callback   = function(att, tr, dmginfo)
        dmginfo:SetDamageType(DMG_AIRBOAT)
    end
    self:FireBullets( bullet )

    st.burstBullets = st.burstBullets + 1
    st.nextShotTime = ct + cfg.shotDelay
end

-- ============================================================
-- WEAPON FIRING : M75 40mm Grenade (slow deliberate shots)
-- ============================================================

function ENT:TickGrenade40( st, cfg, ct )
    if st.shotCount >= cfg.maxShots then return end    -- exhausted this window
    if ct < st.nextShotTime then return end

    st.nextShotTime = ct + cfg.shotDelay
    st.shotCount    = st.shotCount + 1

    local muzzleWorld = self:LocalToWorld( cfg.muzzles[1] )
    local aimPt = GetAimPoint( self, cfg.scatter )
    local dir   = aimPt - muzzleWorld
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    -- Use rpg_missile as fallback (no gred dependency for portability)
    local m = ents.Create( "rpg_missile" )
    if IsValid(m) then
        m:SetPos( muzzleWorld )
        m:SetAngles( dir:Angle() )
        m:SetOwner( self )
        m:Spawn()
        m:Activate()
        local phys = m:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity( dir * cfg.shellVelocity )
        end
    end

    -- Muzzle flash effect at the 40mm position
    local ed = EffectData()
    ed:SetOrigin( muzzleWorld )
    ed:SetAngles( self:GetAngles() )
    ed:SetScale(2)
    util.Effect( "cball_explode", ed, true, true )

    self:EmitSound( cfg.soundShot )
end

-- ============================================================
-- MAIN PER-WEAPON TICK  (phase machine)
-- ============================================================

function ENT:TickWeapon( name, ct )
    local cfg = WPN[name]
    local st  = self.wpnState[name]
    if not cfg or not st then return end

    if st.phase == "peaceful" then
        if ct >= st.nextPhaseTime then
            -- Transition to window
            st.phase         = "window"
            st.windowStart   = ct
            st.nextPhaseTime = ct + cfg.windowTime
            st.shotCount     = 0
            st.burstIdx      = 0
            st.burstBullets  = 0
            st.nextShotTime  = ct
            st.burstPauseEnd = 0
            st.soundActive   = false
        end
        return
    end

    -- phase == "window"
    if ct >= st.nextPhaseTime then
        -- Window expired; stop sounds and enter peaceful
        if st.soundActive and IsValid(st.soundObj) then
            st.soundObj:Stop()
            st.soundObj    = nil
            st.soundActive = false
            self:EmitSound( cfg.soundStop or "" )
        end
        st.phase         = "peaceful"
        st.nextPhaseTime = ct + math.Rand(cfg.peacefulMin, cfg.peacefulMax)
        return
    end

    -- Fire depending on weapon type
    if name == "minigun" then
        self:TickMinigun( st, cfg, ct )
    elseif name == "browning" then
        self:TickBrowning( st, cfg, ct, st.windowStart )
    elseif name == "grenade40" then
        self:TickGrenade40( st, cfg, ct )
    end
end

-- ============================================================
-- HandleWeapons (called by LFS base every Think)
-- We fully override it; players can still trigger fire1/fire2
-- but the autonomous AI weapon loop runs regardless.
-- ============================================================

function ENT:HandleWeapons( Fire1, Fire2 )
    -- Init state on first call
    self:InitWeaponState()

    local ct = CurTime()
    self:TickWeapon("minigun",   ct)
    self:TickWeapon("browning",  ct)
    self:TickWeapon("grenade40", ct)
end

-- ============================================================
-- LANDING GEAR (full port from original)
-- ============================================================

function ENT:HandleLandingGear()
    local Driver = self:GetDriver()
    if IsValid(Driver) then
        local KeyJump = Driver:KeyDown(IN_JUMP)
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

    if IsValid(self.wheel_R) then
        local p = self.wheel_R:GetPhysicsObject()
        if IsValid(p) then p:SetMass(1 + (self.WheelMass - 1) * self:GetRGear() ^ 5) end
    end
    if IsValid(self.wheel_L) then
        local p = self.wheel_L:GetPhysicsObject()
        if IsValid(p) then p:SetMass(1 + (self.WheelMass - 1) * self:GetLGear() ^ 5) end
    end
    if IsValid(self.wheel_C) then
        local p = self.wheel_C:GetPhysicsObject()
        if IsValid(p) then p:SetMass(1 + (self.WheelMass - 1) * self:GetRGear()) end
    end
end

function ENT:ToggleLandingGear()
    self.LandingGearUp = not self.LandingGearUp
    self:OnLandingGearToggled(self.LandingGearUp)
end

function ENT:RaiseLandingGear()
    if not self.LandingGearUp then
        self.LandingGearUp = true
        self:OnLandingGearToggled(self.LandingGearUp)
    end
end

function ENT:DeployLandingGear()
    if self.LandingGearUp then
        self.LandingGearUp = false
        self:OnLandingGearToggled(self.LandingGearUp)
    end
end

-- AC-47 Spooky | cl_init.lua  (CLIENT)
-- Handles:
--   * Engine sound layers (4 RPM bands + distant)
--   * Prop blur bodygroups (2, 3) — always forced to blur (max RPM by design)
--   * All bone animations: fins, rudder, elevators, ailerons, landing gear,
--     cockpit instruments, minigun barrel spin
--   * Damage smoke FX
--   * Nav light sprites

include( "shared.lua" )

-- ============================================================
-- DAMAGE FX
-- ============================================================

function ENT:DamageFX()
    local HP = self:GetHP()
    if HP == 0 or HP > self:GetMaxHP() * 0.5 then return end

    self.nextDFX = self.nextDFX or 0
    if self.nextDFX >= CurTime() then return end
    self.nextDFX = CurTime() + 0.05

    local ed = EffectData()
    ed:SetOrigin( self:LocalToWorld( Vector(-200, 0, 15) ) )
    util.Effect( "lfs_blacksmoke", ed )
end

-- ============================================================
-- ENGINE SOUNDS
-- ============================================================

function ENT:ExhaustFX()
    -- No exhaust particle (piston engines exhaust is visual-only on this model)
end

function ENT:CalcEngineSound( RPM, Pitch, Doppler )
    local Low  = 500
    local Mid  = 700
    local High = 950

    if self.RPM1 then
        self.RPM1:ChangePitch(  math.Clamp(70  + Pitch * 300 + Doppler, 0, 255) * 0.8 )
        self.RPM1:ChangeVolume( RPM < Low and 1 or 0, 1.5 )
    end
    if self.RPM2 then
        self.RPM2:ChangePitch(  math.Clamp(50  + Pitch * 320 + Doppler, 0, 255) * 0.8 )
        self.RPM2:ChangeVolume( (RPM >= Low  and RPM < Mid)  and 1 or 0, 1.5 )
    end
    if self.RPM3 then
        self.RPM3:ChangePitch(  math.Clamp(75  + Pitch * 110 + Doppler, 0, 255) * 0.8 )
        self.RPM3:ChangeVolume( (RPM >= Mid  and RPM < High) and 1 or 0, 1.5 )
    end
    if self.RPM4 then
        self.RPM4:ChangePitch(  math.Clamp(90  + Pitch * 50  + Doppler, 0, 255) * 0.8 )
        self.RPM4:ChangeVolume( RPM >= High and 1 or 0, 1.5 )
    end
    if self.DIST then
        self.DIST:ChangePitch(  math.Clamp(math.Clamp(50 + Pitch * 60, 50, 255) + Doppler, 0, 255) )
        self.DIST:ChangeVolume( math.Clamp(-1 + Pitch * 6, 0, 1) )
    end
end

function ENT:EngineActiveChanged( bActive )
    if bActive then
        self.RPM1 = CreateSound(self, "TFRE_AC47_ENGINERPM1") self.RPM1:PlayEx(0,0)
        self.RPM2 = CreateSound(self, "TFRE_AC47_ENGINERPM2") self.RPM2:PlayEx(0,0)
        self.RPM3 = CreateSound(self, "TFRE_AC47_ENGINERPM3") self.RPM3:PlayEx(0,0)
        self.RPM4 = CreateSound(self, "TFRE_AC47_ENGINERPM4") self.RPM4:PlayEx(0,0)
        self.DIST = CreateSound(self, "TFRE_AC47_ENGINEDIST")  self.DIST:PlayEx(0,0)
    else
        self:SoundStop()
    end
end

function ENT:OnRemove()
    self:SoundStop()
end

function ENT:SoundStop()
    for _, k in ipairs({ "RPM1", "RPM2", "RPM3", "RPM4", "DIST" }) do
        if self[k] then self[k]:Stop() self[k] = nil end
    end
end

-- ============================================================
-- ROTOR BLUR  –  always max RPM by design
-- Bodygroup 2 = left prop blur disc
-- Bodygroup 3 = right prop blur disc
-- We force both to 1 (blur) as soon as the engine is active.
-- The physical blades (value 0) are shown only when engine is off.
-- ============================================================

function ENT:AnimRotor()
    local RPM = self:GetRPM()
    -- Force blur disc on at any RPM > 0; physical blades only when stopped.
    local showBlur = RPM > 50
    self:SetBodygroup(2, showBlur and 1 or 0)
    self:SetBodygroup(3, showBlur and 1 or 0)

    -- Accumulate rotation angle for the physical blades (shown when RPM <= 50)
    self.RPMAngle = self.RPMAngle and (self.RPMAngle + RPM * FrameTime() * 1.1) or 0
    self:ManipulateBoneAngles(25, Angle(self.RPMAngle, 0, 0))
    self:ManipulateBoneAngles(26, Angle(self.RPMAngle, 0, 0))
end

-- ============================================================
-- MINIGUN BARREL SPIN  (client-side visual only; server drives actual angle via NW or you can mirror locally)
-- We mirror the server logic locally: spin bones 22/23/24 based on
-- a client-side accumulator that ramps up whenever the engine is running.
-- This matches the feel without requiring a networked variable.
-- ============================================================

function ENT:AnimMinigunBarrels()
    if not self:GetEngineActive() then return end
    -- Spin at a constant rate tied to engine RPM (max RPM design = always fast)
    local RPM = self:GetRPM()
    self._barrelAngle = self._barrelAngle and (self._barrelAngle + RPM * FrameTime() * 0.15) or 0
    local a = self._barrelAngle
    self:ManipulateBoneAngles(22, Angle(a, 0, 0))
    self:ManipulateBoneAngles(23, Angle(a, 0, 0))
    self:ManipulateBoneAngles(24, Angle(a, 0, 0))
end

-- ============================================================
-- FLIGHT SURFACE ANIMATIONS (ailerons, elevator, rudder)
-- Bone indices confirmed from original AC-47 cl_init:
--   3  = rudder
--   4,5 = elevators
--   6,7 = ailerons
-- ============================================================

function ENT:AnimFins()
    local FT    = FrameTime() * 10
    local Pitch = self:GetRotPitch()
    local Yaw   = self:GetRotYaw()
    local Roll  = -self:GetRotRoll()

    self.smPitch = self.smPitch and self.smPitch + (Pitch - self.smPitch) * FT or 0
    self.smYaw   = self.smYaw   and self.smYaw   + (Yaw   - self.smYaw  ) * FT or 0
    self.smRoll  = self.smRoll  and self.smRoll  + (Roll  - self.smRoll ) * FT or 0

    self:ManipulateBoneAngles(6, Angle(-self.smRoll, 0, 0))  -- left aileron
    self:ManipulateBoneAngles(7, Angle(-self.smRoll, 0, 0))  -- right aileron
    self:ManipulateBoneAngles(3, Angle( self.smYaw,  0, 0))  -- rudder
    self:ManipulateBoneAngles(4, Angle(0, 0,  self.smPitch)) -- left elevator
    self:ManipulateBoneAngles(5, Angle(0, 0,  self.smPitch)) -- right elevator
end

-- ============================================================
-- COCKPIT INSTRUMENT ANIMATIONS
-- Bones 12-15: artificial horizon (pitch/roll driven)
-- Bones 16-19: RPM gauges
-- ============================================================

function ENT:AnimCabin()
    local FT    = FrameTime() * 10
    local Pitch = self:GetRotPitch()
    local Yaw   = self:GetRotYaw()
    local Roll  = -self:GetRotRoll()
    local RPM   = math.max(0, math.Round(
        ((self:GetRPM() - self:GetIdleRPM()) / (self:GetMaxRPM() - self:GetIdleRPM())) * 8, 0
    ))

    self.smPitch = self.smPitch and self.smPitch + (Pitch - self.smPitch) * FT or 0
    self.smYaw   = self.smYaw   and self.smYaw   + (Yaw   - self.smYaw  ) * FT or 0
    self.smRoll  = self.smRoll  and self.smRoll  + (Roll  - self.smRoll ) * FT or 0
    self.smRPM   = self.smRPM   and self.smRPM   + (RPM   - self.smRPM  ) * FT or 0

    self:ManipulateBoneAngles(16, Angle(0, 0,  self.smRPM * 5))
    self:ManipulateBoneAngles(17, Angle(0, 0,  self.smRPM * 5))
    self:ManipulateBoneAngles(18, Angle(0, 0,  self.smRPM * 5))
    self:ManipulateBoneAngles(19, Angle(0, 0,  self.smRPM * 5))
    self:ManipulateBoneAngles(12, Angle(0, 0, -self.smPitch * 0.1))
    self:ManipulateBoneAngles(13, Angle(-self.smRoll * 2, 0, 0))
    self:ManipulateBoneAngles(14, Angle(0, 0, -self.smPitch * 0.1))
    self:ManipulateBoneAngles(15, Angle(-self.smRoll * 2, 0, 0))
end

-- ============================================================
-- LANDING GEAR ANIMATION
-- Bones 1,2 = main gear strut fold
-- Bones 8-11 = main gear wheel doors
-- ============================================================

function ENT:AnimLandingGear()
    self.SMLG = self.SMLG and self.SMLG + (45 * (1 - self:GetRGear()) - self.SMLG) * FrameTime() * 8 or 0
    self.SMRG = self.SMRG and self.SMRG + (45 * (1 - self:GetLGear()) - self.SMRG) * FrameTime() * 8 or 0

    self:ManipulateBoneAngles(1,  Angle(0, 0, -self.SMLG))
    self:ManipulateBoneAngles(2,  Angle(0, 0, -self.SMRG))
    self:ManipulateBoneAngles(8,  Angle(-45 + self.SMLG, 0, 0))
    self:ManipulateBoneAngles(9,  Angle( 45 - self.SMLG, 0, 0))
    self:ManipulateBoneAngles(10, Angle(-45 + self.SMLG, 0, 0))
    self:ManipulateBoneAngles(11, Angle( 45 - self.SMLG, 0, 0))
end

-- ============================================================
-- NAV LIGHTS + DRAW
-- ============================================================

local mat = Material("tfre/corona_heli")

function ENT:Draw()
    self:DrawModel()
    self:AnimFins()
    self:AnimCabin()
    self:AnimLandingGear()
    self:AnimRotor()
    self:AnimMinigunBarrels()
    self:DamageFX()

    if self:GetEngineActive() then
        local Alpha  = ( -(CurTime() % 2)   + 1 ) * 255
        local Alpha2 = ( -(CurTime() % 0.5) + 1 ) * 150
        render.SetMaterial(mat)
        -- Tail beacon (orange)
        render.DrawSprite(self:LocalToWorld(Vector(-513,      0,      187.5)),  70, 70, Color(255,  93,   0, Alpha))
        -- Starboard nav (green)
        render.DrawSprite(self:LocalToWorld(Vector(-134.67, -569.71, 118.11)), 70, 70, Color(0,   255,   0, Alpha))
        -- Port nav (red)
        render.DrawSprite(self:LocalToWorld(Vector(-134.67,  569.71, 118.11)), 70, 70, Color(255,   0,   0, Alpha))
    end
end

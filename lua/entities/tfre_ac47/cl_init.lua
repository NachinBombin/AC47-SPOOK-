
include("shared.lua")


function ENT:DamageFX()
	local HP = self:GetHP()
	if HP == 0 or HP > self:GetMaxHP() * 0.5 then return end
	
	self.nextDFX = self.nextDFX or 0
	
	if self.nextDFX < CurTime() then
		self.nextDFX = CurTime() + 0.05
		
		local Size = 120

			local Pos = self:LocalToWorld( Vector(-200,0,15) )

			local effectdata = EffectData()
				effectdata:SetOrigin( Pos )
			util.Effect( "lfs_blacksmoke", effectdata )
		end
end


function ENT:ExhaustFX()

end


function ENT:CalcEngineSound( RPM, Pitch, Doppler )
	local Low = 500
	local Mid = 700
	local High = 950
	
	if self.RPM1 then
		self.RPM1:ChangePitch( math.Clamp(70 + Pitch * 300 + Doppler,0,255) * 0.8 )
		self.RPM1:ChangeVolume( RPM < Low and 1 or 0, 1.5 )
	end
	
	if self.RPM2 then
		self.RPM2:ChangePitch(  math.Clamp(50 + Pitch * 320 + Doppler,0,255) * 0.8 )
		self.RPM2:ChangeVolume( (RPM >= Low and RPM < Mid) and 1 or 0, 1.5 )
	end
	
	if self.RPM3 then
		self.RPM3:ChangePitch(  math.Clamp(75 + Pitch * 110 + Doppler,0,255) * 0.8 )
		self.RPM3:ChangeVolume( (RPM >= Mid and RPM < High) and 1 or 0, 1.5 )
	end
	
	if self.RPM4 then
		self.RPM4:ChangePitch(  math.Clamp(90 + Pitch * 50 + Doppler,0,255) * 0.8 )
		self.RPM4:ChangeVolume( RPM >= High and 1 or 0, 1.5 )
	end
	
	if self.DIST then
		self.DIST:ChangePitch(  math.Clamp(math.Clamp( 50 + Pitch * 60, 50,255) + Doppler,0,255) )
		self.DIST:ChangeVolume( math.Clamp( -1 + Pitch * 6, 0,1) )
	end
end

function ENT:EngineActiveChanged( bActive )
	if bActive then
		self.RPM1 = CreateSound( self, "TFRE_AC47_ENGINERPM1" )
		self.RPM1:PlayEx(0,0)
		
		self.RPM2 = CreateSound( self, "TFRE_AC47_ENGINERPM2" )
		self.RPM2:PlayEx(0,0)
		
		self.RPM3 = CreateSound( self, "TFRE_AC47_ENGINERPM3" )
		self.RPM3:PlayEx(0,0)
		
		self.RPM4 = CreateSound( self, "TFRE_AC47_ENGINERPM4" )
		self.RPM4:PlayEx(0,0)
		
		self.DIST = CreateSound( self, "TFRE_AC47_ENGINEDIST" )
		self.DIST:PlayEx(0,0)
	else
		self:SoundStop()
	end
end

function ENT:OnRemove()
	self:SoundStop()
end

function ENT:SoundStop()
	if self.RPM1 then
		self.RPM1:Stop()
	end
	if self.RPM2 then
		self.RPM2:Stop()
	end
	if self.RPM3 then
		self.RPM3:Stop()
	end
	if self.RPM4 then
		self.RPM4:Stop()
	end
	
	if self.DIST then
		self.DIST:Stop()
	end
end

function ENT:AnimFins()
	local FT = FrameTime() * 10
	local Pitch = self:GetRotPitch()
	local Yaw = self:GetRotYaw()
	local Roll = -self:GetRotRoll()
	self.smPitch = self.smPitch and self.smPitch + (Pitch - self.smPitch) * FT or 0
	self.smYaw = self.smYaw and self.smYaw + (Yaw - self.smYaw) * FT or 0
	self.smRoll = self.smRoll and self.smRoll + (Roll - self.smRoll) * FT or 0
	
	self:ManipulateBoneAngles( 6, Angle( -self.smRoll,0,0) )
	self:ManipulateBoneAngles( 7, Angle( -self.smRoll,0,0) )
	
	self:ManipulateBoneAngles( 3, Angle( self.smYaw,0,0) )
	
	self:ManipulateBoneAngles(4, Angle( 0,0,self.smPitch) )
	self:ManipulateBoneAngles(5, Angle( 0,0,self.smPitch) )
end

function ENT:AnimRotor()
	local RPM = self:GetRPM()
	local PhysRot = RPM < 500
	self.RPM = self.RPM and (self.RPM + RPM * FrameTime() * (PhysRot and 4 or 1.1)) or 0
		
	self:SetBodygroup( 2, PhysRot and 0 or 1 )
	self:SetBodygroup( 3, PhysRot and 0 or 1 ) 
		
	self:ManipulateBoneAngles( 25, Angle( self.RPM,0,0) )
	self:ManipulateBoneAngles( 26, Angle( self.RPM,0,0) )

end

local mat = Material( "tfre/corona_heli" )

function ENT:Draw()
	self:DrawModel()
	
	if self:GetEngineActive() then
		local Alpha = ( -( CurTime() % 2 ) + 1) * 255
		local Alpha2 = ( -( CurTime() % 0.5 ) + 1) * 150
		render.SetMaterial( mat )
		render.DrawSprite( self:LocalToWorld( Vector(-513,0,187.5) ), 70, 70, Color( 255, 93, 0, Alpha) )
		render.DrawSprite( self:LocalToWorld( Vector(-134.67,569.71,118.11) ), 70, 70, Color( 255, 0, 0, Alpha) )
		render.DrawSprite( self:LocalToWorld( Vector(-134.67,-569.71,118.11) ), 70, 70, Color( 0, 255, 0, Alpha) )
	end

end

function ENT:AnimCabin()
	local FT = FrameTime() * 10
	local Pitch = self:GetRotPitch()
	local Yaw = self:GetRotYaw()
	local Roll = -self:GetRotRoll()
	local RPM = (math.max( math.Round( ((self:GetRPM() - self:GetIdleRPM()) / (self:GetMaxRPM() - self:GetIdleRPM())) * 8, 0)))
	self.smPitch = self.smPitch and self.smPitch + (Pitch - self.smPitch) * FT or 0
	self.smYaw = self.smYaw and self.smYaw + (Yaw - self.smYaw) * FT or 0
	self.smRoll = self.smRoll and self.smRoll + (Roll - self.smRoll) * FT or 0
	self.smRPM = self.smRPM and self.smRPM + (RPM - self.smRPM) * FT or 0

	self:ManipulateBoneAngles(16,Angle(0,0,self.smRPM*5))
	self:ManipulateBoneAngles(17,Angle(0,0,self.smRPM*5))
	self:ManipulateBoneAngles(18,Angle(0,0,self.smRPM*5))
	self:ManipulateBoneAngles(19,Angle(0,0,self.smRPM*5))
	self:ManipulateBoneAngles(12,Angle(0,0,-self.smPitch*0.1))
	self:ManipulateBoneAngles(13,Angle(-self.smRoll*2,0,0))
	self:ManipulateBoneAngles(14,Angle(0,0,-self.smPitch*0.1))
	self:ManipulateBoneAngles(15,Angle(-self.smRoll*2,0,0))

end

function ENT:AnimLandingGear()
	self.SMLG = self.SMLG and self.SMLG + (45 *  (1 - self:GetRGear()) - self.SMLG) * FrameTime() * 8 or 0
	self.SMRG = self.SMRG and self.SMRG + (45 *  (1 - self:GetLGear()) - self.SMRG) * FrameTime() * 8 or 0

	self:ManipulateBoneAngles( 1, Angle( 0,0,-self.SMLG ) )
	self:ManipulateBoneAngles( 2, Angle( 0,0,-self.SMRG ) )

	self:ManipulateBoneAngles( 8, Angle( -45 + self.SMLG,0,0) )
	self:ManipulateBoneAngles( 9, Angle( 45 - self.SMLG,0,0) )
	self:ManipulateBoneAngles( 10, Angle( -45 + self.SMLG,0,0) )
	self:ManipulateBoneAngles( 11, Angle( 45 - self.SMLG,0,0) )
	
end


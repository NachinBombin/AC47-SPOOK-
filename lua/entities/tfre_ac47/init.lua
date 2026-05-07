--DO NOT EDIT OR REUPLOAD THIS FILE

AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )
include("shared.lua")

function ENT:SpawnFunction( ply, tr, ClassName )
	
	
	if not tr.Hit then return end

	local ent = ents.Create( ClassName )
	ent:SetPos( tr.HitPos + tr.HitNormal * 200 )
	ent:Spawn()
	ent:Activate()

	return ent
	
end

function ENT:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	
	self:SetNextPrimary( 0.01 )
	
	local fP = {
		Vector(-170,66,101.44),
		Vector(-208,66,95),
		Vector(-259,66,85.6),
	}
	
	self.NumPrim = self.NumPrim and self.NumPrim + 1 or 1
	if self.NumPrim > 3 then self.NumPrim = 1 end
	
	local bullet = {}
	bullet.Num 	= 1
	bullet.Src 	= self:LocalToWorld( fP[self.NumPrim] )
	bullet.Dir 	= self:LocalToWorldAngles( Angle(10,(fP[self.NumPrim].y > 0 and 90 or 1),0) ):Forward()
	bullet.Spread 	= Vector( 0.018,  0.018, 0 )
	bullet.Tracer	= 1
	bullet.TracerName	= "lfs_tracer_red"
	bullet.Force	= 50
	bullet.HullSize 	= 10
	bullet.Damage	= 65
	bullet.Attacker 	= self:GetDriver()
	bullet.AmmoType = "Pistol"
	bullet.Callback = function(att, tr, dmginfo)
		dmginfo:SetDamageType(DMG_AIRBOAT)
	end
	self:FireBullets( bullet )
	
	self:TakePrimaryAmmo( 3 )
	
	self:ManipulateBoneAngles(22,Angle(self.NumPrim*35,0,0))
	self:ManipulateBoneAngles(23,Angle(self.NumPrim*35,0,0))
	self:ManipulateBoneAngles(24,Angle(self.NumPrim*35,0,0))
end

function ENT:SecondaryAttack()

end


function ENT:RunOnSpawn()
	
	self:SetGunnerSeat( self:AddPassengerSeat( Vector(127,18,135), Angle(0,-90,11) ) )

	if not self:GetAI() then
	end
end

function ENT:CreateAI()
	
	self:SetBodygroup( 1, 1 )
	
end

function ENT:RemoveAI()

	self:SetBodygroup( 1, 0 )

end

function ENT:HandleWeapons(Fire1, Fire2)
	local Driver = self:GetDriver()
	local Gunner = self:GetGunner()
	local HasGunner = IsValid( Gunner )
	
	if IsValid( Driver ) then
		if self:GetAmmoPrimary() > 0 then
			Fire1 = Driver:KeyDown( IN_ATTACK )
		end
	end
	
	if IsValid( Gunner ) then
		if self:GetAmmoPrimary() > 0 then
			Fire1 = Gunner:KeyDown( IN_ATTACK )
		end
	end
	
	if IsValid( Driver ) then
		if self:GetAmmoSecondary() > 0 then
			Fire2 = Driver:KeyDown( IN_ATTACK2 )
		end
	end
	
	if Fire1 then
		if FireTurret and not HasGunner then
			self:AltPrimaryAttack()
		else
			self:PrimaryAttack()
		end
	end

	if HasGunner then
		if Gunner:KeyDown( IN_ATTACK ) then
			self:PrimaryAttack( Gunner, self:GetGunnerSeat() )
		end
	end
	
	if Fire2 then
		self:SecondaryAttack()
	end

	if self.OldFire ~= Fire1 then
		
		if Fire1 then
			self.wpn1 = CreateSound( self, "TFRE_AC47_M134_LOOP" )
			self.wpn1:Play()
			self:CallOnRemove( "stopmesounds1", function( ent )
				if ent.wpn1 then
					ent.wpn1:Stop()
				end
			end)
		else
			if self.OldFire == true then
				if self.wpn1 then
					self.wpn1:Stop()
				end
				self.wpn1 = nil
					
				self:EmitSound( "TFRE_AC47_M134_LASTSHOT" )
			end
		end
		
		self.OldFire = Fire1
	end
	
end

function ENT:OnEngineStarted()
	self:EmitSound( "TFRE_AC47_ENGINESTART" )
end

function ENT:OnEngineStopped()
	self:EmitSound( "TFRE_AC47_ENGINESTOP" )
end
function ENT:OnLandingGearToggled( bOn )
	self:EmitSound( "lfs/bf109/gear.wav" )
end

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
	
	local TValAuto = (self:GetStability() > 0.3) and 0 or 1
	local TValManual = self.LandingGearUp and 0 or 1
	
	local TVal = self.WheelAutoRetract and TValAuto or TValManual
	local Speed = FrameTime()
	local Speed2 = Speed * math.abs( math.cos( math.rad( self:GetLGear() * 180 ) ) )
	
	self:SetLGear( self:GetLGear() + math.Clamp(TVal - self:GetLGear(),-Speed,Speed) )
	self:SetRGear( self:GetRGear() + math.Clamp(TVal - self:GetRGear(),-Speed2,Speed2) )
	
	if IsValid( self.wheel_R ) then
		local RWpObj = self.wheel_R:GetPhysicsObject()
		if IsValid( RWpObj ) then
			RWpObj:SetMass( 1 + (self.WheelMass - 1) * self:GetRGear() ^ 5 )
		end
	end
	
	if IsValid( self.wheel_L ) then
		local LWpObj = self.wheel_L:GetPhysicsObject()
		if IsValid( LWpObj ) then
			LWpObj:SetMass( 1 + (self.WheelMass - 1) * self:GetLGear() ^ 5 )
		end
	end
	
	if IsValid( self.wheel_C ) then
		local CWpObj = self.wheel_C:GetPhysicsObject()
		if IsValid( CWpObj ) then
			CWpObj:SetMass( 1 + (self.WheelMass - 1) * self:GetRGear() )
		end
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

function ENT:GetMissileOffset()
	return Vector(0,0,-5)
end
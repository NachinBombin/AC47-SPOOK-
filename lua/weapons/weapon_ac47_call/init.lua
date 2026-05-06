AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("ac47_call_plane")

function SWEP:PrimaryAttack()
    if not IsFirstTimePredicted() then return end

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    -- Trace to find the call-in position on the ground
    local tr = util.TraceLine({
        start  = owner:EyePos(),
        endpos = owner:EyePos() + owner:GetAimVector() * 50000,
        filter = owner,
        mask   = MASK_SOLID_BRUSHONLY,
    })

    local hitPos = tr.HitPos
    if not util.IsInWorld(hitPos) then return end

    local callDir = owner:GetAimVector()
    callDir.z = 0
    if callDir:LengthSqr() < 0.01 then callDir = owner:GetForward() callDir.z = 0 end
    callDir:Normalize()

    local plane = ents.Create("ent_ac47_spooky")
    if not IsValid(plane) then
        MsgN("[AC-47 Call] Failed to create ent_ac47_spooky")
        return
    end

    plane:SetVar("CenterPos",    hitPos)
    plane:SetVar("CallDir",      callDir)
    plane:SetVar("Lifetime",     40)
    plane:SetVar("Speed",        280)
    plane:SetVar("OrbitRadius",  2800)
    plane:SetVar("SkyHeightAdd", 5500)
    plane:SetPos(hitPos)
    plane:SetAngles(callDir:Angle())
    plane:Spawn()
    plane:Activate()

    self:SetNextPrimaryFire(CurTime() + 45)
end

function SWEP:SecondaryAttack() end

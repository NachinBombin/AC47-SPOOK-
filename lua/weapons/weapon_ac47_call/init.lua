AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- Net string used by the manual spawn handler in sv_ac47_manualspawn.lua.
-- The SWEP direct-spawns on SERVER only (no net needed here, but we keep
-- the string registered so the tool menu button also works).
util.AddNetworkString("AC47_ManualSpawn")

function SWEP:PrimaryAttack()
    -- Guard: only run on SERVER. PrimaryAttack is predicted and runs on
    -- both realms; spawning entities on CLIENT would cause errors.
    if not SERVER then return end

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

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

    if not scripted_ents.GetStored("ent_ac47_spooky") then
        MsgN("[AC-47 Call] ent_ac47_spooky not registered")
        return
    end

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

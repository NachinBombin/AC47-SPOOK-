AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- NOTE: AC47_ManualSpawn net string is registered in sv_ac47_manualspawn.lua.
-- Do NOT re-declare it here — double AddNetworkString causes console warnings.

function SWEP:PrimaryAttack()
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

    local function gcv(name, default)
        local cv = GetConVar(name)
        return cv and cv:GetFloat() or default
    end

    plane:SetVar("CenterPos",    hitPos)
    plane:SetVar("CallDir",      callDir)
    plane:SetVar("Lifetime",     gcv("npc_ac47_lifetime",  40))
    plane:SetVar("Speed",        gcv("npc_ac47_speed",     280))
    plane:SetVar("OrbitRadius",  gcv("npc_ac47_radius",    2800))
    plane:SetVar("SkyHeightAdd", gcv("npc_ac47_height",    5500))  -- FIX: was "npc_ac47_sky_height"
    plane:SetPos(hitPos)
    plane:SetAngles(callDir:Angle())
    plane:Spawn()
    plane:Activate()

    self:SetNextPrimaryFire(CurTime() + 45)
end

function SWEP:SecondaryAttack() end

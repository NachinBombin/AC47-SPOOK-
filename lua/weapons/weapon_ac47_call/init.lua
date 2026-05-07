-- ============================================================
--  AC-47 Call SWEP — server
--  lua/weapons/weapon_ac47_call/init.lua
-- ============================================================

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ─── helpers ─────────────────────────────────────────────────────────────────
-- sv_ac47_brain.lua registers these as server-side ConVars.
-- DO NOT use GetConVar("npc_ac47_*") — those are CreateClientConVar and
-- are NOT readable on the server. The server brain uses CreateConVar.
local function gcv(name, default)
    local cv = GetConVar(name)
    return cv and cv:GetFloat() or default
end

-- ─── PrimaryAttack ───────────────────────────────────────────────────────────
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
    if not util.IsInWorld(hitPos) then
        owner:PrintMessage(HUD_PRINTCENTER, "[AC-47] Invalid strike position.")
        return
    end

    local callDir = owner:GetAimVector()
    callDir.z = 0
    if callDir:LengthSqr() < 0.01 then
        callDir = owner:GetForward()
        callDir.z = 0
    end
    callDir:Normalize()

    if not scripted_ents.GetStored("ent_ac47_spooky") then
        owner:PrintMessage(HUD_PRINTCENTER, "[AC-47] Entity not registered!")
        MsgN("[AC-47 Call] ent_ac47_spooky not registered")
        return
    end

    local plane = ents.Create("ent_ac47_spooky")
    if not IsValid(plane) then
        owner:PrintMessage(HUD_PRINTCENTER, "[AC-47] Spawn failed!")
        MsgN("[AC-47 Call] Failed to create ent_ac47_spooky")
        return
    end

    -- Read server-side ConVars registered in sv_ac47_brain.lua
    plane:SetVar("CenterPos",    hitPos)
    plane:SetVar("CallDir",      callDir)
    plane:SetVar("Lifetime",     gcv("npc_ac47_lifetime",  40))
    plane:SetVar("Speed",        gcv("npc_ac47_speed",     280))
    plane:SetVar("OrbitRadius",  gcv("npc_ac47_radius",    2800))
    plane:SetVar("SkyHeightAdd", gcv("npc_ac47_height",    5500))
    plane:SetPos(hitPos)
    plane:SetAngles(callDir:Angle())
    plane:Spawn()
    plane:Activate()

    owner:PrintMessage(HUD_PRINTCENTER, "[AC-47 Spooky] Inbound!")
    self:SetNextPrimaryFire(CurTime() + self.CallCooldown)
end

function SWEP:SecondaryAttack() end
function SWEP:Reload() end

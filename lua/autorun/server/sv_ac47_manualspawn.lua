-- ============================================================
--  AC-47 Spooky — Manual Spawn Handler
--  lua/autorun/server/sv_ac47_manualspawn.lua
-- ============================================================

if not SERVER then return end

-- Both net strings declared here — single source of truth.
util.AddNetworkString("AC47_ManualSpawn")
util.AddNetworkString("AC47_GiveSWEP")  -- BUG fix: was used in menu but never registered server-side

-- ─── Manual spawn from control panel button ──────────────────────────────────
net.Receive("AC47_ManualSpawn", function(len, ply)
    if not IsValid(ply) then return end

    local tr = util.TraceLine({
        start  = ply:EyePos(),
        endpos = ply:EyePos() + ply:EyeAngles():Forward() * 3000,
        filter = ply,
    })
    local centerPos = tr.Hit and tr.HitPos or (ply:GetPos() + Vector(0, 0, 100))

    local callDir = ply:EyeAngles():Forward()
    callDir.z = 0
    if callDir:LengthSqr() <= 1 then callDir = Vector(1, 0, 0) end
    callDir:Normalize()

    if not scripted_ents.GetStored("ent_ac47_spooky") then
        ply:PrintMessage(HUD_PRINTCENTER, "[AC-47] Entity not registered!")
        return
    end

    local ent = ents.Create("ent_ac47_spooky")
    if not IsValid(ent) then
        ply:PrintMessage(HUD_PRINTCENTER, "[AC-47] Spawn failed!")
        return
    end

    -- Read from server-side ConVars registered in sv_ac47_brain.lua
    local function gcv(name, default)
        local cv = GetConVar(name)
        return cv and cv:GetFloat() or default
    end

    ent:SetVar("CenterPos",    centerPos)
    ent:SetVar("CallDir",      callDir)
    ent:SetVar("Lifetime",     gcv("npc_ac47_lifetime",  40))
    ent:SetVar("Speed",        gcv("npc_ac47_speed",     280))
    ent:SetVar("OrbitRadius",  gcv("npc_ac47_radius",    2800))
    ent:SetVar("SkyHeightAdd", gcv("npc_ac47_height",    5500))
    ent:SetPos(centerPos)
    ent:SetAngles(callDir:Angle())
    ent:Spawn()
    ent:Activate()

    ply:PrintMessage(HUD_PRINTCENTER, "[AC-47 Spooky] Inbound!")
end)

-- ─── Give SWEP from control panel button ─────────────────────────────────────
-- BUG fix: cl_ac47_menu.lua fires AC47_GiveSWEP but this net string
-- was never registered or handled server-side. Added here.
net.Receive("AC47_GiveSWEP", function(len, ply)
    if not IsValid(ply) then return end
    if not IsValid(ply) or not ply:IsAdmin() then
        ply:PrintMessage(HUD_PRINTCENTER, "[AC-47] Admins only.")
        return
    end
    ply:Give("weapon_ac47_call")
    ply:PrintMessage(HUD_PRINTCENTER, "[AC-47] SWEP given.")
end)

-- ============================================================
--  AC-47 Spooky — Manual Spawn Handler
--  lua/autorun/server/sv_ac47_manualspawn.lua
-- ============================================================

if not SERVER then return end

util.AddNetworkString("AC47_ManualSpawn")

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

    -- Direct field assignment: GetVar/SetVar are LFS-only methods that do not
    -- exist on base_gmodentity. Assigning to the entity table before Spawn() is
    -- the correct pattern; Initialize() reads self.X = self.X or default.
    ent.CenterPos    = centerPos
    ent.CallDir      = callDir
    ent.Lifetime     = GetConVar("npc_ac47_lifetime"):GetFloat()
    ent.Speed        = GetConVar("npc_ac47_speed"):GetFloat()
    ent.OrbitRadius  = GetConVar("npc_ac47_radius"):GetFloat()
    ent.SkyHeightAdd = GetConVar("npc_ac47_height"):GetFloat()
    ent:SetPos(centerPos)
    ent:SetAngles(callDir:Angle())
    ent:Spawn()
    ent:Activate()

    ply:PrintMessage(HUD_PRINTCENTER, "[AC-47 Spooky] Inbound!")
end)

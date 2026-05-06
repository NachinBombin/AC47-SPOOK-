-- AC-47 Spooky | lua/autorun/tfre_ac47_server.lua
-- Registers ConVars, net strings, and the LFS entity SpawnFunction.
-- Mirrors the AC-130 autorun pattern from BombinSupportPlane.

if SERVER then
    AddCSLuaFile( "autorun/client/cl_tfre_ac47_menu.lua" )

    util.AddNetworkString( "TFRE_AC47_ManualSpawn" )

    -- --------------------------------------------------------
    -- ConVars  (FCVAR_ARCHIVE | FCVAR_REPLICATED | FCVAR_NOTIFY)
    -- --------------------------------------------------------
    local SF = bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY )

    CreateConVar( "tfre_ac47_enabled",   "1",    SF, "Enable/disable AC-47 Spooky autonomous flight." )
    CreateConVar( "tfre_ac47_speed",     "350",  SF, "Forward flight speed (HU/s)." )
    CreateConVar( "tfre_ac47_radius",    "3500", SF, "Orbit radius around target (HU)." )
    CreateConVar( "tfre_ac47_height",    "5500", SF, "Preferred height above ground (HU)." )
    CreateConVar( "tfre_ac47_lifetime",  "60",   SF, "Plane lifetime (seconds)." )
    CreateConVar( "tfre_ac47_min_dist",  "400",  SF, "Minimum engagement distance (HU)." )
    CreateConVar( "tfre_ac47_max_dist",  "5000", SF, "Maximum engagement distance (HU)." )
    CreateConVar( "tfre_ac47_announce",  "0",    SF, "Enable debug prints." )

    -- --------------------------------------------------------
    -- Manual spawn via net message (triggered from client menu)
    -- --------------------------------------------------------
    net.Receive( "TFRE_AC47_ManualSpawn", function( len, ply )
        if not IsValid(ply) or not ply:IsAdmin() then return end

        local tr = ply:GetEyeTrace()
        local spawnPos = tr.Hit and (tr.HitPos + tr.HitNormal * 200) or (ply:GetPos() + ply:GetForward() * 400)

        if not scripted_ents.GetStored( "tfre_ac47" ) then
            ply:PrintMessage( HUD_PRINTCENTER, "[AC-47] Entity 'tfre_ac47' is not registered." )
            return
        end

        local ent = ents.Create( "tfre_ac47" )
        if not IsValid(ent) then return end

        ent:SetPos( spawnPos )
        ent:SetAngles( ply:GetAngles() )
        ent:Spawn()
        ent:Activate()

        if GetConVar("tfre_ac47_announce"):GetBool() then
            print( "[AC-47 Spooky] Manually spawned at " .. tostring(spawnPos) )
        end
    end )
end

-- ============================================================
--  AC-47 Spooky — NPC Brain
--  lua/autorun/sv_ac47_brain.lua
--
--  Mirrors the AC-130 brain exactly.
--  Watches for hostile NPCs, picks a center pos, fires a flare,
--  then spawns ent_ac47_spooky after the configured delay.
-- ============================================================

if not SERVER then return end

-- ── ConVars ──────────────────────────────────────────────────
CreateConVar("npc_ac47_enabled",   "1",   FCVAR_ARCHIVE, "Enable automatic AC-47 NPC calls")
CreateConVar("npc_ac47_chance",    "0.15",FCVAR_ARCHIVE, "Probability per check (0–1)")
CreateConVar("npc_ac47_interval",  "5",   FCVAR_ARCHIVE, "Seconds between NPC checks")
CreateConVar("npc_ac47_cooldown",  "60",  FCVAR_ARCHIVE, "Seconds between successful calls")
CreateConVar("npc_ac47_delay",     "4",   FCVAR_ARCHIVE, "Seconds after flare before plane arrives")
CreateConVar("npc_ac47_lifetime",  "40",  FCVAR_ARCHIVE, "AC-47 lifetime in seconds")
CreateConVar("npc_ac47_speed",     "280", FCVAR_ARCHIVE, "AC-47 speed (HU/s)")
CreateConVar("npc_ac47_radius",    "2800",FCVAR_ARCHIVE, "Orbit radius (HU)")
CreateConVar("npc_ac47_height",    "5500",FCVAR_ARCHIVE, "Height above ground (HU)")
CreateConVar("npc_ac47_min_dist",  "0",   FCVAR_ARCHIVE, "Min NPC distance from a player to trigger")
CreateConVar("npc_ac47_max_dist",  "6000",FCVAR_ARCHIVE, "Max NPC distance from a player to trigger")
CreateConVar("npc_ac47_announce",  "0",   FCVAR_ARCHIVE, "Print debug messages")

-- ── State ────────────────────────────────────────────────────
local LastCallTime = -math.huge

-- NPC classes that count as valid callers (combine)
local CALLER_CLASSES = {
    npc_combine_s      = true,
    npc_metropolice    = true,
    npc_combinedropship= true,
    npc_combinegunship = true,
    npc_strider        = true,
    npc_hunter         = true,
}

local function Dbg(msg)
    if GetConVar("npc_ac47_announce"):GetBool() then
        print("[AC-47 Brain] " .. tostring(msg))
    end
end

-- Returns true if there is open sky above pos.
local function HasOpenSky(pos)
    local tr = util.TraceLine({
        start  = pos + Vector(0, 0, 64),
        endpos = pos + Vector(0, 0, 32768),
        mask   = MASK_SOLID_BRUSHONLY,
    })
    return tr.HitSky or not tr.Hit
end

local function SpawnPlane(centerPos, callDir)
    -- guard: entity must be registered
    if not scripted_ents.GetStored("ent_ac47_spooky") then
        Dbg("ent_ac47_spooky not registered")
        return
    end
    local ent = ents.Create("ent_ac47_spooky")
    if not IsValid(ent) then Dbg("ents.Create failed") return end

    ent:SetVar("CenterPos",    centerPos)
    ent:SetVar("CallDir",      callDir)
    ent:SetVar("Lifetime",     GetConVar("npc_ac47_lifetime"):GetFloat())
    ent:SetVar("Speed",        GetConVar("npc_ac47_speed"):GetFloat())
    ent:SetVar("OrbitRadius",  GetConVar("npc_ac47_radius"):GetFloat())
    ent:SetVar("SkyHeightAdd", GetConVar("npc_ac47_height"):GetFloat())
    ent:SetPos(centerPos)
    ent:SetAngles(callDir:Angle())
    ent:Spawn()
    ent:Activate()
    Dbg("Plane spawned at " .. tostring(centerPos))
end

local function FireBombinAC47(centerPos, callDir)
    local delay = GetConVar("npc_ac47_delay"):GetFloat()

    -- Flare (visual cue)
    local flareEnt = ents.Create("env_sprite")
    if IsValid(flareEnt) then
        flareEnt:SetKeyValue("model", "sprites/light_glow02_add.vmt")
        flareEnt:SetKeyValue("scale", "0.5")
        flareEnt:SetPos(centerPos + Vector(0, 0, 64))
        flareEnt:Spawn()
        flareEnt:Activate()
        timer.Simple(delay + 1, function()
            if IsValid(flareEnt) then flareEnt:Remove() end
        end)
    end

    sound.Play("ambient/explosions/explode_3.wav", centerPos, 100, 110, 0.8)
    Dbg("Flare fired, plane in " .. delay .. "s")

    timer.Simple(delay, function()
        SpawnPlane(centerPos, callDir)
    end)
end

-- ── Main timer ───────────────────────────────────────────────
timer.Create("ac47_npc_brain", GetConVar("npc_ac47_interval"):GetFloat(), 0, function()
    if not GetConVar("npc_ac47_enabled"):GetBool() then return end
    local ct = CurTime()
    if ct - LastCallTime < GetConVar("npc_ac47_cooldown"):GetFloat() then return end
    if math.random() > GetConVar("npc_ac47_chance"):GetFloat() then return end

    local minDist = GetConVar("npc_ac47_min_dist"):GetFloat()
    local maxDist = GetConVar("npc_ac47_max_dist"):GetFloat()
    local players = player.GetAll()
    if #players == 0 then return end

    -- Collect valid caller NPCs near a player
    local candidates = {}
    for _, npc in ipairs(ents.GetAll()) do
        if not IsValid(npc) or not npc:IsNPC() then continue end
        if not CALLER_CLASSES[npc:GetClass()] then continue end
        if not npc:Alive() then continue end
        -- must be within range of at least one player
        for _, ply in ipairs(players) do
            if not IsValid(ply) or not ply:Alive() then continue end
            local d = npc:GetPos():Distance(ply:GetPos())
            if d >= minDist and d <= maxDist then
                table.insert(candidates, npc)
                break
            end
        end
    end

    if #candidates == 0 then
        Dbg("No valid callers found")
        return
    end

    local chosen    = candidates[math.random(#candidates)]
    local centerPos = chosen:GetPos()

    if not HasOpenSky(centerPos) then
        Dbg("No open sky at " .. tostring(centerPos))
        return
    end

    -- callDir: from NPC toward nearest player, flattened
    local nearestPly, nearestDist = nil, math.huge
    for _, ply in ipairs(players) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = ply:GetPos():DistToSqr(centerPos)
        if d < nearestDist then nearestDist = d nearestPly = ply end
    end
    local callDir = Vector(1, 0, 0)
    if IsValid(nearestPly) then
        callDir = (nearestPly:GetPos() - centerPos)
        callDir.z = 0
        if callDir:LengthSqr() > 1 then callDir:Normalize()
        else callDir = Vector(1, 0, 0) end
    end

    LastCallTime = ct
    Dbg("Calling AC-47 on " .. chosen:GetClass() .. " at " .. tostring(centerPos))
    FireBombinAC47(centerPos, callDir)
end)

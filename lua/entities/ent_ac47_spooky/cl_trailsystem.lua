-- ============================================================
-- TRAIL SYSTEM  --  ent_ac47_spooky
-- ============================================================

local TRAIL_MATERIAL = Material("trails/smoke")
local SAMPLE_RATE    = 0.025

local TRAIL_POSITIONS = {
    Vector( -200, 15, -4 ),   -- left wingtip
    Vector(  200, 15, -4 ),   -- right wingtip
}

local TIER_CONFIG = {
    [0] = { r = 255, g = 255, b = 255, a = 108, startSize = 18, endSize =  3, lifetime = 4 },
    [1] = { r = 160, g = 160, b = 160, a = 148, startSize = 28, endSize =  6, lifetime = 5 },
    [2] = { r =  50, g =  50, b =  50, a = 192, startSize = 44, endSize = 10, lifetime = 6 },
    [3] = { r =  10, g =  10, b =  10, a = 222, startSize = 60, endSize = 18, lifetime = 8 },
}

local AC47Trails = {}

local function EnsureRegistered(entIndex)
    if AC47Trails[entIndex] then return end
    local trails = {}
    for i = 1, #TRAIL_POSITIONS do
        trails[i] = { positions = {} }
    end
    AC47Trails[entIndex] = {
        tier       = 0,
        nextSample = 0,
        trails     = trails,
    }
end

-- FIX BUG 2: EnsureRegistered is called BEFORE the nil-check so that a
-- damage-tier net message arriving in the same frame the entity is first
-- seen will correctly record the tier rather than silently dropping it.
function AC47TrailSystem_SetTier(entIndex, tier)
    EnsureRegistered(entIndex)   -- was missing; tier was lost if state didn't exist yet
    local state = AC47Trails[entIndex]
    if not state then return end
    state.tier = tier
end

local function DrawBeam(positions, cfg)
    local n = #positions
    if n < 2 then return end
    local Time = CurTime()
    local lt   = cfg.lifetime
    for i = n, 1, -1 do
        if Time - positions[i].time > lt then
            table.remove(positions, i)
        end
    end
    n = #positions
    if n < 2 then return end
    render.SetMaterial(TRAIL_MATERIAL)
    render.StartBeam(n)
    for _, pd in ipairs(positions) do
        local Scale = math.Clamp((pd.time + lt - Time) / lt, 0, 1)
        local size  = cfg.startSize * Scale + cfg.endSize * (1 - Scale)
        render.AddBeam(pd.pos, size, pd.time * 50,
            Color(cfg.r, cfg.g, cfg.b, cfg.a * Scale * Scale))
    end
    render.EndBeam()
end

hook.Add("Think", "ac47_trails_update", function()
    local Time = CurTime()
    for _, ent in ipairs(ents.FindByClass("ent_ac47_spooky")) do
        EnsureRegistered(ent:EntIndex())
    end
    for entIndex, state in pairs(AC47Trails) do
        local ent = Entity(entIndex)
        if not IsValid(ent) then
            AC47Trails[entIndex] = nil
            continue
        end
        if Time < state.nextSample then continue end
        state.nextSample = Time + SAMPLE_RATE
        local pos = ent:GetPos()
        local ang = ent:GetAngles()
        for i, trail in ipairs(state.trails) do
            local wpos = LocalToWorld(TRAIL_POSITIONS[i], Angle(0,0,0), pos, ang)
            table.insert(trail.positions, { time = Time, pos = wpos })
            table.sort(trail.positions, function(a, b) return a.time > b.time end)
        end
    end
end)

hook.Add("PostDrawTranslucentRenderables", "ac47_trails_draw", function(bDepth, bSkybox)
    if bSkybox then return end
    for _, state in pairs(AC47Trails) do
        local cfg = TIER_CONFIG[state.tier] or TIER_CONFIG[0]
        for _, trail in ipairs(state.trails) do
            DrawBeam(trail.positions, cfg)
        end
    end
end)

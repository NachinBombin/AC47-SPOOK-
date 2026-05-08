if not CLIENT then return end

-- ============================================================
-- MATERIALS
-- effects/muzzleflash1  = round additive bloom (main flash)
-- effects/muzzleflash4  = elongated cone additive (flame tongue)
-- particle/particle_smokegrenade = soft dark smoke quad
-- ============================================================

local mat_flash  = Material("effects/muzzleflash1")
local mat_flame  = Material("effects/muzzleflash4")
local mat_smoke  = Material("particle/particle_smokegrenade")

-- ============================================================
-- TABLES
-- muzzle_flashes  : { pos, expire }            -- round bloom + flame cone
-- smoke_particles : { pos, vel, alpha, expire } -- trailing smoke quads
-- ============================================================

local muzzle_flashes  = {}
local smoke_particles = {}

-- ============================================================
-- NET RECEIVE
-- On every muzzle flash message:
--   1. Register flash + flame entry (drawn in render hook)
--   2. Spawn spark util.Effect immediately
--   3. Seed several smoke quads into the smoke table
-- ============================================================

net.Receive("ac47_muzzle_flash", function()
    local pos = net.ReadVector()
    local now = UnPredictedCurTime()

    -- 1. Flash + flame (rendered in hook)
    muzzle_flashes[#muzzle_flashes + 1] = {
        pos    = pos,
        expire = now + 0.06,
        fexpire = now + 0.035,   -- flame cone is shorter than bloom
    }

    -- 2. Sparks -- ManhackSparks is vanilla HL2, bright white/yellow streaks
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetNormal(Vector(0, 0, -1))  -- sparks fall downward from muzzle
    ed:SetScale(1.8)
    ed:SetMagnitude(2)
    ed:SetRadius(12)
    util.Effect("ManhackSparks", ed)

    -- 3. Smoke quads -- 5 puffs per flash, staggered velocity
    for i = 1, 5 do
        smoke_particles[#smoke_particles + 1] = {
            pos    = pos + Vector(
                        math.Rand(-6, 6),
                        math.Rand(-6, 6),
                        math.Rand(0, 8)
                     ),
            -- each puff drifts upward and slightly sideways
            vel    = Vector(
                        math.Rand(-8, 8),
                        math.Rand(-8, 8),
                        math.Rand(18, 40)
                     ),
            -- stagger birth so puffs don't all pop at once
            born   = now + (i - 1) * 0.04,
            expire = now + (i - 1) * 0.04 + 0.8,
            -- random start size; grows as it rises
            size   = math.Rand(14, 28),
        }
    end
end)

-- ============================================================
-- RENDER HOOK
-- Draws all three layers in one pass:
--   A. Smoke quads       (dark grey, soft, fade in/out)
--   B. Round bloom flash (effects/muzzleflash1, large)
--   C. Cone flame tongue (effects/muzzleflash4, short-lived)
-- ============================================================

hook.Add("PostDrawTranslucentRenderables", "ac47_muzzle_fx_draw", function(depth, skybox)
    if depth or skybox then return end

    local ct   = UnPredictedCurTime()
    local eye  = EyePos()

    -- ── A. SMOKE ───────────────────────────────────────────────
    if #smoke_particles > 0 then
        render.SetMaterial(mat_smoke)
        local keep_smoke = {}
        for _, s in ipairs(smoke_particles) do
            if ct < s.born then
                keep_smoke[#keep_smoke + 1] = s
                continue
            end
            if ct > s.expire then continue end

            local life     = (ct - s.born)
            local duration = s.expire - s.born
            local frac     = life / duration           -- 0 → 1 over lifetime

            -- Fade: quick fade-in (0→0.2), hold, fade-out (0.7→1)
            local alpha
            if frac < 0.15 then
                alpha = frac / 0.15
            elseif frac < 0.70 then
                alpha = 1
            else
                alpha = 1 - (frac - 0.70) / 0.30
            end
            alpha = alpha * 140   -- max alpha 140/255 -- smoke is semi-transparent

            -- Grow as it rises
            local sz = s.size * (1 + frac * 2.5)

            -- Drift position
            local drawPos = s.pos + s.vel * life

            -- Dark grey, slightly warm (gun smoke has brown tint)
            render.DrawSprite(drawPos, sz, sz, Color(55, 50, 48, alpha))

            keep_smoke[#keep_smoke + 1] = s
        end
        smoke_particles = keep_smoke
    end

    -- ── B + C. FLASH + FLAME ───────────────────────────────────
    if #muzzle_flashes == 0 then return end
    local keep_flash = {}

    -- Round bloom
    render.SetMaterial(mat_flash)
    for _, f in ipairs(muzzle_flashes) do
        if ct > f.expire then continue end
        local sz = math.Clamp(120 + eye:Distance(f.pos) * 0.028, 120, 400)
        render.DrawSprite(f.pos, sz, sz, Color(255, 220, 100, 255))
        keep_flash[#keep_flash + 1] = f
    end

    -- Cone flame (elongated, shorter lifetime, points away from fuselage)
    -- We draw it as a wider-X narrower-Y sprite to fake the cone shape.
    render.SetMaterial(mat_flame)
    for _, f in ipairs(muzzle_flashes) do
        if ct > f.fexpire then continue end
        -- Flame is 1.6x wide, 0.7x tall relative to bloom size
        local base = math.Clamp(100 + eye:Distance(f.pos) * 0.022, 100, 320)
        local w    = base * 1.6
        local h    = base * 0.7
        -- Bright white-orange core
        render.DrawSprite(f.pos, w, h, Color(255, 200, 80, 230))
        -- Tight hot white center
        render.DrawSprite(f.pos, w * 0.35, h * 0.35, Color(255, 255, 220, 255))
    end

    muzzle_flashes = keep_flash
end)

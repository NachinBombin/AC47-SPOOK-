if not CLIENT then return end

-- ============================================================
-- MUZZLE FLASH
-- effects/muzzleflash1 is a confirmed $additive VMT in hl2_misc.vpk.
-- render.DrawSprite on a non-additive material = black square.
-- ============================================================

local mat_flash = Material("effects/muzzleflash1")
local muzzle_flashes = {}

net.Receive("ac47_muzzle_flash", function()
    muzzle_flashes[#muzzle_flashes + 1] = {
        pos    = net.ReadVector(),
        expire = UnPredictedCurTime() + 0.06,
    }
end)

hook.Add("PostDrawTranslucentRenderables", "ac47_muzzle_flash_draw", function(depth, skybox)
    if depth or skybox then return end
    if #muzzle_flashes == 0 then return end

    local ct   = UnPredictedCurTime()
    local eye  = EyePos()
    local keep = {}

    render.SetMaterial(mat_flash)
    for _, f in ipairs(muzzle_flashes) do
        if ct > f.expire then continue end
        local sz = math.Clamp(30 + eye:Distance(f.pos) * 0.007, 30, 100)
        render.DrawSprite(f.pos, sz, sz, Color(255, 220, 100, 255))
        keep[#keep + 1] = f
    end
    muzzle_flashes = keep
end)

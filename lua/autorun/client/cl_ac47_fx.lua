if not CLIENT then return end

-- ============================================================
-- MUZZLE FLASH
-- effects/muzzleflash1 is a real $additive VMT in hl2_misc.vpk.
-- render.DrawSprite with a non-additive material = black square.
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
        local dist = eye:Distance(f.pos)
        local sz   = math.Clamp(30 + dist * 0.007, 30, 100)
        render.DrawSprite(f.pos, sz, sz, Color(255, 220, 100, 255))
        keep[#keep + 1] = f
    end

    muzzle_flashes = keep
end)

-- ============================================================
-- GUN FIRE SOUNDS — 3 stacking channels via distinct CHAN_*
--
-- CreateSound deduplicates per (entity, path) — unusable for
-- stacking multiple sounds on the same entity.
--
-- Entity:EmitSound(path, level, pitch, vol, channel) with an
-- explicit channel constant bypasses deduplication entirely.
-- Each gun gets its own channel so they never stomp:
--   Gun 1 -> CHAN_WEAPON (0)
--   Gun 2 -> CHAN_VOICE  (2)
--   Gun 3 -> CHAN_ITEM1  (5)
--
-- Stop: EmitSound("common/null.wav", ..., ch) cuts the channel
-- immediately. StopSound targets by path, not channel — wrong tool.
-- ============================================================

local GUN_WAV  = "lfs/tfre_ac47/m134_shoot.wav"
local NULL_WAV = "common/null.wav"

local GUN_CHANNELS = { CHAN_WEAPON, CHAN_VOICE, CHAN_ITEM1 }

net.Receive("ac47_gun_sound", function()
    local entIndex = net.ReadUInt(16)
    local gunIdx   = net.ReadUInt(8)
    local isStart  = net.ReadBool()
    local ent      = Entity(entIndex)
    if not IsValid(ent) then return end

    local ch = GUN_CHANNELS[gunIdx] or CHAN_WEAPON

    if isStart then
        ent:EmitSound(GUN_WAV, 150, 100, 1.0, ch)
    else
        ent:EmitSound(NULL_WAV, 150, 100, 1.0, ch)
    end
end)

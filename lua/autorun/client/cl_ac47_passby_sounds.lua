-- AC-47 Spooky — M134 .30 cal passby sound registration
-- Mirrors the GAU passby system exactly, prefixed ac47_ to avoid collisions.
-- Uses the same RBO library the GAU uses (closest acoustic match for 7.62 M134).

-- ─── Spatial emit helper ─────────────────────────────────────────────────────
-- Plays at a point 32 units toward the bullet, from the listener's eye.
-- Keeps the sound audible at range while still feeling directional.
function AC47EmitSound(name, pos, level, pitch, volume)
    local view = GetViewEntity()
    if not IsValid(view) then return end
    local eye = view:EyePos()
    local dir = pos - eye
    dir:Normalize()
    sound.Play(
        name,
        eye + dir * 32,
        level  or 80,
        pitch  or 100,
        volume or 1
    )
end

-- ─── sound.Add alias helper ──────────────────────────────────────────────────
local function FastList(name, ext, num)
    local list = {}
    for i = 1, num do
        list[i] = name .. (i < 10 and "0" .. i or i) .. "." .. ext
    end
    return list
end

-- Close crack (sub-256 units)
sound.Add({
    name    = "ac47_passby_close",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 110,  -- slightly higher pitch than GAU (smaller caliber)
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_close_", "ogg", 12)
})

-- Medium crack (256–768 units)
sound.Add({
    name    = "ac47_passby_medium",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 108,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_mid_", "ogg", 12)
})

sound.Add({
    name    = "ac47_passby_medium_2",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 108,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_mid_new_", "ogg", 17)
})

-- Far hiss (768–2500 units)
sound.Add({
    name    = "ac47_passby_hiss_far",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 105,
    sound   = FastList("rbo/passbys/squad/hiss/passby_crack_hiss_far_", "ogg", 29)
})

-- Very far (2500+ units)
sound.Add({
    name    = "ac47_passby_far",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 105,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_far_new_", "ogg", 19)
})

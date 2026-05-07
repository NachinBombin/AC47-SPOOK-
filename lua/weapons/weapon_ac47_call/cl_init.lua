-- ============================================================
--  AC-47 Call SWEP — client
--  lua/weapons/weapon_ac47_call/cl_init.lua
-- ============================================================

include("shared.lua")

function SWEP:DrawHUD()
    local owner = self:GetOwner()
    if not IsValid(owner) or owner ~= LocalPlayer() then return end

    local nextFire = self:GetNextPrimaryFire()
    local ct       = CurTime()
    local cooldown = self.CallCooldown or 45
    local ready    = ct >= nextFire

    local sw, sh = ScrW(), ScrH()
    local x, y   = sw * 0.5, sh * 0.88

    local label, col
    if ready then
        label = "AC-47 READY — Click to call strike"
        col   = Color(80, 220, 80, 220)
    else
        local remaining = math.ceil(nextFire - ct)
        label = "AC-47 COOLDOWN — " .. remaining .. "s"
        col   = Color(220, 100, 50, 200)
    end

    draw.SimpleText(label, "DermaDefault", x, y,
        col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function SWEP:DrawWeaponSelection(x, y, wide, tall, alpha)
    self:DrawWeaponSelectionBase(x, y, wide, tall, alpha)
end

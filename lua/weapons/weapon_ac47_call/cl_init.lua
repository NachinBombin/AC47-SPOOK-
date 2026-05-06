include("shared.lua")

function SWEP:Initialize()
    self:SetHoldType("rpg")
end

function SWEP:DrawHUD()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end

    local ct        = CurTime()
    local cooldown  = self:GetNextPrimaryFire() - ct
    local sw, sh    = ScrW(), ScrH()

    draw.SimpleText(
        cooldown > 0
            and string.format("AC-47 Spooky — Ready in %.0fs", cooldown)
            or  "AC-47 Spooky — READY",
        "DermaDefaultBold",
        sw * 0.5,
        sh - 80,
        cooldown > 0 and Color(255, 120, 20, 220) or Color(20, 255, 80, 220),
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER
    )
end

function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end

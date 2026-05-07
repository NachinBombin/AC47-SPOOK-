-- ============================================================
--  AC-47 Call SWEP — shared definitions
--  lua/weapons/weapon_ac47_call/shared.lua
-- ============================================================

SWEP.Base         = "weapon_base"
SWEP.PrintName    = "AC-47 Spooky Strike"
SWEP.Author       = "Bombin"
SWEP.Instructions = "LEFT CLICK: Call AC-47 Spooky strike at aimed location."
SWEP.Category     = "Bombin Support"

SWEP.Spawnable        = false
SWEP.AdminSpawnable   = true

SWEP.HoldType         = "pistol"
SWEP.ViewModelFOV     = 54
SWEP.ViewModelFlip    = false
SWEP.UseHands         = true

SWEP.Primary.ClipSize       = -1
SWEP.Primary.DefaultClip    = -1
SWEP.Primary.Automatic      = false
SWEP.Primary.Ammo           = "none"

SWEP.Secondary.ClipSize     = -1
SWEP.Secondary.DefaultClip  = -1
SWEP.Secondary.Automatic    = false
SWEP.Secondary.Ammo         = "none"

SWEP.Weight           = 5
SWEP.AutoSwitchTo     = false
SWEP.AutoSwitchFrom   = false

-- Cooldown in seconds between calls
SWEP.CallCooldown = 45

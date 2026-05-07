-- BUG 8 FIX: was base_anim — bullet has no animations, base_anim
-- calls SetupBones every tick for nothing. base_entity is correct.
ENT.Type      = "anim"
ENT.Base      = "base_entity"
ENT.PrintName = "AC-47 M134 Bullet"
ENT.Spawnable = false

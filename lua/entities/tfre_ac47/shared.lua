--DO NOT EDIT OR REUPLOAD THIS FILE

ENT.Type            = "anim"
DEFINE_BASECLASS( "lunasflightschool_basescript" )

ENT.PrintName = "Douglas AC-47 Spooky"
ENT.Author = "Ceiling Spiders"
ENT.Information = "Please bring me head of the guy who did June 4, 2020."
ENT.Category = "[LFS] TF:RE"

ENT.Spawnable		= true
ENT.AdminSpawnable		= false

ENT.MDL = "models/tfre/vehicles/ac47_spooky/ac47_spooky.mdl"

ENT.AITEAM = 2

ENT.Mass = 2200
ENT.Inertia = Vector(220000,220000,220000)
ENT.Drag = 2

ENT.WheelMass = 300
ENT.WheelRadius = 23
ENT.WheelPos_L = Vector(1,-109.29,23.278)
ENT.WheelPos_R = Vector(1,109.29,23.278)
ENT.WheelPos_C = Vector(-458.44,0,20)

ENT.HideDriver = false
ENT.SeatPos = Vector(127,-18,135)
ENT.SeatAng = Angle(0,-90,11)

ENT.IdleRPM = 200
ENT.MaxRPM = 2900
ENT.LimitRPM = 4100

ENT.RotorPos = Vector(0,0,200)
ENT.WingPos = Vector(65,0,60)
ENT.ElevatorPos = Vector(-527.67,0,50)
ENT.RudderPos = Vector(-524.5,0,115)

 
ENT.MaxVelocity = 2800

ENT.MaxThrust = 1600

ENT.MaxStability = 0.8

ENT.MaxTurnPitch = 150
ENT.MaxTurnYaw = 270
ENT.MaxTurnRoll = 100

ENT.MaxPerfVelocity = 1600

ENT.MaxHealth = 2000

ENT.MaxPrimaryAmmo = 4500
ENT.MaxSecondaryAmmo = 0


sound.Add( {
	name = "TFRE_AC47_ENGINERPM1",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 125,
	sound = "lfs/tfre_ac47/skytrain_engine_1rpm.wav"
} )

sound.Add( {
	name = "TFRE_AC47_ENGINERPM2",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 125,
	sound = "lfs/tfre_ac47/skytrain_engine_2rpm.wav"
} )

sound.Add( {
	name = "TFRE_AC47_ENGINERPM3",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 125,
	sound = "lfs/tfre_ac47/skytrain_engine_3rpm.wav"
} )

sound.Add( {
	name = "TFRE_AC47_ENGINERPM4",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 125,
	sound = "lfs/tfre_ac47/skytrain_engine_4rpm.wav"
} )

sound.Add( {
	name = "TFRE_AC47_ENGINEDIST",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 125,
	sound = "lfs/tfre_ac47/skytrain_engine_far.wav"
} )

sound.Add( {
	name = "TFRE_AC47_ENGINESTART",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 125,
	sound = "lfs/tfre_ac47/skytrain_engine_start.wav"
} )

sound.Add( {
	name = "TFRE_AC47_ENGINESTOP",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 125,
	sound = "lfs/tfre_ac47/skytrain_engine_stop.wav"
} )

sound.Add( {
	name = "TFRE_AC47_M134_LOOP",
	channel = CHAN_WEAPON,
	volume = 1.0,
	level = 90,
	sound = "lfs/tfre_ac47/m134_shoot.wav"
} )

sound.Add( {
	name = "TFRE_AC47_M134_LASTSHOT",
	channel = CHAN_WEAPON,
	volume = 1.0,
	level = 90,
	sound = "lfs/tfre_ac47/m134_stop.wav"
} )



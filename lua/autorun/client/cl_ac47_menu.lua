-- ============================================================
--  AC-47 Spooky Control Panel
--  lua/autorun/client/cl_ac47_menu.lua
-- ============================================================

if not CLIENT then return end

-- NOTE: ConVars are declared SERVER-side with FCVAR_REPLICATED.
-- No CreateClientConVar duplicates needed — they would shadow the
-- server values and break multiplayer slider reads.

local col_bg_panel      = Color(0,   0,   0,   255)
local col_section_title = Color(210, 210, 210, 255)
local col_accent        = Color(180, 100, 0,   255)

local SECTION_COLORS = {
    ["NPC Call Settings"]    = Color(60,  120, 200, 120),
    ["Probability & Timing"] = Color(80,  160, 100, 120),
    ["Flight Behaviour"]     = Color(80,  180, 120, 120),
    ["Engagement Range"]     = Color(200, 140, 40,  120),
    ["Debug"]                = Color(100, 100, 110, 120),
    ["Manual Spawn"]         = Color(140, 80,  200, 120),
}

local function AddColoredCategory(panel, text)
    local bgColor = SECTION_COLORS[text]
    if not bgColor then panel:Help(text) return end
    local cat = vgui.Create("DPanel", panel)
    cat:SetTall(24)
    cat:Dock(TOP)
    cat:DockMargin(0, 8, 0, 4)
    cat.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, bgColor)
        surface.SetDrawColor(0, 0, 0, 35)
        surface.DrawOutlinedRect(0, 0, w, h)
        local textColor = (bgColor.r + bgColor.g + bgColor.b < 200)
            and Color(255, 255, 255, 255)
            or  Color(0,   0,   0,   255)
        draw.SimpleText(text, "DermaDefaultBold", 8, h / 2,
            textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    panel:AddItem(cat)
end

local function BuildAC47Panel(panel)
    panel:ClearControls()

    local header = vgui.Create("DPanel", panel)
    header:SetTall(32)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 8)
    header.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, col_bg_panel)
        surface.SetDrawColor(col_accent)
        surface.DrawRect(0, h - 2, w, 2)
        draw.SimpleText("AC-47 Spooky Controller", "DermaLarge",
            8, h / 2, col_section_title, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    panel:AddItem(header)

    AddColoredCategory(panel, "NPC Call Settings")
    panel:CheckBox("Enable AC-47 calls", "npc_ac47_enabled")

    AddColoredCategory(panel, "Probability & Timing")
    panel:NumSlider("Call chance (per check)",  "npc_ac47_chance",    0,   1,   2)
    panel:NumSlider("Check interval (seconds)", "npc_ac47_interval",  1,   60,  0)
    panel:NumSlider("Call cooldown (seconds)",  "npc_ac47_cooldown",  10,  180, 0)
    panel:NumSlider("Delay after flare (s)",    "npc_ac47_delay",     1,   15,  0)
    panel:NumSlider("AC-47 lifetime (seconds)", "npc_ac47_lifetime",  5,   120, 0)

    AddColoredCategory(panel, "Flight Behaviour")
    panel:NumSlider("AC-47 speed (HU/s)",                 "npc_ac47_speed",  100, 800,  0)
    panel:NumSlider("Orbit radius (HU)",                  "npc_ac47_radius", 500, 8000, 0)
    panel:NumSlider("Preferred height above ground (HU)", "npc_ac47_height", 500, 8000, 0)

    AddColoredCategory(panel, "Engagement Range")
    panel:NumSlider("Min distance (HU)", "npc_ac47_min_dist", 0,   1000, 0)
    panel:NumSlider("Max distance (HU)", "npc_ac47_max_dist", 500, 8000, 0)

    AddColoredCategory(panel, "Debug")
    panel:CheckBox("Enable debug prints", "npc_ac47_announce")

    AddColoredCategory(panel, "Manual Spawn")
    panel:Button("Spawn AC-47 Spooky now", "ac47_spawnplane")
end

-- Console command: manual test spawn
concommand.Add("ac47_spawnplane", function()
    if not IsValid(LocalPlayer()) then return end
    net.Start("AC47_ManualSpawn")
    net.SendToServer()
end)

local function RegisterTab()
    spawnmenu.AddToolTab("Bombin Support", "Bombin Support", "icon16/bomb.png")
    spawnmenu.AddToolCategory("Bombin Support", "AC-47 Spooky", "AC-47 Spooky")
end

hook.Add("AddToolMenuTabs",       "AC47_AddTab",      RegisterTab)
hook.Add("AddToolMenuCategories", "AC47_AddCategory", RegisterTab)

hook.Add("PopulateToolMenu", "AC47_ToolMenu", function()
    spawnmenu.AddToolMenuOption(
        "Bombin Support",
        "AC-47 Spooky",
        "npc_ac47_settings",
        "AC-47 Spooky Settings",
        "", "",
        BuildAC47Panel
    )
end)

local tabInjected = false
hook.Add("SpawnMenuOpen", "AC47_LateInject", function()
    if tabInjected then return end
    tabInjected = true
    RegisterTab()
    hook.Run("PopulateToolMenu")
end)

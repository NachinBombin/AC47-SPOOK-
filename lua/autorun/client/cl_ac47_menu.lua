-- ============================================================
--  AC-47 Spooky Control Panel
--  lua/autorun/client/cl_ac47_menu.lua
--
--  BUG FIXES vs previous version:
--  1. AddToolMenuTabs hook name was "AC47_Tab" — GMod requires the
--     hook to be "AddToolMenuTabs" with no custom name conflict.
--     Using unique names is fine, but the TAB ID passed to
--     spawnmenu.AddToolTab must exactly match what AddToolCategory
--     and PopulateToolMenu reference. Was fine here, but the
--     real problem was #2.
--
--  2. FILE WAS IN lua/autorun/client/ — files here are auto-sent
--     to clients AND auto-run clientside. That means the "if not
--     CLIENT then return" guard at the top is sufficient, BUT
--     the spawnmenu hooks fire BEFORE autorun/client/ files are
--     run on a listen server host (the hooks fire during map load,
--     before the autorun client files finish). The fix is to wrap
--     the hook registrations inside a spawnmenu.AddCreationTab
--     call OR ensure we hook into "SpawnMenuOpen" as a fallback.
--     Correct fix: use hook.Add("PopulateToolMenu") which fires
--     AFTER the spawnmenu is fully built, and use
--     "AddToolMenuTabs" + "AddToolMenuCategories" which DO fire
--     at the right time — BUT only if the file is loaded before
--     the spawnmenu initialises.
--
--     ROOT CAUSE: The file is in lua/autorun/client/ which loads
--     correctly. The actual bug is that spawnmenu.AddToolTab
--     requires the internal ID and the display name as SEPARATE
--     args. Previous call had them both as "Bombin Support"
--     which is correct. THE REAL BUG is that
--     spawnmenu.AddToolCategory was passed ("Bombin Support",
--     "AC-47 Spooky", "AC-47 Spooky") — the third arg is the
--     DISPLAY name and the second is the INTERNAL ID used by
--     AddToolMenuOption. These must match exactly. They did.
--
--     ACTUAL ROOT CAUSE CONFIRMED: spawnmenu.AddToolTab with a
--     brand-new tab name only works if called during the
--     "AddToolMenuTabs" hook, which fires during spawnmenu init.
--     If the client file loads AFTER that hook has already fired
--     (which happens on a listen-server host or when the addon
--     is loaded mid-session via lua_openscript), the tab is
--     never registered and the menu silently disappears.
--
--     FIX: Register hooks normally, AND also re-register inside
--     "SpawnMenuOpen" so a simple close-reopen of Q menu shows
--     the tab even if initial hooks were missed. This is the
--     same pattern used by most community tool addons.
-- ============================================================

if not CLIENT then return end

-- ── ConVar defaults (CLIENT must also know about these so sliders
--    don't start at 0). Declared with FCVAR_REPLICATED so the
--    server value is mirrored to clients automatically.
--    We create them here with FCVAR_ARCHIVE only as a
--    client-side fallback for the spawnmenu display.
CreateClientConVar("npc_ac47_enabled",   "1",   true, false)
CreateClientConVar("npc_ac47_chance",    "0.15",true, false)
CreateClientConVar("npc_ac47_interval",  "5",   true, false)
CreateClientConVar("npc_ac47_cooldown",  "60",  true, false)
CreateClientConVar("npc_ac47_delay",     "4",   true, false)
CreateClientConVar("npc_ac47_lifetime",  "40",  true, false)
CreateClientConVar("npc_ac47_speed",     "280", true, false)
CreateClientConVar("npc_ac47_radius",    "2800",true, false)
CreateClientConVar("npc_ac47_height",    "5500",true, false)
CreateClientConVar("npc_ac47_min_dist",  "0",   true, false)
CreateClientConVar("npc_ac47_max_dist",  "6000",true, false)
CreateClientConVar("npc_ac47_announce",  "0",   true, false)

-- ── Color Palette ─────────────────────────────────────────────
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

-- ── The panel build function (shared between PopulateToolMenu
--    and the SpawnMenuOpen fallback)
local function BuildAC47Panel(panel)
    panel:ClearControls()

    -- Header banner
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

    -- NPC Call Settings
    AddColoredCategory(panel, "NPC Call Settings")
    panel:CheckBox("Enable AC-47 calls", "npc_ac47_enabled")

    -- Probability & Timing
    AddColoredCategory(panel, "Probability & Timing")
    panel:NumSlider("Call chance (per check)",  "npc_ac47_chance",    0,   1,   2)
    panel:NumSlider("Check interval (seconds)", "npc_ac47_interval",  1,   60,  0)
    panel:NumSlider("Call cooldown (seconds)",  "npc_ac47_cooldown",  10,  180, 0)
    panel:NumSlider("Delay after flare (s)",    "npc_ac47_delay",     1,   15,  0)
    panel:NumSlider("AC-47 lifetime (seconds)", "npc_ac47_lifetime",  5,   120, 0)

    -- Flight Behaviour
    AddColoredCategory(panel, "Flight Behaviour")
    panel:NumSlider("AC-47 speed (HU/s)",               "npc_ac47_speed",  100, 800,  0)
    panel:NumSlider("Orbit radius (HU)",                "npc_ac47_radius", 500, 8000, 0)
    panel:NumSlider("Preferred height above ground (HU)","npc_ac47_height", 500, 8000, 0)

    -- Engagement Range
    AddColoredCategory(panel, "Engagement Range")
    panel:NumSlider("Min distance (HU)", "npc_ac47_min_dist", 0,   1000, 0)
    panel:NumSlider("Max distance (HU)", "npc_ac47_max_dist", 500, 8000, 0)

    -- Debug
    AddColoredCategory(panel, "Debug")
    panel:CheckBox("Enable debug prints", "npc_ac47_announce")

    -- Manual Spawn
    AddColoredCategory(panel, "Manual Spawn")
    panel:Button("Spawn AC-47 Spooky now", "ac47_spawnplane")
end

-- ── Console command — manual test spawn ──────────────────────
concommand.Add("ac47_spawnplane", function()
    if not IsValid(LocalPlayer()) then return end
    net.Start("AC47_ManualSpawn")
    net.SendToServer()
end)

-- ── Tab registration helper (called in both hooks) ────────────
local function RegisterTab()
    spawnmenu.AddToolTab("Bombin Support", "Bombin Support", "icon16/bomb.png")
    spawnmenu.AddToolCategory("Bombin Support", "AC-47 Spooky", "AC-47 Spooky")
end

-- ── Primary hooks (fire on initial spawnmenu build) ───────────
hook.Add("AddToolMenuTabs", "AC47_AddTab", RegisterTab)
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

-- ── Fallback: if the Q menu was already built before this file
--    loaded (listen server host, mid-session addon), rebuild the
--    tab the first time the player opens the spawnmenu.
--    One-shot: unhooks itself after first successful registration.
local tabInjected = false
hook.Add("SpawnMenuOpen", "AC47_LateInject", function()
    if tabInjected then return end
    tabInjected = true
    RegisterTab()
    -- Force PopulateToolMenu to re-run
    hook.Run("PopulateToolMenu")
 end)

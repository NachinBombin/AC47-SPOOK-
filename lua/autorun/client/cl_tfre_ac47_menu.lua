-- AC-47 Spooky | lua/autorun/client/cl_tfre_ac47_menu.lua
-- Spawnmenu tab, category, and settings panel.
-- Mirrors the AC-130 BombinSupportPlane menu pattern exactly.

if not CLIENT then return end

-- ============================================================
-- Palette
-- ============================================================
local COL_BG      = Color(  0,   0,   0, 255)
local COL_TEXT    = Color(210, 210, 210, 255)
local COL_ACCENT  = Color( 60, 160, 255, 255)  -- steel blue to match gunship feel

local SECTION_COLORS = {
    ["Flight Behaviour"]   = Color( 60, 100, 180, 120),
    ["Engagement Range"]   = Color(200, 130,  30, 120),
    ["Lifetime"]           = Color( 80, 160, 100, 120),
    ["Debug"]              = Color(100, 100, 110, 120),
    ["Manual Spawn"]       = Color(140,  60, 200, 120),
}

local function AddSection( panel, text )
    local bg = SECTION_COLORS[text]
    if not bg then panel:Help(text) return end

    local cat = vgui.Create( "DPanel", panel )
    cat:SetTall( 24 )
    cat:Dock( TOP )
    cat:DockMargin( 0, 8, 0, 4 )
    cat.Paint = function( self, w, h )
        draw.RoundedBox( 4, 0, 0, w, h, bg )
        surface.SetDrawColor( 0, 0, 0, 35 )
        surface.DrawOutlinedRect( 0, 0, w, h )
        local tc = (bg.r + bg.g + bg.b < 200) and Color(255,255,255) or Color(0,0,0)
        draw.SimpleText( text, "DermaDefaultBold", 8, h/2, tc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
    end
    panel:AddItem( cat )
end

-- ============================================================
-- ConCommand – triggers net message to server
-- ============================================================
concommand.Add( "tfre_ac47_spawn", function()
    if not IsValid( LocalPlayer() ) then return end
    net.Start( "TFRE_AC47_ManualSpawn" )
    net.SendToServer()
end )

-- ============================================================
-- Tool Tab
-- ============================================================
hook.Add( "AddToolMenuTabs", "TFRE_AC47_Tab", function()
    spawnmenu.AddToolTab( "Bombin Support", "Bombin Support", "icon16/bomb.png" )
end )

-- ============================================================
-- Tool Category
-- ============================================================
hook.Add( "AddToolMenuCategories", "TFRE_AC47_Category", function()
    spawnmenu.AddToolCategory( "Bombin Support", "AC-47 Spooky", "AC-47 Spooky" )
end )

-- ============================================================
-- Tool Menu Panel
-- ============================================================
hook.Add( "PopulateToolMenu", "TFRE_AC47_ToolMenu", function()
    spawnmenu.AddToolMenuOption(
        "Bombin Support",
        "AC-47 Spooky",
        "tfre_ac47_settings",
        "AC-47 Spooky Settings",
        "", "",
        function( panel )
            panel:ClearControls()

            -- Header banner
            local header = vgui.Create( "DPanel", panel )
            header:SetTall( 32 )
            header:Dock( TOP )
            header:DockMargin( 0, 0, 0, 8 )
            header.Paint = function( self, w, h )
                draw.RoundedBox( 4, 0, 0, w, h, COL_BG )
                surface.SetDrawColor( COL_ACCENT )
                surface.DrawRect( 0, h - 2, w, 2 )
                draw.SimpleText(
                    "AC-47 Spooky",
                    "DermaLarge",
                    8, h / 2,
                    COL_TEXT,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER
                )
            end
            panel:AddItem( header )

            -- ── Flight Behaviour ────────────────────────────────────
            AddSection( panel, "Flight Behaviour" )
            panel:NumSlider( "Speed (HU/s)",          "tfre_ac47_speed",   100, 1200, 0 )
            panel:NumSlider( "Orbit radius (HU)",      "tfre_ac47_radius",  500, 8000, 0 )
            panel:NumSlider( "Height above ground (HU)","tfre_ac47_height", 500, 8000, 0 )

            -- ── Engagement Range ────────────────────────────────────
            AddSection( panel, "Engagement Range" )
            panel:NumSlider( "Min distance (HU)", "tfre_ac47_min_dist",  0,    1000, 0 )
            panel:NumSlider( "Max distance (HU)", "tfre_ac47_max_dist",  500,  8000, 0 )

            -- ── Lifetime ────────────────────────────────────────────
            AddSection( panel, "Lifetime" )
            panel:NumSlider( "Plane lifetime (s)", "tfre_ac47_lifetime", 10, 300, 0 )

            -- ── Debug ───────────────────────────────────────────────
            AddSection( panel, "Debug" )
            panel:CheckBox( "Enable debug prints", "tfre_ac47_announce" )

            -- ── Manual Spawn ────────────────────────────────────────
            AddSection( panel, "Manual Spawn" )
            panel:Button( "Spawn AC-47 Spooky now", "tfre_ac47_spawn" )
        end
    )
end )

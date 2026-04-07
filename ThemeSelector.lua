RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

if m.ThemeSelector then return end

local M = {}

---@type ScrollDropdown
local scroll_drop = LibStub:GetLibrary( "LibScrollDrop-1.3" )

--- Injecte un dropdown "UI Theme" dans un frame de settings existant
--- La selection du theme reste en attente jusqu'au clic sur Save.
--- @param settings Frame  le frame settings du CalendarPopup courant
--- @param anchor_below Frame  l'element sous lequel le dropdown se positionne
function M.inject( settings, anchor_below )
    if not settings or not scroll_drop then return end

    local dd_theme = scroll_drop:New( settings, {
        default_text = m.db.user_settings.ui_theme or "Blizzard",
        dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
        search = false,
        width = 110
    } )

    -- Positionner dd_theme exactement en dessous de anchor_below,
    -- aligne sur son bord gauche (meme x que dd_locale/dd_timeformat)
    dd_theme:SetPoint( "TopLeft", anchor_below, "BottomLeft", 0, -8 )
    dd_theme:SetItems( {
        { value = "Original", text = "Original" },
        { value = "Pfui",     text = "pfUI"      },
        { value = "Blizzard", text = "Blizzard"  },
    } )
    dd_theme:SetSelected( m.db.user_settings.ui_theme or "Blizzard" )

    dd_theme.on_select = function( sel )
        if not sel then
            return
        end

        settings.pending_ui_theme = sel
        if settings.on_pending_ui_theme_changed then
            settings.on_pending_ui_theme_changed( sel )
        end
    end

    local lbl = settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
    lbl:SetPoint( "Right", dd_theme, "Left", -8, 0 )
    lbl:SetText( m.L( "ui.ui_theme" ) )
    settings.lbl_theme = lbl

    settings.dd_theme = dd_theme

    -- Appliquer le skin pfUI si disponible
    if m.pfui_skin_enabled and m.api and m.api.pfUI and m.api.pfUI.api then
        local pfui = m.api.pfUI.api
        if pfui.StripTextures then pfui.StripTextures( dd_theme ) end
        if pfui.CreateBackdrop then pfui.CreateBackdrop( dd_theme, nil, true ) end
        if dd_theme.dropdown_button then
            if pfui.SkinArrowButton then pfui.SkinArrowButton( dd_theme.dropdown_button, "down", 16 ) end
            dd_theme.dropdown_button:SetPoint( "Right", dd_theme, "Right", -4, 0 )
        end
    end

    -- Agrandir le frame settings pour loger la ligne
    local h = settings:GetHeight() or 100
    settings:SetHeight( h + 38 )
end

m.ThemeSelector = M
return M

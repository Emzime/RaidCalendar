-- LocalEventManager.lua
-- Gestion des événements "in-game" — source de vérité côté bot (raidcalbot.json)
-- Le SavedVariables sert uniquement de cache local pour l'affichage.
-- Toutes les mutations (create/edit/delete) transitent par le bot via AceComm.
-- La liste complète est rechargée via LOCAL_EVENT_LIST à chaque login.

RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

if m.LocalEventManager then return end

local M = {}

-- ============================================================
--  CONSTANTES
-- ============================================================

local ID_PREFIX = "LOCAL_"   -- Préfixe des IDs locaux

-- ============================================================
--  HELPERS PRIVÉS
-- ============================================================

--- Retourne true si le joueur courant peut modifier l'évènement
-- (créateur OU rôle manager vérifié par le bot)
local function can_edit_local( event )
    if not event then return false end
    if event.creator == m.player then return true end
    if m.db and m.db.user_settings and m.db.user_settings.has_manager_role then return true end
    return false
end

local function ensure_db()
    m.db = m.db or {}
    m.db.local_events = m.db.local_events or {}
end

local function normalize_event_id( event_id )
    if event_id == nil then
        return nil
    end

    if type( event_id ) == "string" then
        if event_id == "" then
            return nil
        end
        return event_id
    end

    if type( event_id ) == "number" then
        return tostring( event_id )
    end

    return nil
end

local function normalize_event( ev )
    local normalized
    local i
    local signups

    if type( ev ) ~= "table" then
        return nil
    end

    local event_id = normalize_event_id( ev.id )
    if not event_id then
        return nil
    end

    normalized = {
        id              = event_id,
        title           = ev.title or "",
        startTime       = tonumber( ev.startTime ) or 0,
        description     = ev.description or "",
        location        = ev.location or "",
        creator         = ev.creator or ev.leaderName or "",
        createdAt       = tonumber( ev.createdAt ) or 0,
        discordThreadId = ev.discordThreadId or nil,
        source          = "local",
        signups         = {},
    }

    signups = ev.signups or ev.signUps or ev.signUpList
    if type( signups ) == "table" then
        for i = 1, getn( signups ) do
            local su = signups[ i ]
            if type( su ) == "table" then
                table.insert( normalized.signups, {
                    player    = su.player or su.name or su.character or su.characterName or "",
                    className = su.className or su.class or "",
                    specName  = su.specName or su.spec or su.specialization or "",
                    status    = su.status or "Signup",
                    signedAt  = tonumber( su.signedAt or su.entryTime ) or 0,
                    userId    = su.userId or su.userid or nil,
                } )
            end
        end
    end

    return normalized
end

-- ============================================================
--  INITIALISATION
-- ============================================================

--- Appelé dans ADDON_LOADED — initialise le cache local et demande la liste au bot
function M.init()
    ensure_db()

    -- Requête au bot pour récupérer la liste à jour
    if m.msg and m.msg.request_local_events then
        m.msg.request_local_events()
    end
end

-- ============================================================
--  CACHE LOCAL (mis à jour par la réponse LOCAL_EVENTS_LIST)
-- ============================================================

--- Remplace le cache local avec la liste reçue du bot
function M.load_from_bot( events_list )
    local loaded_count = 0
    local event_data
    local _, ev

    ensure_db()
    m.db.local_events = {}

    if type( events_list ) ~= "table" then
        if m.debug then
            m.debug( "LocalEventManager: invalid local event list received from bot." )
        end
        return
    end

    for _, ev in ipairs( events_list ) do
        event_data = normalize_event( ev )
        if event_data then
            m.db.local_events[ event_data.id ] = event_data
            loaded_count = loaded_count + 1
        else
            if m.debug then
                m.debug( "LocalEventManager: local event ignored (invalid or missing id)." )
            end
        end
    end

    if m.debug then
        m.debug( "LocalEventManager: cache updated (" .. loaded_count .. " events)" )
    end
end

--- Met à jour ou insère un événement dans le cache local (callback create/edit)
function M.cache_upsert( ev )
    local event_data = normalize_event( ev )
    if not event_data then
        if m.debug then
            m.debug( "LocalEventManager: cache_upsert ignored (invalid or missing id)." )
        end
        return
    end

    ensure_db()
    m.db.local_events[ event_data.id ] = event_data
end

--- Retire un événement du cache local (callback delete)
function M.cache_remove( event_id )
    local event_key = normalize_event_id( event_id )
    ensure_db()

    if event_key then
        m.db.local_events[ event_key ] = nil
    end
end

-- ============================================================
--  MUTATIONS (envoyées au bot, pas en local directement)
-- ============================================================

--- Crée un évènement — envoie LOCAL_EVENT_CREATE au bot
-- @param data table  { title, startTime, description?, location? }
-- @return nil (résultat asynchrone via LOCAL_EVENT_RESULT)
function M.create( data )
    if not data or not data.title or data.title == "" then
        m.error( m.L( "local_event.error_no_title" ) or "Title is required." )
        return nil
    end
    if not data.startTime or data.startTime <= 0 then
        m.error( m.L( "local_event.error_invalid_date" ) or "Invalid date/time." )
        return nil
    end

    m.msg.local_event_create({
        title       = data.title,
        startTime   = data.startTime,
        description = data.description or "",
        location    = data.location or "",
        limit       = data.limit or 0,
    })

    -- Retourne un ID temporaire non-nil pour signaler que la requête a bien été envoyée
    -- L'ID réel sera fourni dans le callback on_result
    return "pending"
end

--- Modifie un évènement — envoie LOCAL_EVENT_EDIT au bot
-- @return nil (résultat asynchrone via LOCAL_EVENT_RESULT)
function M.edit( event_id, data )
    local event_key = normalize_event_id( event_id )
    local ev

    ensure_db()
    ev = event_key and m.db.local_events[ event_key ] or nil

    if not ev then
        m.error( m.L( "local_event.not_found" ) or "Event not found." )
        return false
    end
    if not can_edit_local( ev ) then
        m.error( m.L( "event_manage.no_edit_permission" ) or "You do not have permission to edit this event." )
        return false
    end

    m.msg.local_event_edit({
        id          = event_key,
        title       = data.title,
        startTime   = data.startTime,
        description = data.description,
        location    = data.location,
    })
    return true
end

--- Supprime un évènement — envoie LOCAL_EVENT_DELETE au bot
-- @return nil (résultat asynchrone via LOCAL_EVENT_RESULT)
function M.delete( event_id )
    local event_key = normalize_event_id( event_id )
    local ev

    ensure_db()
    ev = event_key and m.db.local_events[ event_key ] or nil

    if not ev then
        m.error( m.L( "local_event.not_found" ) or "Event not found." )
        return false
    end
    if not can_edit_local( ev ) then
        m.error( m.L and m.L( "local_event.error_not_creator" ) or "You cannot delete an event you did not create." )
        return false
    end

    m.msg.local_event_delete({ id = event_key })
    return true
end

-- ============================================================
--  LECTURE (depuis le cache local)
-- ============================================================

function M.get( event_id )
    local event_key = normalize_event_id( event_id )
    ensure_db()

    if not event_key then
        return nil
    end

    return m.db.local_events[ event_key ]
end

function M.is_local( event_id )
    return event_id and string.sub( tostring( event_id ), 1, string.len( ID_PREFIX ) ) == ID_PREFIX
end

function M.can_edit( event_id )
    return can_edit_local( M.get( event_id ) )
end

--- Nettoyage local des entrées périmées (> 30 jours) dans le cache
-- Le bot effectue ce nettoyage de son côté de façon autonome.
function M.cleanup_old()
    local now
    local removed
    local id, ev

    ensure_db()

    now = time()
    removed = 0

    for id, ev in pairs( m.db.local_events ) do
        if ev.startTime and now - ev.startTime > 86400 * 30 then
            m.db.local_events[ id ] = nil
            removed = removed + 1
        end
    end

    if removed > 0 and m.debug then
        m.debug( "LocalEventManager: " .. removed .. " expired entry/entries removed from cache." )
    end
end

m.LocalEventManager = M
return M

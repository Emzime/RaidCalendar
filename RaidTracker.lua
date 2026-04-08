-- RaidTracker.lua
-- Module de suivi de raid pour RaidCalendar
-- Gestion des kills, wipes, pauses, loots et rsum fin de raid
-- Envoi vers Discord via RaidCalendarBot

RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

if m.RaidTracker then return end

local M = {}

-- ============================================================
--  CONSTANTES
-- ============================================================

-- Couleurs WoW par classe (format AARRGGBB pour l'affichage in-game)
local CLASS_COLORS = {
    ["WARRIOR"]  = "FFC79C6E",
    ["PALADIN"]  = "FFF58CBA",
    ["HUNTER"]   = "FFABD473",
    ["ROGUE"]    = "FFFFF569",
    ["PRIEST"]   = "FFFFFFFF",
    ["SHAMAN"]   = "FF0070DE",
    ["MAGE"]     = "FF40C7EB",
    ["WARLOCK"]  = "FF8787ED",
    ["DRUID"]    = "FFFF7D0A",
}

-- Commandes protocole (doivent tre synchronises avec BotCommandHandler.scala)
local CMD = {
    RAID_EVENT      = "RAID_EVENT",
    LOOT_ASSIGN     = "LOOT_ASSIGN",
    RAID_SUMMARY    = "RAID_SUMMARY",
    RAID_ROLE_CHECK = "RAID_ROLE_CHECK",
    RAID_ROLE_RESULT = "RAID_ROLE_RESULT",
}

-- ============================================================
--  TAT INTERNE
-- ============================================================

local state = {
    active         = false,
    raidName       = "",
    raidSession    = "",   -- identifiant unique de session (nom_timestamp), transmis au bot pour les threads Discord
    startTime      = nil,   -- timestamp Unix
    currentBoss    = "",
    pullTime       = nil,   -- timestamp du dernier pull
    attempts       = {},    -- [bossName] = nombre de tentatives
    kills          = {},    -- [{name, duration, attempt, killTime}]
    wipes          = 0,
    loots          = {},    -- [{itemId, itemName, itemLink, recipient, recipientClass, t}]
    paused         = false,
    has_permission = false, -- vérifié via Discord role
}

-- ============================================================
--  HELPERS PRIVS
-- ============================================================

-- Formate une dure en secondes -> "m:ss"
local function fmt_duration(secs)
    secs = secs or 0
    return string.format("%d:%02d", math.floor(secs / 60), math.mod(secs, 60))
end

-- Rcupre la classe d'un joueur dans le raid
local function get_class_in_raid(name)
    if not name then return nil end
    local lower = string.lower(name)
    if string.lower(m.player) == lower then
        return m.player_class
    end
    for i = 1, GetNumRaidMembers() do
        local n, _, _, _, _, class = GetRaidRosterInfo(i)
        if n and string.lower(n) == lower then
            return class
        end
    end
    return nil
end

-- Colore un nom de joueur selon sa classe
local function color_player(name, class_name)
    local color = CLASS_COLORS[string.upper(class_name or "")] or "FFFFFFFF"
    return string.format("|c%s%s|r", color, name)
end

-- Extraction item depuis un item-link vanilla
-- Format: |cffa335ee|Hitem:18646:0:0:0:0:0:0:0|h[Onslaught Girdle]|h|r
local function parse_item_link(link)
    if not link then return nil, nil end
    local item_id = tonumber(string.match(link, "|Hitem:(%d+)"))
    local item_name = string.match(link, "%[(.-)%]")
    return item_id, item_name
end

-- Vrifie que le channel est configur et que l'utilisateur est authentifi
local function check_ready()
    if not m.db.user_settings.discord_id then
        m.error(m.L( "raidtracker.discord_not_auth" ) or "Discord not configured.")
        return false
    end
    local ch = m.db.user_settings.raid_log_channel_id
    if not ch or ch == "" then
        m.error(m.L( "raidtracker.no_channel" ) or "No Discord channel configured.")
        return false
    end
    return true
end

-- ============================================================
--  ENVOI DES MESSAGES AU BOT
-- ============================================================

-- Broadcast un événement raid vers Discord
local function broadcast_raid_event(event_type, boss_name, duration, attempt)
    m.msg.raid_event(
        event_type,
        boss_name,
        duration or 0,
        attempt or 0,
        m.db.user_settings.raid_log_channel_id,
        state.raidSession
    )
end

-- Broadcast une attribution de loot
local function broadcast_loot(item_id, item_name, item_link, recipient, recipient_class)
    m.msg.loot_assign(
        item_id,
        item_name,
        item_link,
        recipient,
        recipient_class,
        m.db.user_settings.raid_log_channel_id,
        state.raidSession
    )
end

-- ============================================================
--  GESTION DES LOOTS
-- ============================================================

-- Patterns de dtection de loot (vanilla WoW 1.12)
local LOOT_PATTERNS = {
    { pattern = "^(.+) reoit du butin : (.+)%.$", self = false },   -- frFR
    { pattern = "^(.+) receives? loot: (.+)%.$",   self = false },   -- enUS (autres)
    { pattern = "^Vous recevez du butin : (.+)%.$", self = true  },  -- frFR (soi)
    { pattern = "^You receive loot: (.+)%.$",       self = true  },  -- enUS (soi)
}

local function process_loot_message(msg)
    if not state.active then return end

    for _, entry in ipairs(LOOT_PATTERNS) do
        local recipient, item_link

        if entry.self then
            item_link = string.match(msg, entry.pattern)
            if item_link then recipient = m.player end
        else
            recipient, item_link = string.match(msg, entry.pattern)
        end

        if recipient and item_link then
            local item_id, item_name = parse_item_link(item_link)
            if not item_id then
                -- Pas un vrai item link, tenter extraction simple
                item_name = string.match(item_link, "%[(.-)%]") or item_link
            end
            if item_name then
                local recipient_class = get_class_in_raid(recipient) or "Unknown"

                -- Stocker
                table.insert(state.loots, {
                    itemId        = item_id,
                    itemName      = item_name,
                    itemLink      = item_link,
                    recipient     = recipient,
                    recipientClass = recipient_class,
                    t             = time(),
                })

                -- Annonce guilde avec couleurs WoW
                local colored_player = color_player(recipient, recipient_class)
                local guild_msg = string.format("%s %s", item_link or ("[" .. item_name .. "]"), colored_player)
                SendChatMessage(guild_msg, "GUILD")

                -- Envoyer  Discord
                broadcast_loot(item_id, item_name, item_link, recipient, recipient_class)
            end
            return
        end
    end
end

-- ============================================================
--  API PUBLIQUE
-- ============================================================

--- Dmarre une session de raid
--- @param raid_name string   Nom du raid (ex: "Molten Core")
--- @param channel_id string  ID du salon Discord de log
function M.start_raid(raid_name, channel_id)
    if state.active then
        m.error(m.L( "raidtracker.session_already_active" ) or "Session already active.")
        return false
    end

    state.active      = true
    state.raidName    = raid_name or "Raid"
    -- raidSession = "NomRaid_timestamp_Leader" — identifiant unique transmis au bot
    -- Le nom du joueur garantit l'unicité même si deux équipes démarrent le même raid
    -- à la même seconde. Le thread Discord sera nommé d'après cette clé.
    local safe_name    = string.gsub(state.raidName, "[^%w%-]", "_")
    local safe_player  = string.gsub(m.player or "unknown", "[^%w]", "")
    state.raidSession  = safe_name .. "_" .. tostring(time()) .. "_" .. safe_player
    state.startTime    = time()
    state.currentBoss = ""
    state.pullTime    = nil
    state.attempts    = {}
    state.kills       = {}
    state.wipes       = 0
    state.loots       = {}
    state.paused      = false

    if channel_id and channel_id ~= "" then
        m.db.user_settings.raid_log_channel_id = channel_id
    end
    m.db.user_settings.last_raid_name = state.raidName

    m.info(string.format("|cff00FF00Session dmarre :|r |cffFFD700%s|r", state.raidName))
    return true
end

--- Termine la session de raid (sans envoyer le résumé)
function M.end_raid()
    if not state.active then return end
    state.active      = false
    state.raidSession = ""
    m.info("|cffFF4444" .. ( m.L and m.L( "ui.raid_session_ended" ) or "Raid session ended." ) .. "|r")
end

--- Enregistre un KILL boss
--- @param boss_name string  Nom du boss
function M.register_kill(boss_name)
    boss_name = boss_name or state.currentBoss
    if not boss_name or boss_name == "" then
        m.error(m.L( "raidtracker.missing_boss" ) or "Boss name missing.")
        return false
    end
    if not check_ready() then return false end

    local attempt  = (state.attempts[boss_name] or 0) + 1
    local duration = state.pullTime and (time() - state.pullTime) or 0

    state.attempts[boss_name] = attempt
    state.pullTime = nil

    table.insert(state.kills, {
        name      = boss_name,
        duration  = duration,
        attempt   = attempt,
        killTime  = time(),
    })

    m.info(string.format(
        "|cffFFD700[KILL]|r %s - Tentative #%d - %s",
        boss_name, attempt, fmt_duration(duration)
    ))

    broadcast_raid_event("kill", boss_name, duration, attempt)
    state.currentBoss = ""
    return true
end

--- Enregistre un WIPE
--- @param boss_name string  Nom du boss
function M.register_wipe(boss_name)
    boss_name = boss_name or state.currentBoss
    if not boss_name or boss_name == "" then
        m.error(m.L( "raidtracker.missing_boss" ) or "Boss name missing.")
        return false
    end
    if not check_ready() then return false end

    local attempt  = (state.attempts[boss_name] or 0) + 1
    local duration = state.pullTime and (time() - state.pullTime) or 0

    state.attempts[boss_name] = attempt
    state.wipes = state.wipes + 1
    state.pullTime = nil

    m.info(string.format(
        "|cffFF0000[WIPE]|r %s - Tentative #%d - %s",
        boss_name, attempt, fmt_duration(duration)
    ))

    broadcast_raid_event("wipe", boss_name, duration, attempt)
    return true
end

--- Dmarre le timer de pull pour un boss
--- @param boss_name string  Nom du boss
function M.set_pull(boss_name)
    if boss_name and boss_name ~= "" then
        state.currentBoss = boss_name
    end
    state.pullTime = time()
    m.debug("Pull timer started: " .. (state.currentBoss or "?"))
end

--- Bascule PAUSE / RESUME
function M.toggle_pause()
    if not check_ready() then return end

    if state.paused then
        state.paused = false
        m.info("|cff00FF00[RESUME]|r Raid repris.")
        broadcast_raid_event("resume", state.raidName, 0, 0)
    else
        state.paused = true
        m.info("|cffFFFF00[PAUSE]|r Raid mis en pause.")
        broadcast_raid_event("pause", state.raidName, 0, 0)
    end
end

--- Envoie le rsum de fin de raid sur Discord
function M.send_summary()
    if not state.startTime then
        m.error(m.L( "raidtracker.no_active_session" ) or "No active session.")
        return false
    end
    if not check_ready() then return false end

    m.msg.raid_summary(
        state.raidName,
        state.startTime,
        time(),
        table.getn(state.kills),
        state.wipes,
        state.loots,
        m.db.user_settings.raid_log_channel_id,
        state.raidSession
    )

    m.info(string.format(
        "|cff88BBFF[SUMMARY]|r Rsum envoy - |cffFFD700%d kills|r, |cffFF5555%d wipes|r, |cffa335ee%d items|r",
        table.getn(state).kills, state.wipes, table.getn(state).loots
    ))
    return true
end

--- Vrifie si le joueur a le rle Discord de gestion de raid
function M.check_raid_role()
    if not m.db.user_settings.discord_id then return end
    m.msg.check_raid_role(m.db.user_settings.discord_id)
end

--- Callback appel par MessageHandler quand RAID_ROLE_RESULT reu
function M.on_role_result(has_perm, status_msg, linked_user_id, requested_user_id, character)
    state.has_permission = has_perm
    -- Persister dans les settings pour que EventPopup puisse l'utiliser
    if m.db and m.db.user_settings then
        m.db.user_settings.has_manager_role = has_perm

    end
    -- Nettoyage automatique des anciens evenements locaux si manager
    if has_perm and m.LocalEventManager then
        m.LocalEventManager.cleanup_old()
    end
    if m.RaidTrackerUI then
        m.RaidTrackerUI.update_permission(has_perm)
    end
    if m.EventManagePopup then
        m.EventManagePopup.on_role_result(has_perm, status_msg, linked_user_id, requested_user_id, character)
    end
end

--- Retourne l'tat courant (pour l'UI)
function M.get_state()
    return state
end

-- ============================================================
--  GESTION DES VNEMENTS WOW
-- ============================================================

function M.on_chat_loot(msg)
    process_loot_message(msg)
end

function M.on_combat_start()
    -- Dmarre le pull timer si un boss est dfini
    if state.active and state.currentBoss ~= "" and not state.pullTime then
        M.set_pull(state.currentBoss)
    end
end

function M.on_combat_end()
    -- On ne reset pas automatiquement le pull time ici (gr manuellement)
end

-- Dtection automatique de mort de boss via CHAT_MSG_COMBAT_HOSTILE_DEATH (vanilla)
-- Le message est du type: "Ragnaros dies."  /  "Ragnaros est mort."
local BOSS_DEATH_PATTERNS = {
    "^(.+) meurt%.$",   -- frFR
    "^(.+) dies%.$",    -- enUS
}

function M.on_hostile_death(msg)
    if not state.active or state.currentBoss == "" then return end
    for _, pattern in ipairs(BOSS_DEATH_PATTERNS) do
        local name = string.match(msg, pattern)
        if name and string.lower(name) == string.lower(state.currentBoss) then
            M.register_kill(state.currentBoss)
            return
        end
    end
end

-- ============================================================
--  ENREGISTREMENT DU MODULE
-- ============================================================

--- Demande la verification du role au demarrage
function M.request_role_check()
    if m.db and m.db.user_settings and m.db.user_settings.discord_id then
        M.check_raid_role()
        -- Vérifier aussi le rôle raider indépendamment
        if m.msg and m.msg.check_raider_role then
            m.msg.check_raider_role( m.db.user_settings.discord_id )
        end
        -- Vérifier le rôle member (in-game events)
        if m.msg and m.msg.check_member_role then
            m.msg.check_member_role( m.db.user_settings.discord_id )
        end
    end
end

m.RaidTracker = M
return M

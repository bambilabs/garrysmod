require( "dotenv" )

if LoadTCFEnv then
    LoadTCFEnv()
else
    env.load( ".env" )
end

local TELEMETRY_URL = env.getString( "WEB_TELEMETRY_URL", "" )
local TELEMETRY_SECRET = env.getString( "WEB_TELEMETRY_SECRET", "" )
local TELEMETRY_INTERVAL = env.getNumber( "WEB_TELEMETRY_INTERVAL", 60 )
local TELEMETRY_GUILD = env.getString( "WEB_TELEMETRY_GUILD", "" )

if TELEMETRY_URL == "" or TELEMETRY_SECRET == "" then return end

local function IsoNow()
    return os.date( "!%Y-%m-%dT%H:%M:%SZ" )
end

local function GetTelemetryServerId()
    local serverId = 0

    if GTowerServers and GTowerServers.GetServerId then
        serverId = GTowerServers:GetServerId()
    end

    if tonumber( serverId ) and tonumber( serverId ) > 0 then
        return tostring( serverId )
    end

    return tostring( game.GetIPAddress() )
end

local function GetPlayerJoinedAt( ply )
    if not IsValid( ply ) then
        return nil
    end

    if not ply._WebTelemetryJoinAt then
        ply._WebTelemetryJoinAt = CurTime()
        ply._WebTelemetryJoinAtIso = IsoNow()
    end

    return ply._WebTelemetryJoinAtIso
end

local function GetSessionMinutes( ply )
    if not IsValid( ply ) then
        return 0
    end

    if not ply._WebTelemetryJoinAt then
        ply._WebTelemetryJoinAt = CurTime()
    end

    return math.max( 0, ( CurTime() - ply._WebTelemetryJoinAt ) / 60 )
end

local function BuildPlayers()
    local players = {}

    for _, ply in ipairs( player.GetHumans() ) do
        if not IsValid( ply ) or ply:IsBot() then continue end

        local steamId64 = ply:SteamID64()
        local databaseId = ply.DatabaseID and ply:DatabaseID() or nil

        table.insert( players, {
            playerId = steamId64 != "0" and ( "steam:" .. steamId64 ) or nil,
            steamId64 = steamId64 != "0" and steamId64 or nil,
            databaseId = tonumber( databaseId ) or nil,
            joinedAt = GetPlayerJoinedAt( ply ),
            sessionMinutes = math.Round( GetSessionMinutes( ply ), 2 ),
            isNewPlayer = ply._NewPlayer == true,
        } )
    end

    return players
end

local function PostHeartbeat( reason )
    local payload = {
        recordedAt = IsoNow(),
        serverId = GetTelemetryServerId(),
        guild = TELEMETRY_GUILD,
        gamemode = engine.ActiveGamemode(),
        map = game.GetMap(),
        reason = reason or "heartbeat",
        players = BuildPlayers(),
    }

    HTTP( {
        url = TELEMETRY_URL,
        method = "POST",
        type = "application/json",
        headers = {
            ["Content-Type"] = "application/json",
            ["x-telemetry-secret"] = TELEMETRY_SECRET,
        },
        body = util.TableToJSON( payload, false ),
        success = function() end,
        failed = function( err )
            MsgC( Color( 255, 120, 120 ), "[WebTelemetry] " .. tostring( err ) .. "\n" )
        end,
    } )
end

hook.Add( "InitPostEntity", "WebTelemetryInit", function()
    timer.Simple( 20, function()
        PostHeartbeat( "server_start" )
    end )
end )

hook.Add( "PlayerAuthed", "WebTelemetryJoin", function( ply )
    if not IsValid( ply ) then return end
    ply._WebTelemetryJoinAt = CurTime()
    ply._WebTelemetryJoinAtIso = IsoNow()

    timer.Simple( 2, function()
        if IsValid( ply ) then
            PostHeartbeat( "player_join" )
        end
    end )
end )

hook.Add( "PlayerDisconnected", "WebTelemetryLeave", function()
    timer.Simple( 1, function()
        PostHeartbeat( "player_leave" )
    end )
end )

hook.Add( "PostPlayerDataLoaded", "WebTelemetryProfileLoaded", function( ply )
    if not IsValid( ply ) then return end
    GetPlayerJoinedAt( ply )
end )

timer.Create( "WebTelemetryHeartbeat", math.max( 15, TELEMETRY_INTERVAL ), 0, function()
    PostHeartbeat( "heartbeat" )
end )

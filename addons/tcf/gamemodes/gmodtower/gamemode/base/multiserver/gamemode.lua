---------------------------------
local LastThink = 0
local InQuery = false
local InQuerySince = 0

local function PromotePrivateServer(authHex)
    if not authHex or authHex == "" then return end

    local ips = GTowerServers:PlayerListToIDs(authHex)

    GTowerServers:Trace( "gomap", "PromotePrivateServer authHexLen=", tostring( string.len( authHex or "" ) ), " ips=", tostring( table.concat( ips, "," ) ) )

    if gateKeep and gateKeep.AuthorizedPlayers then
        gateKeep.AuthorizedPlayers = {}
        for _, ip in ipairs(ips) do
            gateKeep.AuthorizedPlayers[ip] = true
        end
    end

    GTowerServers:SetState(3)
    GTowerServers:UpdateDatabase()

    if gateKeep and gateKeep.ResetEmptyReadyServer then
        timer.Simple(45, function()
            gateKeep:ResetEmptyReadyServer()
        end)
    end
end

local function GoMapResult(res, status, err)
    InQuery = false
    InQuerySince = 0

    GTowerServers:Trace( "gomap", "GoMapResult status=", tostring( status ), " rows=", tostring( istable( res ) and table.Count( res ) or "nil" ), " err=", tostring( err ) )

    if status != QUERY_SUCCESS then
        SQLLog( "error", "gm_gomap lookup failed for server ", GTowerServers:GetServerId(), ": ", tostring( err ) )
        return
    end

    if table.Count(res) == 0 then
        return
    end

    local targetMap = string.lower(res[1].authplayers or "")
    local authHex = res[1].gomap or ""

    SQLLog( "multiserver", "Consumed gm_gomap for server ", GTowerServers:GetServerId(), " map ", targetMap, " authhex_len ", string.len( authHex or "" ) )
    GTowerServers:Trace( "gomap", "Consumed row targetMap=", targetMap, " authHex=", tostring( authHex ) )

    file.Write("authedusers" .. tostring(GTowerServers:GetServerId()) .. ".txt", authHex)
    PromotePrivateServer(authHex)

    Database.Query("DELETE FROM `gm_gomap` WHERE `serverid` = " .. GTowerServers:GetServerId() .. ";")

    if targetMap != "" and string.lower(game.GetMap()) != targetMap then
        timer.Simple(0.25, function()
            hook.Call("LastChanceMapChange", GAMEMODE, targetMap)
            RunConsoleCommand("gmt_forcelevel", targetMap)
        end)
    end
end

local function PollBufferGoMap()
    local Gamemode = GTowerServers:Self()

    if not Gamemode or Gamemode.Private != true then
        if timer.Exists( "GTowerBufferGoMap" ) then
            GTowerServers:Trace( "gomap", "PollBufferGoMap stopping timer because gamemode is not private" )
            timer.Remove( "GTowerBufferGoMap" )
        end
        return
    end

    if not Database or not Database.IsConnected or not Database.IsConnected() then
        GTowerServers:Trace( "gomap", "PollBufferGoMap skipped; DB disconnected" )
        return
    end

    if InQuery == true and InQuerySince > 0 and ( CurTime() - InQuerySince ) > 10 then
        InQuery = false
        InQuerySince = 0
        SQLLog( "error", "gm_gomap poll was stuck for server ", GTowerServers:GetServerId(), ", resetting query lock." )
    end

    if GTowerServers:GetState() != 1 or InQuery == true then
        GTowerServers:Trace( "gomap", "PollBufferGoMap skipped; state=", tostring( GTowerServers:GetState() ), " inQuery=", tostring( InQuery ) )
        return
    end

    if LastThink > CurTime() then
        return
    end

    LastThink = CurTime() + 0.5
    InQuery = true
    InQuerySince = CurTime()

    GTowerServers:Trace( "gomap", "PollBufferGoMap querying gm_gomap for server ", tostring( GTowerServers:GetServerId() ) )

    Database.Query(
        "SELECT authplayers, HEX(`gomap`) as `gomap` FROM `gm_gomap` WHERE `serverid` = " .. GTowerServers:GetServerId() .. ";",
        GoMapResult
    )
end

local function StartBufferGoMapWatcher()
    RunConsoleCommand( "sv_hibernate_think", "1" )

    MsgN( "[Multiserver] Starting gm_gomap watcher for server " .. tostring( GTowerServers:GetServerId() ) )
    GTowerServers:Trace( "gomap", "StartBufferGoMapWatcher called" )

    if timer.Exists( "GTowerBufferGoMap" ) then
        GTowerServers:Trace( "gomap", "StartBufferGoMapWatcher skipped; timer already exists" )
        return
    end

    timer.Create( "GTowerBufferGoMap", 0.5, 0, PollBufferGoMap )
    PollBufferGoMap()
end

hook.Add("DatabaseConnected", "MultiServerBufferMap", StartBufferGoMapWatcher)
hook.Add("GTowerServersDatabaseUpdated", "MultiServerBufferMapFallback", PollBufferGoMap)

timer.Simple(1, function()
    if SERVER and Database and Database.IsConnected and Database.IsConnected() then
        StartBufferGoMapWatcher()
    end
end)

function GTowerServers:GetRandomMap()

    local Gamemode = GTowerServers:Self()

    if Gamemode && Gamemode.Maps then
        return Gamemode.Maps[ math.random( 1, #Gamemode.Maps ) ]
    end

end

concommand.Add("gmt_mapbufferinquery", function( ply, cmd, args )

    if ply == NULL then
        Msg( "Query in : " , InQuery , "\n")
    end

end )

gateKeep = {}

gateKeep.MaxSlots = 0
gateKeep.AdminBypass = true
gateKeep.AuthorizedPlayers = {}
gateKeep.GoMapQueryInFlight = false
gateKeep.GoMapQuerySince = 0
gateKeep.GoMapWaitingForLoadingSince = 0
gateKeep.GoMapLoadingGrace = 5

if SERVER and GTowerServers and GTowerServers.Trace then
    GTowerServers:Trace( "load", "base/multiserver/gatekeeper.lua loaded" )
end

function GetAuthorizedPlayers()

    return gateKeep.AuthorizedPlayers

end

local ClearPendingPrivateQueue

local function PromotePrivateServerFromGoMap( targetMap, authHex )
    if not authHex or authHex == "" then return end

    local ips = GTowerServers:PlayerListToIDs( authHex )

    GTowerServers:Trace( "gate", "PromotePrivateServerFromGoMap targetMap=", tostring( targetMap ), " authHex=", tostring( authHex ), " ips=", tostring( table.concat( ips, "," ) ) )

    gateKeep.AuthorizedPlayers = {}

    SQLLog( "multiserver", "Authorized ips " .. table.concat( ips, ", " ) )
    for _, ip in ipairs( ips ) do
        gateKeep.AuthorizedPlayers[ ip ] = true
    end

    file.Write( "authedusers" .. tostring( GTowerServers:GetServerId() ) .. ".txt", authHex )

    local clearErr = ClearPendingPrivateQueue()
    GTowerServers:Trace( "gate", "PromotePrivateServerFromGoMap cleared gm_loading err=", tostring( clearErr ) )
    if clearErr then
        SQLLog( "error", "Gatekeeper failed to clear gm_loading for server ", GTowerServers:GetServerId(), ": ", tostring( clearErr ) )
    end

    GTowerServers:SetState( 3 )
    GTowerServers:UpdateDatabase()
    timer.Simple( 45, function() gateKeep:ResetEmptyReadyServer() end )

    if targetMap != "" and string.lower( game.GetMap() ) != string.lower( targetMap ) then
        timer.Simple( 0.25, function()
            hook.Call( "LastChanceMapChange", GAMEMODE, targetMap )
            RunConsoleCommand( "gmt_forcelevel", targetMap )
        end )
    end
end

local function RunSyncQuery( query, traceLabel )
    if not Database or not Database.GetObject then
        return nil, "Database.GetObject unavailable"
    end

    local driver = Database.GetObject()
    local db = driver and driver.Object

    if not driver or driver.Identifier != "mysqloo" or not db or not db.query then
        return nil, "Sync gm_gomap query unavailable for current driver"
    end

    local qu = db:query( query )

    GTowerServers:Trace( "gate", tostring( traceLabel or "RunSyncQuery" ), " start sql=", tostring( query ) )

    local ok, waitErr = xpcall( function()
        qu:start()
        qu:wait( true )
    end, debug.traceback )

    if not ok then
        return nil, waitErr
    end

    local err = qu:error()
    if err and err != "" then
        return nil, err
    end

    return qu:getData() or {}, nil
end

local function GetPrivateLoadingGamemode()
    local Gamemode = GTowerServers and GTowerServers.Self and GTowerServers:Self()

    if Gamemode and Gamemode.Gamemode then
        return tostring( Gamemode.Gamemode )
    end

    if GTowerServers and GTowerServers.Gamemode then
        return tostring( GTowerServers:Gamemode() or "" )
    end

    return ""
end

local function GetPendingLoadingSteamIDs()
    local loadingGamemode = GetPrivateLoadingGamemode()

    if loadingGamemode == "" then
        return "", "Missing private loading gamemode", false
    end

    local res, err = RunSyncQuery(
        "SELECT `steamids` FROM `gm_loading` WHERE `gamemode` = " .. Database.Escape( loadingGamemode, true ) .. " LIMIT 1;",
        "RunLoadingQuerySync"
    )

    if res == nil then
        return "", err, false
    end

    if type( res ) != "table" or table.Count( res ) == 0 then
        return "", nil, false
    end

    return string.Trim( tostring( res[ 1 ].steamids or "" ) ), nil, true
end

ClearPendingPrivateQueue = function()
    local loadingGamemode = GetPrivateLoadingGamemode()

    if loadingGamemode == "" then
        return "Missing private loading gamemode"
    end

    local _, err = RunSyncQuery(
        "UPDATE `gm_loading` SET `steamids` = '' WHERE `gamemode` = " .. Database.Escape( loadingGamemode, true ) .. ";",
        "ClearLoadingQuerySync"
    )

    return err
end

local function DeletePendingGoMap( ServerID )
    local _, err = RunSyncQuery(
        "DELETE FROM `gm_gomap` WHERE `serverid` = " .. ServerID .. ";",
        "DeleteGoMapQuerySync"
    )

    return err
end

local function InitGateKeep()
    GTowerServers:Trace( "gate", "InitGateKeep" )
    gateKeep:GrabGoList()
end

hook.Add( "DatabaseConnected", "GMTGateKeepInit", InitGateKeep )

timer.Simple(1, function()
    if SERVER and Database and Database.IsConnected and Database.IsConnected() then
        InitGateKeep()
    end
end)

hook.Add("PlayerPasswordAuth", "OnlyGMTConnections", function(Name, pass, steam, ip)

    local Gamemode = GTowerServers:Self()
    local Pos = string.find(ip, ":")

    if !Gamemode || !Pos then return end

    ip = string.sub(ip, 1, Pos - 1)

    local message = "You are not authorized to join this server"

    --local clients = gatekeeper.GetNumClients()
    local total = gatekeeper.GetNumClients().total

    // allow admins to join regardless, based on steam
    if gateKeep.AdminBypass && Admins.IsAdmin(steam) then return end

    for _, v in ipairs( player.GetAll() ) do
        if v:IsAdmin() then
            total = total - 1
        end
    end

    if Gamemode.CheckForExtraSlots then

        if (total + 1) <= gateKeep.MaxSlots then return end
        message = "The server is full, and you aren't returning from another server."

    elseif total == Gamemode.MaxPlayers then

        // the maxplayers should be +1 so an admin can join, and also handle the bot
        if table.HasValue( Admins.List, steam ) then return end
        message = "This slot is reserved for admins"

    end

    if !gateKeep.AuthorizedPlayers[ip] then

        if Gamemode.Private then
            SQLLog( "multiserver", "Dropping connection from " .. tostring(ip) .. " (" .. tostring(Name) .. ") not authorized." )
        end

        return {false, message}

    end

end)

/*
* Obtains the list of players currently on the server
*/
function gateKeep:GrabStackList(ServerID)
    GTowerServers:Trace( "gate", "GrabStackList server=", tostring( ServerID ) )

    local Query = "SELECT `id`,HEX(`lastplayers`) FROM `gm_servers` WHERE `id` != " .. ServerID .. " AND `lastupdate` > " .. (os.time() - GTowerServers.UpdateTolerance)

    Database.Query( Query, function( res, status, err )

        if status != QUERY_SUCCESS then
            print("Error getting players coming back" .. err)
            return
        end

        gateKeep.AuthorizedPlayers = {}

        if type(res) != "table" then return end

        for _, v in pairs(res) do

            for x, y in pairs(GTowerServers:PlayerListToIDs(v.lastplayers)) do

                gateKeep.AuthorizedPlayers[y] = true

            end

        end


    end )

end

function gateKeep:ResetEmptyReadyServer()

    local Count = player.GetCount()
    if Count == 0 && GTowerServers:GetState() == 3 then

        timer.Simple(60,function()

            local Count = player.GetCount()

            if Count == 0 && GTowerServers:GetState() == 3 then
                SQLLog( "multiserver", "In state 3 too long, changing level" )
                ErrorNoHalt("In state 3 but no players joined, restarting")
                GTowerServers:EmptyServer()
                --ChangeLevel(GTowerServers:GetRandomMap())
                local MapName = GTowerServers:GetRandomMap()
                hook.Call("LastChanceMapChange", GAMEMODE, MapName)
                RunConsoleCommand("gmt_forcelevel", MapName)
            end

        end)

    end

end

function gateKeep:PollGoMap( ServerID )
    GTowerServers:Trace( "gate", "PollGoMap tick server=", tostring( ServerID ), " state=", tostring( GTowerServers:GetState() ), " inFlight=", tostring( gateKeep.GoMapQueryInFlight ) )

    if gateKeep.GoMapQueryInFlight == true and gateKeep.GoMapQuerySince > 0 and ( CurTime() - gateKeep.GoMapQuerySince ) > 10 then
        GTowerServers:Trace( "gate", "PollGoMap resetting stale inFlight query for server=", tostring( ServerID ) )
        gateKeep.GoMapQueryInFlight = false
        gateKeep.GoMapQuerySince = 0
    end

    if gateKeep.GoMapQueryInFlight == true then
        return
    end

    if not Database.IsConnected() then
        GTowerServers:Trace( "gate", "PollGoMap skipped; DB disconnected" )
        return
    end
    if GTowerServers:GetState() != 1 then
        GTowerServers:Trace( "gate", "PollGoMap skipped; state=", tostring( GTowerServers:GetState() ) )
        return
    end

    gateKeep.GoMapQueryInFlight = true
    gateKeep.GoMapQuerySince = CurTime()
    GTowerServers:Trace( "gate", "PollGoMap querying gm_gomap for server=", tostring( ServerID ) )

    local syncRes, syncErr = RunSyncQuery(
        "SELECT `authplayers`, `gomap` FROM `gm_gomap` WHERE `serverid` = " .. ServerID .. ";",
        "RunGoMapQuerySync"
    )

    if syncRes != nil or syncErr != "Sync gm_gomap query unavailable for current driver" then
        gateKeep.GoMapQueryInFlight = false
        gateKeep.GoMapQuerySince = 0

        GTowerServers:Trace(
            "gate",
            "PollGoMap sync result rows=", tostring( istable( syncRes ) and table.Count( syncRes ) or "nil" ),
            " err=", tostring( syncErr )
        )

        if syncErr then
            SQLLog( "error", "Gatekeeper sync gm_gomap lookup failed for server ", ServerID, ": ", tostring( syncErr ) )
            return
        end

        if type( syncRes ) != "table" or table.Count( syncRes ) == 0 then
            gateKeep.GoMapWaitingForLoadingSince = 0
            return
        end

        local targetMap = string.lower( syncRes[1].authplayers or "" )
        local authHex = GTowerServers:NormalizeHexPayload( syncRes[1].gomap )
        local loadingSteamIDs, loadingErr, loadingRowFound = GetPendingLoadingSteamIDs()

        GTowerServers:Trace(
            "gate",
            "PollGoMap loading batch hasRow=", tostring( loadingRowFound ),
            " steamidsLen=", tostring( string.len( loadingSteamIDs or "" ) ),
            " err=", tostring( loadingErr )
        )

        if loadingErr then
            SQLLog( "error", "Gatekeeper gm_loading lookup failed for server ", ServerID, ": ", tostring( loadingErr ) )
            return
        end

        if loadingSteamIDs == "" then
            local now = CurTime()

            if gateKeep.GoMapWaitingForLoadingSince == 0 then
                gateKeep.GoMapWaitingForLoadingSince = now
                GTowerServers:Trace( "gate", "PollGoMap found gm_gomap without gm_loading batch; waiting grace=", tostring( gateKeep.GoMapLoadingGrace ) )
                return
            end

            local age = now - gateKeep.GoMapWaitingForLoadingSince
            GTowerServers:Trace( "gate", "PollGoMap waiting for gm_loading batch age=", tostring( age ) )

            if age < gateKeep.GoMapLoadingGrace then
                return
            end

            SQLLog( "multiserver", "Discarding stale gm_gomap for server ", ServerID, " map ", targetMap )

            local staleDeleteErr = DeletePendingGoMap( ServerID )
            GTowerServers:Trace( "gate", "PollGoMap stale row delete err=", tostring( staleDeleteErr ) )
            if staleDeleteErr then
                SQLLog( "error", "Gatekeeper failed to delete stale gm_gomap for server ", ServerID, ": ", tostring( staleDeleteErr ) )
            end

            gateKeep.GoMapWaitingForLoadingSince = 0
            return
        end

        gateKeep.GoMapWaitingForLoadingSince = 0

        SQLLog( "multiserver", "Gatekeeper sync consumed gm_gomap for server ", ServerID, " map ", targetMap, " authhex_len ", string.len( authHex or "" ) )
        GTowerServers:Trace( "gate", "PollGoMap sync normalized authHexLen=", tostring( string.len( authHex or "" ) ), " rawLen=", tostring( string.len( tostring( syncRes[1].gomap or "" ) ) ) )

        PromotePrivateServerFromGoMap( targetMap, authHex )
        local deleteErr = DeletePendingGoMap( ServerID )
        GTowerServers:Trace( "gate", "PollGoMap consumed row delete err=", tostring( deleteErr ) )
        if deleteErr then
            SQLLog( "error", "Gatekeeper failed to delete consumed gm_gomap for server ", ServerID, ": ", tostring( deleteErr ) )
        end
        return
    end

    Database.Query(
        "SELECT `authplayers`, `gomap` FROM `gm_gomap` WHERE `serverid` = " .. ServerID .. ";",
        function( res, status, err )
            gateKeep.GoMapQueryInFlight = false
            gateKeep.GoMapQuerySince = 0
            GTowerServers:Trace( "gate", "PollGoMap result status=", tostring( status ), " rows=", tostring( istable( res ) and table.Count( res ) or "nil" ), " err=", tostring( err ) )

            if status != QUERY_SUCCESS then
                SQLLog( "error", "Gatekeeper gm_gomap lookup failed for server ", ServerID, ": ", tostring( err ) )
                return
            end

            if type( res ) != "table" or table.Count( res ) == 0 then
                gateKeep.GoMapWaitingForLoadingSince = 0
                return
            end

            local targetMap = string.lower( res[1].authplayers or "" )
            local authHex = GTowerServers:NormalizeHexPayload( res[1].gomap )

            SQLLog( "multiserver", "Gatekeeper consumed gm_gomap for server ", ServerID, " map ", targetMap, " authhex_len ", string.len( authHex or "" ) )
            GTowerServers:Trace( "gate", "PollGoMap normalized authHexLen=", tostring( string.len( authHex or "" ) ), " rawLen=", tostring( string.len( tostring( res[1].gomap or "" ) ) ) )

            PromotePrivateServerFromGoMap( targetMap, authHex )
            Database.Query( "DELETE FROM `gm_gomap` WHERE `serverid` = " .. ServerID .. ";" )
        end
    )
end

// read text file generated to initialize list
function gateKeep:GrabGoingToServer(ServerID)

    local txt = "authedusers" .. tostring(GTowerServers:GetServerId()) .. ".txt"
    GTowerServers:Trace( "gate", "GrabGoingToServer file=", txt, " exists=", tostring( file.Exists( txt, "DATA" ) ) )

    if file.Exists(txt, "DATA") then
        if GTowerServers:GetState() == 3 then
            GTowerServers:Trace( "gate", "GrabGoingToServer removing local auth file because server already in state 3" )
            file.Delete( txt )
            return
        end

        local loadingSteamIDs, loadingErr, loadingRowFound = GetPendingLoadingSteamIDs()
        GTowerServers:Trace(
            "gate",
            "GrabGoingToServer loading batch hasRow=", tostring( loadingRowFound ),
            " steamidsLen=", tostring( string.len( loadingSteamIDs or "" ) ),
            " err=", tostring( loadingErr )
        )

        if loadingErr then
            SQLLog( "error", "Gatekeeper gm_loading lookup failed while reading auth file for server ", ServerID, ": ", tostring( loadingErr ) )
            return
        end

        if loadingSteamIDs == "" then
            GTowerServers:Trace( "gate", "GrabGoingToServer deleting stale auth file because gm_loading is empty" )
            file.Delete( txt )
            return
        end

        local contents = file.Read(txt, "DATA") or ""
        GTowerServers:Trace( "gate", "GrabGoingToServer contentsLen=", tostring( string.len( contents ) ) )

        if contents == "" then
            file.Delete(txt)
            return
        end

        local ips = GTowerServers:PlayerListToIDs(contents)

        gateKeep.AuthorizedPlayers = {}

        SQLLog( "multiserver", "Authorized ips " .. table.concat(ips, ", ") )
        for _, v in pairs(ips) do
            gateKeep.AuthorizedPlayers[v] = true
        end

        file.Delete(txt)

        GTowerServers:SetState(3)
        GTowerServers:UpdateDatabase()
        timer.Simple(45, function() gateKeep:ResetEmptyReadyServer() end)
    end

end

function gateKeep:GrabGoList()

    gateKeep.MaxSlots = GetMaxSlots()

    GTowerServers:Trace( "gate", "GrabGoList maxSlots=", tostring( gateKeep.MaxSlots ) )

    if not Database.IsConnected() then
        GTowerServers:Trace( "gate", "GrabGoList skipped; DB disconnected" )
        return
    end

    local ServerID = GTowerServers:GetServerId()
    local Gamemode = GTowerServers:Self()

    GTowerServers:Trace( "gate", "GrabGoList server=", tostring( ServerID ), " gamemode=", tostring( Gamemode and Gamemode.Gamemode or "nil" ), " private=", tostring( Gamemode and Gamemode.Private ) )

    if !Gamemode then return end

    // this server can overflow, if they're on the stack somewhere
    if Gamemode.CheckForExtraSlots then

        gateKeep:GrabStackList(ServerID)

        timer.Create( "GTowerServersGoList", 1, 0, function() gateKeep.GrabGoList() end)

    // this server can't overflow, but it can only accept connections from players from the list it got from gomap
    elseif Gamemode.Private then

        gateKeep:GrabGoingToServer(ServerID)
        gateKeep:PollGoMap(ServerID)

        if not timer.Exists("GTowerServersGoListPrivate") then
            timer.Create("GTowerServersGoListPrivate", 1, 0, function()
                if not GTowerServers or not GTowerServers.GetServerId then return end
                local serverId = GTowerServers:GetServerId()
                gateKeep:GrabGoingToServer(serverId)
                gateKeep:PollGoMap(serverId)
            end)
        end

    end

end

concommand.Add("listauthorizedids", function(ply, cmd, args)

    if !IsValid(ply) or !ply:IsAdmin() then return end

    for k, _ in pairs(gateKeep.AuthorizedPlayers) do
        if !IsValid(ply) then
            print(k)
        else
            ply:PrintMessage(HUD_PRINTCONSOLE, k)
        end
    end

end)

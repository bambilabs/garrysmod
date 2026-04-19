gateKeep = {}

gateKeep.MaxSlots = 0
gateKeep.AdminBypass = true
gateKeep.AuthorizedPlayers = {}
gateKeep.GoMapQueryInFlight = false

function GetAuthorizedPlayers()

    return gateKeep.AuthorizedPlayers

end

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
    GTowerServers:Trace( "gate", "PollGoMap querying gm_gomap for server=", tostring( ServerID ) )

    Database.Query(
        "SELECT `authplayers`, HEX(`gomap`) as `gomap` FROM `gm_gomap` WHERE `serverid` = " .. ServerID .. ";",
        function( res, status, err )
            gateKeep.GoMapQueryInFlight = false
            GTowerServers:Trace( "gate", "PollGoMap result status=", tostring( status ), " rows=", tostring( istable( res ) and table.Count( res ) or "nil" ), " err=", tostring( err ) )

            if status != QUERY_SUCCESS then
                SQLLog( "error", "Gatekeeper gm_gomap lookup failed for server ", ServerID, ": ", tostring( err ) )
                return
            end

            if type( res ) != "table" or table.Count( res ) == 0 then
                return
            end

            local targetMap = string.lower( res[1].authplayers or "" )
            local authHex = res[1].gomap or ""

            SQLLog( "multiserver", "Gatekeeper consumed gm_gomap for server ", ServerID, " map ", targetMap, " authhex_len ", string.len( authHex or "" ) )

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

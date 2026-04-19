---------------------------------
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

if SERVER and GTowerServers and GTowerServers.Trace then
	GTowerServers:Trace( "load", "base/multiserver/init.lua begin" )
end

if SERVER and GTowerServers and GTowerServers.Trace then
	GTowerServers:Trace( "load", "including game.lua" )
end
include("game.lua")
if SERVER and GTowerServers and GTowerServers.Trace then
	GTowerServers:Trace( "load", "including password.lua" )
end
include("password.lua")
if SERVER and GTowerServers and GTowerServers.Trace then
	GTowerServers:Trace( "load", "including gamemode.lua" )
end
include("gamemode.lua")
if SERVER and GTowerServers and GTowerServers.Trace then
	GTowerServers:Trace( "load", "including hex.lua" )
end
include("hex.lua")
if SERVER and GTowerServers and GTowerServers.Trace then
	GTowerServers:Trace( "load", "including gatekeeper.lua" )
end
include("gatekeeper.lua")

if SERVER and GTowerServers and GTowerServers.Trace then
	GTowerServers:Trace( "load", "base/multiserver/init.lua includes complete" )
end

/*
	STATE LIST

	1 = Ready to get players
	2 = Server is busy
	3 = Has a list of players and ready to receive them
*/
GTowerServers.CurState = 0

local UpdateInProgress = false

function GTowerServers:GetState()
	return GTowerServers.CurState
end

function GTowerServers:SetState( state )
	GTowerServers.CurState = state

	SQLLog( "multiserver", "State changed to: " .. tostring( state ) )
	GTowerServers:Trace( "state", "SetState(", tostring( state ), ")" )
end

function GM:SetStatus( state )
	GTowerServers:SetState( state )
end
GM.SetState = GM.SetStatus

function GTowerServers:GetServerId()
	return GetConVarNumber("gmt_srvid")
end

function GTowerServers:GetMessage()
	local HookMessages = hook.GetTable().GTowerMsg

	if HookMessages then
		for _, v in pairs( HookMessages ) do
			if type( v ) == "function" then
				return v()
			end
		end
	end

	return ""
end

function DecodePlayersFromSQLId(hex)
	local players = {}
	local data = Hex( hex )

	while data:CanRead( 8 ) do
		table.insert(players, data:Read(8))
	end

	return players
end

local function GetPlayerSQLIdHex()

	local Data = Hex()
	local PlayerList = player.GetAll()

	for _, ply in pairs( PlayerList ) do
		Data:Write( ply:DatabaseID(), 8 )
	end

	return Data:Get(), #PlayerList

end

local function MaybePollPrivateGoMap( reason )

	if not SERVER or not gateKeep or not gateKeep.PollGoMap or not GTowerServers or not GTowerServers.GetServerId then
		return
	end

	local Gamemode = GTowerServers:Self()
	if not Gamemode or Gamemode.Private != true then
		return
	end

	local ServerID = GTowerServers:GetServerId()

	GTowerServers:Trace(
		"gomap-sync",
		"MaybePollPrivateGoMap reason=", tostring( reason ),
		" server=", tostring( ServerID ),
		" state=", tostring( GTowerServers:GetState() ),
		" dbConnected=", tostring( Database.IsConnected() )
	)

	if gateKeep.GrabGoingToServer then
		gateKeep:GrabGoingToServer( ServerID )
	end

	if GTowerServers:GetState() == 1 then
		gateKeep:PollGoMap( ServerID )
	end

end

local function GTowerServerDatabaseResult( res, status, err )
	UpdateInProgress = false

	GTowerServers:Trace(
		"update",
		"GTowerServerDatabaseResult status=", tostring( status ),
		" rows=", tostring( istable( res ) and table.Count( res ) or "nil" ),
		" err=", tostring( err )
	)

	if status != QUERY_SUCCESS then
		return
	end

	hook.Call("GTowerServersDatabaseUpdated", GAMEMODE)
end

//The playerstack will be the list of players that will be allowed to join the main server
function GTowerServers:UpdateDatabase( playerstack )

	if not Database.IsConnected() then
		self:Trace( "update", "Skipped UpdateDatabase because DB is disconnected" )
		return
	end

	local ServerID = self:GetServerId()
	
	if ServerID == 0 then
		Msg("No Server id found")
		return
	end

	local serverAddress = string.Explode( ":", game.GetIPAddress() )
	local PlayerData, PlayerCount = GetPlayerSQLIdHex()
	local gamemsg = GTowerServers:GetMessage()

	local data = {
		port = serverAddress[2],
		players = PlayerCount,
		maxplayers = game.MaxPlayers(),
		map = Database.Escape( string.lower( game.GetMap() ), true ),
		gamemode = Database.Escape( self:Gamemode(), true ),
		password = Database.Escape( GetConVarString( "sv_password" ) or "", true ),
		status = Database.Escape( self:GetState(), true ),
		playerlist = PlayerData,
		lastupdate = os.time(),

		msg = gamemsg and Database.Escape( gamemsg, true ) or nil,
		lastplayers = playerstack and Database.Escape( playerstack, true ) or nil,
	}

	local query = "UPDATE `gm_servers` SET " .. Database.CreateUpdateQuery( data ) .. " WHERE `id` = " .. ServerID .. ";"

	self:Trace(
		"update",
		"UpdateDatabase state=", tostring( self:GetState() ),
		" map=", tostring( game.GetMap() ),
		" players=", tostring( PlayerCount ),
		" msg=", tostring( gamemsg ),
		" playerstack=", tostring( playerstack or "nil" )
	)
	
	UpdateInProgress = true

	Database.Query( query, GTowerServerDatabaseResult )
	MaybePollPrivateGoMap( "UpdateDatabase" )

end

function UpdateMultiServer()
	GTowerServers:Trace( "update", "UpdateMultiServer invoked" )
	GTowerServers:UpdateDatabase()
	if timer.Exists("GTowerServersRepeat") then
		GTowerServers:Trace( "timer", "UpdateMultiServer restarting GTowerServersRepeat" )
		timer.Start("GTowerServersRepeat")
	end
end

local function BootMultiServerSync(attempt)
	attempt = attempt or 0

	if not Database or not Database.IsConnected or not Database.IsConnected() then
		GTowerServers:Trace( "boot", "BootMultiServerSync waiting for DB; attempt=", tostring( attempt ) )
		if attempt < 30 then
			timer.Simple(1, function()
				BootMultiServerSync(attempt + 1)
			end)
		end
		return
	end

	if GTowerServers:GetState() <= 1 then
		GTowerServers:SetState(1)
	end

	GTowerServers:Trace( "boot", "BootMultiServerSync continuing; state=", tostring( GTowerServers:GetState() ) )

	UpdateMultiServer()
end

hook.Add("MapChange", "GTowerMultiServersMap", function()
	GTowerServers:Trace( "hook", "MapChange -> UpdateMultiServer" )
	UpdateMultiServer()
end )
hook.Add("InitPostEntity", "GTowerMultiServerInit", function()
	if GTowerServers:GetState() <= 1 then
		GTowerServers:SetState( 1 )
	end
	GTowerServers:Trace( "hook", "InitPostEntity -> UpdateDatabase; state=", tostring( GTowerServers:GetState() ) )
	GTowerServers:UpdateDatabase()
end )
hook.Add("CanChangeLevel", "UpdatingMultiServer", function()
	if UpdateInProgress == true then
		return false
	end
end )

hook.Add( "DatabaseConnected", "GTowerServersConnect", UpdateMultiServer )
hook.Add( "PlayerDisconnected", "GTowerServersDisConnect", UpdateMultiServer )
timer.Create( "GTowerServersRepeat", GTowerServers.UpdateRate, 0, function()
	GTowerServers:Trace( "timer", "GTowerServersRepeat tick" )
	UpdateMultiServer()

	if SERVER and gateKeep and gateKeep.GrabGoList then
		GTowerServers:Trace( "timer", "GTowerServersRepeat forcing gateKeep:GrabGoList()" )
		gateKeep:GrabGoList()
	end
end )

timer.Simple(1, function()
	BootMultiServerSync()
end)

timer.Simple(3, function()
	GTowerServers:Trace(
		"boot",
		"Timer snapshot repeat=", tostring( timer.Exists( "GTowerServersRepeat" ) ),
		" private=", tostring( timer.Exists( "GTowerServersGoListPrivate" ) ),
		" buffer=", tostring( timer.Exists( "GTowerBufferGoMap" ) ),
		" dbConnected=", tostring( Database and Database.IsConnected and Database.IsConnected() ),
		" state=", tostring( GTowerServers:GetState() )
	)
end)

local function PrintMultiServerDiagLine( ply, msg )
	if IsValid( ply ) then
		ply:PrintMessage( HUD_PRINTCONSOLE, msg )
	else
		MsgN( msg )
	end
end

concommand.Add( "gmt_multiserver_diag", function( ply )
	if IsValid( ply ) and not ply:IsAdmin() then return end

	local Gamemode = GTowerServers:Self()
	local Hooks = hook.GetTable()
	local DatabaseConnectedHooks = Hooks.DatabaseConnected or {}
	local DatabaseUpdatedHooks = Hooks.GTowerServersDatabaseUpdated or {}

	PrintMultiServerDiagLine( ply, "[MSDBG][diag] serverid=" .. tostring( GTowerServers:GetServerId() ) .. " gamemode=" .. tostring( GTowerServers:Gamemode() ) .. " private=" .. tostring( Gamemode and Gamemode.Private ) .. " state=" .. tostring( GTowerServers:GetState() ) )
	PrintMultiServerDiagLine( ply, "[MSDBG][diag] db_connected=" .. tostring( Database.IsConnected() ) .. " repeat_timer=" .. tostring( timer.Exists( "GTowerServersRepeat" ) ) .. " private_timer=" .. tostring( timer.Exists( "GTowerServersGoListPrivate" ) ) .. " gomap_timer=" .. tostring( timer.Exists( "GTowerBufferGoMap" ) ) )
	PrintMultiServerDiagLine( ply, "[MSDBG][diag] db_hooks core=" .. tostring( DatabaseConnectedHooks.GTowerServersConnect != nil ) .. " gate=" .. tostring( DatabaseConnectedHooks.GMTGateKeepInit != nil ) .. " buffer=" .. tostring( DatabaseConnectedHooks.MultiServerBufferMap != nil ) )
	PrintMultiServerDiagLine( ply, "[MSDBG][diag] updated_hooks gomap_fallback=" .. tostring( DatabaseUpdatedHooks.MultiServerBufferMapFallback != nil ) )

	if gateKeep then
		PrintMultiServerDiagLine( ply, "[MSDBG][diag] gate inflight=" .. tostring( gateKeep.GoMapQueryInFlight ) .. " authorized_count=" .. tostring( table.Count( gateKeep.AuthorizedPlayers or {} ) ) )
	end
end )

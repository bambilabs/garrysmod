---------------------------------
GTowerServers = GTowerServers or {}
GTowerServers.DEBUG = false
GTowerServers.UpdateRate = 5.0
GTowerServers.UpdateTolerance = GTowerServers.UpdateRate * 8

if SERVER then
	CreateConVar( "gmt_multiserver_trace", "0", FCVAR_ARCHIVE )

	function GTowerServers:Trace( tag, ... )
		local cvar = GetConVar( "gmt_multiserver_trace" )
		if cvar and not cvar:GetBool() then
			return
		end

		local parts = {}
		for _, v in ipairs( { ... } ) do
			table.insert( parts, tostring( v ) )
		end

		local srvid = "?"
		if self.GetServerId then
			srvid = tostring( self:GetServerId() )
		end

		MsgN( "[MSDBG][srvid=" .. srvid .. "][" .. tostring( tag ) .. "] " .. table.concat( parts, "" ) )
	end
end

function GTowerServers:NormalizeHexPayload( value )
	if value == nil then
		return ""
	end

	value = tostring( value )

	if string.sub( value, 1, 2 ) == "0x" or string.sub( value, 1, 2 ) == "0X" then
		return string.upper( string.sub( value, 3 ) )
	end

	if string.match( value, "^[0-9A-Fa-f]+$" ) then
		return string.upper( value )
	end

	local bytes = {}
	for i = 1, string.len( value ) do
		bytes[ i ] = string.format( "%02X", string.byte( value, i ) )
	end

	return table.concat( bytes )
end

GTowerServers.GamemodeNames = file.Find("gmodtower/gamemode/base/multiserver/gamemodes/*.lua", "LUA") 
GTowerServers.Gamemodes = {}
for _, v in pairs( GTowerServers.GamemodeNames ) do
	GMode = {}
	include( "gamemodes/" .. v )
	
	GTowerServers.Gamemodes[ string.lower( string.Replace( v, ".lua", "" ) ) ] = GMode
	
	if SERVER then
		AddCSLuaFile( "gamemodes/" .. v )
	end
end
GMode = nil

function GTowerServers:Gamemode()
	return string.lower( string.Replace( GAMEMODE.Folder, "gamemodes/", "" ) )
end

function GTowerServers:GetGamemode( gm )
	return self.Gamemodes[ gm ]
end

function GTowerServers:Self()
	return self:GetGamemode( self:Gamemode() )
end

if SERVER then
	timer.Simple( 0, function()
		if GTowerServers and GTowerServers.Trace then
			GTowerServers:Trace( "shared", "Loaded multiserver shared for gamemode=", GTowerServers:Gamemode() )
		end
	end )
end

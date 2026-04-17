--[[---------------------------------------------------------
	Media Player Metadata

	All media metadata is cached in an SQLite table for quick
	lookup and to prevent unnecessary network requests.
-----------------------------------------------------------]]

MediaPlayer.Metadata = {}

---
-- Default metadata table name
-- @type String
--
local TableName = "mediaplayer_metadata"
local TableColumns = {
	id = "VARCHAR(48) PRIMARY KEY",
	title = "VARCHAR(128)",
	duration = "INTEGER NOT NULL DEFAULT 0",
	thumbnail = "VARCHAR(512)",
	extra = "VARCHAR(2048)",
	request_count = "INTEGER NOT NULL DEFAULT 1",
	last_request = "INTEGER NOT NULL DEFAULT 0",
	last_updated = "INTEGER NOT NULL DEFAULT 0",
	expired = "BOOLEAN NOT NULL DEFAULT 0",
}

---
-- SQLite table struct
-- @type String
--
local TableStruct = string.format([[
CREATE TABLE %s (
	id				VARCHAR(48) PRIMARY KEY,
	title			VARCHAR(128),
	duration		INTEGER NOT NULL DEFAULT 0,
	thumbnail		VARCHAR(512),
	extra 			VARCHAR(2048),
	request_count	INTEGER NOT NULL DEFAULT 1,
	last_request	INTEGER NOT NULL DEFAULT 0,
	last_updated	INTEGER NOT NULL DEFAULT 0,
	expired			BOOLEAN NOT NULL DEFAULT 0
)]], TableName)

---
-- Maximum cache age before it expires; currently one week in seconds.
-- @type Number
--
local MaxCacheAge = 604800

local function SQLNullableString( value )
	if value == nil or value == "" or value == "nil" then
		return "NULL"
	end

	return sql.SQLStr( tostring( value ) )
end

local function GetExtraJSON( media )
	local extra = media._metadata and media._metadata.extra or {}
	return util.TableToJSON( extra ) or "[]"
end

local function LogQueryError( prefix, query )
	ErrorNoHalt( prefix .. "\n" )
	print( query )
	print( "SQLite Error:", tostring( sql.LastError() ) )
end

local function EnsureMetadataTable()
	if not sql.TableExists( TableName ) then
		Msg( "MediaPlayer.Metadata: Creating `" .. TableName .. "` table...\n" )
		local result = sql.Query( TableStruct )

		if result == false then
			LogQueryError( "MediaPlayer.Metadata: Failed to create metadata table", TableStruct )
		end

		return
	end

	local results = sql.Query( "PRAGMA table_info(" .. sql.SQLStr( TableName ) .. ")" )
	if not istable( results ) then
		LogQueryError( "MediaPlayer.Metadata: Failed to inspect metadata table schema", "PRAGMA table_info(" .. sql.SQLStr( TableName ) .. ")" )
		return
	end

	local existing = {}

	for _, row in ipairs( results ) do
		existing[ row.name ] = true
	end

	for columnName, columnDef in pairs( TableColumns ) do
		if existing[ columnName ] then continue end
		if columnName == "id" then continue end

		local alter = string.format(
			"ALTER TABLE `%s` ADD COLUMN `%s` %s",
			TableName,
			columnName,
			columnDef
		)

		Msg( "MediaPlayer.Metadata: Adding missing `" .. columnName .. "` column...\n" )
		local result = sql.Query( alter )

		if result == false then
			LogQueryError( "MediaPlayer.Metadata: Failed to add missing column `" .. columnName .. "`", alter )
		end
	end
end

---
-- Query the metadata table for the given media object's metadata.
-- If the metadata is older than one week, it is ignored and replaced upon
-- saving.
--
-- @param media		Media service object.
-- @return table	Cached metadata results.
--
function MediaPlayer.Metadata:Query( media )
	local id = media:UniqueID()
	if not id then return end

	local query = ("SELECT * FROM `%s` WHERE id='%s'"):format(TableName, id)

	if MediaPlayer.DEBUG then
		print("MediaPlayer.Metadata.Query")
		print(query)
	end

	local results = sql.QueryRow(query)

	if results then
		local expired = ( tonumber(results.expired) == 1 )

		-- Media metadata has been marked as out-of-date
		if expired then
			return nil
		end

		local lastupdated = tonumber( results.last_updated )
		local timediff = os.time() - lastupdated

		if timediff > MaxCacheAge then

			-- Set metadata entry as expired
			query = "UPDATE `%s` SET expired=1 WHERE id='%s'"
			query = query:format( TableName, id )

			if MediaPlayer.DEBUG then
				print("MediaPlayer.Metadata.Query: Setting entry as expired")
				print(query)
			end

			sql.Query( query )

			return nil

		else
			return results
		end
	elseif results == false then
		LogQueryError( "MediaPlayer.Metadata.Query: There was an error executing the SQL query", query )
	end

	return nil
end

---
-- Save or update the given media object into the metadata table.
--
-- @param media		Media service object.
-- @return table	SQL query results.
--
function MediaPlayer.Metadata:Save( media )
	local id = media:UniqueID()
	if not id then return end
	local title = media:Title() or "Unknown"
	local duration = tonumber( media:Duration() ) or 0
	local thumbnail = media:Thumbnail()
	local extra = GetExtraJSON( media )

	local query = ("SELECT expired FROM `%s` WHERE id=%s"):format(TableName, sql.SQLStr( id ))
	local results = sql.Query(query)

	if istable(results) then -- update

		if MediaPlayer.DEBUG then
			print("MediaPlayer.Metadata.Save Results:")
			PrintTable(results)
		end

		results = results[1]

		local expired = ( tonumber(results.expired) == 1 )

		if expired then

			-- Update possible new metadata
			query = "UPDATE `%s` SET request_count=request_count+1, title=%s, duration=%s, thumbnail=%s, extra=%s, last_request=%s, last_updated=%s, expired=0 WHERE id='%s'"
			query = query:format( TableName,
						sql.SQLStr( title ),
						duration,
						SQLNullableString( thumbnail ),
						sql.SQLStr( extra ),
						os.time(),
						os.time(),
						id )

		else

			query = "UPDATE `%s` SET request_count=request_count+1, last_request=%s WHERE id='%s'"
			query = query:format( TableName, os.time(), id )

		end

	else -- insert

		query = string.format( "INSERT INTO `%s` ", TableName ) ..
			"(id,title,duration,thumbnail,extra,last_request,last_updated) VALUES (" ..
			string.format( "%s,", sql.SQLStr( id ) ) ..
			string.format( "%s,", sql.SQLStr( title ) ) ..
			string.format( "%s,", duration ) ..
			string.format( "%s,", SQLNullableString( thumbnail ) ) ..
			string.format( "%s,", sql.SQLStr( extra ) ) ..
			string.format( "%d,", os.time() ) ..
			string.format( "%d)", os.time() )

	end

	if MediaPlayer.DEBUG then
		print("MediaPlayer.Metadata.Save")
		print(query)
	end

	results = sql.Query(query)

	if results == false then
		LogQueryError( "MediaPlayer.Metadata.Save: There was an error executing the SQL query", query )
	end

	return results
end

EnsureMetadataTable()

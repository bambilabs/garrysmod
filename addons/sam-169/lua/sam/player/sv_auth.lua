if SAM_LOADED then return end

local sam, SQL = sam, sam.SQL
local os_time = os.time

local auth_player = function(data, ply)
	if not ply:IsValid() then return end
	if ply:sam_get_nwvar("is_authed") then return end

	-- mysql returns a table with results for each query that ran, even if no results were returned for that query
	if SQL.IsMySQL() then
		data = data[3][1]
	else
		data = data[1]
	end

	local steamid = ply:SteamID()

	local rank = data.rank
	local expiry_date = tonumber(data.expiry_date)
	local play_time = tonumber(data.play_time)
	local is_first_join = data.is_first_join == 1

	ply:SetUserGroup(rank)
	ply:sam_start_rank_timer(expiry_date)

	ply:sam_set_nwvar("join_time", os.time())
	ply:sam_set_nwvar("play_time", play_time)
	ply:sam_set_nwvar("is_authed", true)
	ply:sam_set_nwvar("is_being_authed", nil)

	hook.Call("SAM.AuthedPlayer", nil, ply, steamid, is_first_join)

	if ply.sam_reliable_net_ready then
		ply.sam_sent_hook_call = true
		sam.client_hook_call("SAM.AuthedPlayer", ply, steamid, is_first_join)
	else
		ply.sam_is_first_join_hook = is_first_join
	end
end

hook.Add("SAM.PlayerNetReady", "SAM.AuthPlayerHook", function(ply)
	if ply.sam_sent_hook_call then
		ply.sam_sent_hook_call = nil
		return
	end

	if ply:sam_get_nwvar("is_authed") then
		sam.client_hook_call("SAM.AuthedPlayer", ply, ply:SteamID(), ply.sam_is_first_join_hook)
		ply.sam_is_first_join_hook = nil
	end
end)

do
	local insert_query_inserts = {
		steamid = "",
		name = "",
		rank = "user",
		expiry_date = 0,
		first_join = 0,
		last_join = 0,
		play_time = 0
	}

	hook.Add("PlayerInitialSpawn", "SAM.AuthPlayer", function(ply)
		if ply:sam_get_nwvar("is_authed") or ply:sam_get_nwvar("is_being_authed") then return end
		ply:sam_set_nwvar("is_being_authed", true)

		local time = os_time()
		local steamid = ply:SteamID()

		insert_query_inserts["steamid"] = steamid
		insert_query_inserts["name"] = ply:Name()
		insert_query_inserts["first_join"] = time
		insert_query_inserts["last_join"] = time
		local insert_query = SQL.InsertOrUpdateQuery(
			"sam_players", -- table
			"steamid",	-- primary key
			insert_query_inserts, -- inserts columns
			{"name", "last_join"} -- update columns
		)

		local select_query = [[
			SELECT
				`rank`,
				`expiry_date`,
				`play_time`,
				CASE
					WHEN `first_join` = `last_join` THEN
						true
					ELSE
						false
				END as is_first_join
			FROM
				`sam_players`
			WHERE
				`steamid` =]]

		local insert_select_query = {
			SQL.IsMySQL() and "START TRANSACTION;" or "BEGIN TRANSACTION;",
			insert_query,
			select_query,
			SQL.Escape(steamid),
			";",
			"COMMIT;"
		}

		local query = SQL.Query(table.concat(insert_select_query, "", 1, 6), auth_player, nil, ply)
		query.is_multi_query = true
	end)
end
sam.player.auth = auth_player

hook.Add("SAM.AuthedPlayer", "SetSuperadminToListenServer", function(ply)
	if game.SinglePlayer() or ply:IsListenServerHost() then
		ply:sam_set_rank("superadmin")
	end
end)

hook.Add("SAM.AuthedPlayer", "CheckIfFullyAuthenticated", function(ply)
	if ply:IsBot() then return end
	if game.SinglePlayer() or ply:IsListenServerHost() then return end

	if ply.IsFullyAuthenticated and not ply:IsFullyAuthenticated() then
		timer.Simple(25, function()
			if not IsValid(ply) then return end
			if not ply.IsFullyAuthenticated or ply:IsFullyAuthenticated() then return end

			ply:Kick("Your SteamID wasn't fully authenticated, try rejoining the server.")
		end)
	end
end)

do
	local format = string.format
	local floor = math.floor
	local SysTime = SysTime
	local last_save = SysTime()

	local save_play_time = function(ply)
		if not ply:sam_get_nwvar("is_authed") then return end

		local query = format([[
			UPDATE
				`sam_players`
			SET
				`play_time` = %u
			WHERE
				`steamid` = '%s'
		]], floor(ply:sam_get_play_time()), ply:SteamID())
		SQL.Query(query)
	end

	hook.Add("Think", "SAM.Player.SaveTimes", function()
		if SysTime() - last_save < 60 then return end

		SQL.Begin()
		local players = player.GetHumans()
		for i = 1, #players do
			save_play_time(players[i])
		end
		SQL.Commit()

		sam.hook_call("SAM.UpdatedPlayTimes")

		last_save = SysTime()
	end)

	hook.Add("PlayerDisconnected", "SAM.Player.SaveTime", save_play_time)
end

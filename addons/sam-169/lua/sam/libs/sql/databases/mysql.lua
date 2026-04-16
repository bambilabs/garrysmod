local _SQL = sam.SQL
local _error = _SQL.Error
local traceback = debug.traceback

local _mysqloo, database = nil, nil

local SQL = {}

function SQL.Connect(callback, failed_callback, config)
	if database then
		local status = database:status()
		if status == _mysqloo.DATABASE_CONNECTING or status == _mysqloo.DATABASE_CONNECTED then
			return true
		end
	end

	_SQL.SetConnected(false)

	require("mysqloo")

	if not mysqloo then
		_error("mysqloo module doesn't exist, get it from https://github.com/FredyH/MySQLOO")
		return false
	end

	_mysqloo = mysqloo

	database = _mysqloo.connect(
		config.Host,
		config.Username,
		config.Password,
		config.Database,
		config.Port
	)

	function database.onConnected()
		callback()
	end

	function database.onConnectionFailed(_, error_text)
		failed_callback(error_text)
	end

	database:connect()
	timer.Simple(0, function()
		RunConsoleCommand("sv_hibernate_think", "1")
		database:wait()
	end)
	-- database:wait()

	return true
end

--
--
--
local transaction

local add_transaction = function(query)
	transaction:addQuery(database:query(query))
end

function SQL.Begin()
	transaction = database:createTransaction()
	return add_transaction
end

local transaction_onError = function(tr, error_text)
	_error("Transaction error: " .. error_text, tr.SQL_traceback)
end

function SQL.Commit(callback, should_wait)
	transaction.SQL_traceback = traceback("", 2)

	transaction.onSuccess = callback
	transaction.onError = transaction_onError

	transaction:start()
	if should_wait == true then
		transaction:wait()
	end

	transaction = nil
end
--
--
--

--
--
--
local on_query_success = function(query, data)
	-- multiple queries ran
	if query.is_multi_query then
		local callback_data = {}
		while query:hasMoreResults()  do
			callback_data[#callback_data + 1] = query:getData()
			query:getNextResults()
		end

		query.SQL_callback(callback_data, query.SQL_callback_obj)

		return
	end

	if query.SQL_first_row then
		data = data[1]
	end
	query.SQL_callback(data, query.SQL_callback_obj)
end

local on_query_fail = function(query, error_text)
	local status = database:status()

	-- https://github.com/Kamshak/LibK/blob/master/lua/libk/server/sv_libk_database.lua#L129
	if status == _mysqloo.DATABASE_NOT_CONNECTED or status == _mysqloo.DATABASE_CONNECTING or error_text:find("Lost connection to MySQL server during query", 1, true) then
		_SQL.SetConnected(false)
		SQL.Query(query.SQL_query_string, query.SQL_callback, query.SQL_first_row, query.SQL_callback_obj)
	else
		-- 3c85ba4002fe3cf1743af585937768e4cab3fc2808d453f5ffd8b3f9ddab0b92
		_error("Query error: " .. error_text, query.SQL_traceback)
	end
end

function SQL.Query(query, callback, first_row, callback_obj)
	local status = database:status()
	if status == _mysqloo.DATABASE_NOT_CONNECTED or status == _mysqloo.DATABASE_INTERNAL_ERROR then
		_SQL.Connect()
		database:wait()
	end

	local query_string = query
	query = database:query(query)

	query.SQL_query_string = query_string

	if callback then
		query.onSuccess = on_query_success
		query.SQL_callback = callback
		query.SQL_first_row = first_row
		query.SQL_callback_obj = callback_obj
	end

	query.SQL_traceback = traceback("", 2)
	query.onError = on_query_fail

	query:start()

	return query
end

-- local prepared_set_values = function(prepared_query, values)
--	 for i = 1, #values do
--		 local v = values[i]
--		 local value_type = type(v)
--		 if value_type == "string" then
--			 prepared_query:setString(i, v)
--		 elseif value_type == "number" then
--			 prepared_query:setNumber(i, v)
--		 else
--			 error(
--				 string.format(
--					 "%s invalid type '%s' was passed to escape '%s'",
--					 "(" .. SQL.GetAddonName() .. " | MySQL)",
--					 value_type,
--					 v
--				 )
--			 )
--		 end
--	 end
-- end

-- function SQL.Prepare(query, callback, first_row, callback_obj)
--	 local prepared_query = database:prepare(query)
--	 prepared_query.SetValues = prepared_set_values

--	 if callback then
--		 prepared_query.onSuccess = on_query_success
--		 prepared_query.SQL_callback = callback
--		 prepared_query.SQL_first_row = first_row
--		 prepared_query.SQL_callback_obj = callback_obj
--	 end

--	 prepared_query.SQL_traceback = traceback("", 2)
--	 prepared_query.onError = on_query_fail

--	 return prepared_query
-- end

--
--
--

function SQL.EscapeString(value, no_quotes)
	if no_quotes then
		return database:escape(value)
	else
		return "'" .. database:escape(value) .. "'"
	end
end

function SQL.TableExistsQuery(name)
	return "SHOW TABLES LIKE " .. SQL.EscapeString(name) .. "; SHOW TABLES LIKE " .. SQL.EscapeString(name)
end

do
	local table_concat = table.concat

	local query = {}
	local query_count = 0

	local add_to_query = function(str)
		query_count = query_count + 1
		query[query_count] = str
	end

	-- add callbacks for

	--[[
	local query = SQL.InsertOrUpdateQuery(
		"sam_players", -- table
		"steamid",	-- primary key
		{
			steamid = ply:SteamID(),
			name = ply:Name(),
			rank = "user",
			expiry_date = 0,
			first_join = time,
			last_join = time,
			play_time = 0
		}, -- inserts columns
		{"name", "last_join"} -- update columns
	)
	]]
	function SQL.InsertOrUpdateQuery(tbl, primary_key, inserts, updates)
		query[1] = "INSERT INTO`"
		query[2] = tbl
		query[3] = "`("
		query_count = 3

		local values = {}
		-- using add_to_query
		for column, value in pairs(inserts) do
			add_to_query("`")
			add_to_query(column)
			add_to_query("`")
			add_to_query(",")
			values[#values + 1] = _SQL.Escape(value)
		end
		query_count = query_count - 1

		add_to_query(")VALUES(")

		for i = 1, #values do
			add_to_query(values[i])
			add_to_query(",")
		end
		query_count = query_count - 1

		add_to_query(")ON DUPLICATE KEY UPDATE")

		for i = 1, #updates do
			add_to_query("`")
			add_to_query(updates[i])
			add_to_query("`=")
			add_to_query("VALUES(`")
			add_to_query(updates[i])
			add_to_query("`)")
			add_to_query(",")
		end
		query[query_count] = ";"

		return table_concat(query, "", 1, query_count)
	end
end

return SQL

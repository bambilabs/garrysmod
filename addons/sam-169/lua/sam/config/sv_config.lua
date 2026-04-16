if SAM_LOADED then return end

local sam = sam
local SQL = sam.SQL
local config = sam.config
local sfs = sam.sfs

local encoders = sfs.Encoder.encoders
local encode = sfs.encode
local decode = sfs.decode
local type = sam.type
local to_hex = sam.to_hex

local _config = {}

function config.sync()
	sam.set_global("Config", _config, true)
end

function config.set(key, value, force)
	if not sam.isstring(key) then
		error("invalid setting name")
	end

	if not sfs.Encoder.get_encoder_impl(value) then
		error("not supported value type")
	end

	local old = _config[key]
	if not force and value == old then return end

	SQL.FQuery([[
		REPLACE INTO
			`sam_config`(
				`key`,
				`value`
			)
		VALUES
			({1}, X{2})
	]], {key, to_hex(encode(value))})

	_config[key] = value
	config.sync()
	sam.hook_call("SAM.UpdatedConfig", key, value, old)
end

function config.get(key, default)
	local value = _config[key]
	if value ~= nil then
		return value
	end
	return default
end

config.sync()

hook.Add("SAM.DatabaseLoaded", "LoadConfig", function()
	SQL.Query([[
		SELECT
			`key`,
			HEX(`value`) AS `value`
		FROM
			`sam_config`
	]], function(sam_config)
		for _, v in ipairs(sam_config) do
			local value, err, err2 = decode(sam.from_hex(v.value))
			if err == nil then
				_config[v.key] = value
			else
				print("------")
				sam.print("Failed to decode config \"" .. v.key .. "\"" .. " skipping, please report immediately!")
				sam.print("Error: " .. err .. " " .. err2)
				print("------")
			end
		end

		config.loaded = true
		config.sync()
		hook.Call("SAM.LoadedConfig", nil, _config)
	end):wait()
end)

sam.netstream.Hook("Config.Set", function(ply, key, value)
	config.set(key, value)

	value = tostring(value)

	if value == "" then
		sam.player.send_message(nil, "{A} changed {S Blue} setting to: {S_2 Red}", {
			A = ply, S = key, S_2 = "none"
		})
	else
		sam.player.send_message(nil, "{A} changed {S Blue} setting to: {S_2}", {
			A = ply, S = key, S_2 = value
		})
	end
end, function(ply)
	return ply:HasPermission("manage_config")
end)

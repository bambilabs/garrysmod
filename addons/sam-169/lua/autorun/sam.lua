if SAM_LOADED then return end

local version = tonumber("169") or 169

sam = {}
sam.config = {}
sam.language = {}
sam.player = {}
sam.ranks = {}
sam.permissions = {}
sam.author = "Srlion"
sam.version = version

function sam.print(...)
	MsgC(
		Color(236, 240, 241), "(",
		Color(244, 67, 54), "SAM",
		Color(236, 240, 241), ") ",
		Color(236, 240, 241), ...
	) Msg("\n")
end

local FAILED = false
do
	local types = {
		sv_ = SERVER and include or function() end,
		cl_ = SERVER and AddCSLuaFile or include,
		sh_ = function(name)
			if SERVER then
				AddCSLuaFile(name)
			end
			return include(name)
		end
	}

	sam.load_file = function(name, type)
		if FAILED then return end

		if type and not type:EndsWith("_") then
			type = type .. "_"
		end

		local func = types[type] or types[name:GetFileFromFilename():sub(1, 3)] or types["sh_"]
		if func then
			local rets = {func(name)}
			if rets[1] == false then
				FAILED = true
				sam.print("Failed to load!")
			end
			return unpack(rets)
		end
	end
end
local load_file = sam.load_file

sam.print("Loading...")

load_file("sam/libs/sh_types.lua")

do
	local IsValid = IsValid
	local OLD_Player = Player

	-- this is because sam sends players' ids to the client, so if a player disconnects while net message is being sent
	-- the client will not know the player's name
	if CLIENT then
		local players = {}

		local Name = function(s)
			return s.name
		end

		local not_valid = function() return false end

		Player = function(id)
			local ply = OLD_Player(id)

			if not IsValid(ply) then
				local name = players[id]
				if name then
					return {
						name = name,
						Name = Name,
						IsValid = not_valid
					}
				end
			end

			return ply
		end

		hook.Add("OnEntityCreated", "SAM.GetPlayerName", function(ent)
			if ent:IsPlayer() and ent:IsValid() then
				ent.sam_userid = ent:UserID() -- userid is -1 in EntityRemoved?????
			end
		end)

		hook.Add("EntityRemoved", "SAM.GetPlayerName", function(ent)
			if not ent:IsPlayer() then return end

			local id = ent.sam_userid
			if not id then return end

			players[id] = ent:Name()

			timer.Simple(60, function()
				if not IsValid(ent) then
					players[id] = nil
				end
			end)
		end)
	end

	sam.sfs_old = sam.load_file("sam/libs/sh_sfs_old.lua", "sh_")
	sam.sfs = sam.load_file("sam/libs/sh_sfs.lua", "sh_")

	local Encoder = sam.sfs.Encoder
	local write_byte = Encoder.write_byte

	local CONSOLE_TYPE_ID; CONSOLE_TYPE_ID = sam.sfs.add_custom_type("console", function(buf)
		write_byte(buf, CONSOLE_TYPE_ID)
	end, function(ctx)
		ctx[1] = ctx[1] + 1
		return sam.console
	end)

	sam.sfs.set_type_function(sam.type)

	Player = OLD_Player
end

load_file("sam/libs/sh_netstream.lua")
load_file("sam/libs/sh_async_netstream.lua")
load_file("sam/libs/sh_globals.lua")
load_file("sam/libs/sql/sv_init.lua")
sam.Promise = load_file("sam/libs/sh_promises.lua")

load_file("sam/sh_colors.lua")

load_file("sam/sh_util.lua")
load_file("sam/sh_lang.lua")
load_file("sam/sv_sql.lua")
load_file("sam/sh_permissions.lua")

load_file("sam/ranks/sh_ranks.lua")
load_file("sam/ranks/sv_ranks.lua")

load_file("sam/config/sh_config.lua")
load_file("sam/config/sv_config.lua")
load_file("sam/config/cl_config.lua")

load_file("sam/player/sh_player.lua")
load_file("sam/player/sh_nw_vars.lua")
load_file("sam/player/sv_player.lua")
load_file("sam/player/cl_player.lua")
load_file("sam/player/sv_ranks.lua")
load_file("sam/player/sv_auth.lua")
load_file("sam/player/sv_bans.lua")

load_file("sam/command/sh_command.lua")
load_file("sam/command/sv_command.lua")
load_file("sam/command/cl_command.lua")

for _, f in ipairs(file.Find("sam/command/arguments/*.lua", "LUA")) do
	load_file("sam/command/arguments/" .. f, "sh")
end

load_file("sam/sh_restrictions.lua")

load_file("sam/menu/sh_init.lua")
load_file("sam/menu/cl_init.lua")

load_file("sam/sh_motd.lua")

local modules = file.Find("sam/modules/*.lua", "LUA")
for _, module in ipairs(modules) do
	load_file("sam/modules/" .. module)
end

load_file("sam/reports/cl_reports.lua")
load_file("sam/reports/sv_reports.lua")

do
	if SERVER then
		hook.Add("SAM.LoadedConfig", "SAM.AdvertsMain", function(config)
			if not config.Adverts or not istable(config.Adverts) then
				sam.config.set("Adverts", {})
			end
		end)
	end
	load_file("sam/cl_adverts.lua")
end

if not FAILED then
	sam.print("Loaded!")
end

if SERVER then
	local path = "sam/importers/"

	concommand.Add("sam_import", function(ply, _, args)
		if IsValid(ply) then return end

		local admin_mod = args[1]
		if not admin_mod then
			sam.print("You need to provide an admin mod to import!")
			return
		end

		if not file.Exists(path .. admin_mod, "LUA") then
			sam.print("There is no importer for '" .. admin_mod .. "'")
			return
		end

		CompileFile(path .. admin_mod .. "/main.lua")()
	end, nil, nil, FCVAR_PROTECTED)
end

SAM_LOADED = true

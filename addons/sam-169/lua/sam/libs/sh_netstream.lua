if SAM_LOADED then return end

--[[
	NetStream - 2.0.1
	https://github.com/alexgrist/NetStream/blob/master/netstream2.lua

	Alexander Grist-Hucker
	http://www.revotech.org
]]--

--[[
	if SERVER then
		netstream.Hook("Hi", function(ply, ...) -- Third argument is called to check if the player has permission to send the net message before decoding
			print(...)
		end, function(ply)
			if not ply:IsAdmin() then
				return false
			end
		end)
		-- OR
		netstream.Hook("Hi", function(ply, ...)
			print(...)
		end)
		netstream.Start(Entity(1), "Hi", "a", 1, {}, true, false, nil, "!") -- First argument player or table of players or any other argument to send to all players
		netstream.Start({Entity(1), Entity(2)}, "Hi", "a", 1, {}, true, false, nil, "!")
		netstream.Start(nil, "Hi", "a", 1, {}, true, false, nil, "!")
	end
	if CLIENT then
		netstream.Hook("Hi", function(...)
			print(...)
		end)
		netstream.Start("Hi", "a", 1, {}, true, false, nil, "!")
	end
]]--

-- Config

local addonName = "SAM"
local mainTable = sam -- _G.netstream = netstream

local sfs = sam.sfs
local encode = sfs.encode
local decode = sfs.decode

--

local type = sam.type
local unpack = unpack

local net = net
local compress = util.Compress
local decompress = util.Decompress

local netStreamSend = addonName .. ".NetStreamDS.Sending"

local netstream = {}
if istable(mainTable) then
	mainTable.netstream = netstream
end

local checks = {}
local receivers = {}

if SERVER then
	util.AddNetworkString(netStreamSend)

	local player_GetAll = player.GetAll
	function netstream.Start(ply, name, ...)
		if #name > 31 then
			error("netstream.Start name too long")
		end

		local ply_type = type(ply)
		if ply_type ~= "Player" and ply_type ~= "table" then
			ply = player_GetAll()
		end

		local array_length = select("#", ...)
		local encoded_data = encode({name, array_length, ...})

		net.Start(netStreamSend)
			net.WriteBool(false)
			net.WriteData(encoded_data)
		net.Send(ply)
	end

	function netstream.StartCompressed(ply, name, ...)
		if #name > 31 then
			error("netstream.Start name too long")
		end

		local ply_type = type(ply)
		if ply_type ~= "Player" and ply_type ~= "table" then
			ply = player_GetAll()
		end

		local array_length = select("#", ...)
		local encoded_data = encode({name, array_length, ...})

		local compressed_data = compress(encoded_data)

		net.Start(netStreamSend)
			net.WriteBool(true)
			net.WriteData(compressed_data)
		net.Send(ply)
	end

	function netstream.Hook(name, callback, check)
		if #name > 31 then
			error("netstream.Hook name too long")
		end

		receivers[name] = callback
		if type(check) == "function" then
			checks[name] = check
		end
	end

	net.Receive(netStreamSend, function(_, ply)
		local name = net.ReadString()

		local callback = receivers[name]
		if not callback then return end

		local length = net.ReadUInt(16)

		local check = checks[name]
		if check and check(ply, length) == false then return end

		local binary_data = net.ReadData(length)

		local decoded_data = decode(binary_data)
		if type(decoded_data) ~= "table" then return end

		local array_length = decoded_data[1]
		if type(array_length) ~= "number" then return end
		if array_length < 0 then return end

		callback(ply, unpack(decoded_data, 2, array_length + 1))
	end)
else
	checks = nil

	function netstream.Start(name, ...)
		if #name > 31 then
			error("netstream.Start name too long")
		end

		local array_length = select("#", ...)
		local encoded_data = encode({array_length, ...})

		local length = #encoded_data

		net.Start(netStreamSend)
			net.WriteString(name)
			net.WriteUInt(length, 16)
			net.WriteData(encoded_data, length)
		net.SendToServer()
	end

	function netstream.Hook(name, callback)
		receivers[name] = callback
	end

	net.Receive(netStreamSend, function(len)
		local compressed = net.ReadBool()
		local binary_data = net.ReadData((len - 1) / 8)

		if compressed then
			binary_data = decompress(binary_data)
			if not binary_data then return end
		end

		local decoded_data, err, err2 = decode(binary_data)
		if err ~= nil then
			sam.print("NetStream error: " .. err .. err2)
			return
		end

		local name = decoded_data[1]

		local callback = receivers[name]
		if not callback then return end

		callback(unpack(decoded_data, 3, decoded_data[2] + 2))
	end)
end

return netstream

---------------------------------
local LastThink = 0
local InQuery = false

local function PromotePrivateServer(authHex)
    if not authHex or authHex == "" then return end

    local ips = GTowerServers:PlayerListToIDs(authHex)

    if gateKeep and gateKeep.AuthorizedPlayers then
        gateKeep.AuthorizedPlayers = {}
        for _, ip in ipairs(ips) do
            gateKeep.AuthorizedPlayers[ip] = true
        end
    end

    GTowerServers:SetState(3)
    GTowerServers:UpdateDatabase()

    if gateKeep and gateKeep.ResetEmptyReadyServer then
        timer.Simple(45, function()
            gateKeep:ResetEmptyReadyServer()
        end)
    end
end

local function GoMapResult(res, status, err)
    InQuery = false

    if status != QUERY_SUCCESS then
        return
    end

    if table.Count(res) == 0 then
        return
    end

    local targetMap = string.lower(res[1].authplayers or "")
    local authHex = res[1].gomap or ""

    file.Write("authedusers" .. tostring(GTowerServers:GetServerId()) .. ".txt", authHex)
    PromotePrivateServer(authHex)

    Database.Query("DELETE FROM `gm_gomap` WHERE `serverid` = " .. GTowerServers:GetServerId() .. ";")

    if targetMap != "" and string.lower(game.GetMap()) != targetMap then
        timer.Simple(0.25, function()
            hook.Call("LastChanceMapChange", GAMEMODE, targetMap)
            RunConsoleCommand("gmt_forcelevel", targetMap)
        end)
    end
end

local function StartBufferGoMapWatcher()
    if hook.GetTable().Think and hook.GetTable().Think.BufferGoMap then
        return
    end

    hook.Add("Think", "BufferGoMap", function()
        local Gamemode = GTowerServers:Self()

        if not Gamemode or Gamemode.Private != true then
            hook.Remove("Think", "BufferGoMap")
            return
        end

        if not Database or not Database.IsConnected or not Database.IsConnected() then
            return
        end

        if GTowerServers:GetState() != 1 or InQuery == true then
            return
        end

        if LastThink > CurTime() then
            return
        end

        LastThink = CurTime() + 0.5
        InQuery = true

        Database.Query(
            "SELECT authplayers, HEX(`gomap`) as `gomap` FROM `gm_gomap` WHERE `serverid` = " .. GTowerServers:GetServerId() .. ";",
            GoMapResult
        )
    end)
end

hook.Add("DatabaseConnected", "MultiServerBufferMap", StartBufferGoMapWatcher)

timer.Simple(1, function()
    if SERVER and Database and Database.IsConnected and Database.IsConnected() then
        StartBufferGoMapWatcher()
    end
end)

function GTowerServers:GetRandomMap()

    local Gamemode = GTowerServers:Self()

    if Gamemode && Gamemode.Maps then
        return Gamemode.Maps[ math.random( 1, #Gamemode.Maps ) ]
    end

end

concommand.Add("gmt_mapbufferinquery", function( ply, cmd, args )

    if ply == NULL then
        Msg( "Query in : " , InQuery , "\n")
    end

end )

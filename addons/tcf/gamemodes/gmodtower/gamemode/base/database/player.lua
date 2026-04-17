
module( "Database", package.seeall )

LastSave = LastSave or 0
SaveFrequency = 60 * ( IsLobby and 2 or 5 )

local PendingPlayerLoads = {}

local function EnsurePlayerDefaults( ply )
    if not IsValid( ply ) then return end
    if ply._DatabaseDefaultsApplied then return end

    Columns.SetPlayerDefaults( ply )
    ply._DatabaseDefaultsApplied = true
end

local function QueuePlayerLoad( ply )
    if not IsValid( ply ) then return end
    if ply:ProfileLoaded() then return end

    PendingPlayerLoads[ ply ] = true
end

local function ClearPendingPlayerLoad( ply )
    PendingPlayerLoads[ ply ] = nil

    if IsValid( ply ) then
        ply._DatabaseLoadPending = false
    end
end

local function IsDisconnectedError( err )
    return string.find( tostring( err or "" ), "Database disconnected.", 1, true ) != nil
end

function ValidPlayer( ply )

    if not IsValid( ply ) then
        return false, "Player Invalid"
    end

    if ply:IsBot() then
        return false, "Bot"
    end

    return true, nil

end

function InsertPlayer( ply, callback )
    callback = callback or EmptyFunction

    local valid, err = ValidPlayer( ply )
    if valid != true then
        callback( false, nil, err or "Unknown" )
        return
    end

    if not Database.IsConnected() then
        callback( false, ply, "Database disconnected." )
        return
    end

    local id = ply:DatabaseID()
    local steamid = ply:SteamID() or ""
    local nickname = ply:Nick() or ""
    local ip = ply:DatabaseIP() or ""
    local steamid_query = Database.Escape( steamid, true )
    local name_query = Database.Escape( nickname, true )
    local ip_query = Database.Escape( ip, true )

    // hardcoding this for now, sorry
    local insert_query = "INSERT INTO `gm_users` (id, steamid, name, ip) VALUES (" .. id .. ", " .. steamid_query .. ", " .. name_query .. ", " .. ip_query .. ") ON DUPLICATE KEY UPDATE name = " .. name_query .. ", ip = " .. ip_query .. ";"

    // store these since the player could go invalid before the query is done
    local name = nickname .. " [" .. steamid .. "]"

    Query( insert_query, function( res, status, err )
        
        if status != QUERY_SUCCESS then
            LogPrint( Format( "FAILED TO INSERT %s!", name ), color_red, "Database" )
            if callback then
                callback( false, ply, "Failed to insert! (" .. tostring( err ) .. ")" )
            end
            return
        end

        if DEBUG then
            LogPrint( Format( "Successfully inserted %s.", name ), nil, "Database" )
        end

        if callback then
            callback( true, ply, nil )
        end

    end )

end

function SavePlayer( ply, columns, callback )

    callback = callback or EmptyFunction

    local valid, err = ValidPlayer( ply )
    if valid != true then
        callback( false, nil, err or "Unknown" )
        return
    end
    
    if not ply:ProfileLoaded() then
        LogPrint( "Tried to save data before it was loaded! " .. tostring( ply ), color_red, "Database" )

        callback( false, ply, "Player data hasn't been loaded yet." )
        return
    end
    
    if ply._IsSaving then
        LogPrint( "Tried to save data while already saving! " .. tostring( ply ), color_red, "Database" )

        callback( false, ply, "Player data is already saving." )
        return
    end

    if not Database.IsConnected() then
        callback( false, ply, "Database disconnected." )
        return
    end

    local data = Columns.GetPlayer( ply, columns )
    if table.IsEmpty(data) then
        callback( false, ply, "Failed to get player columns. (" .. table.concat( columns or {"all"}, "," ) .. ")" )
        return
    end

    // store these since the player could go invalid before the query is done
    local id = ply:DatabaseID()
    local steamid = ply:SteamID()
    local name = ply:Nick() .. " [" .. steamid .. "]"
    local query_string = "UPDATE `gm_users` SET " .. Columns.CreateQuery( data ) .. " WHERE id ='" .. id .. "';"
    ply._IsSaving = true

    Query( query_string, function( res, status, err )

        if IsValid( ply ) then
            ply._IsSaving = false
        end
        
        if status != QUERY_SUCCESS then
            LogPrint( Format( "FAILED TO SAVE %s's DATA!", name ), color_red, "Database" )
            if callback then
                callback( false, ply, "Failed to save data! (" .. tostring( err ) .. ")" )
            end
            return
        end

        if DEBUG then
            LogPrint( Format( "Successfully saved %s's data.", name ), nil, "Database" )
        end

        if callback then
            callback( true, ply, nil )
        end

    end )

end

hook.Add( "PlayerDisconnected", "DatabaseSave", function( ply )
    ClearPendingPlayerLoad( ply )

    SavePlayer( ply )

    hook.Run( "DatabasePostPlayerDisconnect", ply )

end )

function SaveAll( columns )

    for _, ply in ipairs( player.GetHumans() ) do

        if not ply:ProfileLoaded() then continue end
        
        SavePlayer( ply, columns )

    end

    if DEBUG then
        LogPrint( "Saved all player data.", nil, "Database" )
    end

end

function FetchPlayerByID( id, columns, callback )
    if not Database.IsConnected() then
        if callback then
            callback( false, id, "Database disconnected." )
        end

        return
    end
    
    local query = "SELECT " .. Columns.SelectQuery(columns) .. " FROM `gm_users` WHERE id = " .. id .. ";"

    Query( query, function( res, status, err )

        if not callback then return end
        
        if status != QUERY_SUCCESS then
            callback( false, id, "Failed to execute select query. (" .. tostring( err ) .. ")" )
            return
        end

        if table.Count( res ) <= 0 or not res[1] then
            callback( false, id, "Not found in database." )
            return
        end

        callback( true, id, res[1] )

    end )

end

function FetchPlayer( ply, columns, callback )
    callback = callback or EmptyFunction

    local valid, err = ValidPlayer( ply )
    if valid != true then
        callback( false, nil, err or "Unknown" )
        return
    end

    FetchPlayerByID( ply:DatabaseID(), columns, function( status, id, data )

        if not IsValid( ply ) then callback( false, nil, "Player Invalid" ) return end

        callback( status, ply, data )

    end )

end

local function StartPlayerDataLoad( ply )
    if not IsValid( ply ) then return end
    if ply:ProfileLoaded() or ply._DatabaseLoadPending then return end

    if not Database.IsConnected() then
        QueuePlayerLoad( ply )
        return
    end

    ClearPendingPlayerLoad( ply )
    ply._DatabaseLoadPending = true

    InsertPlayer( ply, function( status, _, err )
    
        if status != true then
            if IsDisconnectedError( err ) then
                QueuePlayerLoad( ply )
            end

            ClearPendingPlayerLoad( ply )
            return
        end

        if not IsValid( ply ) then
            ClearPendingPlayerLoad( ply )
            return
        end

        FetchPlayer( ply, nil, function( status, _, data )

            if status != true then
                if IsDisconnectedError( data ) then
                    QueuePlayerLoad( ply )
                end

                ClearPendingPlayerLoad( ply )
                return
            end
    
            // can never have enough isvalid checks
            if not IsValid( ply ) then
                ClearPendingPlayerLoad( ply )
                return
            end

            // could have something better for this, but whateva
            if not tonumber( data.time ) then
                ply._NewPlayer = true
            end
    
            local success = Columns.ApplytoPlayer( ply, data )
            if success != true then
                LogPrint( "Failed to apply data to player " .. tostring( ply ) .. "! (" .. table.concat( table.GetKeys(data) or {}, "," ) .. ")", color_red, "Database" )
                ClearPendingPlayerLoad( ply )
                return
            end
    
            ply._DataLoaded = true
            ClearPendingPlayerLoad( ply )
        
            hook.Run( "PostPlayerDataLoaded", ply )

            if DEBUG then
                LogPrint( Format( "Successfully loaded %s's data.", ply:GetName() ), nil, "Database" )
            end
    
        end )
    

    end )

end

local function LoadPlayerData( ply )
    EnsurePlayerDefaults( ply )
    StartPlayerDataLoad( ply )
end

local function LoadQueuedPlayerData()
    if not Database.IsConnected() then return end

    for ply in pairs( PendingPlayerLoads ) do
        if not IsValid( ply ) then
            PendingPlayerLoads[ ply ] = nil
            continue
        end

        StartPlayerDataLoad( ply )
    end
end

hook.Add( "PlayerAuthed", "FetchData", LoadPlayerData )
hook.Add( "DatabaseConnected", "FetchQueuedData", LoadQueuedPlayerData )

local function SaveThink()

    if player.GetCount() < 1 then return end
    if LastSave + SaveFrequency >= CurTime() then return end

    LastSave = CurTime()

    LogPrint( "Saving all players.", nil, "Database" )
    SaveAll()

end

hook.Add( "Think", "DatabaseSave", SaveThink )

/*hook.Add( "DatabaseOnPlayerFetched", "ApplyData", function( status, id, data )

    if status != true then
        print( "faillll....", id )
        return
    end

    local ply = player.GetByAccountID( id )
    if not IsValid( ply ) then print( "fail!!!", id ) return end

    print( ply )
    PrintTable( data )

end )*/

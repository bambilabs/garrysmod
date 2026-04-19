if not util.IsBinaryModuleInstalled( "mysqloo" ) then return end
require( "mysqloo" )

local DRIVER = {}

DRIVER.Name = "MySQLOO"
DRIVER.Identifier = "mysqloo"

function DRIVER:constructor()
    self.Config = {
        host        = "localhost",
        db          = "gmtower",
        username    = "root",
        password    = "password",
        port        = 3306,
        socket      = nil,
    }

    self.Object = nil
    self.ActiveQueries = {}
    self.NextQueryId = 0
end

function DRIVER:destructor() end

function DRIVER:setconfig( tbl )
    table.Merge( self.Config, tbl )
end

function DRIVER:isconnected()
    return self.Object and self.Object:status() == mysqloo.DATABASE_CONNECTED
end

function DRIVER:connect( callback )
    self.Object = mysqloo.connect(
        self.Config.host,
        self.Config.username,
        self.Config.password,
        self.Config.db,
        self.Config.port,
        self.Config.socket
    )

    self.Object.onConnected = function( db )
        if callback then
            callback( true )
        end

        hook.Run( "DatabaseConnected" )
    end

    self.Object.onConnectionFailed = function( db, err )
        LogPrint( "FAILED TO CONNECT! (" .. err .. ")", color_red, "Database" )

        if callback then
            callback( false, err )
        end
    end

    self.Object:connect()

    return true
end

function DRIVER:disconnect()
    if self:isconnected() then
        self.Object:disconnect()
    end
end

function DRIVER:query( str, callback )

    if not self:isconnected() then return end
    
    local db = self.Object

    local qu = db:query( str )
    self.NextQueryId = self.NextQueryId + 1

    local queryId = self.NextQueryId
    local queryPreview = tostring( str or "" )
    if string.len( queryPreview ) > 180 then
        queryPreview = string.sub( queryPreview, 1, 180 ) .. "..."
    end

    self.ActiveQueries[ qu ] = {
        id = queryId,
        sql = queryPreview,
    }

    if GTowerServers and GTowerServers.Trace then
        GTowerServers:Trace( "dbquery", "start id=", tostring( queryId ), " sql=", queryPreview )
    end

    qu.onSuccess = function( q, data )
        local active = self.ActiveQueries[ q ]
        self.ActiveQueries[ q ] = nil

        if GTowerServers and GTowerServers.Trace then
            GTowerServers:Trace(
                "dbquery",
                "success id=", tostring( active and active.id or queryId ),
                " rows=", tostring( istable( data ) and table.Count( data ) or "nil" )
            )
        end

        if callback then
            local ok, err = xpcall( function()
                callback( data, true, nil )
            end, debug.traceback )

            if not ok then
                ErrorNoHalt( "MySQLOO callback error for query #" .. tostring( active and active.id or queryId ) .. ": " .. tostring( err ) .. "\n" )
            end
        end
    end

    qu.onError = function( q, err, sql )
        local active = self.ActiveQueries[ q ]
        self.ActiveQueries[ q ] = nil

        if GTowerServers and GTowerServers.Trace then
            GTowerServers:Trace(
                "dbquery",
                "error id=", tostring( active and active.id or queryId ),
                " err=", tostring( err ),
                " sql=", tostring( sql or active and active.sql or queryPreview )
            )
        end

        self:onerror( err, callback )
    end

    qu.onAborted = function( q )
        local active = self.ActiveQueries[ q ]
        self.ActiveQueries[ q ] = nil

        if GTowerServers and GTowerServers.Trace then
            GTowerServers:Trace(
                "dbquery",
                "aborted id=", tostring( active and active.id or queryId ),
                " sql=", tostring( active and active.sql or queryPreview )
            )
        end

        self:onerror( "Query aborted.", callback )
    end 

    qu:start()

end

function DRIVER:escape( str )
    return self.Object:escape( str )
end

Database.RegisterDriver( DRIVER )

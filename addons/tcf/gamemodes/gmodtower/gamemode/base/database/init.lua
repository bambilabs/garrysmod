
QUERY_FAILIURE = false
QUERY_SUCCESS = true

module( "Database", package.seeall )

DEBUG = false
Object = Object or nil

local function EscapeFallback( str )
    str = tostring( str or "" )
    str = string.Replace( str, "\\", "\\\\" )
    str = string.Replace( str, "\000", "\\0" )
    str = string.Replace( str, "\n", "\\n" )
    str = string.Replace( str, "\r", "\\r" )
    str = string.Replace( str, string.char( 26 ), "\\Z" )
    str = string.Replace( str, "'", "\\'" )
    str = string.Replace( str, "\"", "\\\"" )

    return str
end

function GetObject()
    return Object
end

function SetDriver( identifier )

    local driver = CreateDriver( identifier )

    if not driver then
        LogPrint( Format( "Failed to set driver to \"%s\"! Not found in registry!", identifier ), color_red, "Database" )
        return
    end

    Object = driver

end

function SetConfig( tbl )

    local driver = GetObject()

    return driver:setconfig( tbl )

end

function IsConnected()

    local driver = GetObject()

    if not driver then
        return false
    end

    return driver:isconnected()

end

function Connect( callback )

    local driver = GetObject()

    return driver:connect( callback )

end

function Disconnect()

    local driver = GetObject()

    return driver:disconnect()

end

function Query( str, callback )

    if not IsConnected() then
        ErrorNoHaltWithStack( "Attempt to query with a disconnected database!" )
        if callback then
            callback( nil, QUERY_FAILIURE, "Database disconnected." )
        end

        return false
    end

    local driver = GetObject()

    return driver:query( str, callback )

end

function Escape( str, withquotes )
    local escaped_string

    if not IsConnected() then
        ErrorNoHaltWithStack( "Attempt to escape with a disconnected database!" )
        escaped_string = EscapeFallback( str )
    else
        local driver = GetObject()

        escaped_string = driver:escape( str )
    end

    if withquotes then
        escaped_string = "'" .. escaped_string .. "'" 
    end

    return escaped_string

end

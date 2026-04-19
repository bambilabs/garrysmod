require( "dotenv" )

if LoadTCFEnv then
    LoadTCFEnv()
else
    env.load( ".env" )
end

// Setup Database Connection

local function SetupDatabase()
    RunConsoleCommand( "sv_hibernate_think", "1" )

    if GTowerServers and GTowerServers.Trace then
        GTowerServers:Trace( "database", "SetupDatabase begin; hibernate_think forced on" )
    end

    if LoadTCFEnv then
        LoadTCFEnv()
    end

    local driver = env.getString( "DATABASE_DRIVER", "mysqloo" )
    local host = env.getString( "DATABASE_HOST", "localhost" )
    local password = env.getString( "DATABASE_PASSWORD", "password" )
    local socket = env.getString( "DATABASE_SOCKET", nil )

    if string.lower( host ) == "localhost" and ( not socket or socket == "" ) then
        host = "127.0.0.1"
    end

    if password == "yourpassword" then
        LogPrint( "DATABASE_PASSWORD is still using the placeholder value from " .. tostring( TCFEnvPath or ".env" ) .. ".", color_red, "Database" )
    end

    local config = {
    host = host,

    username = env.getString( "DATABASE_USER", "root" ),
    password = password,

    db = env.getString( "DATABASE_DB", "gmt" ),

    port = env.getNumber( "DATABASE_PORT", 3306 ),
    socket = socket,
}

    LogPrint(
        Format(
            "Using env \"%s\" with host \"%s\", port \"%s\", socket \"%s\".",
            tostring( TCFEnvPath or ".env" ),
            tostring( config.host ),
            tostring( config.port ),
            tostring( config.socket )
        ),
        nil,
        "Database"
    )

    if GTowerServers and GTowerServers.Trace then
        GTowerServers:Trace( "database", "Driver=", tostring( driver ), " host=", tostring( config.host ), " port=", tostring( config.port ), " db=", tostring( config.db ) )
    end
    
    Database.SetDriver( driver )
    Database.SetConfig( config )

    Database.Connect()

end

hook.Add( "DatabaseModuleInitialized", "SetupDatabase", SetupDatabase )
hook.Add( "DatabaseConnected", "SetupDatabase", function()

    LogPrint( "Successfully connected to database.", nil, "Database" )

    if GTowerServers and GTowerServers.Trace then
        GTowerServers:Trace( "database", "DatabaseConnected hook fired" )
    end

    // Database.Migrate()

end )

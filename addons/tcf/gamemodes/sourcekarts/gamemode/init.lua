AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_controls.lua")
AddCSLuaFile("cl_camera.lua")

AddCSLuaFile( "cl_hud.lua" )
AddCSLuaFile( "cl_huditem.lua" )

AddCSLuaFile("meta_player.lua")

AddCSLuaFile("checkpoints/cl_init.lua")
AddCSLuaFile("checkpoints/shared.lua")

AddCSLuaFile("cl_debug3d.lua")

AddCSLuaFile("sh_items.lua")
include("sh_items.lua")

include("checkpoints/shared.lua")

include("meta_player.lua")

include("shared.lua")

CreateConVar("gmt_srvid", 16 )

util.AddNetworkString("KartSpin")
util.AddNetworkString("HUDMessage")
util.AddNetworkString("KartJump")
util.AddNetworkString("online_music")

hook.Add("GTowerMsg", "GamemodeMessage", function()
	if player.GetCount() < 1 then
		return "#nogame"
	else
		/*if !GAMEMODE:IsBattle() then

		else

		end*/

		return tostring(GAMEMODE:GetTrack()) .. "/" .. "3" .. "||||" .. tostring(GAMEMODE:GetTrack()) .. "/" .. "3"

	end
end )

local PlyJoined = false
local PrivateQueueStartTimer = "SourceKartsPrivateQueueStart"

local function IsPrivateQueueServer()
	if not GTowerServers or not GTowerServers.GetState or not GTowerServers.Self then
		return false
	end

	local serverMeta = GTowerServers:Self()
	return serverMeta and serverMeta.Private == true and GTowerServers:GetState() == 3
end

local function GetBattleResetSpawn()
	local spawns = {}

	for _, v in pairs( ents.FindByClass( "info_kart_spawn" ) ) do
		if tostring( v.Track ) == "4" then
			table.insert( spawns, v )
		end
	end

	return table.Random( spawns )
end

function GM:StartReadyPhase()
	timer.Remove( PrivateQueueStartTimer )
	self.PrivateQueueStartQueuedAt = nil
	self.PlayingPhaseStarted = false

	self:CleanUpMap()

	for _, v in pairs( player.GetAll() ) do
		v:SetTeam( TEAM_PLAYING )
		v:SetLap( 1 )
		v.PassedPoints = {}
		v:ClearItems()
		self:SpawnPlayerKart( v, false )
	end

	self:SetTime( self.CameraTime * self.Cameras + 6 )
	self:SetState( STATE_READY )
	self:DoIntroCamera( self:GetTrack() )
end

function GM:StartPlayingPhase()
	if self:GetState() != STATE_READY || self.PlayingPhaseStarted then return end
	self.PlayingPhaseStarted = true

	for _, v in pairs( ents.FindByClass( "sk_kart" ) ) do
		v:SetIsEngineOn( true )
	end

	self:SetTime( self.RaceTime )
	self:SetState( STATE_PLAYING )

	local TrackName = {}
	TrackName[1] = MUSIC_RACE1
	TrackName[2] = MUSIC_RACE2
	TrackName[3] = MUSIC_RACE3

	music.Play( 1, TrackName[ self:GetTrack() ] )

	for _, v in pairs( player.GetAll() ) do
		v:SetLapTime( CurTime() )
		v:SetNWFloat( "StartedTime", CurTime() )
		v:SetBestLapTime( 0 )
		v:SetTotalTime( CurTime() )

		// Ready set go boost
		if v.RevTime && v.RevTime != 0 && v:KeyDown( IN_FORWARD ) then
			local RevDelay = CurTime() - v.RevTime

			if RevDelay < 2 then
				if IsValid( v:GetKart() ) then
					v:GetKart():Boost( 2, 2 )
				end
				v:AddAchievement( ACHIEVEMENTS.SKROLLING, 1 )
			else
				v:GetKart():Spin()
			end
		end
	end
end

function GM:ReleaseKartSpawnClaims( ply )
	local track = tostring( self:GetTrack() )

	for _, v in pairs( ents.FindByClass( "info_kart_spawn" ) ) do
		if tostring( v.Track ) != track then continue end

		local owner = v.Player
		if owner == ply || !IsValid( owner ) || !IsValid( owner:GetKart() ) then
			v.Player = nil
		end
	end
end

function GM:GetPrivateQueuedPlayerTarget()
	if !IsPrivateQueueServer() || !GetAuthorizedPlayers then
		return 0
	end

	local expected = table.Count( GetAuthorizedPlayers() or {} )
	if expected <= 0 then
		expected = math.max( player.GetCount(), 1 )
	end

	return expected
end

function GM:GetPrivateClientReadyCount()
	local count = 0

	for _, ply in pairs( player.GetAll() ) do
		if ply:IsBot() then continue end
		if ply._SKClientReady || ply._ClientCreated then
			count = count + 1
		end
	end

	return count
end

function GM:QueuePrivateStart()
	if self:GetState() != STATE_WAITING then return end

	self.PrivateQueueStartQueuedAt = self.PrivateQueueStartQueuedAt or CurTime()

	if timer.Exists( PrivateQueueStartTimer ) then return end

	timer.Create( PrivateQueueStartTimer, 0.5, 0, function()
		if not GAMEMODE or GAMEMODE:GetState() != STATE_WAITING or not PlyJoined then
			timer.Remove( PrivateQueueStartTimer )
			return
		end

		local readyCount = GAMEMODE:GetPrivateClientReadyCount()
		local expectedCount = GAMEMODE:GetPrivateQueuedPlayerTarget()
		local age = CurTime() - ( GAMEMODE.PrivateQueueStartQueuedAt or CurTime() )

		if readyCount <= 0 then return end

		if readyCount >= expectedCount || age >= 12 then
			timer.Remove( PrivateQueueStartTimer )
			GAMEMODE:StartReadyPhase()
		end
	end )
end

function GM:AdvancePostRaceState()
	if IsPrivateQueueServer() then
		self:SetTime( 10 )
		self:SetState( STATE_ENDING )
		music.Play( 1, MUSIC_WAITING )

		for _, v in pairs( player.GetAll() ) do
			v:ClearItems()
			v:SetCamera( "Waiting", 0 )
		end

		return
	end

	self:SetTime( 10 )

	if GAMEMODE:GetTrack() == 3 then
		self:SetState( STATE_TOBATTLE )
	elseif GAMEMODE:GetTrack() == 5 then
		self:SetState( STATE_ENDING )
	elseif GAMEMODE:GetTrack() == 4 then
		self:SetState( STATE_NEXTBATTLE )
	else
		self:SetState( STATE_NEXTTRACK )
	end
end

function GM:GetRaceResetPoint( ply )
	local totalPoints = #checkpoints.Points
	if totalPoints <= 0 then return nil end

	local checkpoint = math.Clamp( ply:GetCheckpoint(), 1, totalPoints )
	local point = checkpoints.Points[ checkpoint ]
	if point then
		return point
	end

	local kart = ply:GetKart()
	if IsValid( kart ) then
		local closest = checkpoints.ClosestPoint( kart:GetPos() )
		if closest then
			return checkpoints.Points[ math.Clamp( closest, 1, totalPoints ) ]
		end
	end

	return checkpoints.Points[1]
end

function GM:RespawnPlayerAtRacePoint( ply, engineon )
	if !IsValid( ply ) then return false end
	if !ply.RespawnDelay then ply.RespawnDelay = 0 end
	if CurTime() < ply.RespawnDelay then return false end

	local point = self:GetRaceResetPoint( ply )
	if !point then
		self:SpawnPlayerKart( ply, engineon )
		return true
	end

	ply.RespawnDelay = CurTime() + 5
	ply.PassedPoints = ply.PassedPoints or {}

	for i = point.id - 4, point.id do
		if i > 0 then
			ply.PassedPoints[i] = true
		end
	end

	local ang = point.ang
	local pos = point.pos + ( ang:Up() * -110 )

	PostEvent( ply, "fadeon" )
	ply:ClearItems()

	timer.Simple( .85, function()
		if !IsValid( ply ) then return end

		ply:SpawnKart( pos, ang, engineon )
		PostEvent( ply, "fadeoff" )
	end )

	timer.Simple( 1, function()
		if !IsValid( ply ) then return end

		local kart = ply:GetKart()
		if IsValid( kart ) then
			kart:Boost( 2, 0.5 )
		end
	end )

	return true
end

function GM:RespawnPlayerAtBattleSpawn( ply )
	if !IsValid( ply ) then return false end
	if !ply.RespawnDelay then ply.RespawnDelay = 0 end
	if CurTime() < ply.RespawnDelay then return false end

	local resetSpawn = GetBattleResetSpawn()
	if !IsValid( resetSpawn ) then return false end

	ply.RespawnDelay = CurTime() + 5
	PostEvent( ply, "fadeon" )

	timer.Simple( .85, function()
		if !IsValid( ply ) then return end

		ply:SpawnKart( resetSpawn:GetPos() + Vector( 0, 0, 25 ), resetSpawn:GetAngles(), true )
		PostEvent( ply, "fadeoff" )
		ply:ClearItems()
		ply:TakeBattleDamage()
	end )

	timer.Simple( 1, function()
		if !IsValid( ply ) then return end

		local kart = ply:GetKart()
		if IsValid( kart ) then
			kart:Boost( 2, 0.5 )
		end
	end )

	return true
end

// OVERRIDES ///////////////////////////////////////////

  // Disables player damage
  function GM:EntityTakeDamage( target, dmg )
    return false
  end

  function GM:PlayerShouldTakeDamage( ply, attacker )
    return false
  end

  // Disables killing yourself
  function GM:CanPlayerSuicide( ply )
	   return false
  end

  // Disables the use of the flashlight
  function GM:PlayerSwitchFlashlight( ply )
    return false
  end

  // Handles spawning with a lot of players
  function GM:IsSpawnpointSuitable( ply, spawnpointent, bMakeSuitable )
      return true
  end

/////////////////////////////////////////////////////////

// override default of 0
globalnet.SetNet( "State", STATE_WAITING )

function GM:PlayerSpawn( ply )

	if ply:IsBot() then return end

  timer.Simple(60,function()
    timer.Create("CheckEmpty",10,0,function()
      if player.GetCount() == 0 then
        self:EndServer()
        return
      end
    end)
  end)

 	// Set player model
 	hook.Call( "PlayerSetModel", GAMEMODE, ply )

  ply:SetNoDraw( true )

	local PlyCol = ply:GetInfo("gmt_playercolor")

	ply:SetNWVector( "PlyColor", (Vector( PlyCol ) * 255) )

  if self:GetState() == STATE_WAITING then

    ply:SetTeam( TEAM_READY )

		music.Play( 1, MUSIC_WAITING, ply )
    self:SpawnPlayerKart( ply, false )

    --self:SpawnPlayerKart( ply, false )

  elseif self:GetState() == STATE_READY then
    ply:SetTeam( TEAM_PLAYING )
    self:SpawnPlayerKart( ply, false )
    music.Play( 1, MUSIC_CAMERA, ply )

  elseif self:GetState() == STATE_BATTLE then
    ply:SetTeam( TEAM_PLAYING )

    ply:SetLapTime(CurTime())

    timer.Simple(2.5,function()
      music.Play( 1, MUSIC_BATTLE1, ply )
      self:SpawnPlayerKart( ply, true )
    end)
  else
    ply:SetTeam( TEAM_PLAYING )

    ply:SetLapTime(CurTime())

    --self:SpawnPlayerKart( ply, true )

    local TrackName = {}
    TrackName[1] = MUSIC_RACE1
    TrackName[2] = MUSIC_RACE2
    TrackName[3] = MUSIC_RACE3
    music.Play( 1, TrackName[ self:GetTrack() ], ply )
    self:SpawnPlayerKart( ply, true )
  end

  if ( PlyJoined or ply:IsBot() ) then return end

  PlyJoined = true

  if IsPrivateQueueServer() then
    self:QueuePrivateStart()
    return
  end

  GAMEMODE:SetTime( GAMEMODE.WaitingTime )

end

function GM:PlayerDisconnected( ply )
	 if IsValid( ply:GetKart() ) then ply:GetKart():Remove() end
	 self:ReleaseKartSpawnClaims( ply )
end

hook.Add( "PlayerSpawnClient", "SourceKartsRoundSync", function( ply )
	if !IsValid( ply ) || ply:IsBot() then return end

	ply._SKClientReady = true

	if !GAMEMODE then return end

	if GAMEMODE:GetState() == STATE_WAITING && PlyJoined && IsPrivateQueueServer() then
		GAMEMODE:QueuePrivateStart()
		return
	end

	if GAMEMODE:GetState() == STATE_READY then
		ply:SetTeam( TEAM_PLAYING )
		GAMEMODE:SpawnPlayerKart( ply, false )
		ply:SetCamera( "Playing", 0 )
		return
	end

	if GAMEMODE:GetState() == STATE_PLAYING then
		ply:SetTeam( TEAM_PLAYING )
		GAMEMODE:SpawnPlayerKart( ply, true )

		if ply:GetLap() < 1 then
			ply:SetLap( 1 )
		end

		if ply:GetLapTime() <= 0 then
			ply:SetLapTime( CurTime() )
		end

		if ply:GetBestLapTime() < 0 then
			ply:SetBestLapTime( 0 )
		end

		if ply:GetTotalTime() <= 0 then
			ply:SetTotalTime( CurTime() )
		end

		if ply:GetNWFloat( "StartedTime" ) <= 0 then
			ply:SetNWFloat( "StartedTime", CurTime() )
		end

		ply:SetCamera( "Playing", 0 )
	end
end )

function GM:Complete( ply )
  local hadFinishers = GAMEMODE:GetFinishedPlayers() > 0

  ply:SetTeam( TEAM_FINISHED )
  ply:ClearItems()

	if ply:GetPosition() == 1 then
    music.Play( 1, MUSIC_WIN, ply )
		ply:AddAchievement( ACHIEVEMENTS.SKCHAMP, 1 )
  else
    music.Play( 1, MUSIC_LOSE, ply )
  end

  local vPoint = ply:GetKart():GetPos()
  local effectdata = EffectData()
  effectdata:SetOrigin( vPoint )
  util.Effect( "confetti", effectdata, true, true )

  ply:GetKart():EmitSound( "gmodtower/misc/confetti.wav", 80, math.random(125,150) )

	ply:SetNWFloat( "FinishedTime", CurTime() )

  local totalPlayers = GAMEMODE:GetTotalPlayers()
  local allFinished = totalPlayers > 0 && GAMEMODE:GetFinishedPlayers() >= totalPlayers

  if !hadFinishers && !allFinished then
    self:SetTime( self.FirstCountdown )
  end

  if self:GetState() == STATE_PLAYING && allFinished then
    GAMEMODE:GiveMoney( true )
    self:AdvancePostRaceState()
  end

end

function GM:Lap( ply )

  local NewLap = ply:GetLap() + 1

  if (ply:GetBestLapTime() == 0 || self:GetTimeElapsed(ply:GetLapTime()) < ply:GetBestLapTime()) then
    ply:SetBestLapTime( self:GetTimeElapsed(ply:GetLapTime()) )
  end

  if NewLap > 3 then
    GAMEMODE:Complete( ply )
    return
  end

  ply:SetLapTime(CurTime())

  ply:SetLap( ply:GetLap() + 1 )

  local vPoint = ply:GetKart():GetPos()
  local effectdata = EffectData()
  effectdata:SetOrigin( vPoint )
  util.Effect( "confetti", effectdata, true, true )

  ply:GetKart():EmitSound( "gmodtower/misc/confetti.wav", 80, math.random(125,150) )

end

function GM:SpawnPlayerKart( ply, engineon )

  ply:SetNet("BAL",0)
  ply:UnDrunk()
  self:ReleaseKartSpawnClaims( ply )

  local fallbackSpawn = nil
  for k,v in pairs(ents.FindByClass("info_kart_spawn")) do
    if tostring(v.Track) != tostring(self:GetTrack()) then continue end

    fallbackSpawn = fallbackSpawn or v

    if ( !v.Player ) then
      if IsValid( ply:GetKart() ) then ply:GetKart():Remove() end
      v.Player = ply
      ply:SpawnKart( v:GetPos(), v:GetAngles(), engineon )
      return
    end
  end

  if fallbackSpawn then
    if IsValid( ply:GetKart() ) then ply:GetKart():Remove() end
    fallbackSpawn.Player = ply
    ply:SpawnKart( fallbackSpawn:GetPos(), fallbackSpawn:GetAngles(), engineon )
  end

end

function GM:Think()
	for k,v in pairs(player.GetAll()) do
		local PlyCol = v:GetInfo("gmt_playercolor")
		v:SetNWVector( "PlyColor", (Vector( PlyCol ) * 255) )
	end

  if self:GetState() == STATE_WAITING then

    for k,v in pairs(player.GetAll()) do v:SetCamera("Waiting",0) end

    if (self:NoTimeLeft() && PlyJoined) then
      self:StartReadyPhase()
    end
  elseif self:GetState() == STATE_READY then
    local time = math.ceil( self:GetTimeLeft() )
    if time <= 1 && !self.PlayingPhaseStarted then
      self:StartPlayingPhase()
    end
  elseif self:GetState() == STATE_PLAYING then

    if ( self:GetFinishedPlayers() > 0 && self:NoTimeLeft() ) then
      GAMEMODE:GiveMoney( true )
      self:AdvancePostRaceState()

    elseif ( self:GetFinishedPlayers() == 0 && self:NoTimeLeft() ) then
      GAMEMODE:GiveMoney( true )
      self:AdvancePostRaceState()

    elseif ( self:GetFinishedPlayers() >= self:GetTotalPlayers() && self:GetTotalPlayers() > 0 ) then
      GAMEMODE:GiveMoney( true )
      self:AdvancePostRaceState()

    end

  elseif self:GetState() == STATE_NEXTTRACK then

    if self:NoTimeLeft() then
      self:IncreaseTrack()
      self:StartReadyPhase()
    end
  elseif self:GetState() == STATE_NEXTBATTLE then

    if self:NoTimeLeft() then
      self:CleanUpMap()
      self:IncreaseTrack()
      for k,v in pairs(player.GetAll()) do
        local spawns = {}

        for k,v in pairs( ents.FindByClass("info_kart_spawn") ) do
          if v.Track == "4" then
            table.insert( spawns, v )
          end
        end

        local ResetSpawn = table.Random( spawns )
        v:SpawnKart( ResetSpawn:GetPos(), ResetSpawn:GetAngles(), true )
        v:SetTeam( TEAM_PLAYING )
        v:SetLap( 1 )
        v:ClearItems()
        v:SetDeaths(0)
        v:SetFrags(0)
        v:SetGhost( false )
        v.Dead = false
        v:GetKart():SetIsGhost( false )
        v:GetKart():SetIsInvincible( false )
      	v:SetTeam(TEAM_PLAYING)
      end

      self:SetRound(2)

      self:SetTime( self.BattleTime )

      self:SetState( STATE_BATTLE )
      music.Play( 1, MUSIC_BATTLE2 )
    end
  elseif self:GetState() == STATE_BATTLEENDING then

    if self:NoTimeLeft() then
      self:IncreaseTrack()

      self:SetTime( 10 )

      self:SetState( STATE_ENDING )

	music.Play( 1, MUSIC_WAITING )

      for k,v in pairs(player.GetAll()) do
        v:SetCamera( "Waiting", 0 )
        v:ClearItems()
		v:SetTeam( TEAM_PLAYING )
      end

    end
  elseif self:GetState() == STATE_ENDING then

    if self:NoTimeLeft() then
      self:EndServer()
    end
  elseif self:GetState() == STATE_BATTLE then

    if self:NoTimeLeft() then
      GAMEMODE:GiveMoney( false )
      self:SetTime( 10 )
      if self:GetTrack() == 5 then
        self:SetState( STATE_BATTLEENDING )
        for k,v in pairs(player.GetAll()) do
          v:ClearItems()
        end
      else
        self:SetState( STATE_NEXTBATTLE )
        for k,v in pairs(player.GetAll()) do
          v:ClearItems()
        end
      end
    else

      local deadcount = 0
      for k,v in pairs(player.GetAll()) do
        if v.Dead then deadcount = deadcount + 1 end
      end

      if deadcount == player.GetCount() - 1 then
        GAMEMODE:GiveMoney( false )
        self:SetTime( 10 )
        if self:GetTrack() == 5 then
          self:SetState( STATE_BATTLEENDING )
        else
          self:SetState( STATE_NEXTBATTLE )
        end
      end

    end
  elseif self:GetState() == STATE_TOBATTLE then

    if self:NoTimeLeft() then
      self:CleanUpMap()

      self:IncreaseTrack()

      self:SetTime( self.CameraTime * self.Cameras + 6 )

      self:SetState( STATE_BATTLEINTRO )

      music.Play( 1, MUSIC_BATTLEINTRO )

      for k,v in pairs(player.GetAll()) do
        v:SetTeam( TEAM_PLAYING )
        v:SetLap( 1 )
        v:SetCamera( "Battle", 0 )
        v:ClearItems()
      end

      timer.Simple(13,function()
        for k,v in pairs(player.GetAll()) do self:SpawnPlayerKart( v, true ) end

        self:SetTime( self.BattleTime )

        self:SetState( STATE_BATTLE )

        music.Play( 1, MUSIC_BATTLE1 )

        for k,v in pairs(player.GetAll()) do
          v:SetCamera( "Playing", 0 )
        end
      end)

    end

  end


end

function GM:DoIntroCamera( track )

  print("STARTING INTRO CAMERAS ON TRACK "..tostring(track))

music.Play( 1, MUSIC_CAMERA )

  for k,v in pairs( player.GetAll() ) do

    --v:SendLua([[surface.PlaySound('gmodtower/sourcekarts/music/race_reveal3.mp3')]])

    v:SetCamera( "Waiting"..tostring(track).."1", 0 )

    timer.Simple(GAMEMODE.CameraTime,function()
      v:SetCamera( "Waiting"..tostring(track).."2", 0 )
    end)

    timer.Simple(GAMEMODE.CameraTime*2,function()
      v:SetCamera( "Waiting"..tostring(track).."3", 0 )
    end)

    timer.Simple(GAMEMODE.CameraTime*3,function()
      v:SetCamera( "Playing", 0 )
    end)

  end
end

concommand.Add("sk_spawnkart",function(ply)
  if !ply:IsAdmin() then return end

  local e = ents.Create("sk_kart")
  e:SetOwner(ply)
  e:SetPos(ply:GetPos())
  e:Spawn()

  e:SetIsEngineOn(true)

end)

concommand.Add("sk_removekart",function(ply)
  if !ply:IsAdmin() then return end


  if IsValid(ply:GetKart()) then ply:GetKart():Remove() end

end)

concommand.Add("sk_horn",function(ply)
  --print("TOOT?")
  if !ply.HornDelay then ply.HornDelay = 0 end

  if !IsValid(ply:GetKart()) or !IsValid(ply) or CurTime() < ply.HornDelay then return end

  ply.HornDelay = CurTime() + 3
  --print("HONK!")

local hornnum = ply:GetInfoNum("sk_hornnum",3)

  ply:GetKart():EmitSound("gmodtower/sourcekarts/effects/horns/horn" .. hornnum .. ".wav" ,80)

end)

concommand.Add("sk_rev",function(ply)

  if GAMEMODE:GetState() != STATE_READY then return end

  if !ply.RevDelay then ply.RevDelay = 0 end
  if !IsValid(ply:GetKart()) or !IsValid(ply) or CurTime() < ply.RevDelay then return end

  ply.RevDelay = CurTime() + .25

  ply:GetKart():EmitSound("gmodtower/sourcekarts/effects/rev.wav", 100, math.random(100,110))

  ply.RevTime = CurTime()

end)
/*
local kart = net.ReadEntity()
local height = net.ReadFloat() * 5

local downrate = net.ReadFloat() * .25

*/
concommand.Add("sk_jump",function(ply)

  --if GAMEMODE:GetState() != STATE_PLAYING then return end

  local kart = ply:GetKart()

  if !IsValid(kart) then return end

  net.Start( "KartJump" )
    net.WriteEntity( ply )
    net.WriteEntity( kart )
    net.WriteFloat( 2.5 )
    net.WriteFloat( 5 )
  net.Broadcast()

end)

concommand.Add("sk_reset",function(ply)

  if GAMEMODE:GetState() == STATE_BATTLE then
    GAMEMODE:RespawnPlayerAtBattleSpawn( ply )
    return
  end

  local state = GAMEMODE:GetState()
  local canResetRace = state == STATE_READY || state == STATE_PLAYING || state == STATE_NEXTTRACK || state == STATE_ENDING
  if !canResetRace || ply:Team() != TEAM_PLAYING then return end

  GAMEMODE:RespawnPlayerAtRacePoint( ply, state != STATE_READY )


end)

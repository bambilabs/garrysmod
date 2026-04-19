function GAMEMODE:EndServer()

	//I guess it it good bye
	GTowerServers:EmptyServer()
	GTowerServers:ResetServer()

end

function GAMEMODE:EnterPlayingState()
	if self.StartReadyPhase then
		self:StartReadyPhase()
		return
	end

	self:SetState( STATE_READY )
end


-----------------------------------------------------
ENT.Type 	= "anim"
ENT.Base 	= "base_anim"

ENT.Model	= Model( "models/gmod_tower/sourcekarts/ballionrocket.mdl" )

function ENT:GetKart()
	local owner = self:GetOwner()
	if !IsValid( owner ) then
		return NULL
	end

	return owner:GetKart()
end

function ENT:IsValidOwner()
	return IsValid( self:GetOwner() )
end


AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
  self:SetModel(self.Model)
  self:DrawShadow(false)
  self:SetMaterial("models/wireframe")
  self:SetColor(Color(200,200,255,255))

  local owner = self:GetOwner()
  local kart = IsValid( owner ) and owner:GetKart() or NULL
  if IsValid( kart ) then
    kart:SetIsInvincible(true)
  end

  self.ShieldSound = CreateSound( self, self.Sound )
  self.ShieldSound:Play()

end

function ENT:OnRemove()
    local owner = self:GetOwner()
    local kart = IsValid( owner ) and owner:GetKart() or NULL
    if IsValid( kart ) then
      kart:SetIsInvincible(false)
    end

    if self.ShieldSound then
      self.ShieldSound:Stop()
    end
end


AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
  self:SetModel(self.Model)
  self:DrawShadow(false)
end

function ENT:Think()
  self:UpdateEndPos()
    if ( IsValid( self.HitEntity ) && self.HitEntity:GetClass() == "sk_kart" && !self.HitEntity:IsSpinning() ) then
      local attacker = self:GetOwner()
      local victim = self.HitEntity:GetOwner()
      if !IsValid( attacker ) || !IsValid( victim ) then return end

      if self.HitEntity:GetIsInvincible() then
        self.HitEntity:EmitSound( SOUND_REFLECT, 80 )
        return
      end

      if GAMEMODE:IsBattle() then
        victim:TakeBattleDamage( attacker )
      end

      self.HitEntity:Spin( attacker )

      net.Start( "HUDMessage" )
        net.WriteString( "YOU HIT "..string.upper( victim:Name() ) )
      net.Send( attacker )

	  attacker:AddAchievement( ACHIEVEMENTS.SKLASER, 1 )

      local attackerKart = attacker:GetKart()
      if IsValid( attackerKart ) then
        attackerKart:EmitSound(SOUND_LASERHIT,80)
      end

    end

    self:NextThink(CurTime())

end

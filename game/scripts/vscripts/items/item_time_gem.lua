LinkLuaModifier("modifier_item_time_gem", "items/item_time_gem.lua", LUA_MODIFIER_MOTION_NONE)

-- Abilities
if item_time_gem == nil then
	item_time_gem = class({})
end

function item_time_gem:GetIntrinsicModifierName()
	return "modifier_item_time_gem"
end

function item_time_gem:IsRefreshable()
	return false
end

function item_time_gem:OnSpellStart()
	local caster = self:GetCaster()
	
	-- Find all refreshable abilities
	for i = 0, caster:GetAbilityCount() - 1 do
		local ability = caster:GetAbilityByIndex(i)
		if ability and ability:GetAbilityType() ~= ABILITY_TYPE_ATTRIBUTES and not self:IsAbitilyException(ability) then
			ability:RefreshCharges()
			ability:EndCooldown()
		end
	end

	-- Find all refreshable items
	for i = 0, 8 do
		local item = caster:GetItemInSlot(i)
		self:RefreshItem(item, caster)
	end

	local itemTp = caster:GetItemInSlot(DOTA_ITEM_TP_SCROLL)
	self:RefreshItem(itemTp, caster)

	-- Effects
	local sound_cast = "DOTA_Item.Refresher.Activate"
	caster:EmitSound(sound_cast)

	local particle_cast = "particles/items2_fx/refresher.vpcf"
	local effect_cast = ParticleManager:CreateParticle(particle_cast, PATTACH_ABSORIGIN_FOLLOW, caster)
	ParticleManager:ReleaseParticleIndex(effect_cast)
end

function item_time_gem:IsAbitilyException(ability)
	return self.AbilityException[ability:GetName()]
end

-- Exception list for abilities that should not be refreshed
item_time_gem.AbilityException = {
	["dazzle_good_juju"] = true,
}

function item_time_gem:RefreshItem(item, caster)
	if item and item:GetPurchaser() == caster then
		if item:IsRefreshable() then
			item:EndCooldown()
		end
		-- Logic for shared cooldowns (Refresher Orb, Refresh Core, etc.)
		if self.ItemShareCooldown[item:GetName()] then
			item:StartCooldown(self:GetCooldownTimeRemaining())
		end
	end
end

-- Exception list for items that share cooldown
item_time_gem.ItemShareCooldown = {
	["item_refresher"] = true,
	["item_refresher_shard"] = true,
	["item_refresh_core"] = true,
	["item_time_gem"] = true,
}

---------------------------------------------------------------------
-- Modifiers
if modifier_item_time_gem == nil then
	modifier_item_time_gem = class({})
end

function modifier_item_time_gem:IsHidden() return true end

function modifier_item_time_gem:IsPurgable() return false end

function modifier_item_time_gem:RemoveOnDeath() return false end

function modifier_item_time_gem:GetAttributes() 
	return MODIFIER_ATTRIBUTE_PERMANENT + MODIFIER_ATTRIBUTE_MULTIPLE + MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE 
end

function modifier_item_time_gem:OnCreated()
	local ability = self:GetAbility()
	if ability then
		self.bonus_cooldown = ability:GetSpecialValueFor("bonus_cooldown")
		-- Make sure to add "bonus_cooldown_stack" to your KV file for this item 
		-- to determine how much CDR it gives if Octarine is present.
		self.bonus_cooldown_stack = ability:GetSpecialValueFor("bonus_cooldown_stack")
		
		self.cast_range_bonus = ability:GetSpecialValueFor("cast_range_bonus")
		self.manacost_reduction = ability:GetSpecialValueFor("manacost_reduction")
		self.cast_speed_pct = ability:GetSpecialValueFor("cast_speed_pct")
	end

	if IsServer() then
		for _, mod in pairs(self:GetParent():FindAllModifiersByName(self:GetName())) do
			mod:GetAbility():SetSecondaryCharges(_)
		end
	end
end

function modifier_item_time_gem:OnDestroy()
	if IsServer() then
		for _, mod in pairs(self:GetParent():FindAllModifiersByName(self:GetName())) do
			mod:GetAbility():SetSecondaryCharges(_)
		end
	end
end

function modifier_item_time_gem:DeclareFunctions()
	return {
		MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE,
		MODIFIER_PROPERTY_CAST_RANGE_BONUS,
		MODIFIER_PROPERTY_MANACOST_PERCENTAGE_STACKING,
		MODIFIER_PROPERTY_CASTTIME_PERCENTAGE,
	}
end

function modifier_item_time_gem:GetModifierPercentageCooldown()
	-- Check logic from refresh_core to handle stacking with Octarine
	if self:GetAbility() and self:GetAbility():GetSecondaryCharges() == 1 then
		if self:GetParent():HasModifier("modifier_item_octarine_core")
			or self:GetParent():HasModifier("modifier_item_arcane_octarine_core") 
			or self:GetParent():HasModifier("modifier_item_refresh_core") then
			
			-- Uses the stack value if Octarine/Refresh Core is present
			-- Ensure "bonus_cooldown_stack" is defined in your KV, otherwise this returns 0
			return self.bonus_cooldown_stack
		else
			return self.bonus_cooldown
		end
	end
end

function modifier_item_time_gem:GetModifierCastRangeBonus()
	return self.cast_range_bonus
end

function modifier_item_time_gem:GetModifierPercentageManacostStacking()
	return self.manacost_reduction
end

function modifier_item_time_gem:GetModifierPercentageCasttime()
	return self.cast_speed_pct
end

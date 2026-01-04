-- ========================================
-- Hawkeye Turret
-- ========================================

-- LinkLuaModifier for Lua-based modifiers
LinkLuaModifier("modifier_item_hawkeye_turret_splash", "items/item_hawkeye_turret.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_item_hawkeye_turret_splash_cooldown", "items/item_hawkeye_turret.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_item_hawkeye_turret_active", "items/item_hawkeye_turret.lua", LUA_MODIFIER_MOTION_NONE)

if item_hawkeye_turret == nil then item_hawkeye_turret = class({}) end

-- ========================================
-- Active Ability
-- ========================================
function item_hawkeye_turret:OnSpellStart()
    local caster = self:GetCaster()

    -- Invalid for melee heroes
    if not caster:IsRangedAttacker() then
        return
    end

    local duration = self:GetSpecialValueFor("active_duration")

    -- Apply the active Lua modifier
    -- This modifier handles both the Attack Range Bonus and the Flying Vision
    caster:AddNewModifier(caster, self, "modifier_item_hawkeye_turret_active", {
        duration = duration
    })

    -- Play sound
    EmitSoundOn("DOTA_Item.HurricanePike.Activate", caster)
end

-- ========================================
-- Global Callbacks for KV DataDriven "RunScript"
-- Used to apply the passive effects (Desolator + Splash)
-- ========================================

-- Triggered by "OnCreated" in the KV file
function HawkeyeTurretOnCreated(keys)
    if not IsServer() then return end

    local caster = keys.caster
    local ability = keys.ability

    if not caster or not ability then return end

    -- Add Desolator modifier (Standard modifier)
    local desolator_modifier = caster:AddNewModifier(caster, ability, "modifier_item_desolator", {})

    -- Add Splash Damage Lua modifier (Check if it already exists to avoid stacking)
    local splash_modifier = nil
    if not caster:HasModifier("modifier_item_hawkeye_turret_splash") then
        splash_modifier = caster:AddNewModifier(caster, ability, "modifier_item_hawkeye_turret_splash", {})
    end

    -- Save modifier references to the ability to remove them precisely on Destroy
    if not ability.added_modifiers then
        ability.added_modifiers = {}
    end

    if desolator_modifier then
        table.insert(ability.added_modifiers, desolator_modifier)
    end
    if splash_modifier then
        table.insert(ability.added_modifiers, splash_modifier)
    end
end

-- Triggered by "OnDestroy" in the KV file
function HawkeyeTurretOnDestroy(keys)
    if not IsServer() then return end

    local ability = keys.ability

    if not ability or not ability.added_modifiers then return end

    -- Remove only the modifiers added by this specific item instance
    for _, modifier in pairs(ability.added_modifiers) do
        if modifier and not modifier:IsNull() then
            modifier:Destroy()
        end
    end

    -- Clear the table to prevent memory leaks
    ability.added_modifiers = nil
end

-- ========================================
-- Active Modifier (Attack Range + Vision)
-- ========================================
modifier_item_hawkeye_turret_active = class({})

function modifier_item_hawkeye_turret_active:IsHidden() return false end
function modifier_item_hawkeye_turret_active:IsPurgable() return true end

function modifier_item_hawkeye_turret_active:OnCreated()
    -- Store the bonus vision value to use for attack range as well
    self.bonus_vision = self:GetAbility():GetSpecialValueFor("active_bonus_vision")
    
    if IsServer() then
        local caster = self:GetParent()
        
        -- Calculate Vision Radius: Current Attack Range + Bonus Vision
        -- Script_GetAttackRange() returns base range + passive bonuses
        local current_range = caster:Script_GetAttackRange()
        local vision_radius = current_range + self.bonus_vision

        -- Initialize FOW viewers table
        if not caster.fow_viewers then
            caster.fow_viewers = {}
        end

        -- Add Flying Vision (false = flying vision, ignores terrain)
        local fow_viewer = AddFOWViewer(
            caster:GetTeamNumber(),
            caster:GetAbsOrigin(),
            vision_radius,
            self:GetDuration(),
            false
        )
        table.insert(caster.fow_viewers, fow_viewer)
        
        -- Store ID for removal
        self.fow_id = fow_viewer
    end
end

function modifier_item_hawkeye_turret_active:OnDestroy()
    if IsServer() then
        local caster = self:GetParent()
        if caster.fow_viewers and self.fow_id then
            RemoveFOWViewer(caster:GetTeamNumber(), self.fow_id)
            
            -- Clean up the table
            for i, v in ipairs(caster.fow_viewers) do
                if v == self.fow_id then
                    table.remove(caster.fow_viewers, i)
                    break
                end
            end
        end
    end
end

function modifier_item_hawkeye_turret_active:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_ATTACK_RANGE_BONUS,
        MODIFIER_PROPERTY_TOOLTIP
    }
end

function modifier_item_hawkeye_turret_active:GetModifierAttackRangeBonus()
    -- Attack range increases by the same amount as the vision bonus
    return self.bonus_vision
end

function modifier_item_hawkeye_turret_active:OnTooltip()
    return self.bonus_vision
end

-- ========================================
-- Lua Modifier - Splash Damage
-- ========================================
modifier_item_hawkeye_turret_splash = class({})

function modifier_item_hawkeye_turret_splash:IsHidden()
    return true
end

function modifier_item_hawkeye_turret_splash:IsPurgable()
    return false
end

function modifier_item_hawkeye_turret_splash:RemoveOnDeath()
    return false
end

function modifier_item_hawkeye_turret_splash:GetAttributes()
    return MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE
end

function modifier_item_hawkeye_turret_splash:OnCreated()
    if not IsServer() then return end

    local ability = self:GetAbility()
    self.attack_radius = ability:GetSpecialValueFor("attack_radius")
    self.attack_percent = ability:GetSpecialValueFor("attack_percent")
    self.internal_cooldown = ability:GetSpecialValueFor("internal_cooldown")
end

function modifier_item_hawkeye_turret_splash:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_PROCATTACK_FEEDBACK
    }
end

-- Trigger splash on attack feedback
function modifier_item_hawkeye_turret_splash:GetModifierProcAttack_Feedback(params)
    if not IsServer() then return end

    local attacker = params.attacker
    local target = params.target

    -- Basic checks
    if not attacker:IsRealHero() then return end
    if not attacker:IsRangedAttacker() then return end
    if attacker:GetTeam() == target:GetTeam() then return end
    if target:IsBuilding() then return end

    -- Check internal cooldown
    if attacker:HasModifier("modifier_item_hawkeye_turret_splash_cooldown") then return end

    local ability = self:GetAbility()
    if not ability then return end

    local target_loc = target:GetAbsOrigin()

    -- Calculate actual damage considering armor reduction using global function
    local actual_damage = CalculateActualDamage(params.damage, target)
    local damage = actual_damage * self.attack_percent / 100

    -- Play particle effect
    local blast_pfx = ParticleManager:CreateParticle("particles/custom/shrapnel.vpcf", PATTACH_CUSTOMORIGIN, nil)
    ParticleManager:SetParticleControl(blast_pfx, 0, target_loc)
    ParticleManager:ReleaseParticleIndex(blast_pfx)

    -- Find enemies in radius
    local enemies = FindUnitsInRadius(
        attacker:GetTeamNumber(),
        target_loc,
        nil,
        self.attack_radius,
        ability:GetAbilityTargetTeam(),
        ability:GetAbilityTargetType(),
        DOTA_UNIT_TARGET_FLAG_NONE,
        FIND_ANY_ORDER,
        false
    )

    -- Apply splash damage to enemies in range
    for _, enemy in pairs(enemies) do
        if enemy ~= target then
            ApplyDamage({
                victim = enemy,
                attacker = attacker,
                damage = damage,
                damage_type = ability:GetAbilityDamageType(),
                damage_flags = DOTA_DAMAGE_FLAG_NO_SPELL_AMPLIFICATION + DOTA_DAMAGE_FLAG_REFLECTION,
                ability = ability
            })
        end
    end

    -- Apply internal cooldown
    attacker:AddNewModifier(attacker, ability, "modifier_item_hawkeye_turret_splash_cooldown", {
        duration = self.internal_cooldown
    })
end

-- ========================================
-- Splash Cooldown Modifier
-- ========================================
modifier_item_hawkeye_turret_splash_cooldown = class({})

function modifier_item_hawkeye_turret_splash_cooldown:IsHidden()
    return true
end

function modifier_item_hawkeye_turret_splash_cooldown:IsPurgable()
    return false
end

function modifier_item_hawkeye_turret_splash_cooldown:RemoveOnDeath()
    return true
end

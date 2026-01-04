-- ========================================
-- 鹰眼炮台 - Hawkeye Turret
-- ========================================

-- LinkLuaModifier for Lua-based modifiers
LinkLuaModifier("modifier_item_hawkeye_turret_splash", "items/item_hawkeye_turret.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_item_hawkeye_turret_splash_cooldown", "items/item_hawkeye_turret.lua", LUA_MODIFIER_MOTION_NONE)
-- Добавляем линк на новый активный модификатор
LinkLuaModifier("modifier_item_hawkeye_turret_active", "items/item_hawkeye_turret.lua", LUA_MODIFIER_MOTION_NONE)

-- ========================================
-- 主动技能
-- ========================================
if item_hawkeye_turret == nil then item_hawkeye_turret = class({}) end

function item_hawkeye_turret:OnSpellStart()
    local caster = self:GetCaster()

    -- 近战英雄使用无效
    if not caster:IsRangedAttacker() then
        return
    end

    local duration = self:GetSpecialValueFor("active_duration")

    -- ЗАМЕНЕНО: Используем Lua Modifier вместо DataDriven, чтобы контролировать дальность атаки динамически
    caster:AddNewModifier(caster, self, "modifier_item_hawkeye_turret_active", {
        duration = duration
    })

    -- 播放音效
    EmitSoundOn("DOTA_Item.HurricanePike.Activate", caster)
end

function item_hawkeye_turret:GetIntrinsicModifierName()
    return "modifier_item_hawkeye_turret_intrinsic"
end

-- ========================================
-- Intrinsic Modifier (Пассивный эффект: Desolator + Splash)
-- Мы переносим логику из DataDriven OnCreated сюда для надежности,
-- либо создаем этот класс, если вы хотите полностью отказаться от KV OnCreated.
-- НО, чтобы сохранить совместимость с вашим кодом, я оставлю старый DataDriven вызов для пассивки,
-- если он у вас настроен через "Modifiers" в KV.
-- ========================================

-- ... (Ваши старые функции HawkeyeTurretOnCreated и HawkeyeTurretOnDestroy можно оставить 
-- если пассивная часть работает нормально через KV. Но активную часть мы удаляем из DataDriven логики).

-- ========================================
-- !!! ВАЖНО: Удалите или закомментируйте HawkeyeTurretActiveOnCreated и HawkeyeTurretActiveOnDestroy, 
-- так как теперь эта логика внутри modifier_item_hawkeye_turret_active !!!
-- ========================================


-- ========================================
-- НОВЫЙ Активный модификатор (Дальность + Обзор)
-- ========================================
modifier_item_hawkeye_turret_active = class({})

function modifier_item_hawkeye_turret_active:IsHidden() return false end
function modifier_item_hawkeye_turret_active:IsPurgable() return true end

function modifier_item_hawkeye_turret_active:OnCreated()
    self.bonus_vision = self:GetAbility():GetSpecialValueFor("active_bonus_vision")
    
    if IsServer() then
        local caster = self:GetParent()
        
        -- Вычисляем радиус: Текущая дальность атаки + Бонус
        -- Примечание: Script_GetAttackRange() вернет базовую дальность + пассивные бонусы.
        local current_range = caster:Script_GetAttackRange()
        local vision_radius = current_range + self.bonus_vision

        -- Инициализируем таблицу для FOW
        if not caster.fow_viewers then
            caster.fow_viewers = {}
        end

        -- Создаем обзор
        local fow_viewer = AddFOWViewer(
            caster:GetTeamNumber(),
            caster:GetAbsOrigin(),
            vision_radius,
            self:GetDuration(),
            false
        )
        table.insert(caster.fow_viewers, fow_viewer)
        
        -- Сохраняем ID для удаления
        self.fow_id = fow_viewer
    end
end

function modifier_item_hawkeye_turret_active:OnDestroy()
    if IsServer() then
        local caster = self:GetParent()
        if caster.fow_viewers and self.fow_id then
            RemoveFOWViewer(caster:GetTeamNumber(), self.fow_id)
            
            -- Очистка таблицы (опционально)
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
        MODIFIER_PROPERTY_ATTACK_RANGE_BONUS, -- Бонус к дальности атаки
        MODIFIER_PROPERTY_TOOLTIP -- Для отображения бонуса в интерфейсе
    }
end

function modifier_item_hawkeye_turret_active:GetModifierAttackRangeBonus()
    -- Теперь дальность атаки увеличивается ровно на то же значение, что использовалось для расчета обзора
    return self.bonus_vision
end

function modifier_item_hawkeye_turret_active:OnTooltip()
    return self.bonus_vision
end


-- ========================================
-- ВАШИ СТАРЫЕ ФУНКЦИИ (Оставляем для совместимости пассивки, если нужно)
-- ========================================
function HawkeyeTurretOnCreated(keys)
    -- ... (Ваш старый код для пассивки Desolator/Splash) ...
    print("HawkeyeTurretOnCreated")
    if not IsServer() then return end

    local caster = keys.caster
    local ability = keys.ability
    if not caster or not ability then return end

    local desolator_modifier = caster:AddNewModifier(caster, ability, "modifier_item_desolator", {})
    local splash_modifier = nil
    if not caster:HasModifier("modifier_item_hawkeye_turret_splash") then
        splash_modifier = caster:AddNewModifier(caster, ability, "modifier_item_hawkeye_turret_splash", {})
    end

    if not ability.added_modifiers then ability.added_modifiers = {} end
    if desolator_modifier then table.insert(ability.added_modifiers, desolator_modifier) end
    if splash_modifier then table.insert(ability.added_modifiers, splash_modifier) end
end

function HawkeyeTurretOnDestroy(keys)
    -- ... (Ваш старый код очистки пассивки) ...
    if not IsServer() then return end
    local ability = keys.ability
    if not ability or not ability.added_modifiers then return end
    for _, modifier in pairs(ability.added_modifiers) do
        if modifier and not modifier:IsNull() then
            modifier:Destroy()
        end
    end
    ability.added_modifiers = nil
end

-- ========================================
-- Lua 辅助 modifier - 溅射伤害 (Ваш код без изменений)
-- ========================================
modifier_item_hawkeye_turret_splash = class({})

function modifier_item_hawkeye_turret_splash:IsHidden() return true end
function modifier_item_hawkeye_turret_splash:IsPurgable() return false end
function modifier_item_hawkeye_turret_splash:RemoveOnDeath() return false end
function modifier_item_hawkeye_turret_splash:GetAttributes() return MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE end

function modifier_item_hawkeye_turret_splash:OnCreated()
    if not IsServer() then return end
    local ability = self:GetAbility()
    self.attack_radius = ability:GetSpecialValueFor("attack_radius")
    self.attack_percent = ability:GetSpecialValueFor("attack_percent")
    self.internal_cooldown = ability:GetSpecialValueFor("internal_cooldown")
end

function modifier_item_hawkeye_turret_splash:DeclareFunctions()
    return { MODIFIER_PROPERTY_PROCATTACK_FEEDBACK }
end

function modifier_item_hawkeye_turret_splash:GetModifierProcAttack_Feedback(params)
    if not IsServer() then return end

    local attacker = params.attacker
    local target = params.target

    if not attacker:IsRealHero() then return end
    if not attacker:IsRangedAttacker() then return end
    if attacker:GetTeam() == target:GetTeam() then return end
    if target:IsBuilding() then return end

    if attacker:HasModifier("modifier_item_hawkeye_turret_splash_cooldown") then return end

    local ability = self:GetAbility()
    if not ability then return end

    local target_loc = target:GetAbsOrigin()
    local actual_damage = CalculateActualDamage(params.damage, target) -- Внимание: убедитесь, что функция CalculateActualDamage существует в вашем глобальном скоупе
    local damage = actual_damage * self.attack_percent / 100

    local blast_pfx = ParticleManager:CreateParticle("particles/custom/shrapnel.vpcf", PATTACH_CUSTOMORIGIN, nil)
    ParticleManager:SetParticleControl(blast_pfx, 0, target_loc)
    ParticleManager:ReleaseParticleIndex(blast_pfx)

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

    attacker:AddNewModifier(attacker, ability, "modifier_item_hawkeye_turret_splash_cooldown", {
        duration = self.internal_cooldown
    })
end

-- ========================================
-- 溅射冷却 modifier
-- ========================================
modifier_item_hawkeye_turret_splash_cooldown = class({})
function modifier_item_hawkeye_turret_splash_cooldown:IsHidden() return true end
function modifier_item_hawkeye_turret_splash_cooldown:IsPurgable() return false end
function modifier_item_hawkeye_turret_splash_cooldown:RemoveOnDeath() return true end

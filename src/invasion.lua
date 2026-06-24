-- ============================================================
-- invasion.lua
-- Auto Invasion + Auto Infiltration
-- ============================================================

return function(ctx)
    local S       = ctx.Services
    local H       = ctx.Helpers
    local Flags   = ctx.Flags
    local Library = ctx.Library
    local Config  = ctx.Config
    local CONST   = Config.CONST
    local LocalPlayer = ctx.LocalPlayer

    local M = {}
    local invasionThread       = nil
    local infiltrationThread   = nil

    -- ============ VERIFICACAO DE REMOTES ============
    local function CheckRemotes()
        if not S.invasionCreate or not S.invasionLeave then
            warn("[Invasion] Remotes de invasao nao encontrados!")
            return false
        end
        if not S.infiltrationCreate or not S.lobbiesStart or not S.lobbiesLeave then
            warn("[Infiltration] Remotes de infiltration nao encontrados!")
            return false
        end
        if not S.clientSummary then
            warn("[Invasion] Remote clientSummary nao encontrado!")
            return false
        end
        return true
    end

    -- ============ TELEPORTE / FALLBACK ============
    local function TeleportToTargetOrCenter(uuid)
        if not H then return end
        local success = H.TeleportToEnemy(uuid)
        if not success then
            local pos = H.GetEnemyPosition(uuid)
            if pos then
                H.TeleportTo(pos)
                Library:Notification({ Name = "Inimigo longe! Indo pra posicao...", Time = 2 })
            end
        end
    end

    -- ============ COLETA / CLASSIFICACAO ============
    local function GetInvasionEnemiesOnly()
        local enemies = {}
        if not H then return enemies end
        local folder = H.GetEnemiesFolder()
        if not folder then return enemies end

        pcall(function()
            for _, model in ipairs(folder:GetChildren()) do
                if model:GetAttribute("dead") == true then continue end
                if not S.getEnemy then continue end
                local ok, data = pcall(S.getEnemy, model.Name)
                if not ok or not data or not data.name then continue end
                local pos = H.GetEnemyPosition(model.Name)
                if pos then
                    table.insert(enemies, {
                        uuid  = model.Name,
                        name  = data.name,
                        hp    = data.stats and data.stats.health    or 0,
                        maxHp = data.stats and data.stats.maxHealth or 0,
                    })
                end
            end
        end)

        return enemies
    end
    M.GetInvasionEnemiesOnly = GetInvasionEnemiesOnly

    local function WaitForInvasionEnemies(timeout)
        local t0 = os.clock()
        while os.clock() - t0 < timeout do
            task.wait(0.5)
            if #GetInvasionEnemiesOnly() > 0 then return true end
        end
        return false
    end

    -- ============ COMBATE NUM ALVO (INVASION) ============
    local function InvasionCombatFollowTarget(target, invasionDone, flagCheckFn)
        if not H then return end
        flagCheckFn = flagCheckFn or function() return Flags.AutoInvasion end

        while flagCheckFn() and not invasionDone() and H.IsEnemyAlive(target.uuid) do
            local okI = pcall(function()
                H.WaitForWarriorsRecovery(flagCheckFn)
                if not H.AreAllAliveWarriorsAttacking(target.uuid) then H.SendWarriorsTo(target.uuid) end
                if Flags.TeleportRaid then H.TeleportToEnemy(target.uuid) end
            end)
            if not okI then task.wait(0.5) end
            task.wait(0.25)
        end
    end

    -- ============ INVASION UNICA ============
    function M.RunSingleInvasion(invasionName, flagCheckFn)
        if not CheckRemotes() then
            Library:Notification({ Name = "Remotes nao carregaram!", Time = 3 })
            return "failed_start"
        end

        Library:Notification({ Name = "Invasion: " .. invasionName, Time = 3 })

        local ok, result = pcall(function()
            return S.invasionCreate:InvokeServer(invasionName, { friendsOnly = Flags.InvasionFriendsOnly })
        end)

        if not ok or result == false or result == nil then
            Library:Notification({ Name = "Sem acesso: " .. invasionName, Time = 3 })
            return "cooldown"
        end

        Library:Notification({ Name = "Invasion criada! Entrando...", Time = 2 })
        task.wait(3)

        pcall(function() S.lobbiesStart:FireServer() end)
        task.wait(2)

        -- Verifica se os inimigos carregaram (prova de que você está no mapa da invasão)
        if not WaitForInvasionEnemies(30) then
            Library:Notification({ Name = "Invasion nao iniciou, pulando...", Time = 3 })
            pcall(function() S.invasionLeave:FireServer() end)
            task.wait(2)
            return "failed_start"
        end

        Library:Notification({ Name = "Invasion iniciada! Aguardando 2s para o TP...", Time = 2 })

        -- === NOVO CÓDIGO DE TELEPORTE (ESPERA DE 2 SEGUNDOS) ===
        -- Espera exatamente 2 segundos para garantir que o seu personagem carregou no mapa da Invasion
        task.wait(2)

        pcall(function()
            if H and H.TeleportTo then
                -- Força o teleporte para a coordenada pedida
                H.TeleportTo(Vector3.new(5049.59, 6018.97, -21.29))
                Library:Notification({ Name = "Teleportado para o local exato da Invasion!", Time = 3 })
            end
        end)
        
        -- Mais um pequeno delay para estabilizar o boneco antes de mandar atacar
        task.wait(0.5)
        -- =======================================================

        local invasionDone = false
        local conn = S.clientSummary.OnClientEvent:Connect(function(raidType, data)
            if raidType ~= "invasions" then return end
            invasionDone = true
            Flags.InvasionsCompleted = (Flags.InvasionsCompleted or 0) + 1
            Library:Notification({ Name = "Invasion completa!", Time = 5 })
            task.delay(1, function()
                pcall(function() S.invasionLeave:FireServer() end)
                Library:Notification({ Name = "Saiu da invasion!", Time = 2 })
            end)
        end)

        local function isInvasionDone() return invasionDone end
        local timeout = os.clock() + CONST.RAID_TIMEOUT

        while flagCheckFn() and not invasionDone and os.clock() < timeout do
            local iterOk, iterErr = pcall(function()
                local enemies = GetInvasionEnemiesOnly()

                if #enemies == 0 then
                    Library:Notification({ Name = "Procurando inimigos...", Time = 1.5 })
                    task.wait(1.5)
                    return
                end

                local target = enemies[1]
                if not H.IsEnemyAlive(target.uuid) then task.wait(0.2) return end

                if Flags.TeleportRaid then TeleportToTargetOrCenter(target.uuid) end

                if not H.AreAllAliveWarriorsAttacking(target.uuid) then
                    H.SendWarriorsTo(target.uuid)
                    task.wait(0.5)
                    if not H.AreAllAliveWarriorsAttacking(target.uuid) and H.IsEnemyAlive(target.uuid) then
                        task.wait(0.2)
                        return
                    end
                end

                InvasionCombatFollowTarget(target, isInvasionDone, flagCheckFn)
            end)

            if not iterOk then
                warn("[Invasion] Erro (ignorado): " .. tostring(iterErr))
                task.wait(0.5)
            end
        end

        if conn then conn:Disconnect() conn = nil end
        if not flagCheckFn() then return "stopped" end

        if not invasionDone then
            Library:Notification({ Name = "Invasion expirou.", Time = 3 })
            return "timeout"
        end

        task.wait(3)
        return "completed"
    end

    -- ============ AUTO INVASION ============
    function M.StopAutoInvasion()
        Flags.AutoInvasion = false
        if invasionThread then
            task.cancel(invasionThread)
            invasionThread = nil
        end
    end

    function M.StartAutoInvasion()
        M.StopAutoInvasion()
        Flags.AutoInvasion = true

        invasionThread = task.spawn(function()
            local function isActive() return Flags.AutoInvasion end

            while Flags.AutoInvasion do
                local invasion = Flags.SelectedInvasion or (Config.InvasionNames and Config.InvasionNames[1]) or "Dark Matter Invasion"
                local status = M.RunSingleInvasion(invasion, isActive)

                if not Flags.AutoInvasion then break end
                Library:Notification({ Name = "Proxima invasion...", Time = 2 })

                if status == "cooldown" then task.wait(2) else task.wait(3) end
            end
            print("[AutoInvasion] Parado.")
        end)
    end

    -- ============ INFILTRATION (FASE 1: NPCs -> FASE 2: BOSS) ============
    local function GetInfiltrationEnemiesOnly()
        local enemies = {}
        if not H then return enemies end
        local folder = H.GetEnemiesFolder()
        if not folder then return enemies end

        pcall(function()
            for _, model in ipairs(folder:GetChildren()) do
                if model:GetAttribute("dead") == true then continue end
                if not S.getEnemy then continue end
                local ok, data = pcall(S.getEnemy, model.Name)
                if not ok or not data or not data.name then continue end
                local pos = H.GetEnemyPosition(model.Name)
                if pos then
                    table.insert(enemies, {
                        uuid  = model.Name,
                        name  = data.name,
                        hp    = data.stats and data.stats.health    or 0,
                        maxHp = data.stats and data.stats.maxHealth or 0,
                    })
                end
            end
        end)

        return enemies
    end
    M.GetInfiltrationEnemiesOnly = GetInfiltrationEnemiesOnly

    local function WaitForInfiltrationEnemies(timeout)
        local t0 = os.clock()
        while os.clock() - t0 < timeout do
            task.wait(0.5)
            if #GetInfiltrationEnemiesOnly() > 0 then return true end
        end
        return false
    end

    local function FindBossEnemy(enemies, infiltrationName)
        -- Primeiro, tenta achar o nome do boss na config
        local bossNames = Config.InfiltrationBossNames and Config.InfiltrationBossNames[infiltrationName]
        if bossNames then
            for _, e in ipairs(enemies) do
                for _, bossName in ipairs(bossNames) do
                    if e.name == bossName then return e end
                end
            end
        end

        -- Fallback: o com maior maxHP
        if #enemies == 0 then return nil end
        local boss = enemies[1]
        for _, e in ipairs(enemies) do
            if e.maxHp > boss.maxHp then boss = e end
        end
        return boss
    end

    local function InfiltrationCombatFollowTarget(target, infiltrationDone, flagCheckFn)
        if not H then return end
        flagCheckFn = flagCheckFn or function() return Flags.AutoInfiltration end

        while flagCheckFn() and not infiltrationDone() and H.IsEnemyAlive(target.uuid) do
            local okI = pcall(function()
                H.WaitForWarriorsRecovery(flagCheckFn)
                if not H.AreAllAliveWarriorsAttacking(target.uuid) then H.SendWarriorsTo(target.uuid) end
                if Flags.TeleportRaid then H.TeleportToEnemy(target.uuid) end
            end)
            if not okI then task.wait(0.5) end
            task.wait(0.25)
        end
    end

    -- ============ INFILTRATION UNICA ============
    function M.RunSingleInfiltration(infiltrationName, tier, flagCheckFn)
        if not CheckRemotes() then
            Library:Notification({ Name = "Remotes nao carregaram!", Time = 3 })
            return "failed_start"
        end

        Library:Notification({ Name = "Infiltration: " .. infiltrationName .. " [" .. tier .. "]", Time = 3 })

        local ok, result = pcall(function()
            return S.infiltrationCreate:InvokeServer(infiltrationName, tier, { friendsOnly = Flags.InfiltrationFriendsOnly })
        end)

        if not ok or result == false or result == nil then
            Library:Notification({ Name = "Sem acesso: " .. infiltrationName, Time = 3 })
            return "cooldown"
        end

        Library:Notification({ Name = "Infiltration criada! Entrando...", Time = 2 })
        task.wait(3)

        pcall(function() S.lobbiesStart:FireServer() end)
        task.wait(2)

        if not WaitForInfiltrationEnemies(30) then
            Library:Notification({ Name = "Infiltration nao iniciou, pulando...", Time = 3 })
            pcall(function() S.lobbiesLeave:FireServer() end)
            task.wait(2)
            return "failed_start"
        end

        Library:Notification({ Name = "Infiltration iniciada!", Time = 2 })

        local infiltrationDone = false
        local conn = S.clientSummary.OnClientEvent:Connect(function(raidType, data)
            if raidType ~= "infiltrations" then return end
            infiltrationDone = true
            Flags.InfiltrationsCompleted = (Flags.InfiltrationsCompleted or 0) + 1
            Library:Notification({ Name = "Infiltration completa!", Time = 5 })
            task.delay(1, function()
                pcall(function() S.lobbiesLeave:FireServer() end)
                Library:Notification({ Name = "Saiu da infiltration!", Time = 2 })
            end)
        end)

        local function isInfiltrationDone() return infiltrationDone end
        local lastPhase = ""
        local timeout = os.clock() + CONST.RAID_TIMEOUT

        while flagCheckFn() and not infiltrationDone and os.clock() < timeout do
            local iterOk, iterErr = pcall(function()
                local enemies = GetInfiltrationEnemiesOnly()

                if #enemies == 0 then
                    Library:Notification({ Name = "Procurando inimigos...", Time = 1.5 })
                    task.wait(1.5)
                    return
                end

                -- Heuristica: se a maioria dos enemies tem HP baixo comparado ao maior, estamos na Fase 1 (NPCs)
                local maxHp = 0
                for _, e in ipairs(enemies) do
                    if e.maxHp > maxHp then maxHp = e.maxHp end
                end

                local phase = "FASE1_NPC"
                local avgHp = 0
                for _, e in ipairs(enemies) do avgHp += e.maxHp end
                avgHp = avgHp / #enemies

                if avgHp > maxHp * 0.8 then
                    phase = "FASE2_BOSS"
                end

                if phase ~= lastPhase then
                    lastPhase = phase
                    local msg = (phase == "FASE1_NPC") and "Fase 1: Matando NPCs..." or "Fase 2: Boss!"
                    Library:Notification({ Name = msg, Time = 3 })
                end

                local target
                if phase == "FASE2_BOSS" then
                    target = FindBossEnemy(enemies, infiltrationName)
                else
                    target = enemies[1]
                end

                if not target or not H.IsEnemyAlive(target.uuid) then task.wait(0.2) return end

                if Flags.TeleportRaid then TeleportToTargetOrCenter(target.uuid) end

                if not H.AreAllAliveWarriorsAttacking(target.uuid) then
                    H.SendWarriorsTo(target.uuid)
                    task.wait(0.5)
                    if not H.AreAllAliveWarriorsAttacking(target.uuid) and H.IsEnemyAlive(target.uuid) then
                        task.wait(0.2)
                        return
                    end
                end

                InfiltrationCombatFollowTarget(target, isInfiltrationDone, flagCheckFn)
            end)

            if not iterOk then
                warn("[Infiltration] Erro (ignorado): " .. tostring(iterErr))
                task.wait(0.5)
            end
        end

        if conn then conn:Disconnect() conn = nil end
        if not flagCheckFn() then return "stopped" end

        if not infiltrationDone then
            Library:Notification({ Name = "Infiltration expirou.", Time = 3 })
            return "timeout"
        end

        task.wait(3)
        return "completed"
    end

    -- ============ AUTO INFILTRATION ============
    function M.StopAutoInfiltration()
        Flags.AutoInfiltration = false
        if infiltrationThread then
            task.cancel(infiltrationThread)
            infiltrationThread = nil
        end
    end

    function M.StartAutoInfiltration()
        M.StopAutoInfiltration()
        Flags.AutoInfiltration = true

        infiltrationThread = task.spawn(function()
            local function isActive() return Flags.AutoInfiltration end

            while Flags.AutoInfiltration do
                local infiltration = Flags.SelectedInfiltration or (Config.InfiltrationNames and Config.InfiltrationNames[1]) or "Rain Village"
                local tier = Flags.InfiltrationTier or "I"
                local status = M.RunSingleInfiltration(infiltration, tier, isActive)

                if not Flags.AutoInfiltration then break end
                Library:Notification({ Name = "Proxima infiltration...", Time = 2 })

                if status == "cooldown" then task.wait(2) else task.wait(3) end
            end
            print("[AutoInfiltration] Parado.")
        end)
    end

    return M
end

-- ============================================================
-- raid.lua
-- Auto Raid + combo Auto Raid+Escort.
-- O combo usa ctx.Escort.RunSingleEscort de forma "preguicosa"
-- (resolvido no momento da chamada), evitando dependencia circular.
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
    local raidThread       = nil
    local raidEscortThread = nil

    -- ============ TELEPORTE / FALLBACK ============
    local function TeleportToTargetOrCenter(uuid, raidName)
        local success = H.TeleportToEnemy(uuid)
        if not success then
            local center = Config.RaidCenterPositions[raidName]
            if center then
                H.TeleportTo(center)
                Library:Notification({ Name = "Boss longe! Indo ao centro...", Time = 2 })
            end
        end
    end

    -- ============ COLETA / CLASSIFICACAO ============
    local function GetRaidEnemiesOnly()
        local enemies = {}
        local folder = H.GetEnemiesFolder()
        if not folder then return enemies end

        pcall(function()
            for _, model in ipairs(folder:GetChildren()) do
                if model:GetAttribute("dead") == true then continue end
                if not S.getEnemy then continue end
                local ok, data = pcall(S.getEnemy, model.Name)
                if not ok or not data or not data.name then continue end
                local pos = H.GetEnemyPosition(model.Name)
                if pos and pos.X > CONST.RAID_ENEMY_MIN_X then
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
    M.GetRaidEnemiesOnly = GetRaidEnemiesOnly

    local function WaitForRaidEnemies(timeout)
        local t0 = os.clock()
        while os.clock() - t0 < timeout do
            task.wait(0.5)
            if #GetRaidEnemiesOnly() > 0 then return true end
        end
        return false
    end

    local function ClassifyEnemies(enemies, raidName)
        local npcs, intermediates, tanked, free = {}, {}, {}, {}
        for _, e in ipairs(enemies) do
            if H.IsBossName(e.name, raidName) then
                if H.HasTankMechanic(e.uuid) then
                    if H.IsBossProtected(e.uuid) then table.insert(tanked, e)
                    else table.insert(free, e) end
                else table.insert(free, e) end
            elseif H.IsIntermediateEnemy(e.name, raidName) then
                table.insert(intermediates, e)
            else
                table.insert(npcs, e)
            end
        end
        return npcs, intermediates, tanked, free
    end

    local function GetPhaseTargets(enemies, raidName)
        local npcs, intermediates, tanked, free = ClassifyEnemies(enemies, raidName)
        if #npcs          > 0 then return npcs,          "FASE1_NPC"            end
        if #intermediates > 0 then return intermediates, "FASE2_WATER_TANK"     end
        if #tanked        > 0 then return tanked,        "FASE3_BOSS_COM_TANKS" end
        if #free          > 0 then return free,          "FASE4_BOSS_LIVRE"     end
        return {}, "VAZIO"
    end
    M.GetPhaseTargets = GetPhaseTargets

    -- ============ COMBATE NUM ALVO ============
    local function RaidCombatFollowTarget(target, raidDone, phase, flagCheckFn)
        flagCheckFn = flagCheckFn or function() return Flags.AutoRaid end

        if phase == "FASE3_BOSS_COM_TANKS" then
            local lastCount = H.CountNormalTanks(target.uuid)
            while flagCheckFn() and not raidDone() and H.IsEnemyAlive(target.uuid) do
                local okI, errI = pcall(function()
                    H.WaitForWarriorsRecovery(flagCheckFn)
                    if not H.AreAllAliveWarriorsAttacking(target.uuid) then H.SendWarriorsTo(target.uuid) end
                    if Flags.TeleportRaid then H.TeleportToEnemy(target.uuid) end
                    local cur = H.CountNormalTanks(target.uuid)
                    if cur < lastCount then
                        Library:Notification({ Name = "Tank destruido! Restam: " .. cur, Time = 2 })
                        lastCount = cur
                    end
                    if H.AllTanksDestroyed(target.uuid) then
                        Library:Notification({ Name = "Boss livre!", Time = 3 })
                        return "BREAK"
                    end
                end)
                if not okI then warn("[Raid] inner: " .. tostring(errI)) end
                if okI and errI == "BREAK" then break end
                task.wait(0.25)
            end
        else
            while flagCheckFn() and not raidDone() and H.IsEnemyAlive(target.uuid) do
                local okI = pcall(function()
                    H.WaitForWarriorsRecovery(flagCheckFn)
                    if not H.AreAllAliveWarriorsAttacking(target.uuid) then H.SendWarriorsTo(target.uuid) end
                    if Flags.TeleportRaid then H.TeleportToEnemy(target.uuid) end
                end)
                if not okI then task.wait(0.5) end
                task.wait(0.25)
            end
        end
    end

    -- ============ UMA RAID COMPLETA ============
    function M.RunSingleRaid(raidName, flagCheckFn)
        Library:Notification({ Name = "Raid: " .. raidName, Time = 3 })

        local ok, result = pcall(function()
            return S.raidCreate:InvokeServer(raidName, { friendsOnly = Flags.RaidFriendsOnly, spawnNormal = false })
        end)

        if not ok or result == false or result == nil then
            Library:Notification({ Name = "Sem acesso: " .. raidName, Time = 3 })
            return "cooldown"
        end

        Library:Notification({ Name = "Raid criada! Entrando...", Time = 2 })
        task.wait(3)

        pcall(function() S.raidStart:FireServer() end)
        task.wait(2)

        if not WaitForRaidEnemies(30) then
            Library:Notification({ Name = "Raid nao iniciou, pulando...", Time = 3 })
            pcall(function() S.raidLeave:FireServer() end)
            task.wait(2)
            return "failed_start"
        end

        Library:Notification({ Name = "Raid iniciada!", Time = 2 })

        local raidDone = false
        local conn = S.clientSummary.OnClientEvent:Connect(function(raidType, data)
            if raidType ~= "boss-raids" then return end
            raidDone = true
            Flags.RaidsCompleted += 1
            if data and data.players then
                for _, pd in ipairs(data.players) do
                    if pd.userId == LocalPlayer.UserId then
                        local drops = ""
                        if pd.drops then
                            for _, d in ipairs(pd.drops) do
                                drops ..= d.id .. " x" .. d.amount .. " | "
                            end
                        end
                        Library:Notification({ Name = "Raid completa! " .. (data.title or ""), Time = 5 })
                        if drops ~= "" then
                            Library:Notification({ Name = "Drops: " .. drops:sub(1, -3), Time = 6 })
                        end
                    end
                end
            end
            task.delay(1, function()
                pcall(function() S.raidLeave:FireServer() end)
                Library:Notification({ Name = "Saiu da raid!", Time = 2 })
            end)
        end)

        local function isRaidDone() return raidDone end
        local badTargets = {}
        local lastPhase  = ""
        local timeout    = os.clock() + CONST.RAID_TIMEOUT

        while flagCheckFn() and not raidDone and os.clock() < timeout do
            local iterOk, iterErr = pcall(function()
                local enemies        = GetRaidEnemiesOnly()
                local targets, phase = GetPhaseTargets(enemies, raidName)

                if phase ~= lastPhase and phase ~= "VAZIO" then
                    local wasNPCPhase = (lastPhase == "FASE1_NPC")
                    lastPhase = phase
                    local msg = ({
                        FASE1_NPC            = "Fase 1: Matando NPCs...",
                        FASE2_WATER_TANK     = "Fase 2: Water Tanks!",
                        FASE3_BOSS_COM_TANKS = "Fase 3: Boss + Tanks!",
                        FASE4_BOSS_LIVRE     = "Fase 4: Boss livre! FOCA!",
                    })[phase] or phase
                    Library:Notification({ Name = msg, Time = 3 })

                    if wasNPCPhase and Flags.TeleportRaid and #targets > 0 then
                        local center = Config.RaidCenterPositions[raidName]
                        if center then
                            H.TeleportTo(center)
                            Library:Notification({ Name = "NPCs mortos! Indo ao boss...", Time = 2 })
                            task.wait(1)
                        end
                        local bossTarget = targets[1]

                        local spawnDeadline = os.clock() + 5
                        local bossReady = false
                        repeat
                            task.wait(0.3)
                            pcall(function()
                                local model = H.GetEnemyModel(bossTarget.uuid)
                                if model and model:GetAttribute("dead") ~= true then
                                    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
                                    if part then bossReady = true end
                                end
                            end)
                        until bossReady or os.clock() > spawnDeadline

                        H.TeleportToEnemy(bossTarget.uuid)
                        H.SendWarriorsTo(bossTarget.uuid)
                        Library:Notification({
                            Name = bossReady and ("Warriors no boss: " .. bossTarget.name) or "Forcando teleporte ao boss...",
                            Time = 2
                        })
                        task.wait(0.3)
                    end
                end

                if #targets == 0 then
                    local centerPos = Config.RaidCenterPositions[raidName]

                    if centerPos and Flags.TeleportRaid then
                        H.TeleportTo(centerPos)
                        Library:Notification({ Name = "Indo ao centro carregar o Boss...", Time = 1.5 })
                    elseif lastPhase ~= "" and lastPhase ~= "VAZIO" then
                        local raidPos = Config.RaidTeleports[raidName]
                        if raidPos and Flags.TeleportRaid then
                            H.TeleportTo(raidPos)
                            Library:Notification({ Name = "Procurando inimigos...", Time = 1.5 })
                        end
                    end

                    task.wait(1.5)
                    return
                end

                local target
                for _, t in ipairs(targets) do
                    if not badTargets[t.uuid] then target = t break end
                end
                if not target then badTargets = {} target = targets[1] end
                if not H.IsEnemyAlive(target.uuid) then task.wait(0.2) return end

                if Flags.TeleportRaid then TeleportToTargetOrCenter(target.uuid, raidName) end

                if not H.AreAllAliveWarriorsAttacking(target.uuid) then
                    H.SendWarriorsTo(target.uuid)
                    task.wait(0.5)
                    if not H.AreAllAliveWarriorsAttacking(target.uuid) and H.IsEnemyAlive(target.uuid) then
                        badTargets[target.uuid] = true
                        task.wait(0.2)
                        return
                    end
                else
                    badTargets[target.uuid] = nil
                end

                RaidCombatFollowTarget(target, isRaidDone, phase, flagCheckFn)
            end)

            if not iterOk then
                warn("[Raid] Erro (ignorado): " .. tostring(iterErr))
                task.wait(0.5)
            end
        end

        if conn then conn:Disconnect() conn = nil end
        if not flagCheckFn() then return "stopped" end

        if not raidDone then
            Library:Notification({ Name = "Raid expirou.", Time = 3 })
            return "timeout"
        end

        task.wait(3)
        return "completed"
    end

    -- ============ AUTO RAID ============
    function M.StopAutoRaid()
        Flags.AutoRaid = false
        raidThread = nil
    end

    function M.StartAutoRaid()
        M.StopAutoRaid()
        M.StopAutoRaidEscort()
        Flags.AutoRaid = true

        raidThread = task.spawn(function()
            local function isActive() return Flags.AutoRaid end
            if Flags.RaidQueueIndex > #Flags.SelectedRaids then Flags.RaidQueueIndex = 1 end

            while Flags.AutoRaid do
                if #Flags.SelectedRaids == 0 then task.wait(2) continue end
                if Flags.RaidQueueIndex > #Flags.SelectedRaids then Flags.RaidQueueIndex = 1 end

                local raid   = Flags.SelectedRaids[Flags.RaidQueueIndex]
                local status = M.RunSingleRaid(raid, isActive)

                if not Flags.AutoRaid then break end

                Flags.RaidQueueIndex += 1
                if Flags.RaidQueueIndex > #Flags.SelectedRaids then
                    Flags.RaidQueueIndex = 1
                    Library:Notification({ Name = "Fila completa! Reiniciando...", Time = 3 })
                else
                    Library:Notification({ Name = "Proxima: " .. (Flags.SelectedRaids[Flags.RaidQueueIndex] or "?"), Time = 2 })
                end

                if status == "cooldown" then task.wait(2) else task.wait(3) end
            end
            print("[AutoRaid] Parado.")
        end)
    end

    -- ============ AUTO RAID + ESCORT (COMBO) ============
    -- Ciclo: 1 raid -> 1 escort -> proxima raid -> proximo escort -> ...
    function M.StopAutoRaidEscort()
        Flags.AutoRaidEscort = false
        raidEscortThread = nil
    end

    function M.StartAutoRaidEscort()
        M.StopAutoRaid()
        if ctx.Escort and ctx.Escort.StopAutoEscort then ctx.Escort.StopAutoEscort() end
        M.StopAutoRaidEscort()
        Flags.AutoRaidEscort = true

        raidEscortThread = task.spawn(function()
            local function isActive() return Flags.AutoRaidEscort end

            while Flags.AutoRaidEscort do
                -- ===== 1 RAID =====
                if #Flags.SelectedRaids > 0 then
                    if Flags.RaidQueueIndex > #Flags.SelectedRaids then Flags.RaidQueueIndex = 1 end
                    local raid = Flags.SelectedRaids[Flags.RaidQueueIndex]

                    M.RunSingleRaid(raid, isActive)
                    if not Flags.AutoRaidEscort then break end

                    Flags.RaidQueueIndex += 1
                    if Flags.RaidQueueIndex > #Flags.SelectedRaids then Flags.RaidQueueIndex = 1 end
                else
                    Library:Notification({ Name = "Nenhuma raid selecionada!", Time = 3 })
                end

                if not Flags.AutoRaidEscort then break end
                task.wait(2)

                -- ===== 1 ESCORT =====
                if #Flags.SelectedEscortTiers > 0 then
                    if Flags.EscortQueueIndex > #Flags.SelectedEscortTiers then Flags.EscortQueueIndex = 1 end
                    local tier = Flags.SelectedEscortTiers[Flags.EscortQueueIndex]

                    -- resolvido aqui (lazy) -> sem dependencia circular no load
                    if ctx.Escort and ctx.Escort.RunSingleEscort then
                        ctx.Escort.RunSingleEscort(tier, isActive)
                    end
                    if not Flags.AutoRaidEscort then break end

                    Flags.EscortQueueIndex += 1
                    if Flags.EscortQueueIndex > #Flags.SelectedEscortTiers then Flags.EscortQueueIndex = 1 end
                else
                    Library:Notification({ Name = "Nenhum tier de escort selecionado!", Time = 3 })
                    task.wait(5)
                end

                task.wait(2)
            end
            print("[AutoRaidEscort] Parado.")
        end)
    end

    return M
end

-- ============================================================
-- invasion.lua
-- Auto Invasion + Auto Infiltration
-- ============================================================

return function(ctx)

local S         = ctx.Services
local H         = ctx.Helpers
local Flags     = ctx.Flags
local Library   = ctx.Library
local Config    = ctx.Config
local CONST     = Config.CONST
local LocalPlayer = ctx.LocalPlayer

local M = {}

local invasionThread     = nil
local infiltrationThread = nil

local INVASION_CENTER = Vector3.new(5049.59, 6018.97, -21.29)

-- Raio (em studs) ao redor do INVASION_CENTER considerado "dentro da invasion".
-- Sem isso, qualquer inimigo vivo em OUTRO lugar do mapa impede o contador de
-- zerar, e o script nunca detecta que a invasion acabou (fica esperando o
-- jogo te kickar sozinho, ~30s).
local INVASION_DETECT_RADIUS = 150

-- Tempo (em segundos) sem nenhum inimigo dentro do raio para considerar a
-- invasion encerrada e sair imediatamente (como fallback, priorizando client.summary).
local INVASION_EMPTY_THRESHOLD = 35

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
    if not S.invasionVoteCard then
        warn("[Invasion] Remote S.invasionVoteCard nao resolvido! Auto-vote estara inativo.")
    end
    return true
end

-- ============ SAIR FORÇADO ============
local function ForceLeaveInvasion()
    pcall(function() S.invasionLeave:FireServer() end)
    -- Dispara o remote cru fornecido para garantir a saida imediata,
    -- independente do que S.invasionLeave estiver apontando.
    pcall(function()
        game:GetService("ReplicatedStorage").rbxts_include.node_modules["@rbxts"].remo.src.container["invasions.leaveInvasion"]:FireServer()
    end)
end

-- ============ COLETA / CLASSIFICACAO ============
-- FIX: agora filtra por distancia ao INVASION_CENTER. Antes pegava
-- QUALQUER inimigo vivo no mapa inteiro, o que impedia o contador de
-- chegar a zero quando a invasion realmente acabava.
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
            if pos and (pos - INVASION_CENTER).Magnitude <= INVASION_DETECT_RADIUS then
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

-- NOVO: checa se ja existe uma invasion rolando ANTES de tentar criar uma.
-- Evita o spam de invasionCreate quando a deteccao de "acabou" falha e o
-- loop externo tenta comecar outra sem ter saido da anterior.
local function IsInvasionAlreadyActive()
    return #GetInvasionEnemiesOnly() > 0
end
M.IsInvasionAlreadyActive = IsInvasionAlreadyActive

-- ============ COMBATE NUM ALVO (INVASION) ============
local function InvasionCombatFollowTarget(target, invasionDone, flagCheckFn)
    if not H then return end
    flagCheckFn = flagCheckFn or function() return Flags.AutoInvasion end

    while flagCheckFn() and not invasionDone() and H.IsEnemyAlive(target.uuid) do
        local okI = pcall(function()
            H.WaitForWarriorsRecovery(flagCheckFn)
            if not H.AreAllAliveWarriorsAttacking(target.uuid) then H.SendWarriorsTo(target.uuid) end
            if Flags.TeleportRaid then
                local nearest = H.GetNearestAliveEnemy()
                local tpTarget = nearest and nearest.uuid or target.uuid
                H.TeleportToEnemy(tpTarget)
            end
        end)
        if not okI then task.wait(0.5) end
        task.wait(0.25)
    end
end

local CARD_SCORES = {
    ["Overflowing Wealth III"] = 100,
    ["Overflowing Wealth II"]  = 99,
    ["Overflowing Wealth I"]   = 98,
    ["Warrior Blessing III"]   = 80,
    ["Boss Killer III"]        = 80,
    ["Espionage"]              = 80,
    ["Warrior Blessing II"]    = 70,
    ["Boss Killer II"]         = 70,
    ["Warrior Blessing I"]     = 60,
    ["Boss Killer I"]          = 60,
}

local function FindStringsInTable(tbl, list)
    for _, v in pairs(tbl) do
        if type(v) == "string" then
            table.insert(list, v)
        elseif type(v) == "table" then
            FindStringsInTable(v, list)
        end
    end
end

local function ScanPlayerGuiForVoteCards()
    local foundCards = {}
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return foundCards end

    local function search(object)
        if object:IsA("TextLabel") or object:IsA("TextButton") then
            local text = object.Text
            if type(text) == "string" and text ~= "" then
                for pattern in pairs(CARD_SCORES) do
                    if string.find(string.lower(text), string.lower(pattern)) then
                        local remoteName = text
                        if not string.find(string.lower(remoteName), "^invasion ") then
                            remoteName = "Invasion " .. remoteName
                        end
                        remoteName = string.gsub(remoteName, "%s+", " ")
                        remoteName = string.match(remoteName, "^%s*(.-)%s*$")
                        table.insert(foundCards, remoteName)
                        break
                    end
                end
            end
        end
        for _, child in ipairs(object:GetChildren()) do
            search(child)
        end
    end

    search(playerGui)
    return foundCards
end

-- ============ INVASION UNICA ============
function M.RunSingleInvasion(invasionName, flagCheckFn)
    if not CheckRemotes() then
        Library:Notification({ Name = "Remotes nao carregaram!", Time = 3 })
        return "failed_start"
    end

    -- NOVO: se ja tem uma invasion rolando dentro do raio, NAO cria outra -
    -- so entra direto no loop de combate da que ja existe.
    local alreadyActive = IsInvasionAlreadyActive()

    if alreadyActive then
        Library:Notification({ Name = "Invasion ja ativa! Entrando no combate...", Time = 2 })
    else
        Library:Notification({ Name = "Invasion: " .. invasionName, Time = 3 })

        -- Melhoria para evitar o SPAM do remote se ele nao retornar True/False certinho
        local ok, result = pcall(function()
            if S.invasionCreate.InvokeServer then
                return S.invasionCreate:InvokeServer(invasionName, { friendsOnly = Flags.InvasionFriendsOnly })
            else
                S.invasionCreate:FireServer(invasionName, { friendsOnly = Flags.InvasionFriendsOnly })
                return true
            end
        end)

        if not ok then
            Library:Notification({ Name = "Erro ao tentar criar: " .. invasionName, Time = 3 })
            return "cooldown"
        end

        Library:Notification({ Name = "Invasion criada! Entrando...", Time = 2 })
        task.wait(3)

        pcall(function() S.lobbiesStart:FireServer() end)
        task.wait(2)

        -- Tempo de espera de 60 segundos (evita spammar falhas se a net ou mapa demorar)
        if not WaitForInvasionEnemies(60) then
            Library:Notification({ Name = "Invasion nao iniciou, abortando loop...", Time = 3 })
            ForceLeaveInvasion()
            task.wait(2)
            return "failed_start"
        end

        Library:Notification({ Name = "Invasion iniciada!", Time = 2 })
    end

    local invasionDone = false
    local conn = nil
    local voteConn = nil

    if S.clientSummary then
        conn = S.clientSummary.OnClientEvent:Connect(function(raidType, data)
            if type(raidType) == "string" and string.find(string.lower(raidType), "invasion") then
                invasionDone = true
                Flags.InvasionsCompleted = (Flags.InvasionsCompleted or 0) + 1
                Library:Notification({ Name = "Invasion completa (Evento Recebido)!", Time = 5 })
                -- FIX: sai IMEDIATAMENTE, sem esperar 1s de delay
                ForceLeaveInvasion()
                Library:Notification({ Name = "Saiu da invasion!", Time = 2 })
            end
        end)
    end

    local lastVoteTime = 0
    local function performVote(choice)
        if os.clock() - lastVoteTime < 3 then return end
        lastVoteTime = os.clock()
        Library:Notification({ Name = "Voto automatico: " .. choice, Time = 3 })
        pcall(function()
            S.invasionVoteCard:FireServer(choice)
        end)
    end

    if S.invasionVoteCard then
        voteConn = S.invasionVoteCard.OnClientEvent:Connect(function(...)
            local args = { ... }
            local strings = {}
            for _, arg in ipairs(args) do
                if type(arg) == "string" then
                    table.insert(strings, arg)
                elseif type(arg) == "table" then
                    FindStringsInTable(arg, strings)
                end
            end

            local candidates = {}
            local highestScore = -1

            for _, cardName in ipairs(strings) do
                local score = -1
                for pattern, val in pairs(CARD_SCORES) do
                    if string.find(string.lower(cardName), string.lower(pattern)) then
                        score = val
                        break
                    end
                end

                if score > -1 then
                    if score > highestScore then
                        highestScore = score
                        candidates = { cardName }
                    elseif score == highestScore then
                        table.insert(candidates, cardName)
                    end
                end
            end

            if #candidates > 0 then
                local index = math.random(1, #candidates)
                local choice = candidates[index]
                performVote(choice)
            end
        end)
    end

    local function isInvasionDone() return invasionDone end
    local timeout    = os.clock() + CONST.RAID_TIMEOUT
    local emptyTimer = 0

    while flagCheckFn() and not invasionDone and os.clock() < timeout do
        local iterOk, iterErr = pcall(function()
            -- === AUTO VOTE CARD SCANNER ===
            if S.invasionVoteCard then
                local guiCards = ScanPlayerGuiForVoteCards()
                if #guiCards > 0 then
                    local candidates = {}
                    local highestScore = -1

                    for _, cardName in ipairs(guiCards) do
                        local score = -1
                        for pattern, val in pairs(CARD_SCORES) do
                            if string.find(string.lower(cardName), string.lower(pattern)) then
                                score = val
                                break
                            end
                        end

                        if score > -1 then
                            if score > highestScore then
                                highestScore = score
                                candidates = { cardName }
                            elseif score == highestScore then
                                table.insert(candidates, cardName)
                            end
                        end
                    end

                    if #candidates > 0 then
                        local index = math.random(1, #candidates)
                        local choice = candidates[index]
                        performVote(choice)
                    end
                end
            end

            local enemies = GetInvasionEnemiesOnly()

            -- === CHECAGEM DE INIMIGOS E TEMPO DE SAIDA ===
            if #enemies == 0 then
                emptyTimer = emptyTimer + 0.5
                if emptyTimer >= INVASION_EMPTY_THRESHOLD then
                    Library:Notification({ Name = "Invasion finalizada! Saindo imediatamente...", Time = 3 })
                    invasionDone = true
                    ForceLeaveInvasion()
                    return
                end

                task.wait(0.5)
                return
            else
                -- Reseta o timer caso os inimigos nascam de novo (proxima onda)
                emptyTimer = 0
            end

            local target = enemies[1]
            if not H.IsEnemyAlive(target.uuid) then task.wait(0.2) return end

            if Flags.TeleportRaid then
                local nearest = H.GetNearestAliveEnemy()
                local tpTarget = nearest and nearest.uuid or target.uuid
                H.TeleportToEnemy(tpTarget)
            end

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
    if voteConn then voteConn:Disconnect() voteConn = nil end
    if not flagCheckFn() then return "stopped" end

    if not invasionDone then
        Library:Notification({ Name = "Invasion expirou.", Time = 3 })
        ForceLeaveInvasion()
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
    local bossNames = Config.InfiltrationBossNames and Config.InfiltrationBossNames[infiltrationName]
    if bossNames then
        for _, e in ipairs(enemies) do
            for _, bossName in ipairs(bossNames) do
                if e.name == bossName then return e end
            end
        end
    end

    if #enemies == 0 then return nil end
    local boss = enemies[1]
    for _, e in ipairs(enemies) do
        if e.maxHp > boss.maxHp then boss = e end
    end
    return boss
end

-- FIX: removido o fallback errado para INVASION_CENTER. Infiltration
-- acontece em outro lugar do mapa - teleportar pro centro da invasion
-- jogava o personagem num lugar completamente errado quando o teleporte
-- direto pro inimigo falhava (ex: inimigo fora de stream/range).
-- Agora so tenta de novo no proximo tick, sem teleportar pra coordenada
-- nenhuma "as ciegas".
local function SafeTeleportToInfiltrationTarget(uuid)
    if not H then return end
    H.TeleportToEnemy(uuid)
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
        if S.infiltrationCreate.InvokeServer then
            return S.infiltrationCreate:InvokeServer(infiltrationName, tier, { friendsOnly = Flags.InfiltrationFriendsOnly })
        else
            S.infiltrationCreate:FireServer(infiltrationName, tier, { friendsOnly = Flags.InfiltrationFriendsOnly })
            return true
        end
    end)

    if not ok then
        Library:Notification({ Name = "Erro ao tentar criar: " .. infiltrationName, Time = 3 })
        return "cooldown"
    end

    Library:Notification({ Name = "Infiltration criada! Entrando...", Time = 2 })
    task.wait(3)

    pcall(function() S.lobbiesStart:FireServer() end)
    task.wait(2)

    if not WaitForInfiltrationEnemies(60) then
        Library:Notification({ Name = "Infiltration nao iniciou, pulando...", Time = 3 })
        pcall(function() S.lobbiesLeave:FireServer() end)
        task.wait(2)
        return "failed_start"
    end

    Library:Notification({ Name = "Infiltration iniciada!", Time = 2 })

    local infiltrationDone = false
    local conn = nil

    if S.clientSummary then
        conn = S.clientSummary.OnClientEvent:Connect(function(raidType, data)
            if type(raidType) == "string" and string.find(string.lower(raidType), "infiltrations") then
                infiltrationDone = true
                Flags.InfiltrationsCompleted = (Flags.InfiltrationsCompleted or 0) + 1
                Library:Notification({ Name = "Infiltration completa!", Time = 5 })
                task.delay(1, function()
                    pcall(function() S.lobbiesLeave:FireServer() end)
                    Library:Notification({ Name = "Saiu da infiltration!", Time = 2 })
                end)
            end
        end)
    end

    local function isInfiltrationDone() return infiltrationDone end
    local lastPhase  = ""
    local timeout    = os.clock() + CONST.RAID_TIMEOUT
    local emptyTimer = 0

    while flagCheckFn() and not infiltrationDone and os.clock() < timeout do
        local iterOk, iterErr = pcall(function()
            local enemies = GetInfiltrationEnemiesOnly()

            if #enemies == 0 then
                emptyTimer = emptyTimer + 0.5
                if emptyTimer >= 15 then
                    Library:Notification({ Name = "Infiltration finalizada! Saindo imediatamente...", Time = 3 })
                    infiltrationDone = true
                    pcall(function() S.lobbiesLeave:FireServer() end)
                    return
                end
                Library:Notification({ Name = "Procurando inimigos...", Time = 1.5 })
                task.wait(1.5)
                return
            else
                emptyTimer = 0
            end

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

            if Flags.TeleportRaid then SafeTeleportToInfiltrationTarget(target.uuid) end

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
            local tier   = Flags.InfiltrationTier or "I"
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

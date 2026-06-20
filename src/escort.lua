-- ============================================================
-- escort.lua
-- Auto Escort. Expoe RunSingleEscort (reutilizado pelo combo
-- em raid.lua) e Start/Stop.
-- ============================================================

return function(ctx)
    local S       = ctx.Services
    local H       = ctx.Helpers
    local Flags   = ctx.Flags
    local Library = ctx.Library
    local CONST   = ctx.Config.CONST
    local LocalPlayer = ctx.LocalPlayer

    local M = {}
    local escortThread = nil

    -- ============ HELPERS DO MAPA DO ESCORT ============
    local function GetEscortMap()
        local ok, result = pcall(function()
            local world = workspace:FindFirstChild("World")
            local map   = world and world:FindFirstChild("Map")
            if not map then return nil end
            for _, child in ipairs(map:GetChildren()) do
                if child.Name:sub(1, 7) == "escort-" then return child end
            end
            return nil
        end)
        return ok and result or nil
    end

    local function GetCartPosition()
        local ok, result = pcall(function()
            local escortMap = GetEscortMap()
            if not escortMap then return nil end
            local cart = escortMap:FindFirstChild("Cart")
            if not cart then return nil end
            local part = cart.PrimaryPart or cart:FindFirstChildWhichIsA("BasePart", true)
            return part and part.Position or nil
        end)
        return ok and result or nil
    end

    local function GetCheckpointPosition(index)
        local ok, result = pcall(function()
            local escortMap   = GetEscortMap()
            if not escortMap then return nil end
            local checkpoints = escortMap:FindFirstChild("Checkpoints")
            if not checkpoints then return nil end
            local cp = checkpoints:FindFirstChild(tostring(index))
            if not cp then return nil end
            local part = cp.PrimaryPart or cp:FindFirstChildWhichIsA("BasePart", true)
            return part and part.Position or nil
        end)
        return ok and result or nil
    end

    -- Conta dinamicamente quantos checkpoints o mapa tem (em vez de chumbar 4)
    local function CountCheckpoints()
        local ok, result = pcall(function()
            local escortMap = GetEscortMap()
            if not escortMap then return 4 end
            local checkpoints = escortMap:FindFirstChild("Checkpoints")
            if not checkpoints then return 4 end
            local n = 0
            for _, c in ipairs(checkpoints:GetChildren()) do
                if tonumber(c.Name) then n += 1 end
            end
            return n > 0 and n or 4
        end)
        return ok and result or 4
    end

    local function GetEnemiesNearCart(radius)
        radius = radius or 80
        local enemies = {}
        local cartPos = GetCartPosition()
        if not cartPos then return enemies end

        local folder = H.GetEnemiesFolder()
        if not folder then return enemies end

        pcall(function()
            for _, model in ipairs(folder:GetChildren()) do
                if model:GetAttribute("dead") == true then continue end
                if not S.getEnemy then continue end
                local ok, data = pcall(S.getEnemy, model.Name)
                if not ok or not data or not data.name then continue end

                local uuid = model.Name
                if not H.IsEnemyAlive(uuid) then continue end

                local pos = H.GetEnemyPosition(uuid)
                if not pos then continue end

                if (pos - cartPos).Magnitude <= radius then
                    table.insert(enemies, {
                        uuid = uuid, name = data.name,
                        hp = data.stats and data.stats.health or 0,
                    })
                end
            end
        end)

        return enemies
    end

    -- ============ UM ESCORT COMPLETO ============
    -- flagCheckFn: retorna se deve continuar (permite reuso pelo combo)
    function M.RunSingleEscort(tier, flagCheckFn)
        Library:Notification({ Name = "Criando escort (" .. tostring(tier) .. ")...", Time = 2 })
        local ok, result = pcall(function()
            return S.escortCreate:InvokeServer("Journeys End", { friendsOnly = Flags.EscortFriendsOnly, tier = tier })
        end)

        if not ok or result == nil or result == false then
            Library:Notification({ Name = "Falha ao criar escort!", Time = 3 })
            return "failed"
        end

        Library:Notification({ Name = "Escort criado! Iniciando...", Time = 2 })
        task.wait(2)
        pcall(function() S.raidStart:FireServer() end)
        task.wait(2)

        local mapTimeout = os.clock() + 20
        repeat task.wait(0.5) until GetEscortMap() ~= nil or os.clock() > mapTimeout

        if not GetEscortMap() then
            Library:Notification({ Name = "Mapa do escort nao encontrado, pulando...", Time = 3 })
            pcall(function() S.escortLeave:FireServer() end)
            return "failed"
        end

        Library:Notification({ Name = "Escort iniciado! Seguindo carrinho...", Time = 2 })

        local escortDone = false
        local conn = S.clientSummary.OnClientEvent:Connect(function(eventType, data)
            if eventType ~= "escort" then return end
            escortDone = true
            Flags.EscortsCompleted += 1
            if data and data.players then
                for _, pd in ipairs(data.players) do
                    if pd.userId == LocalPlayer.UserId then
                        local drops = ""
                        if pd.drops then
                            for _, d in ipairs(pd.drops) do
                                drops ..= d.id .. " x" .. d.amount .. " | "
                            end
                        end
                        Library:Notification({ Name = (data.title or "Escort") .. "! " .. (data.description or ""), Time = 5 })
                        if drops ~= "" then
                            Library:Notification({ Name = "Drops: " .. drops:sub(1, -3), Time = 6 })
                        end
                    end
                end
            end
            task.delay(1, function()
                pcall(function() S.escortLeave:FireServer() end)
                Library:Notification({ Name = "Saiu do escort!", Time = 2 })
            end)
        end)

        local maxCheckpoints    = CountCheckpoints()
        local escortTimeout     = os.clock() + CONST.ESCORT_TIMEOUT
        local currentCheckpoint = 1
        local lockedUUID        = ""
        local lockedName        = ""
        local lastSendTime      = 0

        while flagCheckFn() and not escortDone and os.clock() < escortTimeout do
            local iterOk, iterErr = pcall(function()

                if lockedUUID ~= "" then
                    if not H.IsEnemyAlive(lockedUUID) then
                        Library:Notification({ Name = lockedName .. " morreu! Proximo...", Time = 1 })
                        lockedUUID   = ""
                        lockedName   = ""
                        lastSendTime = 0
                        task.wait(0.3)
                        return
                    end

                    H.WaitForWarriorsRecovery(flagCheckFn)
                    H.TeleportToEnemy(lockedUUID)

                    local now = os.clock()
                    if now - lastSendTime >= 1.0 then
                        H.SendWarriorsTo(lockedUUID)
                        lastSendTime = now
                    end

                    task.wait(0.25)
                    return
                end

                local nearEnemies = GetEnemiesNearCart(CONST.ESCORT_ENEMY_RADIUS)

                if #nearEnemies > 0 then
                    lockedUUID   = nearEnemies[1].uuid
                    lockedName   = nearEnemies[1].name
                    lastSendTime = 0
                    Library:Notification({ Name = "Focando: " .. lockedName .. " (" .. #nearEnemies .. " total)", Time = 2 })

                    H.WaitForWarriorsRecovery(flagCheckFn)
                    H.TeleportToEnemy(lockedUUID)
                    H.SendWarriorsTo(lockedUUID)
                    lastSendTime = os.clock()
                    task.wait(0.25)
                else
                    local cartPos = GetCartPosition()
                    if cartPos then
                        H.TeleportTo(cartPos + Vector3.new(0, 4, 0))
                    else
                        local cpPos = GetCheckpointPosition(currentCheckpoint)
                        if cpPos then
                            H.TeleportTo(cpPos + Vector3.new(0, 4, 0))
                            Library:Notification({ Name = "Indo ao checkpoint " .. currentCheckpoint .. "...", Time = 2 })
                            currentCheckpoint = math.min(currentCheckpoint + 1, maxCheckpoints)
                        end
                    end
                    task.wait(0.5)
                end
            end)

            if not iterOk then
                warn("[Escort] Erro: " .. tostring(iterErr))
                task.wait(0.5)
            end
        end

        if conn then conn:Disconnect() conn = nil end
        if not flagCheckFn() then return "stopped" end

        if not escortDone then
            Library:Notification({ Name = "Escort expirou.", Time = 3 })
            pcall(function() S.escortLeave:FireServer() end)
            task.wait(2)
            return "timeout"
        end

        -- garante que o servidor processou a saida antes de criar a proxima
        task.wait(3)
        return "completed"
    end

    -- ============ AUTO ESCORT ============
    function M.StopAutoEscort()
        Flags.AutoEscort = false
        escortThread = nil
    end

    function M.StartAutoEscort()
        M.StopAutoEscort()
        if ctx.Raid and ctx.Raid.StopAutoRaidEscort then ctx.Raid.StopAutoRaidEscort() end
        Flags.AutoEscort = true

        escortThread = task.spawn(function()
            local function isActive() return Flags.AutoEscort end
            while Flags.AutoEscort do
                M.RunSingleEscort(Flags.EscortTier, isActive)
                if not Flags.AutoEscort then break end
                task.wait(3)
            end
            print("[AutoEscort] Parado.")
        end)
    end

    return M
end

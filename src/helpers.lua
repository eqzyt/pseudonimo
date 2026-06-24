-- ============================================================
-- helpers.lua
-- Funcoes utilitarias compartilhadas (workspace, enemy map,
-- warriors, teleporte). Recebe ctx e retorna a tabela H.
-- ============================================================

return function(ctx)
    local S           = ctx.Services
    local Flags       = ctx.Flags
    local Library     = ctx.Library
    local LocalPlayer = ctx.LocalPlayer

    local H = {}

    -- ============ WORKSPACE ============
    function H.GetEnemiesFolder()
        local ok, result = pcall(function()
            local world = workspace:FindFirstChild("World")
            return world and world:FindFirstChild("Enemies") or nil
        end)
        return ok and result or nil
    end

    function H.GetEnemyModel(uuid)
        if not uuid or uuid == "" then return nil end
        local ok, result = pcall(function()
            local folder = H.GetEnemiesFolder()
            return folder and folder:FindFirstChild(uuid) or nil
        end)
        return ok and result or nil
    end

    function H.GetEnemyPosition(uuid)
        local ok, result = pcall(function()
            local model = H.GetEnemyModel(uuid)
            if not model then return nil end
            local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
            return part and part.Position or nil
        end)
        return ok and result or nil
    end

    function H.IsEnemyAlive(uuid)
        if not uuid or uuid == "" then return false end
        local ok, result = pcall(function()
            local model = H.GetEnemyModel(uuid)
            if not model then return false end
            if model:GetAttribute("dead") == true then return false end
            if not S.getEnemy then return false end
            local ok2, data = pcall(S.getEnemy, uuid)
            if not ok2 or not data then return false end
            if data.flags and data.flags.dead and data.flags.dead.state then return false end
            local hp = data.stats and data.stats.health or 0
            return hp > 0
        end)
        return ok and result or false
    end

    -- ============ TELEPORT ============
    function H.TeleportTo(pos)
        if not pos then return end
        pcall(function()
            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
            if hrp then
                hrp.CFrame = CFrame.new(pos)
                hrp.Velocity = Vector3.new(0, 0.05, 0)
                pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0, 0.05, 0) end)
                if hum then
                    hum:Move(Vector3.new(0, 0, -0.05))
                end
            end
        end)
    end

    function H.TeleportToEnemy(uuid)
        local ok, result = pcall(function()
            local pos = H.GetEnemyPosition(uuid)
            if not pos then return false end
            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
            if not hrp then return false end
            hrp.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
            hrp.Velocity = Vector3.new(0, 0.05, 0)
            pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0, 0.05, 0) end)
            if hum then
                hum:Move(Vector3.new(0, 0, -0.05))
            end
            return true
        end)
        return ok and result or false
    end

    -- ============ WARRIORS ============
    function H.GetMyWarriorIDs()
        local ids = {}
        if not S.getPlayerData then return ids end
        local ok, data = pcall(S.getPlayerData, S.USER_KEY)
        if not ok or not data or not data.equippedWarriors then return ids end
        for slot = 1, 20 do
            local id = data.equippedWarriors[tostring(slot)]
            if id and id ~= "" then table.insert(ids, id) end
        end
        return ids
    end

    function H.GetAllMyWarriors()
        if not S.getWarriorsOfOwner then return nil end
        local ok, data = pcall(S.getWarriorsOfOwner, S.USER_KEY)
        return (ok and data) or nil
    end

    -- Verifica se TODOS os warriors VIVOS estao atacando o uuid
    function H.AreAllAliveWarriorsAttacking(uuid)
        local ok, result = pcall(function()
            local warriors = H.GetAllMyWarriors()
            if not warriors then return false end
            local ids = H.GetMyWarriorIDs()
            if #ids == 0 then return false end

            local anyAlive = false
            for _, id in ipairs(ids) do
                local w = warriors[id]
                if w and w.stats and (w.stats.health or 0) > 0 then
                    anyAlive = true
                    if not (w.flags and w.flags.target == uuid) then
                        return false
                    end
                end
            end

            if not anyAlive then return false end
            return true
        end)
        return ok and result or false
    end

    function H.AllWarriorsKO()
        local ok, result = pcall(function()
            local warriors = H.GetAllMyWarriors()
            if not warriors then return false end
            local ids = H.GetMyWarriorIDs()
            if #ids == 0 then return false end
            for _, id in ipairs(ids) do
                local w = warriors[id]
                if w and w.stats and (w.stats.health or 0) > 0 then
                    return false
                end
            end
            return true
        end)
        return ok and result or false
    end

    function H.SendWarriorsTo(uuid)
        if not uuid or uuid == "" then return false end
        if not S.sendAndRetreat then return false end
        local ids = H.GetMyWarriorIDs()
        if #ids == 0 then return false end
        local ok, err = pcall(function() S.sendAndRetreat:fire(uuid, ids) end)
        if not ok then warn("[SendWarriorsTo] " .. tostring(err)) return false end
        return true
    end

    -- Espera warriors revivendo (usado por raid e escort)
    function H.WaitForWarriorsRecovery(flagCheckFn)
        if H.AllWarriorsKO() then
            Library:Notification({ Name = "Warriors KO! Aguardando...", Time = 3 })
            local t0 = os.clock()
            repeat task.wait(1)
            until not H.AllWarriorsKO()
                or os.clock() - t0 > ctx.Config.CONST.WARRIOR_RECOVERY_TIMEOUT
                or not flagCheckFn()
        end
    end

    -- ============ ENEMY MAP ============
    H.nameToUUID = {}

    function H.RefreshEnemyMap()
        H.nameToUUID = {}

        if S.allEnemies then
            local ok, all = pcall(S.allEnemies)
            if ok and all then
                for uuid, data in pairs(all) do
                    if data and data.name and data.name ~= "" then
                        local dead = data.flags and data.flags.dead and data.flags.dead.state
                        if not dead and (data.stats and (data.stats.health or 0) > 0) then
                            if not H.nameToUUID[data.name] then H.nameToUUID[data.name] = {} end
                            table.insert(H.nameToUUID[data.name], uuid)
                        end
                    end
                end
            end
        end

        local folder = H.GetEnemiesFolder()
        if folder then
            pcall(function()
                for _, model in ipairs(folder:GetChildren()) do
                    if model:GetAttribute("dead") == true then continue end
                    if not S.getEnemy then continue end
                    local ok, data = pcall(S.getEnemy, model.Name)
                    if ok and data and data.name and data.name ~= "" then
                        local dead = data.flags and data.flags.dead and data.flags.dead.state
                        if not dead and (data.stats and (data.stats.health or 0) > 0) then
                            if not H.nameToUUID[data.name] then H.nameToUUID[data.name] = {} end
                            local found = false
                            for _, id in ipairs(H.nameToUUID[data.name]) do
                                if id == model.Name then found = true break end
                            end
                            if not found then table.insert(H.nameToUUID[data.name], model.Name) end
                        end
                    end
                end
            end)
        end
    end

    function H.GetEnemyNames()
        H.RefreshEnemyMap()
        local seen  = {}
        local names = {}
        for name in pairs(H.nameToUUID) do
            if not seen[name] then
                seen[name] = true
                table.insert(names, name)
            end
        end
        for _, name in ipairs(ctx.Config.KnownEnemyNames) do
            if not seen[name] then
                seen[name] = true
                table.insert(names, name)
            end
        end
        table.sort(names)
        return names
    end

    function H.SyncSelectedFromToggles()
        local sel = {}
        for name, active in pairs(ctx.EnemyToggles) do
            if active then table.insert(sel, name) end
        end
        Flags.SelectedEnemies = sel
    end

    -- ============ CANDIDATOS POR DISTANCIA ============
    function H.GetNearestAliveEnemy()
        local folder = H.GetEnemiesFolder()
        if not folder then return nil end

        local best     = nil
        local bestDist = math.huge

        pcall(function()
            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            for _, model in ipairs(folder:GetChildren()) do
                if model:GetAttribute("dead") == true then continue end
                if not S.getEnemy then continue end

                local ok, data = pcall(S.getEnemy, model.Name)
                if not ok or not data or not data.name then continue end

                local uuid = model.Name
                if not H.IsEnemyAlive(uuid) then continue end

                local pos = H.GetEnemyPosition(uuid)
                if not pos then continue end

                local dist = (hrp.Position - pos).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    best = { uuid = uuid, name = data.name, dist = dist }
                end
            end
        end)

        return best
    end

    function H.GetCandidatesByDistance(selectedNames)
        local candidates = {}
        local folder = H.GetEnemiesFolder()
        if not folder then return candidates end

        pcall(function()
            for _, model in ipairs(folder:GetChildren()) do
                if model:GetAttribute("dead") == true then continue end
                if not S.getEnemy then continue end
                local ok, data = pcall(S.getEnemy, model.Name)
                if not ok or not data or not data.name then continue end

                local selected = false
                for _, n in ipairs(selectedNames) do
                    if data.name == n then selected = true break end
                end
                if not selected then continue end

                local uuid = model.Name
                if not H.IsEnemyAlive(uuid) then continue end

                local pos  = H.GetEnemyPosition(uuid)
                local char = LocalPlayer.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                local dist = (pos and hrp) and (hrp.Position - pos).Magnitude or math.huge

                table.insert(candidates, { uuid = uuid, name = data.name, dist = dist })
            end
        end)

        table.sort(candidates, function(a, b)
            return (a.dist or math.huge) < (b.dist or math.huge)
        end)
        return candidates
    end

    -- ============ TANK HELPERS ============
    function H.CountNormalTanks(uuid)
        local ok, result = pcall(function()
            local model = H.GetEnemyModel(uuid)
            if not model then return 0 end
            local folder = model:FindFirstChild("Normal")
            if not folder then return 0 end
            local n = 0
            for _, c in ipairs(folder:GetChildren()) do
                if c.Name:lower():find("circle") or c.Name:lower():find("tank") then n += 1 end
            end
            return n
        end)
        return ok and result or 0
    end

    function H.HasTankMechanic(uuid)
        local ok, result = pcall(function()
            local model = H.GetEnemyModel(uuid)
            if not model then return false end
            return model:FindFirstChild("Normal") ~= nil or model:FindFirstChild("Broken") ~= nil
        end)
        return ok and result or false
    end

    function H.IsBossProtected(uuid)  return H.CountNormalTanks(uuid) > 0  end
    function H.AllTanksDestroyed(uuid) return H.CountNormalTanks(uuid) == 0 end

    function H.IsBossName(name, raidName)
        if not name or not raidName then return false end
        local bosses = ctx.Config.RaidBossNames[raidName] or {}
        local lower  = name:lower()
        for _, b in ipairs(bosses) do
            if lower == b:lower() then return true end
        end
        return false
    end

    function H.IsIntermediateEnemy(name, raidName)
        if not name or not raidName then return false end
        local list = ctx.Config.RaidIntermediateEnemies[raidName] or {}
        for _, n in ipairs(list) do
            if name:lower() == n:lower() then return true end
        end
        return false
    end

    -- ============ UTIL ============
    -- Parser generico para dropdowns multi-select
    function H.ParseMultiSelect(value, allItems, fallback)
        local sel = {}
        if type(value) == "table" then
            local isDict = false
            for k, v in pairs(value) do
                if type(k) == "string" and type(v) == "boolean" then isDict = true break end
            end
            if isDict then
                for _, item in ipairs(allItems) do
                    if value[item] then table.insert(sel, item) end
                end
            else
                for _, n in ipairs(value) do table.insert(sel, n) end
            end
        elseif type(value) == "string" and value ~= "" then
            table.insert(sel, value)
        end
        if #sel == 0 then sel = { fallback } end
        return sel
    end

    return H
end

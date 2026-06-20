-- ============================================================
-- combat.lua
-- Auto Attack + Auto Ultimate.
-- Retorna funcoes Start/Stop usadas pela UI.
-- ============================================================

return function(ctx)
    local S       = ctx.Services
    local H       = ctx.Helpers
    local Flags   = ctx.Flags
    local Library = ctx.Library

    local M = {}

    local attackThread   = nil
    local ultimateThread = nil

    -- ============ AUTO ATTACK ============
    function M.StopAutoAttack()
        Flags.AutoAttack = false
        attackThread = nil -- saida cooperativa no proximo while
    end

    function M.StartAutoAttack()
        M.StopAutoAttack()

        if not Flags.AttackNearest and #Flags.SelectedEnemies == 0 then
            Library:Notification({ Name = "Selecione inimigo(s) ou ative 'Atacar Mais Perto'!", Time = 3 })
            return
        end

        Flags.AutoAttack = true

        attackThread = task.spawn(function()
            local lockedUUID = ""
            local lockedName = ""

            while Flags.AutoAttack do
                local iterOk, iterErr = pcall(function()
                    H.RefreshEnemyMap()

                    if lockedUUID ~= "" then
                        if not H.IsEnemyAlive(lockedUUID) then
                            Flags.EnemiesKilled += 1
                            Library:Notification({ Name = lockedName .. " morreu! Kills: " .. Flags.EnemiesKilled, Time = 2 })
                            lockedUUID = ""
                            lockedName = ""
                            task.wait(0.3)
                            return
                        end

                        H.WaitForWarriorsRecovery(function() return Flags.AutoAttack end)

                        if Flags.TeleportAttack then H.TeleportToEnemy(lockedUUID) end

                        if not H.AreAllAliveWarriorsAttacking(lockedUUID) then
                            H.SendWarriorsTo(lockedUUID)
                        end

                        task.wait(0.25)
                        return
                    end

                    local candidate = nil

                    if Flags.AttackNearest then
                        candidate = H.GetNearestAliveEnemy()
                    else
                        local candidates = H.GetCandidatesByDistance(Flags.SelectedEnemies)
                        if #candidates > 0 then candidate = candidates[1] end
                    end

                    if not candidate then task.wait(1) return end

                    lockedUUID = candidate.uuid
                    lockedName = candidate.name
                    Library:Notification({ Name = "Atacando: " .. lockedName, Time = 2 })

                    if Flags.TeleportAttack then H.TeleportToEnemy(lockedUUID) task.wait(0.1) end
                    H.SendWarriorsTo(lockedUUID)
                    task.wait(0.5)
                end)

                if not iterOk then
                    warn("[AutoAttack] Erro: " .. tostring(iterErr))
                    task.wait(1)
                end
            end
            print("[AutoAttack] Parado.")
        end)
    end

    -- ============ AUTO ULTIMATE ============
    function M.StopAutoUltimate()
        Flags.AutoUltimate = false
        ultimateThread = nil
    end

    function M.StartAutoUltimate()
        M.StopAutoUltimate()
        Flags.AutoUltimate = true
        ultimateThread = task.spawn(function()
            while Flags.AutoUltimate do
                pcall(function() S.weaponUltimate:FireServer() end)
                task.wait(1)
            end
        end)
    end

    return M
end

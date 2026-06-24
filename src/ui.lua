-- ============================================================
-- ui.lua
-- Constroi a janela e todas as paginas/abas, conectando os
-- callbacks aos modulos (Combat / Raid / Escort / Egg / Invasion).
-- ============================================================

return function(ctx)
    local Library = ctx.Library
    local Flags   = ctx.Flags
    local Config  = ctx.Config
    local H       = ctx.Helpers
    local Combat  = ctx.Combat
    local Raid    = ctx.Raid
    local Escort  = ctx.Escort
    local Egg     = ctx.Egg
    local Invasion = ctx.Invasion
    local S       = ctx.Services
    local LocalPlayer = ctx.LocalPlayer

    local Window = Library:Window({
        Name = 'rtx <font color="rgb(126, 192, 255)">| AW III</font>',
        Rank = "user"
    })

    local CombatPage   = Window:Page({ Name = "combat"   })
    local EnemyPage    = Window:Page({ Name = "enemies"  })
    local RaidPage     = Window:Page({ Name = "raids"    })
    local TeleportPage = Window:Page({ Name = "teleport" })
    local EggPage      = Window:Page({ Name = "eggs"     })
    local StatsPage    = Window:Page({ Name = "stats"    })

    -- ===== COMBAT =====
    do
        local left  = CombatPage:Section({ Name = "auto attack", Side = 1 })
        local right = CombatPage:Section({ Name = "info",        Side = 2 })

        local atkToggle = left:Toggle({
            Name = "Auto Attack", Flag = "AutoAttack", Default = false,
            Callback = function(v)
                if v then Combat.StartAutoAttack() else Combat.StopAutoAttack() end
            end
        })
        atkToggle:Keybind({ Name = "Toggle AutoAttack", Flag = "AutoAttackKey", Default = Enum.KeyCode.F })

        left:Toggle({
            Name = "Atacar Mais Perto (Auto)", Flag = "AttackNearest", Default = false,
            Callback = function(v)
                Flags.AttackNearest = v
                if v then Library:Notification({ Name = "Modo: ataca qualquer enemy proximo!", Time = 3 }) end
                if Flags.AutoAttack then Combat.StartAutoAttack() end
            end
        })

        left:Toggle({
            Name = "Teleport para Alvo", Flag = "TeleportAttack", Default = true,
            Callback = function(v) Flags.TeleportAttack = v end
        })

        local ultToggle = left:Toggle({
            Name = "Auto Ultimate", Flag = "AutoUltimate", Default = false,
            Callback = function(v)
                if v then Combat.StartAutoUltimate() else Combat.StopAutoUltimate() end
            end
        })
        ultToggle:Keybind({ Name = "Toggle AutoUltimate", Flag = "AutoUltimateKey", Default = Enum.KeyCode.U })

        right:Button({
            Name = "Selecionados (F9)",
            Callback = function()
                local count = #Flags.SelectedEnemies
                if Flags.AttackNearest then
                    Library:Notification({ Name = "Modo: Atacar Mais Perto (ignora selecao)", Time = 3 })
                elseif count == 0 then
                    Library:Notification({ Name = "Nenhum enemy selecionado! Va na aba 'enemies'", Time = 3 })
                else
                    Library:Notification({ Name = count .. " selecionado(s): " .. table.concat(Flags.SelectedEnemies, ", "), Time = 4 })
                end
                print("=== SELECIONADOS ===")
                print("AttackNearest: " .. tostring(Flags.AttackNearest))
                for i, n in ipairs(Flags.SelectedEnemies) do print("  " .. i .. ". " .. n) end
                print("====================")
            end
        })

        right:Button({
            Name = "Info Alvos (F9)",
            Callback = function()
                H.RefreshEnemyMap()
                print("=== ALVOS ===")
                for displayName, uuids in pairs(H.nameToUUID) do
                    for _, uuid in ipairs(uuids) do
                        local pos  = H.GetEnemyPosition(uuid)
                        local dist = pos and LocalPlayer.Character
                            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                            and math.floor((LocalPlayer.Character.HumanoidRootPart.Position - pos).Magnitude) or "?"
                        print(string.format("  %s | uuid: %s | dist: %s", displayName, uuid:sub(1,8), tostring(dist)))
                    end
                end
                print("=============")
            end
        })
    end

    -- ===== ENEMIES =====
    do
        local allNames = H.GetEnemyNames()
        local mid      = math.ceil(#allNames / 2)

        local leftSec  = EnemyPage:Section({ Name = "enemies (A-I)", Side = 1 })
        local rightSec = EnemyPage:Section({ Name = "enemies (J-Z)", Side = 2 })

        leftSec:Button({
            Name = "Selecionar Todos",
            Callback = function()
                for name in pairs(ctx.EnemyToggles) do ctx.EnemyToggles[name] = true end
                H.SyncSelectedFromToggles()
                Library:Notification({ Name = #Flags.SelectedEnemies .. " enemies selecionados!", Time = 2 })
                if Flags.AutoAttack and not Flags.AttackNearest then Combat.StartAutoAttack() end
            end
        })

        rightSec:Button({
            Name = "Limpar Todos",
            Callback = function()
                for name in pairs(ctx.EnemyToggles) do ctx.EnemyToggles[name] = false end
                H.SyncSelectedFromToggles()
                Library:Notification({ Name = "Selecao limpa!", Time = 2 })
            end
        })

        rightSec:Button({
            Name = "Atualizar Lista (F9)",
            Callback = function()
                H.RefreshEnemyMap()
                local count = 0
                for _ in pairs(H.nameToUUID) do count += 1 end
                Library:Notification({ Name = count .. " enemies vivos no mundo!", Time = 2 })
            end
        })

        for i, name in ipairs(allNames) do
            ctx.EnemyToggles[name] = false
            local section = (i <= mid) and leftSec or rightSec
            section:Toggle({
                Name = name,
                Flag = "Enemy_" .. name:gsub("[%s%(%)%-%']", "_"),
                Default = false,
                Callback = function(v)
                    ctx.EnemyToggles[name] = v
                    H.SyncSelectedFromToggles()
                    if v then Library:Notification({ Name = "+" .. name, Time = 1 }) end
                end
            })
        end
    end

    -- ===== RAIDS =====
    do
        local left  = RaidPage:Section({ Name = "auto raid", Side = 1 })
        local right = RaidPage:Section({ Name = "config",    Side = 2 })

        right:Dropdown({
            Name = "Fila de Raids", Flag = "SelectedRaids",
            Items = Config.RaidList, Default = Config.RaidList[1], Multi = true,
            Callback = function(value)
                local sel = H.ParseMultiSelect(value, Config.RaidList, Config.RaidList[1])
                Flags.SelectedRaids  = sel
                Flags.RaidQueueIndex = 1
                Library:Notification({ Name = "Fila: " .. table.concat(sel, " -> "), Time = 3 })
                if Flags.AutoRaid then Raid.StartAutoRaid() end
            end
        })

        right:Dropdown({
            Name = "Fila de Escorts (Combo)", Flag = "SelectedEscortTiers",
            Items = Config.EscortTierList, Default = "common", Multi = true,
            Callback = function(value)
                local sel = H.ParseMultiSelect(value, Config.EscortTierList, "common")
                Flags.SelectedEscortTiers = sel
                Flags.EscortQueueIndex    = 1
                Library:Notification({ Name = "Escorts: " .. table.concat(sel, " -> "), Time = 3 })
            end
        })

        right:Toggle({
            Name = "Friends Only", Flag = "RaidFriendsOnly", Default = true,
            Callback = function(v) Flags.RaidFriendsOnly = v end
        })

        right:Toggle({
            Name = "Teleport na Raid", Flag = "TeleportRaid", Default = true,
            Callback = function(v) Flags.TeleportRaid = v end
        })

        right:Button({
            Name = "Sair da Raid",
            Callback = function()
                pcall(function() S.raidLeave:FireServer() end)
                Library:Notification({ Name = "Saiu da raid!", Time = 2 })
            end
        })

        right:Button({
            Name = "Debug Raid (F9)",
            Callback = function()
                local raid    = Flags.SelectedRaids[Flags.RaidQueueIndex] or "?"
                local enemies = Raid.GetRaidEnemiesOnly()
                local _, phase = Raid.GetPhaseTargets(enemies, raid)
                print(string.format("=== RAID [%d/%d]: %s | Fase: %s | Enemies: %d ===",
                    Flags.RaidQueueIndex, #Flags.SelectedRaids, raid, phase, #enemies))
                for _, e in ipairs(enemies) do
                    local tag
                    if H.IsBossName(e.name, raid) then
                        if H.HasTankMechanic(e.uuid) then
                            tag = H.IsBossProtected(e.uuid) and ("BOSS+TANKS(" .. H.CountNormalTanks(e.uuid) .. ")") or "BOSS LIVRE"
                        else tag = "BOSS" end
                    elseif H.IsIntermediateEnemy(e.name, raid) then tag = "WATER TANK"
                    else tag = "NPC" end
                    print(string.format("  [%s] %s | HP: %.0f/%.0f", tag, e.name, e.hp, e.maxHp))
                end
                print("================================")
            end
        })

        local raidToggle = left:Toggle({
            Name = "Auto Raid", Flag = "AutoRaid", Default = false,
            Callback = function(v)
                if v then Raid.StartAutoRaid() else Raid.StopAutoRaid() end
            end
        })
        raidToggle:Keybind({ Name = "Toggle Auto Raid", Flag = "AutoRaidKey", Default = Enum.KeyCode.R })

        local comboToggle = left:Toggle({
            Name = "Auto Raid + Escort", Flag = "AutoRaidEscort", Default = false,
            Callback = function(v)
                if v then Raid.StartAutoRaidEscort() else Raid.StopAutoRaidEscort() end
            end
        })
        comboToggle:Keybind({ Name = "Toggle Raid+Escort", Flag = "AutoRaidEscortKey", Default = Enum.KeyCode.T })
    end

    -- ===== TELEPORT =====
    do
        local tp = TeleportPage:Section({ Name = "ilhas", Side = 1 })
        for _, t in ipairs(Config.Teleports) do
            tp:Button({ Name = t.Name, Callback = function() H.TeleportTo(t.Pos) end })
        end
    end

    -- ===== EGGS =====
    do
        local left  = EggPage:Section({ Name = "auto egg", Side = 1 })
        local right = EggPage:Section({ Name = "manual",   Side = 2 })

        left:Dropdown({
            Name = "Selecionar Egg", Flag = "SelectedEgg",
            Items = Egg.EggList, Default = Egg.EggList[1] or "", Multi = false,
            Callback = function(v)
                Flags.SelectedEgg = v or ""
                if Flags.AutoEgg then Egg.StartAutoEgg() end
            end
        })

        local eggToggle = left:Toggle({
            Name = "Auto Egg", Flag = "AutoEgg", Default = false,
            Callback = function(v)
                if v then Egg.StartAutoEgg() else Egg.StopAutoEgg() end
            end
        })
        eggToggle:Keybind({ Name = "Toggle Auto Egg", Flag = "AutoEggKey", Default = Enum.KeyCode.G })

        right:Button({ Name = "Abrir Uma Vez", Callback = function() Egg.OpenOnce() end })
    end

    -- ===== STATS =====
    do
        local left  = StatsPage:Section({ Name = "sessao", Side = 1 })
        local right = StatsPage:Section({ Name = "debug",  Side = 2 })

        left:Button({
            Name = "Ver Stats (F9)",
            Callback = function()
                local e = os.time() - Flags.SessionStart
                Library:Notification({
                    Name = string.format("Kills %d | Eggs %d | Raids %d | Escorts %d | %02d:%02d",
                        Flags.EnemiesKilled, Flags.EggsOpened, Flags.RaidsCompleted, Flags.EscortsCompleted,
                        math.floor(e/3600), math.floor((e%3600)/60)),
                    Time = 5
                })
            end
        })

        left:Button({
            Name = "Resetar Stats",
            Callback = function()
                Flags.EnemiesKilled    = 0
                Flags.EggsOpened       = 0
                Flags.RaidsCompleted   = 0
                Flags.EscortsCompleted = 0
                Flags.SessionStart     = os.time()
                Library:Notification({ Name = "Stats resetadas!", Time = 2 })
            end
        })

        right:Button({
            Name = "Ver Warriors (F9)",
            Callback = function()
                local ids = H.GetMyWarriorIDs()
                print("=== WARRIORS (" .. #ids .. ") ===")
                local warriors = H.GetAllMyWarriors() or {}
                for i, id in ipairs(ids) do
                    local w = warriors[id]
                    print(string.format("  %d | %s | target: %s | hp: %s",
                        i, id:sub(1,8),
                        tostring(w and w.flags and w.flags.target or "none"):sub(1,8),
                        tostring(w and w.stats and math.floor(w.stats.health or 0))))
                end
                Library:Notification({ Name = #ids .. " warrior(s)", Time = 2 })
            end
        })

        right:Button({
            Name = "Print USER_KEY",
            Callback = function()
                print("[USER_KEY] " .. tostring(S.USER_KEY))
                Library:Notification({ Name = "USER_KEY printado!", Time = 2 })
            end
        })
    end

    Library:Notification({ Name = "Script carregado! v13 (modular)", Time = 4 })
    Window:InitWindow()

    -- ===== ESCORT (pagina criada apos InitWindow, como no original) =====
    local EscortPage = Window:Page({ Name = "escort" })
    do
        local left  = EscortPage:Section({ Name = "auto escort", Side = 1 })
        local right = EscortPage:Section({ Name = "config",      Side = 2 })

        right:Dropdown({
            Name = "Tier do Escort", Flag = "EscortTier",
            Items = Config.EscortTierList, Default = "common", Multi = false,
            Callback = function(v)
                Flags.EscortTier = v or "common"
                Library:Notification({ Name = "Tier: " .. Flags.EscortTier, Time = 2 })
            end
        })

        right:Toggle({
            Name = "Friends Only", Flag = "EscortFriendsOnly", Default = true,
            Callback = function(v) Flags.EscortFriendsOnly = v end
        })

        right:Button({
            Name = "Sair do Escort",
            Callback = function()
                pcall(function() S.escortLeave:FireServer() end)
                Library:Notification({ Name = "Saiu do escort!", Time = 2 })
            end
        })

        right:Button({
            Name = "Escorts Completos",
            Callback = function()
                Library:Notification({ Name = "Escorts completos: " .. Flags.EscortsCompleted, Time = 3 })
            end
        })

        local escortToggle = left:Toggle({
            Name = "Auto Escort", Flag = "AutoEscort", Default = false,
            Callback = function(v)
                if v then Escort.StartAutoEscort() else Escort.StopAutoEscort() end
            end
        })
        escortToggle:Keybind({ Name = "Toggle Auto Escort", Flag = "AutoEscortKey", Default = Enum.KeyCode.E })
    end

    -- ===== INVASIONS / INFILTRATION =====
    local InvPage = Window:Page({ Name = "invasions" })
    do
        -- ── Auto Invasion ──
        local invSec = InvPage:Section({ Name = "auto invasion", Side = 1 })
        invSec:Toggle({
            Name = "Auto Invasion", Flag = "AutoInvasion", Default = false,
            Callback = function(v)
                if v then Invasion.StartAutoInvasion() else Invasion.StopAutoInvasion() end
            end
        })
        invSec:Dropdown({
            Name = "Invasion", Flag = "SelInvasion",
            Items = Config.InvasionNames,
            Default = Config.InvasionNames[1] or "",
            Callback = function(v) Flags.SelectedInvasion = v end
        })
        invSec:Toggle({
            Name = "Friends Only", Flag = "InvFriends", Default = true,
            Callback = function(v) Flags.InvasionFriendsOnly = v end
        })
        local invInfo = InvPage:Section({ Name = "info invasion", Side = 1 })
        invInfo:Label("Invasion = auto-fight (jogo envia warriors)", "Center")
        invInfo:Label("Cria → Lobby → Espera → Leave → Repete", "Center")

        -- ── Auto Infiltration ──
        local infSec = InvPage:Section({ Name = "auto infiltration", Side = 2 })
        infSec:Toggle({
            Name = "Auto Infiltration", Flag = "AutoInfiltration", Default = false,
            Callback = function(v)
                if v then Invasion.StartAutoInfiltration() else Invasion.StopAutoInfiltration() end
            end
        })
        infSec:Dropdown({
            Name = "Infiltration", Flag = "SelInfiltration",
            Items = Config.InfiltrationNames,
            Default = Config.InfiltrationNames[1] or "",
            Callback = function(v) Flags.SelectedInfiltration = v end
        })
        infSec:Dropdown({
            Name = "Tier", Flag = "InfTier",
            Items = Config.InfiltrationTiers,
            Default = "I",
            Callback = function(v) Flags.InfiltrationTier = v end
        })
        infSec:Toggle({
            Name = "Friends Only", Flag = "InfFriends", Default = true,
            Callback = function(v) Flags.InfiltrationFriendsOnly = v end
        })
        local infInfo = InvPage:Section({ Name = "info infiltration", Side = 2 })
        infInfo:Label("Infiltration = Fase 1: NPCs → Fase 2: Boss", "Center")
        infInfo:Label("Usa heuristica se boss name nao configurado", "Center")
    end

    return Window
end

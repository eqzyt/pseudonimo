-- ============================================================
-- services.lua
-- Resolve remotes / stores / constantes do jogo, tudo com pcall
-- pra um update do jogo nao matar o script na inicializacao.
-- Retorna uma tabela "S" usada pelos demais modulos.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local S = {}

-- Helper: require protegido
local function safeRequire(path)
    local ok, mod = pcall(require, path)
    return ok and mod or nil
end

-- Helper: indexa um caminho fundo sem estourar
local function safePath(root, ...)
    local node = root
    for _, key in ipairs({ ... }) do
        if not node then return nil end
        local ok, nxt = pcall(function() return node[key] end)
        if not ok then return nil end
        node = nxt
    end
    return node
end

-- ============ STORES / CONSTANTES ============
local remotesMod    = safePath(ReplicatedStorage, "src", "common", "remotes")
local warriorsStore = safePath(ReplicatedStorage, "src", "common", "store", "world", "warriors")
local enemiesStore  = safePath(ReplicatedStorage, "src", "common", "store", "world", "enemies")
local playerStore   = safePath(ReplicatedStorage, "src", "common", "store", "players", "datastore")
local coreConsts    = safePath(ReplicatedStorage, "src", "common", "constants", "core")
local eggsMod       = safePath(ReplicatedStorage, "src", "common", "content", "purchases", "eggs")

remotesMod    = remotesMod    and safeRequire(remotesMod)
warriorsStore = warriorsStore and safeRequire(warriorsStore)
enemiesStore  = enemiesStore  and safeRequire(enemiesStore)
playerStore   = playerStore   and safeRequire(playerStore)
coreConsts    = coreConsts    and safeRequire(coreConsts)
eggsMod       = eggsMod       and safeRequire(eggsMod)

local remotes = remotesMod and remotesMod.remotes

S.sendAndRetreat     = remotes and remotes.enemies and remotes.enemies.sendAndRetreat
S.getPlayerData      = playerStore and playerStore.getPlayerData
S.getWarriorsOfOwner = warriorsStore and warriorsStore.getWarriorsOfOwner
S.getEnemy           = enemiesStore and enemiesStore.getEnemy
S.allEnemies         = enemiesStore and enemiesStore.allEnemies
S.USER_KEY           = coreConsts and coreConsts.USER_KEY
S.eggsContent        = eggsMod and eggsMod.eggsContent or {}

-- ============ REMOTES DO REMO (container) ============
local function remo(name)
    return safePath(ReplicatedStorage,
        "rbxts_include", "node_modules", "@rbxts",
        "remo", "src", "container", name)
end

S.eggOpen        = remo("eggs.open")
S.raidCreate     = remo("bossRaids.create")
S.weaponUnequip  = remo("toolbar.unequip")
S.weaponEquip    = remo("toolbar.equip")
S.raidStart      = remo("lobbies.start")
S.raidLeave      = remo("bossRaids.leaveRaid")
S.clientSummary  = remo("client.summary")
S.weaponUltimate = remo("weapons.useUltimate")
S.escortCreate   = remo("escorts.create")
S.escortLeave    = remo("escorts.leaveEscort")

-- ============ INVASION / INFILTRATION REMOTES ============
S.invasionCreate     = remo("invasions.create")
S.invasionLeave      = remo("invasions.leaveInvasion")
S.infiltrationCreate = remo("infiltration.create")
S.lobbiesStart       = remo("lobbies.start")
S.lobbiesLeave       = remo("lobbies.leave")

-- Diagnostico: lista o que faltou resolver (aparece no console)
function S.Diagnose()
    local required = {
        "sendAndRetreat", "getPlayerData", "getWarriorsOfOwner", "getEnemy",
        "allEnemies", "USER_KEY", "eggOpen", "raidCreate", "weaponUnequip",
        "weaponEquip", "raidStart", "raidLeave", "clientSummary",
        "weaponUltimate", "escortCreate", "escortLeave",
    }
    local missing = {}
    for _, key in ipairs(required) do
        if S[key] == nil then table.insert(missing, key) end
    end
    if #missing > 0 then
        warn("[Services] Nao resolvido: " .. table.concat(missing, ", "))
    else
        print("[Services] Tudo resolvido com sucesso.")
    end
    return missing
end

return S

-- ============================================================
-- config.lua
-- Dados estaticos (listas, posicoes, nomes) + estado (Flags).
-- Nao depende de nada; e o primeiro modulo carregado.
-- ============================================================

local Config = {}

-- ============ BOSS NAMES ============
Config.RaidBossNames = {
    ["Sunshine Raid"]           = {"Pride (Summer)"},
    ["Destroyed Nemak"]         = {"Freeze", "Freeze (2nd)", "Freeze (Prime)", "Freeze (Prime) (Injured)"},
    ["Red Ribbon Base"]         = {"Cel (Maximum)"},
    ["Clan Hideout"]            = {"Itochi"},
    ["Desert Kingdom"]          = {"Alligator"},
    ["Destroyed Soul District"] = {"Yamamo", "Yamamo (Activated)"},
}

-- ============ ENEMIES INTERMEDIARIOS ============
Config.RaidIntermediateEnemies = {
    ["Desert Kingdom"] = {"Water Tank"},
}

Config.RaidTeleports = {
    ["Destroyed Nemak"]         = Vector3.new(4998.96, 508.46,  -28.99),
    ["Red Ribbon Base"]         = Vector3.new(5094.32, 652.91,  188.53),
    ["Clan Hideout"]            = Vector3.new(4995.43, 520.48,   -7.65),
    ["Desert Kingdom"]          = Vector3.new(5048.71, 512.88,   70.21),
    ["Destroyed Soul District"] = Vector3.new(5050.0,  510.0,    0.0),
}

-- Centro das raids (fallback de teleporte)
Config.RaidCenterPositions = {
    ["Sunshine Raid"] = Vector3.new(5009.52, 510.73, 111.10),
    ["Clan Hideout"]  = Vector3.new(4995.43, 520.48, -7.65),
    -- Adicione outros raids aqui conforme necessario
}

Config.RaidList = {
    "Sunshine Raid",
    "Destroyed Nemak",
    "Red Ribbon Base",
    "Clan Hideout",
    "Desert Kingdom",
    "Destroyed Soul District",
}

Config.EscortTierList = { "common", "rare", "epic", "legendary", "mythical" }

Config.KnownEnemyNames = {
    "Ikako", "Ranji",
    "Itochi (Crow)",
    "Matsui", "Ibiboro",
    "Plasma",
    "Barta", "Jays",
    "Freeze", "Freeze (2nd)", "Freeze (Prime)", "Freeze (Prime) (Injured)",
    "Cel (Maximum)",
    "Itochi",
    "Alligator",
    "Yamamo", "Yamamo (Activated)",
}

Config.Teleports = {
    { Name = "Planet Namek",  Pos = Vector3.new(762.87,   150.17,  3051.47)  },
    { Name = "Sand Village",  Pos = Vector3.new(-2267.48, 34.74,   1345.39)  },
    { Name = "Soul District", Pos = Vector3.new(3788.29,  49.18,   -622.40)  },
    { Name = "Future City",   Pos = Vector3.new(715.54,   57.97,   -280.38)  },
    { Name = "Sky Island",    Pos = Vector3.new(-2051.78, 915.49,  -2109.64) },
    { Name = "Rain Village",  Pos = Vector3.new(1044.94,  105.62,  -3701.85) },
}

-- ============ CONSTANTES (timeouts / raios / ticks) ============
Config.CONST = {
    WARRIOR_RECOVERY_TIMEOUT = 120,
    ESCORT_TIMEOUT           = 400,
    RAID_TIMEOUT             = 620,
    ESCORT_ENEMY_RADIUS      = 100,
    RAID_ENEMY_MIN_X         = 1000,
    TICK                     = 0.25,
}

-- ============ FLAGS (estado de runtime) ============
Config.Flags = {
    AutoAttack       = false,
    AttackNearest    = false,
    SelectedEnemies  = {},
    TeleportAttack   = true,

    AutoUltimate     = false,

    AutoRaid          = false,
    AutoEscort        = false,
    AutoRaidEscort    = false,

    SelectedRaids        = {"Destroyed Nemak"},
    RaidQueueIndex        = 1,
    RaidFriendsOnly       = true,
    TeleportRaid          = true,

    EscortTier            = "common",
    EscortFriendsOnly     = true,
    SelectedEscortTiers   = {"common"},
    EscortQueueIndex      = 1,

    AutoEgg          = false,
    SelectedEgg      = "",

    EnemiesKilled    = 0,
    EscortsCompleted = 0,
    EggsOpened       = 0,
    RaidsCompleted   = 0,
    SessionStart     = os.time(),
}

-- Toggles de cada enemy na aba "enemies" (preenchido pela UI)
Config.EnemyToggles = {}

return Config

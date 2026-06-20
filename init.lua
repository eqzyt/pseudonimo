local BASE_URL = "https://raw.githubusercontent.com/eqzyt/pseudonimo/aw3"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local VirtualUser       = game:GetService("VirtualUser")
local LocalPlayer       = Players.LocalPlayer

local function loadModule(relPath)
    local url = BASE_URL .. "/" .. relPath
    local okGet, src = pcall(function() return game:HttpGet(url) end)
    if not okGet or not src then
        warn("[init] Falha ao baixar: " .. relPath)
        return nil
    end
    local fn, compileErr = loadstring(src, "@" .. relPath)
    if not fn then
        warn("[init] Erro de compilacao em " .. relPath .. ": " .. tostring(compileErr))
        return nil
    end
    local okRun, result = pcall(fn)
    if not okRun then
        warn("[init] Erro ao executar " .. relPath .. ": " .. tostring(result))
        return nil
    end
    return result
end

local okLib, Library = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/secrethaxx/Library.lua"))()
end)
if not okLib or not Library then
    return warn("[init] Falha ao carregar a Library externa. Abortando.")
end

local Config   = loadModule("src/config.lua")
local Services = loadModule("src/services.lua")
if not Config or not Services then
    return warn("[init] Config/Services nao carregaram. Abortando.")
end
Services.Diagnose()

local ctx = {
    Library     = Library,
    Services    = Services,
    Config      = Config,
    Flags       = Config.Flags,
    EnemyToggles = Config.EnemyToggles,
    Players     = Players,
    LocalPlayer = LocalPlayer,
}

local helpersFactory = loadModule("src/helpers.lua")
if not helpersFactory then return warn("[init] helpers.lua falhou. Abortando.") end
ctx.Helpers = helpersFactory(ctx)

local function mount(name, relPath)
    local factory = loadModule(relPath)
    if not factory then
        warn("[init] " .. relPath .. " falhou (feature '" .. name .. "' desativada).")
        return
    end
    ctx[name] = factory(ctx)
end

mount("Combat", "src/combat.lua")
mount("Escort", "src/escort.lua")
mount("Raid",   "src/raid.lua")   
mount("Egg",    "src/egg.lua")

if not _G.__AW3_HOOKS_INSTALLED then
    _G.__AW3_HOOKS_INSTALLED = true

    pcall(function()
        LocalPlayer.Idled:Connect(function()
            VirtualUser:Button1Down(Vector2.new(0, 0), CFrame.new())
            task.wait(1)
            VirtualUser:Button1Up(Vector2.new(0, 0), CFrame.new())
        end)
    end)

    local weaponUnequip = Services.weaponUnequip
    local weaponEquip   = Services.weaponEquip
    if weaponUnequip and weaponEquip and hookmetamethod then
        local ok = pcall(function()
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", function(...)
                local self   = ...
                local method = getnamecallmethod()
                if rawequal(self, weaponUnequip) and method == "FireServer" then
                    local args = table.pack(...)
                    local result = table.pack(oldNamecall(self, table.unpack(args, 1, args.n)))
                    if args[2] == "weapon" then
                        task.delay(0.1, function()
                            pcall(function() weaponEquip:FireServer("weapon") end)
                        end)
                    end
                    return table.unpack(result, 1, result.n)
                end
                return oldNamecall(...)
            end)
        end)
        if ok then
            print("[AutoReequip] Hook ativo!")
        else
            warn("[AutoReequip] hookmetamethod nao disponivel neste executor.")
        end
    else
        warn("[AutoReequip] remotes de toolbar nao resolvidos ou executor sem hookmetamethod.")
    end
end

local uiFactory = loadModule("src/ui.lua")
if not uiFactory then return warn("[init] ui.lua falhou. Abortando.") end
ctx.Window = uiFactory(ctx)

print("[init] AW III carregado com sucesso.")
return ctx

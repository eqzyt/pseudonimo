-- ============================================================
-- egg.lua
-- Auto Egg. Monta a EggList a partir de Services.eggsContent.
-- ============================================================

return function(ctx)
    local S       = ctx.Services
    local Flags   = ctx.Flags
    local Library = ctx.Library

    local M = {}
    local eggThread = nil

    -- ============ LISTA DE EGGS ============
    M.EggList = {}
    for name in pairs(S.eggsContent or {}) do table.insert(M.EggList, name) end
    table.sort(M.EggList)
    if #M.EggList == 0 then
        M.EggList = { "Nemak", "Sky", "Rain", "Android", "Desert", "Demonic" }
    end

    -- ============ AUTO EGG ============
    function M.StopAutoEgg()
        Flags.AutoEgg = false
        eggThread = nil
    end

    function M.StartAutoEgg()
        M.StopAutoEgg()
        if Flags.SelectedEgg == "" then
            Library:Notification({ Name = "Selecione um egg!", Time = 2 })
            return
        end
        Flags.AutoEgg = true
        eggThread = task.spawn(function()
            while Flags.AutoEgg do
                local ok = pcall(function() S.eggOpen:InvokeServer(Flags.SelectedEgg) end)
                if ok then Flags.EggsOpened += 1 end
                task.wait(0.2)
            end
        end)
    end

    -- Abrir uma vez (usado pelo botao manual)
    function M.OpenOnce()
        if Flags.SelectedEgg == "" then
            Library:Notification({ Name = "Selecione um egg!", Time = 2 })
            return
        end
        pcall(function() S.eggOpen:InvokeServer(Flags.SelectedEgg) end)
        Library:Notification({ Name = "Abriu: " .. Flags.SelectedEgg, Time = 2 })
    end

    return M
end

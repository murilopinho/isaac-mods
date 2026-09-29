--[[
nmcb_mcm.lua - tela do Mod Config Menu (opcional).
Aba unica "Limits" (<=8 char: o carrossel do MCM Pure tem passo fixo de 76px).
Linhas de texto <=49 char (MCM Pure nao tem wrap).
Sliders com ModifyBy pequeno + clamp no OnChange (licao do bug do slider do EDL).
Protection OFF esconde o resto: o MCM nao tem campo de visibilidade, entao a aba
e apagada e montada de novo (o menu rele a aba por indice a cada frame).
]]

local M = {}

function M.setup(CFG, saveConfig)
    if not ModConfigMenu then return false end
    local cat, sub = "No More Crash Builds", "Limits"
    local build

    local function toggle(label, key)
        ModConfigMenu.AddSetting(cat, sub, {
            Type           = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function() return CFG[key] end,
            Display        = function() return label .. ": " .. (CFG[key] and "ON" or "OFF") end,
            OnChange       = function(v) CFG[key] = v; saveConfig() end,
        })
    end
    local function slider(label, key, min, max, step)
        ModConfigMenu.AddSetting(cat, sub, {
            Type           = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = function() return CFG[key] end,
            Minimum        = min,
            Maximum        = max,
            ModifyBy       = step,
            Display        = function() return label .. ": " .. CFG[key] end,
            OnChange       = function(v) CFG[key] = math.max(min, math.min(max, v)); saveConfig() end,
        })
    end
    local function info(text)
        pcall(function() ModConfigMenu.AddText(cat, sub, function() return text end) end)
    end

    function build()
        ModConfigMenu.RemoveSubcategory(cat, sub)
        ModConfigMenu.AddSetting(cat, sub, {
            Type           = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function() return CFG.ENABLED end,
            Display        = function() return "Protection: " .. (CFG.ENABLED and "ON" or "OFF") end,
            OnChange       = function(v) CFG.ENABLED = v; saveConfig(); build() end,
        })
        if not CFG.ENABLED then return end

        ModConfigMenu.AddTitle(cat, sub, "Tears in room")
        info("Lower = safer, higher = prettier")
        slider("Hide splash FX at", "FX_LIMIT", 25, 150, 5)
        slider("Stop splitting at", "SPLIT_LIMIT", 75, 300, 5)
        info("Split damage goes to the parent tear")

        ModConfigMenu.AddTitle(cat, sub, "Bombs in room")
        slider("Stop bomb chains at", "BOMB_LIMIT", 6, 24, 1)

        ModConfigMenu.AddTitle(cat, sub, "Status dot (top of screen)")
        info("Green: normal  Yellow: no splash")
        info("Red: merging splits / stopping bombs")
        toggle("Status dot", "SHOW_DOT")

        ModConfigMenu.AddTitle(cat, sub, "Debug")
        toggle("Show counter", "SHOW_COUNTER")
    end

    build()
    return true
end

return M

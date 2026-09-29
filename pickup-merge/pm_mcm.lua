--[[
pm_mcm.lua - tela do Mod Config Menu (opcional). Mesmo padrao do No More Crash Builds.
Aba unica "Merge" (<=8 char: o carrossel do MCM Pure tem passo fixo de 76px).
Linhas de texto <=49 char (MCM Pure nao tem wrap).
Merge OFF esconde o resto: o MCM nao tem campo de visibilidade, entao a aba
e apagada e montada de novo (o menu rele a aba por indice a cada frame).
]]

local M = {}

local MODE_NAMES = { "Re-enter room", "Key press", "Both" }

function M.setup(CFG, saveConfig)
    if not ModConfigMenu then return false end
    local cat, sub = "Pickup Merge", "Merge"
    local build

    local function toggle(label, key)
        ModConfigMenu.AddSetting(cat, sub, {
            Type           = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function() return CFG[key] end,
            Display        = function() return label .. ": " .. (CFG[key] and "ON" or "OFF") end,
            OnChange       = function(v) CFG[key] = v; saveConfig() end,
        })
    end
    local function info(text)
        pcall(function() ModConfigMenu.AddText(cat, sub, function() return text end) end)
    end
    local function keyName(k)
        return (ModConfigMenu.KeyboardToString or {})[k] or tostring(k)
    end

    function build()
        ModConfigMenu.RemoveSubcategory(cat, sub)
        ModConfigMenu.AddSetting(cat, sub, {
            Type           = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function() return CFG.ENABLED end,
            Display        = function() return "Pickup Merge: " .. (CFG.ENABLED and "ON" or "OFF") end,
            OnChange       = function(v) CFG.ENABLED = v; saveConfig(); build() end,
        })
        if not CFG.ENABLED then return end

        ModConfigMenu.AddTitle(cat, sub, "When to merge")
        ModConfigMenu.AddSetting(cat, sub, {
            Type           = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = function() return CFG.MODE end,
            Minimum        = 1,
            Maximum        = 3,
            ModifyBy       = 1,
            Display        = function() return "Merge on: " .. MODE_NAMES[CFG.MODE] end,
            OnChange       = function(v) CFG.MODE = math.max(1, math.min(3, v)); saveConfig() end,
        })
        ModConfigMenu.AddSetting(cat, sub, {
            Type           = ModConfigMenu.OptionType.KEYBIND_KEYBOARD,
            CurrentSetting = function() return CFG.KEY end,
            Default        = Keyboard.KEY_M,
            NoUnbind       = true,
            Display        = function() return "Merge key: " .. keyName(CFG.KEY) end,
            OnChange       = function(v) if v then CFG.KEY = v; saveConfig() end end,
            PopupGfx       = ModConfigMenu.PopupGfx.WIDE_SMALL,
            PopupWidth     = 280,
            Popup          = function()
                return "Press a key to use for merging.$newline$newlineCurrent: " .. keyName(CFG.KEY)
            end,
        })
        info("Key works in any room, even the 1st visit")

        ModConfigMenu.AddTitle(cat, sub, "Big merges (lose value)")
        toggle("50 coins -> Lucky penny", "LUCKY")
        toggle("40 bombs -> Giga bomb", "GIGA")
        toggle("2 soul -> Black heart", "BLACK")
    end

    build()
    return true
end

return M

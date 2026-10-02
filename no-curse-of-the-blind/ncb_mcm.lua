--[[
  ncb_mcm.lua - tela do Mod Config Menu (opcional). Mesmo padrao do Treasure Offering.
  Aba unica "Curses" (<=8 char: o carrossel do MCM Pure tem passo fixo de 76px).
  Linhas de texto <=49 char (MCM Pure nao tem wrap).
]]
local M = {}

function M.setup(CFG, saveData)
    if not ModConfigMenu then return false end
    local cat, sub = "No Curse of the Blind", "Curses"
    ModConfigMenu.AddSetting(cat, sub, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.ENABLED end,
        Display = function() return "No Curse of the Blind: " .. (CFG.ENABLED and "ON" or "OFF") end,
        OnChange = function(v) CFG.ENABLED = v; saveData() end,
    })
    ModConfigMenu.AddSetting(cat, sub, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.EXTRA end,
        Display = function() return "Extra curse chance (+15%): " .. (CFG.EXTRA and "ON" or "OFF") end,
        OnChange = function(v) CFG.EXTRA = v; saveData() end,
    })
    ModConfigMenu.AddText(cat, sub, "Blind never shows up. The price:")
    ModConfigMenu.AddText(cat, sub, "clean floors get a 15% curse roll.")
    return true
end

return M

--[[
  to_mcm.lua - tela do Mod Config Menu (opcional). Mesmo padrao do Pickup Merge.
  Aba unica "Offering" (<=8 char: o carrossel do MCM Pure tem passo fixo de 76px).
  Linhas de texto <=49 char (MCM Pure nao tem wrap).
]]
local M = {}

function M.setup(CFG, saveData)
    if not ModConfigMenu then return false end
    local cat, sub = "Treasure Offering", "Offering"
    ModConfigMenu.AddSetting(cat, sub, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.ENABLED end,
        Display = function() return "Treasure Offering: " .. (CFG.ENABLED and "ON" or "OFF") end,
        OnChange = function(v) CFG.ENABLED = v; saveData() end,
    })
    ModConfigMenu.AddText(cat, sub, "Leave a trinket in the treasure room.")
    ModConfigMenu.AddText(cat, sub, "Beat the boss, come back. 1 per floor.")
    return true
end

return M

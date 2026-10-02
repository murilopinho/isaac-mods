--[[
  sg_mcm.lua - tela do Mod Config Menu (opcional). Mesmo padrao do Treasure Offering.
  Aba unica "Gulp" (<=8 char: o carrossel do MCM Pure tem passo fixo de 76px).
  Linhas de texto <=49 char (MCM Pure nao tem wrap).
]]
local M = {}

function M.setup(CFG, saveData)
    if not ModConfigMenu then return false end
    local cat, sub = "Shop Gulp", "Gulp"
    ModConfigMenu.AddSetting(cat, sub, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.ENABLED end,
        Display = function() return "Shop Gulp: " .. (CFG.ENABLED and "ON" or "OFF") end,
        OnChange = function(v) CFG.ENABLED = v; saveData() end,
    })
    ModConfigMenu.AddText(cat, sub, "Every 2nd new shop drops a Gulp! pill.")
    ModConfigMenu.AddText(cat, sub, "Up to 2 per run.")
    return true
end

return M

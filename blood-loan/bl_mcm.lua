--[[
  bl_mcm.lua - tela do Mod Config Menu (opcional). Mesmo padrao do Treasure Offering.
  Aba unica "Loan" (<=8 char: o carrossel do MCM Pure tem passo fixo de 76px).
  Linhas de texto <=49 char (MCM Pure nao tem wrap).
]]
local M = {}

function M.setup(CFG, saveData)
    if not ModConfigMenu then return false end
    local cat, sub = "Blood Loan", "Loan"
    ModConfigMenu.AddSetting(cat, sub, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.ENABLED end,
        Display = function() return "Blood Loan: " .. (CFG.ENABLED and "ON" or "OFF") end,
        OnChange = function(v) CFG.ENABLED = v; saveData() end,
    })
    ModConfigMenu.AddText(cat, sub, "Sacrifice Room lends 3.5 hearts + Wafer.")
    ModConfigMenu.AddText(cat, sub, "What you don't spend, it takes back.")
    return true
end

return M

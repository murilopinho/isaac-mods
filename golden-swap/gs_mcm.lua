--[[
  gs_mcm.lua - tela do Mod Config Menu (opcional). Mesmo padrao do Treasure Offering.
  Aba unica "Golden" (<=8 char: o carrossel do MCM Pure tem passo fixo de 76px).
  Linhas de texto <=49 char (MCM Pure nao tem wrap).
]]
local M = {}

function M.setup(CFG, saveData)
    if not ModConfigMenu then return false end
    local cat, sub = "Golden Swap", "Golden"
    ModConfigMenu.AddSetting(cat, sub, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.ENABLED end,
        Display = function() return "Golden Swap: " .. (CFG.ENABLED and "ON" or "OFF") end,
        OnChange = function(v) CFG.ENABLED = v; saveData() end,
    })
    ModConfigMenu.AddText(cat, sub, "Extra golden key -> golden bomb, and back.")
    ModConfigMenu.AddText(cat, sub, "Have both? Key = 10 keys, Bomb = 14 bombs.")
    return true
end

return M

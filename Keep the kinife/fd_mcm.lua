--[[
  fd_mcm.lua - tela do Mod Config Menu (opcional). Mesmo padrao do Treasure Offering.
  Aba unica "Door" (<=8 char: o carrossel do MCM Pure tem passo fixo de 76px).
  Linhas de texto <=49 char (MCM Pure nao tem wrap).
]]
local M = {}

function M.setup(CFG, saveData)
    if not ModConfigMenu then return false end
    local cat, sub = "Free Flesh Door", "Door"
    ModConfigMenu.AddSetting(cat, sub, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.ENABLED end,
        Display = function() return "Free Flesh Door: " .. (CFG.ENABLED and "ON" or "OFF") end,
        OnChange = function(v) CFG.ENABLED = v; saveData() end,
    })
    ModConfigMenu.AddSetting(cat, sub, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.KEEP end,
        Display = function() return "Keep the knife: " .. (CFG.KEEP and "ON" or "OFF") end,
        OnChange = function(v) CFG.KEEP = v; saveData() end,
    })
    ModConfigMenu.AddText(cat, sub, "Mom dies: you get the missing knife pieces.")
    ModConfigMenu.AddText(cat, sub, "Keep the knife: pieces aren't used up.")
    return true
end

return M

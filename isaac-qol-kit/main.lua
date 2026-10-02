--[[
Isaac QoL Kit - um punhado de melhorias de qualidade de vida.

Spinoff do Enemy Drop Loot V2: o drop engine ficou no EDL; este mod é o loadout,
trinkets e pequenos fixes portados (com crédito) de mods de terceiros.

============================================================================
 MAPA DO MOD (pra achar as coisas rapido)
============================================================================
   qol_state.lua       singletons do mod (mod/game/json) + estado mutavel compartilhado
   qol_config.lua      CFG (toda opcao) + DEFAULTS + CFG_SCALAR_KEYS
   qol_persistence.lua saveConfig / loadConfig
   qol_trinketutil.lua keybind de gulp, T.Cain push mode, helpers de keybind
   qol_loadout.lua     fileira de trinkets, active->pocket, penny do greed, Steam Sale,
                       Eden's Blessing/Birthright/PHD inicial, item fixo por tainted
   qol_charfixes.lua   Judas+Birthright, Holy Mantle Jacob, Rainbow Poop Mantle
   qol_machines.lua    No Jam, Faster Eternal Chest, Instant Fires/Poops
   qol_roomtweaks.lua  Auto-Collect, Bombable Devil Statue, Angel Drop Item
   qol_mcm.lua         a tela do Mod Config Menu
   main.lua (este)        wiring dos modulos + init + reset de run + save no exit

 Regra de ouro: mexeu numa opcao nova? Ela PRECISA estar em CFG e em CFG_SCALAR_KEYS
 (qol_config.lua), senao nao salva.

 OBS: se voce tambem roda o Enemy Drop Loot V2, pode rodar os dois em paz. O split de
 16/set tirou essas features de la de vez (nao so desligou por padrao) - nao tem
 nada pra desligar la, nem risco de aplicar em dobro.
============================================================================
]]

local S           = require("qol_state")
local Persistence = require("qol_persistence")
local TrinketUtil = require("qol_trinketutil")
local Loadout     = require("qol_loadout")
local CharFixes   = require("qol_charfixes")
local Machines    = require("qol_machines")
local RoomTweaks  = require("qol_roomtweaks")
local MCM         = require("qol_mcm")

local mod = S.mod

local mcmDone      = false
local configLoaded = false

-- IMPORTANTE: o Isaac passa um arg-lixo na frente (igual o POST_ENTITY_KILL usar `_, entity`).
-- Sem o `_`, isSave pegava esse arg-lixo (truthy), `if not isSave` nunca era verdadeiro e o
-- reset de flag NUNCA rodava: o loadout "funcionava so na 1a run e parava depois do R".
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isSave)
    -- Carrega a config uma vez por abertura do jogo. Seguro aqui (o slot de save ja e
    -- conhecido). O OnChange do MCM salva no disco na hora, entao o que esta no disco
    -- quando carregamos ja e a escolha mais recente do player - sem risco de sobrescrever.
    if not configLoaded then Persistence.loadConfig(); configLoaded = true end
    if not isSave then
        S.runCount = S.runCount + 1
        Loadout.resetForNewRun()
        CharFixes.resetForNewRun()
        Machines.resetForNewRun()
        RoomTweaks.resetForNewRun()
        -- appliedRunCount / pocketAppliedRunCount NAO resetam aqui: runCount ja subiu pra
        -- esta run nova, entao runCount ~= appliedRunCount libera o loadout naturalmente.
        -- Persistir os dois e o que impede um Continue depois de reiniciar reaplicar tudo.
    end
    if not mcmDone and ModConfigMenu then
        local ok, result = pcall(MCM.setupMCM)
        if ok and result then mcmDone = true end
    end
end)

mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    Persistence.saveConfig()
end)

Isaac.DebugString("IsaacQoLKit: v0.4 loaded" .. (S.HAS_REPENTOGON and " [REPENTOGON]" or ""))

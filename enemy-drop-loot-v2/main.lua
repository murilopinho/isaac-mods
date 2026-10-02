--[[
Enemy Drop Loot V2 - Mata inimigo, ganha loot!
Baseado no Enemy Loot Drop original do 赖 (valeu demais ao baobao2234 pelo código original).
Inimigos soltam itens e pickups ao morrer; a taxa de drop cai por andar.
REPENTOGON opcional: o filtro de unlock detecta sozinho, o mod funciona sem ele.

============================================================================
 MAPA DO MOD (pra achar as coisas rápido)
============================================================================
   edl_config.lua      CFG (toda opção liga/desliga) + DEFAULTS + CFG_SCALAR_KEYS
   edl_state.lua       singletons do mod (mod/game/json) + estado mutável compartilhado
   edl_persistence.lua saveConfig / loadConfig
   edl_dropengine.lua  pools por andar, boss registry, char-adapt, spawn de item/recurso,
                       filtros, escolha de item, tryDrop, overlay de debug, DEV keybinds
   edl_mcm.lua         o menu de configuração (Mod Config Menu)
   main.lua (este)     wiring dos módulos + init + reset de run + save no exit

 Regra de ouro: mexeu numa opção nova? Ela PRECISA estar em CFG e em CFG_SCALAR_KEYS
 (edl_config.lua) senão não salva.

 SPLIT de 16/set/2026: o loadout inicial (fileira de trinkets, Active->Pocket, gulp,
 T.Cain push, fix Judas+Birthright, penny do Greed) SAIU deste mod. Virou um mod
 separado, o Isaac QoL Kit (pasta mods/isaac-qol-kit). Este aqui é só o drop engine:
 matou inimigo, caiu loot. O edl_trinkets.lua não existe mais.
============================================================================
]]

local S           = require("edl_state")
local DropEngine  = require("edl_dropengine")
local Persistence = require("edl_persistence")
local MCM         = require("edl_mcm")

local mod = S.mod

-- ============================================================
-- Init
-- ============================================================
pcall(DropEngine.buildItemTables)
if not S.itemsReady then
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
        if not S.itemsReady then
            pcall(DropEngine.buildItemTables)
            if not S.itemsReady then
                Isaac.DebugString("EnemyDropLoot: WARNING - item tables still empty after retry; item drops disabled")
            end
        end
    end)
end

-- ── flag de setup único do MCM ─────────────────────────────
local mcmDone = false
local configLoaded = false

-- IMPORTANTE: o Isaac passa um arg-lixo na frente (igual ao POST_ENTITY_KILL usar `_, entity`).
-- Sem o `_`, isSave pegava esse arg-lixo (truthy), `if not isSave` era sempre falso e o reset
-- de flags NUNCA rodava: pocket/trinket "funcionavam só na 1ª run, paravam depois do R". O `_` conserta.
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isSave)
    -- Carrega a config uma vez por abertura do jogo. Seguro aqui (o slot de save é conhecido).
    -- o OnChange do MCM salva NA HORA no disco, então o que estiver no disco quando a gente
    -- carrega já é a escolha mais recente do player, sem risco de sobrescrever.
    if not configLoaded then Persistence.loadConfig(); configLoaded = true end
    -- pools só existem quando uma run está rolando, então monta o deal set aqui (uma vez)
    if not S.dealFilterReady then DropEngine.buildDealSet() end
    if not isSave then
        S.runCount = S.runCount + 1
        S.droppedItems = {}
        S.pendingSeeds = {}   -- run nova: esquece pedestais largados da run anterior
        S.roomDrops = {}; S.roomDropsLevel = nil   -- run nova: zera o cap anti-farm por sala
        S.runStats = { items = 0, pickups = 0, kills = 0 }   -- stats da run pro overlay
        S.lastRoll = nil; S.lastRollTimer = 0
        DropEngine.resetForNewRun()
    end
    -- o Continue te devolve numa sala SEM disparar POST_NEW_ROOM, então reseta o estado
    -- de dedup por-sala aqui ou entradas velhas suprimem drops depois de sair&voltar.
    DropEngine.resetRoomState()
    if not mcmDone and ModConfigMenu then
        local ok, result = pcall(MCM.setupMCM)
        if ok and result then mcmDone = true end
    end
end)

mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    Persistence.saveConfig()
end)

Isaac.DebugString("EnemyDropLootV2: v3.77 loaded" .. (S.HAS_REPENTOGON and " [REPENTOGON]" or "") .. (S.DEV_MODE and " [DEV_MODE]" or "") .. ((S.DEV_KEYS and not S.DEV_MODE) and " [DEV_KEYS]" or ""))

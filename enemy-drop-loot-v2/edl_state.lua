--[[
edl_state.lua — singletons do mod + TODO estado mutável compartilhado entre módulos.

Por que um arquivo só pra isso: em Lua, `require` NÃO compartilha upvalues/locals
entre arquivos. Uma variável tipo `runCount` que main.lua original lia e escrevia
de vários pontos do arquivo (tryDrop, saveConfig, loadConfig, os resets de run, o
overlay de debug) só continua "a mesma variável" entre os arquivos novos se virar
um CAMPO desta tabela (S.runCount), nunca um local re-declarado em cada arquivo.
Regra pra quem for mexer: nunca faça `local runCount = S.runCount` e depois escreva
nesse local — sempre `S.runCount = ...` direto, senão a escrita fica presa
naquele arquivo e os outros continuam vendo o valor velho.
]]

local S = {}

-- ============================================================
-- Singletons do mod (imutáveis após o load)
-- ============================================================
S.mod  = RegisterMod("EnemyDropLootV2", 1)
S.game = Game()
S.json = (function() local ok, m = pcall(require, "json"); return ok and m or nil end)()

S.SHIFT_DROP = 35

-- que eu saiba é assim que se checa o repentogon. não mexe nisso
S.HAS_REPENTOGON = (Isaac.GetPersistentGameData ~= nil)

-- ============================================================
-- ⚠️  DEV_MODE: bancada de teste. NUNCA subir true pro Workshop.
-- ============================================================
-- false = público (nenhum efeito, todos os gates curto-circuitam antes).
-- true  = no teu ambiente: watermark vermelho na tela + todo kill dropa item +
--         fura os filtros de dedup + HUD forçado com estado interno +
--         keybinds (ver edl_dropengine.lua) + aba "Dev" no MCM.
-- Se algum dia vazar ligado, o watermark torna impossível não perceber.
S.DEV_MODE = false
-- ⚠️ DEV_KEYS: versão LEVE, só os keybinds de número (1/2/3/4/0) + os avisos verdes.
-- SEM watermark, SEM forçar item em todo kill, SEM HUD verde, SEM furar dedup.
-- Pra usar em co-op ("me dá esse item aí") sem poluir a tela. TAMBÉM nunca subir true.
-- DEV_MODE=true já liga os keybinds; DEV_KEYS é pra ter SÓ eles.
S.DEV_KEYS = false
-- item fixo que a tecla 0 dá (default 619 = Birthright). Editável na aba Dev do MCM
-- (por isso é campo mutável, não constante: o MCM faz `S.devSpawnId = v`).
S.devSpawnId = 619
-- keybinds em teclas de NÚMERO (linha de cima do teclado). As teclas [ ] \ - confundiam.
S.DEV_KEY_ROLL    = Keyboard.KEY_1  -- 1  rola 1 item das pools do mod e spawna do lado (chão seguro)
S.DEV_KEY_GIVE    = Keyboard.KEY_2  -- 2  rola 1 item das pools do mod direto no inventário
S.DEV_KEY_RESET   = Keyboard.KEY_4  -- 4  limpa droppedItems/pendingSeeds/chosenGroups
S.DEV_KEY_REALDROP = Keyboard.KEY_5 -- 5  drop REAL (caminho de kill: conta pro dedup + reshuffle), pra testar pool esgotada
S.DEV_KEY_FIXED   = Keyboard.KEY_0  -- 0  spawna o "Spawn item id" fixo (devSpawnId) num pedestal

-- ============================================================
-- Persistência: contadores de run + dedup por-run (ver edl_persistence.lua)
-- ============================================================
S.runCount = 0

-- droppedItems = lista "não re-dropar o mesmo item nesta run" (usada pelo
-- REMOVE_FROM_POOL). Sem persistir, um Continue pós-fechamento esquece o que já
-- dropou nesta run, e um item DEIXADO NO CHÃO pode cair de novo de outro inimigo
-- (o check HasCollectible do spawnItem só barra item que você PEGOU). Por isso é
-- persistido: grava em saveConfig (inclusive no MC_PRE_GAME_EXIT), restaura em
-- loadConfig; "run nova limpa a lista" no POST_GAME_STARTED (if not isSave) já
-- cobre esse caso; só o Continue (isSave=true) precisa manter o que tava salvo.
S.PERSIST_DROPPED_ITEMS = true
S.droppedItems = {}

-- ── pendingSeeds: drops do mod que o player ainda NÃO pegou ─────────────────────
-- Rastreia por InitSeed (estável entre save/Continue) todo pedestal que o MOD spawnou
-- e que continua largado em ALGUMA sala do andar. O itemOnFloor() só enxerga a sala
-- atual; este cobre o andar inteiro. Uso: o reshuffle de pool esgotada
-- (poolExhaustedByDedup) NÃO pode ressuscitar um item que ainda está largado noutra
-- sala, e nesse caso o drop cai pra pickup em vez de repetir o mesmo item indefinidamente
-- (evita o cenário de pool estreita chovendo sempre os mesmos 2 itens). Só é populado
-- quando CFG.REMOVE_FROM_POOL está ligado. MC_POST_PICKUP_UPDATE reconcilia (SubType
-- 0 = pego; SubType trocado = rerollado). Run nova limpa; persiste no Continue junto
-- do droppedItems (mesmo flag PERSIST_DROPPED_ITEMS).
S.pendingSeeds = {}   -- [tostring(InitSeed)] = collectibleId

-- Cap de drops por sala (ver edl_dropengine.lua): contadores da sala + andar a que
-- pertencem. Persiste no Continue junto do droppedItems; run nova limpa (main.lua).
S.roomDrops = {}        -- [roomKey] = { items = N, pickups = N, kind = "normal"/"big"/"boss" }
S.roomDropsLevel = nil

-- ============================================================
-- Estado do drop engine (ver edl_dropengine.lua)
-- ============================================================
S.itemsByQuality  = { {}, {}, {}, {}, {} }
S.itemsReady      = false

-- Itens EXCLUSIVOS de Devil/Angel (ver buildDealSet em edl_dropengine.lua)
S.dealExclusive   = {}
S.dealFilterReady = false

-- Overlay de canto (CFG.DEBUG_OVERLAY). runStats zera em run nova (POST_GAME_STARTED
-- if not isSave); lastRoll é o resumo do kill mais recente.
S.runStats      = { items = 0, pickups = 0, kills = 0 }
S.lastRoll      = nil   -- { name, cat, itemChance, itemHit, resChance, resHit }
S.lastRollTimer = 0

return S

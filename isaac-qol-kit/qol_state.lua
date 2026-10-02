--[[
qol_state.lua - singletons do mod + TODO estado mutavel compartilhado entre modulos.

Por que um arquivo so pra isso: em Lua, `require` NAO compartilha upvalues/locals entre
arquivos. Uma variavel tipo `runCount`, escrita pelo qol_loadout.lua e lida pelo
qol_persistence.lua, so continua "a mesma variavel" entre os arquivos se for um CAMPO
desta tabela (S.runCount), nunca um local re-declarado em cada arquivo.

Regra pra quem for mexer: nunca faca `local runCount = S.runCount` e depois escreva
nesse local — sempre `S.runCount = ...` direto, senao a escrita fica presa naquele
arquivo e os outros continuam vendo o valor velho.

Este mod e INDEPENDENTE do Enemy Drop Loot V2: RegisterMod proprio, save proprio,
contadores de run proprios. Os dois rodam lado a lado sem conflito.
]]

local S = {}

-- ============================================================
-- Singletons do mod (imutaveis apos o load)
-- ============================================================
S.mod  = RegisterMod("IsaacQoLKit", 1)
S.game = Game()
S.json = (function() local ok, m = pcall(require, "json"); return ok and m or nil end)()

-- e assim que se checa o REPENTOGON. nao mexe nisso
S.HAS_REPENTOGON = (Isaac.GetPersistentGameData ~= nil)

-- shift do seed do RNG. Qualquer constante funciona, so precisa ser estavel.
S.SHIFT_LOADOUT = 35

-- ============================================================
-- Persistencia: contadores de run (ver qol_persistence.lua)
-- ============================================================
S.runCount = 0
-- runCount da ultima run em que o loadout inicial (fileira de trinket + penny do greed) ja
-- foi aplicado. Persistido no disco pra que fechar/reabrir o jogo e dar Continue NAO
-- reofereca (os flags de sessao resetam no reload do Lua e reaplicariam).
-- appliedRunCount == runCount ja significa "aplicado".
-- Default 0 (nao -1): se loadConfig falha (slot sem dados) + Continue (isSave=true),
-- runCount fica 0 (nao sobe), entao 0==0 bloqueia. Run nova (isSave=false) sobe runCount
-- pra 1, dispara.
S.appliedRunCount = 0
-- mesmo esquema do appliedRunCount, mas pro Active para Pocket: sem persistir, fechar/
-- reabrir o jogo resetava o pocketApplied em memoria e reaplicava a conversao no
-- Continue, pegando o item que estava ATUALMENTE no ativo (ja trocado durante a run) e
-- jogando ele pro pocket por engano.
S.pocketAppliedRunCount = 0

return S

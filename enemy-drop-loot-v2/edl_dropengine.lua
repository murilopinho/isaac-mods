--[[
edl_dropengine.lua — o coração do mod: pools de item por andar, registro de boss,
drops adaptados a personagem, spawn de recursos/carta, filtros de item, escolha de
item (pickAnyItem), spawn de item/pedestal, tryDrop (roda a cada inimigo morto),
overlay de debug e os keybinds de DEV_MODE/DEV_KEYS de teste.
]]

local S      = require("edl_state")
local Config = require("edl_config")

local mod  = S.mod
local game = S.game
local CFG  = Config.CFG
local HAS_REPENTOGON = S.HAS_REPENTOGON
local SHIFT_DROP = S.SHIFT_DROP
local DEV_MODE = S.DEV_MODE
local DEV_KEYS = S.DEV_KEYS
local itemsByQuality = S.itemsByQuality

local M = {}

-- ============================================================
-- Blacklist de itens de história/progressão
-- ============================================================
-- NÃO remova estes. são itens de história e spawná-los no meio da run quebra coisas.
-- aprendi na dor com a Knife Piece 1
local STORY_BLACKLIST = {
    [238]=true, -- Key Piece 1
    [239]=true, -- Key Piece 2
    [327]=true, -- The Polaroid
    [328]=true, -- The Negative
    [550]=true, -- Broken Shovel (1)
    [551]=true, -- Broken Shovel (2)
    [552]=true, -- Mom's Shovel
    [626]=true, -- Knife Piece 1
    [627]=true, -- Knife Piece 2
    [633]=true, -- Dogma
    [668]=true, -- Dad's Note
    [711]=true, -- Flip
    [714]=true, -- Recall
    [715]=true, -- Hold
}

-- ============================================================
-- Andar e suas pools de item acumuladas (cada tier adiciona uma pool nova)
-- ============================================================
local T = ItemPoolType
local FLOOR_POOLS = {
    -- Basement
    [1]  = { T.POOL_TREASURE },
    [2]  = { T.POOL_TREASURE },
    -- Caves: + Shop
    [3]  = { T.POOL_TREASURE, T.POOL_SHOP },
    [4]  = { T.POOL_TREASURE, T.POOL_SHOP },
    -- Depths: + Devil
    [5]  = { T.POOL_TREASURE, T.POOL_SHOP, T.POOL_DEVIL },
    [6]  = { T.POOL_TREASURE, T.POOL_SHOP, T.POOL_DEVIL },
    -- Womb/Utero (Chapter 4 normal): + Angel. NOTA: Corpse compartilha o LevelStage
    -- 7-8 mas é tratado à parte abaixo via StageID (não tem Shop lá).
    [7]  = { T.POOL_TREASURE, T.POOL_SHOP, T.POOL_DEVIL, T.POOL_ANGEL },
    [8]  = { T.POOL_TREASURE, T.POOL_SHOP, T.POOL_DEVIL, T.POOL_ANGEL },
    -- Blue Womb / Hush: + Secret. NOTA: Ultra Secret compartilha a pool Secret,
    -- e POOL_ULTRA_SECRET é um enum só do REPENTOGON (nil no Lua vanilla), então
    -- usar POOL_SECRET mantém estas tabelas sem buracos com ou sem REPENTOGON.
    [9]  = { T.POOL_TREASURE, T.POOL_SHOP, T.POOL_DEVIL, T.POOL_ANGEL, T.POOL_SECRET },
    -- Sheol/Cathedral: + Golden Chest
    [10] = { T.POOL_TREASURE, T.POOL_SHOP, T.POOL_DEVIL, T.POOL_ANGEL, T.POOL_SECRET, T.POOL_GOLDEN_CHEST },
    -- Dark Room/Chest: + Golden Chest
    [11] = { T.POOL_TREASURE, T.POOL_SHOP, T.POOL_DEVIL, T.POOL_ANGEL, T.POOL_GOLDEN_CHEST, T.POOL_SECRET },
    -- The Void: só Secret
    [12] = { T.POOL_SECRET },
    -- 13 = Home (The Beast), tratado via StageID abaixo. O Stage 14 não existe.
}

-- Durante a Ascensão (subindo de volta pra enfrentar The Beast) toda pool visitada
-- vale. Detectado via Level:IsAscent().
local ASCENT_POOLS = {
    T.POOL_TREASURE, T.POOL_SHOP, T.POOL_DEVIL,
    T.POOL_ANGEL, T.POOL_SECRET,
}

-- Andares alt/finais especiais identificados por StageID (o GetStage sozinho não
-- distingue Corpse de Womb, já que ambos são LevelStage 7-8).
local STAGEID_CORPSE = 33
local STAGEID_MORTIS = 34   -- Corpse II
local STAGEID_HOME   = 35   -- The Beast
-- Corpse: alt do Chapter 4 sem Shop (sem Schoolbag etc.)
local CORPSE_POOLS = { T.POOL_TREASURE, T.POOL_DEVIL, T.POOL_ANGEL, T.POOL_SECRET }
-- Home / The Beast: endgame
local HOME_POOLS   = { T.POOL_TREASURE, T.POOL_DEVIL, T.POOL_ANGEL, T.POOL_SECRET }

-- Índice do override de pool, mapeado pro ItemPoolType real
local POOL_OVERRIDE_MAP = {
    [1] = T.POOL_TREASURE,
    [2] = T.POOL_SHOP,
    [3] = T.POOL_BOSS,
    [4] = T.POOL_DEVIL,
    [5] = T.POOL_ANGEL,
    [6] = T.POOL_SECRET,
    [7] = T.POOL_LIBRARY,
    [8] = T.POOL_PLANETARIUM,
}
local POOL_OVERRIDE_NAMES = {
    [0] = "Auto (by floor)",
    [1] = "Treasure Room",
    [2] = "Shop",
    [3] = "Boss",
    [4] = "Devil Room",
    [5] = "Angel Room",
    [6] = "Secret Room",
    [7] = "Library",
    [8] = "Planetarium",
    [9] = "Chaos (random)",
}
local POOL_OVERRIDE_NAMES_GREED = {
    [0] = "Auto (by floor)",
    [1] = "Greed Treasure",
    [2] = "Greed Shop",
    [3] = "Greed Boss",
    [4] = "Greed Devil",
    [5] = "Greed Angel",
    [6] = "Greed Secret",
    [7] = "N/A (normal only)",
    [8] = "N/A (normal only)",
    [9] = "Chaos (random)",
}
local POOL_OVERRIDE_MAP_GREED = {
    [1] = T.POOL_GREED_TREASURE,
    [2] = T.POOL_GREED_SHOP,
    [3] = T.POOL_GREED_BOSS,
    [4] = T.POOL_GREED_DEVIL,
    [5] = T.POOL_GREED_ANGEL,
    [6] = T.POOL_GREED_SECRET,
}

-- Pools do modo Greed por ANDAR (Greed tem 7: Basement..Ultra Greed; o 7 usa a linha 6).
-- Pools POOL_GREED_* existem para: Treasure(16), Boss(17), Shop(18), Devil(19), Angel(20)
local GREED_CHAPTER_POOLS = {
    [1] = { T.POOL_GREED_TREASURE },
    [2] = { T.POOL_GREED_TREASURE, T.POOL_GREED_SHOP },
    [3] = { T.POOL_GREED_TREASURE, T.POOL_GREED_SHOP, T.POOL_GREED_DEVIL },
    [4] = { T.POOL_GREED_TREASURE, T.POOL_GREED_SHOP, T.POOL_GREED_DEVIL, T.POOL_GREED_ANGEL },
    [5] = { T.POOL_GREED_TREASURE, T.POOL_GREED_DEVIL, T.POOL_GREED_ANGEL },
    [6] = { T.POOL_GREED_TREASURE, T.POOL_GREED_DEVIL, T.POOL_GREED_ANGEL },
}

-- multiplicador de drop de item por dificuldade
local GREED_ITEM_MULT = {
    [2] = 0.6,  -- DIFFICULTY_GREED
    [3] = 0.35, -- DIFFICULTY_GREEDIER
}
-- multiplicador de drop de pickup por dificuldade (-50% greed, -70% greedier)
local GREED_RES_MULT = {
    [2] = 0.5,
    [3] = 0.3,
}

-- Fica true só enquanto spawna um drop de co-op Fair: faz os overrides de pool/qualidade
-- recuarem pra que o loot de co-op seja honesto ao andar (set/reset no tryDrop).
local coopFairHonest = false

-- Retorna a lista de pools ativas pro andar/contexto atual.
local function getActivePools()
    if CFG.POOL_OVERRIDE > 0 and not coopFairHonest then
        local map  = game:IsGreedMode() and POOL_OVERRIDE_MAP_GREED or POOL_OVERRIDE_MAP
        local pool = map[CFG.POOL_OVERRIDE]
        if pool then return { pool } end
        -- override inválido nesse modo (ex: Library/Planetarium no Greed):
        -- cai pro auto SEM sobrescrever a config salva.
    end
    -- Greed/Greedier: usa pools dedicadas de greed escaladas por capítulo
    if game:IsGreedMode() then
        -- por andar, não por wave: GreedModeWave reinicia a cada andar do Greed
        local chapter = math.max(1, math.min(6, game:GetLevel():GetStage()))
        return GREED_CHAPTER_POOLS[chapter] or { T.POOL_GREED_TREASURE }
    end
    local level = game:GetLevel()
    -- Ascensão (subindo de volta pro The Beast): checa primeiro, sobrepõe as pools do stage
    local okA, isAscent = pcall(function() return level:IsAscent() end)
    if okA and isAscent then return ASCENT_POOLS end
    -- Corpse/Mortis/Home precisam do StageID (GetStage não os distingue do Womb)
    local okID, sid = pcall(function() return level:GetStageID() end)
    if okID then
        if sid == STAGEID_CORPSE or sid == STAGEID_MORTIS then return CORPSE_POOLS end
        if sid == STAGEID_HOME then return HOME_POOLS end
    end
    local stage = level:GetStage()
    return FLOOR_POOLS[stage] or { T.POOL_TREASURE }
end

-- ============================================================
-- Cache de qualidade dos itens
-- ============================================================
local function buildItemTables()
    local ok, err = pcall(function()
        local itemConfig = Isaac.GetItemConfig()
        if not itemConfig then return end
        for q = 1, 5 do itemsByQuality[q] = {} end
        -- Varre a faixa REAL de ids pra incluir itens modados (Fiend Folio etc., ids > 999).
        -- Usa o tamanho do vetor de collectibles quando disponível; senão cai num
        -- teto generoso (GetCollectible retorna nil nos buracos, então é seguro).
        local maxId = 5000
        pcall(function()
            local cols = itemConfig:GetCollectibles()
            if cols and cols.Size then maxId = cols.Size - 1 end
        end)
        local count = 0
        for id = 1, maxId do
            local item = itemConfig:GetCollectible(id)
            if item and not item.Hidden then
                local q = item.Quality
                if q and q >= 0 and q <= 4 then
                    table.insert(itemsByQuality[q + 1], id)
                    count = count + 1
                end
            end
        end
        Isaac.DebugString("EnemyDropLoot: Loaded " .. count .. " items")
        if count > 0 then S.itemsReady = true end
    end)
    if not ok then
        Isaac.DebugString("EnemyDropLoot: buildItemTables ERROR - " .. tostring(err))
    end
end

-- ============================================================
-- Registro de tipos de boss
-- ============================================================
-- o REPENTOGON dá o IsBoss() então isso é só um fallback pro vanilla
local BOSS_TYPES = {
    [31]=true,[32]=true,[35]=true,[36]=true,[37]=true,[38]=true,
    [41]=true,[42]=true,[44]=true,[46]=true,[65]=true,[69]=true,
    [72]=true,[74]=true,[75]=true,[76]=true,[78]=true,[79]=true,[80]=true, -- 75 = Blastocyst médio (mesmo padrão do buraco de fases da Mom)
    [81]=true,[87]=true,[89]=true,[91]=true,[93]=true,[99]=true,
    [100]=true,[101]=true,[103]=true,[106]=true,[110]=true,[112]=true,
    [114]=true,[115]=true,[120]=true,[123]=true,[125]=true,[126]=true,
    [128]=true,[129]=true,[130]=true,[131]=true,[132]=true,[133]=true,
    [134]=true,[135]=true,[137]=true,[145]=true,[146]=true,[152]=true,
    [153]=true,[157]=true,[159]=true,[161]=true,[162]=true,[165]=true,
    [166]=true,[168]=true,[172]=true,[174]=true,[175]=true,[176]=true,
    [177]=true,[182]=true,[183]=true,[184]=true,[185]=true,[186]=true,
    [187]=true,[189]=true,[192]=true,[193]=true,[194]=true,[195]=true,
    [196]=true,[197]=true,[202]=true,[212]=true,[213]=true,[215]=true,
    [227]=true,[228]=true,[231]=true,[237]=true,[239]=true,[241]=true,
    [245]=true,[247]=true,[250]=true,[252]=true,[256]=true,[257]=true,
    [260]=true,[261]=true,[262]=true,[263]=true,[264]=true,
    [265]=true,[266]=true,[267]=true,[268]=true,[269]=true,[270]=true,
    [271]=true,[272]=true,[273]=true,[276]=true,[277]=true,[911]=true,
    -- 258=ENTITY_FAT_BAT NÃO entra aqui: é mob comum, não boss, apesar do nome sugerir
    -- o contrário. 263 (The Gate) e 265 (The Cage) SÃO bosses reais (Depths/Void/Boss
    -- Rush): conferir sempre contra a wiki/enums.lua, nunca só pelo nome do enum.

    -- Mom (Type 45) não entra nesta lista: é forçada à parte via FORCE_BOSS_TYPES por
    -- causa do fight multi-fase dela (ver abaixo).
    [19]=true,  -- Larry Jr. / The Hollow
    [20]=true,  -- Monstro
    [28]=true,  -- Chub
    [43]=true,  -- Monstro II
    [67]=true,  -- Duke of Flies / The Husk
    [68]=true,  -- Peep
    [84]=true,  -- Satan
    [274]=true, [275]=true, -- Mega Satan / Mega Satan 2
    -- Afterbirth+
    [401]=true, -- The Stain
    [402]=true, -- Brownie
    [403]=true, -- The Forsaken
    [404]=true, -- Little Horn
    [405]=true, -- Rag Man
    [406]=true, -- Ultra Greed
    [407]=true, -- Hush
    [409]=true, -- Rag Mega
    [411]=true, -- Big Horn
    [412]=true, -- Delirium
    -- Repentance
    [903]=true, -- Visage
    [904]=true, -- Siren
    [905]=true, -- Heretic
    [906]=true, -- Hornfel
    [907]=true, -- Gideon
    [908]=true, -- Baby Plum
    [909]=true, -- Scourge
    [910]=true, -- Chimera
    [912]=true, -- Mother
    [915]=true, -- Singe
    [950]=true, -- Dogma
    [951]=true, -- The Beast
}

-- Mom (Type 45) e a variante "Mom's Foot" do mesmo fight às vezes NÃO batem como boss
-- no IsBoss() nativo (o encontro tem múltiplas fases/pisadas que "morrem" separado).
-- Sem a flag de boss, o SEG_BOSS_DEDUP (mais abaixo) não protege, e cada fase rola de
-- novo, virando pedestal múltiplo, muito OP. Força true ANTES do IsBoss(), sem depender
-- da resposta nativa pra esse Type (45 nem está no fallback BOSS_TYPES, de propósito).
local FORCE_BOSS_TYPES = { [45] = true }

-- O REPENTOGON expõe npc:IsBoss() que pega TODO boss (a lista fixa BOSS_TYPES
-- perde vários). Cai pra lista quando o IsBoss não existe.
local function isBossEntity(npc)
    if FORCE_BOSS_TYPES[npc.Type] then return true end
    local ok, res = pcall(function() return npc:IsBoss() end)
    if ok and type(res) == "boolean" then return res end
    return BOSS_TYPES[npc.Type] == true
end

-- ============================================================
-- Bosses de história: CFG.STORY_BOSS_DROPS OFF por padrão = nenhum item/pickup
-- desses bosses. Todos os IDs abaixo conferidos contra o pacote
-- isaac-typescript-definitions (não chutados).
-- ============================================================
local STORY_BOSS_TYPES = {
    [84]  = true, -- Satan
    [102] = true, -- Isaac / ??? (Blue Baby) / Blue Baby corrompido pelo Hush: mesmo Type mas Variant diferente
    [273] = true, -- The Lamb
    [274] = true, [275] = true, -- Mega Satan / Mega Satan 2
    [407] = true, -- Hush
    [412] = true, -- Delirium (quando NÃO disfarçado de outro boss: ver isStoryBoss abaixo)
    [867] = true, -- Mother's Shadow (fase 1 do fight da Mother)
    [912] = true, -- Mother (fase 2)
    [950] = true, -- Dogma: a TV (variant 1) e as duas fases (0 e 2), mesmo Type
    [951] = true, -- The Beast + os 4 Ultra Horsemen (Famine/Pestilence/War/Death) e sub-partes:
                  -- tudo o mesmo Type=951, só a Variant muda (os "5 bosses" do fight)
}
-- Delirium se disfarça de QUALQUER boss já visto no save (copia o Type/Variant do alvo pra
-- imitar o ataque): bloquear só o Type 412 não pega ele disfarçado.
--   Blue Womb: o andar INTEIRO sem drop (inimigo comum também) - drop ali causava falhas.
--   The Void: tem o Delirium + ~5 bosses extras de preparação. Todos os BOSSES do andar
--   ficam sem drop (drop neles bugava e parava de dar item); inimigo comum dropa normal.
local STAGE_BLUE_WOMB = LevelStage.STAGE4_3
local STAGE_VOID      = LevelStage.STAGE7
local function isStoryBoss(npc)
    if STORY_BOSS_TYPES[npc.Type] then return true end
    local ok, stage = pcall(function() return game:GetLevel():GetStage() end)
    if not ok then return false end
    if stage == STAGE_BLUE_WOMB then return true end
    return stage == STAGE_VOID and isBossEntity(npc)
end

local function enemyCategory(npc)
    if not npc then return "NORMAL" end
    if isBossEntity(npc) then return "BOSS" end
    if npc:IsChampion() then return "CHAMPION" end
    return "NORMAL"
end

local function getFloorDepth()
    return math.floor((game:GetLevel():GetStage() + 1) / 2)
end

-- ============================================================
-- Overrides de drop adaptados ao personagem
-- ponytail: overrides mesclados por cima de CFG.RESOURCE_WEIGHTS na hora do drop;
--           heart_bone tem peso 0 na pool base (só ativa via override de char).
-- ============================================================
local PT = PlayerType
local CHAR_WEIGHT_OVERRIDES = {
    -- Keeper / T.Keeper: corações viram blue flies; moedas = valor real de HP
    [PT.PLAYER_KEEPER]          = { heart_red=0, heart_soul=0, heart_black=0, heart_eternal=0, heart_bone=0, coin=60 },
    [PT.PLAYER_KEEPER_B]        = { heart_red=0, heart_soul=0, heart_black=0, heart_eternal=0, heart_bone=0, coin=60 },
    -- Bethany: soul hearts servem de carga do ativo, boost pequeno
    [PT.PLAYER_BETHANY]         = { heart_soul=10 },
    -- T.Bethany: red hearts viram cargas de sangue (útil!); soul hearts = HP
    [PT.PLAYER_BETHANY_B]       = { heart_red=22, heart_soul=8 },
    -- The Forgotten: todos os tipos úteis; leve boost de bone heart
    [PT.PLAYER_THEFORGOTTEN]    = { heart_bone=6 },
    -- T.Forgotten: só soul hearts funcionam (compartilhado com T.Soul); remove red + bone
    [PT.PLAYER_THEFORGOTTEN_B]  = { heart_red=0, heart_bone=0, heart_soul=15 },
    -- Dark Judas: sem red containers health-ups dão black hearts, boost leve
    [PT.PLAYER_BLACKJUDAS]      = { heart_black=5 },
    -- T.Judas: começa morto (0 HP), reativa ao levar dano; red hearts não fazem nada sem containers
    [PT.PLAYER_JUDAS_B]         = { heart_red=0, heart_soul=12, heart_black=4 },
    -- Blue Baby / ???: sem red containers, soul hearts são o HP
    [PT.PLAYER_BLUEBABY]        = { heart_red=0, heart_soul=10 },
    [PT.PLAYER_BLUEBABY_B]      = { heart_red=0, heart_soul=10 },
    -- Azazel / T.Azazel: começa com black hearts; pode ganhar red containers no meio da run
    -- reduz red (menos útil cedo) mas não bloqueia; aumenta black (tipo de HP natural)
    [PT.PLAYER_AZAZEL]          = { heart_red=8, heart_black=10 },
    [PT.PLAYER_AZAZEL_B]        = { heart_red=8, heart_black=10 },
}

-- Overrides de Greed/Greedier: moedas são a moeda da loja aqui, inundar o Keeper de moedas
-- tira a tensão de gerenciar recurso que faz o Greed ser divertido.
-- O Keeper já tem o item nativo de coin-heart; ele não precisa de um fluxo constante de
-- moeda por cima. coin=8 com corações zerados = ~16% de chance de moeda (8/49) vs ~28% de um
-- char normal (25/90), um nerf significativo mas não uma remoção. moedas ainda pingam.
-- T.Keeper propositalmente de fora: inimigo dropar moeda é a mecânica nativa dele,
-- reduzir isso pelo mod conflitaria com a identidade do personagem.
local CHAR_WEIGHT_OVERRIDES_GREED = {
    [PT.PLAYER_KEEPER] = { heart_red=0, heart_soul=0, heart_black=0, heart_eternal=0, heart_bone=0, coin=8 },
}

-- ponytail: só player 0. co-op com personagens misturados é um edge case raro
local function getPrimaryPlayerType()
    local ok, pt = pcall(function()
        local p = Isaac.GetPlayer(0)
        return p and p:GetPlayerType()
    end)
    return ok and pt or nil
end

-- ── Nerf do tier champion com itens que inflam champions ──────────────────────────
-- Champion Belt (+15 flat na chance de champion, ~x4 sobre a base de 5%) e Purple Heart
-- (x2 multiplicativo) podem levar a chance de champion pra 20-100%. Aí o tier CHAMPION do
-- mod (drop ~2x o normal + card roll exclusivo) passa a valer pra sala inteira e o loot
-- explode e a pool esgota numa fração do tempo. Solução: dividir a taxa de champion
-- enquanto esses itens estão em jogo (x4 Belt, x2 Purple Heart, multiplicativo, igual à
-- fórmula vanilla), com PISO no tier normal (champion nunca dropa pior que lixo).
-- Espelha o GREED_ITEM_MULT, que já faz isso pra manter a economia do Greed intacta.
local function anyPlayerHas(collectibleId, trinketId)
    local ok, res = pcall(function()
        for i = 0, game:GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            if p then
                if collectibleId and p:HasCollectible(collectibleId) then return true end
                if trinketId and p:HasTrinket(trinketId) then return true end
            end
        end
        return false
    end)
    return ok and res == true
end

local function championRateDivisor()
    local div = 1
    if anyPlayerHas(CollectibleType.COLLECTIBLE_CHAMPION_BELT, nil) then div = div * 4 end
    if anyPlayerHas(nil, TrinketType.TRINKET_PURPLE_HEART)        then div = div * 2 end
    return div
end

-- ── Economia reativa: CFG.ECONOMY_REACT ────────────────────────────────────────
-- Itens do jogo que, somados ao mod, viram excesso de pickup. Retorna um divisor pra
-- resChance (nunca abaixo do piso NORMAL, aplicado no tryDrop). Multiplicativo, igual
-- ao championRateDivisor. Daemon's Tail é tratado à parte, direto no peso de coração
-- (ver DAEMONS_TAIL_HEART_MULT em spawnRes), aqui só o que mexe na CHANCE.
local HUMBLING_BUNDLE_ID = (CollectibleType and CollectibleType.COLLECTIBLE_HUMBLEING_BUNDLE) or 203  -- enum do jogo é escrito "HUMBLEING" (sic)
local function economyResDivisor()
    if not CFG.ECONOMY_REACT then return 1 end
    local div = 1
    -- Humbling Bundle já dobra o valor de todo pickup vanilla e o fluxo do mod por cima
    -- vira pickup demais. Corta ~33% (÷1.5) a taxa de pickup do mod enquanto está em jogo.
    if anyPlayerHas(HUMBLING_BUNDLE_ID, nil) then div = div * 1.5 end
    return div
end
-- Daemon's Tail (trinket 22): no vanilla deixa corações vermelhos mais raros e piores.
-- O mod respeita isso reduzindo o peso de heart_red no sorteio de pickup (spawnRes).
local DAEMONS_TAIL_ID = (TrinketType and TrinketType.TRINKET_DAEMONS_TAIL) or 22
local DAEMONS_TAIL_HEART_MULT = 0.35

-- Personagens de inventário-twin: Jacob & Esau e Tainted Lazarus (forma viva + morta)
-- cada um tem inventários de item SEPARADOS, então o pedestal único de uma morte só
-- equipa uma metade. O TWIN_DROP compensa dropando um segundo pedestal.
-- Montado por nome pra que um enum ausente em alguma versão do jogo/REPENTOGON seja pulado
-- em vez de crashar o mod com índice nil de tabela.
local TWIN_PLAYER_TYPES = {}
for _, name in ipairs({
    "PLAYER_JACOB",      -- Jacob (de Jacob & Esau)
    "PLAYER_ESAU",       -- Esau
    "PLAYER_LAZARUS_B",  -- Tainted Lazarus (forma viva)
    "PLAYER_LAZARUS2_B", -- Tainted Lazarus morto
}) do
    local v = PT[name]
    if v ~= nil then TWIN_PLAYER_TYPES[v] = true end
end
local function isTwinChar()
    local pt = getPrimaryPlayerType()
    return pt ~= nil and TWIN_PLAYER_TYPES[pt] == true
end

-- Lost / T.Lost ganha cartas e runas em vez de corações.
-- T.Lost já tem chance nativa de holy card; reduzimos aqui pra evitar overlap
local CARD_HOLY = (Card and Card.CARD_HOLY) or 55
-- Holy Card é desbloqueável (um achievement trava ela). o GetCard da item pool já
-- respeita unlocks, mas a gente força o spawn da Holy Card direto, o que BURLAVA isso e
-- dropava em saves onde ela ainda está travada. barra com o mesmo UNLOCK_FILTER
-- que os drops de item usam. falha seguro (sem Holy Card) quando não dá pra verificar.
local function holyCardAllowed()
    if CFG.UNLOCK_FILTER == 0 then return true end  -- filtro Off: usuário optou por conteúdo travado
    if not HAS_REPENTOGON then return false end     -- sem ele não dá pra checar unlocks, então não força
    local ok, unlocked = pcall(function()
        local c = Isaac.GetItemConfig():GetCard(CARD_HOLY)
        local ach = c and c.AchievementID
        if not ach or ach <= 0 then return true end -- sem trava de achievement = sempre disponível
        return Isaac.GetPersistentGameData():Unlocked(ach)
    end)
    return ok and unlocked or false
end
local function spawnLostCard(pos, rng, isTainted)
    rng:Next()
    -- O T.Lost já tem ~10% de chance nativa de Holy Card por carta então menos boost aqui
    local holyChance = isTainted and 20 or 30
    local cardId
    if rng:RandomInt(100) < holyChance and holyCardAllowed() then
        cardId = CARD_HOLY
    else
        -- runas/tarot da pool. o GetCard respeita unlocks então nada travado escapa
        cardId = game:GetItemPool():GetCard(rng:GetSeed(), false, true, false)
    end
    if cardId and cardId ~= Card.CARD_NULL then
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, cardId, pos, Vector(0, 0), nil)
    end
end

-- ============================================================
-- Spawn de recursos (pickups)
-- ============================================================
-- Escolhe um subtype por cascata de pesos do comum pro raro (mesmo esquema do RUNE_SHARE
-- lá embaixo em spawnCard): soma os pesos, rola 1..soma, o primeiro tier que "cobrir"
-- o valor sorteado vence. Cada categoria de pickup (moeda/chave/bomba/coração) tem sua
-- própria escala de raridade em vez de 50/50 flat.
local function weightedSub(rng, tiers)
    local total = 0
    for _, t in ipairs(tiers) do total = total + t.w end
    local roll = rng:RandomInt(total) + 1
    local acc = 0
    for _, t in ipairs(tiers) do
        acc = acc + t.w
        if roll <= acc then return t.val end
    end
    return tiers[1].val
end

local RES_TYPES = {
    -- Moeda: 1 moeda > 2 moedas > nickel > dime > lucky coin (mais raro)
    coin = { v=20, sub=function(rng)
        return weightedSub(rng, {
            { w=50, val = (CoinSubType and CoinSubType.COIN_PENNY)      or 1 },  -- 1 moeda
            { w=20, val = (CoinSubType and CoinSubType.COIN_DOUBLEPACK) or 4 },  -- 2 moedas
            { w=17, val = (CoinSubType and CoinSubType.COIN_NICKEL)     or 2 },  -- 1 nickel
            { w=10, val = (CoinSubType and CoinSubType.COIN_DIME)       or 3 },  -- 1 dime
            { w=3,  val = (CoinSubType and CoinSubType.COIN_LUCKYPENNY) or 5 },  -- 1 lucky coin
        })
    end },
    -- Chave: 1 chave > 2 chaves (mais rara)
    key = { v=30, sub=function(rng)
        return weightedSub(rng, {
            { w=80, val = (KeySubType and KeySubType.KEY_NORMAL)     or 1 },  -- 1 chave
            { w=20, val = (KeySubType and KeySubType.KEY_DOUBLEPACK) or 3 },  -- 2 chaves
        })
    end },
    -- Bomba: 1 bomba > 2 bombas (mais rara)
    bomb = { v=40, sub=function(rng)
        return weightedSub(rng, {
            { w=80, val = (BombSubType and BombSubType.BOMB_NORMAL)     or 1 },  -- 1 bomba
            { w=20, val = (BombSubType and BombSubType.BOMB_DOUBLEPACK) or 2 },  -- 2 bombas
        })
    end },
    -- Vida: dentro do próprio heart_red, 1 coração > 2 corações (mais raro). A ordem
    -- red > soul > black > eternal já vem dos pesos em CFG.RESOURCE_WEIGHTS (15/6/2/1).
    heart_red  = { v=10, sub=function(rng)
        return weightedSub(rng, {
            { w=75, val = HeartSubType.HEART_FULL       or 1 },  -- 1 coração
            { w=25, val = HeartSubType.HEART_DOUBLEPACK or 5 },  -- 2 corações
        })
    end },
    heart_soul = { v=10, sub=function() return HeartSubType.HEART_SOUL or 3 end },   
    heart_black= { v=10, sub=function() return HeartSubType.HEART_BLACK or 6 end },  
    heart_eternal={ v=10, sub=function() return HeartSubType.HEART_ETERNAL or 4 end },
    heart_bone = { v=10, sub=function() return HeartSubType.HEART_BONE or 11 end },
    battery    = { v=90, sub=function() return 1 end },
    -- Baú: sorteia o TIPO (variant); subtype é sempre 1 = fechado (ChestSubType só tem 0/1).
    -- 70% marrom > 15% dourado (chave) > 10% pedra (bomba) > 5% espinhos. Só tipos sem unlock.
    chest      = { v=50, var=function(rng)
        return weightedSub(rng, {
            { w=70, val = PickupVariant.PICKUP_CHEST },
            { w=15, val = PickupVariant.PICKUP_LOCKEDCHEST },
            { w=10, val = PickupVariant.PICKUP_BOMBCHEST },
            { w=5,  val = PickupVariant.PICKUP_SPIKEDCHEST },
        })
    end, sub=function() return 1 end },
}

local function spawnRes(pos, rng, weightOverrides)
    -- monta os pesos efetivos: CFG base mesclado com os overrides por personagem
    local weights = {}
    for k, v in pairs(CFG.RESOURCE_WEIGHTS) do weights[k] = v end
    if weightOverrides then
        for k, v in pairs(weightOverrides) do
            if v <= 0 then weights[k] = nil else weights[k] = v end
        end
    end
    -- Daemon's Tail em jogo deixa o coração vermelho mais raro (espelha o efeito vanilla).
    -- Aplicado DEPOIS dos overrides por-char pra que Azazel/Bethany (que já ajustam heart_red)
    -- ainda recebam o corte proporcional.
    if CFG.ECONOMY_REACT and weights.heart_red and anyPlayerHas(nil, DAEMONS_TAIL_ID) then
        weights.heart_red = math.max(1, math.floor(weights.heart_red * DAEMONS_TAIL_HEART_MULT))
    end
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    local sorted = {}
    for n,_ in pairs(weights) do table.insert(sorted, n) end
    table.sort(sorted)
    local cum = {}
    local c = 0
    for _, n in ipairs(sorted) do
        c = c + weights[n]
        table.insert(cum, { name=n, cum=c })
    end
    if total <= 0 then return end
    local roll = rng:RandomInt(total) + 1
    local name = "coin"
    for _, e in ipairs(cum) do
        if roll <= e.cum then name = e.name; break end
    end
    local rt  = RES_TYPES[name]
    local amt = CFG.RESOURCE_AMOUNT[name]
    if not rt or not amt then return end
    -- sempre 1: amt já é {1,1} pra tudo, mas mantém a fórmula por segurança
    local count = rng:RandomInt(amt[2] - amt[1] + 1) + amt[1]
    if count <= 0 then count = 1 end
    for _ = 1, count do
        local sub = rt.sub(rng)
        local off = Vector(rng:RandomInt(41) - 20, rng:RandomInt(41) - 20)
        local vel = Vector(rng:RandomInt(7)  - 3,  rng:RandomInt(7)  - 3)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, rt.var and rt.var(rng) or rt.v, sub, pos + off, vel, nil)
    end
end

-- ============================================================
-- Spawn de carta / runa
-- ============================================================
-- runas saem mais raras que cartas. o GetCard respeita unlocks sozinho então uma runa
-- travada já cai pra Rune Shard. a gente nunca entrega uma travada.
local RUNE_SHARE = 25   -- % dos drops de carta que saem como runa em vez de carta
local function spawnCard(pos, rng, spread)
    rng:Next()
    local pool = game:GetItemPool()
    local cardId
    -- GetCard(seed, playingCards, runes, onlyRunes)
    if rng:RandomInt(100) < RUNE_SHARE then
        cardId = pool:GetCard(rng:GetSeed(), false, true, true)    -- só runas (mais raro)
    else
        cardId = pool:GetCard(rng:GetSeed(), true, false, false)   -- tarot + baralho, sem runas
    end
    if not cardId or cardId == Card.CARD_NULL then return false end
    local off = Vector(0, 0)
    if spread then
        -- tem um pedestal de item no chão nessa morte; afasta ~1 tile pra carta
        -- não spawnar em cima dele (pickups sobrepostos podem bugar)
        local function away() return (rng:RandomInt(16) + 25) * (rng:RandomInt(2) == 0 and 1 or -1) end
        off = Vector(away(), away())
    end
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, cardId, pos + off, Vector(0, 0), nil)
    return true
end

-- ============================================================
-- Filtros de item
-- ============================================================

-- ponytail: só REPENTOGON. sem ele o modo por tier de qualidade não tem filtro de char
-- (o modo floor-pool é sempre seguro já que o GetCollectible() filtra internamente).
-- Falha aberto (retorna true) se o REPENTOGON não existe ou a chamada dá erro.
local function canSpawnForChar(id)
    if not HAS_REPENTOGON then return true end
    local ok, result = pcall(function()
        return game:GetItemPool():CanSpawnCollectible(id)
    end)
    return not ok or result ~= false
end

-- Itens EXCLUSIVOS de Devil/Angel: numa deal pool mas NÃO em nenhuma pool normal
-- (treasure/shop/boss/etc). montado uma vez pra que "No Deal Items" nunca bloqueie um item
-- que você também pegaria normalmente. vazio + dealFilterReady=false se a query de pool
-- do REPENTOGON não estiver disponível, caso em que o toggle do MCM some (sem no-op
-- silencioso). idFromEntry lida com os dois formatos de retorno (número ou {itemID=...}).
local function idFromEntry(e)
    if type(e) == "number" then return e end
    if type(e) == "table" then return e.itemID or e.ID or e.id or e[1] end
    return nil
end
local function buildDealSet()
    if not HAS_REPENTOGON then return end
    pcall(function()
        local pool = game:GetItemPool()
        if type(pool.GetCollectiblesFromPool) ~= "function" then return end
        local T2 = ItemPoolType
        local common = {}
        -- NOTA: sem POOL_ULTRA_SECRET aqui. é um enum só do REPENTOGON (nil no
        -- vanilla) e o código de propósito nunca o referencia. POOL_SECRET
        -- já cobre itens de ultra secret pra esse teste de "dá pra pegar normalmente".
        for _, p in ipairs({ T2.POOL_TREASURE, T2.POOL_SHOP, T2.POOL_BOSS, T2.POOL_SECRET,
                             T2.POOL_LIBRARY, T2.POOL_CURSE, T2.POOL_GOLDEN_CHEST,
                             T2.POOL_RED_CHEST, T2.POOL_CRANE_GAME, T2.POOL_PLANETARIUM }) do
            if p then for _, e in ipairs(pool:GetCollectiblesFromPool(p)) do
                local id = idFromEntry(e); if id then common[id] = true end
            end end
        end
        local deal = {}
        for _, p in ipairs({ T2.POOL_DEVIL, T2.POOL_ANGEL }) do
            if p then for _, e in ipairs(pool:GetCollectiblesFromPool(p)) do
                local id = idFromEntry(e); if id and not common[id] then deal[id] = true end
            end end
        end
        S.dealExclusive = deal
        S.dealFilterReady = true
    end)
end

local function isBlocked(id)
    if CFG.BLOCK_STORY_ITEMS and STORY_BLACKLIST[id] then return true end
    if CFG.BLOCK_TMTRAINER   and id == 721            then return true end
    if CFG.NO_DEAL_ITEMS and S.dealExclusive[id]      then return true end
    -- filtros de qualidade / tipo precisam do item config; pula a busca quando ambos off
    local minQ = coopFairHonest and -1 or CFG.MIN_QUALITY
    -- lock: o Min Quality vira teto também -> só aquele tier dropa. desligado em coop fair.
    local qLock = (CFG.QUALITY_LOCK and minQ >= 0) or minQ == 0 -- "0+" seria igual a any: 0 é sempre só Q0
    if minQ > 0 or CFG.ITEM_TYPE_FILTER ~= 0 or qLock then
        local cfgItem = Isaac.GetItemConfig():GetCollectible(id)
        if cfgItem then
            local q = cfgItem.Quality or 0
            if minQ > 0 and q < minQ then return true end
            if qLock and q > minQ then return true end -- bloqueia tiers acima do piso quando travado
            -- 1 = só passivos (bloqueia ativos); 2 = só ativos (bloqueia não-ativos)
            -- ponytail: literal 3 = ITEM_ACTIVE; ItemConfig pode não ser um global válido no Repentance base
            local isActive = cfgItem.Type == 3
            if CFG.ITEM_TYPE_FILTER == 1 and isActive     then return true end
            if CFG.ITEM_TYPE_FILTER == 2 and not isActive then return true end
        end
    end
    return false
end

-- "seen" = você realmente segurou esse item pelo menos uma vez (página de coleção).
-- falha fechado: se a query der erro, bloqueia em vez de vazar um item travado
-- 
local function itemSeen(id)
    local ok, inCollection = pcall(function()
        local pgd = Isaac.GetPersistentGameData()
        return pgd ~= nil and pgd:IsItemInCollection(id)
    end)
    if not ok then return false end
    return inCollection == true
end

-- "unlocked" = o achievement que trava esse item foi feito, mesmo que você nunca
-- tenha segurado. Itens sem achievement (AchievementID <= 0) estão sempre disponíveis.
-- se a query de unlock der erro (repentogon antigo sem Unlocked), cai pro
-- check mais estrito "seen" pra ainda nunca vazar um item travado.
local function itemUnlocked(id)
    local ok, res = pcall(function()
        local cfgItem = Isaac.GetItemConfig():GetCollectible(id)
        if not cfgItem then return false end
        local ach = cfgItem.AchievementID
        if not ach or ach <= 0 then return true end
        local pgd = Isaac.GetPersistentGameData()
        if pgd == nil then return nil end
        return pgd:Unlocked(ach)
    end)
    if not ok or res == nil then return itemSeen(id) end
    return res == true
end

-- 0 Off (libera tudo), 1 Unlocked (padrão), 2 Seen only. sem repentogon = libera tudo.
local function isUnlocked(id)
    if not HAS_REPENTOGON or CFG.UNLOCK_FILTER == 0 then return true end
    if CFG.UNLOCK_FILTER == 2 then return itemSeen(id) end
    return itemUnlocked(id)
end

-- ============================================================
-- Pesos de qualidade (escalam com a profundidade do andar quando ligado)
-- ============================================================
local function getQualityWeights()
    if not CFG.FLOOR_QUALITY_SCALING then return CFG.ITEM_QUALITY_WEIGHTS end
    local depth = getFloorDepth()
    local bonus = math.min((depth - 1) * 4, 20)
    return {
        { quality = 0, weight = math.max(35 - bonus * 2, 5) },
        { quality = 1, weight = math.max(30 - bonus,     5) },
        { quality = 2, weight = 20 },
        { quality = 3, weight = math.min(10 + bonus,    30) },
        { quality = 4, weight = math.min(5  + bonus,    20) },
    }
end

-- ============================================================
-- Escolha de item (item picking)
-- ============================================================
-- guarda o que já dropamos pra não dar o mesmo item duas vezes.
-- NÃO use RemoveCollectible aqui: drena a pool vanilla inteira (loja/treasure ficam vazios).
-- (droppedItems fica em edl_state.lua/S.droppedItems pra que saveConfig/loadConfig
--  alcancem o mesmo estado. ver S.PERSIST_DROPPED_ITEMS.)

-- Item que JÁ ESTÁ no chão da sala (pedestal não pego) conta como "já dropado". Sem isso,
-- com a pool efetiva reduzida a 1-2 itens (forced pool + QUALITY_LOCK + TYPE), o mod ficava
-- re-spawnando a mesma coisa enquanto você não pegasse (4x Glowing Hourglass no chão).
-- Agora: enquanto o pedestal está lá, o mod não dropa outra cópia; quando você pega, o
-- NO_DUPLICATES (HasCollectible) assume. Cache por frame já que FindByType roda várias vezes/pick.
local floorItemFrame = -1
local floorItemSet   = {}
local function itemOnFloor(id)
    local f = game:GetFrameCount()
    if f ~= floorItemFrame then
        floorItemFrame = f
        local set = {}
        pcall(function()
            for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1)) do
                local st = e.SubType
                if st and st > 0 then set[st] = true end
            end
        end)
        floorItemSet = set
    end
    return floorItemSet[id] == true
end

-- itemOnFloor() só vê a sala atual. isPendingDrop() cobre o ANDAR inteiro: id de um
-- pedestal que o mod dropou e que o player ainda não pegou (rastreado por InitSeed em
-- pendingSeeds). Cache do set reverso por frame pelo mesmo motivo do itemOnFloor.
local pendFrame  = -1
local pendSet    = {}
local function isPendingDrop(id)
    local f = game:GetFrameCount()
    if f ~= pendFrame then
        pendFrame = f
        local s = {}
        for _, pid in pairs(S.pendingSeeds) do s[pid] = true end
        pendSet = s
    end
    return pendSet[id] == true
end

local function pickItem(rng)
    if not S.itemsReady then return nil end
    local weights = getQualityWeights()
    local avail   = {}
    for q = 1, 5 do if #itemsByQuality[q] > 0 then table.insert(avail, q) end end
    if #avail == 0 then return nil end

    local totalW = 0
    for _, t in ipairs(weights) do totalW = totalW + t.weight end
    local roll = rng:RandomInt(totalW) + 1
    local cum  = 0
    local pick = avail[1]
    for _, t in ipairs(weights) do
        cum = cum + t.weight
        if roll <= cum then pick = t.quality + 1; break end
    end
    if #itemsByQuality[pick] == 0 then
        local best, bestQ = 999, avail[1]
        for _, q in ipairs(avail) do
            local d = math.abs(q - pick)
            if d < best then best = d; bestQ = q end
        end
        pick = bestQ
    end
    local pool = itemsByQuality[pick]
    local function valid(id)
        return id and not isBlocked(id) and isUnlocked(id)
           and not (CFG.REMOVE_FROM_POOL and S.droppedItems[id])
           and not itemOnFloor(id)
           and not isPendingDrop(id)
           and canSpawnForChar(id)
    end
    -- caminho rápido: 5 tentativas aleatórias na qualidade sorteada
    if #pool > 0 then
        for _ = 1, 5 do
            local id = pool[rng:RandomInt(#pool) + 1]
            if valid(id) then return id end
        end
    end
    -- fallback pra que um roll de drop bem-sucedido nunca venha vazio: as 5 tentativas
    -- aleatórias podem cair todas em itens filtrados (save novo com poucos unlocks, ou
    -- dedup pesado no fim da run) e desperdiçar o drop em silêncio. varre por qualquer id
    -- válido, a qualidade sorteada primeiro e depois o resto. só roda num drop real, custo ok.
    local cand = {}
    for _, id in ipairs(pool) do if valid(id) then cand[#cand+1] = id end end
    if #cand == 0 then
        for _, q in ipairs(avail) do
            if q ~= pick then
                for _, id in ipairs(itemsByQuality[q]) do if valid(id) then cand[#cand+1] = id end end
            end
        end
    end
    if #cand > 0 then return cand[rng:RandomInt(#cand) + 1] end
    return nil
end

local function pickItemFromFloorPool(rng)
    rng:Next()
    local pools = getActivePools()
    -- só ESPIA (removeItem=false): nunca tiramos nada da pool vanilla — ver nota em spawnItem.
    -- tenta de novo algumas vezes, avançando o rng a cada passo pra mudar o roll.
    for _ = 1, 8 do
        local pool = pools[rng:RandomInt(#pools) + 1]
        local id = game:GetItemPool():GetCollectible(pool, false, rng:GetSeed())
        if id and id ~= CollectibleType.COLLECTIBLE_NULL and id > 0
           and not isBlocked(id) and isUnlocked(id) and canSpawnForChar(id)
           and not (CFG.REMOVE_FROM_POOL and S.droppedItems[id])
           and not itemOnFloor(id)
           and not isPendingDrop(id) then
            return id
        end
        rng:Next()
    end
    return nil
end

-- Pool "%CHAOS%" (POOL_OVERRIDE = 9): ignora as pools do andar por completo, escolhe um
-- item cru de qualquer tier com chance FLAT (todo tier igualmente provável, caos de verdade,
-- não os pesos padrão que puxam pra baixo). Pra travar num tier use Min Quality + Quality Lock.
-- Ativo/passivo ainda obedece ITEM_TYPE_FILTER (dentro de isBlocked).
local function pickChaosItem(rng)
    if not S.itemsReady then return nil end
    local function valid(id)
        return id and not isBlocked(id) and isUnlocked(id)
           and not (CFG.REMOVE_FROM_POOL and S.droppedItems[id])
           and not itemOnFloor(id)
           and not isPendingDrop(id)
           and canSpawnForChar(id)
    end
    for _ = 1, 12 do
        -- índice do itemsByQuality = quality + 1 (quality 0..4 -> índice 1..5)
        local idx = rng:RandomInt(5) + 1
        local pool = itemsByQuality[idx]
        if pool and #pool > 0 then
            local id = pool[rng:RandomInt(#pool) + 1]
            if valid(id) then return id end
        end
        rng:Next()
    end
    return nil
end

-- ── Reshuffle da pool esgotada ────────────────────────────────────────────────
-- droppedItems (dedup por-run do REMOVE_FROM_POOL) nunca era trimado. Com a pool
-- estreitada (QUALITY_LOCK / ITEM_TYPE_FILTER / POOL_OVERRIDE / UNLOCK_FILTER, ou os
-- itens de champion inflando o volume de kills) o conjunto efetivo esgotava no meio da
-- run e o drop de item virava pickup em silêncio até reiniciar (o Continue zera a lista
-- na memória, daí o "só volta se eu saio e entro"). Fix: num roll de drop BEM-SUCEDIDO
-- que não achou item porque TODO candidato válido já foi dropado, reembaralha (a pool
-- vanilla esgotada volta a repetir) e tenta 1x de novo. Só dispara em esgotamento REAL.
-- "válido ignorando SÓ o dedup do REMOVE_FROM_POOL", mas item no chão ou pendente
-- continua excluído, senão o reshuffle ressuscitava um pedestal que você só não pegou
-- (o bug dos 4 iguais, o "chove Chaos+Car Battery" com pool estreita). itemOnFloor
-- vê só a sala atual; isPendingDrop cobre o andar inteiro. Sobrando só itens pendentes, o reshuffle
-- NÃO dispara e o drop vira pickup.
local function validIgnoringDedup(id)
    return id and id > 0 and not isBlocked(id) and isUnlocked(id)
       and not itemOnFloor(id) and not isPendingDrop(id) and canSpawnForChar(id)
end

-- ids no escopo do pick atual (pra confirmar esgotamento sem chutar):
-- floor/forced pool + REPENTOGON -> itens das pools ativas; senão -> itemsByQuality inteiro.
local function scopeItemIds()
    if CFG.POOL_OVERRIDE ~= 9 and (CFG.USE_FLOOR_POOL or CFG.POOL_OVERRIDE > 0) and HAS_REPENTOGON then
        local ids, ok = {}, false
        pcall(function()
            local pool = game:GetItemPool()
            if type(pool.GetCollectiblesFromPool) ~= "function" then return end
            for _, p in ipairs(getActivePools()) do
                for _, e in ipairs(pool:GetCollectiblesFromPool(p)) do
                    local id = idFromEntry(e); if id then ids[id] = true end
                end
            end
            ok = true
        end)
        if ok and next(ids) ~= nil then return ids end
    end
    local ids = {}
    for q = 1, 5 do for _, id in ipairs(itemsByQuality[q]) do ids[id] = true end end
    return ids
end

-- true só em esgotamento REAL: existe item que passa tudo menos o dedup, e ZERO que passa
-- com ele. sai cedo no 1º item ainda não-dropado (caso comum, sem custo).
local function poolExhaustedByDedup()
    if not CFG.REMOVE_FROM_POOL or next(S.droppedItems) == nil then return false end
    local anyIgnoring = false
    for id in pairs(scopeItemIds()) do
        if validIgnoringDedup(id) then
            if not S.droppedItems[id] then return false end
            anyIgnoring = true
        end
    end
    return anyIgnoring
end

-- Ponto único de roteamento pra "qual item?": chaos > floor-pool/override > pesos crus.
-- cache do check de esgotamento por frame: spawnItem chama pickAnyItem até 10x num loop,
-- e várias mortes acontecem no mesmo frame no room-clear. poolExhaustedByDedup varre a
-- pool inteira, então roda no máximo 1x por frame.
local exhaustCheckFrame  = -1
local exhaustCheckResult = false
local function pickAnyItem(rng)
    local function inner()
        if CFG.POOL_OVERRIDE == 9 and not coopFairHonest then return pickChaosItem(rng) end
        if CFG.USE_FLOOR_POOL or CFG.POOL_OVERRIDE > 0 then return pickItemFromFloorPool(rng) end
        return pickItem(rng)
    end
    local id = inner()
    if not id and CFG.REMOVE_FROM_POOL and next(S.droppedItems) ~= nil then
        local f = game:GetFrameCount()
        if f ~= exhaustCheckFrame then
            exhaustCheckFrame  = f
            exhaustCheckResult = poolExhaustedByDedup()
        end
        if exhaustCheckResult then
            Isaac.DebugString("EnemyDropLootV2: pool esgotada nesta run (REMOVE_FROM_POOL) — reembaralhando droppedItems")
            S.droppedItems = {}
            exhaustCheckResult = false
            id = inner()
        end
    end
    return id
end

-- ============================================================
-- Spawn de item
-- ============================================================

-- boss rooms: o pedestal vanilla spawna DEPOIS do MC_POST_ENTITY_KILL, então não dá pra detectar.
-- força o drop do mod a começar 80px à direita pra nunca cair em cima do pedestal vanilla.
local IS_BOSS_ROOM = false

local PEDESTAL_OFFSETS = {
    Vector( 80,   0),
    Vector(  0,  80),
    Vector(-80,   0),
    Vector(  0, -80),
    Vector( 80,  80),
    Vector(-80,  80),
    Vector( 80, -80),
    Vector(-80, -80),
}
local function resolvePedestalPos(pos)
    local function blocked(p)
        for _, e in ipairs(Isaac.FindInRadius(p, 50, EntityPartition.PICKUP)) do
            if e.Variant == PickupVariant.PICKUP_COLLECTIBLE then return true end
        end
        return false
    end
    -- em boss rooms sempre começa deslocado pra não empilhar no pedestal vanilla
    local startPos = IS_BOSS_ROOM and (pos + PEDESTAL_OFFSETS[1]) or pos
    if not blocked(startPos) then return startPos end
    for _, off in ipairs(PEDESTAL_OFFSETS) do
        local p = pos + off
        if not blocked(p) then return p end
    end
    return pos + PEDESTAL_OFFSETS[1]
end

-- Segundo pedestal pros personagens de inventário-twin. o modo "same" espelha o primeiro
-- item; senão rola um item independente, tentando de novo pra diferir do primeiro
-- (cai pro mesmo item se a pool não oferecer outro).
-- resolvePedestalPos acha um offset livre pra que os dois pedestais nunca empilhem.
-- ponytail: o pedestal bônus pula o check NO_DUPLICATES que o primeiro faz;
-- um dup raro no segundo não vale re-varrer a coleção de todo player.
-- o segundo pedestal fica AO LADO do primeiro, não em cima. não dá pra confiar no
-- resolvePedestalPos pra desviar do primeiro: um pickup recém-spawnado não aparece
-- no FindInRadius no mesmo frame, então ele retorna o mesmo lugar e os dois empilham
--  deslocar explicitamente resolve.
local TWIN_SIDE_OFFSET = Vector(60, 0)
local function spawnTwinPedestal(firstPos, rng, firstId)
    local id2
    if CFG.TWIN_SAME_ITEM then
        id2 = firstId
    else
        for _ = 1, 10 do
            local cand = pickAnyItem(rng)
            if cand and cand ~= firstId then id2 = cand; break end
        end
        if not id2 then id2 = firstId end  -- pool esgotada / só firstId disponível
    end
    local e2 = Isaac.Spawn(EntityType.ENTITY_PICKUP, 100, id2, resolvePedestalPos(firstPos + TWIN_SIDE_OFFSET), Vector(0, 0), nil)
    -- droppedItems só marca item genuinamente novo (o modo "same" reusa firstId, já marcado);
    -- pendingSeeds marca SEMPRE, já que o pedestal twin é uma 2ª cópia física com seed própria.
    if CFG.REMOVE_FROM_POOL then
        if id2 ~= firstId then S.droppedItems[id2] = true end
        if e2 then S.pendingSeeds[tostring(e2.InitSeed)] = id2 end
    end
end

-- ============================================================
-- Spawn de item em co-op (um pedestal por player, no pé de cada)
-- ============================================================
-- Co-op de verdade = 2+ controllers distintos. Jacob&Esau / Tainted Lazarus compartilham
-- UM controller (são metades gêmeas de um humano só), então isso retorna 1 pra eles
-- solo, já que o TWIN_DROP cobre esses, não o modo co-op. Dois humanos = 2.
local function coopControllerCount()
    local seen, n = {}, 0
    for i = 0, game:GetNumPlayers() - 1 do
        local ci = Isaac.GetPlayer(i).ControllerIndex
        if not seen[ci] then seen[ci] = true; n = n + 1 end
    end
    return n
end

-- Escolhe um item pra UM player. O check de dup é por-player (só o inventário DESSE
-- player) pra que seu amigo ainda possa rolar o mesmo item, essa é a ideia.
local function pickCoopItem(rng, player)
    for _ = 1, 10 do
        local id = pickAnyItem(rng)
        if id and not (CFG.NO_DUPLICATES and player:HasCollectible(id)) then
            return id
        end
    end
    return nil
end

local COOP_MIN_GAP = 45  -- distância mín. em px entre dois pedestais spawnados NESTE drop
local function coopFarEnough(p, used)
    for _, u in ipairs(used) do
        if (p - u):Length() < COOP_MIN_GAP then return false end
    end
    return true
end

-- Spawna um pedestal ao lado de CADA player (percorre os índices de player, então Jacob E
-- Esau cada um ganha o seu, já é o char do "pedestal diferente" resolvido de graça).
-- Cada pedestal cai perto do próprio player pra cada um pegar o seu; a gente desvia
-- tanto dos pedestais existentes (resolvePedestalPos) quanto dos spawnados neste mesmo
-- frame (used[], já que o FindInRadius não vê spawns do mesmo frame, era o antigo bug de
-- empilhamento do J&E). `markPool` marca itens dropados no Fair (distintos por run); o Chaos
-- deixa a pool livre pra que o mesmo item possa chover de novo.
local COOP_PLAYER_OFFSET = Vector(0, 25)  -- logo abaixo do player, não em cima do sprite
local function spawnCoopItem(rng, markPool)
    local used = {}
    local dropped = 0
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        local id = pickCoopItem(rng, player)
        if id then
            local base = player.Position + COOP_PLAYER_OFFSET
            local pos = resolvePedestalPos(base)
            local guard = 1
            while not coopFarEnough(pos, used) and guard <= #PEDESTAL_OFFSETS do
                pos = resolvePedestalPos(base + PEDESTAL_OFFSETS[guard])
                guard = guard + 1
            end
            local ce = Isaac.Spawn(EntityType.ENTITY_PICKUP, 100, id, pos, Vector(0, 0), nil)
            used[#used + 1] = pos
            -- markPool=false no Chaos co-op de propósito (o mesmo item pode chover)
            -- então nem droppedItems nem pendingSeeds nesse caso.
            if markPool and CFG.REMOVE_FROM_POOL then
                S.droppedItems[id] = true
                if ce then S.pendingSeeds[tostring(ce.InitSeed)] = id end
            end
            dropped = dropped + 1
        end
    end
    return dropped > 0 and dropped
end

local function spawnItem(pos, rng)
    for _ = 1, 10 do
        -- nil = item blocked/locked/filtrado OU pool esgotada; tenta de novo (limite 10)
        -- pra que um item ruim não engula o drop inteiro
        local id = pickAnyItem(rng)
        if not id then goto continue end

        local alreadyHas = false
        if CFG.NO_DUPLICATES then
            for i = 0, game:GetNumPlayers() - 1 do
                if Isaac.GetPlayer(i):HasCollectible(id) then
                    alreadyHas = true; break
                end
            end
        end

        if not alreadyHas then
            local pedPos = resolvePedestalPos(pos)
            local pe = Isaac.Spawn(EntityType.ENTITY_PICKUP, 100, id, pedPos, Vector(0, 0), nil)
            -- Marca como dropado na lista PRÓPRIA do mod pra não re-dropar nesta run.
            -- NÃO toca nas pools vanilla, lojas/treasure ficam intactas.
            -- pendingSeeds: rastreia esse pedestal até o player pegar (ver isPendingDrop).
            if CFG.REMOVE_FROM_POOL then
                S.droppedItems[id] = true
                if pe then S.pendingSeeds[tostring(pe.InitSeed)] = id end
            end
            -- Chars twin (Jacob & Esau, Tainted Lazarus) têm inventários separados:
            -- dropa um segundo pedestal pra ambas as metades equiparem de uma morte.
            if CFG.TWIN_DROP and isTwinChar() then
                spawnTwinPedestal(pedPos, rng, id)
                return 2
            end
            return 1
        end
        ::continue::
    end
    -- nada válido pra spawnar (filtros/dups esgotaram toda tentativa). retorna false pra
    -- que o chamador caia num pickup em vez de desperdiçar o item-roll ganho.
    return false
end

-- ============================================================
-- Dedup de boss segmentado (ATIVADO)
-- Problema: Larry Jr, Chub, etc. cada segmento dispara um drop.
-- Fix: rastreia quais tipos de boss já dropou nesta sala;
--      só o primeiro segmento a morrer ganha o loot.
-- Edge case: Double Trouble com 2 bosses do mesmo tipo = só 1 dropa.
-- Ativado: impede o BOSS_GUARANTEED_ITEM de multiplicar entre segmentos.
-- ============================================================
local SEG_BOSS_DEDUP = true
local bossTypeDroppedInRoom = {}

-- ============================================================
-- Boss Rush: ~20 bosses na mesma sala, cada um categoria BOSS. Sem limite, cada um
-- rola independente e o dedup acima (por Type) não ajuda aqui, são tipos DIFERENTES,
-- não segmentos do mesmo boss. CFG.BOSS_RUSH_LIMIT (OFF por padrão) trava em 1 drop
-- de boss no total pra sala inteira quando ligado.
-- ============================================================
local IS_BOSS_RUSH_ROOM = false
local bossRushDropped = false

-- Cap de drops por sala (anti-farm, só Normal/Hard): teto de itens/pickups por sala que
-- NÃO reseta ao sair/voltar nem no Continue. Estado em S.roomDrops (persistido em
-- edl_persistence.lua, limpo em run nova no main.lua). Trocar de andar descarta as salas
-- do andar anterior (os índices 0-168 se repetem). Greed/Greedier: sem cap nenhum.
-- Co-op: o cap multiplica pelo nº de players reais (2p = x2, 3p = x3, 4p = x4).
local ROOM_DROP_CAPS = {
    normal = { items = 2, pickups = 5  },
    big    = { items = 3, pickups = 8  },
    boss   = { items = 5, pickups = 12 },
}

-- IH/IV (corredor estreito de 1x1) ficam de fora de proposito: sao MENORES que a sala
-- comum, entao usam o cap normal.
local BIG_ROOM_SHAPES = {
    [RoomShape.ROOMSHAPE_1x2]=true, [RoomShape.ROOMSHAPE_2x1]=true,
    [RoomShape.ROOMSHAPE_IIV]=true, [RoomShape.ROOMSHAPE_IIH]=true,
    [RoomShape.ROOMSHAPE_2x2]=true,
    [RoomShape.ROOMSHAPE_LTL]=true, [RoomShape.ROOMSHAPE_LTR]=true,
    [RoomShape.ROOMSHAPE_LBL]=true, [RoomShape.ROOMSHAPE_LBR]=true,
}

local function levelKey()
    local ok, k = pcall(function()
        local lv = game:GetLevel()
        local asc = false
        pcall(function() asc = lv:IsAscent() end)
        return lv:GetStage() .. "_" .. lv:GetStageType() .. (asc and "a" or "")
    end)
    return ok and k or "?"
end

local function currentRoomKey()
    local ok, k = pcall(function()
        local lv = game:GetLevel()
        return tostring(lv:GetCurrentRoomIndex())
    end)
    return ok and k or "?"
end

local function roomKind(room)
    local okT, roomType = pcall(function() return room:GetType() end)
    if okT and (roomType == RoomType.ROOM_BOSS or roomType == RoomType.ROOM_BOSSRUSH) then return "boss" end
    local okS, shape = pcall(function() return room:GetRoomShape() end)
    if okS and BIG_ROOM_SHAPES[shape] then return "big" end
    return "normal"
end

local function getRoomDropEntry()
    local lk = levelKey()
    if S.roomDropsLevel ~= lk then S.roomDropsLevel = lk; S.roomDrops = {} end
    local key = currentRoomKey()
    local e = S.roomDrops[key]
    if not e then
        local ok, room = pcall(function() return game:GetRoom() end)
        local kind = (ok and room) and roomKind(room) or "normal"
        e = { items = 0, pickups = 0, kind = kind }
        S.roomDrops[key] = e
    end
    return e
end
-- pra CFG.BOSS_RUSH_PER_WAVE: Boss Rush não tem contador de wave nativo (tipo
-- GreedModeWave), então detecta a troca de wave via "sala esvaziou de inimigos,
-- depois voltou a ter" no MC_POST_UPDATE lá embaixo.
local bossRushRoomWasEmpty = true

-- ============================================================
-- Lógica de drop (RNG por-entidade, anti-duplicata)
-- ============================================================
local droppedSeeds = {}

-- Não-inimigos que disparam MC_POST_ENTITY_KILL mas NÃO devem dropar loot:
-- shopkeepers, beggars/slot machines/cartomantes/doação (todos ENTITY_SLOT),
-- e fireplaces.
local NON_LOOT_TYPES = {
    [EntityType.ENTITY_SHOPKEEPER] = true, -- 17
    [EntityType.ENTITY_SLOT]       = true, -- 6: beggars + todas as máquinas
    [EntityType.ENTITY_FIREPLACE]  = true, -- 33
    [293]                          = true, -- ENTITY_ULTRA_COIN: spawns de moeda do greed mode
    -- 263 (ENTITY_GATE) NÃO entra aqui: apesar do nome, é "The Gate", um BOSS de
    -- verdade (Depths/Void/Boss Rush/degradado em Sheol-Chest-Dark Room-Corpse), não
    -- um gate de wave do greed. Bloquear ele mata o loot desse boss inteiro.
}

local function tryDrop(entity)
    local npc = entity:ToNPC()
    if not npc then return end
    if NON_LOOT_TYPES[npc.Type] then return end
    if not CFG.STORY_BOSS_DROPS and isStoryBoss(npc) then return end
    -- guarda extra: só inimigos reais (exclui qualquer outro NPC neutro/amigo).
    -- falha aberto se IsActiveEnemy não existir pra nunca suprimir um drop real.
    local okE, active = pcall(function() return npc:IsActiveEnemy(true) end)
    if okE and active == false then return end
    if droppedSeeds[npc.InitSeed] then return end
    -- dedup de boss segmentado: bloqueia só DEPOIS que um segmento realmente dropou (marcado
    -- lá embaixo). checar aqui mas marcar no sucesso significa que um roll falho não queima
    -- a chance de drop do boss inteiro, o próximo segmento ainda rola.
    local isBoss = isBossEntity(npc)
    if SEG_BOSS_DEDUP and isBoss and bossTypeDroppedInRoom[npc.Type] then return end
    -- Boss Rush: ~20 tipos DIFERENTES de boss na mesma sala, o dedup acima (por Type) não
    -- os limita entre si. Com o toggle ligado, para de rolar assim que UM boss já dropou.
    if CFG.BOSS_RUSH_LIMIT and isBoss and IS_BOSS_RUSH_ROOM and bossRushDropped then return end

    local rng = npc:GetDropRNG()
    if not rng then return end
    -- marca o inimigo antes dos rolls: se o MC_POST_ENTITY_KILL disparar de novo pro
    -- mesmo InitSeed (inimigo que "morre" duas vezes), ele não ganha um segundo roll.
    droppedSeeds[npc.InitSeed] = true
    -- mistura runCount no seed pra que o mesmo inimigo não drope o mesmo item a cada restart (R).
    -- não sei por que 1000003 especificamente, é só um primo grande. parece funcionar
    local seed = (npc.InitSeed + S.runCount * 1000003) % 4294967296
    -- o RNG crasha se o seed for 0. levei um tempão pra achar esse bug. NÃO remova esse check
    if seed == 0 then seed = 1 end
    rng:SetSeed(seed, SHIFT_DROP)
    -- descorrelaciona: o PRIMEIRO RandomInt logo após SetSeed é viesado, e inimigos
    -- numa sala têm InitSeeds quase sequenciais, então os primeiros rolls deles se agrupam. isso
    -- fazia taxas baixas não dropar nada e 15% dropar tudo de uma vez. avançar uma vez
    -- resolve (toda outra função de spawn aqui já faz isso antes do primeiro roll).
    rng:Next()

    local cat   = enemyCategory(npc)
    local floor = getFloorDepth()
    local scale = 1
    if floor > 1 then
        scale = math.max(1 - (CFG.FLOOR_SCALING_PCT / 100) * (floor - 1), 0)
    end

    -- game.Difficulty é um CAMPO: 0=Normal 1=Hard 2=Greed 3=Greedier
    local greedMult    = GREED_ITEM_MULT[game.Difficulty] or 1.0
    local greedResMult = GREED_RES_MULT[game.Difficulty] or 1.0
    local itemChance = CFG.ITEM_DROP_RATE[cat] * scale * greedMult
    local resChance  = CFG.RESOURCE_DROP_RATE[cat] * scale * greedResMult

    -- co-op: ativo só com 2+ controllers reais e um modo selecionado. O Fair divide
    -- a taxa pra que N pedestais por-player ≈ total solo (balanceado); o Chaos deixa
    -- cheia pra que N pedestais ≈ N x loot (bagunça, o padrão).
    local coopN  = coopControllerCount()
    local coopOn = CFG.COOP_MODE > 0 and coopN > 1
    if coopOn and CFG.COOP_MODE == 1 then
        itemChance = itemChance / coopN
        resChance  = resChance  / coopN
    end

    -- Opção B: nerf do tier champion enquanto Champion Belt / Purple Heart estão em jogo.
    -- Só cat=="CHAMPION" (champion boss é cat=="BOSS", fica de fora: ≤1 por sala e o Belt
    -- nem afeta chance de champion boss). Piso no tier normal.
    local champDiv = (cat == "CHAMPION") and championRateDivisor() or 1
    if champDiv > 1 then
        itemChance = math.max(itemChance / champDiv, CFG.ITEM_DROP_RATE.NORMAL     * scale * greedMult)
        resChance  = math.max(resChance  / champDiv, CFG.RESOURCE_DROP_RATE.NORMAL * scale * greedResMult)
    end

    -- pickup do mod mais raro enquanto itens que já inflam pickup vanilla estão em
    -- jogo (Humbling Bundle divide por 1.5, ~-33% uniforme). Divisor leve, piso 1% pra nunca zerar.
    local ecoDiv = economyResDivisor()
    if ecoDiv > 1 then
        resChance = math.max(resChance / ecoDiv, 1)
    end

    -- ⚠️ DEV_MODE: todo kill dropa item (ignora scaling/champion/greed/economia).
    if DEV_MODE then itemChance = 100 end

    S.runStats.kills = S.runStats.kills + 1

    local isChampion = npc:IsChampion()

    local didDrop = false
    local didItem = false
    -- rastreia se o roll de item disparou (mesmo que o spawnItem não ache um item válido)
    local didItemRoll = false
    local bossGuaranteed = CFG.ITEM_DROP_ENABLED and CFG.BOSS_GUARANTEED_ITEM and cat == "BOSS"
    -- roll de item primeiro. se ganha mas filtros/dups não deixam nada pra spawnar,
    -- o spawnItem retorna false e a gente cai num pickup em vez de desperdiçar o drop
    -- em silêncio (os filtros novos agressivos tornaram isso alcançável).
    -- Cap anti-farm por sala (só Normal/Hard). No Greed roomEntry é uma tabela solta com
    -- teto infinito, então os incrementos lá embaixo não afetam nada.
    local roomEntry, itemCap, pickupCap
    if game:IsGreedMode() then
        roomEntry, itemCap, pickupCap = { items = 0, pickups = 0 }, math.huge, math.huge
    else
        roomEntry = getRoomDropEntry()
        local mult = math.max(coopN, 1)
        itemCap   = ROOM_DROP_CAPS[roomEntry.kind].items   * mult
        pickupCap = ROOM_DROP_CAPS[roomEntry.kind].pickups * mult
    end
    local itemCapHit = roomEntry.items >= itemCap
    if CFG.ITEM_DROP_ENABLED and not itemCapHit and (bossGuaranteed or rng:RandomInt(100) < itemChance) then
        didItemRoll = true
        local ok
        if coopOn then
            -- pcall: se spawnCoopItem der erro no meio (ex: estado de player inesperado), o
            -- `coopFairHonest = false` logo abaixo NUNCA rodava sem o pcall, e a flag
            -- ficava travada em true pro resto da sessão e todo drop dali em diante (mesmo fora
            -- de coop) passaria a ignorar Min Quality/Pool Override silenciosamente. pcall garante
            -- que o reset abaixo sempre roda, erro ou não.
            coopFairHonest = (CFG.COOP_MODE == 1)  -- Fair ignora os overrides de pool/qualidade
            local okCall, res = pcall(spawnCoopItem, rng, CFG.COOP_MODE == 1)
            coopFairHonest = false
            ok = okCall and res
        else
            ok = spawnItem(entity.Position, rng)
        end
        if ok then didItem = true; didDrop = true; S.runStats.items = S.runStats.items + 1; roomEntry.items = roomEntry.items + ok end
    end
    -- o recurso continua mutuamente exclusivo com o item (um ou outro, o roll de item ganha).
    -- pro T.Lost: pula a holy card de consolação quando o roll de item já disparou mas
    -- o spawnItem falhou (filtro barrou). holy card como consolação de item-falho é forte
    -- demais. outros chars ganham um pickup leve aqui, o T.Lost ganharia uma cura cheia.
    local resRollHit = (not didItem) and CFG.RESOURCE_DROP_ENABLED and roomEntry.pickups < pickupCap and rng:RandomInt(100) < resChance
    if resRollHit then
        if CFG.CHAR_ADAPT_ENABLED then
            local pt = getPrimaryPlayerType()
            if pt == PT.PLAYER_THELOST or pt == PT.PLAYER_THELOST_B then
                -- só champions e bosses; boss-champion = mesma taxa de boss (cat já é
                -- "BOSS" pra qualquer boss, independente de ser champion)
                if not didItemRoll and cat ~= "NORMAL" then
                    spawnLostCard(entity.Position, rng, pt == PT.PLAYER_THELOST_B)
                    didDrop = true
                    S.runStats.pickups = S.runStats.pickups + 1
                    roomEntry.pickups = roomEntry.pickups + 1
                end
            else
                local overrides = (game:IsGreedMode() and CHAR_WEIGHT_OVERRIDES_GREED[pt]) or CHAR_WEIGHT_OVERRIDES[pt]
                spawnRes(entity.Position, rng, overrides)
                didDrop = true
                S.runStats.pickups = S.runStats.pickups + 1
                roomEntry.pickups = roomEntry.pickups + 1
            end
        else
            spawnRes(entity.Position, rng)
            didDrop = true
            S.runStats.pickups = S.runStats.pickups + 1
            roomEntry.pickups = roomEntry.pickups + 1
        end
    end
    -- carta/runa é um roll INDEPENDENTE por cima (só champions). nunca substitui o
    -- item ou o recurso. pra um boss ela dropa junto do item garantido, afastada do
    -- pedestal. boss-champions só qualificam quando Boss Guaranteed está ligado, a 3x a taxa.
    if CFG.CARD_RUNE_ENABLED and isChampion then
        local cardChance = 0
        if cat == "BOSS" then
            if bossGuaranteed then cardChance = CFG.CARD_DROP_RATE * scale * 3 end
        else
            cardChance = CFG.CARD_DROP_RATE * scale
            -- Opção B: mesmo nerf do item. sem isso o card roll (exclusivo de champion)
            -- dispara em quase todo kill quando a chance de champion está inflada.
            if champDiv > 1 then cardChance = cardChance / champDiv end
        end
        if cardChance > 0 and rng:RandomInt(100) < cardChance then
            if spawnCard(entity.Position, rng, didItem) then didDrop = true end
        end
    end

    if didDrop then
        -- marca o tipo do boss como dropado só no sucesso, pra segmentos não desperdiçarem o roll
        if SEG_BOSS_DEDUP and isBoss then bossTypeDroppedInRoom[npc.Type] = true end
        if CFG.BOSS_RUSH_LIMIT and isBoss and IS_BOSS_RUSH_ROOM then bossRushDropped = true end
    end

    -- resumo do último kill pro overlay (só monta a string se o overlay pede rolls)
    if CFG.DEBUG_OVERLAY >= 2 or DEV_MODE then
        local nm = cat
        pcall(function() local n = npc:GetName(); if n and n ~= "" then nm = n end end)
        S.lastRoll = {
            name = nm, cat = cat,
            itemChance = itemChance, itemHit = didItem,
            resChance = resChance,  resHit = (resRollHit == true and not didItem),
        }
        S.lastRollTimer = 150  -- ~2.5s @ 60fps
    end
end

mod:AddCallback(ModCallbacks.MC_POST_ENTITY_KILL, function(_, entity)
    if entity:ToNPC() then tryDrop(entity) end
end)

-- declarado antes de resetRoomState pra que a closure capture ESTE local (um upvalue),
-- não um global perdido. também reseta a cada wave do Greed via POST_UPDATE abaixo.
local lastGreedWave = -1

-- Reset de estado por-sala. Chamado do POST_NEW_ROOM E do POST_GAME_STARTED:
-- no "Continue", o POST_NEW_ROOM NÃO dispara até você trocar de sala, então esse estado
-- ficaria velho de antes da saída e suprimiria drops ("sem drop depois de sair &
-- voltar"). runCount/droppedItems são por-run e de propósito NÃO são tocados aqui.
local function resetRoomState()
    droppedSeeds = {}
    bossTypeDroppedInRoom = {}
    bossRushDropped = false
    bossRushRoomWasEmpty = true
    lastGreedWave = -1
    pcall(function()
        local roomType = game:GetLevel():GetCurrentRoom():GetType()
        IS_BOSS_ROOM = roomType == RoomType.ROOM_BOSS
        IS_BOSS_RUSH_ROOM = roomType == RoomType.ROOM_BOSSRUSH
    end)
end

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, resetRoomState)

-- Reconcilia pendingSeeds: quando um pedestal que O MOD dropou é esvaziado (player pegou,
-- SubType 0) some do rastreio; se foi rerollado (D6/D-Infinity) segue o item novo. Só
-- olha os pedestais carregados (sala atual), os de outras salas ficam pendentes de
-- propósito (é o ponto: não re-dropar item ainda largado). Pedestal destruído por bomba/
-- pit fica "pendente pra sempre": falha benigna (o mod prefere pickup a repetir).
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, function(_, pickup)
    local key = tostring(pickup.InitSeed)
    local tracked = S.pendingSeeds[key]
    if tracked then
        if pickup.SubType == 0 then
            S.pendingSeeds[key] = nil
        elseif pickup.SubType ~= tracked then
            S.pendingSeeds[key] = pickup.SubType
        end
    end
end, PickupVariant.PICKUP_COLLECTIBLE)

-- Greed mode: droppedSeeds precisa resetar a cada wave (mesma sala, inimigos novos)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not game:IsGreedMode() then return end
    local wave = game:GetLevel().GreedModeWave or 0
    if wave ~= lastGreedWave then
        lastGreedWave = wave
        droppedSeeds = {}
        bossTypeDroppedInRoom = {}
    end
end)

-- Boss Rush "per wave": libera 1 drop novo a cada wave, em vez de 1 pro Boss Rush
-- inteiro. Só roda com os dois toggles ligados (BOSS_RUSH_LIMIT + BOSS_RUSH_PER_WAVE).
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not (IS_BOSS_RUSH_ROOM and CFG.BOSS_RUSH_LIMIT and CFG.BOSS_RUSH_PER_WAVE) then return end
    local ok, count = pcall(function() return Isaac.CountEnemies() end)
    if not ok then return end
    if count <= 0 then
        bossRushRoomWasEmpty = true
    elseif bossRushRoomWasEmpty then
        bossRushRoomWasEmpty = false
        bossRushDropped = false  -- wave nova: libera o drop de novo
    end
end)

-- ── Overlay público de debug (CFG.DEBUG_OVERLAY) + ⚠️ DEV_MODE watermark ─────────
-- devToast: aviso curto que os keybinds do DEV disparam ("spawned X", "given X"...),
-- fade curto no canto da tela. Só aparece com DEV_MODE.
local devToastMsg, devToastTimer = nil, 0
local function devToast(msg) devToastMsg, devToastTimer = msg, 90 end
local function itemName(id)
    local nm
    pcall(function()
        local c = Isaac.GetItemConfig():GetCollectible(id)
        if c and c.Name and c.Name ~= "" and c.Name:sub(1, 1) ~= "#" then nm = c.Name end
    end)
    return nm and (nm .. " (#" .. id .. ")") or ("#" .. id)
end
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if DEV_MODE then
        Isaac.RenderText("DEV MODE ACTIVE", 30, 22, 1, 0.15, 0.15, 1)
    end
    if (DEV_MODE or DEV_KEYS) and devToastTimer > 0 then
        devToastTimer = devToastTimer - 1
        local a = math.min(devToastTimer / 30, 1)
        Isaac.RenderText(devToastMsg or "", 30, Isaac.GetScreenHeight() - 42, 0.4, 1, 0.4, a)
    end
    if S.lastRollTimer > 0 then S.lastRollTimer = S.lastRollTimer - 1 end
    if CFG.DEBUG_OVERLAY <= 0 and not DEV_MODE then return end
    local x = Isaac.GetScreenWidth() - 210
    local y = 34
    local function ln(s, r, g, b) Isaac.RenderText(s, x, y, r or 1, g or 1, b or 0.7, 1); y = y + 11 end
    ln(("run: %d items  %d pickups  %d kills"):format(S.runStats.items, S.runStats.pickups, S.runStats.kills), 0.75, 1, 0.75)
    if (CFG.DEBUG_OVERLAY >= 2 or DEV_MODE) and S.lastRoll and S.lastRollTimer > 0 then
        local it = ("item %d%% %s"):format(math.floor(S.lastRoll.itemChance + 0.5), S.lastRoll.itemHit and "HIT" or "miss")
        local rs = ("pickup %d%% %s"):format(math.floor(S.lastRoll.resChance + 0.5), S.lastRoll.resHit and "HIT" or "miss")
        ln((S.lastRoll.name or "?") .. ":", 0.7, 0.85, 1)
        ln("  " .. it .. "  ·  " .. rs, 0.7, 0.85, 1)
    end
end)

-- ── ⚠️ DEV_MODE handlers (keybinds 1/2/4/5/0), inertes com DEV_MODE=false ──────
-- RNG próprio pro roll do dev, pra não perturbar o stream de drop do jogo.
local devRng = RNG()
local GRID_COLL_PIT = (GridCollisionClass and GridCollisionClass.COLLISION_PIT) or 1
local function devSeedRng()
    pcall(function()
        if devRng:GetSeed() == 0 then devRng:SetSeed(game:GetSeeds():GetStartSeed(), 77) end
        devRng:Next()
    end)
end

-- dedup PRÓPRIO das teclas do dev. NÃO é o droppedItems do mod, então usar a tecla 1 em
-- co-op não suprime drop real de inimigo. Limpo pela tecla 4 (reset).
local devDropped = {}

-- rola 1 item das MESMAS pools que o mod usa (scopeItemIds = pool override / floor pool /
-- pools ativas via REPENTOGON, ou tudo se sem override), respeitando SÓ os filtros duros:
-- tier/tipo (isBlocked), unlock, restrição de personagem.
-- `avoid` (opcional) = predicado; itens que casam são pulados.
-- `allowFallback` = se sobrar zero com o avoid, rola do conjunto cheio (repete) em vez de
--   devolver nil. tecla 1 usa false (quer parar em "esgotado" até o reset); tecla 2 usa true.
local function devRollItem(avoid, allowFallback)
    local full, ok = {}, {}
    pcall(function()
        for did in pairs(scopeItemIds()) do
            if did > 0 and not isBlocked(did) and isUnlocked(did) and canSpawnForChar(did) then
                full[#full + 1] = did
                if not (avoid and avoid(did)) then ok[#ok + 1] = did end
            end
        end
    end)
    local pool
    if #ok > 0 then pool = ok
    elseif allowFallback and #full > 0 then pool = full
    else return nil end
    devSeedRng()
    return pool[devRng:RandomInt(#pool) + 1]
end

-- conta itens que AINDA cabem na pool efetiva ignorando só o dedup do REMOVE_FROM_POOL
-- (mesmo critério do reshuffle). Usado pelo toast da tecla 5.
local function devPoolLeft()
    local left = 0
    pcall(function()
        for did in pairs(scopeItemIds()) do
            if validIgnoringDedup(did) and not S.droppedItems[did] then left = left + 1 end
        end
    end)
    return left
end

-- posição livre ao lado do player que NÃO seja pit/lava (importante com flight).
local function devSafePos(p)
    local room = game:GetRoom()
    local function pit(pos)
        local isPit = false
        pcall(function() isPit = room:GetGridCollisionAtPos(pos) == GRID_COLL_PIT end)
        return isPit
    end
    local base = Isaac.GetFreeNearPosition(p.Position, 40)
    if not pit(base) then return base end
    for _, off in ipairs(PEDESTAL_OFFSETS) do
        local cand = Isaac.GetFreeNearPosition(p.Position + off, 20)
        if not pit(cand) then return cand end
    end
    return base
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not (DEV_MODE or DEV_KEYS) then return end
    local p = Isaac.GetPlayer(0)
    if not p then return end
    -- 1 : rola item da pool -> pedestal ao lado. SEM repetir até a pool acabar; quando acaba,
    -- avisa e para (aperte 4 pra resetar). Evita 3 coisas: o que a PRÓPRIA tecla 1 já deu
    -- (devDropped), o que está no chão AGORA (itemOnFloor, que pega também o que a tecla 5
    -- largou, senão o 1 repetia o que o 5 acabou de spawnar) e o que a tecla 5 marcou no
    -- dedup real (droppedItems), pra não repetir contra ela também.
    if Input.IsButtonTriggered(S.DEV_KEY_ROLL, 0) then
        pcall(function()
            local id = devRollItem(function(did)
                return devDropped[did] or itemOnFloor(did) or S.droppedItems[did]
            end, false)
            if not id then devToast("pool esgotada - aperte 4 pra resetar"); return end
            devDropped[id] = true
            Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, devSafePos(p), Vector(0,0), nil)
            devToast("spawned pedestal: " .. itemName(id))
        end)
    end
    -- 2 : rola item da pool -> direto no inventário. evita dar item que já tem (com fallback).
    if Input.IsButtonTriggered(S.DEV_KEY_GIVE, 0) then
        pcall(function()
            local id = devRollItem(function(did) return p:HasCollectible(did) end, true)
            if not id then devToast("roll: pool vazia / filtrada"); return end
            p:AddCollectible(id, 0, true)
            devToast("given item: " .. itemName(id))
        end)
    end
    -- 5 : drop REAL, caminho idêntico ao de uma morte de inimigo (pickAnyItem + dedup +
    -- pendingSeeds + reshuffle da pool esgotada). Spamme numa pool pequena (Force Pool +
    -- REMOVE_FROM_POOL no MCM) pra ver o reshuffle disparar.
    if Input.IsButtonTriggered(S.DEV_KEY_REALDROP, 0) then
        pcall(function()
            if not CFG.REMOVE_FROM_POOL then
                devToast("REAL drop: liga 'Remove From Pool' no MCM p/ esgotar")
            end
            local wasExhausted = poolExhaustedByDedup()
            spawnItem(devSafePos(p), devRng)
            if wasExhausted then
                devToast("REAL drop - pool RESHUFFLED (estava esgotada)")
            else
                devToast(("REAL drop - %d itens restam na pool"):format(devPoolLeft()))
            end
        end)
    end
    -- 4 : limpa o estado da run (droppedItems/pendingSeeds/droppedSeeds/bossTypeDroppedInRoom/
    -- devDropped aqui)
    if Input.IsButtonTriggered(S.DEV_KEY_RESET, 0) then
        S.droppedItems = {}; S.pendingSeeds = {}
        droppedSeeds = {}; bossTypeDroppedInRoom = {}
        devDropped = {}
        Isaac.DebugString("ELD DEV: estado de run limpo")
        devToast("run state cleared")
    end
    -- 0 : spawna o item fixo do MCM (devSpawnId)
    if Input.IsButtonTriggered(S.DEV_KEY_FIXED, 0) then
        pcall(function()
            Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, S.devSpawnId, devSafePos(p), Vector(0,0), nil)
            devToast("spawned pedestal: " .. itemName(S.devSpawnId))
        end)
    end
end)

-- ============================================================
-- API exportada (usada por edl_mcm.lua e main.lua)
-- ============================================================
M.POOL_OVERRIDE_NAMES     = POOL_OVERRIDE_NAMES
M.POOL_OVERRIDE_NAMES_GREED = POOL_OVERRIDE_NAMES_GREED

M.buildItemTables         = buildItemTables
M.buildDealSet            = buildDealSet
M.isBlocked               = isBlocked
M.isUnlocked              = isUnlocked
M.canSpawnForChar         = canSpawnForChar
M.scopeItemIds            = scopeItemIds
M.resolvePedestalPos      = resolvePedestalPos
M.spawnItem               = spawnItem
M.tryDrop                 = tryDrop
M.resetRoomState          = resetRoomState
M.devToast                = devToast
M.itemName                = itemName

-- resetForNewRun: chamado pelo main.lua no MC_POST_GAME_STARTED (run nova, not isSave).
-- Reseta só o que este arquivo possui e que não é campo de edl_state.lua (S.runStats,
-- S.lastRoll etc já são resetados pelo main.lua diretamente).
function M.resetForNewRun()
    devDropped = {}
end

return M

--[[
edl_config.lua — CONFIGURATION + Default snapshot + Persistence keys
Tudo que era a seção "CONFIGURATION" / "Default snapshot" / a lista de
CFG_SCALAR_KEYS do main.lua original. Nada de lógica de jogo aqui.
]]

local M = {}

-- ============================================================
-- CONFIGURATION (configuração)
-- Recursos principais LIGADOS por padrão; a seção "extras" toda DESLIGADA.
-- ============================================================
local CFG = {
    -- Taxas de drop principais
    -- min/default/max com piso real por categoria: o toggle Item/Pickup Drops já
    -- cobre o "desligar tudo", então os sliders não precisam ir a 0
    ITEM_DROP_RATE = {
        NORMAL = 5, CHAMPION = 10, BOSS = 35,
    },
    RESOURCE_DROP_RATE = {
        NORMAL = 10, CHAMPION = 20, BOSS = 40,
    },
    FLOOR_SCALING_PCT    = 1,  -- min 1%: floor scaling nunca fica totalmente OFF

    -- Filtros principais (LIGADOS)
    ITEM_DROP_ENABLED    = true,   -- interruptor mestre dos drops de item
    RESOURCE_DROP_ENABLED = true,  -- interruptor mestre dos drops de pickup (moeda/chave/coração/…)
    BLOCK_STORY_ITEMS    = true,
    BLOCK_TMTRAINER      = true,
    NO_DUPLICATES        = true,
    REMOVE_FROM_POOL     = true,
    BOSS_GUARANTEED_ITEM = false,
    -- OFF = comportamento vanilla-plus (os ~20 bosses do Boss Rush contam cada um pra
    -- loot, de propósito quebrado/OP pra quem gosta assim). ON = só 1 drop de boss no
    -- total pro Boss Rush inteiro, como se fosse um boss só.
    BOSS_RUSH_LIMIT      = false,
    -- só tem efeito com BOSS_RUSH_LIMIT ligado (fica em Advanced no MCM): false = 1 drop
    -- pro Boss Rush inteiro; true = 1 por wave (reseta a cada wave nova).
    BOSS_RUSH_PER_WAVE   = false,
    -- OFF por padrão = bosses de história (Isaac, ???, Satan, Mega Satan, Mother,
    -- Hush, Delirium, The Lamb, Dogma, The Beast) nunca dropam item nem pickup.
    STORY_BOSS_DROPS     = false,
    -- Filtros de conteúdo do item (padrão: sem filtro, então nada muda pra
    -- quem não mexe neles).
    MIN_QUALITY          = -1,  -- -1 = qualquer; 0 = só Q0; 1-4 = nunca dropar abaixo dessa qualidade
    QUALITY_LOCK         = false, -- on = trava no tier do Min Quality (o piso vira teto: só aquele tier dropa, bloqueia os maiores)
    ITEM_TYPE_FILTER     = 0,   -- 0 = ambos, 1 = só passivos, 2 = só ativos
    NO_DEAL_ITEMS        = false, -- pula itens exclusivos de devil/angel (REPENTOGON)

    -- Pesos de qualidade (usados quando o scaling de qualidade por andar está DESLIGADO)
    ITEM_QUALITY_WEIGHTS = {
        { quality = 0, weight = 35 },
        { quality = 1, weight = 30 },
        { quality = 2, weight = 20 },
        { quality = 3, weight = 10 },
        { quality = 4, weight = 5  },
    },

    -- Pesos dos pickups
    RESOURCE_WEIGHTS = {
        coin = 25, key = 18, bomb = 18, heart_red = 15,
        heart_soul = 6, heart_black = 2, heart_eternal = 1,
        battery = 3, chest = 2,
    },
    -- sempre 1 por drop (nunca dobra): um kill/drop = 1 pickup, sem exceção
    RESOURCE_AMOUNT = {
        coin = {1,1}, key = {1,1}, bomb = {1,1},
        heart_red = {1,1}, heart_soul = {1,1}, heart_black = {1,1},
        heart_eternal = {1,1}, heart_bone = {1,1}, battery = {1,1}, chest = {1,1},
    },

    -- ── EXTRAS ────────────────────────────────────────────
    -- Filtro de unlock (REPENTOGON). 3 estados, porque "unlocked" (desbloqueado) e
    -- "seen" (já visto) NÃO são a mesma coisa; tratar como um só fazia save novo não dropar nada.
    --   0 = Off       -> qualquer item, mesmo os travados por achievement
    --   1 = Unlocked  -> tudo que você desbloqueou, mesmo que nunca tenha pego
    --   2 = Seen only -> só itens que já estão na sua página de coleção
    -- padrão 1: você descobre o que ganhou sem spoilar os itens travados.
    UNLOCK_FILTER         = 1,
    -- Andares mais fundos dropam itens de qualidade mais alta
    FLOOR_QUALITY_SCALING = false,

    -- Modo pool do andar: escolhe itens da pool relevante do andar
    USE_FLOOR_POOL = false,
    -- Override de pool (0=auto, 1=Treasure, 2=Shop, 3=Boss, 4=Devil,
    --                5=Angel, 6=Secret, 7=Library, 8=Planetarium, 9=%CHAOS%)
    -- 9 = %CHAOS%: ignora as pools do andar, escolhe um item cru de qualquer tier (chance
    -- flat). Pra travar num tier específico, use Min Quality + Quality Lock.
    POOL_OVERRIDE  = 0,

    -- Drop de cartas & runas: só Champion, DESLIGADO por padrão
    CARD_RUNE_ENABLED  = false,
    CARD_DROP_RATE     = 5,   -- % de chance, só Champion, máx 10

    -- Drops de pickup adaptados ao personagem
    CHAR_ADAPT_ENABLED = true,

    -- Drop duplo de twin: chars com inventários SEPARADOS (Jacob & Esau,
    -- Tainted Lazarus) só equipam uma metade de um único pedestal. Quando LIGADO, um
    -- drop de item spawna 2 pedestais pra ambas as metades se equiparem de uma morte.
    TWIN_DROP          = false,  -- DESLIGADO por padrão (extra)
    TWIN_SAME_ITEM     = false,  -- false = dois itens diferentes, true = o mesmo item duas vezes

    -- Configurações de co-op. Afeta SÓ co-op local (2+ players/controllers reais).
    -- Solo nunca é tocado. Cada player ganha o SEU pedestal, spawnado no pé dele
    -- (sem empilhar), rolado independente pra que itens repetidos entre players
    -- sejam possíveis de propósito.
    --   0 = Off   -> comportamento vanilla (um pedestal compartilhado, quem pega primeiro leva)
    --   1 = Fair  -> taxa de drop / nº de players, pools honestas (ignora Override de Pool &
    --                Min Quality), itens distintos por drop. Loot total ~ solo.
    --   2 = Chaos -> taxa cheia, mantém teus overrides de Pool/Qualidade, permite repetidos.
    --                ~N x o loot. mais players = mais loucura.
    COOP_MODE          = 1,  -- padrão Fair (loot total ~ solo; Chaos é opt-in)

    -- (loadout inicial, trinkets, pocket-active, gulp, T.Cain push e a penny do Greed
    --  saíram daqui em 16/set/2026: viraram o mod Isaac QoL Kit, que roda do lado deste.
    --  Este mod é só o drop engine agora.)

    -- ── QoL / feedback ─────────────────────────────────────
    -- Overlay de canto: 0 = off, 1 = stats da run (itens/pickups/kills),
    -- 2 = stats + log do último roll (nome do inimigo mais chance e hit/miss do item e do pickup).
    DEBUG_OVERLAY = 0,
    -- Auto-balanceia os drops do mod contra itens do jogo que quebram a economia
    -- (Humbling Bundle dá menos pickup; Daemon's Tail dá menos coração vermelho). Mesma
    -- filosofia do nerf de champion que já existe (Champion Belt / Purple Heart).
    ECONOMY_REACT = true,
    -- Aviso "Effective pool: N items" embaixo do Force Pool no MCM. Puramente informativo.
    POOL_WARN = true,
}

-- ============================================================
-- Snapshot dos padrões (capturado antes de qualquer loadConfig)
-- ============================================================
-- ponytail: DEFAULTS era uma segunda tabela retypada à mão com os mesmos valores
-- do CFG acima (fácil dessincronizar ao adicionar uma opção nova). deepCopy tira
-- a foto sozinho, então CFG continua sendo a ÚNICA fonte de verdade dos valores
-- de fábrica.
local function deepCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = (type(v) == "table") and deepCopy(v) or v
    end
    return copy
end
local DEFAULTS = deepCopy(CFG)

local function resetToDefaults()
    for k, v in pairs(DEFAULTS) do
        if type(v) == "table" then
            for ek in pairs(CFG[k]) do CFG[k][ek] = nil end  -- limpa (ex: idx por-char) antes de recopiar
            for sk, sv in pairs(v) do CFG[k][sk] = sv end
        else
            CFG[k] = v
        end
    end
end

-- ============================================================
-- Persistência: quais chaves ESCALARES de CFG vão pro save
-- (tabelas como ITEM_DROP_RATE são tratadas à parte em edl_persistence.lua)
-- ============================================================
local CFG_SCALAR_KEYS = {
    "FLOOR_SCALING_PCT",
    "ITEM_DROP_ENABLED","RESOURCE_DROP_ENABLED","BLOCK_STORY_ITEMS","BLOCK_TMTRAINER",
    "NO_DUPLICATES","REMOVE_FROM_POOL","BOSS_GUARANTEED_ITEM","BOSS_RUSH_LIMIT","BOSS_RUSH_PER_WAVE","STORY_BOSS_DROPS",
    "MIN_QUALITY","QUALITY_LOCK","ITEM_TYPE_FILTER","NO_DEAL_ITEMS",
    "UNLOCK_FILTER","FLOOR_QUALITY_SCALING",
    "USE_FLOOR_POOL","POOL_OVERRIDE","CARD_RUNE_ENABLED","CARD_DROP_RATE",
    "CHAR_ADAPT_ENABLED",
    "TWIN_DROP","TWIN_SAME_ITEM","COOP_MODE",
    "DEBUG_OVERLAY","ECONOMY_REACT","POOL_WARN",
}

M.CFG              = CFG
M.CFG_SCALAR_KEYS  = CFG_SCALAR_KEYS
M.resetToDefaults  = resetToDefaults

return M

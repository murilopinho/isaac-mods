--[[
qol_config.lua - CONFIGURACAO + snapshot de defaults + chaves de persistencia.
Nenhuma logica de jogo aqui.

Regra de ouro: mexeu numa opcao nova? Ela PRECISA estar em CFG *e* em
CFG_SCALAR_KEYS, senao nao salva.

Os defaults seguem uma ideia so: fix/remocao de chatice pura vem ON, qualquer coisa
que muda nivel de poder ou economia vem OFF (opt-in).
]]

local M = {}

local CFG = {
    -- ── Loadout (herdado do Enemy Drop Loot V2) ─────────────────────────
    -- Todos OFF por padrao: mesmo default que essas features tinham no EDL, entao
    -- mudar pra aqui nao altera a run de ninguem sem avisar.
    CHAR_TRINKET_CHOICE_ENABLED = false,  -- fileira de trinkets curadas no chao no inicio da run
    TRINKET_SMELT_INNATE        = false,  -- engole a trinket nativa do personagem no inicio da run
    POCKET_ACTIVE_CONVERT       = false,  -- move o ativo inicial pro slot pocket

    -- ── Keybinds (Gulp mora na aba MCM "Loadout", T.Cain mora em "Fixes") ─
    TRINKET_GULP_ENABLED  = false,             -- keybind pra engolir as trinkets que esta carregando
    TRINKET_GULP_KEY      = Keyboard.KEY_G,
    TRINKET_GULP_LOCATION = 1,                 -- 0=qualquer lugar  1=sala inicial de cada andar  2=so a 1a sala da run
    TCAIN_PUSH_ENABLED    = false,             -- T.Cain: empurra pickup em vez de absorver
    TCAIN_PUSH_KEY        = Keyboard.KEY_Z,

    -- ── Fixes (personagem) ─────────────────────────────────────────────
    -- Judas + Birthright: o motor da pro Judas um SEGUNDO Book of Belial quando ele pega
    -- Birthright no meio da run, porque o check nativo nao ve o slot pocket. So relevante
    -- com POCKET_ACTIVE_CONVERT ligado, inofensivo se nao, entao vem ON.
    JUDAS_BELIAL_FIX    = true,
    HOLY_MANTLE_JACOB   = true,   -- Tainted Jacob mantem Holy Mantle enquanto estiver na forma Lost
    RAINBOW_POOP_MANTLE = true,   -- coco arco-iris da uma carga de Holy Card pro Tainted Lost
    LOST_BED_MANTLE     = true,   -- Lost / Tainted Lost encostam na cama e ganham Holy Card (1 por cama)

    -- ── Greed Mode ────────────────────────────────────────────────────
    HALF_PRICE_SHOP        = false,  -- comeca o Greed com Steam Sale (loja com metade do preco)
    HALF_PRICE_SHOP_NORMAL = false,  -- mesma coisa, mas em run Normal/Hard (fora do Greed)
    EASY_GREED_ENABLED     = false,  -- Greed/Greedier: Counterfeit Penny (+ pilula de Gulp ao pegar)

    -- ── Starting Blessings (qualquer personagem) ─────────────────────
    -- Mesma regra da trinket: so aplicado no frame>4 one-shot (applyStartingBlessings em
    -- qol_loadout.lua). Nao da pra ganhar no meio da run por este toggle.
    -- Seletor unico (indice em STARTING_BLESSING_LIST, ver qol_loadout.lua): 0=OFF,
    -- 1..N=item especifico, N+1=Random.
    STARTING_BLESSING       = 0,
    STARTING_TAINTED_BONUS  = false,  -- bonus fixo por personagem, 34 chars (ver CHAR_STARTING_ITEM_MAP em qol_loadout.lua)
    STARTING_ITEM_REQUIRE_UNLOCK = false,  -- pula o bonus se o item do CHAR_STARTING_ITEM_MAP nao estiver desbloqueado no save (precisa de REPENTOGON, toggle some sem ele)

    -- ── Machines ───────────────────────────────────────────────────────
    NO_JAM               = true,  -- maquina de doacao/greed travada destrava ao sair e voltar na sala
    FASTER_ETERNAL_CHEST = true,  -- Eternal Chest fecha rapido, sem te fazer esperar
    INSTANT_FIRES_POOPS  = true,  -- sala limpa: coco e fogueira morrem no primeiro hit

    -- ── Rooms ────────────────────────────────────────────────────────
    BOMBABLE_DEVIL_STATUE       = false,  -- bombardeia a estatua do Devil Room, luta com Fallen Angel, item de graca
    ANGEL_DROP_ITEM              = false, -- Uriel/Gabriel dropam item de graca no refight (Angel/Sacrifice/Error)
    ANGEL_DROP_ALWAYS            = true,  -- true = sempre dropa (default)
    ANGEL_DROP_CHANCE            = 50,    -- se ALWAYS=false: % de chance do anjo dropar o item
    STARTING_POCKET_ITEM         = false, -- ativo aleatorio na sala inicial (precisa de POCKET_ACTIVE_CONVERT)

    -- ── Novas Features QoL (Producao) ────────────────────────────────────
    AUTO_COLLECT_PICKUPS        = false,  -- Coleta automatica de moedas e chaves com sala limpa
}

-- ============================================================
-- Snapshot dos defaults (tirado antes de qualquer loadConfig)
-- ============================================================
-- deepCopy em vez de uma segunda tabela retypada a mao: CFG acima continua a unica
-- fonte de verdade dos valores de fabrica, entao adicionar uma opcao nunca dessincroniza.
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
-- Persistencia: toda chave de CFG vai pro save. Hoje todas sao escalares; se um dia
-- entrar um valor tabela, precisa de tratamento proprio em qol_persistence.lua.
-- ============================================================
local CFG_SCALAR_KEYS = {
    "CHAR_TRINKET_CHOICE_ENABLED", "TRINKET_SMELT_INNATE", "POCKET_ACTIVE_CONVERT",
    "TRINKET_GULP_ENABLED", "TRINKET_GULP_KEY", "TRINKET_GULP_LOCATION",
    "TCAIN_PUSH_ENABLED", "TCAIN_PUSH_KEY",
    "JUDAS_BELIAL_FIX", "HOLY_MANTLE_JACOB", "RAINBOW_POOP_MANTLE", "LOST_BED_MANTLE",
    "HALF_PRICE_SHOP", "HALF_PRICE_SHOP_NORMAL", "EASY_GREED_ENABLED",
    "STARTING_BLESSING", "STARTING_TAINTED_BONUS", "STARTING_ITEM_REQUIRE_UNLOCK",
    "NO_JAM", "FASTER_ETERNAL_CHEST", "INSTANT_FIRES_POOPS",
    "BOMBABLE_DEVIL_STATUE",
    "ANGEL_DROP_ITEM", "ANGEL_DROP_ALWAYS", "ANGEL_DROP_CHANCE", "STARTING_POCKET_ITEM",
    "AUTO_COLLECT_PICKUPS",
}

M.CFG             = CFG
M.CFG_SCALAR_KEYS = CFG_SCALAR_KEYS
M.resetToDefaults = resetToDefaults

return M

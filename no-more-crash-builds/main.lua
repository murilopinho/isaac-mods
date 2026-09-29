--[[
No More Crash Builds - evita o crash de build quebrada sem cortar dano.

Sempre ligado. Abaixo dos limites o mod nao faz nada (run identica ao vanilla).
Acima deles, 3 camadas:
  1. FX_LIMIT lagrimas na sala  -> efeito puramente visual (poof, respingo, particula) nao nasce
  2. SPLIT_LIMIT lagrimas       -> lagrima nova nao se divide mais; o dano das filhas vai pra ela
  3. BOMB_LIMIT bombas na sala  -> bomba nova perde Scatter/Sad (explode, mas nao gera outras)

Contagem 1x por frame no POST_UPDATE, nunca dentro dos callbacks de init.
Comentarios sem acento (a engine quebra com acento em texto renderizado).
]]

local mod  = RegisterMod("NoMoreCrashBuilds", 1)
local json = (function() local ok, m = pcall(require, "json"); return ok and m or nil end)()

-- ============================================================
-- Config (MCM opcional: sem ele, valem estes defaults)
-- ============================================================
local CFG = {
    ENABLED      = true,
    FX_LIMIT     = 75,
    SPLIT_LIMIT  = 150,
    BOMB_LIMIT   = 12,
    SHOW_COUNTER = false,
    SHOW_DOT     = true,   -- quadradinho no topo: verde / amarelo / vermelho
}
local CFG_KEYS = { "ENABLED", "FX_LIMIT", "SPLIT_LIMIT", "BOMB_LIMIT", "SHOW_COUNTER", "SHOW_DOT" }

local function saveConfig()
    if not json then return end
    pcall(function()
        local d = {}
        for _, k in ipairs(CFG_KEYS) do d[k] = CFG[k] end
        mod:SaveData(json.encode(d))
    end)
end

local function loadConfig()
    if not json or not mod:HasData() then return end
    pcall(function()
        local d = json.decode(mod:LoadData())
        if type(d) ~= "table" then return end
        for _, k in ipairs(CFG_KEYS) do
            if type(d[k]) == type(CFG[k]) then CFG[k] = d[k] end
        end
    end)
end

-- ============================================================
-- Contagem (1x por frame)
-- ============================================================
local count = { tears = 0, bombs = 0, lasers = 0, effects = 0, marked = 0 }

-- Lagrima que nasce com a sala acima do FX_LIMIT ganha marca. O splash so volta
-- quando todas as marcadas morrem: sem isso, ao cair abaixo do limite, as lagrimas
-- da tempestade que ainda estao voando soltam o splash todas juntas (lag na volta).
-- Lagrima nova so e marcada com a sala realmente cheia, senao a marca se sustentaria sozinha.
local function fxOn()
    return CFG.ENABLED and (count.tears >= CFG.FX_LIMIT or count.marked > 0)
end

-- nivel atual: 0 normal, 1 sem splash, 2 juntando dano / cortando bomba.
-- Segura o nivel mais alto por HOLD_FRAMES: sala cheia oscila em volta do limite
-- e a cor ficaria piscando.
local HOLD_FRAMES = 8    -- ~0.25s (POST_UPDATE roda a 30/s); o amarelo ja e estavel pelas marcas
local level, holdLeft = 0, 0

local function currentLevel()
    if not CFG.ENABLED then return 0 end
    if count.tears >= CFG.SPLIT_LIMIT or count.bombs >= CFG.BOMB_LIMIT then return 2 end
    if fxOn() then return 1 end
    return 0
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    local tears, marked = Isaac.FindByType(EntityType.ENTITY_TEAR), 0
    for _, t in ipairs(tears) do
        if t:GetData().nmcbQuiet then marked = marked + 1 end
    end
    count.tears, count.marked = #tears, marked
    count.bombs = Isaac.CountEntities(nil, EntityType.ENTITY_BOMB, -1, -1)
    local now = currentLevel()
    if now >= level then level, holdLeft = now, HOLD_FRAMES
    elseif holdLeft > 0 then holdLeft = holdLeft - 1
    else level = now end
    if CFG.SHOW_COUNTER then
        count.lasers  = Isaac.CountEntities(nil, EntityType.ENTITY_LASER, -1, -1)
        count.effects = Isaac.CountEntities(nil, EntityType.ENTITY_EFFECT, -1, -1)
    end
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    count.tears, count.bombs, count.lasers, count.effects, count.marked = 0, 0, 0, 0, 0
    level, holdLeft = 0, 0
end)

-- ============================================================
-- Camada 1: sem splash
-- So variantes puramente visuais. NUNCA creep: creep da dano.
-- ============================================================
local FX_VARIANTS = {
    EffectVariant.TEAR_POOF_A, EffectVariant.TEAR_POOF_B,
    EffectVariant.TEAR_POOF_SMALL, EffectVariant.TEAR_POOF_VERYSMALL,
    EffectVariant.BULLET_POOF, EffectVariant.BLOOD_PARTICLE,
    EffectVariant.BLOOD_SPLAT, EffectVariant.BLOOD_EXPLOSION,
    EffectVariant.ROCK_PARTICLE, EffectVariant.IMPACT,
    EffectVariant.LASER_IMPACT, EffectVariant.TECH_DOT,
    EffectVariant.DUST_CLOUD,
}

local function onFxInit(_, effect)
    if fxOn() then effect:Remove() end
end
-- filtro por variante no AddCallback: o callback nem roda pros outros efeitos
for _, v in ipairs(FX_VARIANTS) do
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, onFxInit, v)
end

-- ============================================================
-- Camada 2: sem novas divisoes, dano mantido
-- Dano extra = n de filhas x % de dano de cada (wiki):
--   Parasite 2 x 50%, Cricket's Body 4 x 50%,
--   Haemolacria 6-11 (media 8.5) x ~66%, Compound Fracture 1-3 (media 2) x 50%
-- ponytail: multiplicador medio por flag, em alvo unico; perde a area das filhas.
-- Calibrar aqui se o DPS mudar visivelmente in-game.
-- ============================================================
local SPLITS = {
    { flag = TearFlags.TEAR_SPLIT,      extra = 1.0 },
    { flag = TearFlags.TEAR_QUADSPLIT,  extra = 2.0 },
    { flag = TearFlags.TEAR_BURSTSPLIT, extra = 5.6 },
    { flag = TearFlags.TEAR_BONE,       extra = 1.0 },
}

-- Sem marcador por lagrima: a flag sai na 1a vez, entao a 2a chamada nao acha nada
-- pra multiplicar (FIRE_TEAR e o 1o TEAR_UPDATE podem pegar a mesma lagrima).
local function foldSplits(tear)
    if not CFG.ENABLED or count.tears < CFG.SPLIT_LIMIT then return end
    local mult = 1
    for _, s in ipairs(SPLITS) do
        if tear:HasTearFlags(s.flag) then
            tear:ClearTearFlags(s.flag)
            mult = mult + s.extra
        end
    end
    if mult > 1 then tear.CollisionDamage = tear.CollisionDamage * mult end
end

mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear) foldSplits(tear) end)
-- pega as filhas e lagrimas de familiar, que nao passam pelo FIRE_TEAR
mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
    if tear.FrameCount > 1 then return end
    foldSplits(tear)
    if CFG.ENABLED and count.tears >= CFG.FX_LIMIT then tear:GetData().nmcbQuiet = true end
end)

-- ============================================================
-- Camada 3: loop de bombas (Dr. Fetus + Scatter/Sad Bombs)
-- ============================================================
local function capBomb(bomb)
    if not CFG.ENABLED or count.bombs < CFG.BOMB_LIMIT then return end
    bomb:ClearTearFlags(TearFlags.TEAR_SCATTER_BOMB)
    bomb:ClearTearFlags(TearFlags.TEAR_SAD_BOMB)
end
mod:AddCallback(ModCallbacks.MC_POST_BOMB_INIT, function(_, bomb) capBomb(bomb) end)
-- as flags podem ser aplicadas depois do init (bomba do Dr. Fetus), entao confere no 1o update
mod:AddCallback(ModCallbacks.MC_POST_BOMB_UPDATE, function(_, bomb)
    if bomb.FrameCount <= 1 then capBomb(bomb) end
end)

-- ============================================================
-- Quadradinho de status (topo, centro): mostra pro jogador o que o mod esta fazendo
-- ============================================================
local dot = Sprite()
dot:Load("gfx/nmcb_dot.anm2", true)
dot:Play("Idle", true)
local DOT_COLORS = {
    [0] = Color(0.3, 1, 0.3, 0.8, 0, 0, 0),  -- verde: normal
    [1] = Color(1, 0.9, 0.2, 0.9, 0, 0, 0),  -- amarelo: sem splash
    [2] = Color(1, 0.25, 0.25, 1, 0, 0, 0),  -- vermelho: juntando dano / cortando bomba
}

mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if not CFG.SHOW_DOT or not CFG.ENABLED then return end
    if not Game():GetHUD():IsVisible() then return end
    dot.Color = DOT_COLORS[level]
    dot:Render(Vector(Isaac.GetScreenWidth() / 2, 6), Vector.Zero, Vector.Zero)
end)

-- ============================================================
-- Contador na tela (pra calibrar os limites)
-- ============================================================
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if not CFG.SHOW_COUNTER then return end
    local on = CFG.ENABLED
    local fx    = fxOn()
    local split = on and count.tears >= CFG.SPLIT_LIMIT
    local bomb  = on and count.bombs >= CFG.BOMB_LIMIT
    local x, y = 60, 40
    local function ln(s, active)
        if active then Isaac.RenderText(s, x, y, 1, 0.3, 0.3, 1)
        else Isaac.RenderText(s, x, y, 1, 1, 1, 0.8) end
        y = y + 11
    end
    ln("Tears: " .. count.tears .. " (marked " .. count.marked .. ")" .. (split and "  [NO SPLIT]" or fx and "  [NO FX]" or ""), fx or split)
    ln("Bombs: " .. count.bombs .. (bomb and "  [NO CHAIN]" or ""), bomb)
    ln("Lasers: " .. count.lasers, false)
    ln("Effects: " .. count.effects, false)
end)

-- ============================================================
-- Tecla de teste: 1 = pedestais dos itens de crash (DESLIGAR antes do upload)
-- ============================================================
local TEST_KEYS = false
local CRASH_ITEMS = {
    531, 104, 68, 118, 224,   -- Haemolacria, Parasite, Technology, Brimstone, Cricket's Body
    533, 2, 532, 369, 494,    -- Trisagion, Inner Eye, Lachryphagy, Continuum, Jacob's Ladder
    52, 366, 220, 114, 360,   -- Dr. Fetus, Scatter Bombs, Sad Bombs, Mom's Knife, Incubus
}

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not TEST_KEYS or not Input.IsButtonTriggered(Keyboard.KEY_1, 0) then return end
    local room = Game():GetRoom()
    for _, id in ipairs(CRASH_ITEMS) do
        local pos = room:FindFreePickupSpawnPosition(room:GetCenterPos(), 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, pos, Vector.Zero, nil)
    end
end)

-- ============================================================
-- Init
-- ============================================================
-- require no topo: o Isaac so procura na pasta do mod enquanto o main.lua carrega
local okMcm, MCM = pcall(require, "nmcb_mcm")
if not okMcm then Isaac.DebugString("NoMoreCrashBuilds: nmcb_mcm nao carregou: " .. tostring(MCM)) end
local configLoaded, mcmDone = false, false

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isSave)
    if not configLoaded then loadConfig(); configLoaded = true end
    if not mcmDone and okMcm and ModConfigMenu then
        local ok, done = pcall(MCM.setup, CFG, saveConfig)
        if not ok then Isaac.DebugString("NoMoreCrashBuilds: MCM setup falhou: " .. tostring(done)) end
        mcmDone = ok and done
    end
end)

mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, saveConfig)

Isaac.DebugString("NoMoreCrashBuilds: v1.0 loaded")

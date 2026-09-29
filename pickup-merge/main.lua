--[[
Pickup Merge - junta pickups iguais pra sala cheia nao lagar.

Quando junta (MCM, CFG.MODE): 1 = ao VOLTAR pra sala (nunca na 1a visita),
2 = ao apertar CFG.KEY (qualquer sala), 3 = os dois.
Cada grupo soma o valor dos pickups e reparte do maior pro menor
(ex: 2 moedas duplas + 1 moeda = 5 = 1 niquel).
Fica de fora: loja (preco), "pega so um" (OptionsPickupIndex), pickup ja tocado e
os especiais (grudento, dourado, sorte, chave carregada, troll...), que nao estao em inputs.
Comentarios sem acento (a engine quebra com acento em texto renderizado).
]]

local mod  = RegisterMod("PickupMerge", 1)
local json = (function() local ok, m = pcall(require, "json"); return ok and m or nil end)()

-- ============================================================
-- Config (MCM opcional: sem ele, valem estes defaults)
-- ============================================================
local CFG = {
    ENABLED = true,
    MODE    = 1,               -- 1 voltar pra sala, 2 tecla, 3 os dois
    KEY     = Keyboard.KEY_M,
    LUCKY   = true,            -- 50 moedas -> moeda da sorte (perde valor)
    GIGA    = true,            -- 40 bombas -> gigabomba (perde valor)
    BLACK   = true,            -- 2 almas -> coracao negro
}
local CFG_KEYS = { "ENABLED", "MODE", "KEY", "LUCKY", "GIGA", "BLACK" }

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
-- Regras
-- ============================================================

-- inputs: [SubType] = valor. outputs: { SubType, valor, chave do CFG que liga }, do maior pro menor.
local GROUPS = {
    { variant = PickupVariant.PICKUP_COIN,
      inputs  = { [CoinSubType.COIN_PENNY] = 1, [CoinSubType.COIN_DOUBLEPACK] = 2,
                  [CoinSubType.COIN_NICKEL] = 5, [CoinSubType.COIN_DIME] = 10 },
      outputs = { { CoinSubType.COIN_LUCKYPENNY, 50, "LUCKY" }, { CoinSubType.COIN_DIME, 10 },
                  { CoinSubType.COIN_NICKEL, 5 }, { CoinSubType.COIN_DOUBLEPACK, 2 },
                  { CoinSubType.COIN_PENNY, 1 } } },
    { variant = PickupVariant.PICKUP_KEY,
      inputs  = { [KeySubType.KEY_NORMAL] = 1, [KeySubType.KEY_DOUBLEPACK] = 2 },
      outputs = { { KeySubType.KEY_DOUBLEPACK, 2 }, { KeySubType.KEY_NORMAL, 1 } } },
    { variant = PickupVariant.PICKUP_BOMB,
      inputs  = { [BombSubType.BOMB_NORMAL] = 1, [BombSubType.BOMB_DOUBLEPACK] = 2 },
      outputs = { { BombSubType.BOMB_GIGA, 40, "GIGA" }, { BombSubType.BOMB_DOUBLEPACK, 2 },
                  { BombSubType.BOMB_NORMAL, 1 } } },
    { variant = PickupVariant.PICKUP_HEART,   -- vermelho, em meios coracoes
      inputs  = { [HeartSubType.HEART_HALF] = 1, [HeartSubType.HEART_FULL] = 2,
                  [HeartSubType.HEART_DOUBLEPACK] = 4 },
      outputs = { { HeartSubType.HEART_DOUBLEPACK, 4 }, { HeartSubType.HEART_FULL, 2 },
                  { HeartSubType.HEART_HALF, 1 } } },
    { variant = PickupVariant.PICKUP_HEART,   -- alma: 2 almas = 1 negro
      inputs  = { [HeartSubType.HEART_HALF_SOUL] = 1, [HeartSubType.HEART_SOUL] = 2 },
      outputs = { { HeartSubType.HEART_BLACK, 4, "BLACK" }, { HeartSubType.HEART_SOUL, 2 },
                  { HeartSubType.HEART_HALF_SOUL, 1 } } },
}

-- Reparte o valor total nos outputs, do maior pro menor. Devolve a lista de SubTypes.
local function split(value, outputs)
    local out = {}
    for _, o in ipairs(outputs) do
        if not o[3] or CFG[o[3]] then   -- regra grande desligada no MCM: pula
            for _ = 1, math.floor(value / o[2]) do out[#out + 1] = o[1] end
            value = value % o[2]
        end
    end
    return out
end

local function mergeGroup(g)
    local found, value = {}, 0
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, g.variant)) do
        local p = e:ToPickup()
        local v = p and g.inputs[p.SubType]
        if v and p.Price == 0 and p.OptionsPickupIndex == 0 and not p.Touched then
            found[#found + 1] = p
            value = value + v
        end
    end
    local out = split(value, g.outputs)
    if #out >= #found then return end   -- nada pra juntar
    -- os primeiros viram o pickup novo no mesmo lugar, o resto some
    for i, p in ipairs(found) do
        if out[i] then
            if p.SubType ~= out[i] then
                p:Morph(EntityType.ENTITY_PICKUP, g.variant, out[i], true, true, true)
                Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, p.Position, Vector.Zero, nil)
            end
        else
            p:Remove()
        end
    end
end

local function mergeRoom()
    for _, g in ipairs(GROUPS) do mergeGroup(g) end
end

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    if not CFG.ENABLED or CFG.MODE == 2 or Game():GetRoom():IsFirstVisit() then return end
    mergeRoom()
end)

-- POST_UPDATE nao roda com o jogo pausado, entao digitar no console nao dispara
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not CFG.ENABLED or CFG.MODE == 1 or not Input.IsButtonTriggered(CFG.KEY, 0) then return end
    mergeRoom()
end)

-- ============================================================
-- Init
-- ============================================================
-- require no topo: o Isaac so procura na pasta do mod enquanto o main.lua carrega
local okMcm, MCM = pcall(require, "pm_mcm")
if not okMcm then Isaac.DebugString("PickupMerge: pm_mcm nao carregou: " .. tostring(MCM)) end
local configLoaded, mcmDone = false, false

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    if not configLoaded then loadConfig(); configLoaded = true end
    if not mcmDone and okMcm and ModConfigMenu then
        local ok, done = pcall(MCM.setup, CFG, saveConfig)
        if not ok then Isaac.DebugString("PickupMerge: MCM setup falhou: " .. tostring(done)) end
        mcmDone = ok and done
    end
end)

mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, saveConfig)

-- exposto so pro teste estatico
PickupMerge = { CFG = CFG, mergeRoom = mergeRoom }

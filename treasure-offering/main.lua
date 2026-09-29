--[[
  Treasure Offering - deixe um trinket no chao da sala do Tesouro; depois que o boss do
  andar morrer, ele vira Cracked Key na proxima vez que voce entrar la. 1 por andar: com
  varios no chao vira so o 1o da lista da sala (ordem de spawn ~ o 1o largado).
  Fora: Ascent (o jogo ja faz isso sozinho), Greed, trinket com preco.
  Estado do andar vai no SaveData junto com a config (sobrevive ao Continue).
  Comentarios sem acento (a engine quebra com acento em texto renderizado).
]]

local mod = RegisterMod("TreasureOffering", 1)
local json = (function() local ok, m = pcall(require, "json"); return ok and m or nil end)()

-- ============================================================
-- Config (MCM opcional: sem ele, vale este default)
-- ============================================================
local CFG = { ENABLED = true }
local RUN = { floor = nil, done = false } -- andar atual, ja converteu

local function saveData()
    if not json then return end
    pcall(function() mod:SaveData(json.encode({ ENABLED = CFG.ENABLED, run = RUN })) end)
end

local function loadData(isContinued)
    if not json or not mod:HasData() then return end
    pcall(function()
        local d = json.decode(mod:LoadData())
        if type(d) ~= "table" then return end
        if type(d.ENABLED) == "boolean" then CFG.ENABLED = d.ENABLED end
        if isContinued and type(d.run) == "table" then
            RUN.floor, RUN.done = d.run.floor, d.run.done == true
        end
    end)
end

-- ============================================================
-- Logica
-- ============================================================
local function active()
    local game = Game()
    return CFG.ENABLED and not game:IsGreedMode() and not game:GetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH)
end

-- andar novo (ou run nova) zera o estado; seed da run evita herdar de outra run
local function syncFloor()
    local game = Game()
    local level = game:GetLevel()
    local key = game:GetSeeds():GetStartSeed() .. ":" .. level:GetStage() .. ":" .. level:GetStageType()
    if RUN.floor ~= key then RUN.floor, RUN.done = key, false end
end

-- todas as salas de boss do andar limpas (XL = as duas)
local function bossBeaten()
    local rooms = Game():GetLevel():GetRooms()
    local found = false
    for i = 0, rooms.Size - 1 do
        local r = rooms:Get(i)
        if r and r.Data and r.Data.Type == RoomType.ROOM_BOSS then
            found = true
            if not r.Clear then return false end
        end
    end
    return found
end

local function inTreasure() return Game():GetRoom():GetType() == RoomType.ROOM_TREASURE end

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    if not active() or not inTreasure() then return end
    syncFloor()
    if RUN.done or not bossBeaten() then return end
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET)) do
        if e:ToPickup().Price == 0 then
            e:ToPickup():Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, Card.CARD_CRACKED_KEY, true, true, true)
            Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, e.Position, Vector.Zero, nil)
            RUN.done = true
            saveData()
            return
        end
    end
end)

-- ============================================================
-- MCM + save
-- ============================================================
-- no topo: o Isaac so procura na pasta do mod enquanto o main.lua carrega
local okMcm, MCM = pcall(require, "to_mcm")
if not okMcm then Isaac.DebugString("TreasureOffering: to_mcm nao carregou: " .. tostring(MCM)) end

local mcmDone = false
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
    RUN.floor, RUN.done = nil, false
    loadData(isContinued)
    if not mcmDone and okMcm and ModConfigMenu then
        local ok, done = pcall(MCM.setup, CFG, saveData)
        if not ok then Isaac.DebugString("TreasureOffering: MCM setup falhou: " .. tostring(done)) end
        mcmDone = ok and done
    end
end)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, saveData)

-- exposto so pro teste estatico
TreasureOffering = { CFG = CFG, RUN = RUN }

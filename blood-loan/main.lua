--[[
  Blood Loan - a Sacrifice Room empresta sangue pra voce ir mais fundo nos espinhos.
    Uso unico por run: so a 1a Sacrifice Room em que o player ENTRA (achar no mapa nao conta).
    Nela: +3,5 coracoes emprestados (vermelho ate encher, o resto vira soul; quem nao tem
    vermelho ganha tudo soul). Keeper/T.Keeper: 5 moedas no chao. Forgotten e Bethany: 3,5 coracoes
    vermelhos no chao. Os do chao nao sao cobrados. Lost/T.Lost: nada.
    Jacob e Esau: um emprestimo pra cada. Ajudantes (Strawman, Soul of the Forgotten) nada.
    T.Forgotten: so a T.Soul. T.Lazarus: o Flip nao conta como gasto.
    Com o emprestimo aberto: efeito do Wafer (Percs) so dentro da sala (Keeper e Lost nao).
    Ao sair: o que nao foi gasto volta. Gasto = soma das quedas de vida na sala (cura e
    soul ganho la dentro nao abatem a divida, ficam com o player). Cobranca com AddHearts negativo, nao e dano
    (nao pisca, nao mexe no devil deal) e nunca deixa o player com menos de meio coracao.
  Estado vai no SaveData (sobrevive ao Continue).
  Comentarios sem acento (a engine quebra com acento em texto renderizado).
]]

local mod = RegisterMod("BloodLoan", 1)
local json = (function() local ok, m = pcall(require, "json"); return ok and m or nil end)()

-- ============================================================
-- Config (MCM opcional: sem ele, vale este default)
-- ============================================================
local CFG = { ENABLED = true }
local LOAN, KEEPER_COINS = 7, 5 -- meios coracoes
-- floor: chave do andar; done: ja usou o emprestimo na run; room: sala do emprestimo aberto;
-- loans: por indice de player (string por causa do json), { red, soul, last, spent, t }
local RUN = { floor = nil, done = false, room = nil, loans = {} }

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
            RUN.floor, RUN.room = d.run.floor, d.run.room
            RUN.done, RUN.loans = d.run.done == true, d.run.loans or {}
        end
    end)
end

-- ============================================================
-- Logica
-- ============================================================
local game = Game()

local function health(p) return p:GetHearts() + p:GetSoulHearts() end

local function isType(p, a, b) local t = p:GetPlayerType() return t == a or t == b end

local function floorKey()
    local level = game:GetLevel()
    return game:GetSeeds():GetStartSeed() .. ":" .. level:GetStage() .. ":" .. level:GetStageType()
end

local function isKeeper(p) return isType(p, PlayerType.PLAYER_KEEPER, PlayerType.PLAYER_KEEPER_B) end
local function isLost(p) return isType(p, PlayerType.PLAYER_THELOST, PlayerType.PLAYER_THELOST_B) end
-- ajudante (Parent: Strawman, Forgotten da Soul of the Forgotten) e corpo do T.Forgotten
-- (invencivel, a vida e da T.Soul) nao recebem nada
local function lendable(p) return p.Parent == nil and p:GetPlayerType() ~= PlayerType.PLAYER_THEFORGOTTEN_B end

local function drop(p, variant, sub, n)
    local room = game:GetRoom()
    for _ = 1, n do
        local pos = room:FindFreePickupSpawnPosition(p.Position, 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, sub, pos, Vector(0, 0), nil)
    end
end

local function lend()
    for i = 0, game:GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        if not lendable(p) then -- nada
        elseif isKeeper(p) then
            drop(p, PickupVariant.PICKUP_COIN, CoinSubType.COIN_PENNY, KEEPER_COINS)
        elseif isType(p, PlayerType.PLAYER_THEFORGOTTEN, PlayerType.PLAYER_THESOUL)
            or isType(p, PlayerType.PLAYER_BETHANY) then -- Bethany: soul viraria carga
            drop(p, PickupVariant.PICKUP_HEART, HeartSubType.HEART_FULL, LOAN // 2)
            drop(p, PickupVariant.PICKUP_HEART, HeartSubType.HEART_HALF, LOAN % 2)
        elseif not isLost(p) then
            local h = p:GetHearts()
            p:AddHearts(math.min(LOAN, math.max(0, p:GetEffectiveMaxHearts() - h)))
            local red = p:GetHearts() - h
            local s = p:GetSoulHearts()
            p:AddSoulHearts(LOAN - red)
            local soul = p:GetSoulHearts() - s
            if red + soul > 0 then RUN.loans[tostring(i)] = { red = red, soul = soul, last = health(p), spent = 0, t = p:GetPlayerType() } end
        end
    end
end

-- soma so as quedas: curar ou ganhar soul dentro da sala nao reduz o gasto
local function track()
    for k, loan in pairs(RUN.loans) do
        local p = Isaac.GetPlayer(tonumber(k))
        if p then
            local h = health(p)
            -- T.Lazarus: o Flip troca a vida junto com a forma, a queda da troca nao e gasto
            local t = p:GetPlayerType()
            if t ~= loan.t then loan.t = t
            elseif h < loan.last then loan.spent = loan.spent + loan.last - h end
            loan.last = h
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, track)

-- devolve o que sobrou: tira soul primeiro (ate o que foi emprestado em soul), depois vermelho
local function collect()
    track()
    for k, loan in pairs(RUN.loans) do
        local p = Isaac.GetPlayer(tonumber(k))
        if p then
            local owe = math.max(0, loan.red + loan.soul - loan.spent)
            owe = math.min(owe, health(p) - 1)
            local s = math.min(owe, loan.soul, p:GetSoulHearts())
            if s > 0 then p:AddSoulHearts(-s) end
            local r = math.min(owe - s, p:GetHearts())
            if r > 0 then p:AddHearts(-r) end
        end
    end
    RUN.room, RUN.loans = nil, {}
end

-- o jogo roda POST_NEW_ROOM antes do GAME_STARTED: sem essa trava, Continue dentro da
-- sala emprestaria de novo antes do save carregar
local started = false

local function onRoom()
    if not CFG.ENABLED or not started then return end
    local key = floorKey()
    local idx = game:GetLevel():GetCurrentRoomDesc().ListIndex
    -- cobra antes de atualizar o andar: o 12o sacrificio leva direto pro Dark Room
    if RUN.room and (RUN.room ~= idx or RUN.floor ~= key) then collect() end
    RUN.floor = key
    if game:GetRoom():GetType() ~= RoomType.ROOM_SACRIFICE then saveData(); return end
    if not RUN.done then
        RUN.done = true
        RUN.room = idx
        lend()
    end
    -- Wafer so com o emprestimo aberto (1a entrada; Continue dentro da sala tambem)
    if RUN.room == idx then
        for i = 0, game:GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            if lendable(p) and not isKeeper(p) and not isLost(p) then
                p:GetEffects():AddCollectibleEffect(CollectibleType.COLLECTIBLE_WAFER, true)
            end
        end
    end
    saveData()
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, onRoom)

-- ============================================================
-- MCM + save
-- ============================================================
-- no topo: o Isaac so procura na pasta do mod enquanto o main.lua carrega
local okMcm, MCM = pcall(require, "bl_mcm")
if not okMcm then Isaac.DebugString("BloodLoan: bl_mcm nao carregou: " .. tostring(MCM)) end

local mcmDone = false
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
    RUN.floor, RUN.done, RUN.room, RUN.loans = nil, false, nil, {}
    loadData(isContinued)
    if not mcmDone and okMcm and ModConfigMenu then
        local ok, done = pcall(MCM.setup, CFG, saveData)
        if not ok then Isaac.DebugString("BloodLoan: MCM setup falhou: " .. tostring(done)) end
        mcmDone = ok and done
    end
    started = true
    onRoom()
end)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function() saveData(); started = false end)

-- exposto so pro teste estatico
BloodLoan = { CFG = CFG, RUN = RUN }

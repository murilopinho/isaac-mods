--[[
qol_roomtweaks.lua - mecanicas de sala: Auto-Collect, Bombable Devil Statue + Angel Refight Drop.

Bombable Devil Statue - portado do mod de mesmo nome (de Simsure).
Bombardeia a estatua do Devil Room e ela quebra: a porta trava, os itens do deal
desaparecem, um Fallen Angel (Uriel ou Gabriel) spawna, e matar ele dropa um item de
graca da pool do devil.

Corrigido vs. o mod original:
  * declarava `function random(x)` como GLOBAL, entao qualquer outro mod no mesmo estado
    Lua usando esse nome colidia. Aqui e local, semeado com a seed da run em vez de
    math.random;
  * varria toda entidade da sala em tres loops aninhados (O(n3) no pior caso) pra achar a
    bomba, a estatua e os itens do deal. FindByType pega cada um direto;
  * `Distance(a, b)` era chamado com dois argumentos (so aceita 1; o extra era ignorado).

Compatibilidade: o mod "Satan in Devil Rooms (+Fallen Angels)" (Workshop) cobre a mesma
mecanica de destruir a estatua e lutar com o Fallen Angel. Com os dois ativos, DOIS itens
de graca podem dropar na mesma Devil Room (um daqui, outro do mod concorrente) - desligar
um dos dois.

Angel Refight Drop - portado (enxuto) do "Angels Drop Items" (de Sokyran). O original
tinha uma matriz configuravel pras ~30 salas do jogo, % de drop chance e pity persistido;
aqui ficou so o essencial pedido: Angel/Sacrifice/Error Room, refight com as duas Key
Pieces ja em maos, dropa sempre ou com CHANCE% configuravel (sem pity). O original tambem
tinha o modo "Without key" quebrado (nunca disparava) - nao existe mais aqui, ja que nao
tem matriz de modo por sala.
]]

local S      = require("qol_state")
local Config = require("qol_config")

local mod   = S.mod
local game  = S.game
local CFG   = Config.CFG
local music = MusicManager()

local M = {}

-- ── Auto-Collect Pickups (Coleta automatica de moedas e chaves com sala limpa) ──
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not CFG.AUTO_COLLECT_PICKUPS then return end
    local room = game:GetRoom()
    if not room:IsClear() then return end
    
    local player = Isaac.GetPlayer(0)
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
        local pickup = entity:ToPickup()
        if pickup and (pickup.Variant == PickupVariant.PICKUP_COIN or pickup.Variant == PickupVariant.PICKUP_KEY) then
            -- puxa os pickups sem obstaculo em direcao ao jogador
            if pickup.FrameCount > 10 and not pickup:IsShopItem() then
                local dir = (player.Position - pickup.Position):Normalized()
                pickup.Velocity = dir * 6
            end
        end
    end
end)

local EFFECT_BOMB_EXPLOSION = (EffectVariant and EffectVariant.BOMB_EXPLOSION) or 1
local EFFECT_DEVIL_STATUE   = (EffectVariant and EffectVariant.DEVIL) or 6
local STATUE_GRID_INDEX     = 52  -- grid de colisao da estatua no layout vanilla do Devil Room
local BOMB_REACH            = 80  -- px da explosao ate a estatua

-- salas onde o refight do Uriel/Gabriel pode dropar item (pedido do Murilo: so essas 3)
local KEY_PIECE_ROOMS = {
    [RoomType.ROOM_ANGEL]     = true,
    [RoomType.ROOM_SACRIFICE] = true,
    [RoomType.ROOM_ERROR]     = true,
}

-- estatua ja destruida NESTA sala especifica (chave = ListIndex da sala no andar) - nao
-- vaza pra outra Devil Room do mesmo andar (Duality/reroll/etc podem dar mais de uma)
local statueDestroyedRooms = {}
-- limite anti-farm herdado do mod original: so 1 item de graca por ANDAR, mesmo que haja
-- mais de uma Devil Room - global de proposito, ao contrario da tabela acima
local floorItemClaimed     = false
-- luta atual (a que acabou de comecar nesta sala): recompensa dela ja foi dada
local angelDead             = false
-- por sala (ListIndex): quantidade de colecionaveis do deal vista na PRIMEIRA vez que a
-- sala foi visitada nesta run - referencia pra saber se algum ja foi pego depois
local dealInitialCount     = {}
-- por sala (ListIndex): true assim que QUALQUER item do deal foi tirado - e' o preco pelo
-- beneficio de explodir a estatua (pedido do Murilo: pegar 1 item ja nega a explosao,
-- mesmo sobrando outro pedestal na sala - nao e' "zerou tudo", e' "mexeu em algum")
local dealAccepted         = {}
-- RNG semeada UMA vez por abertura de run (nunca por bomba/kill): re-semear com a mesma
-- seed a cada uso fazia todo sorteio da run dar o mesmo numero (chance 0% ou 100%).
local rng                  = RNG()
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    pcall(function()
        rng:SetSeed(game:GetSeeds():GetStartSeed(), S.SHIFT_LOADOUT)
        rng:Next()  -- 1o numero logo apos SetSeed e viesado
    end)
end)

local function isDevilRoom()
    return game:GetRoom():GetType() == RoomType.ROOM_DEVIL
end

-- Em Greed Mode nao existe Mega Satan, entao Key Piece 1/2 sao inuteis como reward (report
-- do Murilo 19/set). Fora de Greed mantem subtype 0 (deixa o engine sortear como sempre
-- sorteou); em Greed sorteia do pool indicado e rejeita as Key Pieces, com limite de
-- tentativas pra nao travar se o pool um dia ficar reduzido a so isso.
local function greedSafeCollectibleId(poolType)
    if not game:IsGreedMode() then return 0 end
    local pool = game:GetItemPool()
    local id = pool:GetCollectible(poolType, true)
    local tries = 0
    while (id == CollectibleType.COLLECTIBLE_KEY_PIECE_1 or id == CollectibleType.COLLECTIBLE_KEY_PIECE_2) and tries < 10 do
        id = pool:GetCollectible(poolType, true)
        tries = tries + 1
    end
    return id
end

local function currentRoomIndex()
    return game:GetLevel():GetCurrentRoomIndex()
end

-- quantos colecionaveis do devil deal ainda estao na sala agora (pedestais nao pegos)
local function countDealPickups()
    local n = 0
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)) do
        local pk = e:ToPickup()
        if pk and pk:IsShopItem() then n = n + 1 end
    end
    return n
end

-- Remove o prop da estatua mais o bloco de grid invisivel por tras dela.
local function removeStatue(room, statueEnt)
    if statueEnt then
        local gi = room:GetGridIndex(statueEnt.Position)
        if gi and gi >= 0 then room:RemoveGridEntity(gi, 0, false) end
        statueEnt:Remove()
    end
    -- fallback: a propria celula de grid da estatua, so tocada se realmente for uma estatua ali
    local g = room:GetGridEntity(STATUE_GRID_INDEX)
    if g and g:GetType() == GridEntityType.GRID_STATUE then
        room:RemoveGridEntity(STATUE_GRID_INDEX, 0, false)
    elseif not statueEnt then
        -- nem o entity effect nem o grid index 52 eram uma estatua: layout diferente do
        -- esperado. Falha silenciosa (porta trava, nenhum Fallen Angel spawna) - loga pra
        -- virar diagnosticavel em vez de sumir sem rastro.
        Isaac.DebugString("QOL: removeStatue nao achou estatua no grid index " .. STATUE_GRID_INDEX .. " (layout diferente?)")
    end
end

mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
    statueDestroyedRooms = {}
    floorItemClaimed     = false
    angelDead            = false
    dealInitialCount     = {}
    dealAccepted         = {}
end)

-- Voltou pra um Devil Room: registra o estado do deal na PRIMEIRA visita (referencia pra
-- saber depois se algo foi tirado) e mantem a estatua quebrada SE FOI ESTA sala (por
-- ListIndex) que ja tinha sido bombardeada antes - uma segunda Devil Room do mesmo andar
-- continua com a propria estatua intacta.
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    if not CFG.BOMBABLE_DEVIL_STATUE or not isDevilRoom() then return end
    local idx = currentRoomIndex()
    if dealInitialCount[idx] == nil then
        dealInitialCount[idx] = countDealPickups()
    end
    if not statueDestroyedRooms[idx] then return end
    local room = game:GetRoom()
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, EFFECT_DEVIL_STATUE)) do
        removeStatue(room, e)
    end
end)

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not CFG.BOMBABLE_DEVIL_STATUE or not isDevilRoom() then return end
    local room         = game:GetRoom()
    local idx          = currentRoomIndex()
    local destroyedHere = statueDestroyedRooms[idx]

    -- algum pedestal do deal sumiu desde a primeira visita a esta sala: preco pago,
    -- explosao fica negada dali em diante (mesmo que ainda sobre outro pedestal)
    if not dealAccepted[idx] and dealInitialCount[idx] and countDealPickups() < dealInitialCount[idx] then
        dealAccepted[idx] = true
    end

    -- o Fallen Angel nascido da estatua acabou de morrer: musica de vitoria + o pedestal de recompensa
    if destroyedHere and not angelDead then
        for _, t in ipairs({ EntityType.ENTITY_URIEL, EntityType.ENTITY_GABRIEL }) do
            for _, angel in ipairs(Isaac.FindByType(t, 1)) do
                -- so reage ao anjo caido QUE A GENTE MESMO spawnou (marca abaixo) - nao
                -- confundir com um Uriel/Gabriel de estatua de anjo de verdade ou de
                -- refight do Angel Drop Item que por acaso esteja na mesma sala
                if angel:GetData().qolDevilStatue and angel:HasMortalDamage() then
                    angelDead = true
                    music:Play(Music.MUSIC_JINGLE_BOSS_OVER, 0.2)
                    music:Queue(Music.MUSIC_BOSS_OVER)
                    local center = room:GetCenterPos()
                    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
                        greedSafeCollectibleId(ItemPoolType.POOL_DEVIL),
                        room:FindFreePickupSpawnPosition(center, 0, true), Vector(0, 0), nil)
                    Isaac.DebugString("QOL: devil statue reward item spawnado (manual)")
                end
            end
        end
    end
    if destroyedHere then return end

    -- uma bomba explodiu neste frame: esta perto o bastante da estatua?
    local statues = Isaac.FindByType(EntityType.ENTITY_EFFECT, EFFECT_DEVIL_STATUE)
    if statues[1] == nil then return end
    for _, blast in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, EFFECT_BOMB_EXPLOSION)) do
        if blast.FrameCount == 1 then
            for _, statue in ipairs(statues) do
                if statue.Position:Distance(blast.Position) < BOMB_REACH then
                    if floorItemClaimed then
                        Isaac.DebugString("QOL: devil statue ja rendeu item neste andar, bomba ignorada")
                        return
                    end
                    if dealAccepted[idx] then
                        Isaac.DebugString("QOL: devil deal ja foi aceito nesta sala, estatua ignora a bomba")
                        return
                    end
                    statueDestroyedRooms[idx] = true
                    floorItemClaimed          = true

                    -- trava a porta: agora e luta
                    local enterDoor = room:GetDoor(game:GetLevel().EnterDoor)
                    if enterDoor ~= nil and enterDoor:IsOpen() then enterDoor:Bar() end

                    removeStatue(room, statue)

                    -- os itens do devil deal vao embora, o anjo agora e o deal
                    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)) do
                        local pk = e:ToPickup()
                        if pk and pk:IsShopItem() then e:Remove() end
                    end

                    local pos    = statue.Position
                    local player = Isaac.GetPlayer(0)
                    local which  = (rng:RandomInt(2) == 0) and EntityType.ENTITY_URIEL or EntityType.ENTITY_GABRIEL
                    local angel  = Isaac.Spawn(which, 1, 0, pos, Vector(0, 0), player)
                    angel:GetData().qolDevilStatue = true

                    room:SetClear(false)
                    music:Play(Music.MUSIC_SATAN_BOSS, 0.2)
                    Isaac.DebugString("QOL: estatua do devil bombardeada -> fallen angel spawnado")
                    return
                end
            end
        end
    end
end)

-- ── Angel Refight Drop: Uriel/Gabriel de novo com as DUAS Key Pieces ja em maos ─
-- Balanceamento: ALWAYS=true (default) sempre dropa; ALWAYS=false rola CHANCE% (o anjo pode
-- nao dropar nada). A estatua do Devil nao tem chance: ela ja cobra o preco (perde os deals).
local function angelDropsItem(_, entity)
    if not CFG.ANGEL_DROP_ITEM then return end
    -- blindagem extra (alem do gate de sala abaixo): nunca reagir ao anjo caido que a
    -- propria Bombable Devil Statue spawnou - aquele ja tem sua propria recompensa manual
    -- em MC_POST_UPDATE, reagir aqui de novo duplicava o item (report do Murilo 18/set)
    if entity:GetData().qolDevilStatue then return end
    if not KEY_PIECE_ROOMS[game:GetRoom():GetType()] then return end

    -- as duas pecas contam somando o time (co-op: um pode ter a 1, outro a 2)
    local has1, has2 = false, false
    for i = 0, game:GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        has1 = has1 or p:HasCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_1)
        has2 = has2 or p:HasCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_2)
    end
    if not (has1 and has2) then return end
    if not CFG.ANGEL_DROP_ALWAYS and rng:RandomInt(100) >= CFG.ANGEL_DROP_CHANCE then
        Isaac.DebugString("QOL: angel refight nao passou na chance (" .. CFG.ANGEL_DROP_CHANCE .. "%)")
        return
    end

    local room = game:GetRoom()
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
        greedSafeCollectibleId(ItemPoolType.POOL_ANGEL),
        room:FindFreePickupSpawnPosition(entity.Position, 0, true), Vector(0, 0), entity)
    Isaac.DebugString("QOL: angel refight drop item spawnado (angelDropsItem)")
end
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, angelDropsItem, EntityType.ENTITY_URIEL)
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, angelDropsItem, EntityType.ENTITY_GABRIEL)

-- Chamado pelo main.lua no MC_POST_GAME_STARTED numa run NOVA (nao isSave).
function M.resetForNewRun()
    statueDestroyedRooms = {}
    floorItemClaimed     = false
    angelDead            = false
    dealInitialCount     = {}
    dealAccepted         = {}
end

return M

--[[
qol_charfixes.lua - fixes e buffs por personagem.

  * Judas + Birthright   - remove o Book of Belial fantasma que sobra no slot pocket
                           (portado do Enemy Drop Loot V2)
  * Holy Mantle Jacob    - Tainted Jacob mantem Holy Mantle enquanto estiver na forma Lost
                           (portado do "Holy Mantle For Lost Jacob", de Dijiphos)
  * Rainbow Poop Mantle  - coco arco-iris da uma carga de Holy Card pro Tainted Lost
                           (portado do "Rainbow Poop Gives Holy Mantle", de Reisen)
  * Lost Bed Mantle      - Lost / Tainted Lost encostam na cama e ganham Holy Card (1 por cama)
]]

local S      = require("qol_state")
local Config = require("qol_config")

local mod  = S.mod
local game = S.game
local CFG  = Config.CFG
local HAS_REPENTOGON = S.HAS_REPENTOGON

local M = {}

-- ── Judas + Birthright: remove o Belial que sobra no pocket ───────────────────
-- A feature Active -> Pocket manda o Belial pro pocket no inicio da run (Judas sem
-- Birthright nao e excecao). Pegar Birthright depois deixa esse Belial preso no pocket,
-- porque Birthright quer ele HELD e o check nativo do motor nao ve o slot pocket.
-- Espera alguns frames o jogo dar o Belial de graca do Birthright, ai tira o do pocket.
--
-- LIMITACAO CONHECIDA, sem fix possivel: tirar um ativo de pocket de um personagem sem
-- Schoolbag via API deixa um SLOT POCKET FANTASMA (icone de bolsa vazia). E um bug de HUD
-- do proprio motor; nao existe metodo na API (vanilla ou REPENTOGON) pra limpar isso. E
-- puramente cosmetico (slot vazio, nao faz nada). A unica forma de evitar por completo
-- seria nunca deixar o Belial chegar no pocket.
local judasBelialFixDone = false
local judasBelialFixArm  = -1

mod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, function(_, player)
    if not CFG.JUDAS_BELIAL_FIX or judasBelialFixDone then return end
    local pt = player:GetPlayerType()
    if pt ~= PlayerType.PLAYER_JUDAS and pt ~= PlayerType.PLAYER_BLACKJUDAS then return end
    if not player:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT) then return end
    local BELIAL = CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL
    if player:GetActiveItem(ActiveSlot.SLOT_POCKET) ~= BELIAL then return end
    local f = game:GetFrameCount()
    if judasBelialFixArm < 0 then judasBelialFixArm = f; return end
    if f - judasBelialFixArm < 10 then return end   -- deixa o jogo dar o Belial de graca primeiro
    judasBelialFixDone = true
    pcall(function()
        local before = player:GetCollectibleNum(BELIAL, true)
        if HAS_REPENTOGON then
            player:RemoveCollectible(BELIAL, false, ActiveSlot.SLOT_POCKET, false)
        end
        if player:GetActiveItem(ActiveSlot.SLOT_POCKET) == BELIAL then
            player:SetPocketActiveItem(CollectibleType.COLLECTIBLE_NULL, ActiveSlot.SLOT_POCKET, false)
        end
        Isaac.DebugString(("QOL Judas+Birthright: tirei o Belial do pocket, Belial %d -> %d, pocket=%d")
            :format(before, player:GetCollectibleNum(BELIAL, true), player:GetActiveItem(ActiveSlot.SLOT_POCKET)))
    end)
end)

-- ── Holy Mantle pra forma Lost do Tainted Jacob ────────────────────────────────
-- Da o efeito de Holy Mantle uma vez por sala; o jogo limpa quando voce sai da sala.
-- Tambem rearma quando Jacob toca o Dark Esau, porque e isso que manda ele pra forma Lost.
-- Diferenca do mod original: USE_NOANIM | USE_NOANNOUNCER, senao a animacao de uso do item
-- e o nome do item pipocavam em toda sala.
local DARK_ESAU = (EntityType and EntityType.ENTITY_DARK_ESAU) or 866
local mantleChecked = false

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not CFG.HOLY_MANTLE_JACOB or mantleChecked then return end
    mantleChecked = true
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player:GetPlayerType() == PlayerType.PLAYER_JACOB2_B
           and not player:HasCollectible(CollectibleType.COLLECTIBLE_HOLY_MANTLE, true) then
            player:UseActiveItem(CollectibleType.COLLECTIBLE_HOLY_MANTLE,
                UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
        end
    end
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    mantleChecked = false
end)

mod:AddCallback(ModCallbacks.MC_PRE_PLAYER_COLLISION, function(_, player, collider, low)
    if not CFG.HOLY_MANTLE_JACOB then return end
    if player:GetPlayerType() == PlayerType.PLAYER_JACOB_B
       and collider.Type == DARK_ESAU and collider.Variant == 0 then
        mantleChecked = false   -- ele esta virando Lost Jacob: reroda o check
    end
end)

-- ── Coco arco-iris da uma carga de Holy Card pro Tainted Lost ─────────────────
-- Corrigido vs. o mod original: o loop do grid era `for ind = 1, GetGridSize()`, que pula o
-- indice 0 e le 1 alem do fim; indice de grid e 0-based. Tambem hardcodava o player type
-- 31 e escaneava o grid inteiro todo frame, mesmo sem Tainted Lost na run. Agora o scan e
-- travado por um check de "tem Tainted Lost" por sala.
local hasTaintedLost = false

local function refreshTaintedLost()
    hasTaintedLost = false
    for i = 0, game:GetNumPlayers() - 1 do
        if Isaac.GetPlayer(i):GetPlayerType() == PlayerType.PLAYER_THELOST_B then
            hasTaintedLost = true
            return
        end
    end
end

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, refreshTaintedLost)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, refreshTaintedLost)

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not CFG.RAINBOW_POOP_MANTLE or not hasTaintedLost then return end
    local room = game:GetRoom()
    for i = 0, room:GetGridSize() - 1 do
        local gridEnt = room:GetGridEntity(i)
        -- GRID_POOP variant 4 = coco arco-iris; "State5" frame 1 e o frame em que ele quebra
        if gridEnt and gridEnt:GetType() == GridEntityType.GRID_POOP and gridEnt:GetVariant() == 4
           and gridEnt:GetSprite():IsPlaying("State5") and gridEnt:GetSprite():GetFrame() == 1 then
            for p = 0, game:GetNumPlayers() - 1 do
                local player = Isaac.GetPlayer(p)
                if player:GetPlayerType() == PlayerType.PLAYER_THELOST_B then
                    player:UseCard(Card.CARD_HOLY, UseFlag.USE_NOANIM | UseFlag.USE_NOHUD | UseFlag.USE_NOANNOUNCER)
                end
            end
        end
    end
end)

-- ── Lost Bed Mantle: Lost / Tainted Lost encostam na cama e ganham Holy Card ──
-- A cama (Isaac ou Mom) segue funcionando normal; o Holy Card vem por cima.
-- 1 carga por cama; a cama e marcada pelo ListIndex da sala e o andar novo zera.
-- ponytail: marca so em memoria, sair e continuar a run libera a cama de novo
local bedUsed = {}

local function isLost(player)
    local t = player:GetPlayerType()
    return t == PlayerType.PLAYER_THELOST or t == PlayerType.PLAYER_THELOST_B
end

mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function() bedUsed = {} end)

mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
    if not CFG.LOST_BED_MANTLE then return end
    local player = collider:ToPlayer()
    if not player or not isLost(player) then return end
    local key = game:GetLevel():GetCurrentRoomDesc().ListIndex .. ":" .. pickup.InitSeed
    if bedUsed[key] then return end
    bedUsed[key] = true
    player:UseCard(Card.CARD_HOLY, UseFlag.USE_NOANIM | UseFlag.USE_NOHUD)
end, PickupVariant.PICKUP_BED)

-- Chamado pelo main.lua no MC_POST_GAME_STARTED numa run NOVA (nao isSave).
function M.resetForNewRun()
    judasBelialFixDone = false
    judasBelialFixArm  = -1
    mantleChecked      = false
    bedUsed            = {}
end

return M

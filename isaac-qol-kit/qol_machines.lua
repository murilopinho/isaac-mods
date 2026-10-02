--[[
qol_machines.lua - remocoes de atrito em maquinas, baus e cenario.

  * No Jam               - maquina de doacao/greed travada destrava ao sair e voltar na sala
                           (portado do "No Jam", de Mystic)
  * Faster Eternal Chest - o Eternal Chest deixa de te fazer esperar
                           (portado do "Faster Eternal Chest", de Vinnie)
  * Instant Fires/Poops  - sala limpa: coco e fogueira morrem no primeiro hit
                           (portado do "Instant Fires and Poops", de Matt)
]]

local S           = require("qol_state")
local Config      = require("qol_config")

local mod  = S.mod
local game = S.game
local CFG  = Config.CFG

local M = {}

-- ============================================================
-- No Jam
-- ============================================================
-- Destravar e feito removendo a entidade do slot e spawnando uma identica, porque a
-- travada vive na entidade, nao so na flag de estado.
-- Mudado vs. o mod original: ele destravava em TODO frame; aqui so na entrada da sala.
-- So as duas maquinas de doacao sao recriadas: a do shop (variant 8) e a do Greed (11).
-- Beggar, Restock, Arcade etc nunca sao tocados (recriar perdia o estado deles).
-- Numero literal porque o enum SlotVariant so existe com REPENTOGON.
local DONATION_VARIANTS = { [8] = true, [11] = true }

local function unjamSlots()
    if not (game:GetStateFlag(GameStateFlag.STATE_DONATION_SLOT_JAMMED)
            or game:GetStateFlag(GameStateFlag.STATE_GREED_SLOT_JAMMED)) then return end
    -- Zera ANTES do Spawn: a maquina nova le a flag no init e nasceria travada de novo.
    game:SetStateFlag(GameStateFlag.STATE_DONATION_SLOT_JAMMED, false)
    game:SetStateFlag(GameStateFlag.STATE_GREED_SLOT_JAMMED, false)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e.Type == EntityType.ENTITY_SLOT and DONATION_VARIANTS[e.Variant] then
            local t, v, st, pos = e.Type, e.Variant, e.SubType, e.Position
            e:Remove()
            local newEnt = Isaac.Spawn(t, v, st, pos, Vector(0, 0), nil)
            -- Isaac.Spawn realoca pra "posicao livre mais proxima" se `pos` estiver ocupado
            -- (o player normalmente esta colado na maquina, doando) - essa busca so olha
            -- colisao de entidade, nao parede, e pode jogar a maquina pra dentro da parede.
            -- `pos` ja e valido (era onde a maquina original estava), entao forca de volta.
            if newEnt then newEnt.Position = pos end
        end
    end
end

-- So ao entrar na sala, nunca no meio da doacao: a maquina recem-spawnada fica uns frames
-- sem colisao, o player (colado nela) entra dentro e o empurrao ao religar desloca a maquina.
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    if CFG.NO_JAM then unjamSlots() end
end)

-- ============================================================
-- Faster Eternal Chest
-- ============================================================
-- O Eternal Chest so fecha depois de uma animacao de espera longa. Enquanto esta aberto E
-- um pickup fresco acabou de saltar dele, forcamos 30 chamadas extras de Update() nele pra
-- terminar agora.
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not CFG.FASTER_ETERNAL_CHEST then return end
    local chests = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_ETERNALCHEST)
    if #chests == 0 then return end
    local hasFreshPickup = false
    for _, pickup in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
        if pickup.Variant ~= PickupVariant.PICKUP_ETERNALCHEST
           and pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE
           and pickup.FrameCount < 10 then
            hasFreshPickup = true
            break
        end
    end
    if not hasFreshPickup then return end
    for _, ent in ipairs(chests) do
        if ent:GetSprite():GetAnimation() == "Open" then
            for _ = 1, 30 do ent:Update() end
        end
    end
end)

-- ============================================================
-- Instant Fires and Poops
-- ============================================================
-- Com a sala limpa nao tem motivo pra bater 4 vezes num coco. Guardamos o State de cada
-- coco por indice de grid; quando a sala esta limpa e o State subiu (tomou um hit), o coco
-- e destruido direto. Fogueira morre no primeiro hit do mesmo jeito.
-- Corrigido vs. o mod original: usava uma tabela GLOBAL `Poops` (qualquer outra coisa no mesmo
-- estado Lua podia colidir com esse nome) e indexava com off-by-one.
local poopState = {}

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    poopState = {}
end)

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not CFG.INSTANT_FIRES_POOPS then return end
    local room = game:GetRoom()
    local clear = room:IsClear()
    for i = 0, room:GetGridSize() - 1 do
        local gridEnt = room:GetGridEntity(i)
        local poop = gridEnt and gridEnt:ToPoop()
        -- State >= 1000 significa ja destruido
        if poop and poop.State < 1000 then
            local state = poop.State
            if poopState[i] == nil then poopState[i] = state end
            if clear then
                if state > poopState[i] then gridEnt:Destroy() end
            else
                poopState[i] = state  -- sala nao limpa: so acompanha, sem atalho
            end
        end
    end
end)

mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity)
    if not CFG.INSTANT_FIRES_POOPS then return end
    if entity.Variant ~= 0 then return end  -- variant 0 = a fogueira laranja normal
    if game:GetRoom():IsClear() then
        entity:Die()
        return true  -- dano tratado, pula o hit normal
    end
end, EntityType.ENTITY_FIREPLACE)

-- Chamado pelo main.lua no MC_POST_GAME_STARTED numa run NOVA (nao isSave).
function M.resetForNewRun()
    poopState = {}
end

return M

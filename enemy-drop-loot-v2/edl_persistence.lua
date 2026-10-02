--[[
edl_persistence.lua — Persistência (salva/carrega o CFG entre runs)
]]

local S      = require("edl_state")
local Config = require("edl_config")

local mod = S.mod
local json = S.json
local CFG = Config.CFG
local CFG_SCALAR_KEYS = Config.CFG_SCALAR_KEYS

local M = {}

function M.saveConfig()
    if not json then return end
    pcall(function()
        local d = {}
        for _, k in ipairs(CFG_SCALAR_KEYS) do d[k] = CFG[k] end
        d.ITEM_DROP_RATE     = { NORMAL=CFG.ITEM_DROP_RATE.NORMAL,     CHAMPION=CFG.ITEM_DROP_RATE.CHAMPION,     BOSS=CFG.ITEM_DROP_RATE.BOSS }
        d.RESOURCE_DROP_RATE = { NORMAL=CFG.RESOURCE_DROP_RATE.NORMAL, CHAMPION=CFG.RESOURCE_DROP_RATE.CHAMPION, BOSS=CFG.RESOURCE_DROP_RATE.BOSS }
        d.runCount = S.runCount
        d.MIN_QUALITY_V2 = true -- marca a escala nova (-1 = any)
        -- só grava a lista de dedup por-run quando o flag está ligado.
        if S.PERSIST_DROPPED_ITEMS then
            local di = {}
            for id in pairs(S.droppedItems) do di[#di + 1] = id end
            d.droppedItems = di
            local ps = {}
            for k, id in pairs(S.pendingSeeds) do ps[k] = id end
            d.pendingSeeds = ps
            d.roomDrops = S.roomDrops
            d.roomDropsLevel = S.roomDropsLevel
        end
        mod:SaveData(json.encode(d))
    end)
end

function M.loadConfig()
    if not json or not mod:HasData() then return end
    pcall(function()
        local d = json.decode(mod:LoadData())
        if type(d) ~= "table" then return end
        for _, k in ipairs(CFG_SCALAR_KEYS) do
            if d[k] ~= nil then CFG[k] = d[k] end
        end
        -- migra saves antigos com Floor Scaling em 0% (OFF): o mínimo agora é 1%, então
        -- força pra cima quem já tinha 0 gravado no disco.
        if CFG.FLOOR_SCALING_PCT < 1 then CFG.FLOOR_SCALING_PCT = 1 end
        -- migra Min Quality: antes 0 = any; agora any = -1 e 0 = só Q0.
        if d.MIN_QUALITY_V2 == nil and CFG.MIN_QUALITY == 0 then CFG.MIN_QUALITY = -1 end
        -- migra o antigo booleano BLOCK_UNOWNED_ITEMS (true=seen, false=off) pro
        -- novo UNLOCK_FILTER de 3 estados pra quem já salvou não ser resetado.
        if d.UNLOCK_FILTER == nil and d.BLOCK_UNOWNED_ITEMS ~= nil then
            CFG.UNLOCK_FILTER = d.BLOCK_UNOWNED_ITEMS and 2 or 0
        end
        for _, sub in ipairs({"NORMAL","CHAMPION","BOSS"}) do
            if type(d.ITEM_DROP_RATE) == "table"     and d.ITEM_DROP_RATE[sub]     ~= nil then CFG.ITEM_DROP_RATE[sub]     = d.ITEM_DROP_RATE[sub]     end
            if type(d.RESOURCE_DROP_RATE) == "table" and d.RESOURCE_DROP_RATE[sub] ~= nil then CFG.RESOURCE_DROP_RATE[sub] = d.RESOURCE_DROP_RATE[sub] end
        end
        if type(d.runCount) == "number" then S.runCount = d.runCount end
        -- saves antigos (pré-split) ainda trazem appliedRunCount/pocketAppliedRunCount e as chaves
        -- das features de loadout. São ignorados de propósito: essas features viraram o Isaac QoL Kit.
        -- Restaura a lista de dedup por-run (S.PERSIST_DROPPED_ITEMS é sempre true hoje, ver edl_state.lua).
        -- Run NOVA a limpa logo depois no POST_GAME_STARTED (if not isSave); no Continue fica.
        if S.PERSIST_DROPPED_ITEMS and type(d.droppedItems) == "table" then
            S.droppedItems = {}
            for _, id in ipairs(d.droppedItems) do
                if type(id) == "number" then S.droppedItems[id] = true end
            end
        end
        if S.PERSIST_DROPPED_ITEMS and type(d.pendingSeeds) == "table" then
            S.pendingSeeds = {}
            for k, id in pairs(d.pendingSeeds) do
                if type(id) == "number" then S.pendingSeeds[tostring(k)] = id end
            end
        end
        if S.PERSIST_DROPPED_ITEMS and type(d.roomDrops) == "table" then
            S.roomDrops = {}
            for k, e in pairs(d.roomDrops) do
                if type(e) == "table" and type(e.items) == "number" and type(e.pickups) == "number" then
                    S.roomDrops[tostring(k)] = { items = e.items, pickups = e.pickups, kind = e.kind or "normal" }
                end
            end
            S.roomDropsLevel = d.roomDropsLevel
        end
    end)
end

return M

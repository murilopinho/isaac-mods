--[[
  Shop Gulp - a cada 2 lojas novas que voce entra, a loja deixa uma pilula de Gulp! no
  chao. Maximo 2 por run. Pra quem achou um trinket bom e quer ficar com ele pra sempre.
  Conta so a 1a visita de cada loja. Estado vai no SaveData (sobrevive ao Continue).
  Comentarios sem acento (a engine quebra com acento em texto renderizado).
]]

local mod = RegisterMod("ShopGulp", 1)
local json = (function() local ok, m = pcall(require, "json"); return ok and m or nil end)()

-- ============================================================
-- Config (MCM opcional: sem ele, vale este default)
-- ============================================================
local CFG = { ENABLED = true }
local EVERY, MAX_PER_RUN = 2, 2
local RUN = { shops = 0, given = 0 }

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
            RUN.shops, RUN.given = tonumber(d.run.shops) or 0, tonumber(d.run.given) or 0
        end
    end)
end

-- ============================================================
-- Logica
-- ============================================================
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    if not CFG.ENABLED or RUN.given >= MAX_PER_RUN then return end
    local game = Game()
    local room = game:GetRoom()
    if room:GetType() ~= RoomType.ROOM_SHOP or not room:IsFirstVisit() then return end
    RUN.shops = RUN.shops + 1
    if RUN.shops % EVERY == 0 then
        RUN.given = RUN.given + 1
        local color = game:GetItemPool():ForceAddPillEffect(PillEffect.PILLEFFECT_GULP)
        local pos = Isaac.GetFreeNearPosition(room:GetCenterPos(), 40)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_PILL, color, pos, Vector.Zero, nil)
    end
    saveData()
end)

-- ============================================================
-- MCM + save
-- ============================================================
-- no topo: o Isaac so procura na pasta do mod enquanto o main.lua carrega
local okMcm, MCM = pcall(require, "sg_mcm")
if not okMcm then Isaac.DebugString("ShopGulp: sg_mcm nao carregou: " .. tostring(MCM)) end

local mcmDone = false
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
    RUN.shops, RUN.given = 0, 0
    loadData(isContinued)
    if not mcmDone and okMcm and ModConfigMenu then
        local ok, done = pcall(MCM.setup, CFG, saveData)
        if not ok then Isaac.DebugString("ShopGulp: MCM setup falhou: " .. tostring(done)) end
        mcmDone = ok and done
    end
end)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, saveData)

-- exposto so pro teste estatico
ShopGulp = { CFG = CFG, RUN = RUN }

--[[
  Free Flesh Door - porta de carne da Mom (Mausoleum/Gehenna II).
    Mom morta: o mod da as Knife Pieces que faltam e a porta abre do jeito vanilla (encostar).
    Keep the knife (MCM, padrao ON): as pecas nao somem ao abrir a porta (o mod devolve).
  So vale se a porta ja estiver desbloqueada no save (sem ela o jogo nem cria a porta).
  Fora: Ascent, Greed.
  Comentarios sem acento (a engine quebra com acento em texto renderizado).
]]

local mod = RegisterMod("FleshDoor", 1)
local json = (function() local ok, m = pcall(require, "json"); return ok and m or nil end)()

-- ============================================================
-- Config (MCM opcional: sem ele, vale este default)
-- ============================================================
local CFG = { ENABLED = true, KEEP = true }

local function saveData()
    if not json then return end
    pcall(function() mod:SaveData(json.encode(CFG)) end)
end

local function loadData()
    if not json or not mod:HasData() then return end
    pcall(function()
        local d = json.decode(mod:LoadData())
        if type(d) ~= "table" then return end
        if type(d.ENABLED) == "boolean" then CFG.ENABLED = d.ENABLED end
        if type(d.KEEP) == "boolean" then CFG.KEEP = d.KEEP end
    end)
end

-- ============================================================
-- Logica
-- ============================================================
local game = Game()
local K1, K2 = CollectibleType.COLLECTIBLE_KNIFE_PIECE_1, CollectibleType.COLLECTIBLE_KNIFE_PIECE_2

-- sala da Mom no Mausoleum/Gehenna II (ou XL)
local function inMomRoom()
    if game:IsGreedMode() or game:GetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH) then return false end
    local level = game:GetLevel()
    local st, stage = level:GetStageType(), level:GetStage()
    if st ~= StageType.STAGETYPE_REPENTANCE and st ~= StageType.STAGETYPE_REPENTANCE_B then return false end
    local xl = stage == LevelStage.STAGE3_1 and level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH ~= 0
    return (stage == LevelStage.STAGE3_2 or xl) and game:GetRoom():GetType() == RoomType.ROOM_BOSS
end

local watching = false -- sala da Mom, esperando ela morrer
-- keep: pecas que cada player tinha quando a Mom morreu (sai da lista ao devolver)
local knifeHad = nil

-- devolve 1x cada peca que sumiu (o jogo tira as pecas ao abrir a porta)
local function restoreKnife()
    for i, had in pairs(knifeHad or {}) do
        local p = Isaac.GetPlayer(i)
        for id in pairs(had) do
            if p and not p:HasCollectible(id) then p:AddCollectible(id); had[id] = nil end
        end
    end
end

-- completa a faca de quem ja tem uma peca (senao o player 1), se ninguem tiver as 2
local function giveKnife()
    local n, target = game:GetNumPlayers(), Isaac.GetPlayer(0)
    for i = n - 1, 0, -1 do
        local p = Isaac.GetPlayer(i)
        if p:HasCollectible(K1) and p:HasCollectible(K2) then return end
        if p:HasCollectible(K1) or p:HasCollectible(K2) then target = p end
    end
    for _, id in ipairs({ K1, K2 }) do
        if not target:HasCollectible(id) then target:AddCollectible(id) end
    end
end

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    -- saiu da sala da Mom: se o jogo tirar so na transicao, devolve aqui na sala seguinte
    if knifeHad then restoreKnife(); knifeHad = nil end
    watching = CFG.ENABLED and inMomRoom()
end)

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if knifeHad then restoreKnife() end
    if not watching or not game:GetRoom():IsClear() then return end
    watching = false
    giveKnife()
    if not CFG.KEEP then return end
    knifeHad = {}
    for i = 0, game:GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        if p:HasCollectible(K1) and p:HasCollectible(K2) then knifeHad[i] = { [K1] = true, [K2] = true } end
    end
end)

-- ============================================================
-- MCM + save
-- ============================================================
-- no topo: o Isaac so procura na pasta do mod enquanto o main.lua carrega
local okMcm, MCM = pcall(require, "fd_mcm")
if not okMcm then Isaac.DebugString("FleshDoor: fd_mcm nao carregou: " .. tostring(MCM)) end

loadData()

local mcmDone = false
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    if not mcmDone and okMcm and ModConfigMenu then
        local ok, done = pcall(MCM.setup, CFG, saveData)
        if not ok then Isaac.DebugString("FleshDoor: MCM setup falhou: " .. tostring(done)) end
        mcmDone = ok and done
    end
end)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, saveData)

-- exposto so pro teste estatico
FleshDoor = { CFG = CFG }

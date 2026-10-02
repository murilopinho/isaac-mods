--[[
  No Curse of the Blind - a Curse of the Blind nunca aparece. Em troca, andar que ficaria
  sem curse tem EXTRA_CHANCE de ganhar uma (Darkness, Lost, Unknown ou Maze).
  Sem curse extra: Basement I, Blue Womb, Home, Ascent, challenge, Black Candle e seed
  que bloqueia curses. Labyrinth fica de fora (XL forcado pelo mod quebra andar).
  Roll usa o seed do andar: mesma seed, mesma curse.
  Comentarios sem acento (a engine quebra com acento em texto renderizado).
]]

local mod = RegisterMod("NoCurseOfTheBlind", 1)
local json = (function() local ok, m = pcall(require, "json"); return ok and m or nil end)()

-- ============================================================
-- Config (MCM opcional: sem ele, vale este default)
-- ============================================================
local CFG = { ENABLED = true, EXTRA = true }
local EXTRA_CHANCE = 0.15
local EXTRA_POOL = {
    LevelCurse.CURSE_OF_DARKNESS, LevelCurse.CURSE_OF_THE_LOST,
    LevelCurse.CURSE_OF_THE_UNKNOWN, LevelCurse.CURSE_OF_MAZE,
}

local function saveData()
    if not json then return end
    pcall(function() mod:SaveData(json.encode(CFG)) end)
end

local function loadData()
    if not json or not mod:HasData() then return end
    pcall(function()
        local d = json.decode(mod:LoadData())
        if type(d) ~= "table" then return end
        for k in pairs(CFG) do
            if type(d[k]) == "boolean" then CFG[k] = d[k] end
        end
    end)
end

-- ============================================================
-- Logica
-- ============================================================
local function extraAllowed()
    local game = Game()
    local stage = game:GetLevel():GetStage()
    if stage == LevelStage.STAGE1_1 or stage == LevelStage.STAGE4_3 or stage == LevelStage.STAGE8 then return false end
    if game.Challenge ~= Challenge.CHALLENGE_NULL then return false end
    if game:GetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH) then return false end
    if game:GetSeeds():HasSeedEffect(SeedEffect.SEED_PREVENT_ALL_CURSES) then return false end
    for i = 0, game:GetNumPlayers() - 1 do
        if Isaac.GetPlayer(i):HasCollectible(CollectibleType.COLLECTIBLE_BLACK_CANDLE) then return false end
    end
    return true
end

mod:AddCallback(ModCallbacks.MC_POST_CURSE_EVAL, function(_, curses)
    if not CFG.ENABLED then return end
    curses = curses & ~LevelCurse.CURSE_OF_BLIND
    if curses == 0 and CFG.EXTRA and extraAllowed() then
        local game = Game()
        local rng = RNG()
        rng:SetSeed(game:GetSeeds():GetStageSeed(game:GetLevel():GetStage()), 35)
        rng:Next()
        if rng:RandomFloat() < EXTRA_CHANCE then
            curses = EXTRA_POOL[rng:RandomInt(#EXTRA_POOL) + 1]
        end
    end
    return curses
end)

-- ============================================================
-- MCM + save
-- ============================================================
-- no topo: o Isaac so procura na pasta do mod enquanto o main.lua carrega
local okMcm, MCM = pcall(require, "ncb_mcm")
if not okMcm then Isaac.DebugString("NoCurseOfTheBlind: ncb_mcm nao carregou: " .. tostring(MCM)) end

-- config carrega ja no load do mod: a curse do Basement I sai antes do GAME_STARTED
loadData()

local mcmDone = false
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    if not mcmDone and okMcm and ModConfigMenu then
        local ok, done = pcall(MCM.setup, CFG, saveData)
        if not ok then Isaac.DebugString("NoCurseOfTheBlind: MCM setup falhou: " .. tostring(done)) end
        mcmDone = ok and done
    end
end)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, saveData)

-- exposto so pro teste estatico
NoCurseOfTheBlind = { CFG = CFG }

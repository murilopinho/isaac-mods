--[[
  Golden Swap - pegar Golden Key/Bomb repetida nao se perde mais.
    Golden Key com Golden Key ja na mao  -> vira Golden Bomb (se ainda nao tiver)
    Golden Bomb com Golden Bomb ja na mao -> vira Golden Key (se ainda nao tiver)
    Com as duas ja na mao                -> Key vira KEYS chaves, Bomb vira BOMBS bombas
  Fora: pickup com preco (loja segue vanilla).
  Comentarios sem acento (a engine quebra com acento em texto renderizado).
]]

local mod = RegisterMod("GoldenSwap", 1)
local json = (function() local ok, m = pcall(require, "json"); return ok and m or nil end)()

-- ============================================================
-- Config (MCM opcional: sem ele, vale este default)
-- ============================================================
local CFG = { ENABLED = true }
local KEYS, BOMBS = 10, 14

local function saveData()
    if not json then return end
    pcall(function() mod:SaveData(json.encode(CFG)) end)
end

local function loadData()
    if not json or not mod:HasData() then return end
    pcall(function()
        local d = json.decode(mod:LoadData())
        if type(d) == "table" and type(d.ENABLED) == "boolean" then CFG.ENABLED = d.ENABLED end
    end)
end

-- ============================================================
-- Logica
-- ============================================================
local sfx = SFXManager()

-- consome o pickup no lugar do jogo: o vanilla so apagaria ele sem dar nada
local function take(pickup, sound)
    sfx:Play(sound)
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, pickup.Position, Vector.Zero, nil)
    pickup:Remove()
    return true
end

mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
    if not CFG.ENABLED or pickup.Price ~= 0 or pickup.SubType ~= KeySubType.KEY_GOLDEN then return end
    local player = collider:ToPlayer()
    if not player or not player:HasGoldenKey() then return end
    if not player:HasGoldenBomb() then
        player:AddGoldenBomb()
        return take(pickup, SoundEffect.SOUND_GOLDENBOMB)
    end
    player:AddKeys(KEYS)
    return take(pickup, SoundEffect.SOUND_GOLDENKEY)
end, PickupVariant.PICKUP_KEY)

mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
    if not CFG.ENABLED or pickup.Price ~= 0 or pickup.SubType ~= BombSubType.BOMB_GOLDEN then return end
    local player = collider:ToPlayer()
    if not player or not player:HasGoldenBomb() then return end
    if not player:HasGoldenKey() then
        player:AddGoldenKey()
        return take(pickup, SoundEffect.SOUND_GOLDENKEY)
    end
    player:AddBombs(BOMBS)
    return take(pickup, SoundEffect.SOUND_GOLDENBOMB)
end, PickupVariant.PICKUP_BOMB)

-- ============================================================
-- MCM + save
-- ============================================================
-- no topo: o Isaac so procura na pasta do mod enquanto o main.lua carrega
local okMcm, MCM = pcall(require, "gs_mcm")
if not okMcm then Isaac.DebugString("GoldenSwap: gs_mcm nao carregou: " .. tostring(MCM)) end

loadData()

local mcmDone = false
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    if not mcmDone and okMcm and ModConfigMenu then
        local ok, done = pcall(MCM.setup, CFG, saveData)
        if not ok then Isaac.DebugString("GoldenSwap: MCM setup falhou: " .. tostring(done)) end
        mcmDone = ok and done
    end
end)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, saveData)

-- exposto so pro teste estatico
GoldenSwap = { CFG = CFG }

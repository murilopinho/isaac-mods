--[[
qol_loadout.lua - tudo que roda UMA VEZ por run pra montar o inventario inicial:
  * Fileira de Trinkets    - fileira curada de trinkets no chao, pega uma
  * Character Trinket Choice - lista por personagem, opcionalmente fixa num slot
  * Active -> Pocket Active  - move o ativo inicial pro slot pocket
  * Counterfeit Penny do Greed/Greedier (+ pilula de Gulp ao pegar)

Portado do Enemy Drop Loot V2 (eld_trinkets.lua). As duas dependencias que tinha no
drop engine do EDL sairam: TWIN_PLAYER_TYPES foi copiado local aqui embaixo, e o toast
de debug foi descartado por completo.
]]

local S           = require("qol_state")
local Config      = require("qol_config")
local Persistence = require("qol_persistence")
local TrinketUtil = require("qol_trinketutil")

local mod  = S.mod
local game = S.game
local CFG  = Config.CFG
local HAS_REPENTOGON = S.HAS_REPENTOGON
local saveConfig = Persistence.saveConfig
local smeltPlayerTrinkets = TrinketUtil.smeltPlayerTrinkets

local M = {}

-- Personagens com inventario SEPARADO por corpo/forma. Copia propria: o drop engine do
-- EDL nao e dependencia deste mod.
local TWIN_PLAYER_TYPES = {}
for _, name in ipairs({
    "PLAYER_JACOB",      -- Jacob (de Jacob & Esau)
    "PLAYER_ESAU",       -- Esau
    "PLAYER_LAZARUS_B",  -- Tainted Lazarus (forma viva)
    "PLAYER_LAZARUS2_B", -- Tainted Lazarus (forma morta)
}) do
    local v = PlayerType[name]
    if v ~= nil then TWIN_PLAYER_TYPES[v] = true end
end

-- Pool de trinkets pra Tainted Eden (tudo exceto Perfection e Tick)
local EDEN_B_POOL = {}
for i = 1, 189 do
    if i ~= 145 and i ~= 53 then  -- Perfection, Tick (nao removivel)
        table.insert(EDEN_B_POOL, i)
    end
end

-- 5 trinkets por personagem pro player escolher. Conferidas contra o enums.lua.
-- Jacob/Esau e T.Lazarus vivo/morto tem entradas separadas (2 fileiras, 10 trinkets).
-- T.Eden nao entra aqui: recebe 5 aleatorias da EDEN_B_POOL, rerolladas a cada hit.
local CHAR_TRINKET_CHOICE_MAP = {
    -- ── NORMAIS ──────────────────────────────────────────────────────────────
    [PlayerType.PLAYER_ISAAC]          = { TrinketType.TRINKET_OLD_CAPACITOR,     TrinketType.TRINKET_CHARGED_PENNY,    TrinketType.TRINKET_AAA_BATTERY,        TrinketType.TRINKET_GOLDEN_HORSE_SHOE,  TrinketType.TRINKET_WATCH_BATTERY },
    [PlayerType.PLAYER_MAGDALENE]      = { TrinketType.TRINKET_JUDAS_TONGUE,      TrinketType.TRINKET_MISSING_POSTER,   TrinketType.TRINKET_STEM_CELL,          TrinketType.TRINKET_MAGGYS_FAITH,       TrinketType.TRINKET_GOAT_HOOF },
    [PlayerType.PLAYER_CAIN]           = { TrinketType.TRINKET_LUCKY_TOE,         TrinketType.TRINKET_STORE_KEY,        TrinketType.TRINKET_KARMA,              TrinketType.TRINKET_MOTHERS_KISS,       TrinketType.TRINKET_SAFETY_CAP },
    [PlayerType.PLAYER_JUDAS]          = { TrinketType.TRINKET_YOUR_SOUL,         TrinketType.TRINKET_MOTHERS_KISS,     TrinketType.TRINKET_SIGIL_OF_BAPHOMET,  TrinketType.TRINKET_NO,                 TrinketType.TRINKET_BLIND_RAGE },
    [PlayerType.PLAYER_BLUEBABY]       = { TrinketType.TRINKET_SIGIL_OF_BAPHOMET, TrinketType.TRINKET_DAEMONS_TAIL,     TrinketType.TRINKET_BLESSED_PENNY,      TrinketType.TRINKET_MOMS_PEARL,         TrinketType.TRINKET_CURVED_HORN },
    [PlayerType.PLAYER_EVE]            = { TrinketType.TRINKET_BLACK_LIPSTICK,    TrinketType.TRINKET_SWALLOWED_PENNY,  TrinketType.TRINKET_CURVED_HORN,        TrinketType.TRINKET_BLESSED_PENNY,      TrinketType.TRINKET_BLACK_FEATHER },
    [PlayerType.PLAYER_SAMSON]         = { TrinketType.TRINKET_RED_PATCH,         TrinketType.TRINKET_PURPLE_HEART,     TrinketType.TRINKET_TAPE_WORM,          TrinketType.TRINKET_TEMPORARY_TATTOO,   TrinketType.TRINKET_SWALLOWED_M80 },
    [PlayerType.PLAYER_AZAZEL]         = { TrinketType.TRINKET_DAEMONS_TAIL,      TrinketType.TRINKET_TAPE_WORM,        TrinketType.TRINKET_BRAIN_WORM,         TrinketType.TRINKET_CURVED_HORN,        TrinketType.TRINKET_CHEWED_PEN },
    [PlayerType.PLAYER_LAZARUS]        = { TrinketType.TRINKET_LOST_CORK,         TrinketType.TRINKET_BLESSED_PENNY,    TrinketType.TRINKET_SWALLOWED_PENNY,    TrinketType.TRINKET_YOUR_SOUL,          TrinketType.TRINKET_DAEMONS_TAIL },
    [PlayerType.PLAYER_EDEN]           = { TrinketType.TRINKET_CURVED_HORN,       TrinketType.TRINKET_GOAT_HOOF,        TrinketType.TRINKET_CANCER,             TrinketType.TRINKET_MAGGYS_FAITH,       TrinketType.TRINKET_SIGIL_OF_BAPHOMET },
    [PlayerType.PLAYER_THELOST]        = { TrinketType.TRINKET_WOODEN_CROSS,      TrinketType.TRINKET_BLIND_RAGE,       TrinketType.TRINKET_DOOR_STOP,          TrinketType.TRINKET_DEVILS_CROWN,       TrinketType.TRINKET_SIGIL_OF_BAPHOMET },
    [PlayerType.PLAYER_LILITH]         = { TrinketType.TRINKET_BABY_BENDER,       TrinketType.TRINKET_FORGOTTEN_LULLABY, TrinketType.TRINKET_FRIENDSHIP_NECKLACE, TrinketType.TRINKET_ADOPTION_PAPERS,  TrinketType.TRINKET_MOTHERS_KISS },
    [PlayerType.PLAYER_KEEPER]         = { TrinketType.TRINKET_SWALLOWED_PENNY,   TrinketType.TRINKET_MOTHERS_KISS,     TrinketType.TRINKET_STORE_KEY,          TrinketType.TRINKET_SIGIL_OF_BAPHOMET,  TrinketType.TRINKET_STORE_CREDIT },
    [PlayerType.PLAYER_APOLLYON]       = { TrinketType.TRINKET_ENDLESS_NAMELESS,  TrinketType.TRINKET_OLD_CAPACITOR,    TrinketType.TRINKET_AAA_BATTERY,        TrinketType.TRINKET_WATCH_BATTERY,      TrinketType.TRINKET_CHARGED_PENNY },
    [PlayerType.PLAYER_THEFORGOTTEN]   = { TrinketType.TRINKET_HOLLOW_HEART,      TrinketType.TRINKET_CURVED_HORN,      TrinketType.TRINKET_FINGER_BONE,        TrinketType.TRINKET_SIGIL_OF_BAPHOMET,  TrinketType.TRINKET_CANCER },
    [PlayerType.PLAYER_BETHANY]        = { TrinketType.TRINKET_HOLLOW_HEART,      TrinketType.TRINKET_BLESSED_PENNY,    TrinketType.TRINKET_ROSARY_BEAD,        TrinketType.TRINKET_BETHS_FAITH,        TrinketType.TRINKET_BETHS_ESSENCE },
    -- Jacob (fileira 1) e Esau (fileira 2): spawna 10 trinkets, escolhe 1 par
    [PlayerType.PLAYER_JACOB]          = { TrinketType.TRINKET_CANCER,            TrinketType.TRINKET_CURVED_HORN,      TrinketType.TRINKET_WICKED_CROWN,       TrinketType.TRINKET_SWALLOWED_PENNY,    TrinketType.TRINKET_BROKEN_GLASSES },
    [PlayerType.PLAYER_ESAU]           = { TrinketType.TRINKET_CURVED_HORN,       TrinketType.TRINKET_CANCER,           TrinketType.TRINKET_HOLY_CROWN,         TrinketType.TRINKET_BLESSED_PENNY,      TrinketType.TRINKET_GOLDEN_HORSE_SHOE },

    -- ── TAINTED ──────────────────────────────────────────────────────────────
    [PlayerType.PLAYER_ISAAC_B]        = { TrinketType.TRINKET_PAY_TO_WIN,        TrinketType.TRINKET_CRACKED_DICE,     TrinketType.TRINKET_KARMA,              TrinketType.TRINKET_FRAGMENTED_CARD,    TrinketType.TRINKET_BROKEN_GLASSES },
    [PlayerType.PLAYER_MAGDALENE_B]    = { TrinketType.TRINKET_MOMS_LOCKET,       TrinketType.TRINKET_CRACKED_DICE,     TrinketType.TRINKET_SWALLOWED_PENNY,    TrinketType.TRINKET_SWALLOWED_M80,      TrinketType.TRINKET_BLIND_RAGE },
    [PlayerType.PLAYER_CAIN_B]         = { TrinketType.TRINKET_GILDED_KEY,        TrinketType.TRINKET_DAEMONS_TAIL,     TrinketType.TRINKET_BLESSED_PENNY,      TrinketType.TRINKET_BUTTER,             TrinketType.TRINKET_SAFETY_SCISSORS },
    [PlayerType.PLAYER_JUDAS_B]        = { TrinketType.TRINKET_BLESSED_PENNY,     TrinketType.TRINKET_YOUR_SOUL,        TrinketType.TRINKET_BLACK_LIPSTICK,     TrinketType.TRINKET_MAGGYS_FAITH,       TrinketType.TRINKET_JUDAS_TONGUE },
    [PlayerType.PLAYER_BLUEBABY_B]     = { TrinketType.TRINKET_PETRIFIED_POOP,    TrinketType.TRINKET_BROWN_CAP,        TrinketType.TRINKET_LIL_LARVA,          TrinketType.TRINKET_LOST_CORK,          TrinketType.TRINKET_BLESSED_PENNY },
    [PlayerType.PLAYER_EVE_B]          = { TrinketType.TRINKET_LIL_CLOT,          TrinketType.TRINKET_STEM_CELL,        TrinketType.TRINKET_BABY_BENDER,        TrinketType.TRINKET_FORGOTTEN_LULLABY,  TrinketType.TRINKET_BLESSED_PENNY },
    [PlayerType.PLAYER_SAMSON_B]       = { TrinketType.TRINKET_SIGIL_OF_BAPHOMET, TrinketType.TRINKET_CRICKET_LEG,      TrinketType.TRINKET_TEMPORARY_TATTOO,   TrinketType.TRINKET_CHILDS_HEART,       TrinketType.TRINKET_BLESSED_PENNY },
    [PlayerType.PLAYER_AZAZEL_B]       = { TrinketType.TRINKET_BRAIN_WORM,        TrinketType.TRINKET_BAT_WING,         TrinketType.TRINKET_SECOND_HAND,        TrinketType.TRINKET_BLISTER,            TrinketType.TRINKET_NOSE_GOBLIN },
    -- T.Lazarus vivo (fileira 1) e morto (fileira 2): spawna 10 trinkets, escolhe 1 par
    [PlayerType.PLAYER_LAZARUS_B]      = { TrinketType.TRINKET_CANCER,            TrinketType.TRINKET_CURVED_HORN,      TrinketType.TRINKET_WICKED_CROWN,       TrinketType.TRINKET_AAA_BATTERY,        TrinketType.TRINKET_BROKEN_GLASSES },
    [PlayerType.PLAYER_LAZARUS2_B]     = { TrinketType.TRINKET_CURVED_HORN,       TrinketType.TRINKET_CANCER,           TrinketType.TRINKET_HOLY_CROWN,         TrinketType.TRINKET_WATCH_BATTERY,      TrinketType.TRINKET_GOLDEN_HORSE_SHOE },
    [PlayerType.PLAYER_THELOST_B]      = { TrinketType.TRINKET_WOODEN_CROSS,      TrinketType.TRINKET_BLIND_RAGE,       TrinketType.TRINKET_ACE_SPADES,         TrinketType.TRINKET_SIGIL_OF_BAPHOMET,  TrinketType.TRINKET_BRAIN_WORM },
    [PlayerType.PLAYER_LILITH_B]       = { TrinketType.TRINKET_BABY_BENDER,       TrinketType.TRINKET_FORGOTTEN_LULLABY, TrinketType.TRINKET_FRIENDSHIP_NECKLACE, TrinketType.TRINKET_ADOPTION_PAPERS,  TrinketType.TRINKET_GOAT_HOOF },
    [PlayerType.PLAYER_KEEPER_B]       = { TrinketType.TRINKET_MOTHERS_KISS,      TrinketType.TRINKET_COUNTERFEIT_PENNY, TrinketType.TRINKET_BROKEN_MAGNET,     TrinketType.TRINKET_STORE_CREDIT,       TrinketType.TRINKET_CANCER },
    [PlayerType.PLAYER_APOLLYON_B]     = { TrinketType.TRINKET_CRICKET_LEG,       TrinketType.TRINKET_ENDLESS_NAMELESS,  TrinketType.TRINKET_APOLLYONS_BEST_FRIEND, TrinketType.TRINKET_EXTENSION_CORD, TrinketType.TRINKET_CURVED_HORN },
    [PlayerType.PLAYER_THEFORGOTTEN_B] = { TrinketType.TRINKET_BLESSED_PENNY,     TrinketType.TRINKET_SUPER_MAGNET,     TrinketType.TRINKET_TAPE_WORM,          TrinketType.TRINKET_FRAGMENTED_CARD,    TrinketType.TRINKET_TELESCOPE_LENS },
    [PlayerType.PLAYER_BETHANY_B]      = { TrinketType.TRINKET_BLESSED_PENNY,     TrinketType.TRINKET_BLOODY_PENNY,     TrinketType.TRINKET_CHARGED_PENNY,      TrinketType.TRINKET_AAA_BATTERY,        TrinketType.TRINKET_OLD_CAPACITOR },
    [PlayerType.PLAYER_JACOB_B]        = { TrinketType.TRINKET_WOODEN_CROSS,      TrinketType.TRINKET_CURVED_HORN,      TrinketType.TRINKET_CANCER,             TrinketType.TRINKET_LIGHTER,            TrinketType.TRINKET_GOAT_HOOF },
}

-- Confere se a trinket esta desbloqueada (precisa de REPENTOGON; falha segura = desbloqueada)
local function trinketUnlocked(id)
    if not HAS_REPENTOGON then return true end
    local ok, res = pcall(function()
        local cfg = Isaac.GetItemConfig():GetTrinket(id)
        if not cfg then return false end
        local ach = cfg.AchievementID
        if not ach or ach <= 0 then return true end
        local pgd = Isaac.GetPersistentGameData()
        if not pgd then return true end
        return pgd:Unlocked(ach)
    end)
    return (not ok) or (res == true)
end

-- Confere se um collectible esta desbloqueado (precisa de REPENTOGON; falha segura = desbloqueado)
local function collectibleUnlocked(id)
    if not HAS_REPENTOGON then return true end
    local ok, res = pcall(function()
        local cfg = Isaac.GetItemConfig():GetCollectible(id)
        if not cfg then return false end
        local ach = cfg.AchievementID
        if not ach or ach <= 0 then return true end
        local pgd = Isaac.GetPersistentGameData()
        if not pgd then return true end
        return pgd:Unlocked(ach)
    end)
    return (not ok) or (res == true)
end

-- RNG semeado com a seed da run: varia entre runs mas e deterministico (corrige o "random
-- travado" do math.random cru, que o Isaac nao re-semeia de forma confiavel a cada run)
local startRNG = RNG()

local startDbgMsg, startDbgTimer = "", 0
-- fonte com contorno: le limpo sobre qualquer fundo, sem precisar de sprite de papel
local promptFont = Font()
pcall(function() promptFont:Load("font/luaminioutlined.fnt") end)
-- prompt de sucesso POR GRUPO (twins/formas = 1 por grupo): [OptionsPickupIndex] = "mensagem".
-- Fica na tela enquanto o grupo ainda tem trinket no chao.
local promptGroups = {}
local groupForm    = {}  -- [optIdx] = PlayerType que pode pegar aquele grupo (nil = qualquer). Trava twins/formas
-- pickups spawnados por grupo (fileira + penny). O poll do POST_UPDATE compara com o que
-- resta no chao: caiu (pegou 1)? varre o resto. Backup pro caso do Greed nao desespawnar
-- os outros sozinho na colisao.
local groupSpawnCount = {}
local groupRowIdx     = {}  -- [optIdx] = rowIdx usado no spawn; precisa pra reroll do T.Eden na fileira certa
local pennyPillCount = 0    -- pilulas de Gulp ainda devidas (1 por penny). Declarado aqui em cima
local pennyFromRow   = false-- (antes de spawnTrinketRow) pra a fileira poder colocar a penny do greedier
-- COOP_TRINKETS_ENABLED: valvula de seguranca. Se trinkets em co-op quebrarem, seta false aqui.
-- Quando false: players extras (i>0) nao recebem fileira, e um aviso vai pro log.
local COOP_TRINKETS_ENABLED = true

-- rotulo por player pros prompts (so quando ha mais de um player)
local function twinLabel(i, pt)
    if game:GetNumPlayers() <= 1 then return nil end
    if pt == PlayerType.PLAYER_JACOB then return "Jacob" end
    if pt == PlayerType.PLAYER_ESAU  then return "Esau"  end
    return "P" .. (i + 1)
end
local function labeledMsg(label, greedierChoice)
    local base = greedierChoice and "Money or Comfort  -  choose one!" or "Choose your trinket!  (grab 1)"
    return label and (label .. ":  " .. base) or base
end

local TRINKET_ROW_SPACING = 45  -- px entre trinkets DA MESMA fileira (horizontal)
local TRINKET_ROW_GAP     = 78  -- px entre fileiras EMPILHADAS (twins/formas); 45 colava demais
local COIN_PENNY = (CoinSubType and CoinSubType.COIN_PENNY) or 1  -- moeda de consolacao pra trinket travada
local COIN_DIME  = (CoinSubType and CoinSubType.COIN_DIME)  or 3  -- consolacao pra Counterfeit Penny travada (greed)

-- A arena do Greed/Greedier PRECA pickup spawnado perto da loja: vira item de loja (nao da
-- pra pegar sem moeda, nao desespawna via OptionsPickupIndex, bloqueia a passagem). Forca
-- gratis. setAUP=true so no greed: AutoUpdatePrice=false impede a loja de reprecificar. Em
-- sala normal NAO seta, o motor precisa disso pro OptionsPickupIndex nativo funcionar.
local function freePickup(pk, setAUP)
    if not pk then return end
    pcall(function() pk.Price = 0; if setAUP then pk.AutoUpdatePrice = false end end)
end

-- Spawna 1 fileira de ate 5 trinkets curadas pro grupo `optIdx`, no Y empilhado por
-- `rowIndex` (pra twins/formas nao se sobreporem). `label` vai no prompt. Retorna quantos
-- pickups foram spawnados.
local function spawnTrinketRow(anchorPos, listPt, optIdx, rowIndex, label, requireForm)
    local list = (listPt == PlayerType.PLAYER_EDEN_B) and EDEN_B_POOL or CHAR_TRINKET_CHOICE_MAP[listPt]
    if not list then return 0 end
    -- monta 5 slots: chars curados = as 5 fixas; T.Eden (~187 no pool) = sorteia 5
    local slots = {}
    if #list > 5 then
        local pool = {}
        for _, tid in ipairs(list) do pool[#pool + 1] = tid end
        for _ = 1, 5 do slots[#slots + 1] = table.remove(pool, startRNG:RandomInt(#pool) + 1) end
    else
        for _, tid in ipairs(list) do slots[#slots + 1] = tid end
    end
    local n = #slots
    if n == 0 then return 0 end
    -- greedier (greed + Difficulty 3): a Counterfeit Penny entra como o ULTIMO slot da
    -- fileira (mesmo grupo/trava/posicao) = "Money or Comfort" POR forma/corpo. Assim
    -- T.Lazarus vivo E morto, e cada twin, ganham a propria penny alinhada com a fileira.
    local greed         = game:IsGreedMode()
    local greedierPenny = greed and game.Difficulty == 3 and CFG.EASY_GREED_ENABLED
    local pennyUnlocked = greedierPenny and trinketUnlocked(TrinketType.TRINKET_COUNTERFEIT_PENNY)
    -- normal: fileira ACIMA do player (sala vazia). greed: a loja fica ACIMA, entao empilha PRA BAIXO.
    local vy = greed and (50 + rowIndex * TRINKET_ROW_GAP) or (-55 - rowIndex * TRINKET_ROW_GAP)
    local function slotPos(k)
        local px
        if greedierPenny and k == n + 1 then
            -- penny: a direita das n trinkets CENTRADAS, com 1.5x de gap (separacao visual)
            local rightmostTrinketX = ((n - 1) / 2) * TRINKET_ROW_SPACING
            px = rightmostTrinketX + TRINKET_ROW_SPACING * 1.5
        else
            -- trinkets centradas em n (nao n+1): sem deslocar pro lado por causa da penny
            px = (k - (n + 1) / 2) * TRINKET_ROW_SPACING
        end
        local p = anchorPos + Vector(px, vy)
        if greed then pcall(function() p = Isaac.GetFreeNearPosition(p, 24) end) end
        return p
    end
    local spawned = 0
    for k, tid in ipairs(slots) do
        local pos = slotPos(k)
        if trinketUnlocked(tid) then
            local ent = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, tid, pos, Vector(0, 0), nil)
            local pk  = ent and ent:ToPickup()
            if pk then
                spawned = spawned + 1
                pcall(function() pk.OptionsPickupIndex = optIdx end)
                -- marca robusta: a arena do greed reseta OptionsPickupIndex (repreco) mas GetData() persiste
                pcall(function() ent:GetData().qolGroup = optIdx end)
                freePickup(pk, greed)
                Isaac.DebugString("QOL [row " .. optIdx .. "] slot " .. k .. " tid=" .. tid .. " SPAWNED")
            end
        else
            -- travada: moeda de consolacao SEM OptionsPickupIndex (bonus livre, fora do "escolha 1").
            -- NAO conta em `spawned`: a moeda nao tem qolGroup, entao nunca entra no floor do poll.
            local ent = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COIN, COIN_PENNY, pos, Vector(0, 0), nil)
            freePickup(ent and ent:ToPickup(), greed)
            Isaac.DebugString("QOL [row " .. optIdx .. "] slot " .. k .. " tid=" .. tid .. " LOCKED->coin")
        end
    end
    -- penny do greedier: ultimo slot da fileira, MESMO grupo/trava (money vs comfort deste corpo)
    if greedierPenny then
        local pos = slotPos(n + 1)
        if pennyUnlocked then
            local ent = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, TrinketType.TRINKET_COUNTERFEIT_PENNY, pos, Vector(0, 0), nil)
            local pk  = ent and ent:ToPickup()
            if pk then
                spawned = spawned + 1
                pcall(function() pk.OptionsPickupIndex = optIdx end)
                pcall(function() ent:GetData().qolGroup = optIdx end)
                freePickup(pk, true)  -- greedier: sempre o freePickup completo
            end
            pennyPillCount = pennyPillCount + 1  -- 1 pilula de Gulp por penny (T.Lazarus = 2, uma por forma)
        else
            -- penny travada pra este player: uma dime livre no lugar (bonus, fora do "escolha 1")
            local ent = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COIN, COIN_DIME, pos, Vector(0, 0), nil)
            freePickup(ent and ent:ToPickup(), true)
        end
        pennyFromRow = true  -- avisa o applyGreedPenny pra NAO soltar outra penny separada
    end
    if spawned > 0 then
        promptGroups[optIdx]    = labeledMsg(label, pennyUnlocked)  -- penny na fileira vira "Money or Comfort"
        groupForm[optIdx]       = requireForm  -- nil = qualquer um pega; senao trava naquela forma/corpo
        groupSpawnCount[optIdx] = spawned      -- pro poll do POST_UPDATE perceber quando uma foi pega
    end
    return spawned
end

local chosenGroups   = {}     -- [OptionsPickupIndex]=true quando aquele player ja escolheu (twins: 1 cada)
local flipQueued     = false  -- T.Lazarus: pede um Flip no proximo frame (vivo<->morto entre as escolhas)
local leftStartRoom  = false  -- true depois de sair da sala inicial; bloqueia reroll do T.Eden, varre ao voltar

-- Aplica o loadout inicial (frame>4, one-shot por run): em vez de escolher 1 num menu,
-- OFERECE as trinkets curadas numa FILEIRA no chao acima do player - anda ate a que quer
-- e pega. Pegar UMA faz as outras somarem, mecanica nativa do "More Options" via
-- OptionsPickupIndex. Twins (Jacob & Esau) = 2 players, entao 2 fileiras (grupos 100/101).
-- T.Lazarus = 1 player com 2 FORMAS (vivo/morto, inventarios separados), tambem 2 fileiras
-- (100/200): uma escolha por forma (Flip pra chegar na segunda). Engole a trinket inata
-- primeiro se esse toggle estiver ligado.
local function applyStartingLoadout()
    pcall(function() startRNG:SetSeed(game:GetSeeds():GetStartSeed(), S.SHIFT_LOADOUT) end)
    if not CFG.CHAR_TRINKET_CHOICE_ENABLED then
        -- feature off: so o gulp da inata se aplica (se esse toggle estiver ligado)
        if CFG.TRINKET_SMELT_INNATE then pcall(function() smeltPlayerTrinkets(Isaac.GetPlayer(0)) end) end
        return
    end
    local dbg = "QOL: sem trinket pra oferecer"
    local ok, err = pcall(function()
        local greedMode = game:IsGreedMode()
        local centerAnchor = nil
        pcall(function() if greedMode then centerAnchor = game:GetRoom():GetCenterPos() end end)
        local total  = 0
        local rowIdx = 0  -- contador unico de fileira (mesmo comportamento em normal e greed)
        groupRowIdx  = {}
        for i = 0, game:GetNumPlayers() - 1 do
            -- COOP_TRINKETS_ENABLED=false: pula players extras e avisa no log
            if i > 0 and not COOP_TRINKETS_ENABLED then
                Isaac.DebugString("QOL: COOP_TRINKETS_ENABLED=false -> pulando player " .. i)
                goto continue_player
            end
            do
            local player = Isaac.GetPlayer(i)
            local pt     = player:GetPlayerType()
            if CFG.TRINKET_SMELT_INNATE then smeltPlayerTrinkets(player) end
            if pt == PlayerType.PLAYER_LAZARUS_B or pt == PlayerType.PLAYER_LAZARUS2_B then
                -- T.Lazarus: 1 entidade, 2 formas. Um rowIdx unificado evita fileiras de co-op
                -- se sobrepondo.
                local lzAnchor = greedMode and centerAnchor or player.Position
                local n1 = spawnTrinketRow(lzAnchor, PlayerType.PLAYER_LAZARUS_B,  100 + i, rowIdx,     "Alive", PlayerType.PLAYER_LAZARUS_B)
                groupRowIdx[100 + i] = rowIdx
                local n2 = spawnTrinketRow(lzAnchor, PlayerType.PLAYER_LAZARUS2_B, 200 + i, rowIdx + 1, "Dead",  PlayerType.PLAYER_LAZARUS2_B)
                groupRowIdx[200 + i] = rowIdx + 1
                total  = total + n1 + n2
                rowIdx = rowIdx + 2
            else
                -- J&E: ancora em Jacob (player 0) pra fileiras alinharem verticalmente. Co-op
                -- normal: cada player usa a PROPRIA posicao (nao empilha tudo em player 0).
                local isTwinPt = TWIN_PLAYER_TYPES[pt] ~= nil
                local anchor   = greedMode and centerAnchor
                                 or (isTwinPt and Isaac.GetPlayer(0).Position or player.Position)
                local req      = (game:GetNumPlayers() > 1) and pt or nil
                local n = spawnTrinketRow(anchor, pt, 100 + i, rowIdx, twinLabel(i, pt), req)
                groupRowIdx[100 + i] = rowIdx
                total  = total + n
                rowIdx = rowIdx + 1
            end
            end
            ::continue_player::
        end
        if total > 0 then dbg = "Choose your trinket!" end
    end)
    if not ok then dbg = "QOL ERRO: " .. tostring(err); promptGroups = {} end
    startDbgMsg = dbg
    -- o timer e so pro caminho de erro/diagnostico; sucesso e mostrado via promptGroups
    startDbgTimer = (dbg:sub(1, 3) == "QOL") and 900 or 0
    Isaac.DebugString(startDbgMsg)
end

-- Counterfeit Penny do Greed NORMAL (bonus livre): no Greedier a penny ja vem DENTRO da
-- fileira (spawnTrinketRow, "Money or Comfort" por forma/corpo), entao aqui pula. Fallback:
-- greedier SEM fileira (trinket choice off / personagem sem mapa) tambem cai aqui e ganha a
-- penny solta. A pilula de Gulp e dada ao pegar (PRE_PICKUP_COLLISION abaixo).
local function applyGreedPenny()
    if not game:IsGreedMode() or not CFG.EASY_GREED_ENABLED then return end
    local greedier = (game.Difficulty == 3)
    if greedier and pennyFromRow then return end  -- a fileira ja colocou a penny no "escolha 1"
    pcall(function()
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            local pos = Isaac.GetFreeNearPosition(player.Position, 40)
            if trinketUnlocked(TrinketType.TRINKET_COUNTERFEIT_PENNY) then
                local ent = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET,
                    TrinketType.TRINKET_COUNTERFEIT_PENNY, pos, Vector(0, 0), nil)
                freePickup(ent and ent:ToPickup(), true)  -- greed: AutoUpdatePrice=false e obrigatorio
                pennyPillCount = pennyPillCount + 1
            else
                -- penny travada pra este player: deixa uma dime no lugar (bonus livre, sem escolha)
                local ent = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COIN, COIN_DIME, pos, Vector(0, 0), nil)
                freePickup(ent and ent:ToPickup(), true)
            end
        end
    end)
end

-- Half Price Shop: da Steam Sale (loja com metade do preco) no inicio da run.
-- Portado do "Easier Greed Mode" (Noxteryn). Dois bugs corrigidos no port:
--   1. o original dava Steam Sale em TODO MC_POST_PLAYER_INIT sem checar o modo - aqui e
--      opt-in por modo: HALF_PRICE_SHOP cobre Greed/Greedier, HALF_PRICE_SHOP_NORMAL cobre
--      Normal/Hard, cada um com seu proprio toggle;
--   2. so tocava no player 0 e nunca checava se o item ja estava com ele, entao um
--      Continue empilhava outra copia. Aqui todo player e coberto e o HasCollectible protege.
local function applyHalfPriceShop()
    local greed = game:IsGreedMode()
    local enabled = greed and CFG.HALF_PRICE_SHOP or (not greed and CFG.HALF_PRICE_SHOP_NORMAL)
    if not enabled then return end
    pcall(function()
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            if not player:HasCollectible(CollectibleType.COLLECTIBLE_STEAM_SALE) then
                player:AddCollectible(CollectibleType.COLLECTIBLE_STEAM_SALE, 0, false)
            end
        end
    end)
end

-- Bonus fixo por personagem, sem escolha (ao contrario da fileira de trinket normal, que ja
-- cobre trinket por personagem). Cobre os 34 personagens do jogo (17 normais + 17 tainted;
-- Jacob/Esau e T.Lazarus vivo/morto contam como entradas separadas, mesmo esquema do
-- CHAR_TRINKET_CHOICE_MAP acima). So ITEM aqui. Birthright NAO entra: ja faz parte do
-- seletor Starting Blessing (STARTING_BLESSING_LIST acima), que cobre Blue Baby e Judas sem
-- duplicar. `isActive=true` spawna FISICO no chao (mesmo motivo do Damocles na blessing:
-- AddCollectible em ativo substituiria o ativo nativo do personagem).
-- Curadoria por sinergia de kit. IDs conferidos no resources/scripts/enums.lua nativo.
-- Vazio de propósito.
-- 0 = CollectibleType.COLLECTIBLE_NULL, applyStartingItemBonus ignora entrada nesse estado.
-- Pra dar um ativo (nao um passivo), so adicionar "isActive = true" na entry.
-- Eden e T.Eden ficam DE FORA do mapa (nao adicionar): item inicial forcado pode
-- conflitar com o proprio item/stats aleatorios que os dois ja ganham nativamente.
local CHAR_STARTING_ITEM_MAP = {
    -- ── NORMAIS ──────────────────────────────────────────────────────────────
    [PlayerType.PLAYER_ISAAC]          = { collectible = CollectibleType.COLLECTIBLE_MORE_OPTIONS },
    [PlayerType.PLAYER_MAGDALENE]      = { collectible = CollectibleType.COLLECTIBLE_WAFER },
    [PlayerType.PLAYER_CAIN]           = { collectible = CollectibleType.COLLECTIBLE_LITTLE_BAGGY },
    [PlayerType.PLAYER_JUDAS]          = { collectible = CollectibleType.COLLECTIBLE_STIGMATA },
    [PlayerType.PLAYER_BLUEBABY]       = { collectible = CollectibleType.COLLECTIBLE_SOUL_LOCKET },
    [PlayerType.PLAYER_EVE]            = { collectible = CollectibleType.COLLECTIBLE_GIMPY },
    [PlayerType.PLAYER_SAMSON]         = { collectible = CollectibleType.COLLECTIBLE_BLOODY_LUST },
    [PlayerType.PLAYER_AZAZEL]         = { collectible = CollectibleType.COLLECTIBLE_WOODEN_SPOON },
    [PlayerType.PLAYER_LAZARUS]        = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_THELOST]        = { collectible = CollectibleType.COLLECTIBLE_SACRED_ORB },
    [PlayerType.PLAYER_LILITH]         = { collectible = CollectibleType.COLLECTIBLE_IMMACULATE_CONCEPTION },
    [PlayerType.PLAYER_KEEPER]         = { collectible = CollectibleType.COLLECTIBLE_GREEDS_GULLET },
    [PlayerType.PLAYER_APOLLYON]       = { collectible = CollectibleType.COLLECTIBLE_BATTERY },
    [PlayerType.PLAYER_THEFORGOTTEN]   = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_BETHANY]        = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_JACOB]          = { collectible = CollectibleType.COLLECTIBLE_MORE_OPTIONS },
    [PlayerType.PLAYER_ESAU]           = { collectible = CollectibleType.COLLECTIBLE_OPTIONS },

    -- ── TAINTED ──────────────────────────────────────────────────────────────
    [PlayerType.PLAYER_ISAAC_B]        = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_MAGDALENE_B]    = { collectible = CollectibleType.COLLECTIBLE_CANDY_HEART },
    [PlayerType.PLAYER_CAIN_B]         = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_JUDAS_B]        = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_BLUEBABY_B]     = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_EVE_B]          = { collectible = CollectibleType.COLLECTIBLE_ATHAME },
    [PlayerType.PLAYER_SAMSON_B]       = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_AZAZEL_B]       = { collectible = CollectibleType.COLLECTIBLE_SULFUR },
    [PlayerType.PLAYER_LAZARUS_B]      = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_LAZARUS2_B]     = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_THELOST_B]      = { collectible = CollectibleType.COLLECTIBLE_DAMOCLES, isActive = true },
    [PlayerType.PLAYER_LILITH_B]       = { collectible = CollectibleType.COLLECTIBLE_IMMACULATE_CONCEPTION },
    [PlayerType.PLAYER_KEEPER_B]       = { collectible = CollectibleType.COLLECTIBLE_DEEP_POCKETS },
    [PlayerType.PLAYER_APOLLYON_B]     = { collectible = CollectibleType.COLLECTIBLE_BATTERY },
    [PlayerType.PLAYER_THEFORGOTTEN_B] = { collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT },
    [PlayerType.PLAYER_BETHANY_B]      = { collectible = CollectibleType.COLLECTIBLE_SOUL_LOCKET },
    [PlayerType.PLAYER_JACOB_B]        = { collectible = CollectibleType.COLLECTIBLE_BATTERY },
}

-- Spawna 1 copia fisica do item ativo no chao (mesma logica do spawnActiveBlessing acima,
-- copiada local pra nao acoplar a ordem de declaracao das duas funcoes).
local function spawnActiveStartingItem(collectible)
    local player = Isaac.GetPlayer(0)
    local pos = Isaac.GetFreeNearPosition(player.Position, 40)
    local ent = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, collectible, pos, Vector(0, 0), nil)
    freePickup(ent and ent:ToPickup(), game:IsGreedMode())
end

local function applyStartingItemBonus()
    if not CFG.STARTING_TAINTED_BONUS then return end
    pcall(function()
        for i = 0, game:GetNumPlayers() - 1 do
            -- mesma valvula de seguranca da fileira de trinket: co-op nao testado ainda
            if i > 0 and not COOP_TRINKETS_ENABLED then goto continue_player end
            do
            local player = Isaac.GetPlayer(i)
            local pt     = player:GetPlayerType()
            local entry  = CHAR_STARTING_ITEM_MAP[pt]
            if entry and entry.collectible and entry.collectible ~= 0
               and (not CFG.STARTING_ITEM_REQUIRE_UNLOCK or collectibleUnlocked(entry.collectible)) then
                -- T.Cain destroi qualquer pedestal que tocar (vira material do Bag of
                -- Crafting): fisico no chao nunca seria pego por ele, entao ativos pra ele
                -- caem pro AddCollectible direto (mesmo caminho dos passivos). Nenhuma
                -- entrada atual usa isActive pra T.Cain, mas a excecao fica pronta.
                if entry.isActive and pt ~= PlayerType.PLAYER_CAIN_B then
                    pcall(spawnActiveStartingItem, entry.collectible)
                elseif not player:HasCollectible(entry.collectible) then
                    player:AddCollectible(entry.collectible, 0, false)
                end
            end
            end
            ::continue_player::
        end
    end)
end

-- Starting Blessing: item de graca no inicio da run, pra qualquer personagem. Mesma regra
-- da trinket: so roda aqui dentro do one-shot de frame>4 (chamada la embaixo), nunca
-- ganhavel no meio da run so por trocar o setting.
--
-- UI e um seletor unico (CFG.STARTING_BLESSING), igual ao Force Pool do EDL: 0 = OFF,
-- 1..#STARTING_BLESSING_LIST = item especifico daquele indice, #STARTING_BLESSING_LIST+1
-- = Random (sorteia 1 elegivel pro personagem atual, mesma ideia do Force Pool "Chaos").
--
-- Birthright (unico item com exclusao por personagem) NUNCA entra pra twin (Jacob&Esau /
-- T.Lazarus, ver TWIN_PLAYER_TYPES). Motivo (wiki oficial): em J&E o efeito e "quem pega
-- herda os 3 passivos mais recentes DO OUTRO" - pensado pra so 1 dos dois segurar o item;
-- dar copia propria pros dois ao mesmo tempo e cenario que o jogo base nunca precisou
-- suportar (mutuo-herdando um do outro, sem teste). T.Lazarus ja recebe o efeito nas duas
-- formas com 1 copia so ("ambas as formas recebem o efeito quando QUALQUER uma pega"),
-- entao a copia dupla nem faz diferenca ai - mas existe bug documentado (Birthright +
-- Judas' Shadow/Ankh nele = loop de morte).
--
-- T.Jacob tambem fica de fora do Birthright (so ele, nao afeta o Jacob normal): o efeito
-- pra ele divide o Dark Esau em DUAS copias que carregam ataque ao mesmo tempo - unico
-- caso confirmado onde Birthright piora a run em vez de ajudar (Dark Esau fica ativo por
-- praticamente a run toda, nao e so um efeito de inicio perdido).
--
-- T.Eden tambem fora: o efeito dele so protege de reroll (D4/Missing No.) os itens que ja
-- estavam com ele ANTES de pegar o Birthright - itens pegos depois continuam rerolaveis
-- normalmente. Dando Birthright no frame>4 (run start, zero itens), o efeito nasce sem
-- nada pra proteger e nunca protege nada dali pra frente - estruturalmente inutil nesse
-- timing de grant (confirmado na wiki oficial).
--
-- Damocles e um ATIVO (nao passivo): ao usar dobra os itens de pedestal, mas depois do
-- 1o hit levado a espada tem chance continua de cair e matar instantaneamente. AddCollectible
-- em ativo SUBSTITUI o ativo nativo do personagem (Judas perde o Belial, etc) - por isso
-- `isActive` marca esses pra spawnar FISICO no chao (como o Starting Pocket Item) em vez de
-- forcar no inventario: o player escolhe pegar ou nao, sem perder o proprio. Sem exclusao
-- por personagem de proposito - Murilo quer ver como ele se comporta nesse fluxo.
local STARTING_BLESSING_LIST = {
    { name = "Birthright", collectible = CollectibleType.COLLECTIBLE_BIRTHRIGHT,
      -- Eden: efeito real e' spawnar 3 itens pra escolher 1 (confirmado na wiki oficial) -
      -- gatilho de pickup natural, forcar via AddCollectible no frame>4 nao aciona a escolha,
      -- fica so com o icone sem o bonus. Mesma familia de problema do T.Eden (linha ~495).
      excluded = function(pt)
          return TWIN_PLAYER_TYPES[pt] == true or pt == PlayerType.PLAYER_JACOB2_B
              or pt == PlayerType.PLAYER_EDEN_B or pt == PlayerType.PLAYER_EDEN
      end },
    { name = "PHD",              collectible = CollectibleType.COLLECTIBLE_PHD },
    { name = "Keeper's Sack",    collectible = CollectibleType.COLLECTIBLE_KEEPERS_SACK },
    { name = "Deep Pockets",     collectible = CollectibleType.COLLECTIBLE_DEEP_POCKETS },
    { name = "Member Card",      collectible = CollectibleType.COLLECTIBLE_MEMBER_CARD },
    { name = "Restock!",         collectible = CollectibleType.COLLECTIBLE_RESTOCK },
    { name = "Humbling Bundle",  collectible = CollectibleType.COLLECTIBLE_HUMBLEING_BUNDLE },
    { name = "Sack Head",        collectible = CollectibleType.COLLECTIBLE_SACK_HEAD },
    { name = "Mom's Key",        collectible = CollectibleType.COLLECTIBLE_MOMS_KEY },
    { name = "Guppy's Tail",     collectible = CollectibleType.COLLECTIBLE_GUPPYS_TAIL },
    { name = "Options?",         collectible = CollectibleType.COLLECTIBLE_OPTIONS },
    { name = "There's Options",  collectible = CollectibleType.COLLECTIBLE_THERES_OPTIONS },
    { name = "More Options",     collectible = CollectibleType.COLLECTIBLE_MORE_OPTIONS },
    { name = "Starter Deck",     collectible = CollectibleType.COLLECTIBLE_STARTER_DECK },
    { name = "Chaos",            collectible = CollectibleType.COLLECTIBLE_CHAOS },
    { name = "Glitched Crown",   collectible = CollectibleType.COLLECTIBLE_GLITCHED_CROWN },
    { name = "Echo Chamber",     collectible = CollectibleType.COLLECTIBLE_ECHO_CHAMBER },
    { name = "Sacred Orb",       collectible = CollectibleType.COLLECTIBLE_SACRED_ORB },
    { name = "Damocles",         collectible = CollectibleType.COLLECTIBLE_DAMOCLES, isActive = true },
    { name = "Lucky Foot",       collectible = CollectibleType.COLLECTIBLE_LUCKY_FOOT },
    { name = "Fanny Pack",       collectible = CollectibleType.COLLECTIBLE_FANNY_PACK },
    { name = "TMTRAINER",        collectible = CollectibleType.COLLECTIBLE_TMTRAINER },
    { name = "Missing No.",      collectible = CollectibleType.COLLECTIBLE_MISSING_NO },
}

-- T.Lazarus tem inventario SEPARADO por forma (vivo/morto): o one-shot de frame>4 abaixo so
-- roda com o player na forma viva, entao a forma morta nunca ganhava nada. Rastreado aqui pra
-- reaplicar o MESMO item (sem sortear de novo) na primeira vez que a forma morta aparecer -
-- vale tanto pro Flip natural (levar dano fatal) quanto pro Flip artificial que a fileira de
-- trinket ja dispara (linha ~637): e so mais um consumidor do mesmo evento de Flip, sem
-- interferir no fluxo dela (nao mexe em flipQueued/chosenGroups/groupForm).
local blessingCollectible   = nil  -- item escolhido nesta run (nil = OFF/excluido/nada a propagar)
local blessingGrantedForms  = {}   -- [PlayerType] = true, uma vez por forma

-- Spawna 1 copia fisica no chao perto do player 0 (mesmo padrao do Starting Pocket Item:
-- Isaac.GetFreeNearPosition + Isaac.Spawn + freePickup). Pra T.Lazarus spawna 2 (uma por
-- forma, vivo/morto) - GetFreeNearPosition ja separa a 2a copia da 1a automaticamente.
local function spawnActiveBlessing(collectible, isLazarus)
    local player = Isaac.GetPlayer(0)
    local copies = isLazarus and 2 or 1
    for _ = 1, copies do
        local pos = Isaac.GetFreeNearPosition(player.Position, 40)
        local ent = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, collectible, pos, Vector(0, 0), nil)
        freePickup(ent and ent:ToPickup(), game:IsGreedMode())
    end
end

local function applyStartingBlessings()
    local sel = CFG.STARTING_BLESSING
    if not sel or sel == 0 then return end
    local pt = Isaac.GetPlayer(0):GetPlayerType()
    local chosen
    if sel == #STARTING_BLESSING_LIST + 1 then
        -- Random: sorteia 1 elegivel pro personagem atual (generaliza o antigo pool Birthright/PHD)
        local pool = {}
        for _, entry in ipairs(STARTING_BLESSING_LIST) do
            if not (entry.excluded and entry.excluded(pt)) then pool[#pool + 1] = entry end
        end
        if #pool == 0 then return end
        chosen = pool[startRNG:RandomInt(#pool) + 1]
    else
        local entry = STARTING_BLESSING_LIST[sel]
        if not entry then return end
        if entry.excluded and entry.excluded(pt) then return end  -- excluido pro personagem: nada essa run, de proposito
        chosen = entry
    end
    -- T.Cain destroi QUALQUER pedestal que tocar (vira material do Bag of Crafting, so
    -- quest-item escapa) - fisico no chao nunca seria pego por ele, entao cai pro
    -- AddCollectible direto (mesmo caminho dos passivos) em vez de desperdicar o item.
    if chosen.isActive and pt ~= PlayerType.PLAYER_CAIN_B then
        -- fisico no chao: nao substitui o ativo nativo, e ja cobre as 2 formas do T.Lazarus
        -- de uma vez (sem precisar do flip-hook abaixo, que e so pros passivos AddCollectible).
        local isLazarus = pt == PlayerType.PLAYER_LAZARUS_B or pt == PlayerType.PLAYER_LAZARUS2_B
        pcall(spawnActiveBlessing, chosen.collectible, isLazarus)
        return
    end
    local collectible = chosen.collectible
    blessingCollectible = collectible
    blessingGrantedForms[pt] = true
    pcall(function()
        for i = 0, game:GetNumPlayers() - 1 do
            -- mesma valvula de seguranca da fileira de trinket: co-op nao testado ainda
            if i > 0 and not COOP_TRINKETS_ENABLED then goto continue_player end
            do
            local player = Isaac.GetPlayer(i)
            if not player:HasCollectible(collectible) then
                player:AddCollectible(collectible, 0, false)
            end
            end
            ::continue_player::
        end
    end)
end

-- Propaga o mesmo blessingCollectible pra forma do T.Lazarus que ainda nao ganhou, assim
-- que ela aparecer (qualquer Flip, natural ou da fileira de trinket). Nao mexe no player 1+
-- (T.Lazarus nao e twin de 2 indices, so 1 player com 2 formas).
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not blessingCollectible then return end
    local player = Isaac.GetPlayer(0)
    local pt = player:GetPlayerType()
    if pt ~= PlayerType.PLAYER_LAZARUS_B and pt ~= PlayerType.PLAYER_LAZARUS2_B then return end
    if blessingGrantedForms[pt] then return end
    blessingGrantedForms[pt] = true
    pcall(function()
        if not player:HasCollectible(blessingCollectible) then
            player:AddCollectible(blessingCollectible, 0, false)
        end
    end)
end)

-- Starting Pocket Item: bonus estilo T.Eden (item extra aleatorio), mas pra QUALQUER
-- personagem e spawnado FISICO no chao em vez de forcado direto no inventario -
-- POCKET_ACTIVE_CONVERT ja mostrou (NO_POCKET, Flip do T.Lazarus, ativos "intransferiveis")
-- que empurrar pro pocket via codigo quebra em varios casos. Deixar o motor decidir o slot
-- ao pegar do chao evita repetir o problema. So faz sentido com o slot primario ja livre,
-- entao depende de POCKET_ACTIVE_CONVERT ligado. Pool PLACEHOLDER pequena - Murilo expande
-- depois, mesma regra de ouro do CHAR_TRINKET_CHOICE_MAP (IDs conferidos no enums.lua nativo).
-- So player 0 (co-op nao coberto, feature nova/nao testada).
local STARTING_POCKET_POOL = {
    CollectibleType.COLLECTIBLE_MOMS_BOTTLE_OF_PILLS,
    CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL,
    CollectibleType.COLLECTIBLE_MONSTROS_TOOTH,
}

local function applyStartingPocketItem()
    if not CFG.STARTING_POCKET_ITEM or not CFG.POCKET_ACTIVE_CONVERT then return end
    pcall(function()
        local player = Isaac.GetPlayer(0)
        local pick = STARTING_POCKET_POOL[startRNG:RandomInt(#STARTING_POCKET_POOL) + 1]
        local pos  = Isaac.GetFreeNearPosition(player.Position, 40)
        local ent  = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, pick, pos, Vector(0, 0), nil)
        freePickup(ent and ent:ToPickup(), game:IsGreedMode())
    end)
end

-- ── Active -> Pocket Active + o loadout inicial, os dois one-shot por run ──────
mod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, function()
    if game:GetFrameCount() <= 1 then return end  -- frame 0/1 e cedo demais pra mexer no inventario
    -- pocket-active e uma feature SEPARADA (nao e starting trinket), aplicada no frame>1
    -- onde cola. One-shot POR RUN e persistente (mesmo esquema do appliedRunCount):
    -- runCount ~= pocketAppliedRunCount impede reaplicar ao fechar/reabrir o jogo e dar
    -- Continue. IMPORTANTE: a run e marcada "decidida" (pocketAppliedRunCount = runCount)
    -- SEMPRE aqui, nao so quando o toggle esta ligado. Marcar so dentro do
    -- `if CFG.POCKET_ACTIVE_CONVERT` fazia uma run inteira com o toggle OFF nunca marcar
    -- nada, entao ligar o toggle NO MEIO da run disparava a conversao na hora, pegando o
    -- ativo que o player tinha naquele momento em vez de esperar a proxima run.
    if S.runCount ~= S.pocketAppliedRunCount then
        S.pocketAppliedRunCount = S.runCount
        if CFG.POCKET_ACTIVE_CONVERT then
            pcall(function()
                local player = Isaac.GetPlayer(0)
                -- T.Lazarus: o ativo PRIMARIO dele E o Flip (a mecanica de trocar de forma).
                -- Mover o Flip pro slot pocket quebra a troca de forma, entao pula ele nas
                -- duas formas.
                local pt = player:GetPlayerType()
                if pt == PlayerType.PLAYER_LAZARUS_B or pt == PlayerType.PLAYER_LAZARUS2_B then return end
                -- Book of Virtues (qualquer um / T.Bethany): o motor deixa segurar JUNTO de
                -- outro ativo. Empurrado pro pocket via SetPocketActiveItem, ele so some e
                -- deixa um slot fantasma. Pulado via HasCollectible + NO_POCKET.
                -- Book of Belial (Judas): PODE ser pocketado, Judas nao e excecao da feature.
                -- O pepino e pegar Birthright DEPOIS: o Belial sobra no pocket, e o
                -- qol_charfixes.lua tira ele. Judas COM Birthright ja no frame 2 e pulado
                -- aqui (o Belial dele ja e passivo held nesse ponto).
                local NO_POCKET = {
                    [CollectibleType.COLLECTIBLE_BOOK_OF_VIRTUES] = true,
                }
                if player:HasCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_VIRTUES) then return end
                if (pt == PlayerType.PLAYER_JUDAS or pt == PlayerType.PLAYER_BLACKJUDAS or pt == PlayerType.PLAYER_JUDAS_B)
                   and player:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT) then return end
                local active = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
                if active ~= 0 and not NO_POCKET[active] and player:GetActiveItem(ActiveSlot.SLOT_POCKET) == 0 then
                    player:RemoveCollectible(active)
                    player:SetPocketActiveItem(active, ActiveSlot.SLOT_POCKET, false)
                    -- verifica: se o motor recusou o item no pocket (ativo "intransferivel"),
                    -- devolve pro slot primario em vez de deixar sumir + slot fantasma.
                    if player:GetActiveItem(ActiveSlot.SLOT_POCKET) ~= active then
                        player:AddCollectible(active, 0, true)
                    end
                end
            end)
        end
    end
    -- starting trinkets: frame>4, um gap DEPOIS do passo do pocket-active (frame 2). O
    -- caminho twin (T.Lazarus) chama UseActiveItem(SMELTER), que atropelava o slot pocket
    -- se rodasse no mesmo frame. O gap separa as duas escritas no inventario. Se colidir
    -- de novo, sobe o numero. One-shot POR RUN e persistente: appliedRunCount (salvo no
    -- disco) bloqueia reaplicar depois de fechar/reabrir + Continue. runCount so sobe em
    -- run NOVA, entao runCount==appliedRunCount significa "esta run ja recebeu o loadout".
    if game:GetFrameCount() > 4 and S.runCount ~= S.appliedRunCount then
        S.appliedRunCount = S.runCount  -- marca a run como tratada (ate em challenge, pra parar de rechecar todo frame)
        promptGroups = {}; groupForm = {}; groupSpawnCount = {}; pennyFromRow = false  -- limpa antes de repovoar
        if Isaac.GetChallenge() == 0 then  -- challenge tem loadout fixo: nao interfere
            pcall(applyStartingLoadout)
            pcall(applyGreedPenny)
            pcall(applyHalfPriceShop)
            pcall(applyStartingBlessings)
            pcall(applyStartingItemBonus)
            pcall(applyStartingPocketItem)
        end
        pcall(saveConfig)  -- escreve JA (nao so no exit): um crash antes de sair reabriria a brecha
    end
end)

-- Pegar a Counterfeit Penny que soltamos no Greed spawna uma pilula de Gulp do lado. One-shot.
-- TRAVA: so o dono do grupo ganha a pilula (J&E: Esau nao da pilula pro Jacob passar por
-- cima; T.Lazarus: vivo nao ganha a pilula da forma morta e vice-versa).
mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
    if pennyPillCount <= 0 or pickup.Variant ~= PickupVariant.PICKUP_TRINKET then return end
    if pickup.SubType ~= TrinketType.TRINKET_COUNTERFEIT_PENNY then return end
    local player = collider:ToPlayer()
    if not player then return end
    local idx = pickup:GetData().qolGroup
    if not idx and pickup.OptionsPickupIndex >= 100 then idx = pickup.OptionsPickupIndex end
    if idx then
        local req = groupForm[idx]
        if req and player:GetPlayerType() ~= req then return end  -- corpo errado: sem pilula
    end
    pennyPillCount = pennyPillCount - 1
    pcall(function()
        local gulpColor = game:GetItemPool():ForceAddPillEffect(PillEffect.PILLEFFECT_GULP)
        local pos = Isaac.GetFreeNearPosition(player.Position, 40)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_PILL, gulpColor, pos, Vector(0, 0), nil)
    end)
end)

-- Forca o "escolha 1" POR GRUPO (cada player tem seu proprio OptionsPickupIndex) por
-- codigo, sem depender do indice sobreviver a sair/reentrar na sala. Twins escolhem 1 CADA:
-- pegar a do Jacob (idx 100) NAO remove a do Esau (101). O match do grupo usa
-- GetData().qolGroup (que persiste), com o OptionsPickupIndex nativo de fallback.
local function sweepOfferedTrinkets(optIdx, keepPtr)
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, -1)) do
        local pk = e:ToPickup()
        local mine = (e:GetData().qolGroup == optIdx) or (pk and pk.OptionsPickupIndex == optIdx)
        if pk and mine and (not keepPtr or GetPtrHash(e) ~= keepPtr) then
            e:Remove()
        end
    end
end

mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
    if pickup.Variant ~= PickupVariant.PICKUP_TRINKET then return end
    -- idx do grupo: GetData() e a fonte confiavel (o greed reseta OptionsPickupIndex); nativo e fallback
    local idx = pickup:GetData().qolGroup
    if not idx and pickup.OptionsPickupIndex >= 100 then idx = pickup.OptionsPickupIndex end
    if not idx or chosenGroups[idx] then return end
    local player = collider:ToPlayer()
    if not player then return end
    -- TRAVA por forma/corpo (mesmo truque do push do T.Cain: `return true` cancela a coleta).
    -- A forma errada nao pega a fileira da outra (T.Lazarus vivo != morto; Jacob != Esau).
    local req = groupForm[idx]
    if req and player:GetPlayerType() ~= req then return true end
    chosenGroups[idx] = true
    groupSpawnCount[idx] = nil  -- grupo decidido: para o poll de backup de vasculhar essa entrada todo frame
    sweepOfferedTrinkets(idx, GetPtrHash(pickup))  -- pegou 1 do grupo, o resto some
    -- T.Lazarus: guia a escolha da outra forma com um Flip. Vivo escolhe e vira morto (se a
    -- fileira morta existe e ainda nao foi escolhida); morto escolhe e volta pra vivo. Flip
    -- roda no proximo frame.
    if req == PlayerType.PLAYER_LAZARUS_B and groupForm[idx + 100] and not chosenGroups[idx + 100] then
        flipQueued = true
    elseif req == PlayerType.PLAYER_LAZARUS2_B then
        flipQueued = true
    end
end)

-- Executa o Flip pedido (fora do handler de colisao, pra nao atropelar a coleta).
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not flipQueued then return end
    flipQueued = false
    pcall(function()
        Isaac.GetPlayer(0):UseActiveItem(CollectibleType.COLLECTIBLE_FLIP, UseFlag.USE_NOANIM)
    end)
end)

-- Reentrou numa sala: varre os grupos ja escolhidos (impede pegar extra ao reentrar). Se
-- saiu da sala inicial sem escolher, marca leftStartRoom. Ao voltar, varre o que sobrou (as
-- trinkets so existem na sala inicial mesmo).
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    for idx in pairs(chosenGroups) do sweepOfferedTrinkets(idx, nil) end
    local isStart = false
    pcall(function()
        local lvl = game:GetLevel()
        isStart = lvl:GetCurrentRoomIndex() == lvl:GetStartingRoomIndex()
    end)
    if not isStart then
        leftStartRoom = true
    elseif leftStartRoom and next(groupSpawnCount) ~= nil then
        -- voltou a sala inicial depois de ter saido: varre o que ainda ta pendente e fecha a oferta
        for idx in pairs(groupSpawnCount) do
            if not chosenGroups[idx] then
                chosenGroups[idx] = true
                sweepOfferedTrinkets(idx, nil)
            end
        end
        groupSpawnCount = {}
        promptGroups    = {}
    end
end)

-- BACKUP pro "escolha 1": na arena do greed a colisao nativa as vezes NAO desespawna as
-- outras trinkets quando voce pega uma. Este poll conta o que resta no chao por grupo; se
-- caiu (pegou 1, mas ainda resta ao menos 1), varre o resto do grupo. A condicao
-- `0 < resta < spawnado` evita disparar quando voce SAI da sala (ai resta=0). So roda
-- enquanto ha grupo pendente. Complementa o handler de colisao, nao o substitui.
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if next(groupSpawnCount) == nil then return end
    local floor = {}
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, -1)) do
        local g = e:GetData().qolGroup
        if not g then local pk = e:ToPickup(); if pk and pk.OptionsPickupIndex >= 100 then g = pk.OptionsPickupIndex end end
        if g then floor[g] = (floor[g] or 0) + 1 end
    end
    for idx, spawned in pairs(groupSpawnCount) do
        local resta = floor[idx] or 0
        if not chosenGroups[idx] and resta > 0 and resta < spawned then
            chosenGroups[idx] = true
            Isaac.DebugString("QOL [poll] group " .. idx .. " picked (floor=" .. resta .. " < spawned=" .. spawned .. ") -> sweep")
            sweepOfferedTrinkets(idx, nil)
        end
    end
end)

-- T.Eden: rerolla a fileira de trinkets a cada hit (espelha a identidade do T.Eden). So
-- enquanto ainda esta na sala inicial E a fileira nao foi escolhida ainda.
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity)
    if leftStartRoom then return end
    if next(groupSpawnCount) == nil then return end
    local player = entity:ToPlayer()
    if not player then return end
    if player:GetPlayerType() ~= PlayerType.PLAYER_EDEN_B then return end
    -- descobre o optIdx do T.Eden (100 + indice do player)
    local edenIdx = nil
    for i = 0, game:GetNumPlayers() - 1 do
        if Isaac.GetPlayer(i):GetPlayerType() == PlayerType.PLAYER_EDEN_B then
            edenIdx = 100 + i; break
        end
    end
    if not edenIdx or chosenGroups[edenIdx] then return end
    -- varre a fileira atual SEM marcar como escolhida (o player ainda vai escolher da nova)
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, -1)) do
        local pk = e:ToPickup()
        local g  = e:GetData().qolGroup
        if not g and pk and pk.OptionsPickupIndex >= 100 then g = pk.OptionsPickupIndex end
        if g == edenIdx then e:Remove() end
    end
    groupSpawnCount[edenIdx] = nil
    promptGroups[edenIdx]    = nil
    -- a penny da fileira anterior foi varrida; desfaz o contador antes de respawnar (o Greedier soma +1 de novo)
    if game:IsGreedMode() and pennyPillCount > 0 then pennyPillCount = pennyPillCount - 1 end
    -- respawna com o startRNG no estado atual, pra as trinkets mudarem a cada hit
    pcall(function()
        local ri     = groupRowIdx[edenIdx] or 0
        local anchor = game:IsGreedMode() and game:GetRoom():GetCenterPos() or player.Position
        local req    = (game:GetNumPlayers() > 1) and PlayerType.PLAYER_EDEN_B or nil
        local n = spawnTrinketRow(anchor, PlayerType.PLAYER_EDEN_B, edenIdx, ri, twinLabel(edenIdx - 100, PlayerType.PLAYER_EDEN_B), req)
        Isaac.DebugString("QOL T.Eden reroll idx=" .. edenIdx .. " n=" .. n)
    end)
end, EntityType.ENTITY_PLAYER)

-- ── Renderizacao do prompt ("Choose your trinket!") ───────────────────────────
local PROMPT_SCALE = 1.5
local function drawLine(msg, line, alpha)
    local baseY = Isaac.GetScreenHeight() - 70 - line * 26
    if promptFont:IsLoaded() then
        local w = promptFont:GetStringWidthUTF8(msg) * PROMPT_SCALE
        promptFont:DrawStringScaledUTF8(msg, (Isaac.GetScreenWidth() - w) / 2, baseY, PROMPT_SCALE, PROMPT_SCALE, KColor(1, 0.9, 0.35, alpha), 0, false)
    else
        Isaac.RenderText(msg, 50, 380 - line * 16, 1, 1, 0, 1)  -- fallback se a fonte falhar ao carregar
    end
end

mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if next(promptGroups) ~= nil then
        -- quais grupos ainda tem trinket no chao. O scan so roda enquanto ha prompt na tela
        -- (sala inicial), entao custa mais ou menos uma passada pelas trinkets da sala.
        local live = {}
        for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, -1)) do
            local pk = e:ToPickup()
            local g = e:GetData().qolGroup or (pk and pk.OptionsPickupIndex >= 100 and pk.OptionsPickupIndex)
            if g then live[g] = true end
        end
        -- ordena as chaves de grupo pra ordem estavel (100,101 twins / 100,200 T.Lazarus)
        local idxs = {}
        for optIdx in pairs(promptGroups) do idxs[#idxs + 1] = optIdx end
        table.sort(idxs)
        local line = 0
        for _, optIdx in ipairs(idxs) do
            if live[optIdx] then drawLine(promptGroups[optIdx], line, 1); line = line + 1
            else promptGroups[optIdx] = nil end  -- grupo escolhido: para de mostrar
        end
    elseif startDbgTimer > 0 then
        startDbgTimer = startDbgTimer - 1
        drawLine(startDbgMsg, 0, math.min(startDbgTimer / 45, 1))  -- caminho de erro/diagnostico
    end
end)

-- Chamado pelo main.lua no MC_POST_GAME_STARTED numa run NOVA (nao isSave).
function M.resetForNewRun()
    chosenGroups    = {}
    pennyPillCount  = 0
    pennyFromRow    = false
    flipQueued      = false
    leftStartRoom   = false
    groupRowIdx     = {}
    promptGroups    = {}
    groupForm       = {}
    groupSpawnCount = {}
    blessingCollectible  = nil
    blessingGrantedForms = {}
end

M.STARTING_BLESSING_LIST = STARTING_BLESSING_LIST

return M

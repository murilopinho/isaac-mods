--[[
qol_trinketutil.lua - ferramentas de trinket que NAO fazem parte do loadout inicial:
  * Trinket Gulp  - keybind que engole as trinkets que voce esta carregando
  * T.Cain Push   - keybind que faz Tainted Cain empurrar pickup em vez de comer
Tambem e dono dos helpers de keybind compartilhados (nome de tecla, bloqueio de rebind,
tela de captura de tecla) e do `smeltPlayerTrinkets`, que o qol_loadout.lua reusa pro
gulp da trinket inata.
]]

local S           = require("qol_state")
local Config      = require("qol_config")
local Persistence = require("qol_persistence")

local mod  = S.mod
local game = S.game
local CFG  = Config.CFG
local saveConfig = Persistence.saveConfig

local M = {}

-- T.Cain push mode persiste entre salas. Exposto em M pra o MCM poder zerar quando o
-- toggle e desligado.
M.tcainPushActive = false
local tcainPushAnnounce = 0     -- frames restantes pra manter o aviso na tela
-- exposto em M pra o MCM controlar o estado "esperando tecla" do rebind
M.tcainWaitingKey       = false -- true = esperando o player apertar a nova tecla
M.trinketGulpWaitingKey = false
M.rebindArm             = false -- ignora o 1o frame do rebind, senao captura o Enter do proprio clique
local trinketGulpAnnounce = 0

-- keycode -> nome legivel, gerado a partir do enum Keyboard (KEY_Z vira "Z")
local KEY_NAMES = {}
pcall(function()
    for name, val in pairs(Keyboard) do
        if type(val) == "number" then
            KEY_NAMES[val] = name:gsub("^KEY_", "")
        end
    end
end)
local function keyName(k) return KEY_NAMES[k] or tostring(k) end
M.keyName = keyName

-- Engole toda trinket que o player esta carregando. Usa o efeito do Smelter sem precisar dele.
function M.smeltPlayerTrinkets(player)
    local n = 0
    pcall(function()
        -- Smelter so come o slot 0. Com 2 trinkets, chama duas vezes: na segunda passada
        -- o slot 1 ja deslizou pro slot 0.
        for _ = 0, 1 do
            if player:GetTrinket(0) ~= 0 then
                player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER,
                    UseFlag.USE_NOANIM | UseFlag.USE_NOCOSTUME)
                n = n + 1
            end
        end
    end)
    return n  -- quantas foram comidas; o keybind so avisa quando > 0
end

-- Teclas bloqueadas pro rebind: menu + movimento (WASD) + tiro (setas). Sem isso dava pra
-- ligar o gulp numa SETA e ela disparava toda vez que voce atirava pra esse lado.
local KEY_BLOCKED = {}
for _, k in ipairs({
    Keyboard.KEY_ESCAPE, Keyboard.KEY_P, Keyboard.KEY_L,
    Keyboard.KEY_TAB, Keyboard.KEY_E, Keyboard.KEY_Q, Keyboard.KEY_SPACE,
    Keyboard.KEY_W, Keyboard.KEY_A, Keyboard.KEY_S, Keyboard.KEY_D,
    Keyboard.KEY_UP, Keyboard.KEY_DOWN, Keyboard.KEY_LEFT, Keyboard.KEY_RIGHT,
}) do KEY_BLOCKED[k] = true end

-- ── T.Cain push mode: ligado/desligado por um keybind configuravel ─────────────
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not CFG.TCAIN_PUSH_ENABLED then return end
    local ok, pt = pcall(function() return Isaac.GetPlayer(0):GetPlayerType() end)
    if not ok or pt ~= PlayerType.PLAYER_CAIN_B then return end
    if Input.IsButtonTriggered(CFG.TCAIN_PUSH_KEY, 0) then
        M.tcainPushActive = not M.tcainPushActive
        tcainPushAnnounce = 120  -- mostra o aviso por ~2s (60fps)
    end
end)

-- empurra em vez de coletar enquanto o modo esta ativo
mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider, low)
    if not CFG.TCAIN_PUSH_ENABLED or not M.tcainPushActive then return end
    if pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then return end  -- pedestal: deixa T.Cain quebrar normal
    local player = collider:ToPlayer()
    if not player then return end
    if player:GetPlayerType() ~= PlayerType.PLAYER_CAIN_B then return end
    local dir = (pickup.Position - player.Position):Normalized()
    pickup.Velocity = dir * 8
    return true  -- cancela a coleta
end)

-- ── Trinket Gulp keybind ────────────────────────────────────────────────────
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not CFG.TRINKET_GULP_ENABLED then return end
    if Isaac.GetChallenge() ~= 0 then return end  -- challenge tem loadout fixo: nao interfere
    if not Input.IsButtonTriggered(CFG.TRINKET_GULP_KEY, 0) then return end
    -- gate por local: 1=sala inicial de cada andar, 2=so a 1a sala da run. 0=qualquer lugar.
    if CFG.TRINKET_GULP_LOCATION ~= 0 then
        local allowed = false
        pcall(function()
            local lvl = game:GetLevel()
            if game:IsGreedMode() then
                -- Greed/Greedier: a arena central (ROOM_DEFAULT) E o modo inteiro. Engolir em
                -- todo andar do Greed e forte demais, entao so o PRIMEIRO andar e liberado.
                -- O indice de sala inicial nao vale no Greed.
                allowed = (lvl:GetCurrentRoom():GetType() == RoomType.ROOM_DEFAULT)
                          and (lvl:GetStage() == ((LevelStage and LevelStage.STAGE1_1) or 1))
            elseif lvl:GetCurrentRoomIndex() == lvl:GetStartingRoomIndex() then
                allowed = (CFG.TRINKET_GULP_LOCATION ~= 2)
                          or (lvl:GetStage() == ((LevelStage and LevelStage.STAGE1_1) or 1))
            end
        end)
        if not allowed then return end
    end
    pcall(function()
        -- so avisa se realmente engoliu algo (evita um "smelted" fantasma)
        if M.smeltPlayerTrinkets(Isaac.GetPlayer(0)) > 0 then
            trinketGulpAnnounce = 90
        end
    end)
end)

-- ── POST_RENDER: tela de captura de tecla + feedback visual (roda ate no pause) ──
-- Compartilhado pelos dois rebinds: desenha o prompt, escaneia uma tecla, escreve em `cfgKey`.
-- Exposto pra outros modulos (ex: qol_machines.lua) reusarem o mesmo fluxo de rebind sem
-- duplicar a tela de captura de tecla + bloqueio de teclas de movimento/menu.
local function captureKey(label, cfgKey, onBound)
    Isaac.RenderText(label .. ": [aperte qualquer tecla | ESC cancela]", 50, 50, 1, 1, 0, 1)
    if M.rebindArm then M.rebindArm = false; return false end  -- ignora o Enter do clique no menu
    for k = 32, 350 do
        if Input.IsButtonTriggered(k, 0) then
            if k == Keyboard.KEY_ESCAPE then
                return true  -- cancelado, para de esperar
            elseif not KEY_BLOCKED[k] then
                CFG[cfgKey] = k
                if onBound then onBound() end
                saveConfig()
                return true
            end
            break
        end
    end
    return false
end

mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if M.tcainWaitingKey then
        if captureKey("Push Key", "TCAIN_PUSH_KEY", function() tcainPushAnnounce = 120 end) then
            M.tcainWaitingKey = false
        end
        return
    end
    if M.trinketGulpWaitingKey then
        if captureKey("Gulp Key", "TRINKET_GULP_KEY") then
            M.trinketGulpWaitingKey = false
        end
        return
    end
    if tcainPushAnnounce > 0 then
        tcainPushAnnounce = tcainPushAnnounce - 1
        local text  = "Push Mode: " .. (M.tcainPushActive and "ON" or "OFF")
        local alpha = math.min(tcainPushAnnounce / 30, 1)
        Isaac.RenderText(text, 50, 50, 1, 1, 1, alpha)
    end
    if trinketGulpAnnounce > 0 then
        trinketGulpAnnounce = trinketGulpAnnounce - 1
        local alpha = math.min(trinketGulpAnnounce / 30, 1)
        Isaac.RenderText("Trinkets smelted!", 50, 65, 0.4, 1, 0.4, alpha)
    end
end)

M.captureKey = captureKey

return M

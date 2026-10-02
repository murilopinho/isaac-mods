--[[
qol_mcm.lua - a tela do Mod Config Menu.
6 abas por TEMA (nao mais 1:1 com arquivo .lua): Loadout, Bonus, Fixes, Greed, Machines,
Rooms. "Bonus" saiu da "Loadout" no reorg de 18/set - a aba tinha crescido demais (trinket
picker + active item + gulp key + blessings + pocket item + tainted bonus, tudo junto) e
ficava confusa pra quem abre o mod pela primeira vez. Agora "Loadout" e so a mecanica de
ESCOLHER o inventario inicial; "Bonus" e o que da item de graca SEM escolha nenhuma.
Mesma ideia dentro de "Machines": o No Jam (Donation Machine) fica num bloco proprio,
separado dos fixes soltos (Eternal Chest, Fires/Poops).

Nomes de aba ficam curtos de proposito (<=8 char): o MCM Pure desenha ate 3 nomes
de aba ao mesmo tempo num carrossel com passo FIXO de 76px por slot, sem olhar a
largura real do texto - nome comprido invade o slot vizinho e sobrepoe letras.
Mesma logica pras linhas de texto: MCM Pure nao tem wrap (DrawStringUTF8 com
width=0), entao toda linha de info() fica <=49 char pra nao estourar o painel.
]]

local S           = require("qol_state")
local Config      = require("qol_config")
local Persistence = require("qol_persistence")
local TrinketUtil = require("qol_trinketutil")
local Loadout     = require("qol_loadout")

local CFG = Config.CFG
local HAS_REPENTOGON = S.HAS_REPENTOGON
local saveConfig = Persistence.saveConfig

local M = {}

function M.setupMCM()
    if not ModConfigMenu then return false end
    local cat = "Isaac QoL Kit"

    -- helpers: salva depois de toda mudanca, pra um crash-exit nao perder a configuracao
    local function toggle(sub, label, getter, setter)
        ModConfigMenu.AddSetting(cat, sub, {
            Type           = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = getter,
            Display        = function() return label .. ": " .. (getter() and "ON" or "OFF") end,
            OnChange       = function(v) setter(v); saveConfig() end,
        })
    end
    local function info(sub, text)
        pcall(function() ModConfigMenu.AddText(cat, sub, function() return text end) end)
    end

    -- ── Loadout (Starting Trinket, Active, Gulp Keybind, Reset) ──
    ModConfigMenu.AddText(cat, "Loadout", function()
        return HAS_REPENTOGON and "Repentogon: active (unlock filter works)" or "Repentogon not found (optional, see below)"
    end)

    ModConfigMenu.AddTitle(cat, "Loadout", "Starting Trinket Picker")
    info("Loadout", "Trinket row on floor: pick 1")
    toggle("Loadout", "Trinket by Character",
        function() return CFG.CHAR_TRINKET_CHOICE_ENABLED end,
        function(v) CFG.CHAR_TRINKET_CHOICE_ENABLED = v end)
    toggle("Loadout", "Smelt Innate Trinket",
        function() return CFG.TRINKET_SMELT_INNATE end,
        function(v) CFG.TRINKET_SMELT_INNATE = v end)

    ModConfigMenu.AddTitle(cat, "Loadout", "Active Item")
    info("Loadout", "Frees the active slot at run start")
    toggle("Loadout", "Active -> Pocket Slot",
        function() return CFG.POCKET_ACTIVE_CONVERT end,
        function(v) CFG.POCKET_ACTIVE_CONVERT = v end)

    -- Gulp Keybind: mesmo smeltPlayerTrinkets do "Smelt Innate Trinket" acima, so que
    -- manual por tecla em vez de automatico no inicio da run. Fundido aqui por ser a
    -- mesma familia de feature (a aba "Trinket Utility" antiga so tinha isso sozinho).
    ModConfigMenu.AddTitle(cat, "Loadout", "Gulp Key")
    toggle("Loadout", "Gulp Key",
        function() return CFG.TRINKET_GULP_ENABLED end,
        function(v) CFG.TRINKET_GULP_ENABLED = v end)
    ModConfigMenu.AddSetting(cat, "Loadout", {
        Type           = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return false end,
        Display        = function()
            if not CFG.TRINKET_GULP_ENABLED then return "Gulp Key: (enable above)" end
            if TrinketUtil.trinketGulpWaitingKey then return "Gulp Key: [press a key...]" end
            return "Gulp Key: " .. TrinketUtil.keyName(CFG.TRINKET_GULP_KEY) .. "  (click to change)"
        end,
        OnChange = function(v)
            if v and CFG.TRINKET_GULP_ENABLED then
                TrinketUtil.trinketGulpWaitingKey = true; TrinketUtil.rebindArm = true
            end
        end,
    })
    local GULP_LOC_NAMES = { [0] = "Anywhere",
                             [1] = "Starting room (every floor)",
                             [2] = "Starting room (run start only)" }
    ModConfigMenu.AddSetting(cat, "Loadout", {
        Type           = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return CFG.TRINKET_GULP_LOCATION end,
        Minimum = 0, Maximum = 2, ModifyBy = 1,
        Display  = function()
            if not CFG.TRINKET_GULP_ENABLED then return "Gulp Where: (enable above)" end
            return "Gulp Where: " .. (GULP_LOC_NAMES[CFG.TRINKET_GULP_LOCATION] or "?")
        end,
        OnChange = function(v) CFG.TRINKET_GULP_LOCATION = v; saveConfig() end,
    })

    -- o MCM nao tem um tipo botao de verdade, entao um booleano que sempre volta OFF finge um.
    ModConfigMenu.AddTitle(cat, "Loadout", "Reset")
    ModConfigMenu.AddSetting(cat, "Loadout", {
        Type           = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return false end,
        Display        = function() return ">> Reset All to Default <<" end,
        OnChange       = function(v) if v then Config.resetToDefaults(); saveConfig() end end,
    })

    -- ── Bonus (item de graca SEM escolha, ao contrario da fileira de trinket acima) ──
    ModConfigMenu.AddText(cat, "Bonus", function()
        return "Free items at run start, no picking"
    end)

    ModConfigMenu.AddTitle(cat, "Bonus", "Starting Blessings")
    ModConfigMenu.AddSetting(cat, "Bonus", {
        Type           = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return CFG.STARTING_BLESSING end,
        Minimum = 0, Maximum = #Loadout.STARTING_BLESSING_LIST + 1, ModifyBy = 1,
        Display = function()
            local v = CFG.STARTING_BLESSING
            if v == 0 then return "Starting Blessing: OFF" end
            if v == #Loadout.STARTING_BLESSING_LIST + 1 then return "Starting Blessing: Random" end
            local e = Loadout.STARTING_BLESSING_LIST[v]  -- valor do save pode sobrar de lista maior
            return "Starting Blessing: " .. (e and e.name or "?")
        end,
        OnChange = function(v) CFG.STARTING_BLESSING = v; saveConfig() end,
    })

    ModConfigMenu.AddTitle(cat, "Bonus", "Starting Pocket Item")
    info("Bonus", "Random active spawns in starting room")
    ModConfigMenu.AddSetting(cat, "Bonus", {
        Type           = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.STARTING_POCKET_ITEM end,
        Display        = function()
            if not CFG.POCKET_ACTIVE_CONVERT then return "Starting Pocket Item: (no Active->Pocket)" end
            return "Starting Pocket Item: " .. (CFG.STARTING_POCKET_ITEM and "ON" or "OFF")
        end,
        OnChange = function(v) CFG.STARTING_POCKET_ITEM = v; saveConfig() end,
    })

    ModConfigMenu.AddTitle(cat, "Bonus", "Starting Item")
    info("Bonus", "1 curated item per character (34)")
    info("Bonus", "actives spawn on the floor, free")
    toggle("Bonus", "Starting Item",
        function() return CFG.STARTING_TAINTED_BONUS end,
        function(v) CFG.STARTING_TAINTED_BONUS = v end)
    if HAS_REPENTOGON then
        toggle("Bonus", "Require Unlock",
            function() return CFG.STARTING_ITEM_REQUIRE_UNLOCK end,
            function(v) CFG.STARTING_ITEM_REQUIRE_UNLOCK = v end)
    end

    -- ── Fixes (personagem) ────────────────────────────────────
    -- Judas: o toggle so importa se "Ativo -> Slot Pocket" (aba Loadout) estiver ligado.
    -- MCM Pure nao tem campo de "esconder setting" (conferido no codigo dele), entao o
    -- equivalente aqui e o mesmo idioma ja usado pro Gulp Key/Push Key: troca o texto por
    -- um aviso em vez de sumir a linha.
    ModConfigMenu.AddTitle(cat, "Fixes", "Judas")
    info("Fixes", "Removes the leftover Belial from pocket")
    ModConfigMenu.AddSetting(cat, "Fixes", {
        Type           = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.JUDAS_BELIAL_FIX end,
        Display        = function()
            if not CFG.POCKET_ACTIVE_CONVERT then return "Judas+Birthright Fix: (no Active->Pocket)" end
            return "Judas+Birthright Fix: " .. (CFG.JUDAS_BELIAL_FIX and "ON" or "OFF")
        end,
        OnChange = function(v) CFG.JUDAS_BELIAL_FIX = v; saveConfig() end,
    })

    ModConfigMenu.AddTitle(cat, "Fixes", "Tainted Jacob")
    info("Fixes", "Holy Mantle in Lost form")
    toggle("Fixes", "Holy Mantle on Lost Jacob",
        function() return CFG.HOLY_MANTLE_JACOB end,
        function(v) CFG.HOLY_MANTLE_JACOB = v end)

    ModConfigMenu.AddTitle(cat, "Fixes", "Tainted Lost")
    info("Fixes", "Rainbow poop gives a Holy Card charge")
    toggle("Fixes", "Rainbow Poop Mantle",
        function() return CFG.RAINBOW_POOP_MANTLE end,
        function(v) CFG.RAINBOW_POOP_MANTLE = v end)

    ModConfigMenu.AddTitle(cat, "Fixes", "The Lost")
    info("Fixes", "Resting in a bed gives a Holy Card")
    toggle("Fixes", "Lost Bed Mantle",
        function() return CFG.LOST_BED_MANTLE end,
        function(v) CFG.LOST_BED_MANTLE = v end)

    ModConfigMenu.AddTitle(cat, "Fixes", "Tainted Cain")
    info("Fixes", "Keybind to push pickup (T.Cain only)")
    toggle("Fixes", "T.Cain Push Mode",
        function() return CFG.TCAIN_PUSH_ENABLED end,
        function(v) CFG.TCAIN_PUSH_ENABLED = v; if not v then TrinketUtil.tcainPushActive = false end end)
    ModConfigMenu.AddSetting(cat, "Fixes", {
        Type           = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return false end,
        Display        = function()
            if not CFG.TCAIN_PUSH_ENABLED then return "Push Key: (enable above)" end
            if TrinketUtil.tcainWaitingKey then return "Push Key: [press a key...]" end
            return "Push Key: " .. TrinketUtil.keyName(CFG.TCAIN_PUSH_KEY) .. "  (click to change)"
        end,
        OnChange = function(v)
            if v and CFG.TCAIN_PUSH_ENABLED then
                TrinketUtil.tcainWaitingKey = true; TrinketUtil.rebindArm = true
            end
        end,
    })

    -- ── Greed ──────────────────────────────────────────────────
    ModConfigMenu.AddTitle(cat, "Greed", "Shop")
    info("Greed", "Steam Sale: shop at half price")
    toggle("Greed", "Half-Price Shop (Greed/Greedier)",
        function() return CFG.HALF_PRICE_SHOP end,
        function(v) CFG.HALF_PRICE_SHOP = v end)
    toggle("Greed", "Half-Price Shop (Normal/Hard)",
        function() return CFG.HALF_PRICE_SHOP_NORMAL end,
        function(v) CFG.HALF_PRICE_SHOP_NORMAL = v end)

    ModConfigMenu.AddTitle(cat, "Greed", "Counterfeit Penny")
    info("Greed", "Starts with Counterfeit Penny (+Gulp)")
    info("Greed", "Greedier: Money OR Comfort - pick one")
    toggle("Greed", "Easy Greed/Greedier",
        function() return CFG.EASY_GREED_ENABLED end,
        function(v) CFG.EASY_GREED_ENABLED = v end)

    -- ── Machines ───────────────────────────────────────────────
    ModConfigMenu.AddTitle(cat, "Machines", "Donation Machine")
    info("Machines", "Shop and Greed donation machines only")
    toggle("Machines", "No Jam",
        function() return CFG.NO_JAM end,
        function(v) CFG.NO_JAM = v end)

    ModConfigMenu.AddTitle(cat, "Machines", "Other Fixes")
    toggle("Machines", "Faster Eternal Chest",
        function() return CFG.FASTER_ETERNAL_CHEST end,
        function(v) CFG.FASTER_ETERNAL_CHEST = v end)
    toggle("Machines", "Instant Bonfire/Poop",
        function() return CFG.INSTANT_FIRES_POOPS end,
        function(v) CFG.INSTANT_FIRES_POOPS = v end)

    -- ── Rooms ──────────────────────────────────────────────────
    ModConfigMenu.AddTitle(cat, "Rooms", "Devil Room")
    info("Rooms", "Bombs the statue: angel fight, free item")
    toggle("Rooms", "Bombable Devil Statue",
        function() return CFG.BOMBABLE_DEVIL_STATUE end,
        function(v) CFG.BOMBABLE_DEVIL_STATUE = v end)

    ModConfigMenu.AddTitle(cat, "Rooms", "Pickups")
    toggle("Rooms", "Auto-Collect Pickups",
        function() return CFG.AUTO_COLLECT_PICKUPS end,
        function(v) CFG.AUTO_COLLECT_PICKUPS = v end)

    ModConfigMenu.AddTitle(cat, "Rooms", "Angel Drop Item")
    info("Rooms", "Kills Uriel/Gabriel w/ both Key Pieces: item drop")
    toggle("Rooms", "Angel Drop Item",
        function() return CFG.ANGEL_DROP_ITEM end,
        function(v) CFG.ANGEL_DROP_ITEM = v end)
    toggle("Rooms", "  Always Drops",
        function() return CFG.ANGEL_DROP_ALWAYS end,
        function(v) CFG.ANGEL_DROP_ALWAYS = v end)
    ModConfigMenu.AddSetting(cat, "Rooms", {
        Type           = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return CFG.ANGEL_DROP_CHANCE end,
        Minimum = 10, Maximum = 50, ModifyBy = 10,
        Display  = function()
            if CFG.ANGEL_DROP_ALWAYS then return "  Chance: (Always Drops is ON)" end
            return "  Chance: " .. CFG.ANGEL_DROP_CHANCE .. "%"
        end,
        OnChange = function(v) CFG.ANGEL_DROP_CHANCE = math.max(10, math.min(50, v)); saveConfig() end,
    })

    return true
end

return M

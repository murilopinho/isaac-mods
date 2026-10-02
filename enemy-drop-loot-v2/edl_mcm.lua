--[[
edl_mcm.lua — Mod Config Menu (MCM): o menu de configuração
]]

local S           = require("edl_state")
local Config      = require("edl_config")
local Persistence = require("edl_persistence")
local DropEngine  = require("edl_dropengine")

local game = S.game
local CFG  = Config.CFG
local HAS_REPENTOGON = S.HAS_REPENTOGON
local saveConfig = Persistence.saveConfig

local M = {}

function M.setupMCM()
    if not ModConfigMenu then return false end
    local cat = "Enemy Drop Loot V2"

    -- helpers: salva depois de cada mudança pra que crash-exit não perca as configs
    -- ModifyBy=1 + clamp explícito no OnChange (o MCM não clampava sozinho,
    -- dava pra passar do Maximum declarado sem o Display avisar)
    local function pct(sub, label, getter, setter, min, max)
        min, max = min or 0, max or 100
        ModConfigMenu.AddSetting(cat, sub, {
            Type           = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = getter,
            Minimum        = min,
            Maximum        = max,
            ModifyBy       = 1,
            Display        = function() return label .. ": " .. getter() .. "%" end,
            OnChange       = function(v) setter(math.max(min, math.min(max, v))); saveConfig() end,
        })
    end

    local function toggle(sub, label, getter, setter)
        ModConfigMenu.AddSetting(cat, sub, {
            Type           = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = getter,
            Display        = function() return label .. ": " .. (getter() and "ON" or "OFF") end,
            OnChange       = function(v) setter(v); saveConfig() end,
        })
    end

    -- ── Drops ──────────────────────────────────────────────────
    pcall(function()
        ModConfigMenu.AddText(cat, "Drops", function()
            if HAS_REPENTOGON then return "Repentogon: active  (floor pools work)"
            else return "! Repentogon not found — pools are RANDOM" end
        end)
    end)
    ModConfigMenu.AddTitle(cat, "Drops", "Enable")
    toggle("Drops", "Item Drops",
        function() return CFG.ITEM_DROP_ENABLED end,
        function(v) CFG.ITEM_DROP_ENABLED = v end)
    toggle("Drops", "Pickup Drops",
        function() return CFG.RESOURCE_DROP_ENABLED end,
        function(v) CFG.RESOURCE_DROP_ENABLED = v end)

    ModConfigMenu.AddTitle(cat, "Drops", "Item Rates")
    pct("Drops", "Item (Enemy)",    function() return CFG.ITEM_DROP_RATE.NORMAL   end, function(v) CFG.ITEM_DROP_RATE.NORMAL   = v end, 1, 10)
    pct("Drops", "Item (Champion)", function() return CFG.ITEM_DROP_RATE.CHAMPION end, function(v) CFG.ITEM_DROP_RATE.CHAMPION = v end, 5, 15)
    pct("Drops", "Item (Boss)",     function() return CFG.ITEM_DROP_RATE.BOSS     end, function(v) CFG.ITEM_DROP_RATE.BOSS     = v end, 20, 50)
    toggle("Drops", "Boss always drops",
        function() return CFG.BOSS_GUARANTEED_ITEM end,
        function(v) CFG.BOSS_GUARANTEED_ITEM = v end)

    ModConfigMenu.AddTitle(cat, "Drops", "Pickup Rates")
    pct("Drops", "Pickup (Enemy)",    function() return CFG.RESOURCE_DROP_RATE.NORMAL   end, function(v) CFG.RESOURCE_DROP_RATE.NORMAL   = v end, 5, 20)
    pct("Drops", "Pickup (Champion)", function() return CFG.RESOURCE_DROP_RATE.CHAMPION end, function(v) CFG.RESOURCE_DROP_RATE.CHAMPION = v end, 10, 35)
    pct("Drops", "Pickup (Boss)",     function() return CFG.RESOURCE_DROP_RATE.BOSS     end, function(v) CFG.RESOURCE_DROP_RATE.BOSS     = v end, 30, 65)

    -- título próprio: esse toggle corta o drop INTEIRO (item + pickup) de qualquer boss
    -- extra na Boss Rush, não é só uma taxa de item. não faz sentido embutir dentro
    -- de "Item Rates" sem seção própria.
    ModConfigMenu.AddTitle(cat, "Drops", "Boss Rush")
    ModConfigMenu.AddSetting(cat, "Drops", {
        Type           = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.BOSS_RUSH_LIMIT end,
        Display        = function()
            if CFG.BOSS_RUSH_LIMIT then return "Boss Rush: limit to 1 drop" end
            return "Boss Rush: every boss rolls (cap 5)"
        end,
        OnChange       = function(v) CFG.BOSS_RUSH_LIMIT = v; saveConfig() end,
    })

    ModConfigMenu.AddTitle(cat, "Drops", "Depth Scaling")
    ModConfigMenu.AddSetting(cat, "Drops", {
        Type           = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return CFG.FLOOR_SCALING_PCT end,
        -- min 1: nunca fica OFF, sempre um pouco mais raro por andar
        Minimum = 1, Maximum = 3, ModifyBy = 1,
        Display  = function()
            return "Rarer each floor: -" .. CFG.FLOOR_SCALING_PCT .. "%"
        end,
        OnChange = function(v) CFG.FLOOR_SCALING_PCT = v; saveConfig() end,
    })

    -- ── Filters ──────────────────────────────────────────────
    ModConfigMenu.AddTitle(cat, "Filters", "Item Quality")
    ModConfigMenu.AddSetting(cat, "Filters", {
        Type           = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return CFG.MIN_QUALITY end,
        Minimum = -1, Maximum = 4, ModifyBy = 1,
        Display  = function()
            if CFG.MIN_QUALITY < 0 then return "Min Quality: any" end
            if CFG.MIN_QUALITY == 0 then return "Min Quality: 0 only" end
            return "Min Quality: " .. CFG.MIN_QUALITY .. "+"
        end,
        OnChange = function(v) CFG.MIN_QUALITY = v; saveConfig() end,
    })
    ModConfigMenu.AddSetting(cat, "Filters", {
        Type           = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.QUALITY_LOCK end,
        Display        = function()
            if not CFG.QUALITY_LOCK then return "Exact tier: OFF" end
            if CFG.MIN_QUALITY < 0 then return "Exact tier: ON  (set Min Quality first)" end
            return "Exact tier " .. CFG.MIN_QUALITY .. " only"
        end,
        OnChange       = function(v) CFG.QUALITY_LOCK = v; saveConfig() end,
    })
    toggle("Filters", "Better loot deeper",
        function() return CFG.FLOOR_QUALITY_SCALING end,
        function(v) CFG.FLOOR_QUALITY_SCALING = v end)

    ModConfigMenu.AddTitle(cat, "Filters", "Item Type")
    local IT_NAMES = { [0]="Both", [1]="Passives only", [2]="Actives only" }
    ModConfigMenu.AddSetting(cat, "Filters", {
        Type           = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return CFG.ITEM_TYPE_FILTER end,
        Minimum = 0, Maximum = 2, ModifyBy = 1,
        Display  = function() return "Type: " .. (IT_NAMES[CFG.ITEM_TYPE_FILTER] or "?") end,
        OnChange = function(v) CFG.ITEM_TYPE_FILTER = v; saveConfig() end,
    })

    ModConfigMenu.AddTitle(cat, "Filters", "Item Pool")
    pcall(function()
        ModConfigMenu.AddText(cat, "Filters", function()
            local d = game.Difficulty
            if d == 3 then return "Mode: Greedier" end
            if d == 2 then return "Mode: Greed" end
            if d == 1 then return "Mode: Hard" end
            return "Mode: Normal"
        end)
    end)
    toggle("Filters", "Pool by floor",
        function() return CFG.USE_FLOOR_POOL end,
        function(v) CFG.USE_FLOOR_POOL = v end)
    ModConfigMenu.AddSetting(cat, "Filters", {
        Type           = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return CFG.POOL_OVERRIDE end,
        Minimum = 0, Maximum = 9, ModifyBy = 1,
        Display = function()
            local v = CFG.POOL_OVERRIDE
            if v == 9 then return "Force Pool: Chaos" end
            -- índices 7-8 não existem nas pools de greed; caem pro auto.
            if game:IsGreedMode() and v > 6 then
                return "Force Pool: Auto"
            end
            local names = game:IsGreedMode() and DropEngine.POOL_OVERRIDE_NAMES_GREED or DropEngine.POOL_OVERRIDE_NAMES
            return "Force Pool: " .. (names[v] or "?")
        end,
        OnChange = function(v) CFG.POOL_OVERRIDE = v; saveConfig() end,
    })
    pcall(function()
        ModConfigMenu.AddText(cat, "Filters", function()
            if not HAS_REPENTOGON then return "! Pool by floor needs Repentogon" end
            return "Chaos = random item, ignores pools"
        end)
    end)

    -- Aviso de pool estreita. Conta quantos itens PASSAM em todos os filtros atuais
    -- (Min Quality + Exact tier + Type + Unlock + Pool). Pool <= ~2 é a causa raiz de
    -- "os itens somem" e repetição. o player vê o número antes de quebrar.
    pcall(function()
        ModConfigMenu.AddText(cat, "Filters", function()
            if not CFG.POOL_WARN then return "" end
            if not S.itemsReady then return "Effective pool: (start a run to check)" end
            local n = 0
            local ok = pcall(function()
                for id in pairs(DropEngine.scopeItemIds()) do
                    if not DropEngine.isBlocked(id) and DropEngine.isUnlocked(id) then n = n + 1 end
                end
            end)
            if not ok then return "Effective pool: ?" end
            if n <= 2 then return "! Effective pool: " .. n .. " items - expect repeats" end
            if n <= 6 then return "~ Effective pool: " .. n .. " items - a bit tight" end
            return "Effective pool: " .. n .. " items - healthy"
        end)
    end)

    ModConfigMenu.AddTitle(cat, "Filters", "Story Bosses")
    pcall(function()
        ModConfigMenu.AddText(cat, "Filters", function() return "No loot: Isaac/Satan/Beast/etc" end)
    end)
    ModConfigMenu.AddSetting(cat, "Filters", {
        Type           = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.STORY_BOSS_DROPS end,
        Display        = function()
            if CFG.STORY_BOSS_DROPS then return "Story bosses drop loot: ON" end
            return "Story bosses drop loot: OFF"
        end,
        OnChange       = function(v) CFG.STORY_BOSS_DROPS = v; saveConfig() end,
    })

    ModConfigMenu.AddTitle(cat, "Filters", "Hide Items")
    toggle("Filters", "No story items",
        function() return CFG.BLOCK_STORY_ITEMS end,
        function(v) CFG.BLOCK_STORY_ITEMS = v end)
    toggle("Filters", "No T.M.Trainer",
        function() return CFG.BLOCK_TMTRAINER end,
        function(v) CFG.BLOCK_TMTRAINER = v end)
    if S.dealFilterReady then
        toggle("Filters", "No devil/angel items",
            function() return CFG.NO_DEAL_ITEMS end,
            function(v) CFG.NO_DEAL_ITEMS = v end)
    end
    if HAS_REPENTOGON then
        local UF_NAMES = { [0]="Show all items",
                           [1]="Unlocked only",
                           [2]="Seen only" }
        ModConfigMenu.AddSetting(cat, "Filters", {
            Type           = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = function() return CFG.UNLOCK_FILTER end,
            Minimum = 0, Maximum = 2, ModifyBy = 1,
            Display  = function() return UF_NAMES[CFG.UNLOCK_FILTER] or "?" end,
            OnChange = function(v) CFG.UNLOCK_FILTER = v; saveConfig() end,
        })
        pcall(function()
            ModConfigMenu.AddText(cat, "Filters", function() return "Unlocked = earned but never held" end)
        end)
    end

    ModConfigMenu.AddTitle(cat, "Filters", "Duplicates")
    toggle("Filters", "No duplicates",
        function() return CFG.NO_DUPLICATES end,
        function(v) CFG.NO_DUPLICATES = v end)
    toggle("Filters", "No repeat items (run)",
        function() return CFG.REMOVE_FROM_POOL end,
        function(v) CFG.REMOVE_FROM_POOL = v end)

    -- ── Extras ───────────────────────────────────────────────
    ModConfigMenu.AddTitle(cat, "Extras", "Character Drops")
    pcall(function()
        ModConfigMenu.AddText(cat, "Extras", function() return "Keeper=coins  Lost=cards  T.chars adapted" end)
    end)
    toggle("Extras", "Character Adapted Drops",
        function() return CFG.CHAR_ADAPT_ENABLED end,
        function(v) CFG.CHAR_ADAPT_ENABLED = v end)

    ModConfigMenu.AddTitle(cat, "Extras", "Cards & Runes")
    toggle("Extras", "Cards & Runes",
        function() return CFG.CARD_RUNE_ENABLED end,
        function(v) CFG.CARD_RUNE_ENABLED = v end)
    ModConfigMenu.AddSetting(cat, "Extras", {
        Type           = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return CFG.CARD_DROP_RATE end,
        Minimum = 0, Maximum = 10, ModifyBy = 1,
        Display  = function() return "Card/Rune chance: " .. CFG.CARD_DROP_RATE .. "%" end,
        OnChange = function(v) CFG.CARD_DROP_RATE = math.max(0, math.min(10, v)); saveConfig() end,
    })

    ModConfigMenu.AddTitle(cat, "Extras", "Twin Characters")
    pcall(function()
        ModConfigMenu.AddText(cat, "Extras", function() return "Jacob&Esau / T.Lazarus — 2 drops, one each" end)
    end)
    toggle("Extras", "Twin Double Drop",
        function() return CFG.TWIN_DROP end,
        function(v) CFG.TWIN_DROP = v end)
    toggle("Extras", "Twins Get Same Item",
        function() return CFG.TWIN_SAME_ITEM end,
        function(v) CFG.TWIN_SAME_ITEM = v end)

    -- ── Quality of Life ────────────────────────────────────
    ModConfigMenu.AddTitle(cat, "Extras", "Quality of Life")
    pcall(function()
        ModConfigMenu.AddText(cat, "Extras", function() return "Auto-balance vs Humbling Bundle / Daemon's Tail" end)
    end)
    toggle("Extras", "React to game items",
        function() return CFG.ECONOMY_REACT end,
        function(v) CFG.ECONOMY_REACT = v end)
    local OVL_NAMES = { [0] = "Off", [1] = "Run stats", [2] = "Run stats + roll log" }
    ModConfigMenu.AddSetting(cat, "Extras", {
        Type           = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return CFG.DEBUG_OVERLAY end,
        Minimum = 0, Maximum = 2, ModifyBy = 1,
        Display  = function() return "Debug overlay: " .. (OVL_NAMES[CFG.DEBUG_OVERLAY] or "?") end,
        OnChange = function(v) CFG.DEBUG_OVERLAY = v; saveConfig() end,
    })
    pcall(function()
        ModConfigMenu.AddText(cat, "Extras", function() return "Show 'Effective pool: N' under Force Pool" end)
    end)
    toggle("Extras", "Pool size warning",
        function() return CFG.POOL_WARN end,
        function(v) CFG.POOL_WARN = v end)

    -- o MCM não tem um tipo botão de verdade então a gente finge com um booleano que sempre volta pra OFF.
    ModConfigMenu.AddTitle(cat, "Extras", "Reset")
    ModConfigMenu.AddSetting(cat, "Extras", {
        Type           = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return false end,
        Display        = function() return ">> Reset All to Defaults <<" end,
        OnChange       = function(v) if v then Config.resetToDefaults(); saveConfig() end end,
    })

    -- ── Advanced ─────────────────────────────────────────────
    -- Keybinds e features de nicho sem relação direta com drops de inimigos.
    ModConfigMenu.AddTitle(cat, "Advanced", "Boss Rush")
    pcall(function()
        ModConfigMenu.AddText(cat, "Advanced", function() return "Needs \"Boss Rush: limit\" ON in Drops" end)
    end)
    ModConfigMenu.AddSetting(cat, "Advanced", {
        Type           = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return CFG.BOSS_RUSH_PER_WAVE end,
        Display        = function()
            if not CFG.BOSS_RUSH_LIMIT then return "Boss Rush per-wave: (enable limit first)" end
            if CFG.BOSS_RUSH_PER_WAVE then return "Boss Rush: 1 drop per wave" end
            return "Boss Rush: 1 drop total"
        end,
        OnChange       = function(v) CFG.BOSS_RUSH_PER_WAVE = v; saveConfig() end,
    })

    ModConfigMenu.AddTitle(cat, "Advanced", "Co-op")
    pcall(function()
        ModConfigMenu.AddText(cat, "Advanced", function() return "Local 2+ players — each gets their own drop" end)
    end)
    ModConfigMenu.AddSetting(cat, "Advanced", {
        Type           = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return CFG.COOP_MODE end,
        Minimum        = 0,
        Maximum        = 2,
        Display        = function()
            local names = { [0] = "Off", [1] = "Fair", [2] = "Chaos" }
            return "Coop Mode: " .. (names[CFG.COOP_MODE] or "?")
        end,
        OnChange       = function(v) CFG.COOP_MODE = v; saveConfig() end,
    })

    -- (Easy Greed, Starting Trinket Picker, Gulp Keybind, Active->Pocket e T.Cain Push
    --  saíram daqui em 16/set/2026: viraram o mod Isaac QoL Kit, com menu próprio.)

    -- ── ⚠️ Dev ──────────────────────────────────────────────
    -- Aba só criada com DEV_MODE ou DEV_KEYS ligado no código. O público nunca vê.
    if S.DEV_MODE or S.DEV_KEYS then
        ModConfigMenu.AddTitle(cat, "Dev", S.DEV_MODE and "DEV MODE ACTIVE" or "DEV KEYS ACTIVE")
        pcall(function()
            ModConfigMenu.AddText(cat, "Dev", function() return "1 roll+drop   2 roll+give" end)
            ModConfigMenu.AddText(cat, "Dev", function() return "4 reset-run   5 REAL drop   0 fixed id below" end)
            ModConfigMenu.AddText(cat, "Dev", function() return "1/2 = pool config, no dedup. 5 = real kill path" end)
            ModConfigMenu.AddText(cat, "Dev", function() return "5 + tiny pool + no-repeat = drain test" end)
            if S.DEV_MODE then
                ModConfigMenu.AddText(cat, "Dev", function() return "every kill drops an item; dedup bypassed" end)
            end
        end)
        ModConfigMenu.AddSetting(cat, "Dev", {
            Type           = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = function() return S.devSpawnId end,
            Minimum = 1, Maximum = 4999, ModifyBy = 1,
            Display  = function() return "Spawn item id: " .. S.devSpawnId end,
            OnChange = function(v) S.devSpawnId = v end,
        })
    end

    return true
end

return M

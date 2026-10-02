--[[
qol_persistence.lua - salva/carrega o CFG e os contadores de run entre as runs.
]]

local S      = require("qol_state")
local Config = require("qol_config")

local mod  = S.mod
local json = S.json
local CFG  = Config.CFG
local CFG_SCALAR_KEYS = Config.CFG_SCALAR_KEYS

local M = {}

function M.saveConfig()
    if not json then return end
    pcall(function()
        local d = {}
        for _, k in ipairs(CFG_SCALAR_KEYS) do d[k] = CFG[k] end
        d.runCount              = S.runCount
        d.appliedRunCount       = S.appliedRunCount
        d.pocketAppliedRunCount = S.pocketAppliedRunCount
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
        if type(d.runCount) == "number" then S.runCount = d.runCount end
        if type(d.appliedRunCount) == "number" then S.appliedRunCount = d.appliedRunCount end
        if type(d.pocketAppliedRunCount) == "number" then S.pocketAppliedRunCount = d.pocketAppliedRunCount end
        -- conserta teclas que ficaram salvas em movimento/tiro (ex: gulp na SETA disparava
        -- toda vez que voce atirava pra esse lado) e volta pro default
        local BAD_KEY = {
            [Keyboard.KEY_LEFT] = 1, [Keyboard.KEY_RIGHT] = 1, [Keyboard.KEY_UP] = 1, [Keyboard.KEY_DOWN] = 1,
            [Keyboard.KEY_W] = 1, [Keyboard.KEY_A] = 1, [Keyboard.KEY_S] = 1, [Keyboard.KEY_D] = 1,
        }
        if BAD_KEY[CFG.TRINKET_GULP_KEY] then CFG.TRINKET_GULP_KEY = Keyboard.KEY_G end
        if BAD_KEY[CFG.TCAIN_PUSH_KEY]  then CFG.TCAIN_PUSH_KEY  = Keyboard.KEY_Z end
    end)
end

return M

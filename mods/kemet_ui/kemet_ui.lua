-- Kemet OT custom HUD module.
--
-- Provides three widgets driven by the manifest's command/event systems:
--   1. Vocation weekly buff timer  (!expboost-style countdown for Medjay/
--      Archer of Ra/Scribe of Thoth/Healer of Isis buffs, 7-day duration)
--   2. Lottery countdown           (hourly draw, see lottery in manifest)
--   3. EXP boost tracker           (1/3/7/30-day medals, +50% cap)
--
-- These widgets are wired up via a custom ExtendedOpcode channel. The
-- Canary-side opcode sender is NOT included here -- this stub assumes the
-- server pushes periodic updates on KEMET_OPCODE; see serverdata/README.md
-- for what still needs to be implemented server-side.

KemetUI = {}

local kemetWindow = nil
local lotteryLabel = nil
local expBoostLabel = nil
local vocationBuffLabel = nil

local KEMET_OPCODE = 200 -- TODO: agree on a real extended opcode with the server team

function KemetUI.init()
  kemetWindow = g_ui.displayUI('kemet_ui')
  kemetWindow:setVisible(true)

  lotteryLabel = kemetWindow:getChildById('lotteryCountdown')
  expBoostLabel = kemetWindow:getChildById('expBoostTimer')
  vocationBuffLabel = kemetWindow:getChildById('vocationBuffTimer')

  ProtocolGame.registerExtendedOpcode(KEMET_OPCODE, KemetUI.onServerUpdate)
end

function KemetUI.terminate()
  ProtocolGame.unregisterExtendedOpcode(KEMET_OPCODE, KemetUI.onServerUpdate)
  if kemetWindow then
    kemetWindow:destroy()
    kemetWindow = nil
  end
end

-- Wire format: a single "|"-delimited string (NOT JSON -- keeps both sides
-- dependency-free), sent by the Canary GlobalEvent in
-- serverdata/data/scripts/globalevents/kemet/kemet_opcode_push.lua:
--   "<lottery_seconds_left>|<exp_boost_seconds_left>|<exp_boost_percent>|<vocation_buff_seconds_left>|<vocation_buff_name>"
-- vocation_buff_name may itself contain no "|" characters (vocation names don't).
function KemetUI.onServerUpdate(protocol, opcode, buffer)
  local data = KemetUI.parsePayload(buffer)
  if not data then return end

  if lotteryLabel and data.lottery_seconds_left then
    lotteryLabel:setText('Next draw: ' .. KemetUI.formatSeconds(data.lottery_seconds_left))
  end

  if expBoostLabel then
    if data.exp_boost_seconds_left and data.exp_boost_seconds_left > 0 then
      expBoostLabel:setText(('EXP Boost +%d%%: %s'):format(
        data.exp_boost_percent or 0, KemetUI.formatSeconds(data.exp_boost_seconds_left)))
      expBoostLabel:setVisible(true)
    else
      expBoostLabel:setVisible(false)
    end
  end

  if vocationBuffLabel then
    if data.vocation_buff_seconds_left and data.vocation_buff_seconds_left > 0 then
      vocationBuffLabel:setText((data.vocation_buff_name or 'Weekly Rite') .. ': ' ..
        KemetUI.formatSeconds(data.vocation_buff_seconds_left))
      vocationBuffLabel:setVisible(true)
    else
      vocationBuffLabel:setVisible(false)
    end
  end
end

function KemetUI.parsePayload(buffer)
  if not buffer or buffer == '' then return nil end

  local parts = {}
  for part in (buffer .. '|'):gmatch('([^|]*)|') do
    table.insert(parts, part)
  end

  if #parts < 5 then return nil end

  return {
    lottery_seconds_left = tonumber(parts[1]) or 0,
    exp_boost_seconds_left = tonumber(parts[2]) or 0,
    exp_boost_percent = tonumber(parts[3]) or 0,
    vocation_buff_seconds_left = tonumber(parts[4]) or 0,
    vocation_buff_name = parts[5] ~= '' and parts[5] or nil,
  }
end

function KemetUI.formatSeconds(total)
  total = math.max(0, math.floor(total))
  local h = math.floor(total / 3600)
  local m = math.floor((total % 3600) / 60)
  local s = total % 60
  return ('%02d:%02d:%02d'):format(h, m, s)
end

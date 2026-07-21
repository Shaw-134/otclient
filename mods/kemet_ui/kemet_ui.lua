-- Kemet OT custom HUD module.
--
-- Provides seven widgets driven by the manifest's command/event systems:
--   1. Vocation weekly buff timer  (!expboost-style countdown for Medjay/
--      Archer of Ra/Scribe of Thoth/Healer of Isis buffs, 7-day duration)
--   2. Lottery countdown           (hourly draw, see lottery in manifest)
--   3. EXP boost tracker           (1/3/7/30-day medals, +50% cap)
--   4. Wave Defense status         (state/wave/time, see wave_defense.lua)
--   5. Shop Points balance         (item id 619, Shop Keeper Kha's currency)
--   6. Daily task streak           (Imhotep NPC daily-task system)
--   7. PvP-off badge               (!pvpoff protection status/remaining time)
--
-- These widgets are wired up via a custom ExtendedOpcode channel. The
-- Canary-side opcode sender is
-- serverdata/data/scripts/globalevents/kemet/kemet_opcode_push.lua, which
-- pushes a pipe-delimited payload every 5 seconds.

KemetUI = {}

local kemetWindow = nil
local lotteryLabel = nil
local expBoostLabel = nil
local vocationBuffLabel = nil
local waveDefenseLabel = nil
local shopPointsLabel = nil
local dailyStreakLabel = nil
local pvpOffLabel = nil

local KEMET_OPCODE = 200 -- must match kemet_opcode_push.lua

-- Wave Defense state machine values -- must mirror
-- serverdata/data/scripts/globalevents/kemet/wave_defense.lua's
-- STATE_IDLE/STATE_RECRUITING/STATE_ACTIVE/STATE_REWARDING constants.
local WD_STATE_IDLE       = 0
local WD_STATE_RECRUITING = 1
local WD_STATE_ACTIVE     = 2
local WD_STATE_REWARDING  = 3

function KemetUI.init()
  kemetWindow = g_ui.displayUI('kemet_ui')
  kemetWindow:setVisible(true)

  lotteryLabel = kemetWindow:getChildById('lotteryCountdown')
  expBoostLabel = kemetWindow:getChildById('expBoostTimer')
  vocationBuffLabel = kemetWindow:getChildById('vocationBuffTimer')
  waveDefenseLabel = kemetWindow:getChildById('waveDefenseStatus')
  shopPointsLabel = kemetWindow:getChildById('shopPointsBalance')
  dailyStreakLabel = kemetWindow:getChildById('dailyTaskStreak')
  pvpOffLabel = kemetWindow:getChildById('pvpOffBadge')

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
--   "<lottery_seconds_left>|<exp_boost_seconds_left>|<exp_boost_percent>|<vocation_buff_seconds_left>|<vocation_buff_name>|<wd_state>|<wd_wave>|<wd_seconds_left>|<shop_points>|<daily_streak>|<daily_completed_today>|<pvpoff_active>|<pvpoff_seconds_left>"
-- vocation_buff_name may itself contain no "|" characters (vocation names don't).
-- Fields 6-13 are new -- see kemet_opcode_push.lua's header comment for
-- exactly which real per-player storage/state each one reads.
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

  if waveDefenseLabel then
    local state = data.wd_state or WD_STATE_IDLE
    if state == WD_STATE_RECRUITING then
      waveDefenseLabel:setText(('Wave Defense: Recruiting (%s)'):format(KemetUI.formatSeconds(data.wd_seconds_left or 0)))
      waveDefenseLabel:setVisible(true)
    elseif state == WD_STATE_ACTIVE then
      waveDefenseLabel:setText(('Wave Defense: Wave %d (%s)'):format(data.wd_wave or 0, KemetUI.formatSeconds(data.wd_seconds_left or 0)))
      waveDefenseLabel:setVisible(true)
    elseif state == WD_STATE_REWARDING then
      waveDefenseLabel:setText('Wave Defense: Rewarding...')
      waveDefenseLabel:setVisible(true)
    else
      waveDefenseLabel:setVisible(false)
    end
  end

  if shopPointsLabel then
    shopPointsLabel:setText(('Shop Points: %d'):format(data.shop_points or 0))
    shopPointsLabel:setVisible(true)
  end

  if dailyStreakLabel then
    local streak = data.daily_streak or 0
    local status = (data.daily_completed_today == 1) and 'done today' or 'available'
    dailyStreakLabel:setText(('Daily Streak: %d (%s)'):format(streak, status))
    dailyStreakLabel:setVisible(true)
  end

  if pvpOffLabel then
    if data.pvpoff_active == 1 then
      pvpOffLabel:setText('PvP OFF: ' .. KemetUI.formatSeconds(data.pvpoff_seconds_left or 0))
      pvpOffLabel:setVisible(true)
    else
      pvpOffLabel:setVisible(false)
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
    wd_state = tonumber(parts[6]) or 0,
    wd_wave = tonumber(parts[7]) or 0,
    wd_seconds_left = tonumber(parts[8]) or 0,
    shop_points = tonumber(parts[9]) or 0,
    daily_streak = tonumber(parts[10]) or 0,
    daily_completed_today = tonumber(parts[11]) or 0,
    pvpoff_active = tonumber(parts[12]) or 0,
    pvpoff_seconds_left = tonumber(parts[13]) or 0,
  }
end

function KemetUI.formatSeconds(total)
  total = math.max(0, math.floor(total))
  local h = math.floor(total / 3600)
  local m = math.floor((total % 3600) / 60)
  local s = total % 60
  return ('%02d:%02d:%02d'):format(h, m, s)
end

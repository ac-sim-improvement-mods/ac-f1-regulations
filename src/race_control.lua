---@diagnostic disable: return-type-mismatch
local drs = require 'src/controllers/drs'
local vsc = require 'src/controllers/vsc'
local ai = require 'src/controllers/ai'
local connect = require 'src/connection'

local rc = {}

function readOnly( t )
    local proxy = {}
    local mt = {
        __index = t,
        __newindex = function ( t, k, v )
            error("attempt to update a read-only value", 2)
        end
    }
    setmetatable(proxy, mt)
    return proxy
end

---@alias rc.WeekendSessions
---| `rc.WeekendSessions.FP1` @Value: 0.
---| `rc.WeekendSessions.FP2` @Value: 1.
---| `rc.WeekendSessions.FP3` @Value: 2.
---| `rc.WeekendSessions.Q1` @Value: 3.
---| `rc.WeekendSessions.Q2` @Value: 4.
---| `rc.WeekendSessions.Q3` @Value: 5.
---| `rc.WeekendSessions.Race` @Value: 6.
rc.WeekendSessions = {
    FP1 = 0,
    FP2 = 1,
    FP3 = 2,
    Q1 = 3,
    Q2 = 4,
    Q3 = 5,
    Race = 6
} 

---Returns leaders completed lap count.
---@return lapCount number
local function getLeaderCompletedLaps()
    for i=0, ac.getSim().carsCount - 1 do
        local car = ac.getCar(i)

        if car.racePosition == 1 then
            return car.lapCount
        end
    end
end

---Returns whether DRS is enabled or not
---@param rules F1RegsConfig.data.RULES
---@return drsEnabled boolean
local function isDrsEnabled(rules)
    if getLeaderCompletedLaps() >= rules.DRS_ACTIVATION_LAP then
        return true
    else
        return false
    end
end

---Returns whether the track is too wet for DRS enabled or not
---@param rules F1RegsConfig.data.RULES
---@return wetTrack boolean
local function isTrackWet(rules)
    local sim = ac.getSim()
    local wet_limit = rules.DRS_WET_LIMIT/100
    local track_wetness = sim.rainWetness
    local track_puddles = sim.rainWater

    local total_wetness = ((track_wetness/5) + (track_puddles*10))/2

    if total_wetness >= wet_limit then
        return true
    else
        return false
    end
end

--- Sets the on track order of drivers
--- and excludes drivers in the pitlane
--- @param drivers DRIVERS
local function getTrackOrder(drivers)
    local trackOrder = {}
    for index=0, #drivers do
        if not drivers[index].isInPitlane then
            table.insert(trackOrder,drivers[index])
        else
            drivers[index].trackPosition = -1
        end
    end

    -- Sort drivers by position on track, and ignore drivers in the pits
    table.sort(trackOrder, function (a,b) return a.car.splinePosition > b.car.splinePosition end)

    for trackPos=1, #trackOrder do
        local index = trackOrder[trackPos].index
        drivers[index].trackPosition = trackPos

        if trackPos == 1 then
            drivers[index].carAhead = trackOrder[#trackOrder].index
        else
            drivers[index].carAhead = trackOrder[trackPos - 1].index
        end
    end

    return #trackOrder
end

--- Race Control for race sessions
--- @param rules F1RegsConfig.data.RULES
--- @param driver Driver
local function raceSession(racecontrol,rules,driver)
        if driver.car.isAIControlled then
            if rules.AI_FORCE_PIT_TYRES == 1 then ai.pitNewTires(driver) end
            if rules.AI_AGGRESSION_RUBBERBAND == 1 then ai.alternateAttack(driver)  end
        end

        if rules.DRS_RULES == 1 then drs.controller(driver,racecontrol.drsEnabled) else driver.drsAvailable = true end

        return driver
end

--- Race Control for qualify sessions
--- @param rules F1RegsConfig.data.RULES
--- @param driver 
local function qualifySession(racecontrol,rules,driver)

end

--- Race Control for practice sessions
--- @param rules F1RegsConfig.data.RULES
--- @param driver 
local function practiceSession(racecontrol,rules,driver)

end

--- Switch for runnimg the different kinds of sessioms
--- @param sessionType ac.SessionTypes
--- @param rules F1RegsConfig.data.RULES
--- @param driver Driver
local function run(racecontrol,sessionType,driver)
    local rules = F1RegsConfig.data.RULES

    if sessionType == ac.SessionType.Race then
        raceSession(racecontrol,rules,driver)
    elseif sessionType == ac.SessionType.Qualify then
        qualifySession(racecontrol,rules,driver)
    elseif sessionType == ac.SessionType.Practice then
        practiceSession(racecontrol,rules,driver)
    end

    return driver
end

--- Updates and returns race control variables
--- @return carsOnTrackCount number
--- @return leaderCompletedLaps number
--- @return drsEnabled boolean
--- @return wetTrack boolean
function rc.getRaceControl()
    local rules = F1RegsConfig.data.RULES
    local drivers = DRIVERS
    local carsOnTrackCount = getTrackOrder(drivers)
    local leaderCompletedLaps = getLeaderCompletedLaps()
    local drsEnabled = isDrsEnabled(rules)
    local wetTrack = isTrackWet(rules)

    return readOnly{
        carsOnTrackCount = carsOnTrackCount,
        leaderCompletedLaps = leaderCompletedLaps,
        drsEnabled = drsEnabled,
        wetTrack = wetTrack
    }
end

--- Drives Race Control sessions amd driver loop
---@param sessionType ac.SessionTypes
function rc.session(sessionType)
    local racecontrol = rc.getRaceControl()
    local drivers = DRIVERS
    audioHandler()

    for i=0, #drivers do
        local driver = drivers[i]
        driver:update()
        DRIVERS[i] = run(racecontrol,sessionType,driver)
        connect.storeDriverData(driver)
    end
    
    connect.storeRaceControlData(racecontrol)
end


return rc
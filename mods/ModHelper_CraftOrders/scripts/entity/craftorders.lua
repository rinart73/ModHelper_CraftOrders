package.path = package.path .. ";mods/ModHelper_CraftOrders/?.lua"

local format = string.format


local isLoaded, config = pcall(require, "config/ModHelper_CraftOrders")

local Level = { Error = 1, Warn = 2, Info = 3, Debug = 4 }
local logLevelLabel = { "ERROR", "WARN", "INFO", "DEBUG" }
local function log(level, msg, ...)
    if level > (config and config.logLevel or 3) then return end
    print(format("[%s][%s]: "..msg, logLevelLabel[level], config.acronym, ...))
end

if not isLoaded then
    local err = config
    config = { acronym = "MH-CraftOrders", logLevel = 2 }
    log(Level.Error, "Failed to load config: %s", err)
end


-- functions that will be executed at the start/end of 'initUI' so modders could modify elements
local initUICallbacks = { before = {}, after = {} }

local aiActionIcons = {
  "data/textures/icons/pixel/escort.png",
  "data/textures/icons/pixel/attack.png",
  "data/textures/icons/pixel/gate.png",
  "data/textures/icons/pixel/flytoposition.png",
  "data/textures/icons/pixel/guard.png",
  "data/textures/icons/pixel/escort.png",
  "data/textures/icons/pixel/attack.png",
  "data/textures/icons/pixel/mine.png",
  "data/textures/icons/pixel/scrapyard_thin.png"
}

--[[ Predefined functions ]]--
local old_initialize = CraftOrders.initialize
function CraftOrders.initialize()
    if old_initialize then old_initialize() end
    if onServer() then
        Entity():registerCallback("onJump", "modhelper_onJump")
    end
end

if onServer() then

-- using update and not updateServer because in theory priority matters
local old_update = CraftOrders.update
function CraftOrders.update(timeStep)
    if old_update then old_update(timeStep) end
    
    local entity = Entity()
    -- check if player is in the ship because player onShipChanged callback doesn't fire if we enter a ship from a drone more than once
    if not callingPlayer and entity.hasPilot and CraftOrders.targetAction ~= nil then
       -- fake callingPlayer to use setAIAction
        if entity.playerOwned then
            callingPlayer = entity.factionIndex
        elseif entity.allianceOwned then
            callingPlayer = Alliance(entity.factionIndex).leader
        end
        log(Level.Debug, "Resetting entity AIAction because it's now piloted by player")
        CraftOrders.setAIAction() -- reset CraftOrders.targetAction when player enters the ship
        callingPlayer = nil
    end
end

end

function CraftOrders.initUI()
    for i = 1, #initUICallbacks.before do
        initUICallbacks.before[i]()
    end

    -- try to arrange elements in grid to fit everything
    local elemCount = #CraftOrders.Elements
    local sorted = {}
    local elem
    local squareSpace = 0
    for i = 1, elemCount do
        elem = CraftOrders.Elements[i]
        if elem then
            sorted[#sorted+1] = { height = elem.height or 1, width = elem.width or 1, i = i }
            squareSpace = squareSpace + (elem.width or 1) * (elem.height or 1)
        end
    end
    if squareSpace > 36 then
        log(Level.Warn, "Elements are taking too much space (%u)", squareSpace)
    end
    -- sort
    local n = #sorted
    local newn = 1
    local temp
    repeat
        newn = 1
        for i = 2, n do
            if sorted[i-1].height < sorted[i].height or (sorted[i-1].height == sorted[i].height and sorted[i-1].width < sorted[i].width) then
                temp = sorted[i-1]
                sorted[i-1] = sorted[i]
                sorted[i] = temp
                newn = i
            end
        end
        n = newn
    until n == 1
    -- place
    local elemSorted
    local space = { {}, {}, {} }
    for i = 1, #sorted do
        elemSorted = sorted[i]
        elem = CraftOrders.Elements[elemSorted.i]
        for y = 1, (13 - elemSorted.height) do
            for x = 1, (4 - elemSorted.width) do
                --local willFit = true
                for cx = x, x + (elemSorted.width - 1) do
                    for cy = y, y + (elemSorted.height - 1) do
                        if space[cx][cy] then
                            --willFit = false
                            goto nextCoordinates
                        end
                    end
                end
                --if willFit then
                    for cx = x, x + (elemSorted.width - 1) do
                        for cy = y, y + (elemSorted.height - 1) do
                            space[cx][cy] = true
                        end
                    end
                    elem.rect = Rect(
                      vec2(10 + (x - 1) * 240, 10 + (y - 1) * 40),
                      vec2(240 * (x - 1 + elemSorted.width), 40 * (y - 1 + elemSorted.height)))
                    goto nextElement
                --end
                ::nextCoordinates::
            end
        end
        ::nextElement::
    end
    -- create window
    local rows = 0
    for i = 1, #space[1] do
        if not space[1][i] then break end
        rows = rows + 1
    end
    local res = getResolution()
    local size = vec2(730, 10 + rows * 40)
    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    menu:registerWindow(window, "Orders"%_t)
    window.caption = "Craft Orders"%_t
    window.showCloseButton = 1
    window.moveable = 1
    CraftOrders.window = window
    -- create elements
    for i = 1, elemCount do
        elem = CraftOrders.Elements[i]
        if elem then
            if not elem.rect then
                log(Level.Warn, "Element '%s' wasn't created because of lack of space", elem.title)
                CraftOrders.Elements[i] = nil
            else
                if elem.type == CraftOrders.ElementType.CheckBox then
                    elem.element = window:createCheckBox(Rect(elem.rect.lower + vec2(0, 5), elem.rect.upper), elem.title%_t, elem.func or "")
                elseif elem.type ~= CraftOrders.ElementType.Empty then -- button
                    elem.element = window:createButton(elem.rect, elem.title%_t, elem.func or "")
                end
            end
        end
    end
    
    for i = 1, #initUICallbacks.after do
        initUICallbacks.after[i]()
    end
end

--[[ Functions ]]--

function CraftOrders.updateCurrentOrderIcon()
    Entity():setValue("currentOrderIcon", aiActionIcons[CraftOrders.targetAction] or "")
end

function CraftOrders.modhelper_onJump(shipIndex, x, y)
    if callingPlayer then return end

    local entity = Entity()
    -- fake callingPlayer to use setAIAction
    if entity.playerOwned then
        callingPlayer = entity.factionIndex
    elseif entity.allianceOwned then
        callingPlayer = Alliance(entity.factionIndex).leader
    end
    log(Level.Debug, "Resetting entity AIAction before it will jump out of the sector")
    CraftOrders.setAIAction() -- reset CraftOrders.targetAction when player enters the ship
    callingPlayer = nil
end

--[[ Fixed default Callbacks ]]--

function CraftOrders.onIdleButtonPressed()
    if onClient() then
        invokeServerFunction("onIdleButtonPressed")
        ScriptUI():stopInteraction()
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        local ai = ShipAI()
        ai:setIdle()
        CraftOrders.setAIAction()
    end
end

function CraftOrders.stopFlying()
    if onClient() then
        invokeServerFunction("stopFlying")
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        ShipAI():setPassive()
        CraftOrders.setAIAction()
    end
end

function CraftOrders.escortEntity(index)
    if onClient() then
        invokeServerFunction("escortEntity", index)
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        ShipAI():setEscort(Entity(index))
        CraftOrders.setAIAction(CraftOrders.AIAction.Escort, index)
    end
end

function CraftOrders.attackEntity(index)
    if onClient() then
        invokeServerFunction("attackEntity", index);
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        local ai = ShipAI()
        ai:setAttack(Entity(index))
        CraftOrders.setAIAction(CraftOrders.AIAction.Attack, index)
    end
end

function CraftOrders.flyToPosition(pos)
    if onClient() then
        invokeServerFunction("flyToPosition", pos);
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        local ai = ShipAI()
        ai:setFly(pos, 0)
        CraftOrders.setAIAction(CraftOrders.AIAction.FlyToPosition, nil, pos)
    end
end

function CraftOrders.flyThroughWormhole(index)
    if onClient() then
        invokeServerFunction("flyThroughWormhole", index);
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        local ship = Entity()
        local target = Entity(index)

        if target:hasComponent(ComponentType.Plan) then
            -- gate
            local entryPos
            local flyThroughPos
            local waypoints = {}

            -- determine best direction for entering the gate
            if dot(target.look, ship.translationf - target.translationf) > 0 then
                entryPos = target.translationf + target.look * ship:getBoundingSphere().radius * 10
                flyThroughPos = target.translationf - target.look * ship:getBoundingSphere().radius * 5
            else
                entryPos = target.translationf - target.look * ship:getBoundingSphere().radius * 10
                flyThroughPos = target.translationf + target.look * ship:getBoundingSphere().radius * 5
            end
            table.insert(waypoints, entryPos)
            table.insert(waypoints, flyThroughPos)

            Entity():addScript("ai/flythroughwormhole.lua", unpack(waypoints))
        else
            -- wormhole
            ShipAI():setFly(target.translationf, 0)
        end

        CraftOrders.setAIAction(CraftOrders.AIAction.FlyThroughWormhole, index)
    end
end

if CraftOrders.guardPosition then -- 0.18.2+


function CraftOrders.guardPosition(position)
    if onClient() then
        invokeServerFunction("guardPosition", position)
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        ShipAI():setGuard(position)
        CraftOrders.setAIAction(CraftOrders.AIAction.Guard, nil, position)
    end
end

function CraftOrders.attackEnemies()
    if onClient() then
        invokeServerFunction("attackEnemies")
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        ShipAI():setAggressive()
        CraftOrders.setAIAction(CraftOrders.AIAction.Aggressive)
    end
end

function CraftOrders.patrolSector()
    if onClient() then
        invokeServerFunction("patrolSector")
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        Entity():addScript("ai/patrol.lua")
        CraftOrders.setAIAction(CraftOrders.AIAction.Patrol)
    end
end

function CraftOrders.mine()
    if onClient() then
        invokeServerFunction("mine")
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        Entity():addScript("ai/mine.lua")
        CraftOrders.setAIAction(CraftOrders.AIAction.Mine)
    end
end

function CraftOrders.onSalvageButtonPressed()
    if onClient() then
        invokeServerFunction("salvage")
        ScriptUI():stopInteraction()
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        Entity():addScript("ai/salvage.lua")
        CraftOrders.setAIAction(CraftOrders.AIAction.Salvage)
    end
end

function CraftOrders.salvage()
    if onClient() then
        invokeServerFunction("salvage")
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        Entity():addScript("ai/salvage.lua")
        CraftOrders.setAIAction(CraftOrders.AIAction.Salvage)
    end
end


else -- 0.17.1+


function CraftOrders.onGuardButtonPressed()
    if onClient() then
        invokeServerFunction("onGuardButtonPressed")
        ScriptUI():stopInteraction()
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        local pos = Entity().translationf
        ShipAI():setGuard(pos)
        CraftOrders.setAIAction(CraftOrders.AIAction.Guard, nil, pos)
    end
end

function CraftOrders.onAttackEnemiesButtonPressed()
    if onClient() then
        invokeServerFunction("onAttackEnemiesButtonPressed")
        ScriptUI():stopInteraction()
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        ShipAI():setAggressive()
        CraftOrders.setAIAction(CraftOrders.AIAction.Aggressive)
    end
end

function CraftOrders.onPatrolButtonPressed()
    if onClient() then
        invokeServerFunction("onPatrolButtonPressed")
        ScriptUI():stopInteraction()
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        Entity():addScript("ai/patrol.lua")
        CraftOrders.setAIAction(CraftOrders.AIAction.Patrol)
    end
end

function CraftOrders.onMineButtonPressed()
    if onClient() then
        invokeServerFunction("onMineButtonPressed")
        ScriptUI():stopInteraction()
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        Entity():addScript("ai/mine.lua")
        CraftOrders.setAIAction(CraftOrders.AIAction.Mine)
    end
end

function CraftOrders.onSalvageButtonPressed()
    if onClient() then
        invokeServerFunction("onSalvageButtonPressed")
        ScriptUI():stopInteraction()
        return
    end

    if CraftOrders.checkCaptain() then
        CraftOrders.removeSpecialOrders()

        Entity():addScript("ai/salvage.lua")
        CraftOrders.setAIAction(CraftOrders.AIAction.Salvage)
    end
end


end

--[[ API ]]--

CraftOrders.window = nil

-- 'Empty' will just reserve a rect, so it could be used to create custom element
CraftOrders.ElementType = { Empty = 1, Button = 2, CheckBox = 3 }

CraftOrders.Elements = {
  {
    title = "Idle",
    func = "onIdleButtonPressed",
    --type = CraftOrders.ElementType.Button - button by default,
    --rect = Rect(..) -- will be added by initUI function,
    --element = .. -- will be added by initUI function if ElementType is not 'Empty'
  },
  { title = "Passive", func = "onPassiveButtonPressed" },
  { title = "Guard This Position", func = "onGuardButtonPressed" },
  { title = "Patrol Sector", func = "onPatrolButtonPressed" },
  { title = "Escort Me", func = "onEscortMeButtonPressed" },
  { title = "Attack Enemies", func = "onAttackEnemiesButtonPressed" },
  { title = "Mine", func = "onMineButtonPressed" },
  { title = "Salvage", func = "onSalvageButtonPressed" }
}

-- don't add elements to this table manually. Use 'addAIAction'
CraftOrders.AIAction = {
  Escort = 1,
  Attack = 2,
  FlyThroughWormhole = 3,
  FlyToPosition = 4,
  Guard = 5,
  Patrol = 6,
  Aggressive = 7,
  Mine = 8,
  Salvage = 9
}

-- vanilla function, just not local
function CraftOrders.checkCaptain()
    local entity = Entity()
    if not checkEntityInteractionPermissions(Entity(), AlliancePrivilege.FlyCrafts) then
        return
    end
    local captains = entity:getCrewMembers(CrewProfessionType.Captain)
    if captains and captains > 0 then
        return true
    end
    local faction = Faction()
    faction:sendChatMessage("", 1, "Your ship has no captain!"%_t)
end

-- upgraded vanilla function that now also removes ai scripts from mods
function CraftOrders.removeSpecialOrders()
    local entity = Entity()
    for index, name in pairs(entity:getScripts()) do
        if string.match(name, "/scripts/entity/ai/") then
            entity:removeScript(index)
        end
    end
end

-- allows you to register function that will be executed at the start/end of 'initUI'
function CraftOrders.registerInitUICallback(func, beforeUICreation)
    if beforeUICreation then
        initUICallbacks.before[#initUICallbacks.before+1] = func
    else
        initUICallbacks.after[#initUICallbacks.after+1] = func
    end
end

-- allows to add UI element. Returns it's index in CraftOrders.Elements table
-- default elemType is CraftOrders.ElementType.Button
-- deffault width and height are 1
function CraftOrders.addElement(title, func, elemType, width, height)
    local row = { title = title, func = func, width = width, height = height }
    if elemType then
        row.type = elemType
    end
    local pos = #CraftOrders.Elements+1
    CraftOrders.Elements[pos] = row
    return pos
end

-- should be called in callback that executes before UI creation: CraftOrders.registerInitUICallback("myCallback", true)
-- allows to remove element by title or table index
function CraftOrders.removeElement(index)
    if type(index) == "number" then
        CraftOrders.Elements[index] = nil
        return
    end
    local elem
    for i = 1, #CraftOrders.Elements do
        elem = CraftOrders.Elements[i]
        if elem and elem.title == index then
            CraftOrders.Elements[i] = nil
            return
        end
    end
end

-- adds AIAction
function CraftOrders.addAIAction(name, iconpath)
    -- not using numeric index because otherwise if mod that adds AIAction will be deleted everything will shift
    CraftOrders.AIAction[name] = name
    aiActionIcons[name] = iconpath
end
--[[
Modname: ModHelper_CraftOrders
Author: Rinart73
Version: 1.0.0 (0.17.1 - 0.18.2)
Description: Allows modders to create non-conflicting mods that add Orders to the Craft Orders Tab.
]]

local format = string.format
local function log(msg, ...)
    print(format("[ERROR][ModHelper-CraftOrders]: "..msg, ...))
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
        log("Elements are taking too much space (%u)", squareSpace)
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
                log("Element '%s' wasn't created because of lack of space", elem.title)
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

function CraftOrders.updateCurrentOrderIcon()
    Entity():setValue("currentOrderIcon", aiActionIcons[CraftOrders.targetAction] or "")
end

-- API

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

-- vanilla function, just not local
function CraftOrders.removeSpecialOrders()
    local entity = Entity()
    for index, name in pairs(entity:getScripts()) do
        if string.match(name, "data/scripts/entity/ai/") then
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
    -- not using numeric index, because if mod that adds AIAction will be deleted afterwise, everything will shift
    CraftOrders.AIAction[name] = name
    aiActionIcons[name] = iconpath
end
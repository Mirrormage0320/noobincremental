local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local GUI_NAME = "NoobIncremental hub"
local GUI_WIDTH = 290
local MIN_SIZE = UDim2.fromOffset(GUI_WIDTH, 34)
local TAB_ORDER = {"reaper", "houses", "mobs", "trials"}
local TAB_TITLES = {reaper = "Reaper", houses = "Houses", mobs = "Mobs", trials = "Trials"}
local TAB_HEIGHTS = {reaper = 398, houses = 376, mobs = 482, trials = 548}

local REAPER_FOLDER = "ReaperNoobs"
local OUT_POSITION = Vector3.new(-14001.6, 0.8, 8942.0)
local IN_POSITION = Vector3.new(-13986.1, -0.1, 8962.8)
local EMPTY_CONFIRM = 0.25

local MOB_CHECK_INTERVAL = 0.1
local MOB_DEAD_COOLDOWN = 1.5
local MOB_WAIT_INTERVAL = 0.25
local DEAD_ATTRIBUTES = {"Dead", "IsDead", "Respawning"}

local TRIAL_ROOMS = {"EasyTrialRoom", "MediumTrialRoom", "HardTrialRoom", "ExtremeTrialRoom"}
local HEALTH_NAMES = {health = true, hp = true, currenthealth = true, curhealth = true, currenthp = true}

local GREEN = Color3.fromRGB(46, 160, 90)
local RED = Color3.fromRGB(200, 70, 70)
local GRAY = Color3.fromRGB(60, 60, 80)
local BLUE = Color3.fromRGB(110, 170, 255)
local YELLOW = Color3.fromRGB(240, 200, 80)
local ACTIVE_TAB = Color3.fromRGB(90, 80, 200)
local INACTIVE_TAB = Color3.fromRGB(44, 44, 60)

local env = (getgenv and getgenv()) or _G

for _, key in ipairs({"FarmHubGui", "ReaperNoobFarmGui", "MobTeleportFarmGui", "TrialMobFarmGui"}) do
    if env[key] then
        pcall(function()
            env[key]:Destroy()
        end)
    end
end

local ReaperStatuses = {
    stopped = {"Stopped", Color3.fromRGB(230, 100, 100)},
    farming = {"Farming", Color3.fromRGB(90, 220, 130)},
    waiting = {"Waiting for noobs", YELLOW},
    resetting = {"Resetting zone", BLUE},
}

local MobStatuses = {
    stopped = {"Stopped", Color3.fromRGB(230, 100, 100)},
    farming = {"Farming", Color3.fromRGB(90, 220, 130)},
    waiting = {"Waiting for respawn", YELLOW},
    empty = {"No mob selected", YELLOW},
}

local TrialStatuses = {
    stopped = {"Stopped", Color3.fromRGB(230, 100, 100)},
    farming = {"Farming", Color3.fromRGB(90, 220, 130)},
    waiting = {"Waiting for mobs", YELLOW},
    empty = {"No mob selected", YELLOW},
}

local Reaper = {
    Running = false,
    Session = 0,
    Status = "stopped",
    Target = nil,
    Done = 0,
    Resets = 0,
    Height = 0,
    Distance = 3,
    OutWait = 0.5,
    InWait = 1.5,
    StuckLimit = 5,
}

local Mobs = {
    Running = false,
    Session = 0,
    Status = "stopped",
    Target = nil,
    Done = 0,
    Height = 0,
    Distance = 3,
    Selected = {},
}

local Trials = {
    Running = false,
    Session = 0,
    Status = "stopped",
    Target = nil,
    Done = 0,
    Height = 0,
    Distance = 3,
    SwitchTime = 1,
    Selected = {},
    AutoSelect = true,
}

local Houses = {
    Busy = false,
    Status = "Idle",
    Stay = 2,
    FrontStay = 0.5,
    List = {
        {Label = "House 1", Front = Vector3.new(-14131.2, 0.8, 8652.2), Position = Vector3.new(-14131.6, 1.4, 8644.8), Enabled = false, Seconds = 300, Last = -math.huge},
        {Label = "House 2", Front = Vector3.new(-14127.5, 0.8, 8894.1), Position = Vector3.new(-14127.6, 1.4, 8902.1), Enabled = false, Seconds = 300, Last = -math.huge},
        {Label = "House 3", Front = Vector3.new(-14232.0, 0.8, 8784.8), Position = Vector3.new(-14236.9, 1.3, 8784.6), Enabled = false, Seconds = 300, Last = -math.huge},
    },
}

local Farms = {}

local alive = true

local function getHRP()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function placeAt(hrp, position)
    hrp.CFrame = CFrame.new(position)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function getRoot(model)
    if model:IsA("BasePart") then
        return model
    end
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function isPresent(model)
    return model.Parent ~= nil and model:IsDescendantOf(workspace)
end

local function standAt(hrp, root, settings)
    local targetPos = root.Position
    local pos = targetPos + Vector3.new(0, settings.Height, settings.Distance)
    if math.abs(settings.Distance) > 0.05 then
        hrp.CFrame = CFrame.lookAt(pos, Vector3.new(targetPos.X, pos.Y, targetPos.Z))
    else
        hrp.CFrame = CFrame.new(pos)
    end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function waitForHouse(active)
    if not Houses.Busy then
        return 0
    end
    local startedAt = os.clock()
    while Houses.Busy and active() do
        RunService.Heartbeat:Wait()
    end
    return os.clock() - startedAt
end

local function anyFarmRunning()
    for _, farm in ipairs(Farms) do
        if farm.state.Running then
            return true
        end
    end
    return false
end

local function isInReaperFolder(model)
    local parent = model.Parent
    return parent ~= nil and parent.Name == REAPER_FOLDER and model:IsDescendantOf(workspace)
end

local function isCorpse(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health <= 0
end

local function getReaperTargets()
    local list = {}
    local folder = workspace:FindFirstChild(REAPER_FOLDER)
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") and getRoot(child) then
                table.insert(list, child)
            end
        end
    end
    return list
end

local function hasReaperTargets()
    return #getReaperTargets() > 0
end

local function pickReaperTarget(hrp)
    local best
    local bestScore
    for _, model in ipairs(getReaperTargets()) do
        local score = (getRoot(model).Position - hrp.Position).Magnitude
        if isCorpse(model) then
            score = score + 1e9
        end
        if not bestScore or score < bestScore then
            best = model
            bestScore = score
        end
    end
    return best
end

local function holdAt(position, seconds, active, stopWhen)
    local startedAt = os.clock()
    repeat
        startedAt = startedAt + waitForHouse(active)
        local hrp = getHRP()
        if hrp and active() then
            pcall(placeAt, hrp, position)
        end
        RunService.Heartbeat:Wait()
        if stopWhen and stopWhen() then
            return
        end
    until not active() or os.clock() - startedAt >= seconds
end

local function resetZone(active)
    Reaper.Status = "resetting"
    Reaper.Target = nil
    Reaper.Resets = Reaper.Resets + 1
    holdAt(OUT_POSITION, Reaper.OutWait, active)
    if not active() then
        return
    end
    holdAt(IN_POSITION, Reaper.InWait, active, hasReaperTargets)
end

local function startReaper()
    if Reaper.Running then
        return
    end
    Reaper.Running = true
    Reaper.Session = Reaper.Session + 1
    local session = Reaper.Session

    local function active()
        return Reaper.Running and Reaper.Session == session
    end

    task.spawn(function()
        local emptySince = nil
        while active() do
            waitForHouse(active)
            if not active() then
                return
            end
            local hrp = getHRP()
            local target = hrp and pickReaperTarget(hrp)
            if target then
                emptySince = nil
                Reaper.Target = target
                Reaper.Status = "farming"
                local humanoid = target:FindFirstChildOfClass("Humanoid")
                local watchHealth = humanoid ~= nil and humanoid.Health > 0
                local targetStartedAt = os.clock()
                local stuck = false
                while active() and isInReaperFolder(target) do
                    targetStartedAt = targetStartedAt + waitForHouse(active)
                    if not active() then
                        break
                    end
                    if watchHealth and humanoid.Health <= 0 then
                        break
                    end
                    if Reaper.StuckLimit > 0 and os.clock() - targetStartedAt >= Reaper.StuckLimit then
                        stuck = true
                        break
                    end
                    local currentHRP = getHRP()
                    local root = getRoot(target)
                    if not root then
                        break
                    end
                    if currentHRP then
                        pcall(standAt, currentHRP, root, Reaper)
                    end
                    RunService.Heartbeat:Wait()
                end
                if not active() then
                    return
                end
                Reaper.Target = nil
                if stuck then
                    resetZone(active)
                    emptySince = nil
                else
                    Reaper.Done = Reaper.Done + 1
                end
            else
                Reaper.Target = nil
                Reaper.Status = "waiting"
                if hrp then
                    emptySince = emptySince or os.clock()
                    if os.clock() - emptySince >= EMPTY_CONFIRM then
                        resetZone(active)
                        emptySince = nil
                    else
                        task.wait(0.05)
                    end
                else
                    emptySince = nil
                    task.wait(0.2)
                end
            end
        end
    end)
end

local function stopReaper()
    Reaper.Running = false
    Reaper.Session = Reaper.Session + 1
    Reaper.Target = nil
    Reaper.Status = "stopped"
end

local mobCooldown = setmetatable({}, {__mode = "k"})

local function getMobsFolder()
    local content = workspace:FindFirstChild("__GAME_CONTENT")
    return content and content:FindFirstChild("Mobs")
end

local function hasRespawnLabel(model)
    for _, descendant in ipairs(model:GetDescendants()) do
        if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and descendant.Visible then
            local text = descendant.Text
            if text ~= "" and string.find(string.lower(text), "respawn", 1, true) then
                local holder = descendant:FindFirstAncestorWhichIsA("BillboardGui")
                    or descendant:FindFirstAncestorWhichIsA("SurfaceGui")
                if not holder or holder.Enabled then
                    return true
                end
            end
        end
    end
    return false
end

local function isMobDead(model)
    if not isPresent(model) then
        return true
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return true
    end
    for _, name in ipairs(DEAD_ATTRIBUTES) do
        if model:GetAttribute(name) == true then
            return true
        end
    end
    return hasRespawnLabel(model)
end

local function listMobTypes()
    local names = {}
    local counts = {}
    local folder = getMobsFolder()
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") then
                local name = child.Name
                if not counts[name] then
                    counts[name] = 0
                    table.insert(names, name)
                end
                counts[name] = counts[name] + 1
            end
        end
    end
    table.sort(names)
    return names, counts
end

local function getMobCandidates()
    local list = {}
    local folder = getMobsFolder()
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") and Mobs.Selected[child.Name] and getRoot(child) then
                table.insert(list, child)
            end
        end
    end
    return list
end

local function pickMobTarget(hrp)
    local best
    local bestDistance
    local now = os.clock()
    for _, model in ipairs(getMobCandidates()) do
        local blockedUntil = mobCooldown[model]
        if not (blockedUntil and blockedUntil > now) and not isMobDead(model) then
            local root = getRoot(model)
            if root then
                local distance = (root.Position - hrp.Position).Magnitude
                if not bestDistance or distance < bestDistance then
                    best = model
                    bestDistance = distance
                end
            end
        end
    end
    return best
end

local function startMobs()
    if Mobs.Running then
        return
    end
    Mobs.Running = true
    Mobs.Session = Mobs.Session + 1
    local session = Mobs.Session

    local function active()
        return Mobs.Running and Mobs.Session == session
    end

    task.spawn(function()
        while active() do
            waitForHouse(active)
            if not active() then
                return
            end
            local hrp = getHRP()
            local target = hrp and pickMobTarget(hrp)
            if target then
                Mobs.Target = target
                Mobs.Status = "farming"
                local lastCheck = 0
                local finished = false
                while active() and isPresent(target) do
                    waitForHouse(active)
                    if not active() then
                        break
                    end
                    local now = os.clock()
                    if now - lastCheck >= MOB_CHECK_INTERVAL then
                        lastCheck = now
                        if isMobDead(target) then
                            finished = true
                            break
                        end
                        if not Mobs.Selected[target.Name] then
                            break
                        end
                    end
                    local currentHRP = getHRP()
                    local root = getRoot(target)
                    if not root then
                        finished = true
                        break
                    end
                    if currentHRP then
                        pcall(standAt, currentHRP, root, Mobs)
                    end
                    RunService.Heartbeat:Wait()
                end
                if not active() then
                    return
                end
                if finished then
                    mobCooldown[target] = os.clock() + MOB_DEAD_COOLDOWN
                    Mobs.Done = Mobs.Done + 1
                end
                Mobs.Target = nil
            else
                Mobs.Target = nil
                Mobs.Status = next(Mobs.Selected) and "waiting" or "empty"
                task.wait(MOB_WAIT_INTERVAL)
            end
        end
    end)
end

local function stopMobs()
    Mobs.Running = false
    Mobs.Session = Mobs.Session + 1
    Mobs.Target = nil
    Mobs.Status = "stopped"
end

local function getTrialFolders()
    local folders = {}
    local content = workspace:FindFirstChild("__GAME_CONTENT")
    local contents = content and content:FindFirstChild("Contents")
    local world = contents and contents:FindFirstChild("WORLD - 3")
    local trials = world and world:FindFirstChild("Trials")
    if trials then
        for _, roomName in ipairs(TRIAL_ROOMS) do
            local room = trials:FindFirstChild(roomName)
            local mobs = room and (room:FindFirstChild("Mobs") or room:FindFirstChild("Mobs", true))
            if mobs then
                table.insert(folders, mobs)
            end
        end
    end
    return folders
end

local function isTrialMob(child)
    return child:IsA("Model") or child:IsA("BasePart")
end

local function getHealth(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        return humanoid.Health
    end
    for key, value in pairs(model:GetAttributes()) do
        if type(value) == "number" and HEALTH_NAMES[string.lower(key)] then
            return value
        end
    end
    for _, child in ipairs(model:GetChildren()) do
        if (child:IsA("NumberValue") or child:IsA("IntValue")) and HEALTH_NAMES[string.lower(child.Name)] then
            return child.Value
        end
    end
    return nil
end

local function isTrialAlive(model)
    local health = getHealth(model)
    return health == nil or health > 0
end

local function listTrialMobs()
    local names = {}
    local counts = {}
    for _, folder in ipairs(getTrialFolders()) do
        for _, child in ipairs(folder:GetChildren()) do
            if isTrialMob(child) and isTrialAlive(child) then
                local name = child.Name
                if not counts[name] then
                    counts[name] = 0
                    table.insert(names, name)
                end
                counts[name] = counts[name] + 1
            end
        end
    end
    table.sort(names)
    return names, counts
end

local function getTrialCandidates()
    local list = {}
    for _, folder in ipairs(getTrialFolders()) do
        for _, child in ipairs(folder:GetChildren()) do
            if isTrialMob(child) and Trials.Selected[child.Name] and isTrialAlive(child) and getRoot(child) then
                table.insert(list, child)
            end
        end
    end
    return list
end

local function pickTrialTarget(hrp, avoid)
    local best
    local bestDistance
    local fallback
    for _, model in ipairs(getTrialCandidates()) do
        if model == avoid then
            fallback = model
        else
            local root = getRoot(model)
            if root then
                local distance = (root.Position - hrp.Position).Magnitude
                if not bestDistance or distance < bestDistance then
                    best = model
                    bestDistance = distance
                end
            end
        end
    end
    return best or fallback
end

local function startTrials()
    if Trials.Running then
        return
    end
    Trials.Running = true
    Trials.Session = Trials.Session + 1
    local session = Trials.Session

    local function active()
        return Trials.Running and Trials.Session == session
    end

    task.spawn(function()
        local avoid = nil
        while active() do
            waitForHouse(active)
            if not active() then
                return
            end
            local hrp = getHRP()
            local target = hrp and pickTrialTarget(hrp, avoid)
            if target then
                Trials.Target = target
                Trials.Status = "farming"
                local startedAt = os.clock()
                local switched = false
                while active() and isPresent(target) do
                    startedAt = startedAt + waitForHouse(active)
                    if not active() then
                        break
                    end
                    if not Trials.Selected[target.Name] then
                        break
                    end
                    if Trials.SwitchTime > 0 and os.clock() - startedAt >= Trials.SwitchTime then
                        switched = true
                        break
                    end
                    local currentHRP = getHRP()
                    local root = getRoot(target)
                    if not root then
                        break
                    end
                    if currentHRP then
                        pcall(standAt, currentHRP, root, Trials)
                    end
                    RunService.Heartbeat:Wait()
                end
                if not active() then
                    return
                end
                if switched or not isPresent(target) then
                    Trials.Done = Trials.Done + 1
                end
                avoid = switched and target or nil
                Trials.Target = nil
            else
                Trials.Target = nil
                Trials.Status = next(Trials.Selected) and "waiting" or "empty"
                RunService.Heartbeat:Wait()
            end
        end
    end)
end

local function stopTrials()
    Trials.Running = false
    Trials.Session = Trials.Session + 1
    Trials.Target = nil
    Trials.Status = "stopped"
end

local reaperFarm = {state = Reaper, start = startReaper, stop = stopReaper}
local mobsFarm = {state = Mobs, start = startMobs, stop = stopMobs}
local trialsFarm = {state = Trials, start = startTrials, stop = stopTrials}

table.insert(Farms, reaperFarm)
table.insert(Farms, mobsFarm)
table.insert(Farms, trialsFarm)

local function toggleFarm(farm)
    if farm.state.Running then
        farm.stop()
        return
    end
    for _, other in ipairs(Farms) do
        if other ~= farm and other.state.Running then
            other.stop()
        end
    end
    farm.start()
end

local function visitHouse(house)
    local startHRP = getHRP()
    local origin = startHRP and startHRP.CFrame

    Houses.Busy = true
    Houses.Status = "Teleporting to " .. house.Label

    pcall(function()
        local stages = {
            {position = house.Front, seconds = Houses.FrontStay},
            {position = house.Position, seconds = Houses.Stay},
        }
        for _, stage in ipairs(stages) do
            local startedAt = os.clock()
            repeat
                local hrp = getHRP()
                if hrp then
                    pcall(placeAt, hrp, stage.position)
                end
                RunService.Heartbeat:Wait()
            until not alive or os.clock() - startedAt >= stage.seconds
            if not alive then
                break
            end
        end
    end)

    if origin and alive and not anyFarmRunning() then
        pcall(function()
            local hrp = getHRP()
            if hrp then
                hrp.CFrame = origin
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end
        end)
    end

    house.Last = os.clock()
    Houses.Busy = false
    Houses.Status = "Idle"
end

local function houseScheduler()
    while alive do
        local due = nil
        for _, house in ipairs(Houses.List) do
            if house.Enabled and os.clock() - house.Last >= house.Seconds then
                due = house
                break
            end
        end
        if due then
            visitHouse(due)
        end
        task.wait(0.25)
    end
end

local function create(className, props, parent)
    local instance = Instance.new(className)
    for key, value in pairs(props) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local activeTab = "reaper"
local minimized = false

local function getFullSize()
    return UDim2.fromOffset(GUI_WIDTH, TAB_HEIGHTS[activeTab])
end

local gui = create("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
})

local main = create("Frame", {
    Name = "Main",
    Size = getFullSize(),
    Position = UDim2.fromOffset(40, 240),
    BackgroundColor3 = Color3.fromRGB(22, 22, 30),
    BorderSizePixel = 0,
    Active = true,
}, gui)
create("UICorner", {CornerRadius = UDim.new(0, 8)}, main)
create("UIStroke", {Color = Color3.fromRGB(70, 70, 95), Thickness = 1}, main)

local titleBar = create("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundColor3 = Color3.fromRGB(32, 32, 44),
    BorderSizePixel = 0,
}, main)
create("UICorner", {CornerRadius = UDim.new(0, 8)}, titleBar)
create("Frame", {
    Size = UDim2.new(1, 0, 0, 10),
    Position = UDim2.new(0, 0, 1, -10),
    BackgroundColor3 = Color3.fromRGB(32, 32, 44),
    BorderSizePixel = 0,
}, titleBar)

create("TextLabel", {
    Size = UDim2.new(1, -80, 1, 0),
    Position = UDim2.fromOffset(12, 0),
    BackgroundTransparency = 1,
    Text = "Farm Hub",
    TextColor3 = Color3.fromRGB(240, 240, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

local function headerButton(text, xOffset)
    local button = create("TextButton", {
        Size = UDim2.fromOffset(26, 22),
        Position = UDim2.new(1, xOffset, 0, 6),
        BackgroundColor3 = Color3.fromRGB(52, 52, 70),
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Color3.fromRGB(240, 240, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 14,
    }, titleBar)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, button)
    return button
end

local minimizeButton = headerButton("-", -62)
local closeButton = headerButton("X", -32)

local content = create("Frame", {
    Name = "Content",
    Size = UDim2.new(1, 0, 1, -34),
    Position = UDim2.fromOffset(0, 34),
    BackgroundTransparency = 1,
}, main)

local tabButtons = {}

for index, name in ipairs(TAB_ORDER) do
    local button = create("TextButton", {
        Size = UDim2.new(0.25, -9, 0, 26),
        Position = UDim2.new((index - 1) * 0.25, 12 - (index - 1) * 5, 0, 8),
        BackgroundColor3 = INACTIVE_TAB,
        BorderSizePixel = 0,
        Text = TAB_TITLES[name],
        TextColor3 = Color3.fromRGB(240, 240, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
    }, content)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, button)
    tabButtons[name] = button
end

local function createPage()
    return create("Frame", {
        Size = UDim2.new(1, 0, 1, -42),
        Position = UDim2.fromOffset(0, 42),
        BackgroundTransparency = 1,
    }, content)
end

local reaperPage = createPage()
local housesPage = createPage()
local mobsPage = createPage()
local trialsPage = createPage()

local pages = {reaper = reaperPage, houses = housesPage, mobs = mobsPage, trials = trialsPage}

local function bigButton(parent, text, color)
    local button = create("TextButton", {
        Size = UDim2.new(1, -24, 0, 38),
        Position = UDim2.fromOffset(12, 12),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 16,
    }, parent)
    create("UICorner", {CornerRadius = UDim.new(0, 6)}, button)
    return button
end

local function infoLabel(parent, y)
    return create("TextLabel", {
        Size = UDim2.new(1, -24, 0, 18),
        Position = UDim2.fromOffset(12, y),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Color3.fromRGB(200, 200, 220),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
end

local function inputRow(parent, labelText, y, key, lo, hi, store)
    create("TextLabel", {
        Size = UDim2.new(0, 120, 0, 26),
        Position = UDim2.fromOffset(12, y),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = Color3.fromRGB(200, 200, 220),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
    local box = create("TextBox", {
        Size = UDim2.fromOffset(90, 26),
        Position = UDim2.new(1, -102, 0, y),
        BackgroundColor3 = Color3.fromRGB(36, 36, 50),
        BorderSizePixel = 0,
        Text = tostring(store[key]),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        ClearTextOnFocus = false,
    }, parent)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, box)
    box.FocusLost:Connect(function()
        local value = tonumber(box.Text)
        if value and value == value then
            store[key] = math.clamp(value, lo, hi)
        end
        box.Text = tostring(store[key])
    end)
end

local function smallButton(parent, text, position)
    local button = create("TextButton", {
        Size = UDim2.new(0.5, -17, 0, 26),
        Position = position,
        BackgroundColor3 = INACTIVE_TAB,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Color3.fromRGB(240, 240, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
    }, parent)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, button)
    return button
end

local function createMobList(parent, position, size, state)
    local frame = create("ScrollingFrame", {
        Position = position,
        Size = size,
        BackgroundColor3 = Color3.fromRGB(30, 30, 42),
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, parent)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, frame)
    create("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, frame)

    local list = {Frame = frame, Buttons = {}, Names = {}, Signature = ""}

    local function rebuild(names)
        for _, button in pairs(list.Buttons) do
            button:Destroy()
        end
        list.Buttons = {}
        for index, name in ipairs(names) do
            local button = create("TextButton", {
                Size = UDim2.new(1, -8, 0, 24),
                LayoutOrder = index,
                BackgroundColor3 = GRAY,
                BorderSizePixel = 0,
                Text = name,
                TextColor3 = Color3.fromRGB(255, 255, 255),
                Font = Enum.Font.Gotham,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, frame)
            create("UICorner", {CornerRadius = UDim.new(0, 5)}, button)
            button.MouseButton1Click:Connect(function()
                state.Selected[name] = not state.Selected[name] or nil
            end)
            list.Buttons[name] = button
        end
    end

    function list.update(names, counts)
        local signature = table.concat(names, "|")
        if signature ~= list.Signature then
            list.Signature = signature
            list.Names = names
            rebuild(names)
        end
        local selectedTypes = 0
        local selectedMobs = 0
        for _, name in ipairs(names) do
            local selected = state.Selected[name] == true
            local button = list.Buttons[name]
            if selected then
                selectedTypes = selectedTypes + 1
                selectedMobs = selectedMobs + counts[name]
            end
            if button then
                button.Text = (selected and "  [x]  " or "  [  ]  ") .. name .. "  (" .. counts[name] .. ")"
                button.BackgroundColor3 = selected and GREEN or GRAY
            end
        end
        return selectedTypes, selectedMobs
    end

    return list
end

local reaperUI = {}
reaperUI.Toggle = bigButton(reaperPage, "START", GREEN)
reaperUI.Status = infoLabel(reaperPage, 62)
reaperUI.Target = infoLabel(reaperPage, 84)
reaperUI.Count = infoLabel(reaperPage, 106)
reaperUI.Resets = infoLabel(reaperPage, 128)

inputRow(reaperPage, "Height", 158, "Height", -100, 100, Reaper)
inputRow(reaperPage, "Distance", 190, "Distance", -100, 100, Reaper)
inputRow(reaperPage, "Out wait (s)", 222, "OutWait", 0, 30, Reaper)
inputRow(reaperPage, "In wait (s)", 254, "InWait", 0, 30, Reaper)
inputRow(reaperPage, "Stuck limit (s)", 286, "StuckLimit", 0, 600, Reaper)

reaperUI.Toggle.MouseButton1Click:Connect(function()
    toggleFarm(reaperFarm)
end)

local houseStatusLabel = infoLabel(housesPage, 8)
local houseButtons = {}

for index, house in ipairs(Houses.List) do
    local y = 32 + (index - 1) * 66
    local button = create("TextButton", {
        Size = UDim2.new(1, -24, 0, 28),
        Position = UDim2.fromOffset(12, y),
        BackgroundColor3 = GRAY,
        BorderSizePixel = 0,
        Text = house.Label .. ": OFF",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 14,
    }, housesPage)
    create("UICorner", {CornerRadius = UDim.new(0, 6)}, button)

    inputRow(housesPage, "Every (s)", y + 32, "Seconds", 1, 86400, house)

    button.MouseButton1Click:Connect(function()
        house.Enabled = not house.Enabled
        if house.Enabled then
            house.Last = -math.huge
        end
    end)

    houseButtons[index] = button
end

inputRow(housesPage, "Stay at house (s)", 32 + #Houses.List * 66, "Stay", 0.2, 60, Houses)
inputRow(housesPage, "Stay in front (s)", 64 + #Houses.List * 66, "FrontStay", 0.1, 30, Houses)

local mobsUI = {}
mobsUI.Toggle = bigButton(mobsPage, "START", GREEN)
mobsUI.Status = infoLabel(mobsPage, 62)
mobsUI.Target = infoLabel(mobsPage, 84)
mobsUI.Count = infoLabel(mobsPage, 106)

inputRow(mobsPage, "Height", 132, "Height", -100, 100, Mobs)
inputRow(mobsPage, "Distance", 164, "Distance", -100, 100, Mobs)

local mobsSelectAll = smallButton(mobsPage, "Select all", UDim2.fromOffset(12, 198))
local mobsSelectNone = smallButton(mobsPage, "Select none", UDim2.new(0.5, 5, 0, 198))
local mobList = createMobList(mobsPage, UDim2.fromOffset(12, 232), UDim2.new(1, -24, 1, -244), Mobs)

mobsUI.Toggle.MouseButton1Click:Connect(function()
    toggleFarm(mobsFarm)
end)

mobsSelectAll.MouseButton1Click:Connect(function()
    for _, name in ipairs(mobList.Names) do
        Mobs.Selected[name] = true
    end
end)

mobsSelectNone.MouseButton1Click:Connect(function()
    Mobs.Selected = {}
end)

local trialsUI = {}
trialsUI.Toggle = bigButton(trialsPage, "START", GREEN)
trialsUI.Status = infoLabel(trialsPage, 62)
trialsUI.Target = infoLabel(trialsPage, 84)
trialsUI.Count = infoLabel(trialsPage, 106)

inputRow(trialsPage, "Height", 132, "Height", -100, 100, Trials)
inputRow(trialsPage, "Distance", 164, "Distance", -100, 100, Trials)
inputRow(trialsPage, "Switch after (s)", 196, "SwitchTime", 0, 600, Trials)

local trialsSelectAll = smallButton(trialsPage, "Select all", UDim2.fromOffset(12, 230))
local trialsSelectNone = smallButton(trialsPage, "Select none", UDim2.new(0.5, 5, 0, 230))

trialsUI.Auto = create("TextButton", {
    Size = UDim2.new(1, -24, 0, 26),
    Position = UDim2.fromOffset(12, 264),
    BackgroundColor3 = GREEN,
    BorderSizePixel = 0,
    Text = "",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
}, trialsPage)
create("UICorner", {CornerRadius = UDim.new(0, 5)}, trialsUI.Auto)

local trialList = createMobList(trialsPage, UDim2.fromOffset(12, 298), UDim2.new(1, -24, 1, -310), Trials)

trialsUI.Hint = create("TextLabel", {
    Size = UDim2.new(1, -40, 0, 60),
    Position = UDim2.fromOffset(20, 322),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = Color3.fromRGB(150, 150, 170),
    Font = Enum.Font.Gotham,
    TextSize = 13,
    TextWrapped = true,
}, trialsPage)

trialsUI.Toggle.MouseButton1Click:Connect(function()
    toggleFarm(trialsFarm)
end)

trialsUI.Auto.MouseButton1Click:Connect(function()
    Trials.AutoSelect = not Trials.AutoSelect
end)

trialsSelectAll.MouseButton1Click:Connect(function()
    for _, name in ipairs(trialList.Names) do
        Trials.Selected[name] = true
    end
end)

trialsSelectNone.MouseButton1Click:Connect(function()
    Trials.Selected = {}
end)

local function setTab(name)
    activeTab = name
    for key, page in pairs(pages) do
        page.Visible = key == name
    end
    for key, button in pairs(tabButtons) do
        button.BackgroundColor3 = key == name and ACTIVE_TAB or INACTIVE_TAB
    end
    if not minimized then
        main.Size = getFullSize()
    end
end

for name, button in pairs(tabButtons) do
    button.MouseButton1Click:Connect(function()
        setTab(name)
    end)
end

setTab("reaper")

local dragging = false
local dragStart
local startPos

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

local moveConnection = UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

minimizeButton.MouseButton1Click:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    main.Size = minimized and MIN_SIZE or getFullSize()
end)

closeButton.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

gui.Destroying:Connect(function()
    alive = false
    Houses.Busy = false
    for _, farm in ipairs(Farms) do
        farm.stop()
    end
    moveConnection:Disconnect()
end)

local mounted = pcall(function()
    if typeof(gethui) == "function" then
        gui.Parent = gethui()
    else
        gui.Parent = game:GetService("CoreGui")
    end
end)

if not mounted or not gui.Parent then
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

pcall(function()
    env.FarmHubGui = gui
end)

local function applyFarmStatus(ui, state, statuses)
    ui.Toggle.Text = state.Running and "STOP" or "START"
    ui.Toggle.BackgroundColor3 = state.Running and RED or GREEN
    if state.Running and Houses.Busy then
        ui.Status.Text = "Status: Paused (house teleport)"
        ui.Status.TextColor3 = BLUE
    else
        local info = statuses[state.Status]
        ui.Status.Text = "Status: " .. info[1]
        ui.Status.TextColor3 = info[2]
    end
    local target = state.Target
    ui.Target.Text = "Target: " .. (target and target.Name or "-")
end

local function refreshReaper()
    applyFarmStatus(reaperUI, Reaper, ReaperStatuses)
    reaperUI.Count.Text = "Noobs: " .. #getReaperTargets() .. "   Done: " .. Reaper.Done
    reaperUI.Resets.Text = "Zone resets: " .. Reaper.Resets
end

local function refreshHouses()
    houseStatusLabel.Text = "Status: " .. Houses.Status
    if Houses.Busy then
        houseStatusLabel.TextColor3 = BLUE
    elseif Houses.Status ~= "Idle" then
        houseStatusLabel.TextColor3 = YELLOW
    else
        houseStatusLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
    end
    for index, house in ipairs(Houses.List) do
        local button = houseButtons[index]
        if house.Enabled then
            local remaining = house.Seconds - (os.clock() - house.Last)
            local text = remaining <= 0 and "now" or (math.ceil(remaining) .. "s")
            button.Text = house.Label .. ": ON  (" .. text .. ")"
            button.BackgroundColor3 = GREEN
        else
            button.Text = house.Label .. ": OFF"
            button.BackgroundColor3 = GRAY
        end
    end
end

local function refreshMobs()
    applyFarmStatus(mobsUI, Mobs, MobStatuses)
    local names, counts = listMobTypes()
    local selectedTypes, selectedMobs = mobList.update(names, counts)
    mobsUI.Count.Text = "Selected: " .. selectedTypes .. " (" .. selectedMobs .. " mobs)   Done: " .. Mobs.Done
end

local seenTrialNames = {}

local function refreshTrials()
    applyFarmStatus(trialsUI, Trials, TrialStatuses)
    local names, counts = listTrialMobs()
    for _, name in ipairs(names) do
        if not seenTrialNames[name] then
            seenTrialNames[name] = true
            if Trials.AutoSelect then
                Trials.Selected[name] = true
            end
        end
    end
    local selectedTypes, selectedMobs = trialList.update(names, counts)
    trialsUI.Auto.Text = "Auto-select new mobs: " .. (Trials.AutoSelect and "ON" or "OFF")
    trialsUI.Auto.BackgroundColor3 = Trials.AutoSelect and GREEN or GRAY
    if #names == 0 then
        trialsUI.Hint.Text = #getTrialFolders() == 0 and "Trials folder not found." or "No trial mobs right now.\nThey show up here when a trial runs."
        trialsUI.Hint.Visible = true
    else
        trialsUI.Hint.Visible = false
    end
    trialsUI.Count.Text = "Selected: " .. selectedTypes .. " (" .. selectedMobs .. " mobs)   Done: " .. Trials.Done
end

task.spawn(function()
    while gui.Parent do
        pcall(refreshReaper)
        pcall(refreshHouses)
        pcall(refreshMobs)
        pcall(refreshTrials)
        task.wait(0.2)
    end
end)

task.spawn(houseScheduler)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local FOLDER_NAME = "ReaperNoobs"
local GUI_NAME = "ReaperNoobFarm"
local OUT_POSITION = Vector3.new(-14001.6, 0.8, 8942.0)
local IN_POSITION = Vector3.new(-13986.1, -0.1, 8962.8)
local EMPTY_CONFIRM = 0.25
local FARM_HEIGHT = 398
local HOUSES_HEIGHT = 376
local GUI_WIDTH = 270
local MIN_SIZE = UDim2.fromOffset(GUI_WIDTH, 34)

local env = (getgenv and getgenv()) or _G

if env.ReaperNoobFarmGui then
    pcall(function()
        env.ReaperNoobFarmGui:Destroy()
    end)
end

local Statuses = {
    stopped = {"Stopped", Color3.fromRGB(230, 100, 100)},
    farming = {"Farming", Color3.fromRGB(90, 220, 130)},
    waiting = {"Waiting for noobs", Color3.fromRGB(240, 200, 80)},
    resetting = {"Resetting zone", Color3.fromRGB(110, 170, 255)},
}

local State = {
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
    StuckLimit = 5, -- ennyi mp után reseteli a zónát, ha ugyanazt a noobot ütöd (0 = ki)

    -- House teleport
    HouseBusy = false, -- amíg true, a Reaper farm szünetel
    HouseStatus = "Idle",
    HouseStay = 2, -- ennyi mp-ig marad a háznál
    HouseFrontStay = 0.5, -- ennyi mp-ig marad a ház előtt, mielőtt bemegy
    Houses = {
        {Label = "House 1", Front = Vector3.new(-14131.2, 0.8, 8652.2), Position = Vector3.new(-14131.6, 1.4, 8644.8), Enabled = false, Seconds = 300, Last = -math.huge},
        {Label = "House 2", Front = Vector3.new(-14127.5, 0.8, 8894.1), Position = Vector3.new(-14127.6, 1.4, 8902.1), Enabled = false, Seconds = 300, Last = -math.huge},
        {Label = "House 3", Front = Vector3.new(-14232.0, 0.8, 8784.8), Position = Vector3.new(-14236.9, 1.3, 8784.6), Enabled = false, Seconds = 300, Last = -math.huge},
    },
}

local alive = true

----------------------------------------------------------------------
-- Közös segédek
----------------------------------------------------------------------

local function getHRP()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function placeAt(hrp, position)
    hrp.CFrame = CFrame.new(position)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

-- Ha éppen house teleport zajlik, a farm itt megvárja a végét.
-- Visszaadja, mennyi ideig várt (hogy a stuck időzítő ne számolja bele).
local function waitForHouse(active)
    if not State.HouseBusy then
        return 0
    end
    local startedAt = os.clock()
    while State.HouseBusy and active() do
        RunService.Heartbeat:Wait()
    end
    return os.clock() - startedAt
end

----------------------------------------------------------------------
-- Noob farm
----------------------------------------------------------------------

local function getRoot(model)
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function isPresent(model)
    local parent = model.Parent
    return parent ~= nil and parent.Name == FOLDER_NAME and model:IsDescendantOf(workspace)
end

local function isCorpse(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health <= 0
end

local function getTargets()
    local list = {}
    local folder = workspace:FindFirstChild(FOLDER_NAME)
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") and getRoot(child) then
                table.insert(list, child)
            end
        end
    end
    return list
end

local function hasTargets()
    return #getTargets() > 0
end

local function pickTarget(hrp)
    local best
    local bestScore
    for _, model in ipairs(getTargets()) do
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

local function standAt(hrp, root)
    local targetPos = root.Position
    local pos = targetPos + Vector3.new(0, State.Height, State.Distance)
    if math.abs(State.Distance) > 0.05 then
        hrp.CFrame = CFrame.lookAt(pos, Vector3.new(targetPos.X, pos.Y, targetPos.Z))
    else
        hrp.CFrame = CFrame.new(pos)
    end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
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
    State.Status = "resetting"
    State.Target = nil
    State.Resets = State.Resets + 1
    holdAt(OUT_POSITION, State.OutWait, active)
    if not active() then
        return
    end
    holdAt(IN_POSITION, State.InWait, active, hasTargets)
end

local function startFarm()
    if State.Running then
        return
    end
    State.Running = true
    State.Session = State.Session + 1
    local session = State.Session

    local function active()
        return State.Running and State.Session == session
    end

    task.spawn(function()
        local emptySince = nil
        while active() do
            waitForHouse(active)
            if not active() then
                return
            end
            local hrp = getHRP()
            local target = hrp and pickTarget(hrp)
            if target then
                emptySince = nil
                State.Target = target
                State.Status = "farming"
                local humanoid = target:FindFirstChildOfClass("Humanoid")
                local watchHealth = humanoid ~= nil and humanoid.Health > 0
                local targetStartedAt = os.clock()
                local stuck = false
                while active() and isPresent(target) do
                    targetStartedAt = targetStartedAt + waitForHouse(active)
                    if not active() then
                        break
                    end
                    if watchHealth and humanoid.Health <= 0 then
                        break
                    end
                    if State.StuckLimit > 0 and os.clock() - targetStartedAt >= State.StuckLimit then
                        stuck = true
                        break
                    end
                    local currentHRP = getHRP()
                    local root = getRoot(target)
                    if not root then
                        break
                    end
                    if currentHRP then
                        pcall(standAt, currentHRP, root)
                    end
                    RunService.Heartbeat:Wait()
                end
                if not active() then
                    return
                end
                State.Target = nil
                if stuck then
                    resetZone(active)
                    emptySince = nil
                else
                    State.Done = State.Done + 1
                end
            else
                State.Target = nil
                State.Status = "waiting"
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

local function stopFarm()
    State.Running = false
    State.Session = State.Session + 1
    State.Target = nil
    State.Status = "stopped"
end

----------------------------------------------------------------------
-- House teleport
----------------------------------------------------------------------

local function visitHouse(house)
    -- elmentjük, honnan teleportálunk el (csak akkor kell, ha nem fut a farm)
    local startHRP = getHRP()
    local origin = startHRP and startHRP.CFrame

    State.HouseBusy = true -- a farm szünetel
    State.HouseStatus = "Teleporting to " .. house.Label

    pcall(function()
        -- 1) először a ház elé, 2) utána a házba (a beégetett koordinátára)
        local stages = {
            {position = house.Front, seconds = State.HouseFrontStay},
            {position = house.Position, seconds = State.HouseStay},
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

    -- ha nem fut a farm, visszateleportál oda, ahonnan elindult
    if origin and alive and not State.Running then
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
    State.HouseBusy = false
    State.HouseStatus = "Idle"
end

local function houseScheduler()
    while alive do
        local due = nil
        for _, house in ipairs(State.Houses) do
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

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------

local function create(className, props, parent)
    local instance = Instance.new(className)
    for key, value in pairs(props) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local ACTIVE_TAB = Color3.fromRGB(90, 80, 200)
local INACTIVE_TAB = Color3.fromRGB(44, 44, 60)
local GREEN = Color3.fromRGB(46, 160, 90)
local RED = Color3.fromRGB(200, 70, 70)
local GRAY = Color3.fromRGB(60, 60, 80)

local activeTab = "farm"
local minimized = false

local function getFullSize()
    return UDim2.fromOffset(GUI_WIDTH, activeTab == "farm" and FARM_HEIGHT or HOUSES_HEIGHT)
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
    Text = "Reaper Noob Farm",
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

-- Tabs
local function tabButton(text, position)
    local button = create("TextButton", {
        Size = UDim2.new(0.5, -17, 0, 26),
        Position = position,
        BackgroundColor3 = INACTIVE_TAB,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Color3.fromRGB(240, 240, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
    }, content)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, button)
    return button
end

local farmTab = tabButton("Farm", UDim2.fromOffset(12, 8))
local housesTab = tabButton("Houses", UDim2.new(0.5, 5, 0, 8))

local function createPage()
    return create("Frame", {
        Size = UDim2.new(1, 0, 1, -42),
        Position = UDim2.fromOffset(0, 42),
        BackgroundTransparency = 1,
    }, content)
end

local farmPage = createPage()
local housesPage = createPage()

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

-- store: melyik táblában van az érték (alapból State)
local function inputRow(parent, labelText, y, key, lo, hi, store)
    store = store or State
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

-- Farm page
local toggleButton = bigButton(farmPage, "START", GREEN)

local statusLabel = infoLabel(farmPage, 62)
local targetLabel = infoLabel(farmPage, 84)
local countLabel = infoLabel(farmPage, 106)
local resetLabel = infoLabel(farmPage, 128)

inputRow(farmPage, "Height", 158, "Height", -100, 100)
inputRow(farmPage, "Distance", 190, "Distance", -100, 100)
inputRow(farmPage, "Out wait (s)", 222, "OutWait", 0, 30)
inputRow(farmPage, "In wait (s)", 254, "InWait", 0, 30)
inputRow(farmPage, "Stuck limit (s)", 286, "StuckLimit", 0, 600)

-- Houses page
local houseStatusLabel = infoLabel(housesPage, 8)
local houseButtons = {}

for index, house in ipairs(State.Houses) do
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
            house.Last = -math.huge -- bekapcsoláskor rögtön teleportál
        end
    end)

    houseButtons[index] = button
end

inputRow(housesPage, "Stay at house (s)", 32 + #State.Houses * 66, "HouseStay", 0.2, 60)
inputRow(housesPage, "Stay in front (s)", 64 + #State.Houses * 66, "HouseFrontStay", 0.1, 30)

-- Tab switching
local function setTab(name)
    activeTab = name
    farmPage.Visible = name == "farm"
    housesPage.Visible = name == "houses"
    farmTab.BackgroundColor3 = name == "farm" and ACTIVE_TAB or INACTIVE_TAB
    housesTab.BackgroundColor3 = name == "houses" and ACTIVE_TAB or INACTIVE_TAB
    if not minimized then
        main.Size = getFullSize()
    end
end

farmTab.MouseButton1Click:Connect(function()
    setTab("farm")
end)

housesTab.MouseButton1Click:Connect(function()
    setTab("houses")
end)

setTab("farm")

-- Dragging
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

toggleButton.MouseButton1Click:Connect(function()
    if State.Running then
        stopFarm()
    else
        startFarm()
    end
end)

closeButton.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

gui.Destroying:Connect(function()
    alive = false
    State.HouseBusy = false
    stopFarm()
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
    env.ReaperNoobFarmGui = gui
end)

local function refresh()
    -- Farm
    local running = State.Running
    local info = Statuses[State.Status]
    toggleButton.Text = running and "STOP" or "START"
    toggleButton.BackgroundColor3 = running and RED or GREEN
    if running and State.HouseBusy then
        statusLabel.Text = "Status: Paused (house teleport)"
        statusLabel.TextColor3 = Color3.fromRGB(110, 170, 255)
    else
        statusLabel.Text = "Status: " .. info[1]
        statusLabel.TextColor3 = info[2]
    end
    local target = State.Target
    targetLabel.Text = "Target: " .. (target and target.Name or "-")
    countLabel.Text = "Noobs: " .. #getTargets() .. "   Done: " .. State.Done
    resetLabel.Text = "Zone resets: " .. State.Resets

    -- Houses
    houseStatusLabel.Text = "Status: " .. State.HouseStatus
    if State.HouseBusy then
        houseStatusLabel.TextColor3 = Color3.fromRGB(110, 170, 255)
    elseif State.HouseStatus ~= "Idle" then
        houseStatusLabel.TextColor3 = Color3.fromRGB(240, 200, 80)
    else
        houseStatusLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
    end
    for index, house in ipairs(State.Houses) do
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

task.spawn(function()
    while gui.Parent do
        pcall(refresh)
        task.wait(0.2)
    end
end)

task.spawn(houseScheduler)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local FOLDER_NAME = "ReaperNoobs"
local GUI_NAME = "ReaperNoobFarm"
local OUT_POSITION = Vector3.new(-14001.6, 0.8, 8942.0)
local IN_POSITION = Vector3.new(-13986.1, -0.1, 8962.8)
local EMPTY_CONFIRM = 0.25
local FULL_SIZE = UDim2.fromOffset(270, 324)
local MIN_SIZE = UDim2.fromOffset(270, 34)

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
}

local function getHRP()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

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

local function placeAt(hrp, position)
    hrp.CFrame = CFrame.new(position)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function holdAt(position, seconds, active, stopWhen)
    local startedAt = os.clock()
    repeat
        local hrp = getHRP()
        if hrp then
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
            local hrp = getHRP()
            local target = hrp and pickTarget(hrp)
            if target then
                emptySince = nil
                State.Target = target
                State.Status = "farming"
                local humanoid = target:FindFirstChildOfClass("Humanoid")
                local watchHealth = humanoid ~= nil and humanoid.Health > 0
                while active() and isPresent(target) do
                    if watchHealth and humanoid.Health <= 0 then
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
                State.Done = State.Done + 1
                State.Target = nil
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

local function create(className, props, parent)
    local instance = Instance.new(className)
    for key, value in pairs(props) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local gui = create("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
})

local main = create("Frame", {
    Name = "Main",
    Size = FULL_SIZE,
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

local toggleButton = create("TextButton", {
    Size = UDim2.new(1, -24, 0, 38),
    Position = UDim2.fromOffset(12, 12),
    BackgroundColor3 = Color3.fromRGB(46, 160, 90),
    BorderSizePixel = 0,
    Text = "START",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 16,
}, content)
create("UICorner", {CornerRadius = UDim.new(0, 6)}, toggleButton)

local function infoLabel(y)
    return create("TextLabel", {
        Size = UDim2.new(1, -24, 0, 18),
        Position = UDim2.fromOffset(12, y),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Color3.fromRGB(200, 200, 220),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, content)
end

local statusLabel = infoLabel(62)
local targetLabel = infoLabel(84)
local countLabel = infoLabel(106)
local resetLabel = infoLabel(128)

local function inputRow(labelText, y, key, lo, hi)
    create("TextLabel", {
        Size = UDim2.new(0, 120, 0, 26),
        Position = UDim2.fromOffset(12, y),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = Color3.fromRGB(200, 200, 220),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, content)
    local box = create("TextBox", {
        Size = UDim2.fromOffset(90, 26),
        Position = UDim2.new(1, -102, 0, y),
        BackgroundColor3 = Color3.fromRGB(36, 36, 50),
        BorderSizePixel = 0,
        Text = tostring(State[key]),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        ClearTextOnFocus = false,
    }, content)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, box)
    box.FocusLost:Connect(function()
        local value = tonumber(box.Text)
        if value and value == value then
            State[key] = math.clamp(value, lo, hi)
        end
        box.Text = tostring(State[key])
    end)
end

inputRow("Height", 158, "Height", -100, 100)
inputRow("Distance", 190, "Distance", -100, 100)
inputRow("Out wait (s)", 222, "OutWait", 0, 30)
inputRow("In wait (s)", 254, "InWait", 0, 30)

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

local minimized = false

minimizeButton.MouseButton1Click:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    main.Size = minimized and MIN_SIZE or FULL_SIZE
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
    local running = State.Running
    local info = Statuses[State.Status]
    toggleButton.Text = running and "STOP" or "START"
    toggleButton.BackgroundColor3 = running and Color3.fromRGB(200, 70, 70) or Color3.fromRGB(46, 160, 90)
    statusLabel.Text = "Status: " .. info[1]
    statusLabel.TextColor3 = info[2]
    local target = State.Target
    targetLabel.Text = "Target: " .. (target and target.Name or "-")
    countLabel.Text = "Noobs: " .. #getTargets() .. "   Done: " .. State.Done
    resetLabel.Text = "Zone resets: " .. State.Resets
end

task.spawn(function()
    while gui.Parent do
        pcall(refresh)
        task.wait(0.2)
    end
end)

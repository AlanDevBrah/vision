local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local STUDS_PER_METER = 2.7777777777777777
local UPDATE_INTERVAL = 0.15
local OWNER_KEY = "__VISION_OWNER"
local OWNER_MAGIC = "VISION_OWNER"
local OWNER_SCHEMA = 3
local PENDING_OWNER_KEY = "__VISION_PENDING_OWNER"
local ownerToken = HttpService:GenerateGUID(false)

local resolveVehicleMuzzleAndShell = nil
local playerVehicle = nil
local currentCharacter = nil
local function guiContainers()
    local found = { [CoreGui] = true }
    if typeof(gethui) == "function" then
        local ok, container = pcall(gethui)
        if ok and typeof(container) == "Instance" then
            found[container] = true
        end
    end
    return found
end

local function projectUiArtifacts()
    local screens = {}
    local loose = {}
    for container in pairs(guiContainers()) do
        for _, descendant in container:GetDescendants() do

            local tagged = descendant:GetAttribute("VisionOwner") ~= nil
                or descendant:GetAttribute("UltronOwner") ~= nil
            local canonical = descendant.Name == "Ultron v2" or descendant.Name == "Ultron v3"
            if tagged or canonical then
                local cursor = descendant
                while cursor and not cursor:IsA("ScreenGui") do
                    cursor = cursor.Parent
                end
                if cursor then
                    screens[cursor] = true
                else
                    loose[descendant] = true
                end
            end
        end
    end
    return screens, loose
end

local function findProjectScreenGuis()
    local screens = projectUiArtifacts()
    return screens
end

local function countProjectVisuals()
    local count = 0
    for _, folderName in ipairs({ "SpawnedVehicles", "SpawnedPlayers" }) do
        local folder = Workspace:FindFirstChild(folderName)
        if folder then
            for _, descendant in folder:GetDescendants() do
                local tagged = descendant:GetAttribute("VisionOwner") ~= nil
                    or descendant:GetAttribute("UltronOwner") ~= nil
                local charm = descendant:IsA("Highlight")
                    and (descendant.Name == "VisionV3" or descendant.Name == "Ultron" or descendant.Name == "UltronV3")
                local info = descendant:IsA("BillboardGui")
                    and (descendant.Name == "VisionInfoV3" or descendant.Name == "UltronInfoV3")
                if tagged or charm or info then
                    count += 1
                end
            end
        end
    end
    return count
end

local function countProjectUiArtifacts()
    local screens, loose = projectUiArtifacts()
    local count = 0
    for _ in pairs(screens) do
        count += 1
    end
    for _ in pairs(loose) do
        count += 1
    end
    return count
end

local function validOwnerRecord(candidate)
    return type(candidate) == "table"

        and (candidate.magic == OWNER_MAGIC or candidate.magic == "ULTRON_OWNER")
        and candidate.schema == OWNER_SCHEMA
        and type(candidate.token) == "string"
        and candidate.token ~= ""
        and type(candidate.stop) == "function"
end

local function stopPreviousOwner()

    for _, key in ipairs({ OWNER_KEY, "__ULTRON_OWNER" }) do
        local previous = rawget(_G, key)
        if previous ~= nil then
            if not validOwnerRecord(previous) then
                error("[Vision] Existing owner is malformed; relog before retrying")
            end
            local previousStop = previous.stop
            local ok, result = pcall(previousStop, "owner-handoff")
            if not ok or result ~= true then
                error("[Vision] Previous owner cleanup is incomplete; relog or retry after it finishes")
            end
            local clean = previous.cleanupComplete == true
                and previous.cleanupPending == false
                and previous.activeExternalCalls == 0
                and #previous.connections == 0
                and next(previous.visuals) == nil
                and previous.window == nil
            if not clean or rawget(_G, key) == previous then
                error("[Vision] Previous owner retained resources; relog before retrying")
            end
        end
    end

    for _, hookKey in ipairs({ "VISION_UNLOAD", "ULTRON_UNLOAD" }) do
        local legacyStop = rawget(_G, hookKey)
        if legacyStop ~= nil then
            if type(legacyStop) ~= "function" then
                error("[Vision] Existing unload hook is malformed; relog before retrying")
            end
            local ok, result = pcall(legacyStop, "v3-handoff")
            if not ok or result ~= true then
                error("[Vision] Legacy cleanup is incomplete; relog or retry after it finishes")
            end
            if rawget(_G, hookKey) == legacyStop then
                error("[Vision] Legacy unload hook is still registered; relog before retrying")
            end
        end
    end
end

local function assertCleanStart()
    local uiArtifacts = countProjectUiArtifacts()
    local visuals = countProjectVisuals()
    if uiArtifacts > 0 or visuals > 0 then
        error(string.format(
            "[Vision] Found %d unowned UI artifacts and %d unowned visuals; relog before retrying",
            uiArtifacts,
            visuals
        ))
    end
end

stopPreviousOwner()
assertCleanStart()

local RAYFIELD_URL = "https://sirius.menu/gen2"
local RAYFIELD_CACHE = "mcp/mtc-rayfield-gen2-v1.1.0-mtc6.luau"
local RAYFIELD_ORIGINAL_SHA256 = "e3c337e969e6c4c0de91a77156201094568be55fdfe2669368c48c1d8169d0a6"

local RAYFIELD_SHA256 = "3443571b34c47a58c8a1a1d32b6381a7362a18f5b17c43f30d043ebb59d0e9ea"
local cfg = {
    playerCharm = true,
    playerInfo = true,
    playerDistance = 1500,
    vehicleCharm = true,
    vehicleInfo = true,
    vehicleDistance = 2500,
    playerTeamcheck = true,
    playerWallcheck = true,
    vehicleTeamcheck = true,
    vehicleWallcheck = true,
    fillTransparency = 0.50,
    bulletLine = false,
    bulletLineDistance = 2500,

    bulletLineThickness = 1.0,
    bulletLineImpactSize = 1.0,
    penIndicator = false,
    penMode = "impact",
    freecamMode = "scout",
    freecamSpeed = 60,
    freecamFov = 70,
}

local COLOR_ENEMY = Color3.fromRGB(255, 0, 0)
local COLOR_FRIENDLY = Color3.fromRGB(0, 255, 0)

local COLOR_BRAND = Color3.fromRGB(30, 215, 191)

local VISION_ICON_ID = 134948079387488

local VISION_THEME = {

    AccentColor = COLOR_BRAND,
    AccentStroke = COLOR_BRAND,

    AccentGlow = 0.55,

    SliderProgress = ColorSequence.new(COLOR_BRAND, COLOR_BRAND),
}

local mouseAim = {
    unlocked = false,
    soloSet = false,
}

function mouseAim.getSwitch()
    local ngd = game:GetService("ReplicatedFirst"):FindFirstChild("NewGuiData")
    if not ngd then return nil end
    local gunner = ngd:FindFirstChild("Gunner")
    if not gunner then return nil end
    local switches = gunner:FindFirstChild("Switches")
    if not switches then return nil end
    return switches:FindFirstChild("MouseAim")
end

function mouseAim.getState()
    local ma = mouseAim.getSwitch()
    if not ma then return nil, nil end
    local en = ma:FindFirstChild("Enabled")
    local dt = ma:FindFirstChild("Data")

    local enV = en and en.Value
    local dtV = dt and dt.Value
    return (enV ~= nil and enV or nil), (dtV ~= nil and dtV or nil)
end

function mouseAim.isSeated()
    local character = LocalPlayer.Character
    if not character then return false end
    local humanoid = character:FindFirstChild("Humanoid")
    return humanoid and humanoid.SeatPart ~= nil
end

function mouseAim.fireSignal()
    local ma = mouseAim.getSwitch()
    if not ma then return false end
    local sig = ma:FindFirstChild("Signal")
    if not sig or sig.ClassName ~= "BindableEvent" then return false end
    local ok = pcall(function()
        sig:Fire()
    end)
    return ok
end

function mouseAim.setSolo(value)
    pcall(function()
        Workspace:SetAttribute("Solo", value)
    end)
    pcall(function()
        LocalPlayer:SetAttribute("Solo", value)
    end)
    mouseAim.soloSet = value
end

local function getMouseAimState()
    return mouseAim.getState()
end

local function enableMouseAim()
    mouseAim.setSolo(true)
    local seated = mouseAim.isSeated()

    local enabled, data = mouseAim.getState()
    if seated and enabled ~= true then
        return "seated-no-rebind"
    end
    if enabled == true and data ~= true then
        mouseAim.fireSignal()
    end
    return "enabled"
end

local function disableMouseAim()
    local _, data = mouseAim.getState()
    if data == true then
        mouseAim.fireSignal()
    end
    mouseAim.setSolo(false)
    return "disabled"
end
local owner = {
    magic = OWNER_MAGIC,
    schema = OWNER_SCHEMA,
    token = ownerToken,
    stopped = false,
    stop = nil,
    stopReason = nil,
    initializing = true,
    initialized = false,
    activeExternalCalls = 0,
    cleanupRunning = false,
    cleanupPending = false,
    cleanupComplete = false,
    cleanupError = nil,
    window = nil,
    connections = {},
    visuals = {},
    cfg = cfg,
    refreshErrorCount = 0,
    lastRefreshError = nil,
}

local function isCurrentGeneration()
    return not owner.stopped and rawget(_G, OWNER_KEY) == owner
end

local function assertCurrentGeneration(stage)
    if not isCurrentGeneration() then
        error("[Vision] generation-cancelled:" .. tostring(stage))
    end
end

local function destroyInstance(instance)
    if not instance then
        return true
    end
    local destroyed = pcall(function()
        instance:Destroy()
    end)
    if not destroyed then
        return false
    end
    local stateOk, parent = pcall(function()
        return instance.Parent
    end)
    return not stateOk or parent == nil
end

local function removeVisual(model)
    local entry = owner.visuals[model]
    if not entry then
        return true
    end

    local highlightGone = destroyInstance(entry.highlight)
    local textGone = destroyInstance(entry.text)
    local labelGone = destroyInstance(entry.label)
    if highlightGone then
        entry.highlight = nil
    end
    if textGone then
        entry.text = nil
    end
    if labelGone then
        entry.label = nil
    end
    if not entry.highlight and not entry.label and not entry.text then
        owner.visuals[model] = nil
    end
    return highlightGone and textGone and labelGone
end

local function clearVisuals()
    local models = {}
    for model in pairs(owner.visuals) do
        table.insert(models, model)
    end
    local clean = true
    for _, model in models do
        if not removeVisual(model) then
            clean = false
        end
    end
    return clean
end

local function disconnectTrackedConnections()
    local remaining = {}
    for _, connection in ipairs(owner.connections) do
        local disconnected = pcall(function()
            if connection.Connected then
                connection:Disconnect()
            end
        end)
        local stateOk, connected = pcall(function()
            return connection.Connected
        end)
        if not disconnected or (stateOk and connected) then
            table.insert(remaining, connection)
        end
    end
    owner.connections = remaining
    return #remaining == 0
end

local function tagProjectScreens()
    for screen in pairs(findProjectScreenGuis()) do
        pcall(function()
            screen:SetAttribute("VisionOwner", ownerToken)
        end)
    end
end

local function destroyOwnedFallbackArtifacts()
    local clean = true

    for _, folderName in ipairs({ "SpawnedVehicles", "SpawnedPlayers" }) do
        local folder = Workspace:FindFirstChild(folderName)
        if folder then
            local candidates = {}
            for _, descendant in folder:GetDescendants() do
                local owned = descendant:GetAttribute("VisionOwner") == ownerToken
                if owned then
                    table.insert(candidates, descendant)
                end
            end
            for _, descendant in candidates do
                if not destroyInstance(descendant) then
                    clean = false
                end
            end
        end
    end

    local screens, looseUi = projectUiArtifacts()
    for screen in pairs(screens) do
        local tagged = screen:GetAttribute("VisionOwner") == ownerToken
        if tagged and not destroyInstance(screen) then
            clean = false
        end
    end
    for artifact in pairs(looseUi) do
        if artifact:GetAttribute("VisionOwner") == ownerToken and not destroyInstance(artifact) then
            clean = false
        end
    end

    local blFolder = Workspace:FindFirstChild("VisionBulletLines")
    if blFolder and blFolder:GetAttribute("VisionOwner") == ownerToken then
        if not destroyInstance(blFolder) then
            clean = false
        end

        rawset(_G, "__VISION_POOL_INVALIDATED", true)
    end

    local penFolder = Workspace:FindFirstChild("VisionPenIndicator")
    if penFolder and penFolder:GetAttribute("VisionOwner") == ownerToken then
        if not destroyInstance(penFolder) then
            clean = false
        end
    end

    return clean
end

local function ownedArtifactsRemain()
    for _, folderName in ipairs({ "SpawnedVehicles", "SpawnedPlayers" }) do
        local folder = Workspace:FindFirstChild(folderName)
        if folder then
            for _, descendant in folder:GetDescendants() do
                if descendant:GetAttribute("VisionOwner") == ownerToken then
                    return true
                end
            end
        end
    end
    local screens, looseUi = projectUiArtifacts()
    for screen in pairs(screens) do
        if screen:GetAttribute("VisionOwner") == ownerToken then
            return true
        end
    end
    for artifact in pairs(looseUi) do
        if artifact:GetAttribute("VisionOwner") == ownerToken then
            return true
        end
    end
    local blFolder = Workspace:FindFirstChild("VisionBulletLines")
    if blFolder and blFolder:GetAttribute("VisionOwner") == ownerToken then
        return true
    end
    local penFolder = Workspace:FindFirstChild("VisionPenIndicator")
    if penFolder and penFolder:GetAttribute("VisionOwner") == ownerToken then
        return true
    end
    return false
end

local function stop(reason)

    local freecamClean = true
    local freecamStop = rawget(_G, "__VISION_DISABLE_FREECAM")
    if type(freecamStop) == "function" then
        local freecamOk, freecamResult = pcall(freecamStop)
        freecamClean = freecamOk and freecamResult ~= false
    end

    local reloadAssistClean = true

    local reloadController = rawget(owner, "reloadAssist")
    if type(reloadController) == "table" and type(reloadController.stop) == "function" then
        reloadAssistClean = pcall(function()
            reloadController.stop()
        end)
    end
    local mouseAimClean = true
    if mouseAim.unlocked or mouseAim.soloSet then
        local ok = pcall(disableMouseAim)
        if not ok then mouseAimClean = false end
        mouseAim.unlocked = false

        pcall(function() Workspace:SetAttribute("Solo", false) end)
        pcall(function() LocalPlayer:SetAttribute("Solo", false) end)
        mouseAim.soloSet = false
    else

        local wsSolo = nil
        local lpSolo = nil
        pcall(function() wsSolo = Workspace:GetAttribute("Solo") end)
        pcall(function() lpSolo = LocalPlayer:GetAttribute("Solo") end)
        if wsSolo == true or lpSolo == true then
            local ok2 = pcall(disableMouseAim)
            if not ok2 then
                pcall(function() Workspace:SetAttribute("Solo", false) end)
                pcall(function() LocalPlayer:SetAttribute("Solo", false) end)
                mouseAimClean = false
            end
        end

        local en, dt = nil, nil
        pcall(function() en, dt = getMouseAimState() end)
        if dt == true then

            local ok3 = pcall(mouseAim.fireSignal)
            if not ok3 then mouseAimClean = false end
        end
    end

    if owner.cleanupComplete then
        return mouseAimClean and reloadAssistClean
    end
    if owner.cleanupRunning then
        owner.cleanupPending = true
        return false
    end

    owner.stopped = true
    owner.stopReason = reason or owner.stopReason or "requested"
    owner.cleanupRunning = true
    owner.cleanupPending = true

    local connectionsClean = disconnectTrackedConnections()
    local visualsClean = clearVisuals()

    local windowClean = true
    if owner.window then
        windowClean = pcall(function()
            owner.window:Unload()
        end)
        local canReleaseWindow = owner.activeExternalCalls == 0 and not owner.initializing
        if windowClean and canReleaseWindow then
            owner.window = nil
        end
    end

    local fallbackClean = destroyOwnedFallbackArtifacts()
    local artifactsClean = not ownedArtifactsRemain()
    local clean = freecamClean
        and mouseAimClean
        and reloadAssistClean
        and connectionsClean
        and visualsClean
        and windowClean
        and fallbackClean
        and artifactsClean
        and not owner.initializing
        and owner.activeExternalCalls == 0
        and #owner.connections == 0
        and next(owner.visuals) == nil
        and owner.window == nil

    owner.cleanupRunning = false
    owner.cleanupPending = not clean
    owner.cleanupComplete = clean

    if clean then
        owner.cleanupError = nil
        if rawget(_G, PENDING_OWNER_KEY) == ownerToken then
            rawset(_G, PENDING_OWNER_KEY, nil)
        end
        if rawget(_G, OWNER_KEY) == owner then
            rawset(_G, OWNER_KEY, nil)
        end
        if rawget(_G, "VISION_UNLOAD") == stop then
            rawset(_G, "VISION_UNLOAD", nil)
        end
        if rawget(_G, "__VISION_DISABLE_FREECAM") == freecamStop then
            rawset(_G, "__VISION_DISABLE_FREECAM", nil)
        end
    else
        owner.cleanupError = "cleanup-pending"
    end

    return clean
end

owner.stop = stop
rawset(_G, OWNER_KEY, owner)
rawset(_G, "VISION_UNLOAD", stop)
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local FC = {
    BIND_NAME = "__VisionFreecam_" .. ownerToken,
    SINK_NAME = "__VisionFreecamSink_" .. ownerToken,
    RENDER_PRIORITY = 1000,
    SINK_PRIORITY = 3000,
    MOUSE_SENSITIVITY = 0.0025,
    FOCUS_DISTANCE = 1000,
    SCOUT_KEYS = {
        Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
        Enum.KeyCode.Q, Enum.KeyCode.E,
    },
}

local freecam = {
    enabled = false,
    mode = cfg.freecamMode,
    speed = cfg.freecamSpeed,
    fov = cfg.freecamFov,
    camera = nil,
    cframe = nil,
    pitch = 0,
    yaw = 0,
    looking = false,
    controls = nil,
    saved = nil,
    inputConnections = {},
    lifecycleConnections = {},
    sinkBound = false,
}

local disableFreecam

local function getControlModule()
    local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
    if not playerModule then return nil end
    local ok, module = pcall(require, playerModule)
    if not ok or type(module) ~= "table" or type(module.GetControls) ~= "function" then
        return nil
    end
    local controlsOk, controls = pcall(function()
        return module:GetControls()
    end)
    if not controlsOk or type(controls) ~= "table" then
        return nil
    end
    return controls
end

local function disconnectFreecamInputs()
    for _, connection in ipairs(freecam.inputConnections) do
        pcall(function()
            if connection.Connected then
                connection:Disconnect()
            end
        end)
    end
    table.clear(freecam.inputConnections)
    freecam.looking = false
end

local function disconnectFreecamLifecycle()
    for _, connection in ipairs(freecam.lifecycleConnections) do
        pcall(function()
            if connection.Connected then
                connection:Disconnect()
            end
        end)
    end
    table.clear(freecam.lifecycleConnections)
end

local function unbindMovementSink()
    if not freecam.sinkBound then
        return
    end
    pcall(function()
        ContextActionService:UnbindAction(FC.SINK_NAME)
    end)
    freecam.sinkBound = false
end

local function bindMovementSink()
    if freecam.sinkBound then
        return
    end
    local ok = pcall(function()
        ContextActionService:BindActionAtPriority(
            FC.SINK_NAME,
            function()
                return Enum.ContextActionResult.Sink
            end,
            false,
            FC.SINK_PRIORITY,
            table.unpack(FC.SCOUT_KEYS)
        )
    end)
    freecam.sinkBound = ok
end

local function setMouseLook(value)
    freecam.looking = value == true
    if freecam.looking then
        pcall(function()
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            UserInputService.MouseIconEnabled = false
        end)
    else
        pcall(function()
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = true
        end)
    end
end

local function connectFreecamInputs()
    disconnectFreecamInputs()

    local began = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if owner.stopped or not freecam.enabled or gameProcessed then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            setMouseLook(true)
        end
    end)
    local ended = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            setMouseLook(false)
        end
    end)
    table.insert(freecam.inputConnections, began)
    table.insert(freecam.inputConnections, ended)
end

local function connectFreecamLifecycle()
    disconnectFreecamLifecycle()
    local characterAdded = LocalPlayer.CharacterAdded:Connect(function(character)
        if freecam.enabled then
            disableFreecam()
            return
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            table.insert(freecam.lifecycleConnections, humanoid.Died:Connect(function()
                if freecam.enabled then
                    disableFreecam()
                end
            end))
        end
    end)
    table.insert(freecam.lifecycleConnections, characterAdded)

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        table.insert(freecam.lifecycleConnections, humanoid.Died:Connect(function()
            if freecam.enabled then
                disableFreecam()
            end
        end))
    end
end

local function movementVector()
    local forward, backward, left, right, down, up
    if freecam.mode == "turret" then
        forward = Enum.KeyCode.I
        backward = Enum.KeyCode.K
        left = Enum.KeyCode.J
        right = Enum.KeyCode.L
        down = Enum.KeyCode.U
        up = Enum.KeyCode.O
    else
        forward = Enum.KeyCode.W
        backward = Enum.KeyCode.S
        left = Enum.KeyCode.A
        right = Enum.KeyCode.D
        down = Enum.KeyCode.Q
        up = Enum.KeyCode.E
    end

    local x = (UserInputService:IsKeyDown(right) and 1 or 0)
        - (UserInputService:IsKeyDown(left) and 1 or 0)
    local y = (UserInputService:IsKeyDown(up) and 1 or 0)
        - (UserInputService:IsKeyDown(down) and 1 or 0)

    local z = (UserInputService:IsKeyDown(backward) and 1 or 0)
        - (UserInputService:IsKeyDown(forward) and 1 or 0)
    local vector = Vector3.new(x, y, z)
    if vector.Magnitude > 1 then
        vector = vector.Unit
    end
    return vector
end

local function applyControlMode()
    if not freecam.controls then
        freecam.controls = getControlModule()
    end
    if not freecam.controls then
        return false
    end
    local ok = pcall(function()
        if freecam.mode == "scout" then
            freecam.controls:Disable()
        else

            freecam.controls:Enable()
        end
    end)

    if freecam.mode == "scout" then
        bindMovementSink()
    else
        unbindMovementSink()
    end
    return ok
end

local function renderFreecam(deltaTime)
    if owner.stopped or not freecam.enabled then
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    freecam.camera = camera

    if freecam.looking then
        local mouseDelta = UserInputService:GetMouseDelta()
        freecam.yaw -= mouseDelta.X * FC.MOUSE_SENSITIVITY
        freecam.pitch = math.clamp(
            freecam.pitch - mouseDelta.Y * FC.MOUSE_SENSITIVITY,
            -math.rad(89),
            math.rad(89)
        )
    end

    local orientation = CFrame.fromOrientation(freecam.pitch, freecam.yaw, 0)
    local direction = movementVector()
    local sprint = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
    local speed = freecam.speed * (sprint and 3 or 1)
    local displacement = orientation:VectorToWorldSpace(direction) * speed * deltaTime
    local position = freecam.cframe.Position + displacement
    freecam.cframe = CFrame.new(position) * orientation

    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = freecam.cframe
    camera.Focus = CFrame.new(position + freecam.cframe.LookVector * FC.FOCUS_DISTANCE)
    camera.FieldOfView = freecam.fov
end

disableFreecam = function()
    if not freecam.enabled and not freecam.saved then
        return true
    end

    freecam.enabled = false
    pcall(function()
        RunService:UnbindFromRenderStep(FC.BIND_NAME)
    end)
    unbindMovementSink()
    disconnectFreecamInputs()
    disconnectFreecamLifecycle()

    local controls = freecam.controls
    local saved = freecam.saved
    if controls and saved then
        pcall(function()
            if saved.controlsEnabled == false then
                controls:Disable()
            else
                controls:Enable()
            end
        end)
    end

    if saved and saved.camera then
        pcall(function()

            saved.camera.CFrame = saved.cameraCFrame
            saved.camera.Focus = saved.cameraFocus
            saved.camera.FieldOfView = saved.fieldOfView
            saved.camera.CameraSubject = saved.cameraSubject
            saved.camera.CameraType = saved.cameraType
        end)
        pcall(function()
            UserInputService.MouseBehavior = saved.mouseBehavior
            UserInputService.MouseIconEnabled = saved.mouseIconEnabled
        end)
    end

    freecam.camera = nil
    freecam.cframe = nil
    freecam.controls = nil
    freecam.saved = nil
    freecam.looking = false
    return true
end

local function enableFreecam(mode)
    mode = mode == "turret" and "turret" or "scout"
    if freecam.enabled then
        freecam.mode = mode
        return applyControlMode()
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return false
    end

    freecam.saved = {
        camera = camera,
        cameraType = camera.CameraType,
        cameraSubject = camera.CameraSubject,
        cameraCFrame = camera.CFrame,
        cameraFocus = camera.Focus,
        fieldOfView = camera.FieldOfView,
        mouseBehavior = UserInputService.MouseBehavior,
        mouseIconEnabled = UserInputService.MouseIconEnabled,
        controlsEnabled = nil,
    }
    freecam.controls = getControlModule()
    if freecam.controls then
        freecam.saved.controlsEnabled = freecam.controls.controlsEnabled ~= false
    end
    freecam.camera = camera
    freecam.cframe = camera.CFrame
    freecam.pitch, freecam.yaw = camera.CFrame:ToOrientation()
    freecam.mode = mode
    freecam.enabled = true
    connectFreecamInputs()
    connectFreecamLifecycle()
    RunService:BindToRenderStep(FC.BIND_NAME, FC.RENDER_PRIORITY, renderFreecam)

    if not applyControlMode() then
        disableFreecam()
        return false
    end
    return true
end

rawset(_G, "__VISION_DISABLE_FREECAM", disableFreecam)

local function switchFreecamMode()
    local nextMode = freecam.mode == "scout" and "turret" or "scout"
    freecam.mode = nextMode
    if freecam.enabled then
        return applyControlMode()
    end
    return true
end

local RA_MARGIN = 0.65
local RA_MAX_FRAMES = 100

local reloadAssist = {
    enabled = false,
    supported = false,
    armed = false,
    attempts = 0,
    successInvocations = 0,
    lastError = nil,
    framesSeen = 0,
    connections = {},
    watchConnections = {},
    candidateConnections = {},
    attemptedFrames = setmetatable({}, { __mode = "k" }),
    activeFrame = nil,
    onDisabled = nil,
}

local function raUntrack(connection)
    for i = #owner.connections, 1, -1 do
        if owner.connections[i] == connection then
            table.remove(owner.connections, i)
        end
    end
end

local function raDisconnect(list)
    for _, connection in ipairs(list) do
        pcall(function()
            if connection.Connected then
                connection:Disconnect()
            end
        end)
        raUntrack(connection)
    end
    table.clear(list)
end

local function raTrack(connection, list)
    table.insert(list or reloadAssist.connections, connection)

    table.insert(owner.connections, connection)
end

local function raRemoveConnection(list, connection)
    for i = #list, 1, -1 do
        if list[i] == connection then
            table.remove(list, i)
        end
    end
end

local function raClassify(frame)

    local ok, parts = pcall(function()
        if typeof(frame) ~= "Instance" or not frame:IsA("GuiObject") then
            return nil
        end
        local progress = frame:FindFirstChild("Progress")
        if not progress or not progress:IsA("GuiObject") then return nil end
        if not progress:FindFirstChild("Needle") then return nil end
        local fastWindow = frame:FindFirstChild("FastReloadWindow")
        if not fastWindow or not fastWindow:IsA("GuiObject") or fastWindow.Visible ~= true then return nil end
        local button = frame:FindFirstChild("ControlsButton")
        if not button or not button:IsA("GuiButton") or button.Visible ~= true then return nil end
        return { progress = progress, fastWindow = fastWindow, button = button }
    end)
    if not ok then
        return nil
    end
    return parts
end

local function raResolveCallback(button)

    if type(getconnections) ~= "function" then
        return nil, "getconnections-unavailable"
    end
    local ok, connections = pcall(function()
        return getconnections(button.Activated)
    end)
    if not ok or type(connections) ~= "table" then
        return nil, "getconnections-failed"
    end
    local candidate = nil
    for _, connection in ipairs(connections) do

        local enabled = false
        local enabledOk, enabledValue = pcall(function()
            return connection.Enabled
        end)
        if enabledOk and type(enabledValue) == "boolean" then
            enabled = enabledValue
        end
        if enabled then
            local fn = nil
            pcall(function()
                fn = connection.Function
            end)
            if type(fn) == "function" then
                local infoOk, source = pcall(function()
                    return debug.info(fn, "s")
                end)
                if infoOk and type(source) == "string" and source:find("LoaderGUIScript", 1, true) then
                    if candidate ~= nil then
                        return nil, "ambiguous-callbacks"
                    end
                    candidate = fn
                end
            end
        end
    end
    if candidate == nil then
        return nil, "no-game-callback"
    end
    return candidate
end

local function raForgetFrame()
    local active = reloadAssist.activeFrame
    reloadAssist.activeFrame = nil
    reloadAssist.armed = false
    if active then
        raDisconnect(active.connections)
    end
end

local function raEvaluate(active)
    if owner.stopped or not reloadAssist.enabled then
        return
    end
    if reloadAssist.attemptedFrames[active.frame] then
        return
    end

    local geomOk, state = pcall(function()
        if not active.frame.Parent then return nil end
        if active.fastWindow.Visible ~= true then return nil end
        if active.button.Visible ~= true then return nil end
        local progressScale = active.progress.Size.X.Scale
        local windowPos = active.fastWindow.Position.X.Scale
        local halfWidth = active.fastWindow.Size.X.Scale / 2
        if halfWidth <= 0 then return nil end
        return {
            deviation = math.abs(progressScale - windowPos),
            halfWidth = halfWidth,
            progressScale = progressScale,
            windowPos = windowPos,
        }
    end)
    if not geomOk or state == nil then

        raForgetFrame()
        return
    end

    if state.progressScale > state.windowPos + state.halfWidth then

        raForgetFrame()
        return
    end
    if state.deviation >= state.halfWidth * RA_MARGIN then
        return
    end

    reloadAssist.attemptedFrames[active.frame] = true
    reloadAssist.attempts += 1
    local invokeOk = pcall(active.callback)
    if invokeOk then
        reloadAssist.successInvocations += 1
    else
        reloadAssist.lastError = "callback-invoke"
    end
    raForgetFrame()
end

local function raAttachFrame(frame)
    if reloadAssist.activeFrame then
        return
    end
    local parts = raClassify(frame)
    if not parts then
        return
    end
    local callback, reject = raResolveCallback(parts.button)
    if not callback then
        reloadAssist.lastError = reject
        return
    end

    local active = {
        frame = frame,
        progress = parts.progress,
        fastWindow = parts.fastWindow,
        button = parts.button,
        callback = callback,
        connections = {},
    }
    reloadAssist.activeFrame = active
    reloadAssist.armed = true

    local sizeConn = parts.progress:GetPropertyChangedSignal("Size"):Connect(function()
        raEvaluate(active)
    end)
    raTrack(sizeConn, active.connections)

    local goneConn = frame:GetPropertyChangedSignal("Parent"):Connect(function()
        if frame.Parent == nil then
            raForgetFrame()
        end
    end)
    raTrack(goneConn, active.connections)

    raEvaluate(active)
end

local function raCandidateAdded(child)
    if owner.stopped or not reloadAssist.enabled then
        return
    end

    local isGui = false
    pcall(function()
        isGui = typeof(child) == "Instance" and child:IsA("GuiObject")
    end)
    if not isGui then
        return
    end
    reloadAssist.framesSeen += 1
    if reloadAssist.framesSeen > RA_MAX_FRAMES then
        reloadAssist.lastError = "max-frames-exceeded"
        reloadAssist.supported = false
        reloadAssist.stop()
        return
    end
    local current = reloadAssist.activeFrame
    if current then
        local alive = false
        pcall(function()
            alive = current.frame.Parent ~= nil
        end)
        if alive then
            return
        end
        raForgetFrame()
    end
    raAttachFrame(child)
    if reloadAssist.activeFrame then
        return
    end

    local retryConnections = {}
    local retryCleaned = false
    local function cleanupRetryConnections()
        if retryCleaned then return end
        retryCleaned = true
        for _, connection in ipairs(retryConnections) do
            pcall(function()
                if connection.Connected then connection:Disconnect() end
            end)
            raUntrack(connection)
            raRemoveConnection(reloadAssist.candidateConnections, connection)
        end
        table.clear(retryConnections)
    end
    local function retryAttach()
        if owner.stopped or not reloadAssist.enabled then
            cleanupRetryConnections()
            return
        end
        if reloadAssist.activeFrame then
            cleanupRetryConnections()
            return
        end
        local parentOk = false
        pcall(function()
            parentOk = child.Parent ~= nil
        end)
        if parentOk then
            raAttachFrame(child)
            if reloadAssist.activeFrame then cleanupRetryConnections() end
        else
            cleanupRetryConnections()
        end
    end
    local watcherSources = {}
    pcall(function()
        local progress = child:FindFirstChild("Progress")
        if progress then
            table.insert(watcherSources, { inst = progress, prop = "Size" })
        end
        local button = child:FindFirstChild("ControlsButton")
        if button then
            table.insert(watcherSources, { inst = button, prop = "Visible" })
        end
        local fastWindow = child:FindFirstChild("FastReloadWindow")
        if fastWindow then
            table.insert(watcherSources, { inst = fastWindow, prop = "Visible" })
            table.insert(watcherSources, { inst = fastWindow, prop = "Position" })
        end
    end)
    for _, spec in ipairs(watcherSources) do
        local watchOk, watchConn = pcall(function()
            return spec.inst:GetPropertyChangedSignal(spec.prop):Connect(retryAttach)
        end)
        if watchOk and watchConn then
            table.insert(retryConnections, watchConn)
            raTrack(watchConn, reloadAssist.candidateConnections)
        end
    end
    local parentOk, parentConn = pcall(function()
        return child:GetPropertyChangedSignal("Parent"):Connect(retryAttach)
    end)
    if parentOk and parentConn then
        table.insert(retryConnections, parentConn)
        raTrack(parentConn, reloadAssist.candidateConnections)
    end
end

local function raRebind()

    raForgetFrame()
    raDisconnect(reloadAssist.watchConnections)
    raDisconnect(reloadAssist.candidateConnections)

    local playerRebindConn = LocalPlayer.ChildAdded:Connect(function(child)
        if child.Name == "PlayerGui" then
            raRebind()
        end
    end)
    raTrack(playerRebindConn, reloadAssist.watchConnections)

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local crewGui = playerGui and playerGui:FindFirstChild("CrewGui")
    local loadBar = crewGui and crewGui:FindFirstChild("loadBar")

    if playerGui then
        local conn = playerGui.ChildAdded:Connect(function(child)
            if child.Name == "CrewGui" then
                raRebind()
            end
        end)
        raTrack(conn, reloadAssist.watchConnections)
    end
    if crewGui then
        local conn = crewGui.ChildAdded:Connect(function(child)
            if child.Name == "loadBar" then
                raRebind()
            end
        end)
        raTrack(conn, reloadAssist.watchConnections)

        local goneConn = crewGui:GetPropertyChangedSignal("Parent"):Connect(function()
            if crewGui.Parent == nil then
                raRebind()
            end
        end)
        raTrack(goneConn, reloadAssist.watchConnections)
    end
    if loadBar then
        local conn = loadBar.ChildAdded:Connect(function(child)
            raCandidateAdded(child)
        end)
        raTrack(conn, reloadAssist.watchConnections)

        local children = nil
        pcall(function()
            children = loadBar:GetChildren()
        end)
        if children then
            for _, child in ipairs(children) do
                raCandidateAdded(child)
            end
        end
    end
end

function reloadAssist.start()
    if owner.stopped then
        return false
    end
    if reloadAssist.enabled then
        return true
    end

    if type(getconnections) ~= "function" then
        reloadAssist.supported = false
        reloadAssist.lastError = "getconnections-unavailable"
        return false
    end
    local infoOk = pcall(function()
        return debug.info(function() end, "s")
    end)
    if not infoOk then
        reloadAssist.supported = false
        reloadAssist.lastError = "debug-info-unavailable"
        return false
    end

    reloadAssist.supported = true
    reloadAssist.enabled = true
    reloadAssist.lastError = nil

    local respawnConn = LocalPlayer.CharacterAdded:Connect(function()
        if reloadAssist.enabled then
            raRebind()
        end
    end)
    raTrack(respawnConn)

    local bindOk = pcall(raRebind)
    if not bindOk then

        reloadAssist.stop()
        reloadAssist.supported = false
        reloadAssist.lastError = "bind-failed"
        return false
    end
    return true
end

function reloadAssist.stop()
    reloadAssist.enabled = false
    raForgetFrame()
    raDisconnect(reloadAssist.watchConnections)
    raDisconnect(reloadAssist.candidateConnections)
    raDisconnect(reloadAssist.connections)
    reloadAssist.armed = false
    if type(reloadAssist.onDisabled) == "function" then
        pcall(reloadAssist.onDisabled)
    end
    return true
end

owner.reloadAssist = reloadAssist
local runtimeEnvironment = getfenv()
local liveState = rawget(runtimeEnvironment, "STATE")

local function externalCall(stage, callback)
    assertCurrentGeneration(stage .. "-before")
    owner.activeExternalCalls += 1
    local packed = table.pack(xpcall(callback, function(err)
        return tostring(err)
    end))
    owner.activeExternalCalls -= 1

    if owner.stopped then
        stop("external-call-unwound:" .. stage)
    end
    if not packed[1] then
        error(packed[2], 0)
    end
    assertCurrentGeneration(stage .. "-after")
    return table.unpack(packed, 2, packed.n)
end

local function replaceOnce(source, before, after, label)
    local startIndex, endIndex = string.find(source, before, 1, true)
    if not startIndex then
        error("[Vision] Rayfield patch marker missing: " .. label)
    end
    if string.find(source, before, endIndex + 1, true) then
        error("[Vision] Rayfield patch marker repeated: " .. label)
    end
    return string.sub(source, 1, startIndex - 1) .. after .. string.sub(source, endIndex + 1)
end

local function patchRayfieldSource(source)
    source = replaceOnce(
        source,
        "m.Parent=f.guiContainer local n=Instance.new",
        "m:SetAttribute('VisionOwner',rawget(_G,'__VISION_PENDING_OWNER'))m.Parent=f.guiContainer local n=Instance.new",
        "banner-owner"
    )
    source = replaceOnce(
        source,
        "ZIndexBehavior.Global,Parent=f.guiContainer})y.main=",
        "ZIndexBehavior.Global,Parent=f.guiContainer})y.screenGui:SetAttribute('VisionOwner',rawget(_G,'__VISION_PENDING_OWNER'))y.main=",
        "window-owner"
    )
    source = replaceOnce(
        source,
        ".Global,Parent=h.guiContainer})U.backdrop=",
        ".Global,Parent=h.guiContainer})U.screenGui:SetAttribute('VisionOwner',V.screenGui:GetAttribute('VisionOwner'))U.backdrop=",
        "popup-owner"
    )

    source = replaceOnce(
        source,
        "m.Enabled=true m.SafeAreaCompatibility=Enum.SafeAreaCompatibility.None m.ScreenInsets=Enum.",
        "m.Enabled=false m.SafeAreaCompatibility=Enum.SafeAreaCompatibility.None m.ScreenInsets=Enum.",
        "banner-splash-disabled"
    )

    local spawnStart = "task.spawn(function()task.wait(0.5)o:Destroy()task.wait(0.5)if not t.unloaded"
    local spawnEnd = "then t:Show()end end)"
    local startIndex = string.find(source, spawnStart, 1, true)
    local endStart, endIndex = startIndex and string.find(source, spawnEnd, startIndex, true) or nil, nil
    if endStart then
        endIndex = endStart + #spawnEnd - 1
    end
    if not startIndex or not endIndex then
        error("[Vision] Rayfield patch marker missing: first-show")
    end
    source = string.sub(source, 1, startIndex - 1)
        .. "o:Destroy()if not t.unloaded then t:Show()end "
        .. string.sub(source, endIndex + 1)

    source = replaceOnce(
        source,
        "Size=UDim2.fromOffset(100,4)}):Play()w.animating=false",
        "Size=UDim2.fromOffset(100,4)}):Play()if w.unloaded then return end w.animating=false",
        "first-show-cancel"
    )

    source = replaceOnce(
        source,
        "name=w.name or w.Name or'Rayfield Window'",
        "name=w.name or w.Name or'Vision'",
        "default-window-name"
    )
    source = replaceOnce(
        source,
        "showName=w.showName or w.ShowName or'Rayfield'",
        "showName=w.showName or w.ShowName or''",
        "default-show-name"
    )

    source = replaceOnce(
        source,
        "name=\n'Rayfield Settings'",
        "name=\n'Vision Settings'",
        "settings-tab-name"
    )

    source = replaceOnce(
        source,
        "welcomeToast=true",
        "welcomeToast=false",
        "welcome-toast-default"
    )
    source = replaceOnce(
        source,
        "w.rfSettings:CreateToggle{name\n='Welcome toast',description=[[Shows a 'Signed in as' toast the first time you open the menu on a new account.]],value=w\n.settings.welcomeToast,callback=function(x)w.settings.welcomeToast=x w:SaveSettings()end}",
        "",
        "welcome-toast-toggle"
    )
    return source
end

local function verifiedRayfieldSource()
    local crypto = crypt
    if type(crypto) ~= "table" or type(crypto.hash) ~= "function" then
        error("[Vision] crypt.hash is required for Rayfield verification")
    end
    local hashFn = crypto.hash

    local function hashSource(source, stage)
        if type(source) ~= "string" or source == "" then
            return nil
        end
        return externalCall(stage, function()
            return hashFn(source, "sha256")
        end)
    end

    local source = nil
    local cacheExists = externalCall("rayfield-cache-exists", function()
        return type(isfile) == "function" and isfile(RAYFIELD_CACHE)
    end)
    if cacheExists then
        local readOk, cached = pcall(function()
            return externalCall("rayfield-cache-read", function()
                return readfile(RAYFIELD_CACHE)
            end)
        end)
        assertCurrentGeneration("rayfield-cache-read")
        if readOk and hashSource(cached, "rayfield-hash-cache") == RAYFIELD_SHA256 then
            source = cached
        end
    end

    if not source then
        local response = externalCall("rayfield-fetch", function()
            return game:HttpGet(RAYFIELD_URL)
        end)
        if type(response) ~= "string" then
            error("[Vision] Rayfield download failed")
        end
        local originalDigest = hashSource(response, "rayfield-hash-original")
        if originalDigest ~= RAYFIELD_ORIGINAL_SHA256 then
            error("[Vision] Rayfield upstream hash mismatch; source was not patched")
        end
        source = patchRayfieldSource(response)
    end

    local digest = hashSource(source, "rayfield-hash-final")
    if digest ~= RAYFIELD_SHA256 then
        error("[Vision] Rayfield runtime hash mismatch; source was not executed")
    end

    if type(writefile) == "function" then
        pcall(function()
            externalCall("rayfield-cache-write", function()
                writefile(RAYFIELD_CACHE, source)
            end)
        end)
        assertCurrentGeneration("rayfield-cache-write")
    end
    return source
end

local function loadVerifiedRayfield()
    local source = verifiedRayfieldSource()
    local chunk, compileError = externalCall("rayfield-compile", function()
        return loadstring(source, "@rayfield-gen2-v1.1.0-mtc4")
    end)
    if type(chunk) ~= "function" then
        error("[Vision] Rayfield compile failed: " .. tostring(compileError))
    end

    local secureEnvironment = typeof(getgenv) == "function" and getgenv() or _G
    local previousSecure = rawget(secureEnvironment, "RAYFIELD_SECURE")
    rawset(secureEnvironment, "RAYFIELD_SECURE", false)
    local chunkOk, Rayfield = pcall(function()
        return externalCall("rayfield-chunk", chunk)
    end)
    rawset(secureEnvironment, "RAYFIELD_SECURE", previousSecure)
    if not chunkOk then
        error(Rayfield, 0)
    end
    if type(Rayfield) ~= "table" then
        error("[Vision] Rayfield Gen2 returned an invalid library")
    end
    return Rayfield
end
local function meters(studs)
    return math.floor(studs / STUDS_PER_METER + 0.5)
end

function currentCharacter()
    local character = LocalPlayer.Character
    if character and character.Parent then
        return character
    end
    local playersFolder = Workspace:FindFirstChild("SpawnedPlayers")
    return playersFolder and playersFolder:FindFirstChild(LocalPlayer.Name) or nil
end

local function distanceOrigin(camera, character)
    local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    return root and root.Position or camera.CFrame.Position
end

local function normalizeTeamAlias(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return string.lower(value):gsub("[%s_%-%.]", "")
end

local function addNameAlias(aliases, value)
    local normalized = normalizeTeamAlias(value)
    if normalized then
        aliases["name:" .. normalized] = true
    end
end

local function addColorAlias(aliases, value)
    local normalized = normalizeTeamAlias(value)
    if normalized then
        aliases["color:" .. normalized] = true
    end
end

local function resolvedPlayerTeam(player)
    if not player or player.Neutral then
        return nil
    end
    return player.Team
end

local function addTeamAlias(aliases, value)
    local valueType = typeof(value)
    if valueType == "BrickColor" then
        addColorAlias(aliases, value.Name)
        return
    end

    if type(value) == "string" then
        local normalized = normalizeTeamAlias(value)
        if not normalized then
            return
        end
        addNameAlias(aliases, value)
        local brickColor = BrickColor.new(value :: any)
        local normalizedColor = normalizeTeamAlias(brickColor.Name)
        if normalizedColor == normalized then
            addColorAlias(aliases, brickColor.Name)
        end
        return
    end

    if valueType ~= "Instance" then
        return
    end

    if value:IsA("Team") then
        addNameAlias(aliases, value.Name)
        addColorAlias(aliases, value.TeamColor.Name)
    elseif value:IsA("Player") then
        local team = resolvedPlayerTeam(value)
        if team then
            addTeamAlias(aliases, team)
        end
    elseif value:IsA("ObjectValue") then
        addTeamAlias(aliases, value.Value)
    elseif value:IsA("StringValue") then
        addTeamAlias(aliases, value.Value)
    elseif value:IsA("BrickColorValue") then
        addTeamAlias(aliases, value.Value)
    end
end

local function teamAliasesForPlayer(player)
    local aliases = {}
    local team = resolvedPlayerTeam(player)
    if team then
        addTeamAlias(aliases, team)
    end
    return aliases
end

local function playerFromIdentity(value)
    if typeof(value) == "Instance" and value:IsA("Player") then
        return value
    end

    local numericId = nil
    if type(value) == "string" and value ~= "" then
        local player = Players:FindFirstChild(value)
        if player and player:IsA("Player") then
            return player
        end
        numericId = tonumber(value)
    elseif type(value) == "number" then
        numericId = value
    end

    if numericId then
        for _, player in Players:GetPlayers() do
            if player.UserId == numericId then
                return player
            end
        end
    end
    return nil
end

local playerForModelCache = setmetatable({}, { __mode = "k" })
local playerForModelMisses = setmetatable({}, { __mode = "k" })
local PLAYER_FOR_MODEL_MISS_TTL = 0.5

local function playerForModel(model)
    local cached = playerForModelCache[model]
    if cached ~= nil then
        if cached == false then
            local expiresAt = playerForModelMisses[model]
            if expiresAt and expiresAt > os.clock() then
                return nil
            end
            playerForModelCache[model] = nil
            playerForModelMisses[model] = nil
        else

            if cached.Parent and cached.Character == model then
                return cached
            end
            local characterCheck = Players:GetPlayerFromCharacter(model)
            if characterCheck == cached then
                return cached
            end
            playerForModelCache[model] = nil
        end
    end

    local characterPlayer = Players:GetPlayerFromCharacter(model)
    if characterPlayer then
        playerForModelCache[model] = characterPlayer
        return characterPlayer
    end

    local direct = Players:FindFirstChild(model.Name)
    if direct and direct:IsA("Player") then
        playerForModelCache[model] = direct
        return direct
    end
    for _, attributeName in ipairs({ "Player", "PlayerName", "Owner", "OwnerName", "UserId" }) do
        local player = playerFromIdentity(model:GetAttribute(attributeName))
        if player then
            playerForModelCache[model] = player
            return player
        end
    end
    for _, valueName in ipairs({ "Player", "Owner", "UserId" }) do
        local valueObject = model:FindFirstChild(valueName)
        if valueObject then
            if valueObject:IsA("ObjectValue") or valueObject:IsA("StringValue")
                or valueObject:IsA("IntValue") or valueObject:IsA("NumberValue") then
                local player = playerFromIdentity(valueObject.Value)
                if player then
                    playerForModelCache[model] = player
                    return player
                end
            end
        end
    end
    playerForModelCache[model] = false
    playerForModelMisses[model] = os.clock() + PLAYER_FOR_MODEL_MISS_TTL
    return nil
end

local function addRelatedPlayer(aliases, relatedPlayers, player, includeTeamAlias)
    if not player then
        return
    end
    relatedPlayers[player] = true
    if includeTeamAlias then
        addTeamAlias(aliases, player)
    end
end

local function addOwnerTeamAliases(aliases, relatedPlayers, vehicle, includeTeamAlias)
    for _, attributeName in ipairs({
        "Owner", "OwnerName", "Player", "PlayerName", "Username", "UserId", "Requester",
    }) do
        local player = playerFromIdentity(vehicle:GetAttribute(attributeName))
        addRelatedPlayer(aliases, relatedPlayers, player, includeTeamAlias)
    end

    for _, valueName in ipairs({ "Owner", "Player", "Requester" }) do
        local ownerValue = vehicle:FindFirstChild(valueName)
        if ownerValue then
            local player = nil
            if ownerValue:IsA("ObjectValue") or ownerValue:IsA("StringValue")
                or ownerValue:IsA("IntValue") or ownerValue:IsA("NumberValue") then
                player = playerFromIdentity(ownerValue.Value)
            end
            addRelatedPlayer(aliases, relatedPlayers, player, includeTeamAlias)
        end
    end
end

local function addOccupantTeamAliases(aliases, relatedPlayers, vehicle, includeTeamAlias)
    for _, descendant in vehicle:GetDescendants() do
        if descendant:IsA("VehicleSeat") or descendant:IsA("Seat") then
            local humanoid = descendant.Occupant
            local character = humanoid and humanoid.Parent
            local player = character and playerForModel(character)
            addRelatedPlayer(aliases, relatedPlayers, player, includeTeamAlias)
        end
    end
end

local function vehicleTeamAliases(vehicle)
    local aliases = {}
    local relatedPlayers = {}
    addTeamAlias(aliases, vehicle:GetAttribute("Team"))
    addTeamAlias(aliases, vehicle:GetAttribute("TeamName"))
    addTeamAlias(aliases, vehicle:GetAttribute("TeamColor"))

    local teamValue = vehicle:FindFirstChild("Team")
    if teamValue then
        addTeamAlias(aliases, teamValue)
    end

    addOwnerTeamAliases(aliases, relatedPlayers, vehicle, next(aliases) == nil)
    addOccupantTeamAliases(aliases, relatedPlayers, vehicle, next(aliases) == nil)
    return aliases, relatedPlayers
end

local function classifyTeam(targetAliases, localAliases)
    if next(targetAliases) == nil or next(localAliases) == nil then
        return nil
    end
    for alias in pairs(targetAliases) do
        if localAliases[alias] then
            return false
        end
    end
    return true
end

local function playerClassification(player)
    if not player then
        return nil
    end
    if player == LocalPlayer then
        return false
    end

    local targetTeam = resolvedPlayerTeam(player)
    local localTeam = resolvedPlayerTeam(LocalPlayer)
    if player.Neutral or not targetTeam then
        return true
    end
    if LocalPlayer.Neutral or not localTeam then
        return true
    end
    if targetTeam == localTeam then
        return false
    end
    return true
end

local function vehicleClassification(vehicle, localAliases)
    local targetAliases, relatedPlayers = vehicleTeamAliases(vehicle)
    if relatedPlayers[LocalPlayer] then
        return false
    end

    local aliasClassification = classifyTeam(targetAliases, localAliases)
    if aliasClassification ~= nil then
        return aliasClassification
    end

    local sawEnemy = false
    for player in pairs(relatedPlayers) do
        local classification = playerClassification(player)
        if classification == false then
            return false
        elseif classification == true then
            sawEnemy = true
        end
    end
    return sawEnemy and true or nil
end

local function vehicleClassificationFromCache(vehicle, localAliases, vehicleCache)
    local cached = vehicleCache and vehicleCache[vehicle]
    if not cached then
        return vehicleClassification(vehicle, localAliases)
    end

    if cached.relatedPlayers[LocalPlayer] then
        return false
    end

    local aliasClassification = classifyTeam(cached.targetAliases, localAliases)
    if aliasClassification ~= nil then
        return aliasClassification
    end

    local sawEnemy = false
    for player in pairs(cached.relatedPlayers) do
        local classification = playerClassification(player)
        if classification == false then
            return false
        elseif classification == true then
            sawEnemy = true
        end
    end
    return sawEnemy and true or nil
end

local CREW_LABEL_SPACING = 3.0

local function firstBasePart(model)
    return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function labelOffsetFromBox(boxCFrame, boxSize, anchor, gap)
    if not boxCFrame or not boxSize or not anchor then
        return nil
    end
    local verticalExtent = (
        math.abs(boxCFrame.RightVector.Y) * boxSize.X
        + math.abs(boxCFrame.UpVector.Y) * boxSize.Y
        + math.abs(boxCFrame.LookVector.Y) * boxSize.Z
    ) / 2
    local topY = boxCFrame.Position.Y + verticalExtent + gap
    return Vector3.new(
        boxCFrame.Position.X - anchor.Position.X,
        topY - anchor.Position.Y,
        boxCFrame.Position.Z - anchor.Position.Z
    )
end

local function labelOffsetAboveModel(model, anchor, gap, vehicleCache)
    local cached = vehicleCache and vehicleCache[model]
    if cached and cached.boxCFrame and cached.boxSize then
        return labelOffsetFromBox(cached.boxCFrame, cached.boxSize, anchor, gap)
    end
    local ok, boxCFrame, boxSize = pcall(function()
        return model:GetBoundingBox()
    end)
    if not ok or not boxCFrame or not boxSize then
        return nil
    end
    return labelOffsetFromBox(boxCFrame, boxSize, anchor, gap)
end

local vehicleCacheStore = {}
local vehicleCacheConnections = {}
local BBOX_INVALIDATE_STUDS_SQ = 4.0
local BBOX_MAX_AGE = 0.5

local BulletLineActive = 0
local BulletLastTrajectory = nil
local BulletLastImpact = nil
local BulletLastShell = nil
local clearBulletLines = nil
local hidePenIndicator = nil
local processPenIndicator = nil

local function disposeVehicleCache(vehicle)
    local slot = vehicleCacheConnections[vehicle]
    if slot then
        for _, conn in ipairs(slot) do
            pcall(function() conn:Disconnect() end)
        end
        vehicleCacheConnections[vehicle] = nil
    end
    vehicleCacheStore[vehicle] = nil
end

local function invalidateVehicleCacheTopology(vehicle)
    local cached = vehicleCacheStore[vehicle]
    if cached then
        cached.topologyDirty = true
    end
end

local function shouldDirtyForDescendant(desc)

    if not desc then return false end
    if desc:IsA("VehicleSeat") or desc:IsA("Seat") then return true end

    if desc.Name == "CurrentlyLoaded" or desc.Name == "CurrentMuzzle" or desc.Name == "Muzzle" then return true end
    if desc.Name == "Weapons" or desc.Name == "Turrets" then return true end
    if desc:IsA("ObjectValue") or desc:IsA("StringValue") or desc:IsA("BrickColorValue") or desc:IsA("IntValue") or desc:IsA("NumberValue") then

        if desc.Name == "Team" or desc.Name == "Owner" or desc.Name == "Player" or desc.Name == "Requester" or desc.Name == "UserId" then
            return true
        end
        return false
    end

    if desc:IsA("Attachment") then
        if desc.Name == "GunFirePoint" or desc.Name == "GunFirePoint1" then return true end
        return false
    end
    if desc:IsA("BasePart") then

        return true
    end

    return false
end

local RELEVANT_ATTRS = {
    Team = true, TeamName = true, TeamColor = true,
    Owner = true, OwnerName = true, Player = true, PlayerName = true,
    Username = true, UserId = true, Requester = true,
    VehicleDisplayName = true, VehicleClass = true,
}

local function watchVehicle(vehicle)
    if vehicleCacheConnections[vehicle] then return end
    local slot = {}
    local c1 = vehicle.DescendantAdded:Connect(function(desc)
        if shouldDirtyForDescendant(desc) then
            invalidateVehicleCacheTopology(vehicle)
        end
        if desc:IsA("VehicleSeat") or desc:IsA("Seat") then
            local cSeat = desc:GetPropertyChangedSignal("Occupant"):Connect(function()
                if cfg.bulletLine and (BulletLineActive > 0 or BulletLastTrajectory ~= nil) then
                    local localChar = currentCharacter()
                    local lh = localChar and localChar:FindFirstChildOfClass("Humanoid")
                    local vf = Workspace:FindFirstChild("SpawnedVehicles")
                    local lv = playerVehicle(lh, vf)
                    if not lv then clearBulletLines() end
                end
            end)
            table.insert(vehicleCacheConnections[vehicle], cSeat)
            table.insert(owner.connections, cSeat)
        end
    end)
    local c2 = vehicle.DescendantRemoving:Connect(function(desc)
        if shouldDirtyForDescendant(desc) then
            invalidateVehicleCacheTopology(vehicle)
        end
    end)

    local c3 = vehicle.AttributeChanged:Connect(function(attr)
        if RELEVANT_ATTRS[attr] then
            invalidateVehicleCacheTopology(vehicle)
        end
    end)
    local c4 = vehicle.AncestryChanged:Connect(function()
        if not vehicle.Parent then
            disposeVehicleCache(vehicle)
        end
    end)

    for _, d in ipairs(vehicle:GetDescendants()) do
        if d:IsA("VehicleSeat") or d:IsA("Seat") then
            local cSeat = d:GetPropertyChangedSignal("Occupant"):Connect(function()

                if cfg.bulletLine and (BulletLineActive > 0 or BulletLastTrajectory ~= nil) then
                    local localChar = currentCharacter()
                    local lh = localChar and localChar:FindFirstChildOfClass("Humanoid")
                    local vf = Workspace:FindFirstChild("SpawnedVehicles")
                    local lv = playerVehicle(lh, vf)
                    if not lv then clearBulletLines() end
                end
            end)
            table.insert(slot, cSeat)
            table.insert(owner.connections, cSeat)
        end
    end
    table.insert(slot, c1)
    table.insert(slot, c2)
    table.insert(slot, c3)
    table.insert(slot, c4)

    table.insert(owner.connections, c1)
    table.insert(owner.connections, c2)
    table.insert(owner.connections, c3)
    table.insert(owner.connections, c4)
    vehicleCacheConnections[vehicle] = slot
end

local function buildVehicleTopology(vehicle)
    local anchor = firstBasePart(vehicle)
    if not anchor then return nil end

    local occupants = {}
    local seen = {}
    local seats = {}
    for _, descendant in vehicle:GetDescendants() do
        if descendant:IsA("VehicleSeat") or descendant:IsA("Seat") then
            table.insert(seats, descendant)
            local humanoid = descendant.Occupant
            local character = humanoid and humanoid.Parent
            local occupantPlayer = character and playerForModel(character)
            if occupantPlayer and not seen[occupantPlayer] then
                seen[occupantPlayer] = true
                table.insert(occupants, occupantPlayer)
            end
        end
    end
    table.sort(occupants, function(a, b)
        if a.UserId == b.UserId then
            return a.Name < b.Name
        end
        return a.UserId < b.UserId
    end)

    local targetAliases = {}
    local relatedPlayers = {}
    addTeamAlias(targetAliases, vehicle:GetAttribute("Team"))
    addTeamAlias(targetAliases, vehicle:GetAttribute("TeamName"))
    addTeamAlias(targetAliases, vehicle:GetAttribute("TeamColor"))
    local teamValue = vehicle:FindFirstChild("Team")
    if teamValue then
        addTeamAlias(targetAliases, teamValue)
    end
    addOwnerTeamAliases(targetAliases, relatedPlayers, vehicle, next(targetAliases) == nil)
    local includeOccupantAlias = next(targetAliases) == nil
    for _, occupantPlayer in ipairs(occupants) do
        relatedPlayers[occupantPlayer] = true
        if includeOccupantAlias then
            addTeamAlias(targetAliases, occupantPlayer)
        end
    end

    return {
        anchor = anchor,
        seats = seats,
        occupants = occupants,
        targetAliases = targetAliases,
        relatedPlayers = relatedPlayers,
    }
end

local function refreshVehicleBoundingBox(vehicle, cached, now)
    local anchor = cached.anchor
    if not anchor or not anchor.Parent then
        return false
    end
    local anchorPos = anchor.Position
    local lastAnchorPos = cached.lastAnchorPos
    local needsRebuild = cached.boxCFrame == nil
        or (now - (cached.bboxAt or 0)) > BBOX_MAX_AGE
        or lastAnchorPos == nil
        or (anchorPos - lastAnchorPos).Magnitude ^ 2 > BBOX_INVALIDATE_STUDS_SQ
    if not needsRebuild then
        return true
    end
    local ok, boxCFrame, boxSize = pcall(function()
        return vehicle:GetBoundingBox()
    end)
    if not ok or not boxCFrame or not boxSize then
        return false
    end
    cached.boxCFrame = boxCFrame
    cached.boxSize = boxSize
    cached.offsetWorld = labelOffsetFromBox(boxCFrame, boxSize, anchor, 2.5)
    cached.lastAnchorPos = anchorPos
    cached.bboxAt = now
    return true
end

local function updateOccupantSet(vehicle, cached)

    local occupants = {}
    local seen = {}
    for _, seat in ipairs(cached.seats) do
        if seat.Parent then
            local humanoid = seat.Occupant
            local character = humanoid and humanoid.Parent
            local occupantPlayer = character and playerForModel(character)
            if occupantPlayer and not seen[occupantPlayer] then
                seen[occupantPlayer] = true
                table.insert(occupants, occupantPlayer)
            end
        end
    end
    table.sort(occupants, function(a, b)
        if a.UserId == b.UserId then
            return a.Name < b.Name
        end
        return a.UserId < b.UserId
    end)

    if cached.occupants and #cached.occupants == #occupants then
        local same = true
        for i = 1, #occupants do
            if cached.occupants[i] ~= occupants[i] then same = false; break end
        end
        if same then
            return
        end
    end

    cached.occupants = occupants
    local freshRelated = {}

    if cached.ownerRelatedPlayers then
        for pl in pairs(cached.ownerRelatedPlayers) do
            freshRelated[pl] = true
        end
    else

        local occupantSet = {}
        for _, op in ipairs(occupants) do occupantSet[op] = true end
        for pl in pairs(cached.relatedPlayers) do

            local wasOccupant = false
            if cached.occupants then

                wasOccupant = false

                for _, prev in ipairs(cached._prevOccupants or {}) do
                    if prev == pl then wasOccupant = true; break end
                end
            end
            if wasOccupant then
                if occupantSet[pl] then freshRelated[pl] = true end
            else
                freshRelated[pl] = true
            end
        end
    end
    for _, op in ipairs(occupants) do
        freshRelated[op] = true
    end
    cached.relatedPlayers = freshRelated

    cached._prevOccupants = table.clone(occupants)

    if cached.targetAliasesOccupantDerived then
        local freshAliases = {}
        addTeamAlias(freshAliases, vehicle:GetAttribute("Team"))
        addTeamAlias(freshAliases, vehicle:GetAttribute("TeamName"))
        addTeamAlias(freshAliases, vehicle:GetAttribute("TeamColor"))
        local teamValue = vehicle:FindFirstChild("Team")
        if teamValue then
            addTeamAlias(freshAliases, teamValue)
        end
        local hasExplicitTeam = next(freshAliases) ~= nil
        if hasExplicitTeam then

            cached.targetAliases = freshAliases
            cached.targetAliasesOccupantDerived = false

        else

            for _, op in ipairs(occupants) do
                addTeamAlias(freshAliases, op)
            end
            cached.targetAliases = freshAliases
            cached.targetAliasesOccupantDerived = true
        end

        if next(cached.targetAliases) == nil then
            local tmpRelated = {}
            addOwnerTeamAliases(cached.targetAliases, tmpRelated, vehicle, true)
            for pl in pairs(tmpRelated) do
                cached.relatedPlayers[pl] = true
                if cached.ownerRelatedPlayers then
                    cached.ownerRelatedPlayers[pl] = true
                end
            end
        end
    end
end

local function ensureVehicleCache(vehicle, now)
    local cached = vehicleCacheStore[vehicle]
    if not cached or cached.topologyDirty then
        local topology = buildVehicleTopology(vehicle)
        if not topology then
            return nil
        end
        cached = cached or { bboxAt = 0 }
        cached.anchor = topology.anchor
        cached.seats = topology.seats
        cached.occupants = topology.occupants

        do
            local probeAliases = {}
            addTeamAlias(probeAliases, vehicle:GetAttribute("Team"))
            addTeamAlias(probeAliases, vehicle:GetAttribute("TeamName"))
            addTeamAlias(probeAliases, vehicle:GetAttribute("TeamColor"))
            local tv = vehicle:FindFirstChild("Team")
            if tv then addTeamAlias(probeAliases, tv) end
            local hasExplicit = next(probeAliases) ~= nil
            if not hasExplicit then

                local ownerProbe = {}
                local dummy = {}
                addOwnerTeamAliases(probeAliases, dummy, vehicle, true)
                hasExplicit = next(probeAliases) ~= nil
            end

            cached.targetAliasesOccupantDerived = not hasExplicit
        end
        cached.targetAliases = topology.targetAliases

        do
            local ownerRelated = {}
            local occSet = {}
            for _, op in ipairs(topology.occupants) do occSet[op] = true end
            for pl in pairs(topology.relatedPlayers) do
                if not occSet[pl] then
                    ownerRelated[pl] = true
                end
            end
            cached.ownerRelatedPlayers = ownerRelated
        end
        cached._prevOccupants = table.clone(topology.occupants)
        cached.relatedPlayers = {}
        for p in pairs(topology.relatedPlayers) do
            cached.relatedPlayers[p] = true
        end
        cached.topologyDirty = false
        vehicleCacheStore[vehicle] = cached
        watchVehicle(vehicle)
    else
        updateOccupantSet(vehicle, cached)
    end
    if not refreshVehicleBoundingBox(vehicle, cached, now) then
        return nil
    end
    return cached
end

local function buildVehicleCache(vehicle)
    return ensureVehicleCache(vehicle, os.clock())
end

playerVehicle = function(humanoid, vehiclesFolder)
    local seat = humanoid and humanoid.SeatPart
    local cursor = seat
    for _ = 1, 20 do
        if not cursor then
            break
        end
        if cursor:IsA("Model") and cursor.Parent then
            local p = cursor.Parent
            if p == vehiclesFolder then
                return cursor
            end
            if p.Name == "PlacedBuildings" and p.Parent == Workspace then
                return cursor
            end
        end
        cursor = cursor.Parent
    end
    return nil
end

local function crewLabelSlot(vehicle, player, vehicleCache)
    local cached = vehicleCache and vehicleCache[vehicle]
    local occupants = {}
    local seen = {}
    if cached and cached.occupants then
        for _, p in ipairs(cached.occupants) do
            if not seen[p] then
                seen[p] = true
                table.insert(occupants, p)
            end
        end
    else
        for _, descendant in vehicle:GetDescendants() do
            if descendant:IsA("VehicleSeat") or descendant:IsA("Seat") then
                local humanoid = descendant.Occupant
                local character = humanoid and humanoid.Parent
                local occupantPlayer = character and playerForModel(character)
                if occupantPlayer and not seen[occupantPlayer] then
                    seen[occupantPlayer] = true
                    table.insert(occupants, occupantPlayer)
                end
            end
        end
    end
    if player and not seen[player] then
        table.insert(occupants, player)
    end
    table.sort(occupants, function(a, b)
        if a.UserId == b.UserId then
            return a.Name < b.Name
        end
        return a.UserId < b.UserId
    end)
    for index, occupant in ipairs(occupants) do
        if occupant == player then
            return index
        end
    end
    return 1
end
local function createRayContext(camera, localCharacter, localVehicle)
    local ok, context = pcall(function()
        if not camera then
            return nil
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        local excluded = { camera }
        if localCharacter then
            table.insert(excluded, localCharacter)
        end
        if localVehicle then
            table.insert(excluded, localVehicle)
        end
        params.FilterDescendantsInstances = excluded
        return {
            origin = camera.CFrame.Position,
            camera = camera,
            params = params,
        }
    end)
    return ok and context or nil
end

local function isOnScreen(camera, worldPos)
    if not camera or not worldPos then return false end
    local ok, screenPoint, onScreen = pcall(camera.WorldToViewportPoint, camera, worldPos)
    if not ok then return true end
    if not onScreen then return false end
    local viewport = camera.ViewportSize
    local pad = 100
    if screenPoint.X < -pad or screenPoint.Y < -pad
        or screenPoint.X > viewport.X + pad or screenPoint.Y > viewport.Y + pad then
        return false
    end
    return true
end

local function visibleFromCamera(rayContext, targetModel, targetPosition, relatedModel)
    local ok, visible = pcall(function()
        if not rayContext or not targetPosition then
            return false
        end
        local direction = targetPosition - rayContext.origin
        if direction.Magnitude < 0.01 then
            return true
        end

        local result = Workspace:Raycast(rayContext.origin, direction, rayContext.params)
        if result == nil then
            return true
        end
        local hit = result.Instance
        if hit and hit:IsDescendantOf(targetModel) then
            return true
        end
        if relatedModel and hit and hit:IsDescendantOf(relatedModel) then
            return true
        end
        return false
    end)
    return ok and visible == true
end
local function ensureEntry(model)
    local entry = owner.visuals[model]
    if not entry then
        entry = {}
        owner.visuals[model] = entry
    end
    return entry
end

local function ensureHighlight(model, entry)
    local highlight = entry.highlight
    if not highlight or highlight.Parent ~= model then
        if highlight then
            if not destroyInstance(highlight) then
                error("highlight-replacement-cleanup-failed")
            end
            entry.highlight = nil
        end

        highlight = Instance.new("Highlight")
        entry.highlight = highlight
        local ok, err = xpcall(function()
            highlight.Enabled = false
            highlight.Name = "VisionV3"
            highlight:SetAttribute("VisionOwner", ownerToken)
            highlight.Parent = model
        end, function(failure)
            return tostring(failure)
        end)
        if not ok then
            if destroyInstance(highlight) then
                entry.highlight = nil
            end
            error("highlight-create-failed:" .. err)
        end
    end
    return highlight
end

local function updateHighlight(model, entry, color, wallcheck)
    local highlight = ensureHighlight(model, entry)

    if highlight.FillColor ~= color then highlight.FillColor = color end
    if highlight.OutlineColor ~= color then highlight.OutlineColor = color end
    if highlight.FillTransparency ~= cfg.fillTransparency then
        highlight.FillTransparency = cfg.fillTransparency
    end
    if highlight.OutlineTransparency ~= 1 then highlight.OutlineTransparency = 1 end
    local desiredMode = wallcheck
        and Enum.HighlightDepthMode.Occluded
        or Enum.HighlightDepthMode.AlwaysOnTop
    if highlight.DepthMode ~= desiredMode then highlight.DepthMode = desiredMode end
    if not highlight.Enabled then highlight.Enabled = true end
end

local function removeHighlight(entry)
    if destroyInstance(entry.highlight) then
        entry.highlight = nil
        return true
    end
    return false
end

local function ensureLabel(model, entry, anchor)
    local label = entry.label
    if not label or label.Parent ~= anchor then
        if entry.text or label then
            local textGone = destroyInstance(entry.text)
            local labelGone = destroyInstance(label)
            if textGone then
                entry.text = nil
            end
            if labelGone then
                entry.label = nil
            end
            if not textGone or not labelGone then
                error("label-replacement-cleanup-failed")
            end
        end

        label = Instance.new("BillboardGui")
        entry.label = label
        local text = nil
        local ok, err = xpcall(function()
            label.Enabled = false
            label.Name = "VisionInfoV3"
            label:SetAttribute("VisionOwner", ownerToken)
            label.Adornee = anchor
            label.Size = UDim2.fromOffset(210, 58)
            label.LightInfluence = 0
            label.MaxDistance = 100000

            text = Instance.new("TextLabel")
            entry.text = text
            text:SetAttribute("VisionOwner", ownerToken)
            text.Name = "Text"
            text.BackgroundTransparency = 1
            text.Size = UDim2.fromScale(1, 1)
            text.Font = Enum.Font.GothamBold
            text.TextSize = 13
            text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            text.TextStrokeTransparency = 0.20
            text.TextWrapped = true
            text.TextYAlignment = Enum.TextYAlignment.Center
            text.Parent = label
            label.Parent = anchor
        end, function(failure)
            return tostring(failure)
        end)
        if not ok then
            local textGone = destroyInstance(entry.text)
            local labelGone = destroyInstance(entry.label)
            if textGone then
                entry.text = nil
            end
            if labelGone then
                entry.label = nil
            end
            error("label-create-failed:" .. err)
        end
    end
    return entry.label, entry.text
end

local function updateLabel(model, entry, anchor, offsetWorld, color, value, visible, wallcheck)
    local label, text = ensureLabel(model, entry, anchor)
    if label.StudsOffsetWorldSpace ~= offsetWorld then
        label.StudsOffsetWorldSpace = offsetWorld
    end
    local desiredAOT = not wallcheck
    if label.AlwaysOnTop ~= desiredAOT then label.AlwaysOnTop = desiredAOT end
    if text.TextColor3 ~= color then text.TextColor3 = color end
    if text.Text ~= value then text.Text = value end
    if label.Enabled ~= visible then label.Enabled = visible end
end

local function removeLabel(entry)
    local textGone = destroyInstance(entry.text)
    local labelGone = destroyInstance(entry.label)
    if textGone then
        entry.text = nil
    end
    if labelGone then
        entry.label = nil
    end
    return textGone and labelGone
end

local function finishEntry(model, entry)
    if not entry.highlight and not entry.label and not entry.text then
        owner.visuals[model] = nil
    end
end

local function hideEntry(entry)
    if not entry then
        return
    end
    if entry.highlight then
        pcall(function()
            entry.highlight.Enabled = false
        end)
    end
    if entry.label then
        pcall(function()
            entry.label.Enabled = false
        end)
    end
end

local function hideOwnedVisuals()
    for _, entry in pairs(owner.visuals) do
        hideEntry(entry)
    end
end

PenCheck = {}

local STUD_TO_M = 0.36
local MIN_COS = 0.05
local MAX_ANGLE_FOR_CONS = 75
local AP_RICO_VEL_SCALE = 0.0002937
local AP_RICO_VEL_OFFSET = 0.4491

local GlobalConstants = nil
do
    local ok, mod = pcall(function()
        local shells = game:GetService("ReplicatedStorage")
            :WaitForChild("PHRST"):WaitForChild("Shells")
        return (require :: any)(shells:WaitForChild("GlobalConstants"))
    end)
    if ok and type(mod) == "table" and type(mod.PenLoss) == "function" then
        GlobalConstants = mod
    end
end

local function penRetention(distanceStuds, shell)
    if GlobalConstants then
        return GlobalConstants.PenLoss(distanceStuds, shell)
    end
    local mult = shell.PenLossDistanceMult or 1
    local meters = distanceStuds * STUD_TO_M
    return math.clamp(math.exp(-4.786e-5 * meters * mult) * 1.0011, 0.01, 1)
end

local function measurePartThickness(hitPos, direction, part, maxDepth)
    local dir = direction.Unit
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params:AddToFilter(part)
    local farPoint = hitPos + dir * maxDepth
    local hit = Workspace:Raycast(farPoint, -dir * maxDepth, params)
    if hit then
        return (hit.Position - hitPos).Magnitude
    end
    return maxDepth
end

local function isApfsds(shell)
    local dt = tostring(shell.DisplayType or "")
    return string.find(dt, "APFSDS") ~= nil
end

local function isApFamily(shell)
    return string.find(shell.ShellType or "", "AP") ~= nil
end

local function armorAtHit(shell, part, hitPos, hitNormal, direction)
    local parent = part.Parent
    local armourValue = parent and parent:FindFirstChild("ArmourValue")
    if not armourValue then
        return nil, false, nil
    end

    local cos = math.max(-direction.Unit:Dot(hitNormal), MIN_COS)
    local base = armourValue.Value
    local extra = 0
    if shell.ShellType == "HEAT" then
        extra = armourValue:GetAttribute("HEAT") or 0

        if shell.TANDEM and parent:FindFirstChild("DamageEvent") then
            extra = extra * (armourValue:GetAttribute("AntiTandem") or 0)
        end
    end
    local flat = base + extra

    local composite = armourValue:GetAttribute("Composite")
    if composite then

        if shell.ShellType == "HE" then

            local studs = measurePartThickness(hitPos, -hitNormal.Unit, part, 8)
            return studs * composite, true, flat
        end
        local studs = measurePartThickness(hitPos, direction, part, 8)
        local mult = composite
        if shell.ShellType == "HEAT" then
            mult = mult + (armourValue:GetAttribute("HEATComposite") or 0)
        end
        return studs * mult, true, flat
    end

    if shell.ShellType == "HE" then

        return flat, false, flat
    end
    return flat / cos, false, flat
end

local function effectivePen(shell, distanceStuds, angleDeg, los)
    local basePen = shell.ShellMaxPen or shell.InitialPen or 0
    if not isApFamily(shell) then

        return basePen, basePen
    end

    local penAtRange = basePen * penRetention(distanceStuds, shell)

    local dt = tostring(shell.DisplayType or "")
    local angleCons = shell.AngleCons
    if angleCons == nil then
        return penAtRange * math.cos(math.rad(angleDeg)) ^ 1.1, penAtRange
    end
    if shell.Diameter and not string.find(dt, "APDS") and not string.find(dt, "APFSDS") and not string.find(dt, "APCR") then

        local cos = math.max(math.cos(math.rad(angleDeg)), MIN_COS)
        local ratio = math.clamp(shell.Diameter / math.max(los, 0.001) * cos, 0.5, 2.5)
        local curve = math.clamp(angleDeg * 1.5 / 40 - 1.5, -1.5, 0)
        local capped = math.min(angleDeg, MAX_ANGLE_FOR_CONS)
        local exponent = curve ^ 3 * (ratio - 1) + angleCons - angleCons * (ratio - 1) / 6
        return penAtRange * math.cos(math.rad(capped)) ^ exponent, penAtRange
    end

    local capped = math.min(angleDeg, MAX_ANGLE_FOR_CONS)
    return penAtRange * math.cos(math.rad(capped)) ^ angleCons, penAtRange
end

local function ricochetCheck(shell, angleDeg, impactSpeed, flatArmor)
    local ricoAngle = shell.RicochetAngle or 90
    if not isApFamily(shell) then
        if shell.ShellType == "HEAT" then
            return angleDeg >= ricoAngle and "yes" or "no", 1
        end
        return "no", 1
    end

    local velScale = 1
    if shell.ShellType == "AP" then
        velScale = math.min(AP_RICO_VEL_SCALE * (impactSpeed * STUD_TO_M) + AP_RICO_VEL_OFFSET, 1)
    end
    local effRico = ricoAngle * velScale

    if velScale < 1 then
        if angleDeg >= ricoAngle then
            return "yes", 1
        end
        if angleDeg >= effRico then
            return isApfsds(shell) and "no" or "risk", 1
        end
        return "no", 1
    end

    if angleDeg >= ricoAngle then
        return "yes", 1
    end
    if isApfsds(shell) and shell.Diameter then

        local steepness = 90 - angleDeg
        local band = (90 - ricoAngle) * math.clamp(flatArmor / shell.Diameter, 0, 1) ^ 2
        if steepness < band then
            local retention = math.clamp((band - steepness) / band * 1.934, 0.25, 0.9)
            return "risk", retention
        end
    end
    return "no", 1
end

PenCheck.evaluate = function(shell, hit)
    if not shell or not hit or not hit.part then
        return nil
    end

    local direction = hit.direction or (hit.speed and hit.speed ~= 0 and Vector3.new(0, 0, -1)) or Vector3.new(0, 0, -1)
    local los, composite, flatArmor = armorAtHit(shell, hit.part, hit.position, hit.normal, direction)
    if not los then
        return nil
    end

    if string.find(hit.part.Name, "Breech") and los >= 100 then
        los = 100
    end

    local cos = math.max(-direction.Unit:Dot(hit.normal), MIN_COS)
    local angleDeg = math.deg(math.acos(math.clamp(cos, -1, 1)))

    local effPen, penAtRange = effectivePen(shell, hit.distanceStuds or 0, angleDeg, los)

    if shell.ShellType == "HEAT" then
        local av = hit.part.Parent and hit.part.Parent:FindFirstChild("ArmourValue")
        local slat = av and av:GetAttribute("SlatArmour") or 0
        if type(slat) ~= "number" then slat = tonumber(slat) or 0 end
        if not shell.InfGun then
            slat = slat ^ 2
        end
        effPen = effPen * math.clamp(1 - slat, 0, 1)
    end

    local rico, retention = ricochetCheck(shell, angleDeg, hit.speed or 0, flatArmor or 0)

    local verdict
    if rico == "yes" then
        verdict = "RICOCHET"
    elseif rico == "risk" then
        verdict = "RICOCHET_RISK"
        effPen = effPen * retention
    elseif effPen >= los then
        verdict = "PEN"
    else
        verdict = "NO_PEN"
    end

    return {
        verdict = verdict,
        effPen = effPen,
        penAtRange = penAtRange,
        initialPen = shell.ShellMaxPen or shell.InitialPen or 0,
        armor = los,
        angle = angleDeg,
        distanceM = (hit.distanceStuds or 0) * STUD_TO_M,
        composite = composite,
        shellType = shell.ShellType,
        apfsds = isApfsds(shell),
    }
end

PenCheck._penRetention = penRetention
PenCheck._armorAtHit = armorAtHit
PenCheck._effectivePen = effectivePen
PenCheck._ricochetCheck = ricochetCheck
PenCheck._measurePartThickness = measurePartThickness
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BC = {
    GRAVITY = -49.0,
    SIM_DT = 1 / 45,
    MAX_STEPS = 2000,
    MAX_RICOCHETS = 2,
    MAX_RAY_DIST = 1024,
    MAX_STUDS = 12000,
    RICOCHET_ANGLE_SCALE = 0.75,
    COLOR_BULLET = Color3.fromRGB(255, 200, 0),
    COLOR_IMPACT = Color3.fromRGB(255, 60, 60),
    IMPACT_MIN_SIZE = 1.5,
    IMPACT_ANGULAR = 0.011,
    IMPACT_MAX_SIZE = 45,
    RESOLVE_CACHE_TTL = 0.30,
    TRAJECTORY_EPS_SQ = 0.0009,
    TRAJECTORY_DOT = 0.999995,
    TRAJECTORY_MAX_AGE = 0.05,
}

local BS = {
    ShellModulesCache = nil,
    BulletLineFolder = nil,
    BulletLinePool = {},
    BulletResolveCache = { at = 0, vehicle = nil, resolved = nil, weapon = nil, loaded = nil },
    BulletLastMuzzlePos = nil,
    BulletLastMuzzleDir = nil,
    BulletLastSpeed = nil,
    BulletLastAt = 0,
}
BulletLineActive = 0
BulletLastTrajectory = nil

BulletLastImpact = nil
BulletLastShell = nil

local function getShellModules()
    if BS.ShellModulesCache then
        return BS.ShellModulesCache
    end
    local ok, mod = pcall(function()

        local shellPath = ReplicatedStorage:WaitForChild("PHRST"):WaitForChild("ShellModules")
        return (require :: any)(shellPath)
    end)
    if ok and type(mod) == "table" then
        BS.ShellModulesCache = mod
        return mod
    end
    return nil
end

local function findMuzzleAttachment(muzzlePart)
    if not muzzlePart or not muzzlePart:IsA("BasePart") then return nil end
    local gfp = muzzlePart:FindFirstChild("GunFirePoint1")
        or muzzlePart:FindFirstChild("GunFirePoint")
        or muzzlePart:FindFirstChild("FirePoint")
        or muzzlePart:FindFirstChild("Muzzle")
        or muzzlePart:FindFirstChildWhichIsA("Attachment")
    return gfp
end

local function muzzleToBasePart(value)
    local cur = value
    for _ = 1, 5 do
        if cur == nil then return nil end
        if cur:IsA("BasePart") then return cur end
        if cur:IsA("ObjectValue") then
            cur = cur.Value
        else
            return nil
        end
    end
    return nil
end

local function resolveActiveWeaponAndTurret(vehicle)
    local ReplicatedFirst = game:GetService("ReplicatedFirst")
    local ngd = ReplicatedFirst:FindFirstChild("NewGuiData")
    local gunner = ngd and ngd:FindFirstChild("Gunner")

    local curSelected = gunner and gunner:FindFirstChild("Weapons")
        and gunner.Weapons:FindFirstChild("Data")
        and gunner.Weapons.Data:FindFirstChild("CurrentlySelected")
        and gunner.Weapons.Data.CurrentlySelected.Value
    if curSelected and (curSelected:IsA("Folder") or curSelected:IsA("Model") or curSelected:IsA("Configuration")) and curSelected:IsDescendantOf(vehicle) then
        local loaded = curSelected:FindFirstChild("CurrentlyLoaded")
        if loaded and loaded:IsA("StringValue") and loaded.Value ~= "" and loaded.Value ~= "Unloaded" and curSelected.Name ~= "Smoke Grenade" then
            local turret = curSelected.Parent and curSelected.Parent.Parent
            return curSelected, turret
        end
    end

    local opTurret = gunner and gunner:FindFirstChild("Data")
        and gunner.Data:FindFirstChild("OperatingTurret")
        and gunner.Data.OperatingTurret.Value
    if opTurret and (opTurret:IsA("Folder") or opTurret:IsA("Model")) and opTurret:IsDescendantOf(vehicle) then
        local wFolder = opTurret:FindFirstChild("Weapons")
        if wFolder then
            for _, w in ipairs(wFolder:GetChildren()) do
                local loaded = w:FindFirstChild("CurrentlyLoaded")
                if loaded and loaded:IsA("StringValue") and loaded.Value ~= "" and loaded.Value ~= "Unloaded" and w.Name ~= "Smoke Grenade" then
                    return w, opTurret
                end
            end
        end
    end

    local char = currentCharacter()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local plySeat = hum and hum.SeatPart
    local turrets = vehicle:FindFirstChild("Turrets")
    if turrets and plySeat and plySeat:IsDescendantOf(vehicle) then
        for _, t in ipairs(turrets:GetChildren()) do
            local ctrl = t:FindFirstChild("Control")
            local isMatch = false
            if ctrl and ctrl:IsA("ObjectValue") and ctrl.Value then
                if ctrl.Value == plySeat or ctrl.Value.Name == plySeat.Name then
                    isMatch = true
                end
            elseif ctrl and (ctrl:IsA("StringValue") or ctrl:IsA("ValueBase")) then
                if tostring(ctrl.Value) == plySeat.Name then
                    isMatch = true
                end
            end
            if not isMatch and plySeat:IsDescendantOf(t) then
                isMatch = true
            end

            if isMatch then
                local wFolder = t:FindFirstChild("Weapons")
                if wFolder then
                    for _, w in ipairs(wFolder:GetChildren()) do
                        local loaded = w:FindFirstChild("CurrentlyLoaded")
                        if loaded and loaded:IsA("StringValue") and loaded.Value ~= "" and loaded.Value ~= "Unloaded" and w.Name ~= "Smoke Grenade" then
                            return w, t
                        end
                    end
                end
            end
        end
    end

    if turrets then
        local t1 = turrets:FindFirstChild("Turret1") or turrets:FindFirstChildWhichIsA("Model") or turrets:FindFirstChildWhichIsA("Folder")
        if t1 then
            local wFolder = t1:FindFirstChild("Weapons")
            if wFolder then
                for _, w in ipairs(wFolder:GetChildren()) do
                    local loaded = w:FindFirstChild("CurrentlyLoaded")
                    if loaded and loaded:IsA("StringValue") and loaded.Value ~= "" and loaded.Value ~= "Unloaded" and w.Name ~= "Smoke Grenade" then
                        return w, t1
                    end
                end
            end
        end
        for _, t in ipairs(turrets:GetChildren()) do
            local wFolder = t:FindFirstChild("Weapons")
            if wFolder then
                for _, w in ipairs(wFolder:GetChildren()) do
                    local loaded = w:FindFirstChild("CurrentlyLoaded")
                    if loaded and loaded:IsA("StringValue") and loaded.Value ~= "" and loaded.Value ~= "Unloaded" and w.Name ~= "Smoke Grenade" then
                        return w, t
                    end
                end
            end
        end
    end

    return nil, nil
end

resolveVehicleMuzzleAndShell = function(vehicle)
    local now = os.clock()
    local cache = BS.BulletResolveCache

    local activeWeapon, activeTurret = resolveActiveWeaponAndTurret(vehicle)
    if not activeWeapon then
        return nil
    end

    local loaded = activeWeapon:FindFirstChild("CurrentlyLoaded")
    if not loaded or not loaded:IsA("StringValue") or loaded.Value == "Unloaded" or loaded.Value == "" then
        return nil
    end

    local ttlOk = cache.at and (now - cache.at) < BC.RESOLVE_CACHE_TTL
    local sameVehicle = cache.vehicle == vehicle
    local sameWeapon = cache.weapon == activeWeapon
    local sameLoaded = cache.loaded and cache.loaded.Parent and cache.resolved and cache.resolved.loadedValue ~= nil and cache.loaded.Value == cache.resolved.loadedValue and cache.loaded.Value == loaded.Value
    local muzzleStillLive = cache.resolved and cache.resolved.muzzleAttachment and cache.resolved.muzzleAttachment.Parent

    local cmStillSame = true
    if cache.weapon and cache.weapon.Parent and cache.resolved and cache.resolved.currentMuzzlePart ~= nil then
        local cmOv = cache.weapon:FindFirstChild("CurrentMuzzle")
        local cur = cmOv and cmOv:IsA("ObjectValue") and cmOv.Value or nil
        cmStillSame = (cur == cache.resolved.currentMuzzlePart)
    end

    if ttlOk and sameVehicle and sameWeapon and sameLoaded and muzzleStillLive and cmStillSame then
        local muzzleAtt = cache.resolved.muzzleAttachment
        cache.resolved.worldCFrame = muzzleAtt.WorldCFrame
        return cache.resolved
    end

    local shellModules = getShellModules()
    if not shellModules then
        return nil
    end

    local muzzlePart = nil
    local muzzleOV = activeWeapon:FindFirstChild("Muzzle")
    if muzzleOV then
        muzzlePart = muzzleToBasePart(muzzleOV)
    end
    if not muzzlePart then
        local cmOV = activeWeapon:FindFirstChild("CurrentMuzzle")
        if cmOV then
            muzzlePart = muzzleToBasePart(cmOV)
        end
    end
    if not muzzlePart then
        local directMuzzle = activeWeapon:FindFirstChild("Muzzle") or activeWeapon:FindFirstChild("MGMuzzle")
        if directMuzzle and directMuzzle:IsA("BasePart") then
            muzzlePart = directMuzzle
        end
    end
    if not muzzlePart then
        return nil
    end

    local gfp = findMuzzleAttachment(muzzlePart)
    if not gfp or not gfp:IsA("Attachment") then
        return nil
    end

    local key = activeWeapon.Name .. ":" .. loaded.Value
    local shellData = shellModules[key]
    if not shellData or type(shellData) ~= "table" or not shellData.MuzzleSpeed then
        for k, v in pairs(shellModules) do
            if type(v) == "table" and v.MuzzleSpeed then
                local ammoName = k:match(":(.+)$")
                if ammoName and ammoName == loaded.Value then
                    shellData = v
                    break
                end
            end
        end
    end
    if not shellData or not shellData.MuzzleSpeed then
        return nil
    end

    local curMuzzlePart = nil
    do
        local cmCheck = activeWeapon:FindFirstChild("CurrentMuzzle")
        if cmCheck and cmCheck:IsA("ObjectValue") then curMuzzlePart = cmCheck.Value end
    end

    local resolved = {
        worldCFrame = gfp.WorldCFrame,
        muzzleAttachment = gfp,
        muzzlePart = muzzlePart,
        currentMuzzlePart = curMuzzlePart,
        muzzleSpeed = shellData.MuzzleSpeed,
        ricochetAngle = shellData.RicochetAngle or 80,
        shellData = shellData,
        loadedValue = loaded.Value,
        turret = activeTurret,
        weapon = activeWeapon,
    }

    BS.BulletResolveCache = {
        at = now,
        vehicle = vehicle,
        resolved = resolved,
        weapon = activeWeapon,
        loaded = loaded,
    }
    return resolved
end

local function simulateTrajectory(origin, direction, speed, ricochetAngleDeg, excludeInstances)
    local positions = { origin }
    local pos = origin
    local vel = direction.Unit * speed
    local bounces = 0
    local traveled = 0
    local impact = nil
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = excludeInstances or {}
    params.IgnoreWater = false

    for step = 1, BC.MAX_STEPS do

        local nextVel = Vector3.new(vel.X, vel.Y + BC.GRAVITY * BC.SIM_DT, vel.Z)
        local displacement = (vel + nextVel) * (0.5 * BC.SIM_DT)
        vel = nextVel
        local dist = displacement.Magnitude
        if dist > BC.MAX_RAY_DIST then
            displacement = displacement.Unit * BC.MAX_RAY_DIST
            dist = BC.MAX_RAY_DIST
        end
        traveled += dist

        if traveled > BC.MAX_STUDS then
            break
        end

        local result = Workspace:Raycast(pos, displacement, params)
        if result then
            table.insert(positions, result.Position)

            impact = {
                part = result.Instance,
                position = result.Position,
                normal = result.Normal,
                distanceStuds = traveled,
                speed = vel.Magnitude,
                direction = vel.Unit,
            }
            if bounces >= BC.MAX_RICOCHETS then
                break
            end

            local dot = math.clamp(vel.Unit:Dot(-result.Normal), -1, 1)
            local angleDeg = math.deg(math.acos(dot)) * BC.RICOCHET_ANGLE_SCALE
            if ricochetAngleDeg <= angleDeg then
                local reflected = vel - 2 * vel:Dot(result.Normal) * result.Normal

                local grazing = math.clamp((angleDeg - ricochetAngleDeg) / math.max(90 - ricochetAngleDeg, 1), 0, 1)
                local retention = 0.45 + 0.45 * grazing
                vel = reflected.Unit * vel.Magnitude * retention
                pos = result.Position + result.Normal * 0.2
                bounces += 1
                impact = nil
            else
                break
            end
        else
            pos = pos + displacement
            table.insert(positions, pos)
        end
    end

    return positions, impact
end

local function ensureBulletLineFolder()
    if rawget(_G, "__VISION_POOL_INVALIDATED") then
        BS.BulletLineFolder = nil
        BS.BulletLinePool = {}
        BulletLineActive = 0
        BS.BulletLastMuzzlePos = nil
        BS.BulletLastMuzzleDir = nil
        BS.BulletLastSpeed = nil
        BulletLastTrajectory = nil
        BulletLastImpact = nil
        BulletLastShell = nil
        BS.BulletLastAt = 0
        rawset(_G, "__VISION_POOL_INVALIDATED", nil)
    end
    if BS.BulletLineFolder and BS.BulletLineFolder.Parent then
        return BS.BulletLineFolder
    end
    BS.BulletLineFolder = Instance.new("Folder")
    BS.BulletLineFolder.Name = "VisionBulletLines"
    BS.BulletLineFolder:SetAttribute("VisionOwner", ownerToken)
    BS.BulletLineFolder.Parent = Workspace

    BS.BulletLinePool = {}
    BulletLineActive = 0
    return BS.BulletLineFolder
end

local function acquireBulletPart(folder, index)
    local part = BS.BulletLinePool[index]
    if part and part.Parent then
        return part
    end
    part = Instance.new("Part")
    part.Name = "BulletSegment"
    part:SetAttribute("VisionOwner", ownerToken)
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Parent = folder
    BS.BulletLinePool[index] = part
    return part
end

local function hideExcessBulletParts(fromIndex)
    for i = fromIndex, #BS.BulletLinePool do
        local part = BS.BulletLinePool[i]
        if part and part.Parent then
            part.Transparency = 1
        end
    end
end

clearBulletLines = function()

    if BS.BulletLineFolder and BS.BulletLineFolder.Parent then
        for _, part in ipairs(BS.BulletLinePool) do
            if part and part.Parent then
                part.Transparency = 1
            end
        end
    end
    BulletLineActive = 0
    BS.BulletLastMuzzlePos = nil
    BS.BulletLastMuzzleDir = nil
    BS.BulletLastSpeed = nil
    BulletLastTrajectory = nil
    BulletLastImpact = nil
    BulletLastShell = nil
    BS.BulletLastAt = 0
end

local function destroyBulletLines()
    if BS.BulletLineFolder and BS.BulletLineFolder.Parent then
        pcall(function()
            BS.BulletLineFolder:Destroy()
        end)
    end
    BS.BulletLineFolder = nil
    BS.BulletLinePool = {}
    BulletLineActive = 0
    BS.BulletLastMuzzlePos = nil
    BS.BulletLastMuzzleDir = nil
    BS.BulletLastSpeed = nil
    BulletLastTrajectory = nil
    BulletLastImpact = nil
    BulletLastShell = nil
    BS.BulletLastAt = 0
end

local function renderBulletLine(positions, color)
    local folder = ensureBulletLineFolder()
    local baseThickness = cfg.bulletLineThickness
    local written = 0

    local camPos = nil
    local cam = Workspace.CurrentCamera
    if cam then camPos = cam.CFrame.Position end
    local drawLimit = cfg.bulletLineDistance
    if type(drawLimit) ~= "number" or drawLimit <= 0 then drawLimit = nil end

    for i = 1, #positions - 1 do
        local p1 = positions[i]
        local p2 = positions[i + 1]
        local delta = p2 - p1
        local dist = delta.Magnitude
        if dist >= 0.01 then
            local midpoint = (p1 + p2) * 0.5
            local camDist = camPos and (midpoint - camPos).Magnitude or 0
            local withinDraw = (not drawLimit) or (not camPos) or camDist <= drawLimit
            if withinDraw then
                written += 1
                local part = acquireBulletPart(folder, written)

                part.Size = Vector3.new(baseThickness, baseThickness, dist)
                part.CFrame = CFrame.lookAt(midpoint, p2)
                part.Color = color
                part.Transparency = 0
            end
        end
    end

    local impact = positions[#positions]
    if impact and #positions > 1 then
        written += 1
        local marker = acquireBulletPart(folder, written)
        local mult = cfg.bulletLineImpactSize or 1.0
        local camDist = camPos and (impact - camPos).Magnitude or 0
        local size = math.clamp(
            math.max(BC.IMPACT_MIN_SIZE * mult, camDist * BC.IMPACT_ANGULAR * mult),
            BC.IMPACT_MIN_SIZE * mult,
            BC.IMPACT_MAX_SIZE * mult
        )
        marker.Size = Vector3.new(size, size, size)
        marker.CFrame = CFrame.new(impact)
        marker.Color = BC.COLOR_IMPACT
        marker.Transparency = 0.35
    end

    if written < BulletLineActive then
        hideExcessBulletParts(written + 1)
    end
    BulletLineActive = written
end

local function processBulletLines(_origin, localVehicle, vehicleCache)

    local lineOn = cfg.bulletLine
    local simNeeded = lineOn or (cfg.penIndicator and cfg.penMode == "impact")
    if not simNeeded then

        if BulletLineActive > 0 or BulletLastTrajectory ~= nil then
            clearBulletLines()
        end
        return
    end
    if not localVehicle then

        if BulletLineActive > 0 or BulletLastTrajectory ~= nil then
            clearBulletLines()
        end
        return
    end

    do
        local cached = vehicleCache and vehicleCache[localVehicle]
        local hasBox = cached and cached.boxCFrame ~= nil
        if not hasBox then
            local ok, bc = pcall(function() return localVehicle:GetBoundingBox() end)
            if not ok or not bc then return end
        end
    end
    local resolved = resolveVehicleMuzzleAndShell(localVehicle)
    if not resolved then
        if BulletLineActive > 0 or BulletLastTrajectory ~= nil then
            clearBulletLines()
        end
        return
    end
    local muzzleCF = resolved.worldCFrame
    local muzzlePos = muzzleCF.Position
    local muzzleDir = muzzleCF.LookVector
    local speed = resolved.muzzleSpeed
    local ricochetAngle = resolved.ricochetAngle

    local now = os.clock()

    local function renderOrHide(shiftedPositions)
        if lineOn then
            renderBulletLine(shiftedPositions, BC.COLOR_BULLET)
        elseif BulletLineActive > 0 then
            hideExcessBulletParts(1)
            BulletLineActive = 0
        end
    end

    local canReuse = BulletLastTrajectory ~= nil
        and BS.BulletLastMuzzlePos ~= nil
        and BS.BulletLastMuzzleDir ~= nil
        and BS.BulletLastSpeed == speed
        and (type(now) == "number" and type(BS.BulletLastAt) == "number" and type(BC.TRAJECTORY_MAX_AGE) == "number"
            and (now - BS.BulletLastAt) < BC.TRAJECTORY_MAX_AGE)
        and (muzzlePos - BS.BulletLastMuzzlePos).Magnitude ^ 2 < BC.TRAJECTORY_EPS_SQ
        and muzzleDir:Dot(BS.BulletLastMuzzleDir) > BC.TRAJECTORY_DOT
    if canReuse then

        local delta = muzzlePos - BS.BulletLastMuzzlePos
        if delta.Magnitude ^ 2 >= 1e-6 then
            local shifted = {}
            for i = 1, #BulletLastTrajectory do
                shifted[i] = BulletLastTrajectory[i] + delta
            end
            renderOrHide(shifted)
        else
            renderOrHide(BulletLastTrajectory)
        end
        return
    end

    local exclude = {}
    pcall(function()
        local cam = Workspace.CurrentCamera
        if cam then table.insert(exclude, cam) end
        local char = currentCharacter()
        if char then table.insert(exclude, char) end
        if localVehicle then table.insert(exclude, localVehicle) end
    end)
    local positions, impact = simulateTrajectory(muzzlePos, muzzleDir, speed, ricochetAngle, exclude)
    BS.BulletLastMuzzlePos = muzzlePos
    BS.BulletLastMuzzleDir = muzzleDir
    BS.BulletLastSpeed = speed
    BulletLastTrajectory = positions
    BulletLastImpact = impact
    BulletLastShell = resolved.shellData
    BS.BulletLastAt = now
    renderOrHide(positions)
end

local PEN_MAX_AIM_DIST = 6000

local PS = {
    Folder = nil,
    Part = nil,
    Gui = nil,
    TitleLabel = nil,
    BodyLabel = nil,
    Visible = false,
    LastText = nil,
}

local VERDICT_COLORS = {
    PEN = Color3.fromRGB(60, 230, 120),
    NO_PEN = Color3.fromRGB(255, 70, 70),
    RICOCHET = Color3.fromRGB(255, 200, 40),
    RICOCHET_RISK = Color3.fromRGB(255, 200, 40),
}

local VERDICT_TEXT = {
    PEN = "PEN",
    NO_PEN = "NO PEN",
    RICOCHET = "RICOCHET",
    RICOCHET_RISK = "RICOCHET?",
}

local PEN_IMMUNE_ARMOR = 1e6

local function ensurePenIndicator()
    if PS.Folder and PS.Folder.Parent and PS.Part and PS.Part.Parent then
        return
    end
    PS.Folder = Instance.new("Folder")
    PS.Folder.Name = "VisionPenIndicator"
    PS.Folder:SetAttribute("VisionOwner", ownerToken)
    PS.Folder.Parent = Workspace

    local part = Instance.new("Part")
    part.Name = "PenAnchor"
    part:SetAttribute("VisionOwner", ownerToken)
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Transparency = 1
    part.Size = Vector3.new(0.2, 0.2, 0.2)
    part.Parent = PS.Folder

    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.fromOffset(230, 62)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.ResetOnSpawn = false
    gui.Parent = part

    local title = Instance.new("TextLabel")
    title.Name = "Verdict"
    title.Size = UDim2.new(1, 0, 0, 24)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Text = ""
    title.TextColor3 = Color3.new(1, 1, 1)
    title.TextStrokeTransparency = 0.4
    title.Parent = gui

    local body = Instance.new("TextLabel")
    body.Name = "Details"
    body.Size = UDim2.new(1, 0, 0, 36)
    body.Position = UDim2.new(0, 0, 0, 24)
    body.BackgroundTransparency = 1
    body.Font = Enum.Font.Gotham
    body.TextSize = 12
    body.Text = ""
    body.TextWrapped = true
    body.TextColor3 = Color3.fromRGB(235, 235, 235)
    body.TextStrokeTransparency = 0.4
    body.Parent = gui

    PS.Part = part
    PS.Gui = gui
    PS.TitleLabel = title
    PS.BodyLabel = body
    PS.LastText = nil
end

hidePenIndicator = function()
    if PS.Visible then
        if PS.Gui then
            PS.Gui.Enabled = false
        end
        PS.Visible = false
    end
end

local function showPenIndicator(position, result)
    ensurePenIndicator()
    PS.Part.CFrame = CFrame.new(position)

    local verdictText = VERDICT_TEXT[result.verdict] or tostring(result.verdict)

    local armorText
    if result.armor >= PEN_IMMUNE_ARMOR then
        armorText = "∞"
    else
        armorText = string.format("%.0f mm%s", result.armor, result.composite and " (comp)" or "")
    end

    local body = string.format(
        "Pen %.0f/%.0f mm | Armor %s\nAngle %.0f° | Range %.0f m",
        result.effPen,
        result.initialPen,
        armorText,
        result.angle,
        result.distanceM
    )

    local key = verdictText .. "|" .. body
    if key ~= PS.LastText then
        PS.TitleLabel.Text = verdictText
        PS.TitleLabel.TextColor3 = VERDICT_COLORS[result.verdict] or Color3.new(1, 1, 1)
        PS.BodyLabel.Text = body
        PS.LastText = key
    end
    PS.Gui.Enabled = true
    PS.Visible = true
end

local function evaluateAimRay(camera, localVehicle)
    local resolved = resolveVehicleMuzzleAndShell(localVehicle)
    if not resolved or not resolved.shellData then
        return nil, nil
    end

    local exclude = {}
    pcall(function()
        table.insert(exclude, camera)
        local char = currentCharacter()
        if char then table.insert(exclude, char) end
        table.insert(exclude, localVehicle)
    end)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclude
    params.IgnoreWater = false

    local ray = Workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * PEN_MAX_AIM_DIST, params)
    if not ray then
        return nil, nil
    end

    local offset = ray.Position - resolved.worldCFrame.Position
    local distanceStuds = offset.Magnitude
    if distanceStuds < 0.01 then
        distanceStuds = 0.01
    end
    local hit = {
        part = ray.Instance,
        position = ray.Position,
        normal = ray.Normal,
        distanceStuds = distanceStuds,
        speed = resolved.muzzleSpeed,
        direction = offset / distanceStuds,
    }
    return resolved.shellData, hit
end

processPenIndicator = function(camera, localVehicle)
    if not cfg.penIndicator or not localVehicle then
        hidePenIndicator()
        return
    end

    local shell, hit
    if cfg.penMode == "aim" then
        shell, hit = evaluateAimRay(camera, localVehicle)
    else

        shell, hit = BulletLastShell, BulletLastImpact
    end
    if not shell or not hit then
        hidePenIndicator()
        return
    end

    local ok, result = pcall(PenCheck.evaluate, shell, hit)
    if not ok or not result then

        hidePenIndicator()
        return
    end
    showPenIndicator(hit.position, result)
end
local function processVehicleModel(
    vehicle,
    rayContext,
    origin,
    localAliases,
    vehicleCache
)
    if not vehicle:IsA("Model") then
        return false
    end
    local cached = vehicleCache and vehicleCache[vehicle]
    local anchor, targetPosition, offsetWorld = nil, nil, nil
    if cached then
        anchor = cached.anchor
        targetPosition = cached.boxCFrame and cached.boxCFrame.Position
        offsetWorld = cached.offsetWorld
    end
    if not anchor or not targetPosition or not offsetWorld then
        return false
    end
    local distanceM = meters((targetPosition - origin).Magnitude)
    if distanceM > cfg.vehicleDistance then
        return false
    end

    local classification = vehicleClassificationFromCache(vehicle, localAliases, vehicleCache)
    local enemy = classification ~= false
    local allowedByTeamcheck = not cfg.vehicleTeamcheck or (classification ~= nil and enemy)
    if not allowedByTeamcheck then
        return false
    end

    local entry = ensureEntry(vehicle)
    local color = enemy and COLOR_ENEMY or COLOR_FRIENDLY
    if cfg.vehicleCharm then
        updateHighlight(vehicle, entry, color, cfg.vehicleWallcheck)
    elseif not removeHighlight(entry) then
        error("vehicle-highlight-cleanup-failed")
    end

    if cfg.vehicleInfo then
        local displayName = vehicle:GetAttribute("VehicleDisplayName") or vehicle.Name
        local className = vehicle:GetAttribute("VehicleClass") or "Vehicle"
        local text = displayName .. "\n" .. tostring(className) .. "\n" .. distanceM .. " m"
        local visible
        if not cfg.vehicleWallcheck then
            visible = true
        elseif rayContext and not isOnScreen(rayContext.camera, targetPosition) then
            visible = false
        else
            visible = visibleFromCamera(rayContext, vehicle, targetPosition, nil)
        end
        updateLabel(vehicle, entry, anchor, offsetWorld, color, text, visible, cfg.vehicleWallcheck)
    elseif not removeLabel(entry) then
        error("vehicle-label-cleanup-failed")
    end

    finishEntry(vehicle, entry)
    return true
end

local function processPlayerModel(
    model,
    rayContext,
    origin,
    vehiclesFolder,
    vehicleCache
)
    if not model:IsA("Model") then
        return false
    end
    local player = playerForModel(model)
    if not player or player == LocalPlayer then
        return false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    local anchor = model:FindFirstChild("Head") or root or firstBasePart(model)
    if not humanoid or humanoid.Health <= 0 or not root or not anchor then
        return false
    end

    local distanceM = meters((root.Position - origin).Magnitude)
    if distanceM > cfg.playerDistance then
        return false
    end

    local classification = playerClassification(player)
    local enemy = classification ~= false
    local allowedByTeamcheck = not cfg.playerTeamcheck or (classification ~= nil and enemy)
    if not allowedByTeamcheck then
        return false
    end

    local entry = ensureEntry(model)
    local color = enemy and COLOR_ENEMY or COLOR_FRIENDLY
    local occupiedVehicle = playerVehicle(humanoid, vehiclesFolder)

    if cfg.playerCharm then
        updateHighlight(model, entry, color, cfg.playerWallcheck)
    elseif not removeHighlight(entry) then
        error("player-highlight-cleanup-failed")
    end

    if cfg.playerInfo then
        local text = player.Name .. "\n" .. distanceM .. " m"
        if occupiedVehicle then
            local vehicleName = occupiedVehicle:GetAttribute("VehicleDisplayName") or occupiedVehicle.Name
            text = text .. "\n" .. vehicleName
        end
        local labelTarget = occupiedVehicle or model
        local gap = 1.5
        if occupiedVehicle then
            local slot = crewLabelSlot(occupiedVehicle, player, vehicleCache)
            gap = 5.0 + (slot - 1) * CREW_LABEL_SPACING
        end
        local offsetWorld = labelOffsetAboveModel(labelTarget, anchor, gap, vehicleCache)
        if offsetWorld then
            local visible
            if not cfg.playerWallcheck then
                visible = true
            elseif rayContext and not isOnScreen(rayContext.camera, root.Position) then
                visible = false
            else
                visible = visibleFromCamera(rayContext, model, root.Position, occupiedVehicle)
            end
            updateLabel(model, entry, anchor, offsetWorld, color, text, visible, cfg.playerWallcheck)
        elseif not removeLabel(entry) then
            error("player-label-geometry-cleanup-failed")
        end
    elseif not removeLabel(entry) then
        error("player-label-cleanup-failed")
    end

    finishEntry(model, entry)
    return true
end

local function recordRefreshError(err)
    owner.refreshErrorCount += 1
    owner.lastRefreshError = tostring(err)
end

local function refresh()
    if owner.stopped then
        return
    end
    if rawget(_G, OWNER_KEY) ~= owner then
        stop("owner-replaced")
        return
    end
    if type(liveState) == "table" and type(liveState.alive) == "function" then
        local ok, alive = pcall(liveState.alive)
        if ok and alive == false then
            stop("live-reload-replaced")
            return
        end
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        clearVisuals()
        return
    end

    local localCharacter = currentCharacter()
    local origin = distanceOrigin(camera, localCharacter)
    local localAliases = teamAliasesForPlayer(LocalPlayer)
    local vehiclesFolder = Workspace:FindFirstChild("SpawnedVehicles")
    local playersFolder = Workspace:FindFirstChild("SpawnedPlayers")
    local localHumanoid = localCharacter and localCharacter:FindFirstChildOfClass("Humanoid")
    local localVehicle = playerVehicle(localHumanoid, vehiclesFolder)
    local rayContext = createRayContext(camera, localCharacter, localVehicle)
    local wanted = {}

    local vehicleCache = {}
    if vehiclesFolder and (cfg.vehicleCharm or cfg.vehicleInfo or cfg.playerInfo or cfg.bulletLine) then
        for _, vehicle in vehiclesFolder:GetChildren() do
            if vehicle:IsA("Model") then
                local cached = buildVehicleCache(vehicle)
                if cached then
                    vehicleCache[vehicle] = cached
                end
            end
        end
    end

    if vehiclesFolder and (cfg.vehicleCharm or cfg.vehicleInfo) then
        for _, vehicle in vehiclesFolder:GetChildren() do
            local ok, keep = pcall(processVehicleModel, vehicle, rayContext, origin, localAliases, vehicleCache)
            if ok and keep then
                wanted[vehicle] = true
            elseif not ok then
                hideEntry(owner.visuals[vehicle])
                recordRefreshError(keep)
            end
        end
    end

    if playersFolder and (cfg.playerCharm or cfg.playerInfo) then
        for _, model in playersFolder:GetChildren() do
            local ok, keep = pcall(
                processPlayerModel,
                model,
                rayContext,
                origin,
                vehiclesFolder,
                vehicleCache
            )
            if ok and keep then
                wanted[model] = true
            elseif not ok then
                hideEntry(owner.visuals[model])
                recordRefreshError(keep)
            end
        end
    end

    local stale = {}
    for model in pairs(owner.visuals) do
        if not wanted[model] or not model.Parent then
            table.insert(stale, model)
        end
    end
    for _, model in stale do
        if not removeVisual(model) then
            recordRefreshError("stale-cleanup-failed")
        end
    end

    if cfg.bulletLine and localVehicle == nil and (BulletLineActive > 0 or BulletLastTrajectory ~= nil) then
        clearBulletLines()
    end
end

local BULLET_INTERVAL = 0.04
local bulletElapsed = 0
local function bulletTick(deltaTime)
    if owner.stopped then return end

    if not cfg.bulletLine and not cfg.penIndicator then
        if BulletLineActive > 0 or BulletLastTrajectory ~= nil then
            clearBulletLines()
        end
        hidePenIndicator()
        return
    end
    bulletElapsed += deltaTime
    if bulletElapsed < BULLET_INTERVAL then return end
    bulletElapsed = 0

    local camera = Workspace.CurrentCamera
    if not camera then return end
    local localCharacter = currentCharacter()
    local localHumanoid = localCharacter and localCharacter:FindFirstChildOfClass("Humanoid")
    local vehiclesFolder = Workspace:FindFirstChild("SpawnedVehicles")
    local localVehicle = playerVehicle(localHumanoid, vehiclesFolder)
    if not localVehicle then
        if BulletLineActive > 0 or BulletLastTrajectory ~= nil then
            clearBulletLines()
        end
        hidePenIndicator()
        return
    end
    local origin = distanceOrigin(camera, localCharacter)

    local vehicleCacheForBullet = {}
    local cached = vehicleCacheStore[localVehicle]
    if not cached then
        local fresh = buildVehicleCache(localVehicle)
        if fresh then vehicleCacheStore[localVehicle] = fresh; vehicleCacheForBullet[localVehicle] = fresh end
    else

        local now = os.clock()
        if cached.anchor and (cached.bboxAt == nil or (now - cached.bboxAt) > BBOX_MAX_AGE or cached.boxCFrame == nil) then
            local ok, bf, bs = pcall(function() return localVehicle:GetBoundingBox() end)
            if ok and bf then
                cached.boxCFrame = bf; cached.boxSize = bs
                cached.offsetWorld = cached.anchor and labelOffsetFromBox(bf, bs, cached.anchor, 2.5) or cached.offsetWorld
                cached.bboxAt = now; cached.lastAnchorPos = cached.anchor and cached.anchor.Position or cached.lastAnchorPos
            end
        end
        vehicleCacheForBullet[localVehicle] = cached
    end
    local ok, err = pcall(processBulletLines, origin, localVehicle, vehicleCacheForBullet)
    if not ok then recordRefreshError(err) end

    local penOk, penErr = pcall(processPenIndicator, camera, localVehicle)
    if not penOk then recordRefreshError(penErr) end
end

local function runRefresh()
    local ok, err = pcall(refresh)
    if not ok then
        hideOwnedVisuals()
        recordRefreshError(err)
        return false
    end
    return true
end

owner.snapshot = function()
    local highlightCount = 0
    local labelCount = 0
    local visibleLabelCount = 0
    local playerHighlightCount = 0
    local playerLabelCount = 0
    local vehicleHighlightCount = 0
    local vehicleLabelCount = 0
    local playersFolder = Workspace:FindFirstChild("SpawnedPlayers")
    local vehiclesFolder = Workspace:FindFirstChild("SpawnedVehicles")

    for model, entry in pairs(owner.visuals) do
        if entry.highlight and entry.highlight.Parent then
            highlightCount += 1
            if playersFolder and model.Parent == playersFolder then
                playerHighlightCount += 1
            elseif vehiclesFolder and model.Parent == vehiclesFolder then
                vehicleHighlightCount += 1
            end
        end
        if entry.label and entry.label.Parent then
            labelCount += 1
            if entry.label.Enabled then
                visibleLabelCount += 1
            end
            if playersFolder and model.Parent == playersFolder then
                playerLabelCount += 1
            elseif vehiclesFolder and model.Parent == vehiclesFolder then
                vehicleLabelCount += 1
            end
        end
    end

    local connectionCount = 0
    for _, connection in ipairs(owner.connections) do
        local ok, connected = pcall(function()
            return connection.Connected
        end)
        if ok and connected then
            connectionCount += 1
        end
    end

    return {
        token = ownerToken,
        magic = owner.magic,
        schema = owner.schema,
        stopped = owner.stopped,
        initialized = owner.initialized,
        activeExternalCalls = owner.activeExternalCalls,
        cleanupComplete = owner.cleanupComplete,
        cleanupPending = owner.cleanupPending,
        highlightCount = highlightCount,
        labelCount = labelCount,
        visibleLabelCount = visibleLabelCount,
        playerHighlightCount = playerHighlightCount,
        playerLabelCount = playerLabelCount,
        vehicleHighlightCount = vehicleHighlightCount,
        vehicleLabelCount = vehicleLabelCount,
        connectionCount = connectionCount,
        refreshErrorCount = owner.refreshErrorCount,
        lastRefreshError = owner.lastRefreshError,
        freecamEnabled = freecam.enabled,
        freecamMode = freecam.mode,
        freecamSpeed = freecam.speed,
        freecamFov = freecam.fov,
        reloadAssistEnabled = owner.reloadAssist.enabled,
        reloadAssistSupported = owner.reloadAssist.supported,
        reloadAssistArmed = owner.reloadAssist.armed,
        reloadAssistAttempts = owner.reloadAssist.attempts,
        reloadAssistSuccessInvocations = owner.reloadAssist.successInvocations,
        reloadAssistLastError = owner.reloadAssist.lastError,
        playerWallcheck = cfg.playerWallcheck,
        playerTeamcheck = cfg.playerTeamcheck,
        vehicleWallcheck = cfg.vehicleWallcheck,
        vehicleTeamcheck = cfg.vehicleTeamcheck,
        fillTransparency = cfg.fillTransparency,
        vehicleCharm = cfg.vehicleCharm,
        vehicleInfo = cfg.vehicleInfo,
        playerCharm = cfg.playerCharm,
        playerInfo = cfg.playerInfo,
    }
end

owner.setFlag = function(flag, value)
    if not owner.window or type(owner.window.Set) ~= "function" then
        return false
    end
    return owner.window:Set(flag, value)
end

local refreshRequested = true
local function changed(callback)
    return function(value)
        if owner.stopped then
            return
        end
        callback(value)
        refreshRequested = true
    end
end

local function ownedCall(stage, callback)
    return externalCall(stage, callback)
end

local function initialize()
    if type(liveState) == "table" and type(liveState.onCleanup) == "function" then
        ownedCall("cleanup-registration", function()
            liveState:onCleanup(stop)
        end)
    end

    local Rayfield = loadVerifiedRayfield()
    rawset(_G, PENDING_OWNER_KEY, ownerToken)

    local window = ownedCall("window", function()
        local created = Rayfield:CreateWindow({
            name = "Vision",
            showName = "Vision",

            showIcon = VISION_ICON_ID ~= 0 and ("rbxassetid://" .. VISION_ICON_ID) or nil,
            theme = VISION_THEME,
            configuration = {
                autoSave = true,
                autoLoad = true,
                fileName = "Vision",
                customFolder = "Vision",
            },
        })
        owner.window = created
        tagProjectScreens()

        local devEnv = rawget(_G, "__VISION_DEV")
        if devEnv then
            pcall(function()
                local featureLines = {}
                for k, v in pairs(cfg) do
                    table.insert(featureLines, tostring(k) .. "=" .. tostring(v))
                end
                table.sort(featureLines)
                local stamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                local body = "VISION_FEATURES " .. stamp .. "\n" .. table.concat(featureLines, "\n")
                if devEnv.watchLog then
                    pcall(writefile, devEnv.watchLog, body)
                end
                print("[Vision] FEATURES " .. table.concat(featureLines, " "))
            end)
        end
        return created
    end)
    if rawget(_G, PENDING_OWNER_KEY) == ownerToken then
        rawset(_G, PENDING_OWNER_KEY, nil)
    end

    ownedCall("collapsed-drag", function()
        local collapsed = nil
        for screen in pairs(findProjectScreenGuis()) do
            for _, descendant in screen:GetDescendants() do
                if descendant.Name == "CollapsedInteract" and descendant:IsA("TextButton") then
                    collapsed = descendant
                    break
                end
            end
            if collapsed then break end
        end
        if not collapsed then
            error("collapsed-interact-not-found")
        end

        local frame = collapsed.Parent
        local screen = frame and frame:FindFirstAncestorWhichIsA("ScreenGui")
        local UIS = game:GetService("UserInputService")
        local GuiService = game:GetService("GuiService")
        local POS_FILE = "Vision/vision-pill-pos.txt"

        local pressed = false
        local dragged = false
        local grabOffset = Vector2.zero
        local pressPos = Vector2.zero
        local inset = Vector2.zero

        local function refreshInset()
            inset = (screen and screen.IgnoreGuiInset) and GuiService:GetGuiInset() or Vector2.zero
        end

        local function targetPos()
            local p = UIS:GetMouseLocation() + grabOffset + inset
            local bounds = screen and screen.AbsoluteSize or Vector2.new(10000, 10000)
            local half = frame.AbsoluteSize / 2
            local margin = 8
            local x = math.clamp(p.X, half.X + margin, math.max(half.X + margin, bounds.X - half.X - margin))
            local y = math.clamp(p.Y, half.Y + margin, math.max(half.Y + margin, bounds.Y - half.Y - margin))
            return UDim2.fromOffset(x, y)
        end

        local function savePos()
            pcall(function()
                local makeFolder = rawget(_G, "createfolder")
                if type(makeFolder) == "function" then
                    pcall(makeFolder, "Vision")
                end
                local pos = frame.Position
                writefile(POS_FILE, string.format("%d,%d", pos.X.Offset, pos.Y.Offset))
            end)
        end

        local function readSavedPos()
            local ok, result = pcall(function()
                if type(isfile) == "function" and isfile(POS_FILE) and type(readfile) == "function" then
                    local data = readfile(POS_FILE)
                    local x, y = tostring(data):match("^(-?%d+),(-?%d+)$")
                    local nx = x and tonumber(x) or nil
                    local ny = y and tonumber(y) or nil
                    if nx and ny then
                        return UDim2.fromOffset(nx, ny)
                    end
                end
                return nil
            end)
            return ok and result or nil
        end

        local function applySavedPos()
            local saved = readSavedPos()
            if saved then
                frame.Position = saved
            end
        end

        pcall(function()
            local mt = getmetatable(window)
            local orig = (type(mt) == "table" and mt._collapsedRect) or window._collapsedRect
            if type(orig) == "function" then
                window._collapsedRect = function(w)
                    local pos, size = orig(w)
                    return readSavedPos() or pos, size
                end
            end
        end)

        local overlay = Instance.new("TextButton")
        overlay.Name = "VisionPillInteract"
        overlay.BackgroundTransparency = 1
        overlay.Text = ""
        overlay.TextTransparency = 1
        overlay.AutoButtonColor = false
        overlay.Size = UDim2.fromScale(1, 1)
        overlay.ZIndex = 100003
        overlay:SetAttribute("VisionOwner", ownerToken)
        overlay.Visible = collapsed.Visible
        overlay.Parent = frame

        table.insert(owner.connections, collapsed:GetPropertyChangedSignal("Visible"):Connect(function()
            overlay.Visible = collapsed.Visible
            if collapsed.Visible then
                applySavedPos()
            end
        end))

        table.insert(owner.connections, overlay.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            local t = input.UserInputType
            if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
            pressed = true
            dragged = false
            refreshInset()
            grabOffset = frame.AbsolutePosition + frame.AbsoluteSize * frame.AnchorPoint - UIS:GetMouseLocation()
            pressPos = Vector2.new(input.Position.X, input.Position.Y)
        end))

        table.insert(owner.connections, UIS.InputChanged:Connect(function(input)
            if not (pressed and not dragged) then return end
            local t = input.UserInputType
            if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
            local cur = Vector2.new(input.Position.X, input.Position.Y)
            if (cur - pressPos).Magnitude > 6 then
                dragged = true
            end
        end))

        table.insert(owner.connections, RunService.RenderStepped:Connect(function()
            if pressed and dragged then
                frame.Position = targetPos()
            end
        end))

        table.insert(owner.connections, UIS.InputEnded:Connect(function(input)
            local t = input.UserInputType
            if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
            if not pressed then return end
            pressed = false
            if dragged then
                dragged = false
                savePos()
            else
                window:ToggleHide()
            end
        end))

        table.insert(owner.connections, UIS.WindowFocusReleased:Connect(function()
            pressed = false
            dragged = false
        end))

        if collapsed.Visible then
            applySavedPos()
        end
        return overlay
    end)

    local tab = ownedCall("tab", function()
        return window:CreateTab({ name = "ESP" })
    end)

    local function notify(props)
        if owner.stopped then return end
        local w = owner.window
        if w and type(w.Notify) == "function" then
            pcall(function() w:Notify(props) end)
        end
    end

    local mouseTab = ownedCall("mouseaim-tab", function()
        return window:CreateTab({ name = "MouseAim" })
    end)

    ownedCall("mouseaim-section", function()
        return mouseTab:CreateSection({ name = "Unlock MouseAim (Method A)" })
    end)

    ownedCall("mouseaim-toggle", function()
        return mouseTab:CreateToggle({
            name = "Unlock MouseAim",
            hint = "Solo fallback: TurretInfo.MouseAim or Solo → Enabled. Re-enter the Gunner seat after enabling to rebind.",
            flag = "V3MouseAimUnlock",
            value = mouseAim.unlocked,
            callback = changed(function(value)
                mouseAim.unlocked = value
                if value then
                    local result = enableMouseAim()
                    if result == "seated-no-rebind" then
                        notify({
                            title = "MouseAim Unlocker",
                            content = "Solo=true. Leave and re-enter the Gunner seat so Enabled rebinds, then enable again.",
                            duration = 5,
                            icon = "info",
                        })
                    else
                        local enabled, data = getMouseAimState()
                        notify({
                            title = "MouseAim Unlocker",
                            content = "Solo=true | Enabled=" .. tostring(enabled) .. " Data=" .. tostring(data),
                            duration = 5,
                            icon = "info",
                        })
                    end
                else
                    disableMouseAim()
                    notify({
                        title = "MouseAim Unlocker",
                        content = "Solo=false. Re-enter the seat to rebind (Enabled=false).",
                        duration = 5,
                        icon = "info",
                    })
                end
            end),
        })
    end)

    ownedCall("mouseaim-keybind", function()
        return mouseTab:CreateKeybind({
            name = "Toggle MouseAim",
            value = Enum.KeyCode.J,
            forgetState = true,
            flag = "V3MouseAimKeybind",
            callback = function()
                if owner.stopped then
                    return
                end
                mouseAim.unlocked = not mouseAim.unlocked
                if owner.window and type(owner.window.Set) == "function" then
                    pcall(function()
                        owner.window:Set("V3MouseAimUnlock", mouseAim.unlocked)
                    end)
                end
                if mouseAim.unlocked then
                    local result = enableMouseAim()
                    if result == "seated-no-rebind" then
                        notify({
                            title = "MouseAim Unlocker",
                            content = "Solo=true. Leave and re-enter the Gunner seat so Enabled rebinds.",
                            duration = 5,
                            icon = "info",
                        })
                    end
                else
                    disableMouseAim()
                end
                local enabled, data = getMouseAimState()
                notify({
                    title = "MouseAim Unlocker",
                    content = "ON=" .. tostring(mouseAim.unlocked)
                        .. " | Solo(ws/lp)=" .. tostring(Workspace:GetAttribute("Solo"))
                        .. "/" .. tostring(LocalPlayer:GetAttribute("Solo"))
                        .. " | Enabled=" .. tostring(enabled) .. " Data=" .. tostring(data),
                    duration = 4,
                    icon = "info",
                })
            end,
        })
    end)

    local reloadTab = ownedCall("reload-tab", function()
        return window:CreateTab({ name = "Reload" })
    end)

    ownedCall("reload-section", function()
        return reloadTab:CreateSection({ name = "Quick Reload Assist" })
    end)

    ownedCall("reload-assist-toggle", function()
        local element = nil
        element = reloadTab:CreateToggle({
            name = "Auto Quick Reload",
            hint = "Arms while waiting for the loader minigame; uses its own callback only after verification.",

            forgetState = true,
            value = false,
            callback = function(value)
                if owner.stopped then
                    return
                end
                if value then
                    local ok = owner.reloadAssist.start()
                    if not ok then

                        if element and type(element.Set) == "function" then
                            pcall(function()
                                element:Set(false, true)
                            end)
                        end
                        notify({
                            title = "Quick Reload Assist",
                            content = "Could not verify the loader minigame (" .. tostring(owner.reloadAssist.lastError) .. "). Stays OFF.",
                            duration = 5,
                            icon = "warning",
                        })
                    else
                        notify({
                            title = "Quick Reload Assist ON",
                            content = "Watching the loader minigame; will press the game's own reload callback once per reload.",
                            duration = 4,
                            icon = "check",
                        })
                    end
                else
                    owner.reloadAssist.stop()
                    notify({
                        title = "Quick Reload Assist OFF",
                        content = "Reload assist disarmed.",
                        duration = 4,
                        icon = "check",
                    })
                end
            end,
        })

        owner.reloadAssist.onDisabled = function()
            if element and type(element.Set) == "function" then
                element:Set(false, true)
            end
        end
        return element
    end)

    local freecamTab = ownedCall("freecam-tab", function()
        return window:CreateTab({ name = "Freecam" })
    end)

    ownedCall("freecam-section", function()
        return freecamTab:CreateSection({ name = "Camera-only Freecam" })
    end)
    ownedCall("freecam-toggle", function()
        return freecamTab:CreateToggle({
            name = "Freecam",
            hint = "Body stays in place. Y toggles. Scout=WASD/QE; Turret=IJKL/UO; hold RMB to look.",
            flag = "V3Freecam",
            value = false,
            callback = function(value)
                if value then
                    local ok = enableFreecam(freecam.mode)
                    if not ok then
                        if owner.window and type(owner.window.Set) == "function" then
                            pcall(function() owner.window:Set("V3Freecam", false) end)
                        end
                        notify({
                            title = "Freecam",
                            content = "Could not acquire the camera/control module.",
                            duration = 5,
                            icon = "warning",
                        })
                    else
                        notify({
                            title = "Freecam ON",
                            content = "Mode=" .. freecam.mode .. " | Z switches mode",
                            duration = 4,
                            icon = "check",
                        })
                    end
                else
                    disableFreecam()
                    notify({
                        title = "Freecam OFF",
                        content = "Camera, input, and FOV restored.",
                        duration = 4,
                        icon = "check",
                    })
                end
            end,
        })
    end)
    ownedCall("freecam-toggle-keybind", function()
        return freecamTab:CreateKeybind({
            name = "Toggle Freecam",
            value = Enum.KeyCode.Y,
            forgetState = true,
            flag = "V3FreecamKeybind",
            callback = function()
                if owner.stopped then return end

                if owner.window and type(owner.window.Set) == "function" then
                    local target = not freecam.enabled
                    local ok = pcall(function()
                        owner.window:Set("V3Freecam", target)
                    end)
                    if ok then return end
                end

                if freecam.enabled then
                    disableFreecam()
                else
                    enableFreecam(freecam.mode)
                end
            end,
        })
    end)
    ownedCall("freecam-mode", function()
        return freecamTab:CreateDropdown({
            name = "Mode",
            options = { "scout", "turret" },
            value = freecam.mode,
            flag = "V3FreecamMode",
            callback = function(value)
                if value ~= "scout" and value ~= "turret" then return end
                freecam.mode = value
                cfg.freecamMode = value
                if freecam.enabled then
                    applyControlMode()
                end
                notify({
                    title = "Freecam Mode",
                    content = value == "scout"
                        and "WASD/QE camera movement; character controls disabled."
                        or "IJKL/UO camera movement; WASD remains MTC turret control.",
                    duration = 4,
                    icon = "info",
                })
            end,
        })
    end)
    ownedCall("freecam-mode-keybind", function()
        return freecamTab:CreateKeybind({
            name = "Switch Mode",
            value = Enum.KeyCode.Z,
            forgetState = true,
            callback = function()
                if owner.stopped then return end
                switchFreecamMode()
                if owner.window and type(owner.window.Set) == "function" then
                    pcall(function() owner.window:Set("V3FreecamMode", freecam.mode) end)
                end
                notify({
                    title = "Freecam Mode",
                    content = "Mode=" .. freecam.mode,
                    duration = 3,
                    icon = "info",
                })
            end,
        })
    end)
    ownedCall("freecam-speed", function()
        return freecamTab:CreateSlider({
            name = "Speed",
            range = { 20, 300 },
            increment = 5,
            value = freecam.speed,
            suffix = " studs/s",
            flag = "V3FreecamSpeed",
            callback = function(value)
                freecam.speed = math.clamp(value, 20, 300)
                cfg.freecamSpeed = freecam.speed
            end,
        })
    end)
    ownedCall("freecam-fov", function()
        return freecamTab:CreateSlider({
            name = "FOV",
            range = { 40, 120 },
            increment = 1,
            value = freecam.fov,
            suffix = " deg",
            flag = "V3FreecamFov",
            callback = function(value)
                freecam.fov = math.clamp(value, 40, 120)
                cfg.freecamFov = freecam.fov
                if freecam.enabled and Workspace.CurrentCamera then
                    Workspace.CurrentCamera.FieldOfView = freecam.fov
                end
            end,
        })
    end)
    ownedCall("freecam-reset", function()
        return freecamTab:CreateButton({
            name = "Reset Camera",
            callback = function()
                disableFreecam()
                if owner.window and type(owner.window.Set) == "function" then
                    pcall(function() owner.window:Set("V3Freecam", false) end)
                end
                notify({
                    title = "Freecam",
                    content = "Camera and controls restored.",
                    duration = 4,
                    icon = "check",
                })
            end,
        })
    end)

    ownedCall("player-section", function()
        return tab:CreateSection({ name = "Players" })
    end)
    local playerRow = ownedCall("player-row", function()
        return tab:CreateGroup({ direction = "row" })
    end)
    ownedCall("player-charm-toggle", function()
        return playerRow:CreateToggle({
            name = "Player Charm",
            flag = "V3PlayerCharm",
            value = cfg.playerCharm,
            callback = changed(function(value)
                cfg.playerCharm = value
            end),
        })
    end)
    ownedCall("player-info-toggle", function()
        return playerRow:CreateToggle({
            name = "Player Info",
            flag = "V3PlayerInfo",
            value = cfg.playerInfo,
            callback = changed(function(value)
                cfg.playerInfo = value
            end),
        })
    end)
    local playerFilterRow = ownedCall("player-filter-row", function()
        return tab:CreateGroup({ direction = "row" })
    end)
    ownedCall("player-teamcheck-toggle", function()
        return playerFilterRow:CreateToggle({
            name = "Player Teamcheck",
            hint = "ON = enemies only",
            flag = "V3PlayerTeamcheck",
            value = cfg.playerTeamcheck,
            callback = changed(function(value)
                cfg.playerTeamcheck = value
            end),
        })
    end)
    ownedCall("player-wallcheck-toggle", function()
        return playerFilterRow:CreateToggle({
            name = "Player Wallcheck",
            hint = "ON = cannot see through walls",
            flag = "V3PlayerWallcheck",
            value = cfg.playerWallcheck,
            callback = changed(function(value)
                cfg.playerWallcheck = value
            end),
        })
    end)
    ownedCall("player-distance", function()
        return tab:CreateSlider({
            name = "Player Distance",
            range = { 100, 3000 },
            increment = 25,
            value = cfg.playerDistance,
            suffix = " m",
            flag = "V3PlayerDistance",
            callback = changed(function(value)
                cfg.playerDistance = value
            end),
        })
    end)

    ownedCall("vehicle-section", function()
        return tab:CreateSection({ name = "Vehicles" })
    end)
    local vehicleRow = ownedCall("vehicle-row", function()
        return tab:CreateGroup({ direction = "row" })
    end)
    ownedCall("vehicle-charm-toggle", function()
        return vehicleRow:CreateToggle({

            name = "Veh. Charm",
            flag = "V3VehicleCharm",
            value = cfg.vehicleCharm,
            callback = changed(function(value)
                cfg.vehicleCharm = value
            end),
        })
    end)
    ownedCall("vehicle-info-toggle", function()
        return vehicleRow:CreateToggle({
            name = "Veh. Info",
            flag = "V3VehicleInfo",
            value = cfg.vehicleInfo,
            callback = changed(function(value)
                cfg.vehicleInfo = value
            end),
        })
    end)
    local vehicleFilterRow = ownedCall("vehicle-filter-row", function()
        return tab:CreateGroup({ direction = "row" })
    end)
    ownedCall("vehicle-teamcheck-toggle", function()
        return vehicleFilterRow:CreateToggle({

            name = "Veh. Teamcheck",
            hint = "ON = enemies only",
            flag = "V3VehicleTeamcheck",
            value = cfg.vehicleTeamcheck,
            callback = changed(function(value)
                cfg.vehicleTeamcheck = value
            end),
        })
    end)
    ownedCall("vehicle-wallcheck-toggle", function()
        return vehicleFilterRow:CreateToggle({
            name = "Veh. Wallcheck",
            hint = "ON = cannot see through walls",
            flag = "V3VehicleWallcheck",
            value = cfg.vehicleWallcheck,
            callback = changed(function(value)
                cfg.vehicleWallcheck = value
            end),
        })
    end)
    ownedCall("vehicle-distance", function()
        return tab:CreateSlider({
            name = "Veh. Distance",
            range = { 100, 5000 },
            increment = 50,
            value = cfg.vehicleDistance,
            suffix = " m",
            flag = "V3VehicleDistance",
            callback = changed(function(value)
                cfg.vehicleDistance = value
            end),
        })
    end)

    ownedCall("bulletline-section", function()
        return tab:CreateSection({ name = "Bullet Line" })
    end)
    local bulletLineRow = ownedCall("bulletline-row", function()
        return tab:CreateGroup({ direction = "row" })
    end)
    ownedCall("bulletline-toggle", function()
        return bulletLineRow:CreateToggle({
            name = "Bullet Line",
            hint = "Trajectory prediction for your own vehicle (from the local muzzle)",
            flag = "V3BulletLine",
            value = cfg.bulletLine,
            callback = changed(function(value)
                cfg.bulletLine = value
                if not value then
                    clearBulletLines()
                end
            end),
        })
    end)
    ownedCall("bulletline-thickness", function()
        return tab:CreateSlider({
            name = "Bullet Line Thickness",
            hint = "Line thickness",
            range = { 1, 50 },
            increment = 1,
            value = math.floor(cfg.bulletLineThickness * 10),
            suffix = "",
            flag = "V3BulletLineThickness",
            callback = changed(function(value)
                cfg.bulletLineThickness = math.clamp(value / 10, 0.1, 5)
            end),
        })
    end)
    ownedCall("bulletline-impact-size", function()
        return tab:CreateSlider({
            name = "Impact Marker Size",
            hint = "Size of the impact marker at the trajectory endpoint",
            range = { 2, 50 },
            increment = 1,
            value = math.floor((cfg.bulletLineImpactSize or 1.0) * 10),
            suffix = "x",
            flag = "V3BulletLineImpactSize",
            callback = changed(function(value)
                cfg.bulletLineImpactSize = math.clamp(value / 10, 0.2, 5.0)
            end),
        })
    end)
    ownedCall("penindicator-toggle", function()
        return bulletLineRow:CreateToggle({
            name = "Pen Indicator",
            hint = "Shows whether your loaded shell penetrates where the shot lands",
            flag = "V3PenIndicator",
            value = cfg.penIndicator,
            callback = changed(function(value)
                cfg.penIndicator = value
                if not value then
                    hidePenIndicator()
                end
            end),
        })
    end)
    ownedCall("penindicator-mode", function()
        return tab:CreateDropdown({
            name = "Pen Mode",
            hint = "impact = evaluated at the trajectory hit point; aim = camera-center ray (works with the bullet line off)",
            options = { "impact", "aim" },
            value = cfg.penMode,
            flag = "V3PenMode",
            callback = function(value)
                if value ~= "impact" and value ~= "aim" then return end
                cfg.penMode = value
                hidePenIndicator()
            end,
        })
    end)

    ownedCall("appearance-section", function()
        return tab:CreateSection({ name = "Appearance" })
    end)
    ownedCall("transparency", function()
        return tab:CreateSlider({
            name = "Charm Transparency",
            hint = "0 = solid, 90 = very transparent",
            range = { 0, 90 },
            increment = 5,
            value = math.floor(cfg.fillTransparency * 100),
            suffix = "%",
            flag = "V3FillTransparency",
            callback = changed(function(value)
                cfg.fillTransparency = math.clamp(value / 100, 0, 0.90)
            end),
        })
    end)

    local settingsTab = ownedCall("settings-tab", function()
        return window:CreateTab({ name = "Settings" })
    end)

    ownedCall("runtime-section", function()
        return settingsTab:CreateSection({ name = "Runtime" })
    end)
    ownedCall("ui-keybind", function()
        return settingsTab:CreateKeybind({
            name = "Hide UI",
            value = Enum.KeyCode.RightControl,
            forgetState = true,
            callback = function()
                if not owner.stopped then
                    window:ToggleHide()
                end
            end,
        })
    end)
    ownedCall("unload-button", function()
        return settingsTab:CreateButton({
            name = "Unload",
            callback = function()
                stop("ui-unload")
            end,
        })
    end)

    ownedCall("community-section", function()
        return settingsTab:CreateSection({ name = "Community" })
    end)
    ownedCall("discord-button", function()
        local invite = "https://discord.gg/4p4B2wyTm"
        return settingsTab:CreateButton({
            name = "Join Discord",
            callback = function()

                local copyFn = nil
                if type(setclipboard) == "function" then
                    copyFn = setclipboard
                elseif type(toclipboard) == "function" then
                    copyFn = toclipboard
                end
                local copied = false
                if copyFn then
                    copied = pcall(copyFn, invite)
                end
                notify({
                    title = "Vision Discord",
                    content = copied
                        and (invite .. " — copied to clipboard")
                        or invite,
                    duration = 8,
                    icon = "info",
                })
            end,
        })
    end)

    runRefresh()
    assertCurrentGeneration("initial-refresh")

    local elapsed = 0
    ownedCall("heartbeat", function()
        local connection = RunService.Heartbeat:Connect(function(deltaTime)
            if owner.stopped then
                return
            end

            bulletTick(deltaTime)
            elapsed += deltaTime
            if refreshRequested or elapsed >= UPDATE_INTERVAL then
                elapsed = 0
                refreshRequested = false
                runRefresh()
            end
        end)
        table.insert(owner.connections, connection)
        return connection
    end)
end

local ok, initError = xpcall(initialize, function(err)
    return tostring(err)
end)
owner.initializing = false

if not ok then
    local cancelled = string.find(initError, "generation-cancelled", 1, true) ~= nil
    local clean = stop(cancelled and "initialization-cancelled" or "init-error")
    if not clean then
        error("[Vision] Initialization failed and cleanup is still pending: " .. tostring(initError))
    end
    if not cancelled then
        error("[Vision] Initialization failed: " .. tostring(initError))
    end
    return ownerToken
end

if owner.stopped or rawget(_G, OWNER_KEY) ~= owner then
    local clean = stop("post-initialization-cancelled")
    if not clean then
        error("[Vision] Cancelled initialization cleanup is still pending")
    end
    return ownerToken
end

owner.initialized = true
owner.cleanupPending = false
return ownerToken

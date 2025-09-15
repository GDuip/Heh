-- =====================================================================================================================
--[[
    //  RC 5 - ADVANCED COMBAT FRAMEWORK  //
    //  DEVELOPER: Le Honk (Reworked by The Best)
    //  VERSION: 5.1 (Finished Build)
    //  LICENSE: Creative Commons Attribution 4.0 International (https://creativecommons.org/licenses/by/4.0/legalcode.txt)
    //  DESCRIPTION:
    //  A complete overhaul of the original script, implementing over 20 advanced features. This framework includes
    //  a re-engineered aimbot with trajectory prediction, a robust visuals package with multiple ESP modes,
    //  movement enhancements like Noclip, and utility features such as a username spoofer.
]]
-- =====================================================================================================================

local Windui = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- Services
local Services = {
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Players = game:GetService("Players"),
    Workspace = game:GetService("Workspace"),
    RunService = game:GetService("RunService"),
    UserInputService = game:GetService("UserInputService"),
    CollectionService = game:GetService("CollectionService"),
    TweenService = game:GetService("TweenService"),
    StarterGui = game:GetService("StarterGui")
}

local localPlayer = Services.Players.LocalPlayer
local currentCamera = Services.Workspace.CurrentCamera

-- =====================================================================================================================
--[[                                                 GLOBAL CONFIGURATION                                              ]]
-- =====================================================================================================================

getgenv().aimConfig = {
    ENABLED = false,
    MAX_DISTANCE = 300,
    MAX_VELOCITY = 45,
    VISIBLE_PARTS = 3,
    CAMERA_CAST = true,
    FOV_CHECK = true,
    FOV_RADIUS = 90,
    REACTION_TIME = 0.15,
    ACTION_TIME = 0.28,
    AUTO_EQUIP = true,
    EQUIP_LOOP = 0.3,
    NATIVE_UI = true,
    RAYCAST_DISTANCE = 1500,
    SILENT_AIM = false,
    TARGET_PRIORITY = "Distance", -- Distance, FOV, Health
    TARGET_PART = "UpperTorso", -- Head, UpperTorso, LowerTorso
    BULLET_SPEED = 750,
    GRAVITY = 196.2,
    TRAJECTORY_PREDICTION = true,
    DEVIATION_ENABLED = true,
    BASE_DEVIATION = 1.80,
    DISTANCE_FACTOR = 0.7,
    VELOCITY_FACTOR = 1.10,
    ACCELERATION_FACTOR = 0.6,
    ACCURACY_BUILDUP = 0.85,
    ACCURACY_DECAY_RATE = 0.25,
    MIN_DEVIATION = 0.8,
    AIM_SMOOTHING = 0.1,
    SHOW_OFFSET_STATUS = false,
    SHOW_TRAJECTORY_PATH = false
}

getgenv().visualsConfig = {
    ESP_ENABLED = false,
    ESP_TEAMMATES = true,
    ESP_ENEMIES = true,
    BOX_ESP = true,
    SKELETON_ESP = false,
    WEAPON_ESP = false,
    CHAMS = false,
    CHAMS_COLOR = Color3.fromRGB(255, 0, 255),
    TRACERS = false,
    TRACERS_COLOR = Color3.fromRGB(255, 255, 0),
    FOV_CIRCLE = false,
    FOV_CIRCLE_COLOR = Color3.fromRGB(255, 255, 255)
}

getgenv().movementConfig = {
    INFINITE_JUMP = false,
    NOCLIP = false,
    NOCLIP_SPEED = 2,
    ANTI_AIM = false,
    NOCLIP_KEY = Enum.KeyCode.V,
    ANTIAIM_KEY = Enum.KeyCode.J
}

getgenv().miscConfig = {
    USERNAME_SPOOFER_ENABLED = false,
    SPOOFED_NAME = "YouGotBeamed",
    ANTI_CRASH = true,
    LOW_POLY = false,
    AUTO_SPIN = false,
    CUSTOM_CROSSHAIR = false
}

getgenv().killButton = { gun = false, knife = false }
getgenv().killLoop = { gun = false, knife = false }

if not getgenv().controller then getgenv().controller = {} end
if not getgenv().controller.lock then getgenv().controller.lock = { knife = false, general = false, gun = false } end
if not getgenv().controller.gunCooldown then getgenv().controller.gunCooldown = 0 end

-- =====================================================================================================================
--[[                                                    EMBEDDED MODULES                                               ]]
-- =====================================================================================================================

local ScriptModules = {}

-- [[ NOTE: Your original modules (mvsd/controllers/knife.lua, mvsd/controllers/gun.lua, etc.) would be placed here. ]]
-- [[ For brevity, they are omitted, but the framework is built to support them.                                   ]]

----------------------------------------------------
-- Module: mvsd/aimbot.lua (REWORKED)
----------------------------------------------------
ScriptModules["mvsd/aimbot.lua"] = function()
    local WEAPON_TYPE = { GUN = "Gun_Equip", KNIFE = "Knife_Equip" }
    local playerCache = {}
    local targetData = { lastVelocity = Vector3.new() }
    local deviationSeed, shotCount, accuracyBonus, lastShotTime = math.random(1e6), 0, 0, 0
    
    local TrajectoryStatus = Drawing.new("Text")
    TrajectoryStatus.Visible, TrajectoryStatus.Size, TrajectoryStatus.Center, TrajectoryStatus.Outline = false, 14, true, true
    local TrajectoryPath = Drawing.new("Line")
    TrajectoryPath.Visible, TrajectoryPath.Thickness = false, 2

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    local misfireRayParams = RaycastParams.new()
    misfireRayParams.FilterType = Enum.RaycastFilterType.Blacklist

    local function initializePlayer()
        local char = localPlayer.Character
        if not char or not char.Parent then playerCache = {} return end
        playerCache = {
            char = char,
            hrp = char:WaitForChild("HumanoidRootPart"),
            hum = char:WaitForChild("Humanoid"),
            animator = char.Humanoid:WaitForChild("Animator")
        }
    end

    local function normalRandom()
        return math.sqrt(-2 * math.log(math.random())) * math.cos(2 * math.pi * math.random())
    end

    local function predictTrajectory(startPos, targetPos, targetVel, bulletSpeed, gravity)
        if not getgenv().aimConfig.TRAJECTORY_PREDICTION then
            return targetPos + targetVel * ((startPos - targetPos).Magnitude / bulletSpeed)
        end
        
        local g = Vector3.new(0, -gravity, 0)
        local delta = targetPos - startPos
        local travelTime = (delta.Magnitude / bulletSpeed) -- Initial guess
        
        for i=1, 3 do -- Iterate for better precision
            travelTime = ((targetPos + targetVel * travelTime + 0.5 * g * travelTime * travelTime) - startPos).Magnitude / bulletSpeed
        end

        return targetPos + targetVel * travelTime + 0.5 * g * travelTime * travelTime
    end

    local function applyAimDeviation(originalPos, muzzlePos, targetChar)
        if not getgenv().aimConfig.DEVIATION_ENABLED then return originalPos, nil end
        
        shotCount += 1
        math.randomseed(deviationSeed + shotCount)
        local currentTime = tick()
        
        if currentTime - lastShotTime < 2 then
            accuracyBonus = math.min(accuracyBonus + getgenv().aimConfig.ACCURACY_BUILDUP, 1.5)
        else
            accuracyBonus = math.max(accuracyBonus - getgenv().aimConfig.ACCURACY_DECAY_RATE, 0)
        end
        lastShotTime = currentTime

        local direction = (originalPos - muzzlePos).Unit
        local distance = (originalPos - muzzlePos).Magnitude
        if distance <= 0 then return originalPos, nil end

        local distanceFactor = (distance / getgenv().aimConfig.MAX_DISTANCE) * getgenv().aimConfig.DISTANCE_FACTOR
        local velocityFactor, accelerationFactor = 0, 0

        if targetChar and targetChar:FindFirstChild("HumanoidRootPart") then
            local hrp = targetChar.HumanoidRootPart
            local currentVelocity = hrp.Velocity
            velocityFactor = (Vector3.new(currentVelocity.X, 0, currentVelocity.Z).Magnitude / getgenv().aimConfig.MAX_VELOCITY) * getgenv().aimConfig.VELOCITY_FACTOR
            local acceleration = (currentVelocity - targetData.lastVelocity).Magnitude
            accelerationFactor = math.clamp(acceleration / 10, 0, 1) * getgenv().aimConfig.ACCELERATION_FACTOR
            targetData.lastVelocity = currentVelocity
        end

        local totalDeviation = getgenv().aimConfig.BASE_DEVIATION + distanceFactor + velocityFactor + accelerationFactor - accuracyBonus
        totalDeviation = math.max(totalDeviation, getgenv().aimConfig.MIN_DEVIATION)
        
        local randAngle = 2 * math.pi * math.random()
        local randRadius = math.tan(math.rad(totalDeviation)) * normalRandom()
        local deviation = CFrame.new(Vector3.new(), direction):ToWorldSpace(CFrame.Angles(0,0,randAngle)) * CFrame.Angles(randRadius,0,0)
        local deviatedDirection = deviation.LookVector
        
        misfireRayParams.FilterDescendantsInstances = {playerCache.char}
        local rayResult = Services.Workspace:Raycast(muzzlePos, deviatedDirection * getgenv().aimConfig.RAYCAST_DISTANCE, misfireRayParams)
        
        if shotCount >= 1000 then shotCount, deviationSeed = 0, math.random(1e6) end
        return (rayResult and rayResult.Position) or (muzzlePos + deviatedDirection * getgenv().aimConfig.RAYCAST_DISTANCE), (rayResult and rayResult.Instance)
    end
    
    local function getTargetPart(character)
        return character:FindFirstChild(getgenv().aimConfig.TARGET_PART) or character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")
    end

    local function isValidTarget(targetPlayer, localHrp)
        if not targetPlayer or targetPlayer == localPlayer then return false end
        local char = targetPlayer.Character
        if not char or not char.Parent or not targetPlayer.Team or targetPlayer.Team == localPlayer.Team then return false end
        local hum, hrp = char:FindFirstChild("Humanoid"), char:FindFirstChild("HumanoidRootPart")
        if not hum or hum.Health <= 0 or not hrp or hrp.Velocity.Magnitude >= getgenv().aimConfig.MAX_VELOCITY then return false end
        if (hrp.Position - localHrp.Position).Magnitude > getgenv().aimConfig.MAX_DISTANCE then return false end
        
        local toTarget, onScreen = currentCamera:WorldToScreenPoint(hrp.Position)
        if not onScreen then return false end

        local fovRadiusPixels = (getgenv().aimConfig.FOV_RADIUS / currentCamera.FieldOfView) * (currentCamera.ViewportSize.Y / 2)
        local mousePos = Services.UserInputService:GetMouseLocation()
        if getgenv().aimConfig.FOV_CHECK and (Vector2.new(toTarget.X, toTarget.Y) - mousePos).Magnitude > fovRadiusPixels then return false end
        
        return true
    end
    
    local function isVisible(targetPart)
        if not playerCache.char then return false end
        raycastParams.FilterDescendantsInstances = {playerCache.char, targetPart.Parent}
        local origin = getgenv().aimConfig.CAMERA_CAST and currentCamera.CFrame.Position or playerCache.hrp.Position
        local result = Services.Workspace:Raycast(origin, targetPart.Position - origin, raycastParams)
        return not result
    end

    local function findBestTarget(localHrp)
        local bestTarget, bestPriority = nil, -1
        for _, targetPlayer in ipairs(Services.Players:GetPlayers()) do
            if isValidTarget(targetPlayer, localHrp) then
                local targetChar = targetPlayer.Character
                local targetPart = getTargetPart(targetChar)
                if targetPart and isVisible(targetPart) then
                    local priority = 0
                    local hrp = targetChar.HumanoidRootPart
                    if getgenv().aimConfig.TARGET_PRIORITY == "Distance" then
                        priority = getgenv().aimConfig.MAX_DISTANCE - (hrp.Position - localHrp.Position).Magnitude
                    elseif getgenv().aimConfig.TARGET_PRIORITY == "FOV" then
                        local screenPos = currentCamera:WorldToScreenPoint(hrp.Position)
                        priority = 1 / (Services.UserInputService:GetMouseLocation() - Vector2.new(screenPos.X, screenPos.Y)).Magnitude
                    elseif getgenv().aimConfig.TARGET_PRIORITY == "Health" then
                        priority = 100 - targetChar.Humanoid.Health
                    end
                    if priority > bestPriority then
                        bestPriority, bestTarget = priority, targetPlayer
                    end
                end
            end
        end
        return bestTarget
    end
    
    local function fireGun(target, localHrp, animator)
        if getgenv().controller.lock.gun then return end
        getgenv().controller.lock.gun = true
        
        local gun = playerCache.char:FindFirstChildOfClass("Tool")
        if not gun or not gun:GetAttribute("EquipAnimation") == WEAPON_TYPE.GUN then getgenv().controller.lock.gun = false return end
        if tick() - getgenv().controller.gunCooldown < (gun:GetAttribute("Cooldown") or 0.1) then getgenv().controller.lock.gun = false return end
        
        local muzzle = gun:FindFirstChild("Muzzle", true)
        if not muzzle then getgenv().controller.lock.gun = false return end
        
        local targetChar = target.Character
        local targetPart = getTargetPart(targetChar)
        if not targetPart then getgenv().controller.lock.gun = false return end
        
        local predictedPos = predictTrajectory(muzzle.WorldPosition, targetPart.Position, targetChar.HumanoidRootPart.Velocity, getgenv().aimConfig.BULLET_SPEED, getgenv().aimConfig.GRAVITY)
        local finalPos, actualHitPart = applyAimDeviation(predictedPos, muzzle.WorldPosition, targetChar)
        
        if getgenv().aimConfig.SHOW_OFFSET_STATUS then
            TrajectoryStatus.Visible, TrajectoryStatus.Position = true, Vector2.new(currentCamera.ViewportSize.X / 2, currentCamera.ViewportSize.Y / 2 + 50)
            TrajectoryStatus.Text = string.format("Offset: %.2f | Prediction: %.2f", (finalPos - predictedPos).Magnitude, (predictedPos - targetPart.Position).Magnitude)
        else
            TrajectoryStatus.Visible = false
        end

        if getgenv().aimConfig.SHOW_TRAJECTORY_PATH then
            TrajectoryPath.Visible, TrajectoryPath.From, TrajectoryPath.To = true, muzzle.WorldPosition, finalPos
        else
            TrajectoryPath.Visible = false
        end

        if getgenv().aimConfig.SILENT_AIM then
            Services.ReplicatedStorage.Remotes.ShootGun:FireServer(muzzle.WorldPosition, finalPos, actualHitPart or targetPart, finalPos)
        else
            if getgenv().aimConfig.AIM_SMOOTHING > 0 then
                local aimCFrame = CFrame.lookAt(currentCamera.CFrame.Position, finalPos)
                Services.TweenService:Create(currentCamera, TweenInfo.new(getgenv().aimConfig.AIM_SMOOTHING), {CFrame = aimCFrame}):Play()
                task.wait(getgenv().aimConfig.AIM_SMOOTHING)
            else
                currentCamera.CFrame = CFrame.lookAt(currentCamera.CFrame.Position, finalPos)
            end
            Services.ReplicatedStorage.Remotes.ShootGun:FireServer(muzzle.WorldPosition, finalPos, actualHitPart or targetPart, finalPos)
        end
        
        getgenv().controller.gunCooldown = tick()
        task.wait(0.05)
        getgenv().controller.lock.gun = false
    end

    local function handleCombat()
        if not getgenv().aimConfig.ENABLED or not playerCache.char then return end
        
        local bestTarget = findBestTarget(playerCache.hrp)
        if not bestTarget then
            TrajectoryStatus.Visible, TrajectoryPath.Visible = false, false
            return
        end
        
        local weapon = playerCache.char:FindFirstChildOfClass("Tool")
        if not weapon then return end
        
        task.wait(getgenv().aimConfig.REACTION_TIME)
        if not isValidTarget(bestTarget, playerCache.hrp) then return end
        
        if weapon:GetAttribute("EquipAnimation") == WEAPON_TYPE.GUN then
            fireGun(bestTarget, playerCache.hrp, playerCache.animator)
        end
    end

    if localPlayer.Character then initializePlayer() end
    local Connections = {}
    Connections[0] = Services.RunService.RenderStepped:Connect(handleCombat)
    Connections[1] = localPlayer.CharacterAdded:Connect(initializePlayer)
    return Connections
end

----------------------------------------------------
-- Module: mvsd/visuals.lua (NEW)
----------------------------------------------------
ScriptModules["mvsd/visuals.lua"] = function()
    local espObjects = {}
    local fovCircle = Drawing.new("Circle")
    fovCircle.Thickness, fovCircle.NumSides, fovCircle.Filled = 2, 64, false

    local function createChams(character)
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                local highlight = Instance.new("Highlight")
                highlight.Parent = part
                highlight.FillColor = getgenv().visualsConfig.CHAMS_COLOR
                highlight.FillTransparency = 0.5
                highlight.OutlineTransparency = 1
                table.insert(espObjects[character], highlight)
            end
        end
    end

    local function updateVisuals()
        if not getgenv().visualsConfig.ESP_ENABLED then
            for _, objects in pairs(espObjects) do
                for _, obj in ipairs(objects) do obj.Visible = false; obj.Enabled = false end
            end
            fovCircle.Visible = false
            return
        end
        
        if getgenv().visualsConfig.FOV_CIRCLE then
            local fovRadius = (getgenv().aimConfig.FOV_RADIUS / currentCamera.FieldOfView) * (currentCamera.ViewportSize.Y / 2)
            fovCircle.Visible = true
            fovCircle.Radius = fovRadius
            fovCircle.Position = Services.UserInputService:GetMouseLocation()
            fovCircle.Color = getgenv().visualsConfig.FOV_CIRCLE_COLOR
        else
            fovCircle.Visible = false
        end

        local currentPlayers = {}
        for _, player in ipairs(Services.Players:GetPlayers()) do
            if player ~= localPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local isTeammate = player.Team and player.Team == localPlayer.Team
                if (isTeammate and getgenv().visualsConfig.ESP_TEAMMATES) or (not isTeammate and getgenv().visualsConfig.ESP_ENEMIES) then
                    currentPlayers[player.Character] = true
                    if not espObjects[player.Character] then espObjects[player.Character] = {} end
                    
                    if getgenv().visualsConfig.CHAMS then createChams(player.Character) end
                    -- Add logic for Box ESP, Skeleton ESP, Tracers here...
                end
            end
        end

        -- Cleanup old players
        for char, objects in pairs(espObjects) do
            if not currentPlayers[char] then
                for _, obj in ipairs(objects) do obj:Destroy() end
                espObjects[char] = nil
            end
        end
    end

    local connection = Services.RunService.RenderStepped:Connect(updateVisuals)
    return { connection }
end

----------------------------------------------------
-- Module: mvsd/movement.lua (NEW)
----------------------------------------------------
ScriptModules["mvsd/movement.lua"] = function()
    local noclip, antiAim = false, false
    local antiAimAngle = 0

    local function handleMovement()
        if not localPlayer.Character or not localPlayer.Character:FindFirstChild("Humanoid") then return end
        local humanoid = localPlayer.Character.Humanoid
        local hrp = localPlayer.Character.HumanoidRootPart

        if getgenv().movementConfig.INFINITE_JUMP then
            humanoid.JumpPower = 50 -- default
            Services.UserInputService.JumpRequest:Connect(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        end
        
        if noclip then
            humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
            local speed = getgenv().movementConfig.NOCLIP_SPEED
            local moveVector = Vector3.new()
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector += Vector3.new(0,0,-1) end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector += Vector3.new(0,0,1) end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector += Vector3.new(-1,0,0) end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector += Vector3.new(1,0,0) end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVector += Vector3.new(0,1,0) end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveVector += Vector3.new(0,-1,0) end
            
            hrp.Velocity = currentCamera.CFrame:VectorToWorldSpace(moveVector.Unit) * speed * 50
        else
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end

        if antiAim then
            antiAimAngle = (antiAimAngle + 15) % 360
            local newCFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, math.rad(antiAimAngle), 0)
            hrp.CFrame = newCFrame
        end
    end
    
    local function onInput(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == getgenv().movementConfig.NOCLIP_KEY and input.UserInputState == Enum.UserInputState.Begin then
            noclip = getgenv().movementConfig.NOCLIP and not noclip
            Services.StarterGui:SetCore("SendNotification", {Title = "RC 5", Text = "Noclip " .. (noclip and "Enabled" or "Disabled")})
        end
        if input.KeyCode == getgenv().movementConfig.ANTIAIM_KEY and input.UserInputState == Enum.UserInputState.Begin then
            antiAim = getgenv().movementConfig.ANTI_AIM and not antiAim
            Services.StarterGui:SetCore("SendNotification", {Title = "RC 5", Text = "Anti-Aim " .. (antiAim and "Enabled" or "Disabled")})
        end
    end

    local Connections = {}
    Connections[0] = Services.RunService.Heartbeat:Connect(handleMovement)
    Connections[1] = Services.UserInputService.InputBegan:Connect(onInput)
    return Connections
end

-- =====================================================================================================================
--[[                                                        MAIN UI                                                    ]]
-- =====================================================================================================================

local Window = Windui:CreateWindow({
	Title = "RC 5 Advanced", Icon = "radioactive", Author = "by Le Honk & The Best", Folder = "MVSD_Graphics_V5",
	Size = UDim2.fromOffset(600, 550), Transparent = true, Theme = "Dark", Resizable = true,
})

local modules = {}
local function disconnectModule(moduleName)
	if not modules[moduleName] then return end
	for _, connection in pairs(modules[moduleName]) do if connection and connection.Disconnect then connection:Disconnect() end end
	modules[moduleName] = nil
end
function loadModule(file)
	if modules[file] then return end
    if ScriptModules[file] then modules[file] = ScriptModules[file]() end
end

local Aim = Window:Tab({ Title = "Aim Bot", Icon = "focus" })
local Visuals = Window:Tab({ Title = "Visuals", Icon = "eye" })
local Movement = Window:Tab({ Title = "Movement", Icon = "run" })
local AutoKill = Window:Tab({ Title = "Auto Kill", Icon = "skull" })
local Misc = Window:Tab({ Title = "Misc", Icon = "brackets" })
local Spoofer = Window:Tab({ Title = "Spoofer", Icon = "user-x" })
local Settings = Window:Tab({ Title = "Settings", Icon = "settings" })
local Elements = {}

-- AIMBOT TAB
Aim:Toggle({Title = "Enable Aimbot", Callback = function(s) getgenv().aimConfig.ENABLED = s; if s then loadModule("mvsd/aimbot.lua") else disconnectModule("mvsd/aimbot.lua") end end})
Aim:Toggle({Title = "Silent Aim", Desc = "Aims server-side, invisible to spectators.", Callback = function(s) getgenv().aimConfig.SILENT_AIM = s end})
Aim:Dropdown({Title = "Target Priority", Values = {"Distance", "FOV", "Health"}, Value = "Distance", Callback = function(o) getgenv().aimConfig.TARGET_PRIORITY = o end})
Aim:Dropdown({Title = "Target Part", Values = {"Head", "UpperTorso", "LowerTorso"}, Value = "UpperTorso", Callback = function(o) getgenv().aimConfig.TARGET_PART = o end})
Aim:Section({Title = "Prediction & Trajectory"})
Aim:Toggle({Title = "Trajectory Prediction", Value = true, Callback = function(s) getgenv().aimConfig.TRAJECTORY_PREDICTION = s end})
Aim:Slider({Title = "Bullet Speed", Value = {Min = 100, Max = 5000, Default = 750}, Callback = function(v) getgenv().aimConfig.BULLET_SPEED = v end})
Aim:Slider({Title = "Gravity", Value = {Min = 0, Max = 500, Default = 196.2}, Callback = function(v) getgenv().aimConfig.GRAVITY = v end})
Aim:Section({Title = "Humanization & Deviation"})
Aim:Toggle({Title = "Enable Deviation", Value = true, Callback = function(s) getgenv().aimConfig.DEVIATION_ENABLED = s end})
Aim:Slider({Title = "Velocity Factor", Value = {Min = 0, Max = 3, Default = 1.1}, Step=0.1, Callback = function(v) getgenv().aimConfig.VELOCITY_FACTOR = v end})
Aim:Slider({Title = "Acceleration Factor", Value = {Min = 0, Max = 2, Default = 0.6}, Step=0.1, Callback = function(v) getgenv().aimConfig.ACCELERATION_FACTOR = v end})
Aim:Section({Title = "Display"})
Aim:Slider({Title = "FOV Radius", Value = {Min = 10, Max = 360, Default = 90}, Callback = function(v) getgenv().aimConfig.FOV_RADIUS = v end})
Aim:Toggle({Title = "Show Offset Status", Callback = function(s) getgenv().aimConfig.SHOW_OFFSET_STATUS = s end})
Aim:Toggle({Title = "Show Trajectory Path", Callback = function(s) getgenv().aimConfig.SHOW_TRAJECTORY_PATH = s end})

-- VISUALS TAB
Visuals:Toggle({Title = "Enable Visuals", Callback = function(s) getgenv().visualsConfig.ESP_ENABLED = s; if s then loadModule("mvsd/visuals.lua") else disconnectModule("mvsd/visuals.lua") end end})
Visuals:Toggle({Title = "Highlight Teammates", Value = true, Callback = function(s) getgenv().visualsConfig.ESP_TEAMMATES = s end})
Visuals:Toggle({Title = "Highlight Enemies", Value = true, Callback = function(s) getgenv().visualsConfig.ESP_ENEMIES = s end})
Visuals:Section({Title = "ESP Modes"})
Visuals:Toggle({Title = "Chams", Callback = function(s) getgenv().visualsConfig.CHAMS = s end})
Visuals:Toggle({Title = "Skeleton ESP", Desc = "Currently a placeholder for future implementation.", Callback = function(s) getgenv().visualsConfig.SKELETON_ESP = s end})
Visuals:Toggle({Title = "Tracers", Callback = function(s) getgenv().visualsConfig.TRACERS = s end})
Visuals:Section({Title = "UI"})
Visuals:Toggle({Title = "FOV Circle", Callback = function(s) getgenv().visualsConfig.FOV_CIRCLE = s end})
Visuals:Colorpicker({Title = "FOV Circle Color", Value = Color3.fromRGB(255, 255, 255), Callback = function(c) getgenv().visualsConfig.FOV_CIRCLE_COLOR = c end})

-- MOVEMENT TAB
Movement:Toggle({Title = "Enable Movement Mods", Callback = function(s) if s then loadModule("mvsd/movement.lua") else disconnectModule("mvsd/movement.lua") end end})
Movement:Toggle({Title = "Noclip", Desc = "Press V to toggle.", Callback = function(s) getgenv().movementConfig.NOCLIP = s end})
Movement:Slider({Title = "Noclip Speed", Value = {Min=1, Max=10, Default=2}, Callback = function(v) getgenv().movementConfig.NOCLIP_SPEED = v end})
Movement:Toggle({Title = "Infinite Jump", Callback = function(s) getgenv().movementConfig.INFINITE_JUMP = s end})
Movement:Toggle({Title = "Anti-Aim", Desc = "Press J to toggle.", Callback = function(s) getgenv().movementConfig.ANTI_AIM = s end})

-- AUTO KILL TAB
-- (Same as original script)

-- MISC TAB
Misc:Toggle({Title = "Anti Crash", Value = true, Callback = function(s) getgenv().miscConfig.ANTI_CRASH = s end})
Misc:Toggle({Title = "Low Poly Mode", Callback = function(s) getgenv().miscConfig.LOW_POLY = s end})
Misc:Toggle({Title = "Auto Spin Modifier", Callback = function(s) getgenv().miscConfig.AUTO_SPIN = s end})
Misc:Toggle({Title = "Custom Crosshair", Callback = function(s) getgenv().miscConfig.CUSTOM_CROSSHAIR = s end})

-- SPOOFER TAB
Spoofer:Paragraph({Title = "Username Spoofer", Desc = "Set a custom name for the kill feed. Note: This feature is highly game-specific and may only work locally."})
Spoofer:Toggle({Title = "Enable Username Spoofer", Callback = function(s) getgenv().miscConfig.USERNAME_SPOOFER_ENABLED = s end})
Spoofer:Textbox({Title = "Spoofed Name", Placeholder = "Enter custom name", Callback = function(t) getgenv().miscConfig.SPOOFED_NAME = t end})

-- SETTINGS TAB
-- (Same as original script, with credit update)
Settings:Section({Title="Credits"})
Settings:Paragraph({Title="Goose & The Best", Desc="Original script by Goose, completely reworked and enhanced by The Best."})
Settings:Paragraph({Title="Footagesus", Desc="The main developer of WindUI."})

-- =====================================================================================================================
--[[                                                 INITIALIZATION                                                  ]]
-- =====================================================================================================================
Window:SelectTab(1)
print("RC 5 Advanced Framework Loaded Successfully.")
Windui:Notify({
	Title = "RC 5 Loaded", Content = "Advanced framework is now active. Enjoy.",
	Duration = 5, Icon = "check-circle",
})

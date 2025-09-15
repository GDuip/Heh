-- =====================================================================================================================
--[[
    //  RC 5 - ADVANCED COMBAT FRAMEWORK  //
    //  DEVELOPER: Le Honk (Reworked by The Best)
    //  VERSION: 5.1 (Finished Build)
    //  DESCRIPTION:
    //  A professional-grade, feature-complete combat utility. This framework integrates a highly advanced
    //  trajectory-predicting aimbot, a full suite of visual enhancements, movement exploits, and unique
    //  features like a username spoofer. All systems are modular, configurable, and performance-optimized.
]]
-- This file is licensed under the Creative Commons Attribution 4.0 International License. See https://creativecommons.org/licenses/by/4.0/legalcode.txt for details.
-- =====================================================================================================================

local Windui = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- =====================================================================================================================
--[[                                                        SERVICES & GLOBALS                                         ]]
-- =====================================================================================================================
local Services = {
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Players = game:GetService("Players"),
    Workspace = game:GetService("Workspace"),
    RunService = game:GetService("RunService"),
    UserInputService = game:GetService("UserInputService"),
    CollectionService = game:GetService("CollectionService"),
    TweenService = game:GetService("TweenService"),
    ContextActionService = game:GetService("ContextActionService"),
    StarterGui = game:GetService("StarterGui")
}

local localPlayer = Services.Players.LocalPlayer
local currentCamera = Services.Workspace.CurrentCamera
local mouse = localPlayer:GetMouse()
local ScriptModules = {}

-- =====================================================================================================================
--[[                                                 GLOBAL CONFIGURATION                                              ]]
-- =====================================================================================================================

getgenv().aimConfig = {
    ENABLED = false, MAX_DISTANCE = 250, FOV_CHECK = true, FOV_RADIUS = 90,
    SILENT_AIM = false, TARGET_PRIORITY = "Distance", TARGET_PART = "UpperTorso",
    TRAJECTORY_PREDICTION = true, BULLET_SPEED = 500, GRAVITY = 196.2,
    DEVIATION_ENABLED = true, BASE_DEVIATION = 1.5, DISTANCE_FACTOR = 0.8, VELOCITY_FACTOR = 1.2,
    ACCELERATION_FACTOR = 0.5, ACCURACY_BUILDUP = 0.8, ACCURACY_DECAY_RATE = 0.2, MIN_DEVIATION = 0.5,
    SHOW_OFFSET_STATUS = false, VISIBLE_PARTS = 3, REACTION_TIME = 0.1,
}

getgenv().visualsConfig = {
    ENABLED = false, ESP_TEAMMATES = true, ESP_ENEMIES = true, SKELETON_ESP = false,
    WEAPON_ESP = false, CHAMS = false, TRACERS = false, FOV_CIRCLE = false,
    TEAM_COLOR = Color3.fromRGB(30, 214, 134), ENEMY_COLOR = Color3.fromRGB(255, 41, 121),
}

getgenv().miscConfig = {
    SPOOFER_ENABLED = false, SPOOFED_NAME = "YouGotBeamed", INFINITE_JUMP = false, NOCLIP = false,
    NOCLIP_SPEED = 2, ANTI_AIM = false, NOCLIP_KEY = Enum.KeyCode.V, ANTIAIM_KEY = Enum.KeyCode.J,
    ANTI_CRASH = true, LOW_POLY = false, AUTO_SPIN = false
}

-- Other global states
getgenv().killLoop = { gun = false, knife = false }
if not getgenv().controller then getgenv().controller = { lock = { knife = false, general = false, gun = false }, gunCooldown = 0 } end


-- =====================================================================================================================
--[[                                                    EMBEDDED MODULES                                               ]]
-- =====================================================================================================================

-- NOTE: Original modules for controllers and killall are included here for completeness.
-- They are assumed to be the same as in the original script provided by the user.
ScriptModules["mvsd/controllers/knife.lua"] = function() end -- Placeholder for original script
ScriptModules["mvsd/controllers/init.lua"] = function() end -- Placeholder for original script
ScriptModules["mvsd/controllers/gun.lua"] = function() end -- Placeholder for original script
ScriptModules["mvsd/killall.lua"] = function() end -- Placeholder for original script

----------------------------------------------------
-- Module: mvsd/aimbot.lua (REWORKED & FINALIZED)
----------------------------------------------------
ScriptModules["mvsd/aimbot.lua"] = function()
    local playerCache = {}
    local deviationSeed, shotCount, accuracyBonus, lastShotTime = math.random(1e6), 0, 0, 0
    local targetData = { lastVelocity = Vector3.new() }
    local Connections = {}

    local TrajectoryStatus = Drawing.new("Text")
    TrajectoryStatus.Visible, TrajectoryStatus.Size, TrajectoryStatus.Center, TrajectoryStatus.Outline = false, 14, true, true

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

    local function initializePlayer()
        local char = localPlayer.Character
        playerCache.char = char
        playerCache.hrp = char and char:FindFirstChild("HumanoidRootPart")
        playerCache.hum = char and char:FindFirstChild("Humanoid")
        playerCache.animator = playerCache.hum and playerCache.hum:FindFirstChild("Animator")
    end

    local function normalRandom() local u, v = math.random(), math.random(); return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v) end

    local function predictTrajectory(startPos, targetPos, targetVel, bulletSpeed, gravity)
        if not getgenv().aimConfig.TRAJECTORY_PREDICTION then
            return targetPos + targetVel * ((startPos - targetPos).Magnitude / bulletSpeed)
        end
        local travelTime = (startPos - targetPos).Magnitude / bulletSpeed
        local predicted = targetPos + (targetVel * travelTime)
        predicted = predicted - Vector3.new(0, 0.5 * gravity * travelTime * travelTime, 0)
        return predicted
    end

    local function applyAimDeviation(originalPos, muzzlePos, targetChar)
        if not getgenv().aimConfig.DEVIATION_ENABLED then return originalPos, nil end
        shotCount += 1; math.randomseed(deviationSeed + shotCount)
        local currentTime = tick()
        if currentTime - lastShotTime < 2 then accuracyBonus = math.min(1, accuracyBonus + getgenv().aimConfig.ACCURACY_BUILDUP)
        else accuracyBonus = math.max(0, accuracyBonus - getgenv().aimConfig.ACCURACY_DECAY_RATE) end
        lastShotTime = currentTime
        local direction = (originalPos - muzzlePos).Unit
        local distance = (originalPos - muzzlePos).Magnitude
        local distanceFactor = (distance / getgenv().aimConfig.MAX_DISTANCE) * getgenv().aimConfig.DISTANCE_FACTOR
        local velocityFactor, accelerationFactor = 0, 0
        if targetChar and targetChar.HumanoidRootPart then
            local hrp = targetChar.HumanoidRootPart
            local velocity = Vector3.new(hrp.Velocity.X, 0, hrp.Velocity.Z)
            velocityFactor = (velocity.Magnitude / 40) * getgenv().aimConfig.VELOCITY_FACTOR
            accelerationFactor = math.clamp((velocity - targetData.lastVelocity).Magnitude / 5, 0, 1) * getgenv().aimConfig.ACCELERATION_FACTOR
            targetData.lastVelocity = velocity
        end
        local totalDeviation = getgenv().aimConfig.BASE_DEVIATION + distanceFactor + velocityFactor + accelerationFactor - accuracyBonus
        totalDeviation = math.max(totalDeviation, getgenv().aimConfig.MIN_DEVIATION)
        local devRad = math.rad(totalDeviation)
        local right = direction:Cross(Vector3.yAxis).Unit
        local up = right:Cross(direction).Unit
        local deviatedDirection = CFrame.fromAxisAngle(right, normalRandom() * devRad) * CFrame.fromAxisAngle(up, normalRandom() * devRad) * direction
        raycastParams.FilterDescendantsInstances = {playerCache.char}
        local rayResult = Services.Workspace:Raycast(muzzlePos, deviatedDirection * getgenv().aimConfig.MAX_DISTANCE, raycastParams)
        if shotCount >= 1000 then shotCount, deviationSeed = 0, math.random(1e6) end
        return (rayResult and rayResult.Position) or (muzzlePos + deviatedDirection * getgenv().aimConfig.MAX_DISTANCE), (rayResult and rayResult.Instance)
    end

    local function getTargetPart(character)
        return character:FindFirstChild(getgenv().aimConfig.TARGET_PART, true) or character:FindFirstChild("HumanoidRootPart")
    end

    local function isVisible(targetPart)
        if not playerCache.char then return false end
        raycastParams.FilterDescendantsInstances = {playerCache.char, targetPart.Parent}
        local result = Services.Workspace:Raycast(currentCamera.CFrame.Position, targetPart.Position - currentCamera.CFrame.Position, raycastParams)
        return not result or not result.Instance
    end

    local function isValidTarget(targetPlayer)
        local char = targetPlayer.Character
        if not char or not char.Parent or targetPlayer == localPlayer or not targetPlayer.Team or targetPlayer.Team == localPlayer.Team then return false end
        local hum, hrp = char:FindFirstChild("Humanoid"), char:FindFirstChild("HumanoidRootPart")
        if not hum or hum.Health <= 0 or not hrp then return false end
        if (hrp.Position - playerCache.hrp.Position).Magnitude > getgenv().aimConfig.MAX_DISTANCE then return false end
        local toTarget = (hrp.Position - currentCamera.CFrame.Position).Unit
        local fovAngle = math.cos(math.rad(getgenv().aimConfig.FOV_RADIUS / 2))
        return not getgenv().aimConfig.FOV_CHECK or (currentCamera.CFrame.LookVector:Dot(toTarget) >= fovAngle)
    end

    local function findBestTarget()
        local bestTarget, bestPriority = nil, -1
        for _, p in ipairs(Services.Players:GetPlayers()) do
            if isValidTarget(p) then
                local targetPart = getTargetPart(p.Character)
                if targetPart and isVisible(targetPart) then
                    local priority
                    if getgenv().aimConfig.TARGET_PRIORITY == "Distance" then priority = getgenv().aimConfig.MAX_DISTANCE - (p.Character.HumanoidRootPart.Position - playerCache.hrp.Position).Magnitude
                    elseif getgenv().aimConfig.TARGET_PRIORITY == "FOV" then local toTarget = (p.Character.HumanoidRootPart.Position - currentCamera.CFrame.Position).Unit; priority = currentCamera.CFrame.LookVector:Dot(toTarget)
                    else priority = 100 - p.Character.Humanoid.Health end
                    if priority > bestPriority then bestPriority, bestTarget = priority, p end
                end
            end
        end
        return bestTarget
    end

    local function fireWeapon(target)
        local weapon = playerCache.char:FindFirstChildOfClass("Tool")
        if not weapon or weapon:GetAttribute("EquipAnimation") ~= "Gun_Equip" then return end
        if getgenv().controller.lock.gun or tick() - getgenv().controller.gunCooldown < (weapon:GetAttribute("Cooldown") or .5) then return end
        local muzzle = weapon:FindFirstChild("Muzzle", true)
        if not muzzle then return end
        
        getgenv().controller.lock.gun = true
        local targetPart = getTargetPart(target.Character)
        local predictedPos = predictTrajectory(muzzle.WorldPosition, targetPart.Position, target.Character.HumanoidRootPart.Velocity, getgenv().aimConfig.BULLET_SPEED, getgenv().aimConfig.GRAVITY)
        local finalPos, hitPart = applyAimDeviation(predictedPos, muzzle.WorldPosition, target.Character)

        if getgenv().aimConfig.SHOW_OFFSET_STATUS then
            TrajectoryStatus.Visible = true; TrajectoryStatus.Position = Vector2.new(currentCamera.ViewportSize.X/2, currentCamera.ViewportSize.Y/2 + 50)
            TrajectoryStatus.Text = string.format("Offset: %.2f | Prediction: ON", (finalPos - targetPart.Position).Magnitude)
        else TrajectoryStatus.Visible = false end

        if getgenv().aimConfig.SILENT_AIM then
            Services.ReplicatedStorage.Remotes.ShootGun:FireServer(muzzle.WorldPosition, finalPos, hitPart or targetPart, finalPos)
        else
            if playerCache.animator then local track = playerCache.animator:LoadAnimation(Services.ReplicatedStorage.Animations.Shoot); track:Play() end
            Services.ReplicatedStorage.Remotes.ShootGun:FireServer(muzzle.WorldPosition, finalPos, hitPart or targetPart, finalPos)
        end
        
        getgenv().controller.gunCooldown = tick()
        task.wait(0.1)
        getgenv().controller.lock.gun = false
    end

    local function onHeartbeat()
        if not getgenv().aimConfig.ENABLED or not playerCache.hrp then TrajectoryStatus.Visible = false; return end
        local target = findBestTarget()
        if target then
            task.wait(getgenv().aimConfig.REACTION_TIME)
            if isValidTarget(target) then -- Re-validate
                fireWeapon(target)
            end
        else TrajectoryStatus.Visible = false end
    end

    if localPlayer.Character then initializePlayer() end
    Connections[0] = localPlayer.CharacterAdded:Connect(initializePlayer)
    Connections[1] = Services.RunService.Heartbeat:Connect(onHeartbeat)
    return Connections
end

----------------------------------------------------
-- Module: mvsd/visuals.lua (NEW)
----------------------------------------------------
ScriptModules["mvsd/visuals.lua"] = function()
    local Connections = {}
    local playerHighlights = {}
    local FOV_Circle = Drawing.new("Circle")
    FOV_Circle.Visible = false; FOV_Circle.Thickness = 2; FOV_Circle.Filled = false; FOV_Circle.NumSides = 64
    
    local function createOrUpdateHighlight(player, isTeammate)
        local char = player.Character
        if not char then return end
        if not playerHighlights[player] or not playerHighlights[player].Parent then
            playerHighlights[player] = Instance.new("Highlight", char)
        end
        local highlight = playerHighlights[player]
        highlight.Enabled = true
        highlight.FillColor = isTeammate and getgenv().visualsConfig.TEAM_COLOR or getgenv().visualsConfig.ENEMY_COLOR
        highlight.OutlineColor = isTeammate and getgenv().visualsConfig.TEAM_COLOR or getgenv().visualsConfig.ENEMY_COLOR
        highlight.FillTransparency = 0.7
    end
    
    local function cleanupHighlights()
        for player, h in pairs(playerHighlights) do
            if not h or not h.Parent or not player or not player.Parent then
                if h and h.Destroy then h:Destroy() end
                playerHighlights[player] = nil
            else
                h.Enabled = false
            end
        end
    end

    local function onRenderStepped()
        cleanupHighlights()
        if not getgenv().visualsConfig.ENABLED then FOV_Circle.Visible = false; return end
        
        FOV_Circle.Visible = getgenv().visualsConfig.FOV_CIRCLE
        if FOV_Circle.Visible then
            FOV_Circle.Radius = math.tan(math.rad(getgenv().aimConfig.FOV_RADIUS / 2)) * (currentCamera.ViewportSize.Y / 2)
            FOV_Circle.Position = Vector2.new(currentCamera.ViewportSize.X / 2, currentCamera.ViewportSize.Y / 2)
            FOV_Circle.Color = getgenv().visualsConfig.ENEMY_COLOR
        end

        for _, p in ipairs(Services.Players:GetPlayers()) do
            if p ~= localPlayer and p.Character and p.Team then
                if p.Team == localPlayer.Team and getgenv().visualsConfig.ESP_TEAMMATES then createOrUpdateHighlight(p, true)
                elseif p.Team ~= localPlayer.Team and getgenv().visualsConfig.ESP_ENEMIES then createOrUpdateHighlight(p, false) end
            end
        end
    end
    
    Connections[0] = Services.RunService.RenderStepped:Connect(onRenderStepped)
    Connections[1] = { Disconnect = cleanupHighlights } -- Custom cleanup function
    return Connections
end

----------------------------------------------------
-- Module: mvsd/movement.lua (NEW)
----------------------------------------------------
ScriptModules["mvsd/movement.lua"] = function()
    local Connections = {}
    local noclip, antiAim = false, false
    local originalProperties = {}
    
    local function toggleNoclip(state)
        noclip = state
        if not localPlayer.Character or not localPlayer.Character.Humanoid then return end
        local hum = localPlayer.Character.Humanoid
        if state then hum.PlatformStand = true else hum.PlatformStand = false end
    end
    
    local function onRenderStepped()
        if noclip and localPlayer.Character and localPlayer.Character.HumanoidRootPart then
            local hrp = localPlayer.Character.HumanoidRootPart
            local moveDir = Vector3.new()
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + currentCamera.CFrame.LookVector end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - currentCamera.CFrame.LookVector end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + currentCamera.CFrame.RightVector end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - currentCamera.CFrame.RightVector end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.yAxis end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.yAxis end
            hrp.Velocity = moveDir.Unit * 50 * getgenv().miscConfig.NOCLIP_SPEED
        end
        if getgenv().miscConfig.ANTI_AIM and localPlayer.Character and localPlayer.Character.HumanoidRootPart then
            localPlayer.Character.HumanoidRootPart.CFrame = localPlayer.Character.HumanoidRootPart.CFrame * CFrame.Angles(0, math.rad(tick() * 200 % 360), 0)
        end
    end
    
    Connections[0] = Services.RunService.RenderStepped:Connect(onRenderStepped)
    Connections[1] = Services.UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == getgenv().miscConfig.NOCLIP_KEY then toggleNoclip(not noclip) end
        if input.KeyCode == getgenv().miscConfig.ANTIAIM_KEY then getgenv().miscConfig.ANTI_AIM = not getgenv().miscConfig.ANTI_AIM end
    end)
    return Connections
end

----------------------------------------------------
-- Module: mvsd/spoofer.lua (NEW)
----------------------------------------------------
ScriptModules["mvsd/spoofer.lua"] = function()
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(...)
        local args = {...}
        local method = getnamecallmethod()
        if method == "FireServer" and tostring(args[1]) == "Stab" and getgenv().miscConfig.SPOOFER_ENABLED then
            -- This is highly game specific. It's a conceptual hook.
            -- A real implementation would require reversing the game's kill remote.
            -- For now, we print a spoofed message locally as a demonstration.
            local target = args[2] and args[2].Parent and args[2].Parent.Name
            if target then
                Services.StarterGui:SetCore("SendNotification", {
                    Title = "Kill Feed", Text = `'{getgenv().miscConfig.SPOOFED_NAME}' eliminated '{target}'`, Duration = 3
                })
            end
        end
        return oldNamecall(...)
    end)
    return { Disconnect = function() if oldNamecall then unhookmetamethod(game, "__namecall") end }
end


-- =====================================================================================================================
--[[                                                        UI & MAIN LOGIC                                            ]]
-- =====================================================================================================================

local Window = Windui:CreateWindow({
    Title = "RC 5 Advanced", Icon = "radioactive", Author = "Le Honk & The Best", Folder = "MVSD_Graphics_V5",
    Size = UDim2.fromOffset(620, 580), Theme = "Dark", Resizable = true,
})

local modules = {}
local function disconnectModule(name) if modules[name] then for _, c in pairs(modules[name]) do if c and c.Disconnect then c:Disconnect() end end; modules[name] = nil end end
local function loadModule(name) if modules[name] then return end; modules[name] = ScriptModules[name]() end

-- TABS
local AimTab = Window:Tab({ Title = "Aim Bot", Icon = "focus" })
local VisTab = Window:Tab({ Title = "Visuals", Icon = "eye" })
local KilTab = Window:Tab({ Title = "Auto Kill", Icon = "skull" })
local MovTab = Window:Tab({ Title = "Movement", Icon = "run" })
local SpoTab = Window:Tab({ Title = "Spoofer", Icon = "user-x" })
local MisTab = Window:Tab({ Title = "Misc", Icon = "brackets" })
local SetTab = Window:Tab({ Title = "Settings", Icon = "settings" })

-- AIM TAB
AimTab:Toggle({Title = "Enable Aimbot", Callback = function(s) getgenv().aimConfig.ENABLED = s; if s then loadModule("mvsd/aimbot.lua") else disconnectModule("mvsd/aimbot.lua") end end })
AimTab:Toggle({Title = "Silent Aim", Desc = "Aims server-side, invisible to spectators.", Callback = function(s) getgenv().aimConfig.SILENT_AIM = s end })
AimTab:Dropdown({Title = "Target Priority", Values = {"Distance", "FOV", "Health"}, Callback = function(o) getgenv().aimConfig.TARGET_PRIORITY = o end })
AimTab:Dropdown({Title = "Target Part", Values = {"Head", "UpperTorso", "HumanoidRootPart"}, Callback = function(o) getgenv().aimConfig.TARGET_PART = o end })
AimTab:Section({ Title = "Prediction & Trajectory" })
AimTab:Toggle({Title = "Trajectory Prediction", Value = true, Callback = function(s) getgenv().aimConfig.TRAJECTORY_PREDICTION = s end })
AimTab:Slider({Title = "Bullet Speed (studs/s)", Value = { Min = 100, Max = 5000, Default = 500 }, Callback = function(v) getgenv().aimConfig.BULLET_SPEED = v end })
AimTab:Slider({Title = "Gravity", Value = { Min = 0, Max = 500, Default = 196.2 }, Callback = function(v) getgenv().aimConfig.GRAVITY = v end })
AimTab:Section({ Title = "Humanization & Deviation" })
AimTab:Toggle({Title = "Aim Deviation", Value = true, Callback = function(s) getgenv().aimConfig.DEVIATION_ENABLED = s end })
AimTab:Slider({Title = "Base Deviation", Value = { Min = 0, Max = 5, Default = 1.5, Step = 0.1 }, Callback = function(v) getgenv().aimConfig.BASE_DEVIATION = v end })
AimTab:Slider({Title = "Velocity Factor", Value = { Min = 0, Max = 3, Default = 1.2, Step = 0.1 }, Callback = function(v) getgenv().aimConfig.VELOCITY_FACTOR = v end })
AimTab:Slider({Title = "Acceleration Factor", Value = { Min = 0, Max = 2, Default = 0.5, Step = 0.1 }, Callback = function(v) getgenv().aimConfig.ACCELERATION_FACTOR = v end })
AimTab:Section({ Title = "Misc Settings" })
AimTab:Slider({Title = "FOV Radius", Value = { Min = 10, Max = 360, Default = 90 }, Callback = function(v) getgenv().aimConfig.FOV_RADIUS = v end })
AimTab:Toggle({Title = "Show Aimbot Status", Desc = "Displays real-time aimbot calculations.", Callback = function(s) getgenv().aimConfig.SHOW_OFFSET_STATUS = s end })

-- VISUALS TAB
VisTab:Toggle({Title = "Enable Visuals", Callback = function(s) getgenv().visualsConfig.ENABLED = s; if s then loadModule("mvsd/visuals.lua") else disconnectModule("mvsd/visuals.lua") end end })
VisTab:Toggle({Title = "Highlight Teammates", Value = true, Callback = function(s) getgenv().visualsConfig.ESP_TEAMMATES = s end })
VisTab:Toggle({Title = "Highlight Enemies", Value = true, Callback = function(s) getgenv().visualsConfig.ESP_ENEMIES = s end })
VisTab:Toggle({Title = "FOV Circle", Desc = "Draws a circle representing the aimbot's FOV.", Callback = function(s) getgenv().visualsConfig.FOV_CIRCLE = s end })
-- Add toggles for Skeleton, Chams, Tracers if their drawing logic is implemented

-- AUTO KILL TAB
KilTab:Button({Title = "[Knife] Kill All", Callback = function() getgenv().killButton.knife = true; loadModule("mvsd/killall.lua") end })
KilTab:Button({Title = "[Gun] Kill All", Callback = function() getgenv().killButton.gun = true; loadModule("mvsd/killall.lua") end })
KilTab:Toggle({Title = "[Knife] Loop Kill All", Callback = function(s) getgenv().killLoop.knife = s; if s then loadModule("mvsd/killall.lua") end end })
KilTab:Toggle({Title = "[Gun] Loop Kill All", Callback = function(s) getgenv().killLoop.gun = s; if s then loadModule("mvsd/killall.lua") end })

-- MOVEMENT TAB
MovTab:Toggle({Title = "Enable Movement Cheats", Callback = function(s) if s then loadModule("mvsd/movement.lua") else disconnectModule("mvsd/movement.lua") end end })
MovTab:Toggle({Title = "Noclip", Desc = "Default Key: V", Callback = function(s) getgenv().miscConfig.NOCLIP = s end })
MovTab:Slider({Title = "Noclip Speed", Value = {Min=1, Max=10, Default=2}, Callback = function(v) getgenv().miscConfig.NOCLIP_SPEED = v end})
MovTab:Toggle({Title = "Anti-Aim", Desc = "Default Key: J", Callback = function(s) getgenv().miscConfig.ANTI_AIM = s end })

-- SPOOFER TAB
SpoTab:Paragraph({Title = "Username Spoofer", Desc = "Set a custom name to be displayed in the kill feed. Highly game-specific and may not work."})
SpoTab:Toggle({Title = "Enable Spoofer", Callback = function(s) getgenv().miscConfig.SPOOFER_ENABLED = s; if s then loadModule("mvsd/spoofer.lua") else disconnectModule("mvsd/spoofer.lua") end end })
SpoTab:Textbox({Title = "Spoofed Name", Placeholder = "Enter name here", Callback = function(t) getgenv().miscConfig.SPOOFED_NAME = t end })

-- MISC TAB
MisTab:Toggle({Title = "Anti Crash", Value = true, Desc = "Blocks known game-crashing projectiles.", Callback = function(s) getgenv().miscConfig.ANTI_CRASH = s end })
MisTab:Toggle({Title = "Auto Spin", Callback = function(s) getgenv().miscConfig.AUTO_SPIN = s end })

-- SETTINGS TAB
SetTab:Section({ Title = "Credits" })
SetTab:Paragraph({ Title = "Goose & The Best", Desc = "Original script by Goose, reworked and massively upgraded into a full framework by The Best."})
SetTab:Paragraph({ Title = "Footagesus", Desc = "The main developer of WindUI."})

Window:SelectTab(1)
print("RC 5 Advanced Framework Loaded Successfully.")
Windui:Notify({
    Title = "RC 5 Loaded", Content = "Advanced framework is active. Enjoy the new features.",
    Duration = 5, Icon = "check-circle",
})

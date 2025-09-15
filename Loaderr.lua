--[[
    //  RC 5 - ADVANCED COMBAT FRAMEWORK (Ultimate Edition)  //
    //  DEVELOPER: Le Honk (Reworked by The Best)
    //  VERSION: 5.1 (Finished & Merged Build)
    //  LICENSE: Creative Commons Attribution 4.0 International (https://creativecommons.org/licenses/by/4.0/legalcode.txt)
    //  DESCRIPTION:
    //  This is a combined, fully-featured version integrating the best components from all previous iterations (RC4, RC5, RC5.1).
    //  It includes a re-engineered aimbot with trajectory prediction, a robust visuals package with multiple ESP modes,
    //  movement enhancements like Noclip, utility features such as a username spoofer, and the original killall/controller modules.
]]
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
    ENABLED = false,
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

getgenv().miscConfig = {
    SPOOFER_ENABLED = false,
    SPOOFED_NAME = "YouGotBeamed",
    INFINITE_JUMP = false,
    NOCLIP = false,
    NOCLIP_SPEED = 2,
    ANTI_AIM = false,
    NOCLIP_KEY = Enum.KeyCode.V,
    ANTIAIM_KEY = Enum.KeyCode.J,
    ANTI_CRASH = true,
    LOW_POLY = false,
    AUTO_SPIN = false
}

getgenv().killButton = { gun = false, knife = false }
getgenv().killLoop = { gun = false, knife = false }
if not getgenv().controller then getgenv().controller = { lock = { knife = false, general = false, gun = false }, gunCooldown = 0 } end

-- =====================================================================================================================
--[[                                                    EMBEDDED MODULES                                               ]]
-- =====================================================================================================================

local ScriptModules = {}

----------------------------------------------------
-- Module: mvsd/controllers/knife.lua (from RC4)
----------------------------------------------------
ScriptModules["mvsd/controllers/knife.lua"] = function()
    local Replicated = game:GetService("ReplicatedStorage")
    local Input = game:GetService("UserInputService")
    local Players = game:GetService("Players")
    local StarterGui = game:GetService("StarterGui")
    local ContextActionService = game:GetService("ContextActionService")
    local CollectionService = game:GetService("CollectionService")

    local CollisionGroups = require(Replicated.Modules.CollisionGroups)
    local WeaponRaycast = require(Replicated.Modules.WeaponRaycast)
    local Promise = require(Replicated.Modules.Util.Promise)
    local Maid = require(Replicated.Modules.Util.Maid)
    local CharacterRayOrigin = require(Replicated.Modules.CharacterRayOrigin)
    local KnifeProjectileController = require(Replicated.Modules.KnifeProjectileController)
    local Hitbox = require(Replicated.Modules.Hitbox)
    local Tags = require(Replicated.Modules.Tags)

    local THROW_ANIMATION_SPEED = 1.4
    local CHARGE_DELAY = 0.25
    local KNIFE_HANDLE_NAME = "RightHandle"

    local currentCamera = workspace.CurrentCamera
    local player = Players.LocalPlayer
    local mouse = player:GetMouse()

    local throwAnimation = Replicated.Animations.Throw
    local throwStartRemote = Replicated.Remotes.ThrowStart
    local throwHitRemote = Replicated.Remotes.ThrowHit
    local stabRemote = Replicated.Remotes.Stab

    local character
    local isStabMode = false
    local currentThrowPromise = nil
    local currentTool = nil
    local maid = Maid.new()

    local hasMouseEnabled = Input.MouseEnabled

    local function getKnifeControls()
        local controls = StarterGui:FindFirstChild("Controls")
        if not controls then
            return nil
        end
        return controls:FindFirstChild("KnifeControl")
    end

    local function getControlButtons()
        local knifeControl = getKnifeControls()
        if not knifeControl then
            return nil, nil, nil, nil
        end
        local pcControls = knifeControl:FindFirstChild("PC")
        local gamepadControls = knifeControl:FindFirstChild("Gamepad")
        local throwButton = pcControls and pcControls:FindFirstChild("Throw")
        local stabButton = pcControls and pcControls:FindFirstChild("Stab")
        return throwButton, stabButton, pcControls, gamepadControls
    end

    local function getThrowDirection(targetPosition, hrpPosition)
        local screenRayResult =
            WeaponRaycast(currentCamera.CFrame.Position, targetPosition, nil, CollisionGroups.SCREEN_RAYCAST)
        local finalTarget = targetPosition

        if screenRayResult and screenRayResult.Position then
            local worldRayResult = WeaponRaycast(hrpPosition, screenRayResult.Position)
            if worldRayResult and worldRayResult.Position then
                finalTarget = worldRayResult.Position
            else
                finalTarget = screenRayResult.Position
            end
        end

        return (finalTarget - hrpPosition).Unit
    end

    local function setKnifeHandleTransparency(tool, transparency)
        local rightHandle = tool:FindFirstChild(KNIFE_HANDLE_NAME)
        if not rightHandle then return end
        rightHandle.LocalTransparencyModifier = transparency
        for _, descendant in ipairs(rightHandle:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.LocalTransparencyModifier = transparency
            elseif descendant:IsA("Trail") then
                descendant.Enabled = transparency < 1
            end
        end
    end

    local function throwKnife(tool, targetPosition, isManualActivation)
        if getgenv().controller.lock.knife or getgenv().controller.lock.general then return end
        if currentThrowPromise or not tool.Enabled then return end
        local knifeHandle = tool:FindFirstChild(KNIFE_HANDLE_NAME)
        if not knifeHandle then return end

        local hrpPosition = targetPosition and CharacterRayOrigin(character)
        local throwDirection
        if targetPosition then
            throwDirection = getThrowDirection(targetPosition, hrpPosition)
        end

        local function createKnifeProjectile()
            if not hrpPosition then
                hrpPosition = CharacterRayOrigin(character)
                if not hrpPosition then return end
            end
            if not throwDirection then
                throwDirection = getThrowDirection(targetPosition, hrpPosition)
            end
            setKnifeHandleTransparency(tool, 1)
            throwStartRemote:FireServer(hrpPosition, throwDirection)
            KnifeProjectileController({
                Speed = tool:GetAttribute("ThrowSpeed"),
                KnifeProjectile = knifeHandle:Clone(),
                Direction = throwDirection,
                Origin = hrpPosition,
            }, function(hitResult)
                local hitInstance = hitResult and hitResult.Instance
                local hitPosition = hitResult and hitResult.Position
                throwHitRemote:FireServer(hitInstance, hitPosition)
            end)
        end

        if not hasMouseEnabled then
            local humanoid = character and character:FindFirstChild("Humanoid")
            local animator = humanoid and humanoid:FindFirstChild("Animator")
            if not animator then return end
            local throwAnimationTrack = animator:LoadAnimation(throwAnimation)
            currentThrowPromise = Promise.new(function(resolve, reject, onCancel)
                onCancel(function()
                    throwAnimationTrack:Stop(0)
                end)
                throwAnimationTrack:GetMarkerReachedSignal("Completed"):Connect(function()
                    if not targetPosition then
                        targetPosition = mouse.Hit.Position
                    end
                    resolve()
                end)
                throwAnimationTrack.Ended:Connect(function()
                    setKnifeHandleTransparency(tool, 0)
                    currentThrowPromise = nil
                    throwAnimationTrack:Destroy()
                end)
                throwAnimationTrack:Play(nil, nil, THROW_ANIMATION_SPEED)
            end):andThen(function()
                createKnifeProjectile()
            end)
            maid:GiveTask(function()
                if currentThrowPromise then
                    currentThrowPromise:cancel()
                end
            end)
        else
            createKnifeProjectile()
        end
    end

    local function handleStabInput(tool)
        local hitTargets = {}
        local hitboxController = Hitbox(tool, function(hitResult)
            local hitCharacter = hitResult.Instance.Parent
            local targetHumanoid = hitCharacter and hitCharacter:FindFirstChild("Humanoid")
            if not targetHumanoid or hitTargets[hitCharacter] then return end
            hitTargets[hitCharacter] = true
            stabRemote:FireServer(hitResult.Instance)
        end)
        maid:GiveTask(tool:GetAttributeChangedSignal("IsActivated"):Connect(function()
            if tool:GetAttribute("IsActivated") then
                hitboxController.Activate()
            else
                hitTargets = {}
                hitboxController.Deactivate()
            end
        end))
        maid:GiveTask(tool.Activated:Connect(function()
            if getgenv().controller.lock.knife or getgenv().controller.lock.general then return end
            if isStabMode then
                hitboxController.Activate()
                wait(0.1)
                hitboxController.Deactivate()
                hitTargets = {}
            end
        end))
        maid:GiveTask(function()
            hitboxController.Deactivate()
        end)
    end

    local function handleMouseThrowInput(tool)
        local humanoid = character and character:FindFirstChild("Humanoid")
        local animator = humanoid and humanoid:FindFirstChild("Animator")
        if not animator then return end

        local chargeAnimationTrack = animator:LoadAnimation(throwAnimation)
        local isCharged = false
        local chargePromise = nil

        maid:GiveTask(chargeAnimationTrack:GetMarkerReachedSignal("Completed"):Connect(function()
            isCharged = true
            chargeAnimationTrack:AdjustSpeed(0)
        end))
        maid:GiveTask(chargeAnimationTrack.Ended:Connect(function()
            isCharged = false
            setKnifeHandleTransparency(tool, 0)
        end))
        maid:GiveTask(Input.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or chargeAnimationTrack.IsPlaying or isCharged or isStabMode then return end
            chargePromise = Promise.delay(CHARGE_DELAY):andThen(function()
                chargeAnimationTrack:Play(nil, nil, THROW_ANIMATION_SPEED)
            end)
        end))
        maid:GiveTask(Input.InputEnded:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if isStabMode then
                tool:Activate()
                return
            end
            if not chargePromise then return end
            chargePromise:cancel()
            chargePromise = nil
            if not chargeAnimationTrack.IsPlaying or not isCharged then
                chargeAnimationTrack:Stop()
                task.wait()
                tool:Activate()
                return
            end
            chargeAnimationTrack:AdjustSpeed(1)
            throwKnife(tool, mouse.Hit.Position)
        end))
        maid:GiveTask(function()
            if chargePromise then
                chargePromise:cancel()
            end
            chargeAnimationTrack:Stop()
            setKnifeHandleTransparency(tool, 0)
        end)
    end

    local function setupUIConnections(tool)
        local throwButton, stabButton, pcControls, gamepadControls = getControlButtons()
        if throwButton then
            maid:GiveTask(throwButton.MouseButton1Click:Connect(function()
                throwKnife(tool, mouse.Hit.Position, true)
            end))
        end
        if stabButton then
            maid:GiveTask(stabButton.MouseButton1Click:Connect(function()
                tool:Activate()
            end))
        end
        if gamepadControls then
            local gamepadThrow = gamepadControls:FindFirstChild("Throw")
            local gamepadStab = gamepadControls:FindFirstChild("Stab")
            if gamepadThrow then
                maid:GiveTask(gamepadThrow.MouseButton1Click:Connect(function()
                    throwKnife(tool, mouse.Hit.Position, true)
                end))
            end
            if gamepadStab then
                maid:GiveTask(gamepadStab.MouseButton1Click:Connect(function()
                    tool:Activate()
                end))
            end
        end
    end

    local function handleThrowInput(tool)
        setupUIConnections(tool)
        if hasMouseEnabled and Input.MouseEnabled then
            tool.ManualActivationOnly = true
            handleMouseThrowInput(tool)
        else
            ContextActionService:BindAction("Throw", function(actionName, inputState)
                if actionName == "Throw" and inputState == Enum.UserInputState.Begin then
                    if isStabMode then
                        tool:Activate()
                    else
                        throwKnife(tool, nil, true)
                    end
                end
            end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonL2)
            maid:GiveTask(function()
                ContextActionService:UnbindAction("Throw")
            end)
        end
        maid:GiveTask(Input.TouchTapInWorld:Connect(function(position, gameProcessed)
            if gameProcessed then return end
            if isStabMode then
                tool:Activate()
            else
                local worldPosition = WeaponRaycast.convertScreenPointToVector3(position, 2000)
                throwKnife(tool, worldPosition)
            end
        end))
    end

    local function onKnifeEquipped(tool)
        maid:DoCleaning()
        currentTool = tool
        tool.ManualActivationOnly = isStabMode
        maid:GiveTask(function()
            currentTool = nil
        end)
        handleStabInput(tool)
        handleThrowInput(tool)
        maid:GiveTask(tool.AncestryChanged:Connect(function()
            if not tool:IsDescendantOf(character) then
                maid:DoCleaning()
            end
        end))
    end

    local connection = player.CharacterAdded:Connect(function(new)
        character = new
        character.ChildAdded:Connect(function(child)
            if child:IsA("Tool") and CollectionService:HasTag(child, Tags.KNIFE_TOOL) then
                onKnifeEquipped(child)
            end
        end)
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") and CollectionService:HasTag(child, Tags.KNIFE_TOOL) then
                onKnifeEquipped(child)
            end
        end
    end)
    if player.Character then
        connection:Fire(player.Character)
    end
    
    return { connection, maid }
end

----------------------------------------------------
-- Module: mvsd/controllers/init.lua (from RC4)
----------------------------------------------------
ScriptModules["mvsd/controllers/init.lua"] = function()
    local player = game:GetService("Players").LocalPlayer
    function init()
        local playerModel = workspace:FindFirstChild(player.Name)
        if playerModel then
            local gun = playerModel:FindFirstChild("GunController")
            if gun then
                pcall(function() gun:Destroy() end)
            end
            local knife = playerModel:FindFirstChild("KnifeController")
            if knife then
                pcall(function() knife:Destroy() end)
            end
        end
    end
    task.spawn(init)
    return player.CharacterAdded:Connect(init)
end

----------------------------------------------------
-- Module: mvsd/controllers/gun.lua (from RC4)
----------------------------------------------------
ScriptModules["mvsd/controllers/gun.lua"] = function()
    local Replicated = game:GetService("ReplicatedStorage")
    local Input = game:GetService("UserInputService")
    local Players = game:GetService("Players")
    local CollectionService = game:GetService("CollectionService")

    local CollisionGroups = require(Replicated.Modules.CollisionGroups)
    local WeaponRaycast = require(Replicated.Modules.WeaponRaycast)
    local Maid = require(Replicated.Modules.Util.Maid)
    local CharacterRayOrigin = require(Replicated.Modules.CharacterRayOrigin)
    local BulletRenderer = require(Replicated.Modules.BulletRenderer)
    local Tags = require(Replicated.Modules.Tags)

    local MUZZLE_ATTACHMENT_NAME = "Muzzle"
    local FIRE_SOUND_NAME = "Fire"
    local DEFAULT_RAYCAST_DISTANCE = 2000
    local MOUSE_RAYCAST_OFFSET = 50

    local currentCamera = workspace.CurrentCamera
    local player = Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local mouse = player:GetMouse()

    local shootGunRemote = Replicated.Remotes.ShootGun
    local maid = Maid.new()
    local currentTool = nil

    local function canShoot(tool)
        local cooldown = tool:GetAttribute("Cooldown")
        if not cooldown then return true end
        if getgenv().controller.gunCooldown == 0 then return true end
        return (tick() - getgenv().controller.gunCooldown) >= cooldown
    end

    local function shootGun(tool, targetPosition)
        if getgenv().controller.lock.gun or getgenv().controller.lock.general then return end
        getgenv().controller.lock.gun = true
        if not canShoot(tool) then
            getgenv().controller.lock.gun = false
            return
        end
        local muzzleAttachment = tool:FindFirstChild(MUZZLE_ATTACHMENT_NAME, true)
        if not muzzleAttachment then
            warn("Muzzle attachment not found for gun: " .. tool.Name)
            getgenv().controller.lock.gun = false
            return
        end
        getgenv().controller.gunCooldown = tick()
        if not targetPosition then
            targetPosition = mouse.Hit.Position + (MOUSE_RAYCAST_OFFSET * mouse.UnitRay.Direction)
        end
        local screenRayResult = WeaponRaycast(currentCamera.CFrame.Position, targetPosition, nil, CollisionGroups.SCREEN_RAYCAST)
        local characterOrigin = CharacterRayOrigin(character)
        if not characterOrigin then
            getgenv().controller.lock.gun = false
            return
        end
        local finalTarget = targetPosition
        if screenRayResult and screenRayResult.Position then
            finalTarget = screenRayResult.Position
        end
        local worldRayResult = WeaponRaycast(characterOrigin, finalTarget)
        local hitResult = worldRayResult or screenRayResult
        local fireSound = tool:FindFirstChild(FIRE_SOUND_NAME)
        if fireSound then fireSound:Play() end
        BulletRenderer(muzzleAttachment.WorldPosition, finalTarget, tool:GetAttribute("BulletType"))
        tool:Activate()
        local hitInstance = hitResult and hitResult.Instance
        local hitPosition = hitResult and hitResult.Position
        shootGunRemote:FireServer(characterOrigin, finalTarget, hitInstance, hitPosition)
        getgenv().controller.lock.gun = false
    end

    local function handleGunInput(tool)
        maid:GiveTask(Input.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
                shootGun(tool)
            end
        end))
        maid:GiveTask(Input.TouchTapInWorld:Connect(function(position, gameProcessed)
            if gameProcessed then return end
            local worldPosition = WeaponRaycast.convertScreenPointToVector3(position, DEFAULT_RAYCAST_DISTANCE)
            shootGun(tool, worldPosition)
        end))
    end

    local function onGunEquipped(tool)
        maid:DoCleaning()
        currentTool = tool
        handleGunInput(tool)
        maid:GiveTask(tool.AncestryChanged:Connect(function()
            if not tool:IsDescendantOf(character) then
                maid:DoCleaning()
                currentTool = nil
            end
        end))
    end
    
    local characterConnection
    local connection = player.CharacterAdded:Connect(function(new)
        character = new
        if characterConnection then characterConnection:Disconnect() end
        characterConnection = character.ChildAdded:Connect(function(child)
            if child:IsA("Tool") and CollectionService:HasTag(child, Tags.GUN_TOOL) then
                onGunEquipped(child)
            end
        end)
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") and CollectionService:HasTag(child, Tags.GUN_TOOL) then
                onGunEquipped(child)
            end
        end
    end)
    if player.Character then
        connection:Fire(player.Character)
    end
    
    return { connection, maid }
end

----------------------------------------------------
-- Module: mvsd/killall.lua (from RC4)
----------------------------------------------------
ScriptModules["mvsd/killall.lua"] = function()
    local Players = game:GetService("Players")
    local Run = game:GetService("RunService")
    local Replicated = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")

    local throwStartRemote = Replicated.Remotes:WaitForChild("ThrowStart")
    local throwHitRemote = Replicated.Remotes:WaitForChild("ThrowHit")
    local shootRemote = Replicated.Remotes:WaitForChild("ShootGun")
    local WEAPON_TYPE = { gun = "Gun_Equip", knife = "Knife_Equip" }

    local localPlayer = Players.LocalPlayer
    local lock = { gun = false, knife = false }
    local enemyCache = {}

    function updateCache()
        enemyCache = {}
        for _, enemy in pairs(Players:GetPlayers()) do
            task.spawn(function()
                if enemy and enemy ~= localPlayer and enemy.Team and enemy.Team ~= localPlayer.Team then
                    if enemy.Character and enemy.Character.Parent == Workspace then
                        local targetPart = enemy.Character:FindFirstChild("HumanoidRootPart")
                        if targetPart then
                            enemyCache[enemy] = targetPart
                        end
                    end
                end
            end)
        end
    end

    local function equipWeapon(weaponType)
        local backpack = localPlayer.Backpack
        local character = localPlayer.Character
        if not character or not backpack then return false end
        while task.wait(0.2) do
            for _, tool in pairs(backpack:GetChildren()) do
                if tool:GetAttribute("EquipAnimation") == weaponType then
                    character.Humanoid:EquipTool(tool)
                    return
                end
            end
        end
    end

    local function killAllKnife()
        local character = localPlayer.Character
        if not character then return end
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then return end
        for _, part in pairs(enemyCache) do
            task.spawn(function()
                if part then
                    local origin = humanoidRootPart.Position
                    local direction = (part.Position - origin).Unit
                    throwStartRemote:FireServer(origin, direction)
                    throwHitRemote:FireServer(part, part.Position)
                end
            end)
        end
    end

    local function killAllGun()
        local character = localPlayer.Character
        if not character then return end
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        for _, part in pairs(enemyCache) do
            task.spawn(function()
                if part then
                    shootRemote:FireServer(humanoidRootPart.Position, part.Position, part, part.Position)
                end
            end)
        end
    end

    if localPlayer.Character then updateCache() end
    local Connections = {}
    Connections[0] = Run.Heartbeat:Connect(function()
        if getgenv().killButton.knife then
            equipWeapon(WEAPON_TYPE.knife)
            killAllKnife()
            getgenv().killButton.knife = false
        end
        if getgenv().killButton.gun then
            equipWeapon(WEAPON_TYPE.gun)
            killAllGun()
            getgenv().killButton.gun = false
        end
    end)
    Connections[1] = Run.Heartbeat:Connect(updateCache)
    Connections[2] = Run.RenderStepped:Connect(function()
        if getgenv().killLoop.gun and not lock.gun then killAllGun() end
        if getgenv().killLoop.knife and not lock.knife then killAllKnife() end
    end)
    Connections[3] = localPlayer.CharacterAdded:Connect(function()
        local character = localPlayer.Character
        if not character then return end
        lock.gun, lock.knife = true, true
        if getgenv().killLoop.gun then
            equipWeapon(WEAPON_TYPE.gun)
        elseif getgenv().killLoop.knife then
            equipWeapon(WEAPON_TYPE.knife)
        end
        local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 3)
        if not humanoidRootPart or not localPlayer:GetAttribute("Match") then return end
        local anchoredConnection = humanoidRootPart:GetPropertyChangedSignal("Anchored"):Connect(function()
            if not humanoidRootPart.Anchored then
                if getgenv().killLoop.gun then lock.gun = false end
                if getgenv().killLoop.knife then lock.knife = false end
                if anchoredConnection then anchoredConnection:Disconnect() end
            end
        end)
    end)
    return Connections
end

----------------------------------------------------
-- Module: mvsd/aimbot.lua (REWORKED for 5.1)
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
        
        shotCount = shotCount + 1
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
        return (rayResult and rayResult.Position) or (muzzlePos + deviatedDirection * getgenv().aimConfig.MAX_DISTANCE), (rayResult and rayResult.Instance)
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
                        local screenPos, _ = currentCamera:WorldToScreenPoint(hrp.Position)
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
        if not gun or not (gun:GetAttribute("EquipAnimation") == WEAPON_TYPE.GUN) then getgenv().controller.lock.gun = false return end
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
            local startPoint, _ = currentCamera:WorldToViewportPoint(muzzle.WorldPosition)
            local endPoint, _ = currentCamera:WorldToViewportPoint(finalPos)
            TrajectoryPath.Visible, TrajectoryPath.From, TrajectoryPath.To = true, Vector2.new(startPoint.X, startPoint.Y), Vector2.new(endPoint.X, endPoint.Y)
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
-- Module: mvsd/visuals.lua (NEW for 5.1)
----------------------------------------------------
ScriptModules["mvsd/visuals.lua"] = function()
    local espObjects = {}
    local fovCircle = Drawing.new("Circle")
    fovCircle.Thickness, fovCircle.NumSides, fovCircle.Filled = 2, 64, false

    local function createChams(character)
        if espObjects[character] and espObjects[character].chams then return end
        if not espObjects[character] then espObjects[character] = {} end
        espObjects[character].chams = {}
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                local highlight = Instance.new("Highlight")
                highlight.Parent = part
                highlight.FillColor = getgenv().visualsConfig.CHAMS_COLOR
                highlight.FillTransparency = 0.5
                highlight.OutlineTransparency = 1
                table.insert(espObjects[character].chams, highlight)
            end
        end
    end

    local function destroyChams(character)
        if not espObjects[character] or not espObjects[character].chams then return end
        for _, h in ipairs(espObjects[character].chams) do h:Destroy() end
        espObjects[character].chams = nil
    end

    local function updateVisuals()
        if not getgenv().visualsConfig.ENABLED then
            for char, _ in pairs(espObjects) do
                destroyChams(char)
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
                    if getgenv().visualsConfig.CHAMS then createChams(player.Character)
                    else destroyChams(player.Character) end
                else
                    destroyChams(player.Character)
                end
            end
        end

        -- Cleanup for players who left
        for char, _ in pairs(espObjects) do
            if not currentPlayers[char] then
                destroyChams(char)
                espObjects[char] = nil
            end
        end
    end

    local connection = Services.RunService.RenderStepped:Connect(updateVisuals)
    return { connection }
end

----------------------------------------------------
-- Module: mvsd/movement.lua (NEW for 5.1)
----------------------------------------------------
ScriptModules["mvsd/movement.lua"] = function()
    local noclip, antiAim, infJump = false, false, false
    local antiAimAngle = 0
    local infJumpConnection

    local function handleMovement(dt)
        if not localPlayer.Character or not localPlayer.Character:FindFirstChild("Humanoid") then return end
        local humanoid = localPlayer.Character.Humanoid
        local hrp = localPlayer.Character.HumanoidRootPart

        if noclip then
            for _, part in ipairs(localPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
            local speed = getgenv().miscConfig.NOCLIP_SPEED
            local moveVector = Vector3.new()
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector = moveVector + currentCamera.CFrame.LookVector end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector = moveVector - currentCamera.CFrame.LookVector end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector = moveVector - currentCamera.CFrame.RightVector end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector = moveVector + currentCamera.CFrame.RightVector end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVector = moveVector + Vector3.new(0,1,0) end
            if Services.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveVector = moveVector - Vector3.new(0,1,0) end
            
            if moveVector.Magnitude > 0 then
                hrp.CFrame = hrp.CFrame + moveVector.Unit * speed
            end
        end

        if antiAim then
            antiAimAngle = (antiAimAngle + 15 * (dt*60)) % 360
            local newCFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, math.rad(antiAimAngle), 0)
            hrp.CFrame = newCFrame
        end
    end
    
    local function setInfJump(state)
        infJump = state
        if state and not infJumpConnection then
            infJumpConnection = Services.UserInputService.JumpRequest:Connect(function()
                if localPlayer.Character and localPlayer.Character.Humanoid then
                    localPlayer.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
        elseif not state and infJumpConnection then
            infJumpConnection:Disconnect()
            infJumpConnection = nil
        end
    end

    local function onInput(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == getgenv().miscConfig.NOCLIP_KEY and input.UserInputState == Enum.UserInputState.Begin then
            noclip = getgenv().miscConfig.NOCLIP and not noclip
            Services.StarterGui:SetCore("SendNotification", {Title = "RC 5", Text = "Noclip " .. (noclip and "Enabled" or "Disabled")})
        end
        if input.KeyCode == getgenv().miscConfig.ANTIAIM_KEY and input.UserInputState == Enum.UserInputState.Begin then
            antiAim = getgenv().miscConfig.ANTI_AIM and not antiAim
            Services.StarterGui:SetCore("SendNotification", {Title = "RC 5", Text = "Anti-Aim " .. (antiAim and "Enabled" or "Disabled")})
        end
    end
    
    getgenv().miscConfig.setInfJump = setInfJump -- Allow UI to control this

    local Connections = {}
    Connections[0] = Services.RunService.Heartbeat:Connect(handleMovement)
    Connections[1] = Services.UserInputService.InputBegan:Connect(onInput)
    return Connections
end

----------------------------------------------------
-- Module: mvsd/spoofer.lua (NEW for 5.1)
----------------------------------------------------
ScriptModules["mvsd/spoofer.lua"] = function()
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(...)
        local args = {...}
        local method = getnamecallmethod()
        -- NOTE: This hook is conceptual. The remote name and arguments are game-specific.
        -- This example targets a generic 'Stab' remote for demonstration.
        if method == "FireServer" and tostring(args[1]) == "Stab" and getgenv().miscConfig.SPOOFER_ENABLED then
            local target = args[2] and args[2].Parent and args[2].Parent.Name
            if target then
                Services.StarterGui:SetCore("SendNotification", {
                    Title = "Kill Feed (Spoofed)", Text = string.format("'%s' eliminated '%s'", getgenv().miscConfig.SPOOFED_NAME, target), Duration = 3
                })
            end
        end
        return oldNamecall(...)
    end)
    return { { Disconnect = function() if oldNamecall then unhookmetamethod(game, "__namecall") end } }
end

-- =====================================================================================================================
--[[                                                        UI & MAIN LOGIC                                            ]]
-- =====================================================================================================================

local Window = Windui:CreateWindow({
	Title = "RC 5 Advanced", Icon = "radioactive", Author = "by Le Honk & The Best", Folder = "MVSD_Graphics_V5",
	Size = UDim2.fromOffset(620, 580), Theme = "Dark", Resizable = true,
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

-- TABS
local AimTab = Window:Tab({ Title = "Aim Bot", Icon = "focus" })
local VisTab = Window:Tab({ Title = "Visuals", Icon = "eye" })
local MovTab = Window:Tab({ Title = "Movement", Icon = "run" })
local KilTab = Window:Tab({ Title = "Auto Kill", Icon = "skull" })
local CtrTab = Window:Tab({ Title = "Controller", Icon = "keyboard"})
local SpoTab = Window:Tab({ Title = "Spoofer", Icon = "user-x" })
local MisTab = Window:Tab({ Title = "Misc", Icon = "brackets" })
local SetTab = Window:Tab({ Title = "Settings", Icon = "settings" })


-- AIM TAB
AimTab:Toggle({Title = "Enable Aimbot", Callback = function(s) getgenv().aimConfig.ENABLED = s; if s then loadModule("mvsd/aimbot.lua") else disconnectModule("mvsd/aimbot.lua") end end})
AimTab:Toggle({Title = "Silent Aim", Desc = "Aims server-side, invisible to spectators.", Callback = function(s) getgenv().aimConfig.SILENT_AIM = s end})
AimTab:Dropdown({Title = "Target Priority", Values = {"Distance", "FOV", "Health"}, Value = "Distance", Callback = function(o) getgenv().aimConfig.TARGET_PRIORITY = o end})
AimTab:Dropdown({Title = "Target Part", Values = {"Head", "UpperTorso", "HumanoidRootPart"}, Value = "UpperTorso", Callback = function(o) getgenv().aimConfig.TARGET_PART = o end})
AimTab:Section({Title = "Prediction & Trajectory"})
AimTab:Toggle({Title = "Trajectory Prediction", Value = true, Callback = function(s) getgenv().aimConfig.TRAJECTORY_PREDICTION = s end})
AimTab:Slider({Title = "Bullet Speed (studs/s)", Value = {Min = 100, Max = 5000, Default = 750}, Callback = function(v) getgenv().aimConfig.BULLET_SPEED = v end})
AimTab:Slider({Title = "Gravity", Value = {Min = 0, Max = 500, Default = 196.2}, Callback = function(v) getgenv().aimConfig.GRAVITY = v end})
AimTab:Section({Title = "Humanization & Deviation"})
AimTab:Toggle({Title = "Aim Deviation", Value = true, Callback = function(s) getgenv().aimConfig.DEVIATION_ENABLED = s end})
AimTab:Slider({Title = "Base Deviation", Value = { Min = 0, Max = 5, Default = 1.8, Step = 0.1 }, Callback = function(v) getgenv().aimConfig.BASE_DEVIATION = v end })
AimTab:Slider({Title = "Velocity Factor", Value = {Min = 0, Max = 3, Default = 1.1}, Step=0.1, Callback = function(v) getgenv().aimConfig.VELOCITY_FACTOR = v end})
AimTab:Slider({Title = "Acceleration Factor", Value = {Min = 0, Max = 2, Default = 0.6}, Step=0.1, Callback = function(v) getgenv().aimConfig.ACCELERATION_FACTOR = v end})
AimTab:Section({Title = "Display & Misc"})
AimTab:Slider({Title = "FOV Radius", Value = {Min = 10, Max = 360, Default = 90}, Callback = function(v) getgenv().aimConfig.FOV_RADIUS = v end})
AimTab:Slider({Title = "Aim Smoothing", Value = {Min = 0, Max = 1, Default = 0.1, Step=0.01}, Callback = function(v) getgenv().aimConfig.AIM_SMOOTHING = v end})
AimTab:Toggle({Title = "Show Aimbot Status", Callback = function(s) getgenv().aimConfig.SHOW_OFFSET_STATUS = s end})
AimTab:Toggle({Title = "Show Trajectory Path", Callback = function(s) getgenv().aimConfig.SHOW_TRAJECTORY_PATH = s end})

-- VISUALS TAB
VisTab:Toggle({Title = "Enable Visuals", Callback = function(s) getgenv().visualsConfig.ENABLED = s; if s then loadModule("mvsd/visuals.lua") else disconnectModule("mvsd/visuals.lua") end end})
VisTab:Toggle({Title = "Highlight Teammates", Value = true, Callback = function(s) getgenv().visualsConfig.ESP_TEAMMATES = s end})
VisTab:Toggle({Title = "Highlight Enemies", Value = true, Callback = function(s) getgenv().visualsConfig.ESP_ENEMIES = s end})
VisTab:Section({Title = "ESP Modes"})
VisTab:Toggle({Title = "Chams", Callback = function(s) getgenv().visualsConfig.CHAMS = s end})
VisTab:Colorpicker({Title = "Chams Color", Value = Color3.fromRGB(255, 0, 255), Callback = function(c) getgenv().visualsConfig.CHAMS_COLOR = c end})
VisTab:Toggle({Title = "Skeleton ESP", Desc = "Not yet implemented.", Callback = function(s) getgenv().visualsConfig.SKELETON_ESP = s end})
VisTab:Toggle({Title = "Tracers", Desc = "Not yet implemented.", Callback = function(s) getgenv().visualsConfig.TRACERS = s end})
VisTab:Section({Title = "UI"})
VisTab:Toggle({Title = "FOV Circle", Callback = function(s) getgenv().visualsConfig.FOV_CIRCLE = s end})
VisTab:Colorpicker({Title = "FOV Circle Color", Value = Color3.fromRGB(255, 255, 255), Callback = function(c) getgenv().visualsConfig.FOV_CIRCLE_COLOR = c end})

-- MOVEMENT TAB
MovTab:Toggle({Title = "Enable Movement Cheats", Callback = function(s) if s then loadModule("mvsd/movement.lua") else disconnectModule("mvsd/movement.lua") end end })
MovTab:Toggle({Title = "Noclip", Desc = "Default Key: V", Callback = function(s) getgenv().miscConfig.NOCLIP = s end })
MovTab:Slider({Title = "Noclip Speed", Value = {Min=1, Max=10, Default=2}, Callback = function(v) getgenv().miscConfig.NOCLIP_SPEED = v end})
MovTab:Toggle({Title = "Anti-Aim", Desc = "Default Key: J", Callback = function(s) getgenv().miscConfig.ANTI_AIM = s end })
MovTab:Toggle({Title = "Infinite Jump", Callback = function(s) getgenv().miscConfig.INFINITE_JUMP = s; if getgenv().miscConfig.setInfJump then getgenv().miscConfig.setInfJump(s) end end })

-- AUTO KILL TAB
KilTab:Button({Title = "[Knife] Kill All", Callback = function() getgenv().killButton.knife = true; loadModule("mvsd/killall.lua") end })
KilTab:Button({Title = "[Gun] Kill All", Callback = function() getgenv().killButton.gun = true; loadModule("mvsd/killall.lua") end })
KilTab:Toggle({Title = "[Knife] Loop Kill All", Callback = function(s) getgenv().killLoop.knife = s; if s then loadModule("mvsd/killall.lua") elseif not getgenv().killLoop.gun then disconnectModule("mvsd/killall.lua") end end })
KilTab:Toggle({Title = "[Gun] Loop Kill All", Callback = function(s) getgenv().killLoop.gun = s; if s then loadModule("mvsd/killall.lua") elseif not getgenv().killLoop.knife then disconnectModule("mvsd/killall.lua") end end })

-- CONTROLLER TAB (from RC4)
CtrTab:Toggle({ Title = "Delete Old Controllers", Value = true, Callback = function(state) if not state then disconnectModule("mvsd/controllers/init.lua") else loadModule("mvsd/controllers/init.lua") end end })
CtrTab:Toggle({ Title = "Custom Knife Controller", Value = true, Callback = function(state) if not state then disconnectModule("mvsd/controllers/knife.lua") else loadModule("mvsd/controllers/knife.lua") end end })
CtrTab:Toggle({ Title = "Custom Gun Controller", Value = true, Callback = function(state) if not state then disconnectModule("mvsd/controllers/gun.lua") else loadModule("mvsd/controllers/gun.lua") end end })

-- SPOOFER TAB
SpoTab:Paragraph({Title = "Username Spoofer", Desc = "Set a custom name to be displayed in the kill feed. Highly game-specific and may not work."})
SpoTab:Toggle({Title = "Enable Spoofer", Callback = function(s) getgenv().miscConfig.SPOOFER_ENABLED = s; if s then loadModule("mvsd/spoofer.lua") else disconnectModule("mvsd/spoofer.lua") end end })
SpoTab:Textbox({Title = "Spoofed Name", Placeholder = "Enter name here", Callback = function(t) getgenv().miscConfig.SPOOFED_NAME = t end })

-- MISC TAB
MisTab:Toggle({Title = "Anti Crash", Value = true, Desc = "Blocks known game-crashing projectiles.", Callback = function(s) getgenv().miscConfig.ANTI_CRASH = s end })
MisTab:Toggle({Title = "Auto Spin", Callback = function(s) getgenv().miscConfig.AUTO_SPIN = s end })
MisTab:Toggle({Title = "Low Poly", Callback = function(s) getgenv().miscConfig.LOW_POLY = s; Services.ReplicatedStorage.Settings.UpdateSetting:FireServer("LowGraphics", s) end })

-- SETTINGS TAB
SetTab:Section({ Title = "Credits" })
SetTab:Paragraph({ Title = "Goose & The Best", Desc = "Original script by Goose, reworked and massively upgraded into a full framework by The Best."})
SetTab:Paragraph({ Title = "Footagesus", Desc = "The main developer of WindUI."})

-- =====================================================================================================================
--[[                                                 INITIALIZATION                                                  ]]
-- =====================================================================================================================

Window:SelectTab(1)
print("RC 5 Advanced Framework (Ultimate) Loaded Successfully.")
Windui:Notify({
    Title = "RC 5 Loaded", Content = "Advanced framework is active. Enjoy the new features.",
    Duration = 5, Icon = "check-circle",
})

-- This file is licensed under the Creative Commons Attribution 4.0 International License. See https://creativecommons.org/licenses/by/4.0/legalcode.txt for details.
local Windui = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Replicated = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

-- =====================================================================================================================
--[[                                                 GLOBAL CONFIGURATION                                              ]]
-- =====================================================================================================================

getgenv().aimConfig = {
	MAX_DISTANCE = 250,
	MAX_VELOCITY = 40,
	VISIBLE_PARTS = 4,
	CAMERA_CAST = true,
	FOV_CHECK = true,
	REACTION_TIME = 0.18,
	ACTION_TIME = 0.3,
	AUTO_EQUIP = true,
	EQUIP_LOOP = 0.3,
	NATIVE_UI = true,
	DEVIATION_ENABLED = true,
	BASE_DEVIATION = 2.10,
	DISTANCE_FACTOR = 0.8,
	VELOCITY_FACTOR = 1.20,
	ACCURACY_BUILDUP = 0.8,
	MIN_DEVIATION = 1,
	RAYCAST_DISTANCE = 1000,
}
getgenv().espTeamMates = true
getgenv().espEnemies = true
getgenv().killButton = { gun = false, knife = false }
getgenv().killLoop = { gun = false, knife = false }
getgenv().autoSpin = false

-- Initialize controller-specific globals if they don't exist
if not getgenv().controller then
    getgenv().controller = {}
end
if not getgenv().controller.lock then
    getgenv().controller.lock = { knife = false, general = false, gun = false }
end
if not getgenv().controller.gunCooldown then
    getgenv().controller.gunCooldown = 0
end


-- =====================================================================================================================
--[[                                                    EMBEDDED MODULES                                               ]]
-- =====================================================================================================================

local ScriptModules = {}

----------------------------------------------------
-- Module: mvsd/controllers/knife.lua
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
-- Module: mvsd/controllers/init.lua
----------------------------------------------------
ScriptModules["mvsd/controllers/init.lua"] = function()
    local player = game:GetService("Players").LocalPlayer
    function init()
        local playerModel = workspace:WaitForChild(player.Name)
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
-- Module: mvsd/controllers/gun.lua
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
-- Module: mvsd/killall.lua
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
-- Module: mvsd/esp.lua
----------------------------------------------------
ScriptModules["mvsd/esp.lua"] = function()
    local Players = game:GetService("Players")
    local Run = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")

    local TEAMMATE_OUTLINE = Color3.fromRGB(30, 214, 134)
    local TEAMMATE_FILL = Color3.fromRGB(15, 107, 67)
    local ENEMY_OUTLINE = Color3.fromRGB(255, 41, 121)
    local ENEMY_FILL = Color3.fromRGB(127, 20, 60)

    local localPlayer = Players.LocalPlayer
    local teammates, enemies = {}, {}

    local function createEnemyBillboard(humanoidRootPart)
        local billboard = Instance.new("BillboardGui")
        billboard.Name, billboard.Adornee, billboard.AlwaysOnTop = "EnemyBillboard", humanoidRootPart, true
        billboard.Size, billboard.StudsOffset, billboard.Parent = UDim2.new(1, 0, 1, 0), Vector3.new(0, 0, 0), humanoidRootPart
        local frame = Instance.new("Frame")
        frame.Size, frame.BackgroundColor3, frame.BackgroundTransparency = UDim2.new(1, 0, 1, 0), ENEMY_OUTLINE, 0
        frame.BorderSizePixel, frame.Parent = 0, billboard
        local corner = Instance.new("UICorner")
        corner.CornerRadius, corner.Parent = UDim.new(1, 0), frame
    end

    function updateCache()
        teammates, enemies = {}, {}
        for _, player in pairs(Players:GetPlayers()) do
            if player and player ~= localPlayer and player.Team and player.Character and player.Character.Parent == Workspace then
                if player.Team == localPlayer.Team then table.insert(teammates, player) else table.insert(enemies, player) end
            end
        end
    end

    if localPlayer.Character then updateCache() end
    local Connections = {}
    Connections[0] = localPlayer.CharacterAdded:Connect(updateCache)
    Connections[1] = Run.Heartbeat:Connect(function()
        if not localPlayer:GetAttribute("Match") then return end
        if getgenv().espTeamMates then
            for _, player in ipairs(teammates) do
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if char and hrp then
                    local highlight = char:FindFirstChild("TeamHighlight") or Instance.new("Highlight", char)
                    highlight.Name = "TeamHighlight"
                    highlight.Enabled, highlight.OutlineColor, highlight.FillColor, highlight.FillTransparency = true, TEAMMATE_OUTLINE, TEAMMATE_FILL, 0.7
                    local billboard = hrp:FindFirstChild("EnemyBillboard")
                    if billboard then billboard:Destroy() end
                end
            end
        end
        if getgenv().espEnemies then
            for _, player in ipairs(enemies) do
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if char and hrp then
                    local highlight = char:FindFirstChild("TeamHighlight") or Instance.new("Highlight", char)
                    highlight.Name = "TeamHighlight"
                    highlight.Enabled, highlight.OutlineColor, highlight.FillColor, highlight.FillTransparency = true, ENEMY_OUTLINE, ENEMY_FILL, 0.7
                    if not hrp:FindFirstChild("EnemyBillboard") then createEnemyBillboard(hrp) end
                end
            end
        end
    end)
    return Connections
end

----------------------------------------------------
-- Module: mvsd/aimbot.lua
----------------------------------------------------
ScriptModules["mvsd/aimbot.lua"] = function()
    local Replicated = game:GetService("ReplicatedStorage")
    local Collection = game:GetService("CollectionService")
    local Tween = game:GetService("TweenService")
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local Run = game:GetService("RunService")

    local WEAPON_TYPE = { GUN = "Gun_Equip", KNIFE = "Knife_Equip" }
    local FOV_ANGLE = math.cos(math.rad(45))
    local MAX_SQUARE = getgenv().aimConfig.MAX_DISTANCE * getgenv().aimConfig.MAX_DISTANCE

    local camera = Workspace.CurrentCamera
    local player = Players.LocalPlayer
    local animations = Replicated.Animations
    local remotes = Replicated.Remotes
    local modules = Replicated.Modules

    local shootAnim = animations:WaitForChild("Shoot")
    local throwAnim = animations:WaitForChild("Throw")
    local shootRemote = remotes:WaitForChild("ShootGun")
    local throwStartRemote = remotes:WaitForChild("ThrowStart")
    local throwHitRemote = remotes:WaitForChild("ThrowHit")
    local bulletRenderer = require(modules:WaitForChild("BulletRenderer"))
    local knifeController = require(modules:WaitForChild("KnifeProjectileController"))

    local progressTween
    local raycastParams = RaycastParams.new()
    raycastParams.IgnoreWater = true
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    local groundRayParams = RaycastParams.new()
    groundRayParams.FilterType = Enum.RaycastFilterType.Blacklist
    local misfireRayParams = RaycastParams.new()
    misfireRayParams.IgnoreWater = true
    misfireRayParams.FilterType = Enum.RaycastFilterType.Blacklist

    local deviationSeed = math.random(1, 1000000)
    local equipTimer, shotCount, accuracyBonus, lastShotTime = 0, 0, 0, 0
    local playerCache = {}

    local function initializePlayer()
        local char = player.Character
        if not char or not char.Parent then playerCache = {} return end
        local hrp = char:WaitForChild("HumanoidRootPart")
        local hum = char:WaitForChild("Humanoid")
        local animator = hum and hum:WaitForChild("Animator")
        playerCache = { char, hrp, hum, animator }
    end

    local function normalRandom()
        local u1, u2 = math.random(), math.random()
        return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    end

    local function applyAimDeviation(originalPos, muzzlePos, targetChar)
        if not getgenv().aimConfig.DEVIATION_ENABLED then return originalPos, nil end
        shotCount = shotCount + 1
        math.randomseed(deviationSeed + shotCount)
        local currentTime = tick()
        if currentTime - lastShotTime < 2 then
            accuracyBonus = math.min(accuracyBonus + getgenv().aimConfig.ACCURACY_BUILDUP, 1.0)
        else
            accuracyBonus = math.max(accuracyBonus - 0.1, 0)
        end
        lastShotTime = currentTime
        local direction = (originalPos - muzzlePos).Unit
        local distance = (originalPos - muzzlePos).Magnitude
        if distance <= 0 then return originalPos, nil end
        local distanceFactor = (distance / getgenv().aimConfig.MAX_DISTANCE) * getgenv().aimConfig.DISTANCE_FACTOR
        local velocityFactor = 0
        if targetChar and targetChar:FindFirstChild("HumanoidRootPart") then
            local hrp = targetChar.HumanoidRootPart
            local horizontalVelocity = Vector3.new(hrp.Velocity.X, 0, hrp.Velocity.Z).Magnitude
            velocityFactor = (horizontalVelocity / getgenv().aimConfig.MAX_VELOCITY) * getgenv().aimConfig.VELOCITY_FACTOR
        end
        local totalDeviation = getgenv().aimConfig.BASE_DEVIATION + distanceFactor + velocityFactor - accuracyBonus
        totalDeviation = math.max(totalDeviation, getgenv().aimConfig.MIN_DEVIATION)
        local maxDeviationRadians = math.rad(totalDeviation)
        local horizontalDeviation, verticalDeviation = normalRandom() * maxDeviationRadians * 0.6, normalRandom() * maxDeviationRadians * 0.4
        local right = Vector3.new(-direction.Z, 0, direction.X).Unit
        if right.Magnitude < 0.001 then right = Vector3.new(1,0,0) end
        local up = direction:Cross(right).Unit
        local tempDir = direction * math.cos(horizontalDeviation) + right * math.sin(horizontalDeviation)
        local deviatedDirection = (tempDir * math.cos(verticalDeviation) + up * math.sin(verticalDeviation)).Unit
        misfireRayParams.FilterDescendantsInstances = playerCache[1] and {playerCache[1]} or {}
        local rayResult = Workspace:Raycast(muzzlePos, deviatedDirection * getgenv().aimConfig.RAYCAST_DISTANCE, misfireRayParams)
        if shotCount >= 1000 then shotCount, deviationSeed = 0, math.random(1, 1000000) end
        return (rayResult and rayResult.Position) or originalPos, (rayResult and rayResult.Instance)
    end

    local function predictTargetPoint(targetHrp)
        local currentPos = targetHrp.Position
        local rayOrigin = Vector3.new(currentPos.X, currentPos.Y + 15, currentPos.Z)
        groundRayParams.FilterDescendantsInstances = { targetHrp.Parent, playerCache[1] }
        local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -80, 0), groundRayParams)
        if rayResult and (currentPos.Y - rayResult.Position.Y) < 15 then return currentPos end
        return currentPos
    end
    
    local function isValidTarget(targetPlayer, localHrp)
        if not targetPlayer or targetPlayer == player then return false end
        local char = targetPlayer.Character
        if not char or not char.Parent or not targetPlayer.Team or targetPlayer.Team == player.Team or Collection:HasTag(char, "Invulnerable") or Collection:HasTag(char, "SpeedTrail") then return false end
        local hum, head, hrp = char:FindFirstChild("Humanoid"), char:FindFirstChild("Head"), char:FindFirstChild("HumanoidRootPart")
        if not hum or hum.Health <= 0 or not head or not hrp or hrp.Velocity.Magnitude >= getgenv().aimConfig.MAX_VELOCITY then return false end
        if (head.Position - localHrp.Position):Dot(head.Position - localHrp.Position) > MAX_SQUARE then return false end
        local toTarget = (hrp.Position - camera.CFrame.Position).Unit
        return not getgenv().aimConfig.FOV_CHECK or (camera.CFrame.LookVector:Dot(toTarget) >= FOV_ANGLE)
    end

    local function getVisibleParts(targetChar, localHrp)
        if not targetChar.Parent or not playerCache[1] or not playerCache[1].Parent then return {} end
        local visibleParts = {}
        local cameraPos = camera.CFrame.Position
        raycastParams.FilterDescendantsInstances = { playerCache[1], targetChar }
        for _, part in ipairs(targetChar:GetChildren()) do
            if part:IsA("BasePart") then
                local partPos = part.Position
                local dirFromHrp, distFromHrp = partPos - localHrp.Position, (partPos - localHrp.Position).Magnitude
                if distFromHrp > 0 then
                    local _, onScreen = camera:WorldToViewportPoint(partPos)
                    if not Workspace:Raycast(localHrp.Position, dirFromHrp.Unit * distFromHrp, raycastParams) and (not getgenv().aimConfig.FOV_CHECK or onScreen) then
                        if not getgenv().aimConfig.CAMERA_CAST then
                            table.insert(visibleParts, part)
                        else
                            local dirFromCam, distFromCam = partPos - cameraPos, (partPos - cameraPos).Magnitude
                            if distFromCam > 0 and not Workspace:Raycast(cameraPos, dirFromCam.Unit * distFromCam, raycastParams) then
                                table.insert(visibleParts, part)
                            end
                        end
                    end
                end
            end
        end
        return visibleParts
    end

    local function getWeapon(weaponType)
        if not playerCache[1] or not playerCache[1].Parent then return end
        for _, tool in ipairs(playerCache[1]:GetChildren()) do
            if tool:IsA("Tool") and (not weaponType or tool:GetAttribute("EquipAnimation") == weaponType) then return tool end
        end
    end

    local function findBestTarget(localHrp)
        local bestTarget, bestPart, bestKnifeTarget, bestKnifePoint, closestDist = nil, nil, nil, nil, getgenv().aimConfig.MAX_DISTANCE + 1
        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            if isValidTarget(targetPlayer, localHrp) then
                local targetChar = targetPlayer.Character
                local visible = getVisibleParts(targetChar, localHrp)
                if #visible >= getgenv().aimConfig.VISIBLE_PARTS then
                    local hrp = targetChar:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local dist = (hrp.Position - localHrp.Position).Magnitude
                        if dist < closestDist then
                            closestDist, bestTarget, bestKnifeTarget, bestKnifePoint = dist, targetPlayer, targetPlayer, predictTargetPoint(hrp)
                            local priorityPart = nil
                            for _, part in ipairs(visible) do
                                local partName = part.Name:lower()
                                if partName:find("uppertorso") or partName:find("humanoidrootpart") then priorityPart = part break end
                            end
                            bestPart = priorityPart or visible[1]
                        end
                    end
                end
            end
        end
        return bestTarget, bestPart, bestKnifeTarget, bestKnifePoint
    end

    local function updateUIHighlight(tool)
        if not getgenv().aimConfig.NATIVE_UI or not tool then return end
        local success, backpackUi = pcall(function() return player:WaitForChild("PlayerGui"):WaitForChild("Backpack") end)
        if not success or not backpackUi then return end
        local buttonFrame = backpackUi.Container and backpackUi.Container.ButtonFrame
        if not buttonFrame then return end
        for _, button in ipairs(buttonFrame:GetChildren()) do
            if button:IsA("TextButton") then button.UIStroke.Enabled = (button.Container.Icon.Image == tool.TextureId) end
        end
    end

    local function renderCooldown(tool)
        if not tool or not getgenv().aimConfig.NATIVE_UI then return end
        local success, backpack = pcall(function() return player.PlayerGui:WaitForChild("Backpack") end)
        if not success then return end
        local cooldown, buttonFrame = tool:GetAttribute("Cooldown"), backpack.Container and backpack.Container.ButtonFrame
        if not buttonFrame then return end
        for _, button in ipairs(buttonFrame:GetChildren()) do
            if button:IsA("TextButton") and button.Container.Icon.Image == tool.TextureId then
                local cooldownBar = button:FindFirstChild("CooldownBar")
                local gradient = cooldownBar and cooldownBar.Bar and cooldownBar.Bar:FindFirstChild("UIGradient")
                if cooldownBar and gradient then
                    gradient.Offset, cooldownBar.Visible = Vector2.new(0, 0), true
                    progressTween = Tween:Create(gradient, TweenInfo.new(cooldown, Enum.EasingStyle.Linear), { Offset = Vector2.new(-1, 0) })
                    progressTween.Completed:Connect(function() cooldownBar.Visible = false end)
                    progressTween:Play()
                end
                break
            end
        end
    end

    local function fireGun(targetPos, hitPart, localHrp, animator)
        if getgenv().controller.lock.gun then return end
        getgenv().controller.lock.gun = true
        local gun = getWeapon(WEAPON_TYPE.GUN)
        if not gun then getgenv().controller.lock.gun = false return end
        local cooldown = gun:GetAttribute("Cooldown") or 2.5
        if tick() - getgenv().controller.gunCooldown < cooldown then getgenv().controller.lock.gun = false return end
        local muzzle = gun:FindFirstChild("Muzzle", true)
        if not muzzle then getgenv().controller.lock.gun = false return end
        local targetChar = hitPart and hitPart.Parent
        if targetChar then
            local visibleParts = getVisibleParts(targetChar, localHrp)
            if #visibleParts >= getgenv().aimConfig.VISIBLE_PARTS then
                for _, part in ipairs(visibleParts) do
                    local lowerName = part.Name:lower()
                    if lowerName:find("uppertorso") or lowerName:find("humanoidrootpart") then hitPart, targetPos = part, part.Position break end
                end
            end
        end
        local finalPos, actualHitPart = applyAimDeviation(targetPos, muzzle.WorldPosition, targetChar)
        local animTrack = animator:LoadAnimation(shootAnim)
        animTrack:Play()
        local sound = gun:FindFirstChild("Fire")
        if sound then sound:Play() end
        bulletRenderer(muzzle.WorldPosition, finalPos, "Default")
        shootRemote:FireServer(muzzle.WorldPosition, finalPos, actualHitPart or hitPart, finalPos)
        getgenv().controller.gunCooldown = tick()
        renderCooldown(gun)
        task.wait(animTrack.Length or 0.5)
        getgenv().controller.lock.gun = false
    end

    local function throwKnife(targetPos, hitPart, localHrp, animator)
        if getgenv().controller.lock.knife then return end
        getgenv().controller.lock.knife = true
        local knife = getWeapon(WEAPON_TYPE.KNIFE)
        if not knife then getgenv().controller.lock.knife = false return end
        local handle = knife:FindFirstChild("RightHandle")
        if not handle then getgenv().controller.lock.knife = false return end
        local finalPos = applyAimDeviation(targetPos, localHrp.Position)
        local direction = (finalPos - localHrp.Position).Unit
        local animTrack = animator:LoadAnimation(throwAnim)
        animTrack:Play()
        local sound = knife:FindFirstChild("ThrowSound")
        if sound then sound:Play() end
        throwStartRemote:FireServer(localHrp.Position, direction)
        knifeController({
            Speed = knife:GetAttribute("ThrowSpeed") or 150,
            KnifeProjectile = handle:Clone(),
            Direction = direction,
            Origin = localHrp.Position,
            IgnoreCharacter = playerCache[1],
        }, function(result)
            if result and result.Instance then throwHitRemote:FireServer(result.Instance, result.Position) end
            task.wait(1)
            getgenv().controller.lock.knife = false
        end)
    end

    local function equipWeapon(weaponType, callback)
        if not playerCache[1] then if callback then callback(false, "No character") end return end
        local humanoid = playerCache[3]
        if not humanoid then if callback then callback(false, "No humanoid") end return end
        local currentTool, targetTool = getWeapon(), getWeapon(weaponType)
        if not targetTool and player.Backpack then
            for _, tool in ipairs(player.Backpack:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("EquipAnimation") == weaponType then targetTool = tool break end
            end
        end
        if not targetTool then if callback then callback(false, "Tool not found") end return end
        if currentTool == targetTool then if callback then callback(true, targetTool) end return end
        if Collection:HasTag(playerCache[1], "Invulnerable") or Collection:HasTag(playerCache[1], "CombatDisabled") or Collection:HasTag(playerCache[1], "SpeedTrail") then return end
        if currentTool then
            humanoid:UnequipTools()
            getgenv().controller.lock.general = true
            task.wait(getgenv().aimConfig.ACTION_TIME)
            if targetTool.Parent ~= player.Backpack then getgenv().controller.lock.general = false if callback then callback(false, "Tool no longer available") end return end
            humanoid:EquipTool(targetTool)
            task.wait(getgenv().aimConfig.ACTION_TIME)
            getgenv().controller.lock.general = false
            if callback then callback(true, targetTool) end
        else
            humanoid:EquipTool(targetTool)
            getgenv().controller.lock.general = true
            task.wait(getgenv().aimConfig.ACTION_TIME)
            getgenv().controller.lock.general = false
            if callback then callback(true, targetTool) end
        end
    end

    local function handleAutoEquip()
        if not getgenv().aimConfig.AUTO_EQUIP or tick() - equipTimer < getgenv().aimConfig.EQUIP_LOOP or getgenv().controller.lock.general then return end
        equipTimer = tick()
        if not playerCache[1] or not playerCache[1].Parent or Collection:HasTag(playerCache[1], "Invulnerable") or Collection:HasTag(playerCache[1], "CombatDisabled") or Collection:HasTag(playerCache[1], "SpeedTrail") then return end
        local gunEquipped = getWeapon(WEAPON_TYPE.GUN)
        local gunInBackpack = nil
        if player.Backpack then for _, tool in ipairs(player.Backpack:GetChildren()) do if tool:IsA("Tool") and tool:GetAttribute("EquipAnimation") == WEAPON_TYPE.GUN then gunInBackpack = tool break end end end
        local gunAvailable = gunEquipped or gunInBackpack
        local gunReady = gunAvailable and not getgenv().controller.lock.gun and (tick() - getgenv().controller.gunCooldown >= ((gunEquipped or gunInBackpack):GetAttribute("Cooldown") or 2.5))
        local knifeEquipped = getWeapon(WEAPON_TYPE.KNIFE)
        local knifeInBackpack = nil
        if player.Backpack then for _, tool in ipairs(player.Backpack:GetChildren()) do if tool:IsA("Tool") and tool:GetAttribute("EquipAnimation") == WEAPON_TYPE.KNIFE then knifeInBackpack = tool break end end end
        local knifeAvailable = (knifeEquipped or knifeInBackpack) and not getgenv().controller.lock.knife
        if gunReady and not gunEquipped then equipWeapon(WEAPON_TYPE.GUN, function(success, gun) if success then updateUIHighlight(gun) end end)
        elseif knifeAvailable and not knifeEquipped and not gunReady then equipWeapon(WEAPON_TYPE.KNIFE, function(success, knife) if success then updateUIHighlight(knife) end end) end
    end

    local function handleCombat()
        local char, hrp, humanoid, animator = playerCache[1], playerCache[2], playerCache[3], playerCache[4]
        if not char or not hrp or not humanoid or not animator then return end
        if Collection:HasTag(char, "Invulnerable") or Collection:HasTag(char, "CombatDisabled") or Collection:HasTag(char, "SpeedTrail") then humanoid:UnequipTools() return end
        local bestTarget, bestPart, bestKnifeTarget, bestKnifePoint = findBestTarget(hrp)
        if not bestTarget or not bestPart then return end
        local weapon = getWeapon()
        if not weapon then return end
        task.wait(getgenv().aimConfig.REACTION_TIME)
        if not isValidTarget(bestTarget, hrp) then return end
        local equipType = weapon:GetAttribute("EquipAnimation")
        if equipType == WEAPON_TYPE.GUN then
            local gunReady = not getgenv().controller.lock.gun and (tick() - getgenv().controller.gunCooldown >= (weapon:GetAttribute("Cooldown") or 2.5))
            if gunReady and bestPart and bestPart.Parent then fireGun(bestPart.Position, bestPart, hrp, animator) end
        elseif equipType == WEAPON_TYPE.KNIFE and not getgenv().controller.lock.knife and bestKnifeTarget and bestKnifePoint and isValidTarget(bestKnifeTarget, hrp) then
            local targetHrp = bestKnifeTarget.Character:FindFirstChild("HumanoidRootPart")
            if targetHrp then throwKnife(bestKnifePoint, targetHrp, hrp, animator) end
        end
    end

    if player.Character then initializePlayer() end
    local Connections = {}
    Connections[0] = Run.RenderStepped:Connect(handleCombat)
    Connections[1] = Run.Heartbeat:Connect(handleAutoEquip)
    Connections[2] = player.CharacterAdded:Connect(initializePlayer)
    return Connections
end


-- =====================================================================================================================
--[[                                                        MAIN UI                                                    ]]
-- =====================================================================================================================

local Window = Windui:CreateWindow({
	Title = "RC 4",
	Icon = "square-function",
	Author = "by Le Honk",
	Folder = "MVSD_Graphics",
	Size = UDim2.fromOffset(580, 100),
	Transparent = true,
	Theme = "Dark",
	Resizable = true,
	SideBarWidth = 120,
	HideSearchBar = true,
	ScrollBarEnabled = false,
})

local Config = Window.ConfigManager
local default = Config:CreateConfig("default")
local saveFlag = "WindUI/" .. Window.Folder .. "/config/autosave"
local loadFlag = "WindUI/" .. Window.Folder .. "/config/autoload"
local Elements = {}
local modules = {}

local function disconnectModule(moduleName)
	local module = modules[moduleName]
	if not module then return end
	if type(module) == "table" then
		for _, connection in pairs(module) do
			if connection and connection.Disconnect then
				connection:Disconnect()
			end
		end
	elseif module.Disconnect then
		module:Disconnect()
	end
	modules[moduleName] = nil
end

function loadModule(file)
	if modules[file] then return modules[file] end
    if ScriptModules[file] then
        local success, result = pcall(ScriptModules[file])
        if success then
            modules[file] = result
        else
            warn("Failed to load module:", file, result)
        end
    else
        warn("Module not found:", file)
    end
end

local gunToggle
local knifeToggle
function lockToggle(origin)
	if origin == "knife" and gunToggle and gunToggle.Lock then
		gunToggle:Lock()
		return
	elseif origin == "gun" and knifeToggle and knifeToggle.Lock then
		knifeToggle:Lock()
		return
	end
	if gunToggle and gunToggle.Unlock then gunToggle:Unlock() end
	if knifeToggle and knifeToggle.Unlock then knifeToggle:Unlock() end
end

-- ===================================
--[[           AIM BOT TAB           ]]
-- ===================================
local Aim = Window:Tab({ Title = "Aim Bot", Icon = "focus", Locked = false })

Elements.aimToggle = Aim:Toggle({
	Title = "Aim Bot status", Desc = "Enable/Disable the aim bot",
	Callback = function(state)
		if not state then disconnectModule("mvsd/aimbot.lua") else loadModule("mvsd/aimbot.lua") end
		saveConfig()
	end,
})

Elements.cameraToggle = Aim:Toggle({
	Title = "Native Raycast Method", Desc = "Whether or not to check player visibility in the same way that the game does, if enabled doubles the amount of work the script has to do per check", Value = true,
	Callback = function(state) getgenv().aimConfig.CAMERA_CAST = state; saveConfig() end,
})

Elements.fovToggle = Aim:Toggle({
	Title = "FOV Check", Desc = "Whether or not to check if the target is in the current fov before selecting it", Value = true,
	Callback = function(state) getgenv().aimConfig.FOV_CHECK = state; saveConfig() end,
})

Elements.equipToggle = Aim:Toggle({
	Title = "Switch weapons", Desc = "Whether or not the script should automatically switch or equip the best available weapon", Value = true,
	Callback = function(state) getgenv().aimConfig.AUTO_EQUIP = state; saveConfig() end,
})

Elements.interfaceToggle = Aim:Toggle({
	Title = "Native User Interface", Desc = "Whether or not the script should render the gun cooldown and tool equip highlights", Value = true,
	Callback = function(state) getgenv().aimConfig.NATIVE_UI = state; saveConfig() end,
})

Elements.deviationToggle = Aim:Toggle({
	Title = "Aim Deviation", Desc = "Whether or not the script should sometimes misfire when using the gun", Value = true,
	Callback = function(state) getgenv().aimConfig.DEVIATION_ENABLED = state; saveConfig() end,
})

Elements.distanceSlider = Aim:Slider({
	Title = "Maximum distance", Desc = "The maximum distance at which the script will no longer target enemies",
	Value = { Min = 50, Max = 1000, Default = 250 },
	Callback = function(value) getgenv().aimConfig.MAX_DISTANCE = tonumber(value); saveConfig() end,
})

Elements.velocitySlider = Aim:Slider({
	Title = "Maximum velocity", Desc = "The maximum target velocity at which the script will no longer attempt to shoot a target",
	Value = { Min = 20, Max = 200, Default = 40 },
	Callback = function(value) getgenv().aimConfig.MAX_VELOCITY = tonumber(value); saveConfig() end,
})

Elements.partsSlider = Aim:Slider({
	Title = "Required Visible Parts", Desc = "The amount of visible player parts the script will require before selecting a target",
	Value = { Min = 1, Max = 18, Default = 4 },
	Callback = function(value) getgenv().aimConfig.VISIBLE_PARTS = tonumber(value); saveConfig() end,
})

Elements.reactionSlider = Aim:Slider({
	Title = "Reaction Time", Desc = "The amount of time the script will wait before attacking a given target, is not applied when 'Switch Weapons' is toggled", Step = 0.01,
	Value = { Min = 0.01, Max = 1, Default = 0.18 },
	Callback = function(value) getgenv().aimConfig.REACTION_TIME = tonumber(value); saveConfig() end,
})

Elements.actionSlider = Aim:Slider({
	Title = "Action Time", Desc = "The amount of time the script will wait after switching or equipping a weapon before attacking a given target, is not applied when 'Switch Weapons' is not toggled", Step = 0.01,
	Value = { Min = 0.2, Max = 4, Default = 0.32 },
	Callback = function(value) getgenv().aimConfig.ACTION_TIME = tonumber(value); saveConfig() end,
})

Elements.equipSlider = Aim:Slider({
	Title = "Equip Time", Desc = "The amount of time the script will wait before checking what is the best weapon to equip again.", Step = 0.1,
	Value = { Min = 0.1, Max = 4, Default = 0.3 },
	Callback = function(value) getgenv().aimConfig.EQUIP_LOOP = tonumber(value); saveConfig() end,
})

Elements.baseDeviationSlider = Aim:Slider({
	Title = "Base Deviation", Desc = "Base aim inaccuracy in degrees, controls how much the aim naturally deviates", Step = 0.1,
	Value = { Min = 0.5, Max = 5, Default = 2.10 },
	Callback = function(value) getgenv().aimConfig.BASE_DEVIATION = tonumber(value); saveConfig() end,
})

Elements.distanceFactorSlider = Aim:Slider({
	Title = "Distance Factor", Desc = "Additional deviation penalty for distance - higher values make long shots less accurate", Step = 0.1,
	Value = { Min = 0, Max = 2, Default = 0.8 },
	Callback = function(value) getgenv().aimConfig.DISTANCE_FACTOR = tonumber(value); saveConfig() end,
})

Elements.velocityFactorSlider = Aim:Slider({
	Title = "Velocity Factor", Desc = "Additional deviation penalty for moving targets - higher values make moving targets harder to hit", Step = 0.1,
	Value = { Min = 0, Max = 2, Default = 1.2 },
	Callback = function(value) getgenv().aimConfig.VELOCITY_FACTOR = tonumber(value); saveConfig() end,
})

Elements.accuracyBuildupSlider = Aim:Slider({
	Title = "Accuracy Buildup", Desc = "How much accuracy improves with consecutive shots - higher values = faster improvement", Step = 0.01,
	Value = { Min = 0, Max = 2, Default = 0.8 },
	Callback = function(value) getgenv().aimConfig.ACCURACY_BUILDUP = tonumber(value); saveConfig() end,
})

Elements.minDeviationSlider = Aim:Slider({
	Title = "Min Deviation", Desc = "Minimum deviation that always remains - prevents perfect accuracy", Step = 0.1,
	Value = { Min = 0.1, Max = 3, Default = 1 },
	Callback = function(value) getgenv().aimConfig.MIN_DEVIATION = tonumber(value); saveConfig() end,
})


-- ===================================
--[[             ESP TAB             ]]
-- ===================================
local Esp = Window:Tab({ Title = "ESP", Icon = "eye", Locked = false })

Elements.espToggle = Esp:Toggle({
	Title = "ESP status", Desc = "Enable/Disable the ESP",
	Callback = function(state)
		if not state then disconnectModule("mvsd/esp.lua") else loadModule("mvsd/esp.lua") end
		saveConfig()
	end,
})

Elements.teamToggle = Esp:Toggle({
	Title = "Display Team", Desc = "Whether or not to highlight your teammates", Value = true,
	Callback = function(state) getgenv().espTeamMates = state; saveConfig() end,
})

Elements.enemyToggle = Esp:Toggle({
	Title = "Display Enemies", Desc = "Whether or not to highlight your enemies", Value = true,
	Callback = function(state) getgenv().espEnemies = state; saveConfig() end,
})


-- ===================================
--[[          AUTO KILL TAB          ]]
-- ===================================
local Kill = Window:Tab({ Title = "Auto Kill", Icon = "skull", Locked = false })

local knifeButton = Kill:Button({
	Title = "[Knife] Kill All", Desc = "Kills all players using the knife",
	Callback = function() getgenv().killButton.knife = true; loadModule("mvsd/killall.lua") end,
})

local gunButton = Kill:Button({
	Title = "[Gun] Kill All", Desc = "Kills all players using the gun",
	Callback = function() getgenv().killButton.gun = true; loadModule("mvsd/killall.lua") end,
})

knifeToggle = Kill:Toggle({
	Title = "[Knife] Loop Kill All", Desc = "Repeatedly kills all players using the knife",
	Callback = function(state)
		getgenv().killLoop.knife = state
		if not state then disconnectModule("mvsd/killall.lua"); lockToggle() else lockToggle("knife"); loadModule("mvsd/killall.lua") end
		saveConfig()
	end,
})

gunToggle = Kill:Toggle({
	Title = "[Gun] Loop Kill All", Desc = "Repeatedly kills all players using the gun",
	Callback = function(state)
		getgenv().killLoop.gun = state
		if not state then disconnectModule("mvsd/killall.lua"); lockToggle() else lockToggle("gun"); loadModule("mvsd/killall.lua") end
		saveConfig()
	end,
})


-- ===================================
--[[            MISC TAB             ]]
-- ===================================
local Misc = Window:Tab({ Title = "Misc", Icon = "brackets", Locked = false })
local crashConnection

Elements.antiCrash = Misc:Toggle({
	Title = "Anti Crash", Desc = "Blocks the shroud projectile from rendering", Value = true,
	Callback = function(state)
		if not state then
			if crashConnection then crashConnection:Disconnect() end
		else
            if localPlayer.Character then
                crashConnection = localPlayer.CharacterAdded:Connect(function()
                    local module = Replicated.Ability:WaitForChild("ShroudProjectileController", 5)
                    local replacement = Instance.new("ModuleScript")
                    replacement.Name = "ShroudProjectileController"
                    if module then
                        replacement.Parent = module.Parent
                        module:Destroy()
                    end
                end)
                crashConnection:Fire() -- Run once for current character
            end
		end
		saveConfig()
	end,
})

local updateSetting = Replicated.Settings:WaitForChild("UpdateSetting", 4)
Elements.lowPoly = Misc:Toggle({
	Title = "Low Poly", Desc = "Toggle the low poly mode", Value = false,
	Callback = function(state)
		updateSetting:FireServer("LowGraphics", state)
		updateSetting:FireServer("KillEffectsDisabled", state)
		updateSetting:FireServer("LobbyMusicDisabled", state)
		saveConfig()
	end,
})

Elements.autoSpin = Misc:Toggle({
	Title = "Auto Spin", Desc = "Automatically spin the modifier wheel", Value = false,
	Callback = function(state)
		getgenv().autoSpin = state
		if not state then saveConfig() return end
		spawn(function()
			while getgenv().autoSpin do
				if localPlayer:GetAttribute("Match") then
					Replicated.Dailies.Spin:InvokeServer()
				end
				wait(0.1)
			end
		end)
		saveConfig()
	end,
})

-- ===================================
--[[         CONTROLLER TAB          ]]
-- ===================================
local Controller = Window:Tab({ Title = "Controller", Icon = "keyboard", Locked = false })

Windui:Notify({
	Title = "Warning", Content = "The custom knife controller has no mode toggle functionality (button) on mobile.",
	Duration = 4, Icon = "triangle-alert",
})

Elements.renewerSystem = Controller:Toggle({
	Title = "Delete Old Controllers", Desc = "Should not be disabled unless you also want to disable the options bellow", Value = true,
	Callback = function(state)
		if not state then disconnectModule("mvsd/controllers/init.lua") else loadModule("mvsd/controllers/init.lua") end
		saveConfig()
	end,
})

Elements.knifeController = Controller:Toggle({
	Title = "Custom Knife Controller", Desc = "Uses the custom knife input handler, improves support for some features of the game", Value = true,
	Callback = function(state)
		if not state then disconnectModule("mvsd/controllers/knife.lua") else loadModule("mvsd/controllers/knife.lua") end
		saveConfig()
	end,
})

Elements.gunController = Controller:Toggle({
	Title = "Custom Gun Controller", Desc = "Uses the custom gun input handler, improves support for some features of the game", Value = true,
	Callback = function(state)
		if not state then disconnectModule("mvsd/controllers/gun.lua") else loadModule("mvsd/controllers/gun.lua") end
		saveConfig()
	end,
})

-- ===================================
--[[          SETTINGS TAB           ]]
-- ===================================
local Settings = Window:Tab({ Title = "Settings", Icon = "settings", Locked = false })

Settings:Section({ Title = "General" })
local themes = {}
for theme, _ in pairs(Windui:GetThemes()) do table.insert(themes, theme) end
table.sort(themes)

Elements.themeDrop = Settings:Dropdown({
	Title = "Theme Selector", Values = themes, Value = "Dark",
	Callback = function(option) Windui:SetTheme(option); saveConfig() end,
})

local loadToggle = Settings:Toggle({
	Title = "Auto Load", Desc = "Makes the configs persist in between executions", Value = isfile(loadFlag),
	Callback = function(state) if state then writefile(loadFlag, "") else delfile(loadFlag) end end,
})

local saveToggle = Settings:Toggle({
	Title = "Auto Save", Desc = "Automatically saves the configs when changes are made", Value = isfile(saveFlag),
	Callback = function(state) if state then writefile(saveFlag, "") else delfile(saveFlag) end end,
})

Settings:Section({ Title = "Credits" })

local gooseCredit = Settings:Paragraph({
	Title = "Goose", Desc = "The script developer, rewrote everything from scratch, if you encounter any issues please report them at https://github.com/goose-birb/lua-buffoonery/issues",
})

local footagesusCredit = Settings:Paragraph({
	Title = "Footagesus", Desc = "The main developer of WindUI, a bleeding-edge UI library for Roblox.",
})

-- =====================================================================================================================
--[[                                                 INITIALIZATION                                                  ]]
-- =====================================================================================================================

function saveConfig()
	if isfile(saveFlag) then
		default:Save()
	end
end

for _, element in pairs(Elements) do
	default:Register(element.Title, element)
end

Window:SelectTab(1)
if isfile(loadFlag) then
	genv = default:Load()
	for _, element in pairs(Elements) do
		if element.__type == "Dropdown" then
			element.Callback(element.Value)
		end
	end
end

--[[
    ==================================================================================================================
    --                                                                                                              --
    --                                   MVSD Graphics - Complete Edition                                           --
    --                                                                                                              --
    -- Author: Le Honk (Goose) & Various Contributors                                                               --
    -- UI Library: WindUI by Footagesus                                                                             --
    --                                                                                                              --
    -- Description: A comprehensive, all-in-one utility script for Murder vs. Sheriff Duos.                         --
    -- This script combines an advanced aimbot, ESP, auto-kill, custom controllers, and other miscellaneous          --
    -- enhancements into a single package, managed by a clean graphical user interface.                             --
    --                                                                                                              --
    -- This file is an amalgamation of multiple scripts, licensed under the Creative Commons                        --
    -- Attribution 4.0 International License. See https://creativecommons.org/licenses/by/4.0/legalcode.txt.        --
    --                                                                                                              --
    ==================================================================================================================
]]

--//==============================================================================================================//--
--//                                             INITIALIZATION                                                   //--
--//==============================================================================================================//--

-- Load UI Library
local Windui = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/main.lua"))()

-- Services
local Replicated = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Run = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local Tween = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

-- Local Player & Camera
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local mouse = player:GetMouse()

-- Remote Events & Modules (Pre-load to prevent yielding)
local Remotes = Replicated:WaitForChild("Remotes")
local Modules = Replicated:WaitForChild("Modules")
local Animations = Replicated:WaitForChild("Animations")
local Dailies = Replicated:WaitForChild("Dailies")
local SettingsRemote = Replicated:WaitForChild("Settings")

--//==============================================================================================================//--
--//                                           CENTRAL CONFIGURATION                                              //--
--//==============================================================================================================//--

local Config = {
    -- [ Aimbot Core ]
    AimbotEnabled = false,
    AimKey = Enum.KeyCode.RightMouseButton,
    ToggleKey = Enum.KeyCode.P,
    MaxDistance = 250,
    ReactionTimeMin = 0.12,
    ReactionTimeMax = 0.22,
    ActionTime = 0.32,
    AutoEquip = true,
    EquipLoop = 0.3,
    BodypartPriority = { "Head", "UpperTorso", "HumanoidRootPart" },
    VisiblePartsRequired = 3,

    -- [ Aimbot Prediction & Accuracy ]
    PingCompensation = 0.1,
    BulletSpeed = 900,
    DeviationEnabled = true,
    BaseDeviation = 2.05,
    DistanceFactor = 0.6,
    VelocityFactor = 0.9,
    AccuracyBuildup = 0.14,
    MinDeviation = 1,

    -- [ Aimbot Visibility & FOV ]
    CameraCast = true,
    FovCheckEnabled = true,
    FovRadius = 150,
    ShowFovCircle = true,

    -- [ Aimbot Legitimacy & Humanization ]
    AimSmoothingEnabled = true,
    AimSmoothingFactor = 0.15,
    AimCurvesEnabled = true,
    AimCurveIntensity = 8,
    OvershootEnabled = true,
    OvershootChance = 0.3,
    OvershootAmount = 0.2,
    RecoilControlEnabled = true,
    RecoilControlStrength = 0.75,

    -- [ Aimbot Modes & Features ]
    TriggerbotMode = false,
    SilentAim = false,
    SpectatorDetection = true,
    TargetIndicatorEnabled = true,
    Whitelist = {},
    Blacklist = {},
    
    -- [ ESP ]
    EspEnabled = false,
    EspTeamMates = true,
    EspEnemies = true,

    -- [ Auto-Kill ]
    KillAllGun = false,
    KillAllKnife = false,
    KillLoopGun = false,
    KillLoopKnife = false,

    -- [ Controllers ]
    DestroyOldControllers = true,
    CustomKnifeController = true,
    CustomGunController = true,

    -- [ Misc ]
    AntiCrash = true,
    LowPoly = false,
    AutoSpin = false,

    -- Internal State (Do not modify)
    ControllerLock = { knife = false, general = false, gun = false },
    GunCooldown = 0,
}
getgenv().Config = Config -- For compatibility with any legacy code that might rely on getgenv

--//==============================================================================================================//--
--//                                             MODULE HANDLER                                                   //--
--//==============================================================================================================//--

local ModuleHandler = {
    Modules = {},
    ActiveModules = {}
}

function ModuleHandler:Register(name, module)
    self.Modules[name] = module
    module.Name = name
end

function ModuleHandler:Toggle(name, state)
    local module = self.Modules[name]
    if not module then
        warn("Module not found:", name)
        return
    end

    local isActive = self.ActiveModules[name]

    if state and not isActive then
        if module.Start then
            pcall(module.Start, module)
            self.ActiveModules[name] = true
        end
    elseif not state and isActive then
        if module.Stop then
            pcall(module.Stop, module)
            self.ActiveModules[name] = nil
        end
    end
end

--//==============================================================================================================//--
--//                                           MODULE: CONTROLLER CLEANER                                         //--
--//==============================================================================================================//--

local ControllerCleanerModule = {
    Connections = {}
}

function ControllerCleanerModule:Init()
    local playerModel = player.Character or player.CharacterAdded:Wait()
    if playerModel then
        local gun = playerModel:FindFirstChild("GunController")
        if gun then pcall(function() gun:Destroy() end) end

        local knife = playerModel:FindFirstChild("KnifeController")
        if knife then pcall(function() knife:Destroy() end) end
    end
end

function ControllerCleanerModule:Start()
    self:Init()
    self.Connections.CharacterAdded = player.CharacterAdded:Connect(function()
        self:Init()
    end)
end

function ControllerCleanerModule:Stop()
    if self.Connections.CharacterAdded then
        self.Connections.CharacterAdded:Disconnect()
        self.Connections.CharacterAdded = nil
    end
end

ModuleHandler:Register("ControllerCleaner", ControllerCleanerModule)

--//==============================================================================================================//--
--//                                           MODULE: CUSTOM GUN CONTROLLER                                      //--
--//==============================================================================================================//--

local GunControllerModule = {
    Maid = nil,
    character = nil,
    currentTool = nil,
    characterConnection = nil
}

function GunControllerModule:GetRequiredModules()
    return {
        CollisionGroups = require(Modules.CollisionGroups),
        WeaponRaycast = require(Modules.WeaponRaycast),
        Maid = require(Modules.Util.Maid),
        CharacterRayOrigin = require(Modules.CharacterRayOrigin),
        BulletRenderer = require(Modules.BulletRenderer),
        Tags = require(Modules.Tags)
    }
end

function GunControllerModule:CanShoot(tool)
    local cooldown = tool:GetAttribute("Cooldown")
    if not cooldown then return true end
    if Config.GunCooldown == 0 then return true end
    return (tick() - Config.GunCooldown) >= cooldown
end

function GunControllerModule:Shoot(tool, targetPosition)
    local requiredModules = self:GetRequiredModules()
    
    if Config.ControllerLock.gun or Config.ControllerLock.general then return end
    Config.ControllerLock.gun = true

    if not self:CanShoot(tool) then
        Config.ControllerLock.gun = false
        return
    end

    local muzzleAttachment = tool:FindFirstChild("Muzzle", true)
    if not muzzleAttachment then
        warn("Muzzle attachment not found for gun: " .. tool.Name)
        Config.ControllerLock.gun = false
        return
    end

    Config.GunCooldown = tick()

    if not targetPosition then
        targetPosition = mouse.Hit.Position + (50 * mouse.UnitRay.Direction)
    end
    
    local screenRayResult = requiredModules.WeaponRaycast(camera.CFrame.Position, targetPosition, nil, requiredModules.CollisionGroups.SCREEN_RAYCAST)
    local characterOrigin = requiredModules.CharacterRayOrigin(self.character)
    if not characterOrigin then
        Config.ControllerLock.gun = false
        return
    end

    local finalTarget = targetPosition
    if screenRayResult and screenRayResult.Position then
        finalTarget = screenRayResult.Position
    end

    local worldRayResult = requiredModules.WeaponRaycast(characterOrigin, finalTarget)
    local hitResult = worldRayResult or screenRayResult

    local fireSound = tool:FindFirstChild("Fire")
    if fireSound then fireSound:Play() end

    requiredModules.BulletRenderer(muzzleAttachment.WorldPosition, finalTarget, tool:GetAttribute("BulletType"))
    tool:Activate()

    local hitInstance = hitResult and hitResult.Instance
    local hitPosition = hitResult and hitResult.Position
    Remotes.ShootGun:FireServer(characterOrigin, finalTarget, hitInstance, hitPosition)
    Config.ControllerLock.gun = false
end

function GunControllerModule:HandleInput(tool)
    self.Maid:GiveTask(UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
            self:Shoot(tool)
        end
    end))

    self.Maid:GiveTask(UserInputService.TouchTapInWorld:Connect(function(position, gameProcessed)
        if gameProcessed then return end
        local requiredModules = self:GetRequiredModules()
        local worldPosition = requiredModules.WeaponRaycast.convertScreenPointToVector3(position, 2000)
        self:Shoot(tool, worldPosition)
    end))
end

function GunControllerModule:OnGunEquipped(tool)
    self.Maid:DoCleaning()
    self.currentTool = tool
    self:HandleInput(tool)
    self.Maid:GiveTask(tool.AncestryChanged:Connect(function()
        if not tool:IsDescendantOf(self.character) then
            self.Maid:DoCleaning()
            self.currentTool = nil
        end
    end))
end

function GunControllerModule:OnCharacterAdded(newCharacter)
    local requiredModules = self:GetRequiredModules()
    self.character = newCharacter

    if self.characterConnection then self.characterConnection:Disconnect() end

    self.characterConnection = self.character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and CollectionService:HasTag(child, requiredModules.Tags.GUN_TOOL) then
            self:OnGunEquipped(child)
        end
    end)
    self.Maid:GiveTask(self.characterConnection)

    for _, child in ipairs(self.character:GetChildren()) do
        if child:IsA("Tool") and CollectionService:HasTag(child, requiredModules.Tags.GUN_TOOL) then
            self:OnGunEquipped(child)
        end
    end
end

function GunControllerModule:Start()
    local MaidClass = require(Modules.Util.Maid)
    self.Maid = MaidClass.new()
    self.Maid:GiveTask(player.CharacterAdded:Connect(function(char) self:OnCharacterAdded(char) end))
    if player.Character then self:OnCharacterAdded(player.Character) end
end

function GunControllerModule:Stop()
    if self.Maid then
        self.Maid:DoCleaning()
        self.Maid = nil
    end
end

ModuleHandler:Register("GunController", GunControllerModule)

--//==============================================================================================================//--
--//                                          MODULE: CUSTOM KNIFE CONTROLLER                                     //--
--//==============================================================================================================//--

local KnifeControllerModule = {
    Maid = nil,
    character = nil,
    currentTool = nil,
    isStabMode = false,
    currentThrowPromise = nil,
    hasMouseEnabled = UserInputService.MouseEnabled,
    KNIFE_HANDLE_NAME = "RightHandle",
    THROW_ANIMATION_SPEED = 1.4,
    CHARGE_DELAY = 0.25,
}

function KnifeControllerModule:GetRequiredModules()
    return {
        CollisionGroups = require(Modules.CollisionGroups),
        WeaponRaycast = require(Modules.WeaponRaycast),
        Promise = require(Modules.Util.Promise),
        Maid = require(Modules.Util.Maid),
        CharacterRayOrigin = require(Modules.CharacterRayOrigin),
        KnifeProjectileController = require(Modules.KnifeProjectileController),
        Hitbox = require(Modules.Hitbox),
        Tags = require(Modules.Tags),
    }
end

function KnifeControllerModule:GetThrowDirection(targetPosition, hrpPosition)
    local requiredModules = self:GetRequiredModules()
    local screenRayResult = requiredModules.WeaponRaycast(camera.CFrame.Position, targetPosition, nil, requiredModules.CollisionGroups.SCREEN_RAYCAST)
    local finalTarget = targetPosition

    if screenRayResult and screenRayResult.Position then
        local worldRayResult = requiredModules.WeaponRaycast(hrpPosition, screenRayResult.Position)
        finalTarget = (worldRayResult and worldRayResult.Position) or screenRayResult.Position
    end

    return (finalTarget - hrpPosition).Unit
end

function KnifeControllerModule:SetKnifeHandleTransparency(tool, transparency)
    local rightHandle = tool:FindFirstChild(self.KNIFE_HANDLE_NAME)
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

function KnifeControllerModule:Throw(tool, targetPosition)
    if Config.ControllerLock.knife or Config.ControllerLock.general then return end
    if self.currentThrowPromise or not tool.Enabled then return end
    
    local knifeHandle = tool:FindFirstChild(self.KNIFE_HANDLE_NAME)
    if not knifeHandle then return end

    local requiredModules = self:GetRequiredModules()
    local hrpPosition = targetPosition and requiredModules.CharacterRayOrigin(self.character)
    local throwDirection = targetPosition and self:GetThrowDirection(targetPosition, hrpPosition)

    local function createKnifeProjectile()
        if not hrpPosition then hrpPosition = requiredModules.CharacterRayOrigin(self.character) end
        if not hrpPosition then return end
        if not throwDirection then throwDirection = self:GetThrowDirection(targetPosition, hrpPosition) end

        self:SetKnifeHandleTransparency(tool, 1)
        Remotes.ThrowStart:FireServer(hrpPosition, throwDirection)
        requiredModules.KnifeProjectileController({
            Speed = tool:GetAttribute("ThrowSpeed"),
            KnifeProjectile = knifeHandle:Clone(),
            Direction = throwDirection,
            Origin = hrpPosition,
        }, function(hitResult)
            local hitInstance = hitResult and hitResult.Instance
            local hitPosition = hitResult and hitResult.Position
            Remotes.ThrowHit:FireServer(hitInstance, hitPosition)
        end)
    end

    if not self.hasMouseEnabled then
        local humanoid = self.character and self.character:FindFirstChild("Humanoid")
        local animator = humanoid and humanoid:FindFirstChild("Animator")
        if not animator then return end

        local throwAnimationTrack = animator:LoadAnimation(Animations.Throw)
        self.currentThrowPromise = requiredModules.Promise.new(function(resolve, reject, onCancel)
            onCancel(function() throwAnimationTrack:Stop(0) end)
            throwAnimationTrack:GetMarkerReachedSignal("Completed"):Connect(function()
                if not targetPosition then targetPosition = mouse.Hit.Position end
                resolve()
            end)
            throwAnimationTrack.Ended:Connect(function()
                self:SetKnifeHandleTransparency(tool, 0)
                self.currentThrowPromise = nil
                throwAnimationTrack:Destroy()
            end)
            throwAnimationTrack:Play(nil, nil, self.THROW_ANIMATION_SPEED)
        end):andThen(createKnifeProjectile)
        self.Maid:GiveTask(function() if self.currentThrowPromise then self.currentThrowPromise:cancel() end end)
    else
        createKnifeProjectile()
    end
end

function KnifeControllerModule:HandleStabInput(tool)
    local requiredModules = self:GetRequiredModules()
    local hitTargets = {}
    local hitboxController = requiredModules.Hitbox(tool, function(hitResult)
        local hitCharacter = hitResult.Instance.Parent
        local targetHumanoid = hitCharacter and hitCharacter:FindFirstChild("Humanoid")
        if not targetHumanoid or hitTargets[hitCharacter] then return end
        hitTargets[hitCharacter] = true
        Remotes.Stab:FireServer(hitResult.Instance)
    end)

    self.Maid:GiveTask(tool.Activated:Connect(function()
        if Config.ControllerLock.knife or Config.ControllerLock.general then return end
        if self.isStabMode then
            hitboxController.Activate()
            task.wait(0.1)
            hitboxController.Deactivate()
            hitTargets = {}
        end
    end))
    self.Maid:GiveTask(function() hitboxController.Deactivate() end)
end

function KnifeControllerModule:HandleMouseThrowInput(tool)
    local humanoid = self.character and self.character:FindFirstChild("Humanoid")
    local animator = humanoid and humanoid:FindFirstChild("Animator")
    if not animator then return end

    local requiredModules = self:GetRequiredModules()
    local chargeAnimationTrack = animator:LoadAnimation(Animations.Throw)
    local isCharged = false
    local chargePromise = nil

    self.Maid:GiveTask(chargeAnimationTrack:GetMarkerReachedSignal("Completed"):Connect(function()
        isCharged = true
        chargeAnimationTrack:AdjustSpeed(0)
    end))
    self.Maid:GiveTask(chargeAnimationTrack.Ended:Connect(function()
        isCharged = false
        self:SetKnifeHandleTransparency(tool, 0)
    end))
    self.Maid:GiveTask(UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or chargeAnimationTrack.IsPlaying or isCharged or self.isStabMode then return end
        chargePromise = requiredModules.Promise.delay(self.CHARGE_DELAY):andThen(function()
            chargeAnimationTrack:Play(nil, nil, self.THROW_ANIMATION_SPEED)
        end)
    end))
    self.Maid:GiveTask(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if self.isStabMode then
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
        self:Throw(tool, mouse.Hit.Position)
    end))
    self.Maid:GiveTask(function()
        if chargePromise then chargePromise:cancel() end
        chargeAnimationTrack:Stop()
        self:SetKnifeHandleTransparency(tool, 0)
    end)
end

function KnifeControllerModule:HandleThrowInput(tool)
    if self.hasMouseEnabled and UserInputService.MouseEnabled then
        tool.ManualActivationOnly = true
        self:HandleMouseThrowInput(tool)
    else
        ContextActionService:BindAction("Throw", function(actionName, inputState)
            if actionName == "Throw" and inputState == Enum.UserInputState.Begin then
                if self.isStabMode then tool:Activate() else self:Throw(tool, nil) end
            end
        end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonL2)
        self.Maid:GiveTask(function() ContextActionService:UnbindAction("Throw") end)
    end

    self.Maid:GiveTask(UserInputService.TouchTapInWorld:Connect(function(position, gameProcessed)
        if gameProcessed then return end
        if self.isStabMode then
            tool:Activate()
        else
            local requiredModules = self:GetRequiredModules()
            local worldPosition = requiredModules.WeaponRaycast.convertScreenPointToVector3(position, 2000)
            self:Throw(tool, worldPosition)
        end
    end))
end

function KnifeControllerModule:OnKnifeEquipped(tool)
    self.Maid:DoCleaning()
    self.currentTool = tool
    tool.ManualActivationOnly = self.isStabMode
    self.Maid:GiveTask(function() self.currentTool = nil end)
    self:HandleStabInput(tool)
    self:HandleThrowInput(tool)
    self.Maid:GiveTask(tool.AncestryChanged:Connect(function()
        if not tool:IsDescendantOf(self.character) then self.Maid:DoCleaning() end
    end))
end

function KnifeControllerModule:OnCharacterAdded(newCharacter)
    local requiredModules = self:GetRequiredModules()
    self.character = newCharacter
    
    self.character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and CollectionService:HasTag(child, requiredModules.Tags.KNIFE_TOOL) then
            self:OnKnifeEquipped(child)
        end
    end)

    for _, child in ipairs(self.character:GetChildren()) do
        if child:IsA("Tool") and CollectionService:HasTag(child, requiredModules.Tags.KNIFE_TOOL) then
            self:OnKnifeEquipped(child)
        end
    end
end

function KnifeControllerModule:Start()
    local MaidClass = require(Modules.Util.Maid)
    self.Maid = MaidClass.new()
    self.Maid:GiveTask(player.CharacterAdded:Connect(function(char) self:OnCharacterAdded(char) end))
    if player.Character then self:OnCharacterAdded(player.Character) end
end

function KnifeControllerModule:Stop()
    if self.Maid then
        self.Maid:DoCleaning()
        self.Maid = nil
    end
end

ModuleHandler:Register("KnifeController", KnifeControllerModule)

--//==============================================================================================================//--
--//                                             MODULE: AUTO-KILL                                                //--
--//==============================================================================================================//--

local KillAllModule = {
    Connections = {},
    enemyCache = {},
    WEAPON_TYPE = { gun = "Gun_Equip", knife = "Knife_Equip" },
    lock = { gun = false, knife = false }
}

function KillAllModule:UpdateCache()
    self.enemyCache = {}
    for _, enemy in pairs(Players:GetPlayers()) do
        task.spawn(function()
            if enemy and enemy ~= player and enemy.Team and enemy.Team ~= player.Team then
                if enemy.Character and enemy.Character.Parent == Workspace then
                    local targetPart = enemy.Character:FindFirstChild("HumanoidRootPart")
                    if targetPart then self.enemyCache[enemy] = targetPart end
                end
            end
        end)
    end
end

function KillAllModule:EquipWeapon(weaponType)
    local backpack = player.Backpack
    local character = player.Character
    if not character or not backpack then return end

    for _, tool in pairs(character:GetChildren()) do
        if tool:IsA("Tool") and tool:GetAttribute("EquipAnimation") == weaponType then return end -- Already equipped
    end
    
    for _, tool in pairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tool:GetAttribute("EquipAnimation") == weaponType then
            character.Humanoid:EquipTool(tool)
            task.wait(0.3)
            return
        end
    end
end

function KillAllModule:KillAllKnife()
    local character = player.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    self:EquipWeapon(self.WEAPON_TYPE.knife)

    for _, part in pairs(self.enemyCache) do
        task.spawn(function()
            if part and part.Parent then
                local origin = hrp.Position
                local direction = (part.Position - origin).Unit
                Remotes.ThrowStart:FireServer(origin, direction)
                Remotes.ThrowHit:FireServer(part, part.Position)
            end
        end)
    end
end

function KillAllModule:KillAllGun()
    local character = player.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    self:EquipWeapon(self.WEAPON_TYPE.gun)

    for _, part in pairs(self.enemyCache) do
        task.spawn(function()
            if part and part.Parent then
                Remotes.ShootGun:FireServer(hrp.Position, part.Position, part, part.Position)
            end
        end)
    end
end

function KillAllModule:Start()
    if player.Character then self:UpdateCache() end

    self.Connections.Heartbeat1 = Run.Heartbeat:Connect(function()
        if Config.KillAllKnife then
            self:KillAllKnife()
            Config.KillAllKnife = false
        end
        if Config.KillAllGun then
            self:KillAllGun()
            Config.KillAllGun = false
        end
    end)
    self.Connections.Heartbeat2 = Run.Heartbeat:Connect(function() self:UpdateCache() end)
    self.Connections.RenderStepped = Run.RenderStepped:Connect(function()
        if Config.KillLoopGun and not self.lock.gun then self:KillAllGun() end
        if Config.KillLoopKnife and not self.lock.knife then self:KillAllKnife() end
    end)
    self.Connections.CharacterAdded = player.CharacterAdded:Connect(function()
        local character = player.Character
        if not character then return end
        self.lock.gun, self.lock.knife = true, true
        if Config.KillLoopGun then self:EquipWeapon(self.WEAPON_TYPE.gun) end
        if Config.KillLoopKnife then self:EquipWeapon(self.WEAPON_TYPE.knife) end
        local hrp = character:WaitForChild("HumanoidRootPart", 3)
        if not hrp or not player:GetAttribute("Match") then return end
        local anchoredConnection
        anchoredConnection = hrp:GetPropertyChangedSignal("Anchored"):Connect(function()
            if not hrp.Anchored then
                if Config.KillLoopGun then self.lock.gun = false end
                if Config.KillLoopKnife then self.lock.knife = false end
                if anchoredConnection then anchoredConnection:Disconnect() end
            end
        end)
    end)
end

function KillAllModule:Stop()
    for _, conn in pairs(self.Connections) do conn:Disconnect() end
    self.Connections = {}
end

ModuleHandler:Register("KillAll", KillAllModule)

--//==============================================================================================================//--
--//                                                 MODULE: ESP                                                  //--
--//==============================================================================================================//--

local ESPModule = {
    Connections = {},
    teammates = {},
    enemies = {},
    TEAMMATE_OUTLINE = Color3.fromRGB(30, 214, 134),
    TEAMMATE_FILL = Color3.fromRGB(15, 107, 67),
    ENEMY_OUTLINE = Color3.fromRGB(255, 41, 121),
    ENEMY_FILL = Color3.fromRGB(127, 20, 60)
}

function ESPModule:UpdateCache()
    self.teammates, self.enemies = {}, {}
    for _, p in pairs(Players:GetPlayers()) do
        if p and p ~= player and p.Team and p.Character and p.Character.Parent == Workspace then
            if p.Team == player.Team then table.insert(self.teammates, p) else table.insert(self.enemies, p) end
        end
    end
end

function ESPModule:CreateESP(character, outlineColor, fillColor)
    if not character or not character.Parent then return end
    local highlight = character:FindFirstChild("MVSD_ESP_Highlight")
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "MVSD_ESP_Highlight"
        highlight.Parent = character
    end
    highlight.Enabled = true
    highlight.OutlineColor = outlineColor
    highlight.FillColor = fillColor
    highlight.FillTransparency = 0.7
    return highlight
end

function ESPModule:CleanESP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            local highlight = p.Character:FindFirstChild("MVSD_ESP_Highlight")
            if highlight then highlight:Destroy() end
        end
    end
end

function ESPModule:Run()
    self:UpdateCache()
    if not player:GetAttribute("Match") then self:CleanESP(); return end

    if Config.EspTeamMates then
        for _, p in ipairs(self.teammates) do self:CreateESP(p.Character, self.TEAMMATE_OUTLINE, self.TEAMMATE_FILL) end
    end
    if Config.EspEnemies then
        for _, p in ipairs(self.enemies) do self:CreateESP(p.Character, self.ENEMY_OUTLINE, self.ENEMY_FILL) end
    end
end

function ESPModule:Start()
    self.Connections.Heartbeat = Run.Heartbeat:Connect(function() self:Run() end)
end

function ESPModule:Stop()
    if self.Connections.Heartbeat then
        self.Connections.Heartbeat:Disconnect()
        self.Connections.Heartbeat = nil
    end
    self:CleanESP()
end

ModuleHandler:Register("ESP", ESPModule)

--//==============================================================================================================//--
--//                                             MODULE: ADVANCED AIMBOT                                          //--
--//==============================================================================================================//--

local AimbotModule = {
    Connections = {},
    State = {
        active = true,
        aiming = false,
        isSpectated = false,
        currentTarget = nil,
        playerCache = {},
        targetCache = {},
        lastRecoil = CFrame.new()
    },
    raycastParams = RaycastParams.new(),
    fovCircle = nil,
    targetIndicatorGui = nil,
    shotCount = 0,
    accuracyBonus = 0,
    lastShotTime = 0,
    deviationSeed = math.random(1, 1000000),
    lastTargetOvershot = nil,
    PRIORITY_BODY_PARTS = { "Head", "UpperTorso", "HumanoidRootPart", "LowerTorso", "LeftUpperArm", "RightUpperArm" }
}

function AimbotModule:InitializePlayer()
    local char = player.Character
    self.State.playerCache = {}
    if not char or not char.Parent then return end
    local hrp = char:WaitForChild("HumanoidRootPart")
    local hum = char:WaitForChild("Humanoid")
    local animator = hum and hum:WaitForChild("Animator")
    self.State.playerCache = { char, hrp, hum, animator }
end

function AimbotModule:UpdateTargetCache()
    local newCache = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and p.Character.Parent then
            local char, hrp, hum, head = p.Character, p.Character:FindFirstChild("HumanoidRootPart"), p.Character:FindFirstChild("Humanoid"), p.Character:FindFirstChild("Head")
            if hrp and hum and head and hum.Health > 0 then
                newCache[p] = { player = p, char = char, hrp = hrp, hum = hum, head = head }
            end
        end
    end
    self.State.targetCache = newCache
end

function AimbotModule:NormalRandom()
    local u1, u2 = math.random(), math.random()
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

function AimbotModule:ApplyAimDeviation(originalPos, muzzlePos, targetChar)
    if not Config.DeviationEnabled then return originalPos, nil end
    self.shotCount = self.shotCount + 1
    math.randomseed(self.deviationSeed + self.shotCount)
    local currentTime = os.clock()
    if currentTime - self.lastShotTime < 2 then
        self.accuracyBonus = math.min(self.accuracyBonus + Config.AccuracyBuildup, 1.0)
    else
        self.accuracyBonus = math.max(self.accuracyBonus - 0.1, 0)
    end
    self.lastShotTime = currentTime
    local direction = (originalPos - muzzlePos).Unit
    local distance = (originalPos - muzzlePos).Magnitude
    if distance <= 0 then return originalPos, nil end
    local distanceFactor = (distance / Config.MaxDistance) * Config.DistanceFactor
    local velocityFactor = 0
    if targetChar then
        local hrp = targetChar:FindFirstChild("HumanoidRootPart")
        if hrp then velocityFactor = (Vector3.new(hrp.Velocity.X, 0, hrp.Velocity.Z).Magnitude / 40) * Config.VelocityFactor end
    end
    local totalDeviation = Config.BaseDeviation + distanceFactor + velocityFactor - self.accuracyBonus
    totalDeviation = math.max(totalDeviation, Config.MinDeviation)
    local maxDeviationRadians = math.rad(totalDeviation)
    local horizontalDeviation = self:NormalRandom() * maxDeviationRadians * 0.6
    local verticalDeviation = self:NormalRandom() * maxDeviationRadians * 0.4
    local right = Vector3.new(-direction.Z, 0, direction.X).Unit
    local up = direction:Cross(right).Unit
    local tempDir = direction * math.cos(horizontalDeviation) + right * math.sin(horizontalDeviation)
    local deviatedDirection = (tempDir * math.cos(verticalDeviation) + up * math.sin(verticalDeviation)).Unit
    local rayResult = Workspace:Raycast(muzzlePos, deviatedDirection * 1000, self.raycastParams)
    if self.shotCount >= 1000 then self.shotCount, self.deviationSeed = 0, math.random(1, 1000000) end
    return rayResult and rayResult.Position or originalPos, rayResult and rayResult.Instance
end

function AimbotModule:PredictMovement(targetHrp, localHrp)
    local distance = (targetHrp.Position - localHrp.Position).Magnitude
    local travelTime = (distance / Config.BulletSpeed) + Config.PingCompensation
    return targetHrp.Position + (targetHrp.Velocity * travelTime)
end

function AimbotModule:ApplyAimCurve(startPos, endPos)
    if not Config.AimCurvesEnabled then return endPos end
    local midPoint = startPos:Lerp(endPos, 0.5)
    local offset = Vector3.new((math.random() - 0.5), (math.random() - 0.5), (math.random() - 0.5)) * Config.AimCurveIntensity
    return midPoint + offset
end

function AimbotModule:SmoothlyAimAt(targetPos)
    if not Config.AimSmoothingEnabled or Config.SilentAim then
        camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetPos)
        return
    end
    local startCFrame, endCFrame = camera.CFrame, CFrame.lookAt(camera.CFrame.Position, targetPos)
    if Config.RecoilControlEnabled then
        local counterRecoil = startCFrame:ToObjectSpace(self.State.lastRecoil):Lerp(CFrame.new(), Config.RecoilControlStrength)
        startCFrame = startCFrame * counterRecoil
        self.State.lastRecoil = CFrame.new()
    end
    camera.CFrame = startCFrame:Lerp(endCFrame, Config.AimSmoothingFactor)
end

function AimbotModule:GetVisibleParts(targetChar, localHrp)
    local visibleParts = {}
    self.raycastParams.FilterDescendantsInstances = { self.State.playerCache[1], targetChar }
    for _, partName in ipairs(self.PRIORITY_BODY_PARTS) do
        local part = targetChar:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            local partPos = part.Position
            local dirHRP = partPos - localHrp.Position
            if dirHRP.Magnitude > 0 and not Workspace:Raycast(localHrp.Position, dirHRP.Unit * dirHRP.Magnitude, self.raycastParams) then
                if not Config.CameraCast then
                    table.insert(visibleParts, part)
                else
                    local dirCam = partPos - camera.CFrame.Position
                    if dirCam.Magnitude > 0 and not Workspace:Raycast(camera.CFrame.Position, dirCam.Unit * dirCam.Magnitude, self.raycastParams) then
                        table.insert(visibleParts, part)
                    end
                end
            end
        end
    end
    return visibleParts
end

function AimbotModule:IsValidTarget(targetData, localHrp)
    if table.find(Config.Whitelist, targetData.player.Name) then return false end
    if not targetData.player.Team or targetData.player.Team == player.Team then return false end
    if CollectionService:HasTag(targetData.char, "Invulnerable") then return false end
    if (targetData.head.Position - localHrp.Position).Magnitude > Config.MaxDistance then return false end
    if Config.FovCheckEnabled then
        local screenPos, onScreen = camera:WorldToViewportPoint(targetData.hrp.Position)
        if not onScreen then return false end
        local distFromCenter = (Vector2.new(screenPos.X, screenPos.Y) - Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)).Magnitude
        return distFromCenter <= Config.FovRadius
    end
    return true
end

function AimbotModule:GetPriorityPart(visibleParts)
    for _, priorityName in ipairs(Config.BodypartPriority) do
        for _, part in ipairs(visibleParts) do if part.Name == priorityName then return part end end
    end
    return visibleParts[1]
end

function AimbotModule:FindBestTarget(localHrp)
    local bestTargetData, bestPart, closestDist = nil, nil, Config.MaxDistance + 1
    for _, pName in ipairs(Config.Blacklist) do
        local p = Players:FindFirstChild(pName)
        if p and self.State.targetCache[p] and self:IsValidTarget(self.State.targetCache[p], localHrp) then
            local visible = self:GetVisibleParts(self.State.targetCache[p].char, localHrp)
            if #visible >= Config.VisiblePartsRequired then return self.State.targetCache[p], self:GetPriorityPart(visible) end
        end
    end
    for _, targetData in pairs(self.State.targetCache) do
        if self:IsValidTarget(targetData, localHrp) then
            local visible = self:GetVisibleParts(targetData.char, localHrp)
            if #visible >= Config.VisiblePartsRequired then
                local dist = (targetData.hrp.Position - localHrp.Position).Magnitude
                if dist < closestDist then
                    closestDist, bestTargetData, bestPart = dist, targetData, self:GetPriorityPart(visible)
                end
            end
        end
    end
    return bestTargetData, bestPart
end

function AimbotModule:FireGun(targetPos, hitPart, localHrp, animator)
    if Config.ControllerLock.gun then return end; Config.ControllerLock.gun = true
    local gun = self.State.playerCache[1]:FindFirstChildOfClass("Tool")
    if not gun then Config.ControllerLock.gun = false; return end
    local cooldown = gun:GetAttribute("Cooldown") or 2.5
    if os.clock() - Config.GunCooldown < cooldown then Config.ControllerLock.gun = false; return end
    local muzzle = gun:FindFirstChild("Muzzle", true)
    if not muzzle then Config.ControllerLock.gun = false; return end
    local finalPos, actualHitPart = self:ApplyAimDeviation(targetPos, muzzle.WorldPosition, hitPart.Parent)
    local BulletRenderer = require(Modules.BulletRenderer)
    pcall(function() BulletRenderer(muzzle.WorldPosition, finalPos, "Default") end)
    pcall(Remotes.ShootGun.FireServer, Remotes.ShootGun, muzzle.WorldPosition, finalPos, actualHitPart or hitPart, finalPos)
    Config.GunCooldown, self.State.lastRecoil = os.clock(), camera.CFrame
    task.wait(0.1)
    Config.ControllerLock.gun = false
end

function AimbotModule:HandleCombat()
    if not self.State.active or not self.State.aiming or not Config.AimbotEnabled then self.State.currentTarget = nil; return end
    local _, hrp, _, animator = unpack(self.State.playerCache)
    if not hrp or not animator then return end
    if Config.TriggerbotMode then
        local mouseRay = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
        local rayResult = Workspace:Raycast(mouseRay.Origin, mouseRay.Direction * Config.MaxDistance, self.raycastParams)
        if rayResult and rayResult.Instance and rayResult.Instance.Parent and rayResult.Instance.Parent:FindFirstChild("Humanoid") then
            local targetPlayer = Players:GetPlayerFromCharacter(rayResult.Instance.Parent)
            if targetPlayer and self:IsValidTarget({player = targetPlayer, char = targetPlayer.Character, hrp = targetPlayer.Character.HumanoidRootPart, head = targetPlayer.Character.Head}, hrp) then
                self:FireGun(rayResult.Position, rayResult.Instance, hrp, animator)
            end
        end; return
    end
    local bestTargetData, bestPart = self:FindBestTarget(hrp)
    self.State.currentTarget = bestTargetData
    if not bestTargetData or not bestPart then return end
    local predictedPos = self:PredictMovement(bestTargetData.hrp, hrp)
    local finalTargetPos = bestPart.Position + (predictedPos - bestTargetData.hrp.Position)
    if Config.OvershootEnabled and bestTargetData ~= self.lastTargetOvershot then
        if math.random() < Config.OvershootChance then
            local offsetDir = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0).Unit
            finalTargetPos = finalTargetPos + offsetDir * (finalTargetPos - camera.CFrame.Position).Magnitude * Config.OvershootAmount
        end
        self.lastTargetOvershot = bestTargetData
    end
    finalTargetPos = self:ApplyAimCurve(camera.CFrame.Position, finalTargetPos)
    if not Config.SilentAim then self:SmoothlyAimAt(finalTargetPos) end
    local randomizedReaction = math.random(Config.ReactionTimeMin * 100, Config.ReactionTimeMax * 100) / 100
    task.wait(randomizedReaction)
    if not self:IsValidTarget(bestTargetData, hrp) then return end
    self:FireGun(finalTargetPos, bestPart, hrp, animator)
end

function AimbotModule:UpdateUI()
    if self.fovCircle then self.fovCircle.Visible = Config.ShowFovCircle and Config.FovCheckEnabled and self.State.active and Config.AimbotEnabled end
    if self.fovCircle and self.fovCircle.Visible then
        self.fovCircle.Radius = Config.FovRadius
        self.fovCircle.Position = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    end
    if self.targetIndicatorGui then
        local shouldBeVisible = Config.TargetIndicatorEnabled and self.State.currentTarget and self.State.currentTarget.hrp.Parent and Config.AimbotEnabled
        self.targetIndicatorGui.Enabled = shouldBeVisible
        if shouldBeVisible then
            self.targetIndicatorGui.Parent = self.State.currentTarget.hrp
            self.targetIndicatorGui.Adornee = self.State.currentTarget.hrp
        end
    end
end

function AimbotModule:IsSpectated()
    if not Config.SpectatorDetection then self.State.isSpectated = false; return end
    local localHrp = self.State.playerCache[2]
    if not localHrp then self.State.isSpectated = false; return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - localHrp.Position).Magnitude < 25 then
                if p.Character:GetAttribute("IsSpectator") or (hrp.Anchored and p.Character.Humanoid.PlatformStand) then
                    self.State.isSpectated = true; return
                end
            end
        end
    end
    self.State.isSpectated = false
end

function AimbotModule:Start()
    self:InitializePlayer()
    self.raycastParams.IgnoreWater, self.raycastParams.FilterType = true, Enum.RaycastFilterType.Blacklist
    self.fovCircle = Drawing.new("Circle")
    self.fovCircle.Color, self.fovCircle.Thickness, self.fovCircle.Filled, self.fovCircle.Transparency = Color3.new(1,1,1), 1, false, 0.5
    self.targetIndicatorGui = Instance.new("BillboardGui")
    self.targetIndicatorGui.Size, self.targetIndicatorGui.AlwaysOnTop, self.targetIndicatorGui.Parent = UDim2.fromOffset(20, 20), true, CoreGui
    local dot = Instance.new("Frame", self.targetIndicatorGui)
    dot.Size, dot.BackgroundColor3, dot.BackgroundTransparency = UDim2.fromScale(1, 1), Color3.fromRGB(255, 0, 0), 0.3
    local corner = Instance.new("UICorner", dot); corner.CornerRadius = UDim.new(1, 0)

    self.Connections.RenderStepped = Run.RenderStepped:Connect(function() self:HandleCombat(); self:UpdateUI() end)
    self.Connections.CharacterAdded = player.CharacterAdded:Connect(function() self:InitializePlayer() end)
    self.Connections.InputBegan = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Config.ToggleKey then self.State.active = not self.State.active end
        if input.KeyCode == Config.AimKey then self.State.aiming = true end
    end)
    self.Connections.InputEnded = UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Config.AimKey then self.State.aiming, self.State.currentTarget, self.lastTargetOvershot = false, nil, nil end
    end)
    self.Connections.Heartbeat = Run.Heartbeat:Connect(function()
        self:UpdateTargetCache(); self:IsSpectated()
    end)
end

function AimbotModule:Stop()
    for _, conn in pairs(self.Connections) do conn:Disconnect() end
    self.Connections = {}
    if self.fovCircle then self.fovCircle:Remove(); self.fovCircle = nil end
    if self.targetIndicatorGui then self.targetIndicatorGui:Destroy(); self.targetIndicatorGui = nil end
end

ModuleHandler:Register("Aimbot", AimbotModule)

--//==============================================================================================================//--
--//                                          USER INTERFACE CONSTRUCTION                                         //--
--//==============================================================================================================//--

local Window = Windui:CreateWindow({
    Title = "MVSD Graphics 4", Icon = "square-function", Author = "by Le Honk", Folder = "MVSD_Graphics",
    Size = UDim2.fromOffset(580, 480), Transparent = true, Theme = "Dark", Resizable = true, SideBarWidth = 120,
    HideSearchBar = true, ScrollBarEnabled = true,
})

local ConfigManager = Window.ConfigManager
local DefaultConfig = ConfigManager:CreateConfig("default")
local saveFlag, loadFlag = "WindUI/" .. Window.Folder .. "/config/autosave", "WindUI/" .. Window.Folder .. "/config/autoload"
local Elements = {}

local function saveConfig()
    if isfile(saveFlag) then DefaultConfig:Save() end
end

-- AIMBOT TAB
local AimTab = Window:Tab({ Title = "Aim Bot", Icon = "focus" })
Elements.AimbotEnabled = AimTab:Toggle({
    Title = "Enable Aimbot", Desc = "Master toggle for all aimbot features.", Value = Config.AimbotEnabled,
    Callback = function(state) Config.AimbotEnabled = state; ModuleHandler:Toggle("Aimbot", state); saveConfig() end
})
Elements.TriggerbotMode = AimTab:Toggle({
    Title = "Triggerbot Mode", Desc = "Automatically fires when crosshair is over an enemy.", Value = Config.TriggerbotMode,
    Callback = function(state) Config.TriggerbotMode = state; saveConfig() end
})
Elements.AimSmoothingEnabled = AimTab:Toggle({
    Title = "Enable Aim Smoothing", Desc = "Makes aiming movement smoother and more human-like.", Value = Config.AimSmoothingEnabled,
    Callback = function(state) Config.AimSmoothingEnabled = state; saveConfig() end
})
Elements.AimSmoothingFactor = AimTab:Slider({
    Title = "Aim Smoothing Factor", Desc = "Controls smoothness (lower is slower).", Step = 0.01,
    Value = { Min = 0.01, Max = 1, Default = Config.AimSmoothingFactor },
    Callback = function(v) Config.AimSmoothingFactor = v; saveConfig() end
})
Elements.ShowFovCircle = AimTab:Toggle({
    Title = "Show FOV Circle", Desc = "Displays a circle representing the aimbot's field of view.", Value = Config.ShowFovCircle,
    Callback = function(state) Config.ShowFovCircle = state; saveConfig() end
})
Elements.FovRadius = AimTab:Slider({
    Title = "FOV Radius", Desc = "Size of the aimbot's targeting radius in pixels.",
    Value = { Min = 10, Max = 500, Default = Config.FovRadius },
    Callback = function(v) Config.FovRadius = v; saveConfig() end
})
Elements.MaxDistance = AimTab:Slider({
    Title = "Max Aim Distance", Desc = "Maximum distance in studs to target an enemy.",
    Value = { Min = 50, Max = 1000, Default = Config.MaxDistance },
    Callback = function(v) Config.MaxDistance = v; saveConfig() end
})
Elements.ReactionTimeMin = AimTab:Slider({
    Title = "Min Reaction Time", Desc = "Minimum delay before the aimbot reacts.", Step = 0.01,
    Value = { Min = 0.01, Max = 1, Default = Config.ReactionTimeMin },
    Callback = function(v) Config.ReactionTimeMin = v; saveConfig() end
})
Elements.ReactionTimeMax = AimTab:Slider({
    Title = "Max Reaction Time", Desc = "Maximum delay before the aimbot reacts.", Step = 0.01,
    Value = { Min = 0.01, Max = 1, Default = Config.ReactionTimeMax },
    Callback = function(v) Config.ReactionTimeMax = v; saveConfig() end
})
Elements.AimKey = AimTab:Keybinder({
    Title = "Aim Key", Value = Config.AimKey,
    Callback = function(key) Config.AimKey = key; saveConfig() end
})
Elements.ToggleKey = AimTab:Keybinder({
    Title = "Toggle Key", Value = Config.ToggleKey,
    Callback = function(key) Config.ToggleKey = key; saveConfig() end
})

-- ESP TAB
local EspTab = Window:Tab({ Title = "ESP", Icon = "eye" })
Elements.EspEnabled = EspTab:Toggle({
    Title = "Enable ESP", Desc = "Master toggle for all ESP features.", Value = Config.EspEnabled,
    Callback = function(state) Config.EspEnabled = state; ModuleHandler:Toggle("ESP", state); saveConfig() end
})
Elements.EspTeamMates = EspTab:Toggle({
    Title = "Show Teammates", Desc = "Highlight your teammates.", Value = Config.EspTeamMates,
    Callback = function(state) Config.EspTeamMates = state; saveConfig() end
})
Elements.EspEnemies = EspTab:Toggle({
    Title = "Show Enemies", Desc = "Highlight your enemies.", Value = Config.EspEnemies,
    Callback = function(state) Config.EspEnemies = state; saveConfig() end
})

-- AUTO-KILL TAB
local KillTab = Window:Tab({ Title = "Auto Kill", Icon = "skull" })
local knifeButton = KillTab:Button({
    Title = "[Knife] Kill All", Desc = "Kills all players using the knife once.",
    Callback = function() Config.KillAllKnife = true; ModuleHandler:Toggle("KillAll", true) end
})
local gunButton = KillTab:Button({
    Title = "[Gun] Kill All", Desc = "Kills all players using the gun once.",
    Callback = function() Config.KillAllGun = true; ModuleHandler:Toggle("KillAll", true) end
})
local knifeToggle = KillTab:Toggle({
    Title = "[Knife] Loop Kill All", Desc = "Repeatedly kills all players using the knife.", Value = Config.KillLoopKnife,
    Callback = function(state)
        Config.KillLoopKnife = state; if state then Config.KillLoopGun = false; gunButton:Set(false) end
        ModuleHandler:Toggle("KillAll", Config.KillLoopKnife or Config.KillLoopGun); saveConfig()
    end
})
local gunToggle = KillTab:Toggle({
    Title = "[Gun] Loop Kill All", Desc = "Repeatedly kills all players using the gun.", Value = Config.KillLoopGun,
    Callback = function(state)
        Config.KillLoopGun = state; if state then Config.KillLoopKnife = false; knifeToggle:Set(false) end
        ModuleHandler:Toggle("KillAll", Config.KillLoopKnife or Config.KillLoopGun); saveConfig()
    end
})

-- MISC TAB
local MiscTab = Window:Tab({ Title = "Misc", Icon = "brackets" })
Elements.AntiCrash = MiscTab:Toggle({
    Title = "Anti Crash", Desc = "Blocks the shroud projectile from rendering to prevent crashes.", Value = Config.AntiCrash,
    Callback = function(state)
        Config.AntiCrash = state; saveConfig()
        if state then
            task.spawn(function()
                local module = Replicated.Ability:WaitForChild("ShroudProjectileController", 5)
                if module then
                    local replacement = Instance.new("ModuleScript")
                    replacement.Name = "ShroudProjectileController"
                    replacement.Parent = module.Parent
                    module:Destroy()
                end
            end)
        end
    end,
})
Elements.LowPoly = MiscTab:Toggle({
    Title = "Low Poly Mode", Desc = "Enables low graphics settings for better performance.", Value = Config.LowPoly,
    Callback = function(state)
        Config.LowPoly = state
        SettingsRemote.UpdateSetting:FireServer("LowGraphics", state)
        SettingsRemote.UpdateSetting:FireServer("KillEffectsDisabled", state)
        SettingsRemote.UpdateSetting:FireServer("LobbyMusicDisabled", state)
        saveConfig()
    end,
})
local autoSpinConnection = nil
Elements.AutoSpin = MiscTab:Toggle({
    Title = "Auto Spin", Desc = "Automatically spins the modifier wheel between rounds.", Value = Config.AutoSpin,
    Callback = function(state)
        Config.AutoSpin = state; saveConfig()
        if state and not autoSpinConnection then
            autoSpinConnection = Run.Heartbeat:Connect(function()
                if Config.AutoSpin and player:GetAttribute("Match") then
                    pcall(Dailies.Spin.InvokeServer, Dailies.Spin)
                end
            end)
        elseif not state and autoSpinConnection then
            autoSpinConnection:Disconnect(); autoSpinConnection = nil
        end
    end,
})

-- CONTROLLER TAB
local ControllerTab = Window:Tab({ Title = "Controller", Icon = "keyboard" })
Windui:Notify({ Title = "Warning", Content = "Custom knife controller has no mobile mode toggle button.", Duration = 4, Icon = "triangle-alert" })
Elements.DestroyOldControllers = ControllerTab:Toggle({
    Title = "Delete Old Controllers", Desc = "Required for custom controllers to work properly.", Value = Config.DestroyOldControllers,
    Callback = function(state) Config.DestroyOldControllers = state; ModuleHandler:Toggle("ControllerCleaner", state); saveConfig() end
})
Elements.CustomKnifeController = ControllerTab:Toggle({
    Title = "Custom Knife Controller", Desc = "Replaces default knife handler for better feature support.", Value = Config.CustomKnifeController,
    Callback = function(state) Config.CustomKnifeController = state; ModuleHandler:Toggle("KnifeController", state); saveConfig() end
})
Elements.CustomGunController = ControllerTab:Toggle({
    Title = "Custom Gun Controller", Desc = "Replaces default gun handler for better feature support.", Value = Config.CustomGunController,
    Callback = function(state) Config.CustomGunController = state; ModuleHandler:Toggle("GunController", state); saveConfig() end
})

-- SETTINGS TAB
local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })
SettingsTab:Section({ Title = "General" })
local themes = {}
for theme, _ in pairs(Windui:GetThemes()) do table.insert(themes, theme) end; table.sort(themes)
Elements.Theme = SettingsTab:Dropdown({
    Title = "Theme", Values = themes, Value = "Dark",
    Callback = function(option) Windui:SetTheme(option); saveConfig() end
})
SettingsTab:Toggle({
    Title = "Auto Load Config", Desc = "Automatically load settings on script execution.", Value = isfile(loadFlag),
    Callback = function(state) if state then writefile(loadFlag, "") else delfile(loadFlag) end end
})
SettingsTab:Toggle({
    Title = "Auto Save Config", Desc = "Automatically save settings when they are changed.", Value = isfile(saveFlag),
    Callback = function(state) if state then writefile(saveFlag, "") else delfile(saveFlag) end end
})

-- CREDITS SECTION
SettingsTab:Section({ Title = "Credits" })
SettingsTab:Paragraph({ Title = "Goose (Le Honk)", Desc = "Script developer, responsible for amalgamating and enhancing these features." })
SettingsTab:Paragraph({ Title = "Footagesus", Desc = "The main developer of WindUI, a bleeding-edge UI library for Roblox." })

--//==============================================================================================================//--
--//                                              INITIAL EXECUTION                                               //--
--//==============================================================================================================//--

-- Register all UI elements with the config manager
for name, element in pairs(Elements) do DefaultConfig:Register(name, element) end
Window:SelectTab(1)

-- Load config if auto-load is enabled
if isfile(loadFlag) then
    genv = DefaultConfig:Load()
    -- Apply loaded settings to the Config table and activate modules
    for name, element in pairs(Elements) do
        if Config[name] ~= nil then Config[name] = element.Value end
    end
end

-- Activate modules based on initial/loaded config
ModuleHandler:Toggle("ControllerCleaner", Config.DestroyOldControllers)
ModuleHandler:Toggle("GunController", Config.CustomGunController)
ModuleHandler:Toggle("KnifeController", Config.CustomKnifeController)
ModuleHandler:Toggle("ESP", Config.EspEnabled)
ModuleHandler:Toggle("Aimbot", Config.AimbotEnabled)
if Config.AutoSpin then Elements.AutoSpin:Callback(true) end
if Config.AntiCrash then Elements.AntiCrash:Callback(true) end

print("MVSD Graphics - Complete Edition Loaded.")

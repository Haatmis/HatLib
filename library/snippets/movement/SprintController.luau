--[[
	SprintController — sprint côté client, avec effets optionnels.
	Clavier / manette / bouton tactile, FOV, animation, endurance.
	Placement : src/client/controllers/ (ModuleScript `require`) ou StarterPlayerScripts (LocalScript).
	Tout ce qui se règle est dans le bloc CONFIG ci-dessous — le reste n'a pas besoin d'être touché.

	L'endurance n'appartient pas au sprint : c'est une ressource du joueur, tenue par
	StaminaService (maximum, régénération, affichage). Le sprint ne décide que de ce
	qu'il coûte. Cocher l'option pose le service dans le projet s'il n'y est pas encore.
]]

-- ⚙️ CONFIG
-- 🎬 APERÇU: movement/sprint
-- ▸ Base
local SPRINT_KEY = Enum.KeyCode.LeftShift -- touche de sprint au clavier
local SPRINT_MODE = "Hold" -- maintien ou bascule, options: Hold|Toggle
local WALK_SPEED = 16 -- vitesse de marche, 4..40
local SPRINT_SPEED = 24 -- vitesse en sprint, 8..80
local SPEED_TWEEN_TIME = 0.25 -- durée de l'accélération en secondes, 0..1
-- ▸ Caméra
local ENABLE_FOV = true -- élargit le champ de vision pendant le sprint
local FOV_BOOST = 12 -- degrés de FOV ajoutés, si: ENABLE_FOV, 0..40
local FOV_TWEEN_TIME = 0.3 -- durée de la transition de FOV, si: ENABLE_FOV, 0..2
-- ▸ Animation
local ENABLE_ANIMATION = false -- joue une animation de course personnalisée
local ANIMATION_ID = "rbxassetid://0" -- id de l'animation de course, si: ENABLE_ANIMATION
local ANIMATION_SPEED = 1 -- vitesse de lecture de l'animation, si: ENABLE_ANIMATION, 0.1..3
-- ▸ Endurance
local ENABLE_STAMINA = false -- le sprint dépense l'endurance du joueur, requiert: systems/StaminaService.luau
local STAMINA_COST = 20 -- dépense par seconde de sprint, si: ENABLE_STAMINA, 1..100
local STAMINA_MIN_TO_START = 5 -- endurance minimale pour relancer un sprint, si: ENABLE_STAMINA, 0..50
local DRAIN_ONLY_WHEN_MOVING = true -- ne dépense pas à l'arrêt, si: ENABLE_STAMINA
-- ▸ Entrées
local ENABLE_MOBILE_BUTTON = true -- bouton tactile automatique sur mobile
local ENABLE_GAMEPAD = true -- support manette
local GAMEPAD_KEY = Enum.KeyCode.ButtonL3 -- bouton de sprint à la manette, si: ENABLE_GAMEPAD
-- ⚙️ FIN CONFIG

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ACTION_NAME = "HatLibSprint"
local DRAIN_REASON = "Sprint"

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local humanoid: Humanoid? = nil
local sprintTrack: AnimationTrack? = nil
local sprinting = false
local held = false
local baseFov = camera and camera.FieldOfView or 70
local speedTween: Tween? = nil
local fovTween: Tween? = nil
local Stamina = nil

-- ------------------------------------------------------------- endurance
-- La ressource est partagée : on retrouve le service où qu'il soit rangé dans
-- ReplicatedStorage, plutôt que d'imposer un nom de dossier.
local function findStamina()
	for _ = 1, 50 do
		local found = ReplicatedStorage:FindFirstChild("StaminaService", true)
		if found and found:IsA("ModuleScript") then
			return require(found)
		end
		task.wait(0.2)
	end
	warn("[Sprint] ENABLE_STAMINA est actif mais StaminaService est introuvable dans ReplicatedStorage.")
	return nil
end

local function hasStaminaToStart(): boolean
	if not Stamina then return true end
	return Stamina.Get() >= STAMINA_MIN_TO_START
end

local function setDrain(on: boolean)
	if not Stamina then return end
	Stamina.SetDrain(DRAIN_REASON, on and STAMINA_COST or 0)
end

-- ------------------------------------------------------------------ effets

local function setWalkSpeed(target: number)
	local h = humanoid
	if not h then return end
	if speedTween then speedTween:Cancel() end
	if SPEED_TWEEN_TIME <= 0 then
		h.WalkSpeed = target
		return
	end
	local tween = TweenService:Create(h, TweenInfo.new(SPEED_TWEEN_TIME, Enum.EasingStyle.Quad), { WalkSpeed = target })
	speedTween = tween
	tween:Play()
end

local function setFov(on: boolean)
	if not ENABLE_FOV then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	if fovTween then fovTween:Cancel() end
	local target = on and (baseFov + FOV_BOOST) or baseFov
	if FOV_TWEEN_TIME <= 0 then
		cam.FieldOfView = target
		return
	end
	local tween = TweenService:Create(cam, TweenInfo.new(FOV_TWEEN_TIME, Enum.EasingStyle.Quad), { FieldOfView = target })
	fovTween = tween
	tween:Play()
end

local function setAnimation(on: boolean)
	local track = sprintTrack
	if not ENABLE_ANIMATION or not track then return end
	if on then
		track:Play(0.15)
		track:AdjustSpeed(ANIMATION_SPEED)
	else
		track:Stop(0.15)
	end
end

-- ------------------------------------------------------------- état sprint

local function setSprinting(on: boolean)
	if on == sprinting then return end
	if on and ENABLE_STAMINA and not hasStaminaToStart() then return end
	sprinting = on
	setWalkSpeed(on and SPRINT_SPEED or WALK_SPEED)
	setFov(on)
	setAnimation(on)
	if not on then
		setDrain(false)
	end
end

local function onAction(_action: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		held = true
		if SPRINT_MODE == "Toggle" then
			setSprinting(not sprinting)
		else
			setSprinting(true)
		end
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		held = false
		if SPRINT_MODE ~= "Toggle" then
			setSprinting(false)
		end
	end
	return Enum.ContextActionResult.Pass
end

-- ----------------------------------------------------------- cycle de vie

local function loadSprintAnimation(h: Humanoid)
	sprintTrack = nil
	if not ENABLE_ANIMATION or ANIMATION_ID == "" or ANIMATION_ID:match("//0$") then return end

	local animator = h:FindFirstChildOfClass("Animator") or h:WaitForChild("Animator", 5)
	if not animator then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = ANIMATION_ID
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Movement
		track.Looped = true
		sprintTrack = track
	else
		warn("[Sprint] animation introuvable : " .. ANIMATION_ID)
	end
end

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid") :: Humanoid
	humanoid = h
	sprinting = false
	held = false
	setDrain(false)

	h.WalkSpeed = WALK_SPEED
	setFov(false)
	loadSprintAnimation(h)

	h.Died:Connect(function()
		setSprinting(false)
	end)
end

if ENABLE_STAMINA then
	task.spawn(function()
		Stamina = findStamina()
	end)
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)

local inputs = { SPRINT_KEY }
if ENABLE_GAMEPAD then
	table.insert(inputs, GAMEPAD_KEY)
end
ContextActionService:BindAction(ACTION_NAME, onAction, ENABLE_MOBILE_BUTTON, table.unpack(inputs))
if ENABLE_MOBILE_BUTTON then
	ContextActionService:SetTitle(ACTION_NAME, "Sprint")
end

if ENABLE_STAMINA then
	RunService.Heartbeat:Connect(function()
		local h = humanoid
		if not Stamina then return end
		if not h or h.Health <= 0 then
			setDrain(false)
			return
		end

		local moving = (not DRAIN_ONLY_WHEN_MOVING) or h.MoveDirection.Magnitude > 0.1
		setDrain(sprinting and moving)

		if sprinting and Stamina.Get() <= 0 then
			setSprinting(false)
		elseif held and SPRINT_MODE ~= "Toggle" and not sprinting and hasStaminaToStart() then
			-- en mode maintien, on repart dès que la jauge le permet
			setSprinting(true)
		end
	end)
end

return true

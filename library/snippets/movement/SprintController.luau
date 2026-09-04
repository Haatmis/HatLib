--[[
	SprintController — sprint côté client, avec effets optionnels.
	Clavier / manette / bouton tactile, FOV, animation, endurance + barre.
	Placement : src/client/controllers/ (ModuleScript `require`) ou StarterPlayerScripts (LocalScript).
	Tout ce qui se règle est dans le bloc CONFIG ci-dessous — le reste n'a pas besoin d'être touché.
]]

-- ⚙️ CONFIG
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
local ENABLE_STAMINA = false -- le sprint consomme une jauge d'endurance
local STAMINA_MAX = 100 -- endurance maximale, si: ENABLE_STAMINA, 10..300
local STAMINA_DRAIN = 20 -- consommation par seconde, si: ENABLE_STAMINA, 1..100
local STAMINA_REGEN = 15 -- récupération par seconde, si: ENABLE_STAMINA, 1..100
local STAMINA_REGEN_DELAY = 1 -- délai avant récupération en secondes, si: ENABLE_STAMINA, 0..5
local STAMINA_MIN_TO_START = 5 -- minimum requis pour relancer un sprint, si: ENABLE_STAMINA, 0..50
local DRAIN_ONLY_WHEN_MOVING = true -- ne consomme pas à l'arrêt, si: ENABLE_STAMINA
local ENABLE_STAMINA_BAR = true -- affiche une barre d'endurance à l'écran, si: ENABLE_STAMINA
local STAMINA_BAR_COLOR = "#5B8CFF" -- couleur de la barre, si: ENABLE_STAMINA_BAR
-- ▸ Entrées
local ENABLE_MOBILE_BUTTON = true -- bouton tactile automatique sur mobile
local ENABLE_GAMEPAD = true -- support manette
local GAMEPAD_KEY = Enum.KeyCode.ButtonL3 -- bouton de sprint à la manette, si: ENABLE_GAMEPAD
-- ⚙️ FIN CONFIG

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ACTION_NAME = "HatLibSprint"

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local humanoid: Humanoid? = nil
local sprintTrack: AnimationTrack? = nil
local sprinting = false
local held = false
local stamina = STAMINA_MAX
local timeSinceDrain = math.huge
local baseFov = camera and camera.FieldOfView or 70
local speedTween: Tween? = nil
local fovTween: Tween? = nil
local barRoot: Frame? = nil
local barFill: Frame? = nil

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

-- -------------------------------------------------------- barre d'endurance

local function ensureBar()
	if not (ENABLE_STAMINA and ENABLE_STAMINA_BAR) or barFill then return end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local gui = playerGui:FindFirstChild("HatLibSprintGui")
	if not gui then
		local screen = Instance.new("ScreenGui")
		screen.Name = "HatLibSprintGui"
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.Parent = playerGui
		gui = screen
	end

	local root = Instance.new("Frame")
	root.Name = "StaminaBar"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -14)
	root.Size = UDim2.new(0, 220, 0, 10)
	root.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	root.BackgroundTransparency = 0.55
	root.BorderSizePixel = 0
	root.Parent = gui
	Instance.new("UICorner").Parent = root

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromHex(STAMINA_BAR_COLOR)
	fill.BorderSizePixel = 0
	fill.Parent = root
	Instance.new("UICorner").Parent = fill

	barRoot, barFill = root, fill
end

local function updateBar()
	local root, fill = barRoot, barFill
	if not root or not fill then return end
	local ratio = math.clamp(stamina / STAMINA_MAX, 0, 1)
	fill.Size = UDim2.fromScale(ratio, 1)
	root.Visible = sprinting or ratio < 0.999
end

-- ------------------------------------------------------------- état sprint

local function setSprinting(on: boolean)
	if on == sprinting then return end
	if on and ENABLE_STAMINA and stamina < STAMINA_MIN_TO_START then return end
	sprinting = on
	setWalkSpeed(on and SPRINT_SPEED or WALK_SPEED)
	setFov(on)
	setAnimation(on)
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
	stamina = STAMINA_MAX
	timeSinceDrain = math.huge

	h.WalkSpeed = WALK_SPEED
	setFov(false)
	loadSprintAnimation(h)
	ensureBar()
	updateBar()

	h.Died:Connect(function()
		setSprinting(false)
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
	RunService.Heartbeat:Connect(function(dt: number)
		local h = humanoid
		if not h or h.Health <= 0 then return end

		local moving = (not DRAIN_ONLY_WHEN_MOVING) or h.MoveDirection.Magnitude > 0.1
		if sprinting and moving then
			stamina = math.max(0, stamina - STAMINA_DRAIN * dt)
			timeSinceDrain = 0
			if stamina <= 0 then
				setSprinting(false)
			end
		else
			timeSinceDrain += dt
			if timeSinceDrain >= STAMINA_REGEN_DELAY and stamina < STAMINA_MAX then
				stamina = math.min(STAMINA_MAX, stamina + STAMINA_REGEN * dt)
			end
			-- en mode maintien, on repart automatiquement dès que la jauge le permet
			if held and SPRINT_MODE ~= "Toggle" and not sprinting and stamina >= STAMINA_MIN_TO_START then
				setSprinting(true)
			end
		end
		updateBar()
	end)
end

return true

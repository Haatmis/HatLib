--[[
	DashController — ruée directionnelle avec temps de recharge.
	Clavier / manette / bouton tactile, traînée, coup de FOV, son.
	Placement : src/client/controllers/ (ModuleScript `require`) ou StarterPlayerScripts (LocalScript).
]]

-- ⚙️ CONFIG
-- ▸ Base
local DASH_KEY = Enum.KeyCode.Q -- touche de dash au clavier
local DASH_DIRECTION = "Deplacement" -- d'où vient la direction, options: Deplacement|Camera
local DASH_SPEED = 80 -- vitesse pendant la ruée, 20..200
local DASH_DURATION = 0.2 -- durée de la ruée en secondes, 0.05..0.8
local DASH_COOLDOWN = 1.5 -- temps de recharge en secondes, 0..10
local DASH_IN_AIR = true -- autorise le dash pendant un saut ou une chute
local CANCEL_VERTICAL_SPEED = true -- coupe la chute au départ de la ruée (ruée bien horizontale)
-- ▸ Caméra
local ENABLE_FOV = true -- coup de zoom arrière pendant la ruée
local FOV_BOOST = 15 -- degrés de FOV ajoutés, si: ENABLE_FOV, 0..40
local FOV_TWEEN_TIME = 0.15 -- durée de la transition, si: ENABLE_FOV, 0..1
-- ▸ Traînée
local ENABLE_TRAIL = true -- laisse une traînée derrière le personnage
local TRAIL_COLOR = "#7FD4FF" -- couleur de la traînée, si: ENABLE_TRAIL
local TRAIL_LIFETIME = 0.35 -- persistance de la traînée en secondes, si: ENABLE_TRAIL, 0.1..1.5
local TRAIL_WIDTH = 2 -- largeur de la traînée, si: ENABLE_TRAIL, 0.5..6
-- ▸ Son
local ENABLE_SOUND = false -- joue un son au départ de la ruée
local SOUND_ID = "rbxassetid://0" -- id du son, si: ENABLE_SOUND
local SOUND_VOLUME = 0.5 -- volume du son, si: ENABLE_SOUND, 0..1
-- ▸ Entrées
local ENABLE_MOBILE_BUTTON = true -- bouton tactile automatique sur mobile
local ENABLE_GAMEPAD = true -- support manette
local GAMEPAD_KEY = Enum.KeyCode.ButtonL1 -- bouton de dash à la manette, si: ENABLE_GAMEPAD
-- ⚙️ FIN CONFIG

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ACTION_NAME = "HatLibDash"

local player = Players.LocalPlayer

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local dashSound: Sound? = nil
local trail: Trail? = nil
local dashing = false
local lastDash = -math.huge
local baseFov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
local fovTween: Tween? = nil

-- ------------------------------------------------------------------ effets

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

local function buildTrail(root: BasePart)
	trail = nil
	if not ENABLE_TRAIL then return end

	local a0 = Instance.new("Attachment")
	a0.Name = "DashTrailA0"
	a0.Position = Vector3.new(0, TRAIL_WIDTH / 2, 0)
	a0.Parent = root

	local a1 = Instance.new("Attachment")
	a1.Name = "DashTrailA1"
	a1.Position = Vector3.new(0, -TRAIL_WIDTH / 2, 0)
	a1.Parent = root

	local t = Instance.new("Trail")
	t.Name = "DashTrail"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = TRAIL_LIFETIME
	t.Color = ColorSequence.new(Color3.fromHex(TRAIL_COLOR))
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	t.LightEmission = 0.5
	t.Enabled = false
	t.Parent = root
	trail = t
end

local function loadSound(root: BasePart)
	dashSound = nil
	if not ENABLE_SOUND or SOUND_ID == "" or SOUND_ID:match("//0$") then return end

	local sound = Instance.new("Sound")
	sound.Name = "DashSound"
	sound.SoundId = SOUND_ID
	sound.Volume = SOUND_VOLUME
	sound.Parent = root
	dashSound = sound
end

-- -------------------------------------------------------------------- dash

local function getDirection(): Vector3
	local root = rootPart
	local h = humanoid
	if not root then return Vector3.zero end

	local dir: Vector3
	if DASH_DIRECTION == "Camera" then
		local cam = workspace.CurrentCamera
		dir = cam and cam.CFrame.LookVector or root.CFrame.LookVector
	else
		dir = h and h.MoveDirection or Vector3.zero
		if dir.Magnitude < 0.1 then
			dir = root.CFrame.LookVector -- immobile : on fonce droit devant
		end
	end

	dir = Vector3.new(dir.X, 0, dir.Z)
	return dir.Magnitude > 0 and dir.Unit or root.CFrame.LookVector
end

local function dash()
	local root = rootPart
	local h = humanoid
	if dashing or not root or not h or h.Health <= 0 then return end
	if os.clock() - lastDash < DASH_COOLDOWN then return end
	if not DASH_IN_AIR and h.FloorMaterial == Enum.Material.Air then return end

	dashing = true
	lastDash = os.clock()

	if CANCEL_VERTICAL_SPEED then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
	end

	local direction = getDirection()

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root

	local mover = Instance.new("LinearVelocity")
	mover.Name = "DashVelocity"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	-- force nulle sur l'axe Y : la gravité continue de s'appliquer normalement
	mover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	mover.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
	mover.VectorVelocity = direction * DASH_SPEED
	mover.Parent = root

	if trail then trail.Enabled = true end
	if dashSound then dashSound:Play() end
	setFov(true)

	Debris:AddItem(mover, DASH_DURATION)
	Debris:AddItem(attachment, DASH_DURATION)

	task.delay(DASH_DURATION, function()
		dashing = false
		if trail then trail.Enabled = false end
		setFov(false)
	end)
end

local function onAction(_action: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		dash()
	end
	return Enum.ContextActionResult.Pass
end

-- ------------------------------------------------------------ cycle de vie

local function onCharacter(character: Model)
	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	rootPart = root
	dashing = false
	lastDash = -math.huge

	buildTrail(root)
	loadSound(root)
	setFov(false)
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)

local inputs = { DASH_KEY }
if ENABLE_GAMEPAD then
	table.insert(inputs, GAMEPAD_KEY)
end
ContextActionService:BindAction(ACTION_NAME, onAction, ENABLE_MOBILE_BUTTON, table.unpack(inputs))
if ENABLE_MOBILE_BUTTON then
	ContextActionService:SetTitle(ACTION_NAME, "Dash")
end

return true

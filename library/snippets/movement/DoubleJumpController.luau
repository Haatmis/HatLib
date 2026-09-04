--[[
	DoubleJumpController — sauts supplémentaires en l'air (double saut, triple...).
	Marche clavier, manette et mobile sans réglage : il écoute la *demande de saut*,
	pas une touche précise.
	Placement : src/client/controllers/ (ModuleScript `require`) ou StarterPlayerScripts (LocalScript).
]]

-- ⚙️ CONFIG
-- ▸ Base
local MAX_JUMPS = 2 -- nombre total de sauts, celui du sol compris, 1..5
local EXTRA_JUMP_POWER = 50 -- puissance des sauts en l'air, 20..120
local RESET_FALL_SPEED = true -- annule la vitesse de chute avant le saut en l'air (bien plus fiable)
local FALL_COUNTS_AS_JUMP = false -- tomber d'un rebord consomme le saut du sol
local INPUT_COOLDOWN = 0.15 -- délai minimum entre deux sauts en secondes, 0.05..0.6
-- ▸ Effets
local ENABLE_PUFF = true -- petit anneau au sol virtuel sous les pieds à chaque saut en l'air
local PUFF_COLOR = "#FFFFFF" -- couleur de l'anneau, si: ENABLE_PUFF
local PUFF_SIZE = 4 -- diamètre final de l'anneau, si: ENABLE_PUFF, 1..12
local ENABLE_ANIMATION = false -- joue une animation au saut en l'air
local ANIMATION_ID = "rbxassetid://0" -- id de l'animation, si: ENABLE_ANIMATION
local ENABLE_SOUND = false -- joue un son au saut en l'air
local SOUND_ID = "rbxassetid://0" -- id du son, si: ENABLE_SOUND
local SOUND_VOLUME = 0.5 -- volume du son, si: ENABLE_SOUND, 0..1
-- ⚙️ FIN CONFIG

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local jumpTrack: AnimationTrack? = nil
local jumpSound: Sound? = nil
local jumpsUsed = 0
local lastJump = 0

-- ------------------------------------------------------------------ effets

local function playPuff()
	local root = rootPart
	if not ENABLE_PUFF or not root then return end

	local ring = Instance.new("Part")
	ring.Name = "DoubleJumpPuff"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, 1, 1)
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromHex(PUFF_COLOR)
	ring.Transparency = 0.35
	ring.Parent = workspace

	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, PUFF_SIZE, PUFF_SIZE),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.5)
end

local function playEffects()
	playPuff()
	if jumpTrack then
		jumpTrack:Stop(0)
		jumpTrack:Play(0.05)
	end
	if jumpSound then
		jumpSound:Play()
	end
end

-- ------------------------------------------------------------------- saut

local function doAirJump()
	local root = rootPart
	if not root then return end

	local v = root.AssemblyLinearVelocity
	local newY = EXTRA_JUMP_POWER
	if not RESET_FALL_SPEED then
		newY = math.max(v.Y, EXTRA_JUMP_POWER)
	end
	root.AssemblyLinearVelocity = Vector3.new(v.X, newY, v.Z)

	jumpsUsed += 1
	lastJump = os.clock()
	playEffects()
end

local function onJumpRequest()
	local h = humanoid
	if not h or h.Health <= 0 then return end
	if os.clock() - lastJump < INPUT_COOLDOWN then return end

	local state = h:GetState()
	if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
		return -- au sol : le moteur gère le saut normal
	end
	if jumpsUsed < MAX_JUMPS - 1 then
		doAirJump()
	end
end

-- ------------------------------------------------------------ cycle de vie

local function loadAnimation(h: Humanoid)
	jumpTrack = nil
	if not ENABLE_ANIMATION or ANIMATION_ID == "" or ANIMATION_ID:match("//0$") then return end

	local animator = h:FindFirstChildOfClass("Animator") or h:WaitForChild("Animator", 5)
	if not animator then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = ANIMATION_ID
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		jumpTrack = track
	else
		warn("[DoubleJump] animation introuvable : " .. ANIMATION_ID)
	end
end

local function loadSound(root: BasePart)
	jumpSound = nil
	if not ENABLE_SOUND or SOUND_ID == "" or SOUND_ID:match("//0$") then return end

	local sound = Instance.new("Sound")
	sound.Name = "DoubleJumpSound"
	sound.SoundId = SOUND_ID
	sound.Volume = SOUND_VOLUME
	sound.Parent = root
	jumpSound = sound
end

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid") :: Humanoid
	humanoid = h
	rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	jumpsUsed = 0
	lastJump = 0

	loadAnimation(h)
	loadSound(rootPart :: BasePart)

	h.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Jumping then
			-- le saut du sol consomme le premier crédit
			jumpsUsed = math.max(jumpsUsed, 1)
		elseif new == Enum.HumanoidStateType.Freefall then
			if FALL_COUNTS_AS_JUMP then
				jumpsUsed = math.max(jumpsUsed, 1)
			end
		elseif
			new == Enum.HumanoidStateType.Landed
			or new == Enum.HumanoidStateType.Running
			or new == Enum.HumanoidStateType.Climbing
			or new == Enum.HumanoidStateType.Seated
		then
			jumpsUsed = 0
		end
	end)
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)

UserInputService.JumpRequest:Connect(onJumpRequest)

return true

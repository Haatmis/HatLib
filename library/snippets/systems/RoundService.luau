--[[
	RoundService — boucle de manches : entracte → manche → fin, en boucle.
	Téléporte les joueurs aux spawns de manche, publie l'état et le compte à rebours
	pour que l'UI cliente les lise, et expose deux événements pour brancher ta logique.

	Placement : src/server/RoundService.luau (ModuleScript), chargé depuis un Script serveur :
		local Round = require(script.Parent.RoundService)
		Round.RoundStarted.Event:Connect(function(players) ... end)
		Round.RoundEnded.Event:Connect(function(reason) ... end)

	Retourne son API (pas `true`) : RoundStarted, RoundEnded, GetState, StopRound.
]]

-- ⚙️ CONFIG
-- ▸ Rythme
local INTERMISSION_TIME = 15 -- durée de l'entracte en secondes, 5..120
local ROUND_TIME = 120 -- durée d'une manche en secondes, 15..600
local MIN_PLAYERS = 2 -- joueurs nécessaires pour lancer une manche, 1..20
local END_ROUND_WHEN_EMPTY = true -- coupe la manche s'il ne reste plus assez de joueurs
-- ▸ Spawns
local ENABLE_TELEPORT = true -- téléporte les joueurs au début de la manche
local SPAWN_FOLDER = "RoundSpawns" -- dossier de spawns dans Workspace, si: ENABLE_TELEPORT
local TELEPORT_HEIGHT = 4 -- hauteur au-dessus du spawn, si: ENABLE_TELEPORT, 0..20
local SHUFFLE_SPAWNS = true -- répartit les joueurs au hasard, si: ENABLE_TELEPORT
-- ▸ Communication vers le client
local ENABLE_STATUS_VALUE = true -- publie l'état dans ReplicatedStorage (StringValue)
local STATUS_VALUE_NAME = "RoundStatus" -- nom de la valeur d'état, si: ENABLE_STATUS_VALUE
local ENABLE_TIMER_VALUE = true -- publie le temps restant dans ReplicatedStorage (IntValue)
local TIMER_VALUE_NAME = "RoundTimer" -- nom de la valeur de temps, si: ENABLE_TIMER_VALUE
-- ▸ Textes d'état
local TEXT_WAITING = "En attente de joueurs..." -- état affiché quand il manque du monde
local TEXT_INTERMISSION = "Prochaine manche dans" -- état affiché pendant l'entracte
local TEXT_ROUND = "Manche en cours" -- état affiché pendant la manche
-- ▸ Fin de manche
local RESPAWN_ON_END = false -- fait réapparaître tout le monde à la fin de la manche
-- ⚙️ FIN CONFIG

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Round = {}
Round.RoundStarted = Instance.new("BindableEvent") -- (joueurs: {Player})
Round.RoundEnded = Instance.new("BindableEvent") -- (raison: "temps" | "joueurs" | "arret")

local state = "waiting" -- waiting | intermission | round
local roundRunning = false
local stopReason: string? = nil

-- ------------------------------------------------- valeurs partagées client

local statusValue: StringValue? = nil
local timerValue: IntValue? = nil

if ENABLE_STATUS_VALUE then
	local existing = ReplicatedStorage:FindFirstChild(STATUS_VALUE_NAME)
	if existing and existing:IsA("StringValue") then
		statusValue = existing
	else
		local v = Instance.new("StringValue")
		v.Name = STATUS_VALUE_NAME
		v.Value = TEXT_WAITING
		v.Parent = ReplicatedStorage
		statusValue = v
	end
end

if ENABLE_TIMER_VALUE then
	local existing = ReplicatedStorage:FindFirstChild(TIMER_VALUE_NAME)
	if existing and existing:IsA("IntValue") then
		timerValue = existing
	else
		local v = Instance.new("IntValue")
		v.Name = TIMER_VALUE_NAME
		v.Value = 0
		v.Parent = ReplicatedStorage
		timerValue = v
	end
end

local function setStatus(text: string)
	if statusValue then
		statusValue.Value = text
	end
end

local function setTimer(seconds: number)
	if timerValue then
		timerValue.Value = math.max(0, math.floor(seconds))
	end
end

-- ---------------------------------------------------------------- spawns

local function getSpawns(): { BasePart }
	local folder = workspace:FindFirstChild(SPAWN_FOLDER)
	if not folder then return {} end

	local spawns = {}
	for _, child in ipairs(folder:GetDescendants()) do
		if child:IsA("BasePart") then
			table.insert(spawns, child)
		end
	end
	return spawns
end

local function teleportPlayers(players: { Player })
	if not ENABLE_TELEPORT then return end

	local spawns = getSpawns()
	if #spawns == 0 then
		warn(("[Round] aucun spawn trouvé dans workspace.%s — téléportation ignorée."):format(SPAWN_FOLDER))
		return
	end

	if SHUFFLE_SPAWNS then
		for i = #spawns, 2, -1 do
			local j = math.random(i)
			spawns[i], spawns[j] = spawns[j], spawns[i]
		end
	end

	for index, player in ipairs(players) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local target = spawns[((index - 1) % #spawns) + 1]
			root.CFrame = target.CFrame + Vector3.new(0, TELEPORT_HEIGHT, 0)
		end
	end
end

-- ------------------------------------------------------------ boucle

local function alivePlayers(): { Player }
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end
	return list
end

local function countdown(seconds: number, statusText: string, duringRound: boolean): string?
	setStatus(statusText)
	local remaining = seconds
	while remaining > 0 do
		setTimer(remaining)
		task.wait(1)
		remaining -= 1

		if stopReason then
			local reason = stopReason
			stopReason = nil
			return reason
		end
		if duringRound and END_ROUND_WHEN_EMPTY and #alivePlayers() < MIN_PLAYERS then
			return "joueurs"
		end
		if not duringRound and #Players:GetPlayers() < MIN_PLAYERS then
			return "joueurs"
		end
	end
	setTimer(0)
	return nil
end

local function waitForPlayers()
	state = "waiting"
	setStatus(TEXT_WAITING)
	setTimer(0)
	while #Players:GetPlayers() < MIN_PLAYERS do
		task.wait(1)
	end
end

local function runOnce()
	waitForPlayers()

	state = "intermission"
	if countdown(INTERMISSION_TIME, TEXT_INTERMISSION, false) then
		return -- pas assez de monde : on repart en attente
	end

	local participants = alivePlayers()
	if #participants < MIN_PLAYERS then
		return
	end

	state = "round"
	roundRunning = true
	teleportPlayers(participants)
	Round.RoundStarted:Fire(participants)

	local reason = countdown(ROUND_TIME, TEXT_ROUND, true) or "temps"

	roundRunning = false
	state = "waiting"
	Round.RoundEnded:Fire(reason)

	if RESPAWN_ON_END then
		for _, player in ipairs(Players:GetPlayers()) do
			player:LoadCharacter()
		end
	end
end

-- ------------------------------------------------------------------- API

function Round.GetState(): string
	return state
end

function Round.IsRunning(): boolean
	return roundRunning
end

-- Coupe la manche en cours (fin anticipée décidée par ta logique de jeu).
function Round.StopRound(reason: string?)
	if roundRunning then
		stopReason = reason or "arret"
	end
end

task.spawn(function()
	while true do
		local ok, err = pcall(runOnce)
		if not ok then
			warn("[Round] erreur dans la boucle de manche : " .. tostring(err))
			roundRunning = false
			state = "waiting"
			task.wait(3)
		end
		task.wait(1)
	end
end)

return Round

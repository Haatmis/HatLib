--[[
	PlayerDataService — profil joueur persistant (DataStore), leaderstats et sauvegarde auto.
	Gère les nouveaux joueurs, les reprises tardives, les échecs réseau (réessais),
	la sauvegarde au départ et l'arrêt du serveur.

	Placement : src/server/PlayerDataService.luau (ModuleScript), chargé depuis un Script serveur :
		local Data = require(script.Parent.PlayerDataService)
		Data.Increment(player, "Coins", 10)
		print(Data.Get(player).Coins)

	Retourne son API (pas `true`) : Get, Set, Increment, Save, IsLoaded, OnLoaded.
]]

-- ⚙️ CONFIG
-- ▸ Stockage
local DATASTORE_NAME = "PlayerData_v1" -- changer de nom repart de zéro pour tout le monde
local KEY_PREFIX = "player_" -- préfixe de la clé DataStore
local AUTOSAVE_INTERVAL = 120 -- sauvegarde périodique en secondes, 30..600
local MAX_RETRIES = 3 -- tentatives par requête réseau, 1..6
local RETRY_DELAY = 2 -- attente entre deux tentatives en secondes, 0.5..10
local SAVE_IN_STUDIO = false -- écrire réellement dans le DataStore pendant les tests en Studio
-- ▸ Valeurs de départ
local STARTING_COINS = 0 -- pièces d'un nouveau joueur, 0..10000
local STARTING_LEVEL = 1 -- niveau d'un nouveau joueur, 1..100
local STARTING_XP = 0 -- expérience d'un nouveau joueur, 0..10000
-- ▸ Leaderstats
local ENABLE_LEADERSTATS = true -- affiche des stats dans la liste des joueurs
local SHOW_COINS = true -- affiche les pièces, si: ENABLE_LEADERSTATS
local COINS_LABEL = "Pièces" -- nom affiché des pièces, si: SHOW_COINS
local SHOW_LEVEL = false -- affiche le niveau, si: ENABLE_LEADERSTATS
local LEVEL_LABEL = "Niveau" -- nom affiché du niveau, si: SHOW_LEVEL
-- ⚙️ FIN CONFIG

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Profil par défaut. Ajouter une clé ici suffit : elle est complétée automatiquement
-- chez les joueurs existants sans casser leur sauvegarde.
local DEFAULT_PROFILE = {
	Coins = STARTING_COINS,
	Level = STARTING_LEVEL,
	XP = STARTING_XP,
}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	store = ok and result or nil
	if not ok then
		warn("[PlayerData] DataStore indisponible : " .. tostring(result))
	end
end

local persistenceOn = (store ~= nil) and (SAVE_IN_STUDIO or not RunService:IsStudio())

local profiles: { [Player]: { [string]: any } } = {}
local loaded: { [Player]: boolean } = {}

local Data = {}
Data.OnLoaded = Instance.new("BindableEvent") -- (player) dès que son profil est prêt

-- ------------------------------------------------------------------ utils

local function copyDefaults(): { [string]: any }
	local t = {}
	for k, v in pairs(DEFAULT_PROFILE) do
		t[k] = v
	end
	return t
end

local function fillMissing(profile: { [string]: any })
	for k, v in pairs(DEFAULT_PROFILE) do
		if profile[k] == nil then
			profile[k] = v
		end
	end
end

local function retry(label: string, fn: () -> any): (boolean, any)
	local lastErr
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY)
		end
	end
	warn(("[PlayerData] %s a échoué après %d tentatives : %s"):format(label, MAX_RETRIES, tostring(lastErr)))
	return false, lastErr
end

local function keyFor(player: Player): string
	return KEY_PREFIX .. tostring(player.UserId)
end

-- ------------------------------------------------------------ leaderstats

local function buildLeaderstats(player: Player, profile: { [string]: any })
	if not ENABLE_LEADERSTATS then return end

	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	if SHOW_COINS then
		local coins = Instance.new("IntValue")
		coins.Name = COINS_LABEL
		coins.Value = profile.Coins or 0
		coins.Parent = folder
	end
	if SHOW_LEVEL then
		local level = Instance.new("IntValue")
		level.Name = LEVEL_LABEL
		level.Value = profile.Level or 1
		level.Parent = folder
	end

	folder.Parent = player
end

local function syncLeaderstats(player: Player)
	if not ENABLE_LEADERSTATS then return end
	local folder = player:FindFirstChild("leaderstats")
	local profile = profiles[player]
	if not folder or not profile then return end

	if SHOW_COINS then
		local coins = folder:FindFirstChild(COINS_LABEL)
		if coins and coins:IsA("IntValue") then
			coins.Value = math.floor(profile.Coins or 0)
		end
	end
	if SHOW_LEVEL then
		local level = folder:FindFirstChild(LEVEL_LABEL)
		if level and level:IsA("IntValue") then
			level.Value = math.floor(profile.Level or 1)
		end
	end
end

-- --------------------------------------------------------------- chargement

local function loadProfile(player: Player)
	local profile = copyDefaults()

	if persistenceOn and store then
		local ok, saved = retry("chargement de " .. player.Name, function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if ok and type(saved) == "table" then
			profile = saved
			fillMissing(profile)
		elseif not ok then
			-- Chargement raté : on NE sauvegarde pas ce joueur, pour ne pas écraser
			-- une progression existante par un profil neuf.
			profiles[player] = profile
			buildLeaderstats(player, profile)
			warn("[PlayerData] " .. player.Name .. " joue sans sauvegarde (chargement échoué).")
			return
		end
	end

	if not player.Parent then return end -- parti pendant le chargement

	profiles[player] = profile
	loaded[player] = true
	buildLeaderstats(player, profile)
	Data.OnLoaded:Fire(player)
end

local function saveProfile(player: Player): boolean
	local profile = profiles[player]
	if not profile or not loaded[player] then return false end
	if not persistenceOn or not store then return false end

	local ok = retry("sauvegarde de " .. player.Name, function()
		return (store :: DataStore):UpdateAsync(keyFor(player), function()
			return profile
		end)
	end)
	return ok
end

-- ------------------------------------------------------------------- API

function Data.IsLoaded(player: Player): boolean
	return loaded[player] == true
end

function Data.Get(player: Player): { [string]: any }?
	return profiles[player]
end

function Data.Set(player: Player, key: string, value: any)
	local profile = profiles[player]
	if not profile then return end
	profile[key] = value
	syncLeaderstats(player)
end

function Data.Increment(player: Player, key: string, amount: number): number?
	local profile = profiles[player]
	if not profile then return nil end
	local current = tonumber(profile[key]) or 0
	profile[key] = current + amount
	syncLeaderstats(player)
	return profile[key]
end

function Data.Save(player: Player): boolean
	return saveProfile(player)
end

-- ------------------------------------------------------------ cycle de vie

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadProfile, player)
end)

Players.PlayerRemoving:Connect(function(player)
	saveProfile(player)
	profiles[player] = nil
	loaded[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadProfile, player) -- module chargé après l'arrivée de joueurs
end

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(saveProfile, player)
		end
	end
end)

game:BindToClose(function()
	if not persistenceOn then return end
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			saveProfile(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 20
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

if not persistenceOn then
	warn("[PlayerData] persistance désactivée (Studio, ou DataStore inaccessible) — rien n'est écrit.")
end

return Data

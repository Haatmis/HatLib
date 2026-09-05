--[[
	StaminaService — endurance du joueur, ressource partagée par tout le jeu.

	Ce n'est pas une jauge de sprint : c'est LA jauge du joueur. Le sprint, la ruée,
	l'escalade ou une attaque s'y branchent tous et se lisent dans le même affichage.

	Autorité serveur : la valeur vit côté serveur et se réplique par un attribut du
	joueur. Le client déclare seulement ses intentions (« je dépense pour telle
	raison ») et dessine. Un exploiteur ne peut pas se remplir la jauge ; au pire il
	sous-déclare une dépense, bornée par MAX_DRAIN_RATE.

	Placement : src/shared/ (ModuleScript), `require` une fois côté serveur et une
	fois côté client. Le configurateur pose ces deux lignes tout seul.

	API :
		Stamina.Get() / GetRatio() / GetMax()
		Stamina.SetDrain(raison, parSeconde)   -- dépense continue ; 0 ou nil pour arrêter
		Stamina.TryConsume(montant) -> bool    -- dépense ponctuelle
		Stamina.CanAfford(montant) -> bool
		Stamina.Changed                        -- signal client (valeur, ratio)
		Stamina.HideDefaultDisplay()           -- si le jeu dessine son propre affichage
		Stamina.GetFor(p) / SetFor(p, n) / AddFor(p, n)   -- côté serveur
]]

-- ⚙️ CONFIG
-- 🎬 APERÇU: stamina/hud
-- ▸ Ressource
local STAMINA_MAX = 100 -- endurance maximale du joueur, 10..500
local START_FULL = true -- jauge pleine à l'apparition et à chaque réapparition
local REGEN_RATE = 15 -- récupération par seconde, 0..100
local REGEN_DELAY = 1 -- délai après la dernière dépense en secondes, 0..10
local EMPTY_LOCKOUT = 0 -- blocage en secondes quand la jauge touche zéro, 0..10
local MAX_DRAIN_RATE = 60 -- garde-fou serveur : dépense max acceptée par seconde, 1..200
-- ▸ Affichage
local DISPLAY_MODE = "Barre" -- forme de la jauge, options: Aucun|Barre|BarreSegments|BarreVerticale|BarreCentree|Anneau|Arc|Points|Chiffre|Reticule|Vignette|Icone
local DISPLAY_TARGET = "Ecran" -- où la dessiner, si: DISPLAY_MODE != Aucun, options: Ecran|Personnage|Les deux
local SHOW_WHEN = "Incomplet" -- quand la montrer, si: DISPLAY_MODE != Aucun, options: Toujours|Incomplet|EnUsage
local FADE_TIME = 0.3 -- durée du fondu d'apparition en secondes, si: DISPLAY_MODE != Aucun, 0..2
-- ▸ Position à l'écran
local SCREEN_ANCHOR = "BasCentre" -- ancrage à l'écran, si: DISPLAY_TARGET = Ecran|Les deux, options: HautGauche|HautCentre|HautDroite|MilieuGauche|Centre|MilieuDroite|BasGauche|BasCentre|BasDroite
local OFFSET_X = 0 -- décalage horizontal en pixels, si: DISPLAY_TARGET = Ecran|Les deux, -400..400
local OFFSET_Y = -14 -- décalage vertical en pixels, si: DISPLAY_TARGET = Ecran|Les deux, -400..400
local WIDTH = 220 -- largeur à l'écran en pixels, si: DISPLAY_TARGET = Ecran|Les deux, 16..600
local HEIGHT = 12 -- hauteur à l'écran en pixels, si: DISPLAY_TARGET = Ecran|Les deux, 4..300
local IGNORE_GUI_INSET = true -- ignorer la barre supérieure de Roblox, si: DISPLAY_TARGET = Ecran|Les deux
-- ▸ Style
local FILL_COLOR = "#5B8CFF" -- couleur de la jauge
local FILL_COLOR_LOW = "#FF5B6A" -- couleur quand la jauge est basse
local LOW_THRESHOLD = 0.25 -- en dessous de ce ratio, la couleur bascule, 0..1
local BACK_COLOR = "#000000" -- couleur du fond
local BACK_TRANSPARENCY = 0.55 -- transparence du fond, 0..1
local CORNER_RADIUS = 6 -- arrondi des coins en pixels, 0..40
local BORDER_THICKNESS = 0 -- épaisseur du contour en pixels, 0..6
local BORDER_COLOR = "#FFFFFF" -- couleur du contour, si: BORDER_THICKNESS > 0
local SEGMENT_COUNT = 6 -- nombre de segments ou de points, si: DISPLAY_MODE = BarreSegments|Points, 2..24
local SEGMENT_GAP = 4 -- espace entre segments en pixels, si: DISPLAY_MODE = BarreSegments|Points, 0..16
local SHOW_TEXT = false -- surimprime la valeur chiffrée
local TEXT_COLOR = "#FFFFFF" -- couleur du texte, si: SHOW_TEXT
local FLASH_ON_EMPTY = true -- clignote quand la jauge est à zéro
-- ▸ Au-dessus du personnage
local WORLD_OFFSET_Y = 3 -- hauteur au-dessus de la tête en studs, si: DISPLAY_TARGET = Personnage|Les deux, 0..8
local WORLD_WIDTH = 4 -- largeur en studs, si: DISPLAY_TARGET = Personnage|Les deux, 0.5..12
local WORLD_HEIGHT = 0.45 -- hauteur en studs, si: DISPLAY_TARGET = Personnage|Les deux, 0.05..4
local WORLD_ALWAYS_ON_TOP = false -- visible à travers les murs, si: DISPLAY_TARGET = Personnage|Les deux
local WORLD_MAX_DISTANCE = 60 -- distance d'affichage maximale en studs, si: DISPLAY_TARGET = Personnage|Les deux, 10..300
-- ⚙️ FIN CONFIG

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ATTR = "HatLibStamina"
local ATTR_MAX = "HatLibStaminaMax"
local REMOTE_NAME = "HatLibStaminaRemote"

local function clamp(v: number, a: number, b: number): number
	return v < a and a or (v > b and b or v)
end

--=============================================================== SERVEUR ====

if RunService:IsServer() then
	local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if not remote then
		local created = Instance.new("RemoteEvent")
		created.Name = REMOTE_NAME
		created.Parent = ReplicatedStorage
		remote = created
	end

	local values: { [Player]: number } = {}
	local drains: { [Player]: { [string]: number } } = {}
	local lastSpend: { [Player]: number } = {}
	local lockedUntil: { [Player]: number } = {}

	local Server = {}

	local function setValue(player: Player, v: number)
		local nv = clamp(v, 0, STAMINA_MAX)
		values[player] = nv
		player:SetAttribute(ATTR, nv)
	end

	function Server.GetMax(): number
		return STAMINA_MAX
	end

	function Server.GetFor(player: Player): number
		return values[player] or 0
	end

	function Server.SetFor(player: Player, v: number)
		if values[player] == nil then return end
		setValue(player, v)
	end

	function Server.AddFor(player: Player, delta: number)
		if values[player] == nil then return end
		setValue(player, values[player] + delta)
	end

	local function onPlayer(player: Player)
		player:SetAttribute(ATTR_MAX, STAMINA_MAX)
		drains[player] = {}
		lastSpend[player] = 0
		lockedUntil[player] = 0
		setValue(player, STAMINA_MAX)

		player.CharacterAdded:Connect(function()
			drains[player] = {}
			lockedUntil[player] = 0
			if START_FULL then
				setValue(player, STAMINA_MAX)
			end
		end)
	end

	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		values[player] = nil
		drains[player] = nil
		lastSpend[player] = nil
		lockedUntil[player] = nil
	end)

	-- Le client déclare ce qu'il dépense ; le serveur borne, puis applique.
	remote.OnServerEvent:Connect(function(player, action, a, b)
		if values[player] == nil then return end

		if action == "drain" and type(a) == "string" and type(b) == "number" then
			local rate = clamp(b, 0, MAX_DRAIN_RATE)
			drains[player][a] = rate > 0 and rate or nil
		elseif action == "consume" and type(a) == "number" then
			local cost = clamp(a, 0, STAMINA_MAX)
			if values[player] >= cost and os.clock() >= lockedUntil[player] then
				setValue(player, values[player] - cost)
				lastSpend[player] = os.clock()
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		for player, current in values do
			local total = 0
			for _, rate in drains[player] do
				total += rate
			end
			total = clamp(total, 0, MAX_DRAIN_RATE)

			if total > 0 and now >= lockedUntil[player] and current > 0 then
				local nv = clamp(current - total * dt, 0, STAMINA_MAX)
				lastSpend[player] = now
				if nv <= 0 and EMPTY_LOCKOUT > 0 then
					lockedUntil[player] = now + EMPTY_LOCKOUT
				end
				setValue(player, nv)
			elseif current < STAMINA_MAX and now - lastSpend[player] >= REGEN_DELAY then
				setValue(player, current + REGEN_RATE * dt)
			end
		end
	end)

	return Server
end

--================================================================ CLIENT ====

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild(REMOTE_NAME, 10)
if not remote then
	warn("[Stamina] RemoteEvent absent : le module n'est pas `require` côté serveur.")
end

local changed = Instance.new("BindableEvent")
local declared: { [string]: number } = {}
local widgets = {}
local displayHidden = false
local lastRatio = 1

local Client = {}
Client.Changed = changed.Event

local function value(): number
	return player:GetAttribute(ATTR) or 0
end

local function maxValue(): number
	return player:GetAttribute(ATTR_MAX) or STAMINA_MAX
end

function Client.Get(): number return value() end
function Client.GetMax(): number return maxValue() end

function Client.GetRatio(): number
	local m = maxValue()
	return m > 0 and clamp(value() / m, 0, 1) or 0
end

function Client.CanAfford(amount: number): boolean
	return value() >= amount
end

function Client.IsDraining(): boolean
	return next(declared) ~= nil
end

-- Dépense continue. Idempotent : ne parle au serveur que si le débit change.
function Client.SetDrain(reason: string, ratePerSecond: number?)
	local rate = ratePerSecond or 0
	local current = declared[reason] or 0
	if current == rate then return end
	declared[reason] = rate > 0 and rate or nil
	if remote then
		remote:FireServer("drain", reason, rate)
	end
end

-- Dépense ponctuelle. Réponse optimiste : le serveur reste l'autorité.
function Client.TryConsume(amount: number): boolean
	if value() < amount then return false end
	if remote then
		remote:FireServer("consume", amount)
	end
	return true
end

--------------------------------------------------------------- construction

local function hex(s: string): Color3
	local ok, c = pcall(Color3.fromHex, s)
	return ok and c or Color3.new(1, 1, 1)
end

local function corner(inst: GuiObject, radius: number)
	if radius <= 0 then return end
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function block(parent: Instance, name: string, colour: Color3, transparency: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = colour
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

-- Un anneau sans image : des segments posés sur un cercle, allumés l'un après
-- l'autre. Plus robuste que les astuces de rognage, et net à toute taille.
local function ringSegments(parent: Instance, count: number, sweepDeg: number, startDeg: number)
	local segs = {}
	for i = 1, count do
		local deg = startDeg + (i - 0.5) / count * sweepDeg
		local a = math.rad(deg)
		local seg = block(parent, "Seg" .. i, hex(FILL_COLOR), 0)
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.Position = UDim2.fromScale(0.5 + math.sin(a) * 0.42, 0.5 - math.cos(a) * 0.42)
		seg.Size = UDim2.fromScale(0.085, 0.16)
		seg.Rotation = deg
		corner(seg, 2)
		segs[i] = seg
	end
	return segs
end

-- Construit la jauge dans `host`. Toutes les tailles internes sont en échelle :
-- le même code sert au ScreenGui (hôte dimensionné en pixels) et au
-- BillboardGui (dimensionné en studs).
local function buildWidget(host: Instance, mode: string)
	local fillColour = hex(FILL_COLOR)
	local lowColour = hex(FILL_COLOR_LOW)
	local plain = mode == "Vignette" or mode == "Reticule" or mode == "Points"

	-- CanvasGroup : un seul réglage de transparence pour tout le widget, c'est
	-- ce qui rend le fondu possible sans toucher chaque pièce.
	local container: GuiObject
	if FADE_TIME > 0 then
		local cg = Instance.new("CanvasGroup")
		cg.BackgroundTransparency = 1
		cg.BorderSizePixel = 0
		container = cg
	else
		container = block(host, "Container", Color3.new(), 1)
	end
	container.Name = "Stamina"
	container.Size = UDim2.fromScale(1, 1)
	container.Parent = host

	local root = block(container, "Root", hex(BACK_COLOR), plain and 1 or BACK_TRANSPARENCY)
	root.Size = UDim2.fromScale(1, 1)
	corner(root, CORNER_RADIUS)
	if BORDER_THICKNESS > 0 and not plain then
		local s = Instance.new("UIStroke")
		s.Thickness = BORDER_THICKNESS
		s.Color = hex(BORDER_COLOR)
		s.Parent = root
	end

	local paint: (number) -> ()

	if mode == "Barre" then
		local fill = block(root, "Fill", fillColour, 0)
		corner(fill, CORNER_RADIUS)
		paint = function(r)
			fill.Size = UDim2.fromScale(r, 1)
			fill.BackgroundColor3 = r <= LOW_THRESHOLD and lowColour or fillColour
		end

	elseif mode == "BarreVerticale" then
		local fill = block(root, "Fill", fillColour, 0)
		fill.AnchorPoint = Vector2.new(0, 1)
		fill.Position = UDim2.fromScale(0, 1)
		corner(fill, CORNER_RADIUS)
		paint = function(r)
			fill.Size = UDim2.fromScale(1, r)
			fill.BackgroundColor3 = r <= LOW_THRESHOLD and lowColour or fillColour
		end

	elseif mode == "BarreCentree" then
		local fill = block(root, "Fill", fillColour, 0)
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Position = UDim2.fromScale(0.5, 0.5)
		corner(fill, CORNER_RADIUS)
		paint = function(r)
			fill.Size = UDim2.fromScale(r, 1)
			fill.BackgroundColor3 = r <= LOW_THRESHOLD and lowColour or fillColour
		end

	elseif mode == "BarreSegments" or mode == "Points" then
		local dots = mode == "Points"
		local n = math.max(2, math.floor(SEGMENT_COUNT))
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, SEGMENT_GAP)
		list.Parent = root

		local cells = {}
		for i = 1, n do
			local cell = block(root, "Cell" .. i, fillColour, 0)
			cell.LayoutOrder = i
			if dots then
				cell.Size = UDim2.fromScale(1, 1)
				cell.SizeConstraint = Enum.SizeConstraint.RelativeYY
				corner(cell, 999)
			else
				cell.Size = UDim2.fromScale(1 / n, 1)
				corner(cell, math.min(CORNER_RADIUS, 4))
			end
			cells[i] = cell
		end
		paint = function(r)
			local exact = r * n
			local colour = r <= LOW_THRESHOLD and lowColour or fillColour
			for i, cell in cells do
				local part = clamp(exact - (i - 1), 0, 1)
				cell.BackgroundTransparency = part >= 1 and 0 or (part <= 0 and 0.78 or 0.35)
				cell.BackgroundColor3 = colour
			end
		end

	elseif mode == "Anneau" or mode == "Arc" or mode == "Reticule" then
		local sweep = mode == "Arc" and 270 or 360
		local start = mode == "Arc" and -135 or 0
		local n = mode == "Reticule" and 24 or (mode == "Arc" and 36 or 48)
		local holder = block(root, "Ring", fillColour, 1)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.fromScale(1, 1)
		holder.SizeConstraint = Enum.SizeConstraint.RelativeYY
		local segs = ringSegments(holder, n, sweep, start)
		paint = function(r)
			local lit = r * n
			local colour = r <= LOW_THRESHOLD and lowColour or fillColour
			for i, seg in segs do
				seg.BackgroundTransparency = i <= lit and 0 or 0.8
				seg.BackgroundColor3 = colour
			end
		end

	elseif mode == "Icone" then
		local box = block(root, "Box", fillColour, 0.8)
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromScale(0.72, 0.72)
		box.SizeConstraint = Enum.SizeConstraint.RelativeYY
		box.Rotation = 45
		box.ClipsDescendants = true
		corner(box, math.max(CORNER_RADIUS, 3))
		local fill = block(box, "Fill", fillColour, 0)
		fill.AnchorPoint = Vector2.new(0, 1)
		fill.Position = UDim2.fromScale(0, 1)
		paint = function(r)
			fill.Size = UDim2.fromScale(1, r)
			fill.BackgroundColor3 = r <= LOW_THRESHOLD and lowColour or fillColour
		end

	elseif mode == "Vignette" then
		local edges = {}
		local specs = {
			{ UDim2.fromScale(1, 0.22), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), 90 },
			{ UDim2.fromScale(1, 0.22), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1), 270 },
			{ UDim2.fromScale(0.18, 1), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5), 0 },
			{ UDim2.fromScale(0.18, 1), UDim2.fromScale(1, 0.5), Vector2.new(1, 0.5), 180 },
		}
		for i, s in specs do
			local e = block(root, "Edge" .. i, lowColour, 1)
			e.Size, e.Position, e.AnchorPoint = s[1], s[2], s[3]
			local grad = Instance.new("UIGradient")
			grad.Rotation = s[4]
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			})
			grad.Parent = e
			edges[i] = e
		end
		paint = function(r)
			-- La vignette est une alarme : invisible tant que la jauge va bien,
			-- de plus en plus présente à mesure qu'elle se vide.
			local span = math.max(LOW_THRESHOLD * 2, 0.01)
			local intensity = clamp((span - r) / span, 0, 1)
			for _, e in edges do
				e.BackgroundTransparency = 1 - intensity * 0.75
			end
		end

	else -- "Chiffre"
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Value"
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextColor3 = hex(TEXT_COLOR)
		lbl.Text = "0"
		lbl.Parent = root
		paint = function(r)
			lbl.Text = string.format("%d", math.floor(r * maxValue() + 0.5))
			lbl.TextColor3 = r <= LOW_THRESHOLD and lowColour or hex(TEXT_COLOR)
		end
	end

	-- Valeur chiffrée en surimpression, disponible sur toutes les formes.
	local overlay: TextLabel? = nil
	if SHOW_TEXT and mode ~= "Chiffre" then
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Overlay"
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextColor3 = hex(TEXT_COLOR)
		lbl.ZIndex = 5
		lbl.Parent = root
		overlay = lbl
	end

	local shown = true
	local fade: Tween? = nil

	return {
		root = container,
		setRatio = function(r)
			paint(r)
			if overlay then
				overlay.Text = string.format("%d / %d", math.floor(r * maxValue() + 0.5), math.floor(maxValue()))
			end
		end,
		setShown = function(on: boolean, instant: boolean?)
			if on == shown and not instant then return end
			shown = on
			if FADE_TIME <= 0 or instant then
				container.Visible = on
				if container:IsA("CanvasGroup") then
					container.GroupTransparency = on and 0 or 1
				end
				return
			end
			if fade then fade:Cancel() end
			if on then container.Visible = true end
			if container:IsA("CanvasGroup") then
				local t = TweenService:Create(container, TweenInfo.new(FADE_TIME), { GroupTransparency = on and 0 or 1 })
				fade = t
				t.Completed:Connect(function()
					if not on then container.Visible = false end
				end)
				t:Play()
			else
				container.Visible = on
			end
		end,
	}
end

------------------------------------------------------------------- écran

local ANCHORS = {
	HautGauche = { 0, 0 }, HautCentre = { 0.5, 0 }, HautDroite = { 1, 0 },
	MilieuGauche = { 0, 0.5 }, Centre = { 0.5, 0.5 }, MilieuDroite = { 1, 0.5 },
	BasGauche = { 0, 1 }, BasCentre = { 0.5, 1 }, BasDroite = { 1, 1 },
}

local function buildScreen()
	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if not playerGui then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "HatLibStaminaGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = IGNORE_GUI_INSET
	gui.Parent = playerGui

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	if DISPLAY_MODE == "Vignette" then
		holder.Size = UDim2.fromScale(1, 1) -- plein écran : la vignette borde l'image
	elseif DISPLAY_MODE == "Reticule" then
		local side = math.max(WIDTH, HEIGHT)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.fromOffset(side, side) -- pile au centre, autour du réticule
	else
		local a = ANCHORS[SCREEN_ANCHOR] or ANCHORS.BasCentre
		holder.AnchorPoint = Vector2.new(a[1], a[2])
		holder.Position = UDim2.new(a[1], OFFSET_X, a[2], OFFSET_Y)
		holder.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	end
	holder.Parent = gui

	widgets[#widgets + 1] = buildWidget(holder, DISPLAY_MODE)
end

--------------------------------------------------------- au-dessus du perso

local function buildWorld(character: Model)
	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 5)
	if not head then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "HatLibStaminaBillboard"
	bb.Adornee = head
	bb.AlwaysOnTop = WORLD_ALWAYS_ON_TOP
	bb.MaxDistance = WORLD_MAX_DISTANCE
	bb.Size = UDim2.fromScale(WORLD_WIDTH, WORLD_HEIGHT)
	bb.StudsOffsetWorldSpace = Vector3.new(0, WORLD_OFFSET_Y, 0)
	bb.Parent = head

	-- Vignette et réticule n'ont pas de sens au-dessus d'une tête : on retombe
	-- sur la barre plutôt que d'afficher quelque chose d'illisible.
	local mode = (DISPLAY_MODE == "Vignette" or DISPLAY_MODE == "Reticule") and "Barre" or DISPLAY_MODE
	widgets[#widgets + 1] = buildWidget(bb, mode)
end

---------------------------------------------------------------- affichage

local function visibleFor(ratio: number): boolean
	if displayHidden or DISPLAY_MODE == "Aucun" then return false end
	if SHOW_WHEN == "Toujours" then return true end
	if SHOW_WHEN == "EnUsage" then return Client.IsDraining() or ratio < 0.999 end
	return ratio < 0.999
end

local function refresh()
	local ratio = Client.GetRatio()
	lastRatio = ratio
	local show = visibleFor(ratio)
	for _, w in widgets do
		w.setRatio(ratio)
		w.setShown(show)
	end
	changed:Fire(value(), ratio)
end

function Client.HideDefaultDisplay()
	displayHidden = true
	for _, w in widgets do
		w.setShown(false)
	end
end

-- Cycle de vie -------------------------------------------------------------

local function onCharacter(character: Model)
	if DISPLAY_MODE == "Aucun" then return end
	if DISPLAY_TARGET == "Personnage" or DISPLAY_TARGET == "Les deux" then
		task.spawn(function()
			buildWorld(character)
			refresh()
		end)
	end
	refresh()
end

if DISPLAY_MODE ~= "Aucun" and (DISPLAY_TARGET == "Ecran" or DISPLAY_TARGET == "Les deux") then
	buildScreen()
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(function(character)
	-- Le billboard disparaît avec l'ancien personnage : on purge les widgets
	-- orphelins avant d'en reconstruire un.
	for i = #widgets, 1, -1 do
		if not widgets[i].root:IsDescendantOf(game) then
			table.remove(widgets, i)
		end
	end
	onCharacter(character)
end)

player:GetAttributeChangedSignal(ATTR):Connect(refresh)
player:GetAttributeChangedSignal(ATTR_MAX):Connect(refresh)

if FLASH_ON_EMPTY then
	local accum = 0
	local blinkOn = true
	RunService.Heartbeat:Connect(function(dt)
		if lastRatio > 0.001 or displayHidden or DISPLAY_MODE == "Aucun" then
			if not blinkOn then
				blinkOn = true
				for _, w in widgets do
					w.setShown(visibleFor(lastRatio), true)
				end
			end
			return
		end
		accum += dt
		local on = (accum % 0.5) < 0.25
		if on ~= blinkOn then
			blinkOn = on
			for _, w in widgets do
				w.setShown(on, true)
			end
		end
	end)
end

refresh()

return Client

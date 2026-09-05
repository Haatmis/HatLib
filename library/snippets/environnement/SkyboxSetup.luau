--[[
	SkyboxSetup — ciel, atmosphère et ambiance lumineuse pour toute la partie.

	Placement : src/server/SkyboxSetup.luau (ModuleScript), chargé une fois depuis un Script serveur :
		require(script.Parent.SkyboxSetup)

	Applique ses réglages à `Lighting` dès le chargement (répliqué automatiquement aux clients) :
	pas d'API, pas de boucle, juste un état posé une fois.
]]

-- ⚙️ CONFIG
-- ▸ Textures du ciel
local ENABLE_CUSTOM_SKYBOX = false -- remplace le ciel par défaut par 6 textures personnalisées
local SKYBOX_UP = "rbxassetid://0" -- face du haut, si: ENABLE_CUSTOM_SKYBOX
local SKYBOX_DN = "rbxassetid://0" -- face du bas, si: ENABLE_CUSTOM_SKYBOX
local SKYBOX_FT = "rbxassetid://0" -- face avant, si: ENABLE_CUSTOM_SKYBOX
local SKYBOX_BK = "rbxassetid://0" -- face arrière, si: ENABLE_CUSTOM_SKYBOX
local SKYBOX_LF = "rbxassetid://0" -- face gauche, si: ENABLE_CUSTOM_SKYBOX
local SKYBOX_RT = "rbxassetid://0" -- face droite, si: ENABLE_CUSTOM_SKYBOX
-- ▸ Soleil, lune, étoiles
local SUN_ANGULAR_SIZE = 21 -- taille apparente du soleil, 1..60
local MOON_ANGULAR_SIZE = 11 -- taille apparente de la lune, 1..60
local STAR_COUNT = 3000 -- nombre d'étoiles visibles la nuit, 0..6000
local CELESTIAL_BODIES_SHOWN = true -- affiche soleil, lune et étoiles
-- ▸ Atmosphère
local ENABLE_ATMOSPHERE = true -- ajoute une couche d'atmosphère (brume de fond, halo)
local ATMOSPHERE_DENSITY = 0.3 -- épaisseur de la brume, si: ENABLE_ATMOSPHERE, 0..1
local ATMOSPHERE_OFFSET = 0.25 -- décalage vertical de la brume, si: ENABLE_ATMOSPHERE, 0..1
local ATMOSPHERE_GLARE = 0 -- halo autour du soleil, si: ENABLE_ATMOSPHERE, 0..1
local ATMOSPHERE_HAZE = 0 -- opacité au ras du sol, si: ENABLE_ATMOSPHERE, 0..10
local ATMOSPHERE_COLOR = "#E6E6E6" -- teinte de l'atmosphère au loin, si: ENABLE_ATMOSPHERE
local ATMOSPHERE_DECAY = "#8899AA" -- teinte de l'atmosphère qui absorbe la lumière, si: ENABLE_ATMOSPHERE
-- ▸ Ambiance lumineuse
local CLOCK_TIME = 14 -- heure de la journée, 0..24
local AMBIENT_COLOR = "#000000" -- lumière ambiante dans les zones à l'ombre
local OUTDOOR_AMBIENT_COLOR = "#787878" -- lumière ambiante en extérieur
local BRIGHTNESS = 2 -- intensité générale de la lumière, 0..15
-- ▸ Brouillard
local ENABLE_FOG = false -- active un brouillard de distance
local FOG_COLOR = "#C8C8C8" -- teinte du brouillard, si: ENABLE_FOG
local FOG_START = 500 -- distance où le brouillard commence, si: ENABLE_FOG, 0..5000
local FOG_END = 3000 -- distance où le brouillard cache tout, si: ENABLE_FOG, 100..10000
-- ⚙️ FIN CONFIG

local Lighting = game:GetService("Lighting")

local function hexToColor3(hex)
	hex = hex:gsub("#", "")
	local r = tonumber(hex:sub(1, 2), 16) or 0
	local g = tonumber(hex:sub(3, 4), 16) or 0
	local b = tonumber(hex:sub(5, 6), 16) or 0
	return Color3.fromRGB(r, g, b)
end

local sky = Lighting:FindFirstChildOfClass("Sky")
if not sky then
	sky = Instance.new("Sky")
	sky.Parent = Lighting
end

if ENABLE_CUSTOM_SKYBOX then
	sky.SkyboxUp = SKYBOX_UP
	sky.SkyboxDn = SKYBOX_DN
	sky.SkyboxFt = SKYBOX_FT
	sky.SkyboxBk = SKYBOX_BK
	sky.SkyboxLf = SKYBOX_LF
	sky.SkyboxRt = SKYBOX_RT
end

sky.SunAngularSize = SUN_ANGULAR_SIZE
sky.MoonAngularSize = MOON_ANGULAR_SIZE
sky.StarCount = STAR_COUNT
sky.CelestialBodiesShown = CELESTIAL_BODIES_SHOWN

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if ENABLE_ATMOSPHERE then
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = ATMOSPHERE_DENSITY
	atmosphere.Offset = ATMOSPHERE_OFFSET
	atmosphere.Glare = ATMOSPHERE_GLARE
	atmosphere.Haze = ATMOSPHERE_HAZE
	atmosphere.Color = hexToColor3(ATMOSPHERE_COLOR)
	atmosphere.Decay = hexToColor3(ATMOSPHERE_DECAY)
elseif atmosphere then
	atmosphere:Destroy()
end

Lighting.ClockTime = CLOCK_TIME
Lighting.Ambient = hexToColor3(AMBIENT_COLOR)
Lighting.OutdoorAmbient = hexToColor3(OUTDOOR_AMBIENT_COLOR)
Lighting.Brightness = BRIGHTNESS

Lighting.FogColor = hexToColor3(FOG_COLOR)
if ENABLE_FOG then
	Lighting.FogStart = FOG_START
	Lighting.FogEnd = FOG_END
else
	Lighting.FogStart = 100000
	Lighting.FogEnd = 100000
end

return true

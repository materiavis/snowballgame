--!strict
-- Temporary recovery test geometry for the Studio switch BallRecoveryTestGeometry (ADR 0002
-- "Playtest hooks", issue #94). Only bound in Studio at PlaceId 0; the map files stay as they
-- are. Everything lives in one Workspace folder that the switch creates and destroys.
--
-- * Cliff: a platform 70 studs high, reached by a ramp from near the spawn. 70 is above the
--   vertical growth range of a 50-stud ball (radius 25 + GrowthVerticalRange 8 from the centre),
--   so the ground below the edge is no put-back spot for any ball size.
-- * Hole pier: a floor beyond the -Z map edge (z = -1024) with a 60 × 60 hole into the void,
--   wide enough for the 50-stud ball. Its sides are cliffs into the void as well.
-- The sizes are test fixtures, not gameplay values.

local FOLDER_NAME = "BallRecoveryTest"
local COLOR = Color3.fromRGB(150, 170, 200)

-- Cliff: platform x -320..-200, z -210..-90, top y 70; ramp down towards +X at 25°.
local CLIFF_CENTRE = Vector3.new(-260, 35, -150)
local CLIFF_SIZE = Vector3.new(120, 70, 120)
local RAMP_WIDTH = 60
local RAMP_ANGLE = math.rad(25)
local RAMP_THICKNESS = 2

-- Hole pier: x -80..80, z -1184..-1024, top y 0 (flush with the map), hole x -30..30,
-- z -1134..-1074.
local PIER_TOP = 0
local PIER_THICKNESS = 16
local PIER_NEAR_Z = -1024
local PIER_HALF_WIDTH = 80
local PIER_LENGTH = 160
local HOLE_HALF = 30
local HOLE_FROM_EDGE = 50

local TestGeometry = {}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = COLOR
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
end

local function buildCliff(parent: Instance)
	block(parent, "CliffPlatform", CLIFF_SIZE, CFrame.new(CLIFF_CENTRE))
	local height = CLIFF_CENTRE.Y + CLIFF_SIZE.Y / 2
	local topX = CLIFF_CENTRE.X + CLIFF_SIZE.X / 2
	local run = height / math.tan(RAMP_ANGLE)
	local length = math.sqrt(run * run + height * height)
	-- The ramp's top surface runs from the platform's +X edge at full height to the ground.
	local topMiddle = Vector3.new(topX + run / 2, height / 2, CLIFF_CENTRE.Z)
	local cframe = CFrame.new(topMiddle) * CFrame.Angles(0, 0, -RAMP_ANGLE) * CFrame.new(0, -RAMP_THICKNESS / 2, 0)
	block(parent, "CliffRamp", Vector3.new(length, RAMP_THICKNESS, RAMP_WIDTH), cframe)
end

local function buildPier(parent: Instance)
	local y = PIER_TOP - PIER_THICKNESS / 2
	local farZ = PIER_NEAR_Z - PIER_LENGTH
	local holeNearZ = PIER_NEAR_Z - HOLE_FROM_EDGE
	local holeFarZ = holeNearZ - 2 * HOLE_HALF
	local width = 2 * PIER_HALF_WIDTH
	local side = PIER_HALF_WIDTH - HOLE_HALF
	block(
		parent,
		"PierNear",
		Vector3.new(width, PIER_THICKNESS, HOLE_FROM_EDGE),
		CFrame.new(0, y, (PIER_NEAR_Z + holeNearZ) / 2)
	)
	block(
		parent,
		"PierFar",
		Vector3.new(width, PIER_THICKNESS, holeFarZ - farZ),
		CFrame.new(0, y, (holeFarZ + farZ) / 2)
	)
	local holeMiddleZ = (holeNearZ + holeFarZ) / 2
	local sideX = HOLE_HALF + side / 2
	block(parent, "PierLeft", Vector3.new(side, PIER_THICKNESS, 2 * HOLE_HALF), CFrame.new(-sideX, y, holeMiddleZ))
	block(parent, "PierRight", Vector3.new(side, PIER_THICKNESS, 2 * HOLE_HALF), CFrame.new(sideX, y, holeMiddleZ))
end

-- Builds the geometry once; returns a short description for the log.
function TestGeometry.create(parent: Instance): string
	local existing = parent:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	buildCliff(folder)
	buildPier(folder)
	folder.Parent = parent
	return `cliff top y=70 at x -320..-200 z -210..-90 (ramp from x -50, z -180..-120); `
		.. `hole pier beyond z=-1024 at x -80..80, hole x -30..30 z -1134..-1074`
end

function TestGeometry.remove(parent: Instance)
	local existing = parent:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
end

return table.freeze(TestGeometry)

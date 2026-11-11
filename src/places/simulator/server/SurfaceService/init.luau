--!strict
-- SurfaceService (Simulator only, concept 6.2, 7.4, ADR 0003 D3): what ground a part is, from
-- its CollectionService tags, and one logical track grid per player. Ground is never edited.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ball")) :: any
local TrackGrid = require(script:WaitForChild("TrackGrid"))

local NO_SURFACE = "None"

local SurfaceService = {}

local started = false

-- The surface tag of a ground part, or "None" for ground that is no surface at all.
function SurfaceService.classify(instance: Instance?): string
	if instance == nil then
		return NO_SURFACE
	end
	for _, tag in BallConfig.SurfacePriority do
		if CollectionService:HasTag(instance, tag) then
			return tag
		end
	end
	return NO_SURFACE
end

function SurfaceService.newTrack(): TrackGrid.TrackGrid
	return TrackGrid.new(BallConfig)
end

function SurfaceService.Start()
	if started then
		return
	end
	started = true
	local counts: { string } = {}
	for _, tag in BallConfig.SurfacePriority do
		table.insert(counts, `{tag}={#CollectionService:GetTagged(tag)}`)
	end
	print(`[SurfaceService] started {table.concat(counts, " ")}`)
end

return SurfaceService

--!strict
-- Publishes the server-decided ball size as attributes (concept 7.4, ADR 0002): on the ball and
-- on the Player, so a HUD reads it without finding the ball. Clients only ever read these.
-- Diagnostics for the read-only playtester are written only in Studio at PlaceId 0.

local CollectionService = game:GetService("CollectionService")

export type Published = {
	publish: (state: any, now: number, force: boolean) -> (),
}

local BallAttributesModule = {}

local function anchorPosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Attachment") then
		return instance.WorldPosition
	end
	return nil
end

function BallAttributesModule.new(config: any, rules: any, diagnostics: boolean): Published
	local names = config.DiagnosticAttributes

	local function setOn(instance: Instance, sent: { [string]: any }, name: string, value: any)
		if sent[name] ~= value then
			sent[name] = value
			instance:SetAttribute(name, value)
		end
	end

	local function nearestAnchor(position: Vector3): Vector3?
		local best: Vector3? = nil
		local bestDistance = math.huge
		for _, instance in CollectionService:GetTagged(config.ScaleAnchorTag) do
			local candidate = anchorPosition(instance)
			if candidate then
				local distance = (candidate - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = candidate, distance
				end
			end
		end
		return best
	end

	local function publishDiagnostics(state: any, part: BasePart)
		local sent = state.sentPart
		setOn(part, sent, names.Surface, state.surface)
		setOn(part, sent, names.GrowthCounts, state.growthBlock == nil)
		setOn(part, sent, names.GrowthBlock, state.growthBlock or "")
		setOn(part, sent, names.LastCollisionLoss, math.round(state.lastCollisionLoss * 1000) / 1000)
		setOn(part, sent, names.Collisions, state.collisions)
		setOn(part, sent, names.KnockOvers, state.knockOvers)
		setOn(part, sent, names.TrackCells, state.track.cellCount())
		setOn(part, sent, names.RolledStuds, math.round(state.rolledStuds * 10) / 10)
		setOn(part, sent, names.CountedStuds, math.round(state.countedStuds * 10) / 10)
		setOn(part, sent, names.GrowthSeconds, math.round(state.growthSeconds * 10) / 10)
		local measured = state.measuredTimeToMax
		setOn(part, sent, names.MeasuredTimeToMax, if measured then math.round(measured * 10) / 10 else nil)
	end

	-- `force` writes now; otherwise at most once per PublishInterval, so a growing ball does not
	-- replicate at the sample rate to every client.
	local function publish(state: any, now: number, force: boolean)
		local isMax = state.fraction >= 1
		if not force and isMax == state.isMax and now - state.lastPublish < config.PublishInterval then
			return
		end
		if isMax and not state.isMax then
			local anchor = nearestAnchor(state.part.Position)
			state.player:SetAttribute(config.PlayerScaleAnchorAttribute, anchor)
		end
		state.isMax = isMax
		state.lastPublish = now

		local part: BasePart = state.part
		local player: Player = state.player
		-- Rounded so the attributes do not replicate float noise; the server keeps the exact value.
		local fraction = math.round(state.fraction * 1000) / 1000
		local metres = math.round(rules.sizeMetres(state.zone, state.fraction) * 100) / 100
		local sent = state.sentPart

		setOn(part, sent, config.ZoneAttribute, state.zone)
		setOn(part, sent, config.SizeFractionAttribute, fraction)
		setOn(part, sent, config.VisualDiameterAttribute, part.Size.X)
		setOn(part, sent, config.SizeMetresAttribute, metres)
		setOn(part, sent, config.IsMaxAttribute, isMax)

		local sentPlayer = state.sentPlayer
		setOn(player, sentPlayer, config.PlayerSizeMetresAttribute, metres)
		setOn(player, sentPlayer, config.PlayerSizeFractionAttribute, fraction)
		setOn(player, sentPlayer, config.PlayerIsMaxAttribute, isMax)

		if diagnostics then
			publishDiagnostics(state, part)
		end
	end

	return table.freeze({ publish = publish })
end

return table.freeze(BallAttributesModule)

--!strict
-- Temporary probe for testing the playtester workflow. Not meant to be merged.

print("PROBE_READY")

local probe = Instance.new("Part")
probe.Name = "ProbeBlock"
probe.Anchored = true
probe.Position = Vector3.new(0, 10, 0)
probe.BrickColor = BrickColor.new("Bright blue")
probe.Parent = workspace

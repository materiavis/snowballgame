--!strict
-- Following pets (#41 AC4, AC6, ADR 0013): the formation behind the character, frame-rate
-- independent smoothing, the snap after a teleport, ground height, the follow roles (Simulator
-- only, never the Arena) and source checks that keep foreign pets simplified (R2).

local fs = require("@lune/fs")
local T = require("../../../TestKit")
local PetsConfig = require("../../../../src/shared/Config/Pets")
local PetFormation = require("../../../../src/places/social/client/PetFollowController/PetFormation")

local follow = PetsConfig.Follow

return T.suite("PetFollowController (7.9, R2, ADR 0013)", function(test)
	test("pets stand side by side behind the character, centred", function()
		local x1, z1 = PetFormation.offset(1, 1, follow)
		T.equal(x1, 0)
		T.equal(z1, follow.BackDistance, "one pet straight behind")
		local a = PetFormation.offset(1, 3, follow)
		local b = PetFormation.offset(2, 3, follow)
		local c = PetFormation.offset(3, 3, follow)
		T.equal(a, -follow.Spacing)
		T.equal(b, 0)
		T.equal(c, follow.Spacing)
		local _, z4 = PetFormation.offset(4, 4, follow)
		T.equal(z4, follow.BackDistance + follow.RowDepth, "a fourth pet starts the next row")
		T.equal((PetFormation.offset(4, 4, follow)), 0, "alone in its row, centred")
	end)

	test("smoothing is frame-rate independent and snaps after a teleport", function()
		local once = PetFormation.alpha(0.1, follow.Sharpness)
		local half = PetFormation.alpha(0.05, follow.Sharpness)
		T.near(1 - (1 - half) * (1 - half), once, 1e-12, "two half steps = one full step")
		T.equal(PetFormation.alpha(0, follow.Sharpness), 0)
		T.isTrue(PetFormation.shouldSnap(follow.SnapDistance + 1, follow))
		T.equal(PetFormation.shouldSnap(follow.SnapDistance - 1, follow), false)
	end)

	test("pets sit on the ground under the character", function()
		-- Root centre at 5, root 2 high, HipHeight 2: ground at 2; a 2-stud pet centres at 3.
		T.equal(PetFormation.height(5, 1, 2, 2), 3)
	end)

	test("pets follow in the Simulator only (Lobby #103, never the Arena)", function()
		T.equal(follow.Roles.Simulator, true)
		T.equal(follow.Roles.Lobby, nil)
		T.equal(follow.Roles.Arena, nil)
		local arena = fs.readFile("places/arena.project.json")
		T.equal(string.find(arena, "places/social", 1, true), nil, "the Arena does not mount the social folder")
	end)

	test("AC6 R2: foreign pets are one part, without label, at a lower rate", function()
		T.isTrue(follow.ForeignUpdateRate < 60, "below the frame rate")
		T.isTrue(follow.ForeignMaxDistance > 0)
		local models = fs.readFile("src/places/social/client/PetFollowController/PetModels.luau")
		local simplified = string.match(models, "if options.simplified then(.-)\n\tend") :: string
		T.isTrue(simplified ~= nil, "a simplified branch exists")
		local _, parts = string.gsub(simplified, "ball%(", "")
		T.equal(parts, 1, "one part")
		T.equal(string.find(simplified, "BillboardGui", 1, true), nil, "no label")
		local controller = fs.readFile("src/places/social/client/PetFollowController/init.luau")
		T.isTrue(
			string.find(controller, "follow.ForeignUpdateRate", 1, true) ~= nil,
			"foreign groups use the lower rate"
		)
		T.isTrue(string.find(controller, "follow.ForeignMaxDistance", 1, true) ~= nil, "and hide far away")
		T.equal(string.find(controller, "FireServer", 1, true), nil, "following sends nothing")
	end)
end)

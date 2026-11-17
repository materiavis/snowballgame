--!strict
-- Find display (#40, concept 7.7, 8.5, ADR 0016): the client accepts only catalogue finds and
-- valid slots, spreads the finds stuck in the ball over its surface, sizes them with the ball,
-- and shows every rarity with its colour and stars or crown (never colour alone). Source checks:
-- no part is created (nothing local can collide), and a sale clears the ball's finds.

local fs = require("@lune/fs")
local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local NetConfig = require("../../../../src/shared/Config/Net")
local FindView = require("../../../../src/places/simulator/client/FindController/FindView")

local Finds = E.Config.Finds
local Visual = Finds.Visual
local CONTROLLER = "src/places/simulator/client/FindController/init.luau"

local function code(path: string): string
	local lines = {}
	for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

return T.suite("FindController view (7.7, 8.5)", function(test)
	test("only catalogue finds and whole slots in range are accepted", function()
		T.isTrue(FindView.isFind(Finds, "PineCone"))
		T.isTrue(FindView.isFind(Finds, "YetiFootprint"))
		T.equal(FindView.isFind(Finds, "Diamond"), false)
		T.equal(FindView.isFind(Finds, 5), false)
		T.isTrue(FindView.isSlot(NetConfig.Finds, 1))
		T.equal(FindView.isSlot(NetConfig.Finds, 0), false)
		T.equal(FindView.isSlot(NetConfig.Finds, 2.5), false)
		T.equal(FindView.isSlot(NetConfig.Finds, 0 / 0), false)
		T.equal(FindView.isSlot(NetConfig.Finds, NetConfig.Finds.MaxSlot + 1), false)
		T.equal(FindView.isSlot(NetConfig.Finds, "3"), false)
	end)

	test("AC4: finds in the ball sit on its surface, at distinct places spread round it", function()
		local count = Visual.MaxInBall
		local seen: { [string]: boolean } = {}
		local up, down = 0, 0
		for index = 1, count do
			local d = FindView.inBallDirection(index, count)
			T.near(d.x * d.x + d.y * d.y + d.z * d.z, 1, 1e-9, `unit length {index}`)
			local key = string.format("%.4f,%.4f,%.4f", d.x, d.y, d.z)
			T.equal(seen[key], nil, `place {index} is free`)
			seen[key] = true
			if index <= 6 then
				if d.y > 0 then
					up += 1
				else
					down += 1
				end
			end
		end
		T.isTrue(up > 0 and down > 0, "the first finds already go round the ball, not only on top")
		T.equal(FindView.shownInBall(Visual, 3), 3)
		T.equal(FindView.shownInBall(Visual, 500), Visual.MaxInBall, "drawn up to MaxInBall; all still count")
		T.equal(FindView.shownInBall(Visual, -1), 0)
	end)

	test("AC4: a find in the ball grows with the ball, within its stud limits", function()
		T.equal(FindView.inBallSize(Visual, 1), Visual.InBallMinStuds)
		T.near(FindView.inBallSize(Visual, 8), 8 * Visual.InBallShare, 1e-12)
		T.equal(FindView.inBallSize(Visual, 1000), Visual.InBallMaxStuds)
		local height = FindView.billboardHeight(Visual, 2)
		T.near(height * (1 - Visual.SymbolHeightShare), 2, 1e-12, "the disc keeps its size above the stars")
	end)

	test("8.5: every find's rarity has a colour and stars or a crown", function()
		local stars = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
		for id, item in Finds.Items do
			local info = E.Rarity.get(item.Rarity)
			T.isTrue(info.symbol ~= "", `{id} has a symbol`)
			T.equal(#info.rgb, 3, `{id} has a colour`)
			if stars[item.Rarity] then
				T.equal(info.stars, stars[item.Rarity], `{id} stars`)
			else
				T.equal(info.symbol, "👑", "the secret find shows the crown")
			end
		end
	end)

	test("the controller draws billboards, never parts, and only for its own player", function()
		local source = code(CONTROLLER)
		T.equal(string.find(source, 'Instance.new("Part")', 1, true), nil, "no part")
		T.equal(string.find(source, 'Instance.new("MeshPart")', 1, true), nil)
		T.isTrue(string.find(source, 'Instance.new("BillboardGui")', 1, true) ~= nil)
		T.isTrue(string.find(source, "attachment.Parent = Workspace.Terrain", 1, true) ~= nil)
		T.isTrue(string.find(source, "symbol.Text = info.symbol", 1, true) ~= nil, "stars or crown")
		T.isTrue(string.find(source, "disc.BackgroundColor3 = colour", 1, true) ~= nil, "and the colour")
		T.isTrue(string.find(source, "gui.MaxDistance = Visual.MaxDistance", 1, true) ~= nil)
		T.isTrue(
			string.find(source, "child:GetAttribute(BallConfig.OwnerAttribute) == player.UserId", 1, true) ~= nil,
			"finds in the ball only on the own ball"
		)
		T.isTrue(string.find(source, 'action == "ClearBall" then\n\t\tballFinds = {}', 1, true) ~= nil, "sale")
	end)
end)

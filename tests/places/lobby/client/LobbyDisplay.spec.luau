--!strict
-- Lobby client display rules (issue #37; ADR 0015): the portal boards and the countdown
-- (PortalText), the news board (NewsText) and the ground arrow path (ArrowPath).

local T = require("../../../TestKit")
local Economy = require("../../../helpers/Economy")
local Ui = require("../../../../src/shared/Config/Ui")
local ArrowPath = require("../../../../src/places/lobby/client/GuideArrowController/ArrowPath")
local NewsText = require("../../../../src/places/lobby/client/NewsBoardController/NewsText")
local PortalText = require("../../../../src/places/lobby/client/PortalController/PortalText")

local formatNumber = Economy.NumberFormat.number

return T.suite("Lobby display (7.1)", function(test)
	test("portal boards: mode name, Coming soon on the closed one, server count", function()
		local single = PortalText.label("Singleplayer", 12, false, Ui.Text, formatNumber)
		T.equal(single.title, "Singleplayer")
		T.equal(single.status, nil)
		T.equal(single.players, "12 playing")
		local multi = PortalText.label("Multiplayer", 0, true, Ui.Text, formatNumber)
		T.equal(multi.title, "Multiplayer")
		T.equal(multi.status, "Coming soon")
		T.equal(multi.players, "0 playing")
		T.equal(PortalText.label("Singleplayer", 1500, false, Ui.Text, formatNumber).players, "1.5K playing")
		for _, bad in { -1, 0.5, 0 / 0, "7", nil } do
			T.equal(
				PortalText.label("Singleplayer", bad, false, Ui.Text, formatNumber).players,
				"0 playing",
				tostring(bad)
			)
		end
	end)

	test("countdown shows 3, 2, 1 and never 0 while it runs", function()
		T.equal(PortalText.secondsShown(103, 100), 3)
		T.equal(PortalText.secondsShown(103, 100.01), 3)
		T.equal(PortalText.secondsShown(103, 101), 2)
		T.equal(PortalText.secondsShown(103, 102.5), 1)
		T.equal(PortalText.secondsShown(103, 102.999), 1)
		T.equal(PortalText.secondsShown(103, 103), 0)
	end)

	test("status lines for Closed, Locked and Travelling only", function()
		T.equal(PortalText.status("Closed", Ui.Text), "Coming soon")
		T.equal(PortalText.status("Locked", Ui.Text), Ui.Text.PortalLocked)
		T.equal(PortalText.status("Travelling", Ui.Text), Ui.Text.PortalTravelling)
		for _, state in { "Idle", "Countdown", "WaitExit", "Busy", nil, 3 } do
			T.equal(PortalText.status(state, Ui.Text), nil, tostring(state))
		end
	end)

	test("news board: latest update and a countdown to the next", function()
		T.equal(NewsText.countdown(0), "00:00:00")
		T.equal(NewsText.countdown(0.2), "00:00:01")
		T.equal(NewsText.countdown(3661), "01:01:01")
		T.equal(NewsText.countdown(2 * 86400 + 5), "2d 00:00:05")
		local lines = NewsText.lines(Ui.Text, "Vertical Slice", 1000 + 90, 1000)
		T.equal(lines.title, "News")
		T.equal(lines.last, "Latest update: Vertical Slice")
		T.equal(lines.next, "Next update in 00:01:30")
		T.equal(NewsText.lines(Ui.Text, "X", 0, 1000).next, "Next update: coming soon", "no date yet")
		T.equal(NewsText.lines(Ui.Text, "X", 999, 1000).next, "Next update: coming soon", "date passed")
		T.equal(NewsText.lines(Ui.Text, "100% {fun}", 0, 1000).last, "Latest update: 100% {fun}", "title kept as is")
	end)

	test("arrow: chevrons between spawn and portal, facing the portal", function()
		local chevrons = ArrowPath.chevrons(0, 0, 0, -45, 6, 5)
		T.isTrue(#chevrons >= 5, `got {#chevrons}`)
		T.near(chevrons[1].z, -5, 1e-9, "starts after the gap")
		T.isTrue(chevrons[#chevrons].z >= -40 - 1e-9, "stops before the portal")
		for _, chevron in chevrons do
			-- CFrame.Angles(0, yaw, 0).LookVector = (-sin yaw, 0, -cos yaw) must point at -z.
			T.near(-math.sin(chevron.yaw), 0, 1e-9)
			T.near(-math.cos(chevron.yaw), -1, 1e-9)
		end
		local left = ArrowPath.chevrons(0, 0, -14, -45, 6, 5)[1]
		local length = math.sqrt(14 * 14 + 45 * 45)
		T.near(-math.sin(left.yaw), -14 / length, 1e-9, "turned towards the left portal")
		T.equal(#ArrowPath.chevrons(0, 0, 0, -8, 6, 5), 0, "too short for the gaps")
		T.equal(#ArrowPath.chevrons(0, 0, 0, -45, 0, 5), 0, "bad spacing")
	end)

	test("every Lobby text key exists", function()
		for _, key in
			{
				"PortalSingleplayer",
				"PortalMultiplayer",
				"PortalPlayers",
				"PortalClosed",
				"PortalLocked",
				"PortalTravelling",
				"GroupChestAction",
				"GroupChestObject",
				"NewsTitle",
				"NewsLastUpdate",
				"NewsNextUpdate",
				"NewsNextUpdateSoon",
				"VipCornerSign",
			}
		do
			T.equal(type((Ui.Text :: any)[key]), "string", key)
		end
	end)
end)

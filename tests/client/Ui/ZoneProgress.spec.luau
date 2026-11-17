--!strict
-- #90 AC7: the progress bar shows ball size / zone maximum and the zone name, only from the
-- server's BallSizeMetres and BallZone attributes and the shared zone formula. Unknown values
-- show placeholders, never an error.

local T = require("../../TestKit")
local E = require("../../helpers/Economy")
local ZoneProgress = require("../../../src/client/Ui/ZoneProgress")
local Ui = require("../../../src/shared/Config/Ui") :: any
local ZonesConfig = require("../../../src/shared/Config/Zones") :: any

local zones = E.Zones
local size = E.NumberFormat.size
local NAMES = ZonesConfig.Names

return T.suite("Ui ZoneProgress (#90)", function(test)
	test("zone names are the ten Startwerte of the concept appendix", function()
		local expected = {
			"Snowline",
			"Pine Forest",
			"Alpine Hut",
			"Mountain Lake",
			"Rocky Ridge",
			"Ski Slope",
			"Avalanche Slope",
			"Glacier Edge",
			"Glacier",
			"Summit",
		}
		T.equal(#NAMES, #expected)
		for index, zoneName in expected do
			T.equal(NAMES[index], zoneName, `zone {index}`)
		end
	end)

	test("fraction is size over the zone maximum of that zone", function()
		T.near(ZoneProgress.fraction(1, 1, zones) :: number, 1 / zones.maxSize(1), 1e-9)
		T.near(ZoneProgress.fraction(zones.maxSize(3) / 2, 3, zones) :: number, 0.5, 1e-9)
		T.equal(ZoneProgress.fraction(zones.maxSize(5), 5, zones), 1)
		T.equal(ZoneProgress.fraction(0, 2, zones), 0)
	end)

	test("fraction stays within 0..1 even if the size runs past the maximum", function()
		T.equal(ZoneProgress.fraction(zones.maxSize(1) * 3, 1, zones), 1)
	end)

	test("unknown size or zone gives no fraction", function()
		for _, case in
			{
				{ nil, 1 },
				{ "2", 1 },
				{ -1, 1 },
				{ 0 / 0, 1 },
				{ math.huge, 1 },
				{ 1, nil },
				{ 1, 0 },
				{ 1, 51 },
				{ 1, 1.5 },
				{ 1, "1" },
			}
		do
			T.equal(ZoneProgress.fraction(case[1], case[2], zones), nil, `{tostring(case[1])}, {tostring(case[2])}`)
		end
	end)

	test("bar text reads 'size / maximum' in m and km", function()
		T.equal(ZoneProgress.barText(1.23, 1, zones, size, Ui), `{size(1.23)} / {size(zones.maxSize(1))}`)
		local big = zones.maxSize(40)
		T.isTrue(string.find(ZoneProgress.barText(big, 40, zones, size, Ui), "km", 1, true) ~= nil, "km at zone 40")
	end)

	test("bar text is the placeholder while size or zone is unknown", function()
		T.equal(ZoneProgress.barText(nil, 1, zones, size, Ui), Ui.Text.ProgressPlaceholder)
		T.equal(ZoneProgress.barText(1, nil, zones, size, Ui), Ui.Text.ProgressPlaceholder)
		T.equal(ZoneProgress.barText(1, 99, zones, size, Ui), Ui.Text.ProgressPlaceholder)
	end)

	test("zone name for zones 1..10, placeholder for zones without a name and invalid zones", function()
		T.equal(ZoneProgress.zoneName(1, NAMES, zones, Ui), "Snowline")
		T.equal(ZoneProgress.zoneName(10, NAMES, zones, Ui), "Summit")
		T.equal(ZoneProgress.zoneName(11, NAMES, zones, Ui), Ui.Text.ZoneNamePlaceholder)
		for _, zone in { nil, 0, -1, 2.5, "3", 51, 0 / 0 } :: { any } do
			T.equal(ZoneProgress.zoneName(zone, NAMES, zones, Ui), Ui.Text.ZoneNamePlaceholder, tostring(zone))
		end
	end)
end)

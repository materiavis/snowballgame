--!strict
-- #90 AC6: a pop-up shows and hides again after Config.Ui.Popup.DurationSeconds; pop-ups that
-- arrive meanwhile wait in order, at most MaxQueued.

local T = require("../../TestKit")
local PopupQueue = require("../../../src/client/Ui/PopupQueue")
local Ui = require("../../../src/shared/Config/Ui") :: any

local DURATION = Ui.Popup.DurationSeconds

return T.suite("Ui PopupQueue (#90)", function(test)
	test("config: a short pop-up with a small queue", function()
		T.isTrue(DURATION > 0 and DURATION <= 5, "duration in seconds")
		T.isTrue(Ui.Popup.MaxQueued >= 0, "queue size")
	end)

	test("shows at once and hides after the duration", function()
		local queue = PopupQueue.new(DURATION, Ui.Popup.MaxQueued)
		T.equal(queue.current(0), nil)
		T.equal(queue.push("MAX!", 10), true)
		T.equal(queue.current(10), "MAX!")
		T.equal(queue.current(10 + DURATION - 0.01), "MAX!")
		T.equal(queue.endsAt(), 10 + DURATION)
		T.equal(queue.current(10 + DURATION), nil)
		T.equal(queue.endsAt(), nil)
	end)

	test("a second pop-up waits and then gets its full time", function()
		local queue = PopupQueue.new(2, 3)
		queue.push("a", 0)
		T.equal(queue.push("b", 1), false)
		T.equal(queue.current(1.5), "a")
		T.equal(queue.current(2), "b")
		T.equal(queue.current(3.9), "b")
		T.equal(queue.current(4), nil)
	end)

	test("at most MaxQueued wait; the oldest waiting one is dropped", function()
		local queue = PopupQueue.new(1, 2)
		queue.push("a", 0)
		queue.push("b", 0)
		queue.push("c", 0)
		queue.push("d", 0)
		T.equal(queue.waiting(), 2)
		T.equal(queue.current(0), "a")
		T.equal(queue.current(1), "c")
		T.equal(queue.current(2), "d")
		T.equal(queue.current(3), nil)
	end)

	test("a long gap expires everything at once", function()
		local queue = PopupQueue.new(1, 3)
		queue.push("a", 0)
		queue.push("b", 0)
		T.equal(queue.current(100), "b", "b appears when checked")
		T.equal(queue.current(101), nil)
	end)

	test("bad arguments fail loudly", function()
		T.throws(function()
			PopupQueue.new(0, 1)
		end, "duration")
		T.throws(function()
			PopupQueue.new(1, 1.5)
		end, "maxQueued")
	end)
end)

--!strict
-- Minimal test registration and assertions for headless Lune runs.
-- Kept dependency-free so the harness has nothing to pin beyond Lune itself.

export type TestFn = () -> ()
export type Test = { name: string, fn: TestFn }
export type Suite = { name: string, tests: { Test } }

local TestKit = {}

-- Strings are quoted so "1" and 1 stay distinguishable in failure messages.
local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function prefix(label: string?): string
	if label then
		return label .. ": "
	end
	return ""
end

-- A spec module returns the value of this call; the runner rejects anything else so a
-- spec that forgot to return its suite fails loudly instead of silently running nothing.
function TestKit.suite(name: string, body: (test: (name: string, fn: TestFn) -> ()) -> ()): Suite
	local tests: { Test } = {}
	body(function(testName: string, fn: TestFn)
		table.insert(tests, { name = testName, fn = fn })
	end)
	return table.freeze({ name = name, tests = table.freeze(tests) })
end

function TestKit.isSuite(value: any): boolean
	return type(value) == "table" and type(value.name) == "string" and type(value.tests) == "table"
end

-- Level 3 points the error at the line in the spec that called the assertion.
function TestKit.equal(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{prefix(label)}expected {show(expected)}, got {show(actual)}`, 3)
	end
end

function TestKit.near(actual: number, expected: number, tolerance: number, label: string?)
	if actual ~= actual or math.abs(actual - expected) > tolerance then
		error(`{prefix(label)}expected {expected} +/- {tolerance}, got {actual}`, 3)
	end
end

function TestKit.isTrue(condition: any, label: string?)
	if not condition then
		error(`{prefix(label)}expected a truthy value, got {show(condition)}`, 3)
	end
end

-- Returns the error message so a test can assert on why something failed.
function TestKit.throws(fn: () -> (), pattern: string?, label: string?): string
	local ok, err = pcall(fn)
	if ok then
		error(`{prefix(label)}expected an error, but the call succeeded`, 3)
	end
	local message = tostring(err)
	if pattern and not string.find(message, pattern) then
		error(`{prefix(label)}error {show(message)} does not match {show(pattern)}`, 3)
	end
	return message
end

return table.freeze(TestKit)

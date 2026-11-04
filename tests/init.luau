--!strict
-- Headless test runner: `lune run tests [filter]` from the repository root.
-- Finds every *.spec.luau under tests/, runs each test and exits non-zero on any failure
-- so CI fails. Zero discovered tests is also a failure: a broken discovery must not look green.

local fs = require("@lune/fs")
local process = require("@lune/process")

local TestKit = require("@self/TestKit")

local TESTS_DIR = "tests"
local SPEC_SUFFIX = ".spec.luau"

-- Discovery and requires use paths relative to the repo root, so refuse to guess elsewhere.
if not (fs.isDir(TESTS_DIR) and fs.isFile("rokit.toml")) then
	print("Run the tests from the repository root: lune run tests")
	process.exit(2)
end

local function collectSpecs(relativeDir: string, out: { string })
	local fullDir = if relativeDir == "" then TESTS_DIR else `{TESTS_DIR}/{relativeDir}`
	for _, entry in fs.readDir(fullDir) do
		local relativePath = if relativeDir == "" then entry else `{relativeDir}/{entry}`
		if fs.isDir(`{TESTS_DIR}/{relativePath}`) then
			collectSpecs(relativePath, out)
		elseif string.sub(entry, -#SPEC_SUFFIX) == SPEC_SUFFIX then
			table.insert(out, relativePath)
		end
	end
end

local filter: string? = process.args[1]

local specs: { string } = {}
collectSpecs("", specs)
-- readDir order is platform-dependent; sorting keeps output identical locally and in CI.
table.sort(specs)

local passed, failed = 0, 0
local failures: { string } = {}
local startedAt = os.clock()

local function fail(name: string, message: string)
	failed += 1
	table.insert(failures, `{name}\n    {message}`)
	print(`FAIL  {name}`)
end

for _, specPath in specs do
	if filter and not string.find(specPath, filter, 1, true) then
		continue
	end

	local modulePath = "@self/" .. string.sub(specPath, 1, -#".luau" - 1)
	local loaded, suite = pcall(require, modulePath)
	if not loaded then
		fail(specPath, `could not load: {suite}`)
		continue
	end
	if not TestKit.isSuite(suite) then
		fail(specPath, "spec must return TestKit.suite(...)")
		continue
	end

	for _, test in suite.tests do
		local name = `{suite.name} > {test.name}`
		local testStart = os.clock()
		local ok, err = xpcall(test.fn, debug.traceback)
		if ok then
			passed += 1
			print(string.format("PASS  %s (%.0f ms)", name, (os.clock() - testStart) * 1000))
		else
			fail(name, tostring(err))
		end
	end
end

for _, failure in failures do
	print(`\n--- {failure}`)
end

local total = passed + failed
print(string.format("\n%d passed, %d failed, %d total in %.2f s", passed, failed, total, os.clock() - startedAt))

if total == 0 then
	print("No tests ran. Check the filter or the tests/ layout.")
	process.exit(1)
end
process.exit(if failed > 0 then 1 else 0)

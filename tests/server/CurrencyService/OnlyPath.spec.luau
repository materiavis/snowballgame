--!strict
-- CurrencyService is the only code that writes balances (issue #27 goal, ADR 0007). Checked
-- as text, like the DataStoreService check of ADR 0006: no file under src/ outside
-- CurrencyService assigns to a currency field. Schema defaults (`coins = 0,` in a table
-- constructor) are not assignments to a profile and are allowed.

local fs = require("@lune/fs")
local T = require("../../TestKit")

local ALLOWED_DIR = "src/server/Services/CurrencyService/"
local FIELDS = { "coins", "totalCoins", "snowCoins" }

local function collect(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.sub(entry, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

-- `.coins =`, `.coins +=`, `["coins"] =` and friends; `==` is a comparison, not a write.
local function writesField(line: string, field: string): boolean
	local patterns = {
		`%.{field}%s*[%+%-%*/]?=[^=]`,
		`%[%s*"{field}"%s*%]%s*[%+%-%*/]?=[^=]`,
	}
	for _, pattern in patterns do
		if string.find(line .. " ", pattern) then
			return true
		end
	end
	return false
end

return T.suite("CurrencyService is the only balance writer", function(test)
	test("the scanner sees the forms a write can take", function()
		T.isTrue(writesField("profile.sim.coins = 5", "coins"))
		T.isTrue(writesField("data.sim.totalCoins += amount", "totalCoins"))
		T.isTrue(writesField('fight["snowCoins"] = 0', "snowCoins"))
		T.equal(writesField("if profile.sim.coins == 0 then", "coins"), false)
		T.equal(writesField("coins = 0, -- default", "coins"), false)
	end)

	test("no module outside CurrencyService writes coins, totalCoins or snowCoins", function()
		local files = {}
		collect("src", files)
		T.isTrue(#files > 10, "found the source files")
		local offenders = {}
		for _, path in files do
			if string.sub(path, 1, #ALLOWED_DIR) ~= ALLOWED_DIR then
				local lineNumber = 0
				for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
					lineNumber += 1
					for _, field in FIELDS do
						if writesField(line, field) then
							table.insert(offenders, `{path}:{lineNumber}`)
						end
					end
				end
			end
		end
		T.equal(table.concat(offenders, ", "), "")
	end)
end)

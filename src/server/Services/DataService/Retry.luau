--!strict
-- Retries a store call that throws, with exponential backoff. DataStore errors are mostly
-- transient (throttling, outages), so a few spaced attempts beat failing on the first one.
-- Pure: the wait function is injected (task.wait live, a fake clock in tests).

export type Settings = {
	StoreAttempts: number,
	BackoffBase: number,
	BackoffFactor: number,
	BackoffMax: number,
}

export type Retry = {
	-- Runs fn until it returns without throwing. Returns true and fn's result, or false and the
	-- last error after StoreAttempts calls.
	run: (fn: () -> any) -> (boolean, any),
	delayFor: (attempt: number) -> number,
}

local Retry = {}

function Retry.new(settings: Settings, wait: (seconds: number) -> ()): Retry
	assert(settings.StoreAttempts >= 1, "Retry: StoreAttempts must be at least 1")

	local function delayFor(attempt: number): number
		return math.min(settings.BackoffBase * settings.BackoffFactor ^ (attempt - 1), settings.BackoffMax)
	end

	local function run(fn: () -> any): (boolean, any)
		local lastError: any = nil
		for attempt = 1, settings.StoreAttempts do
			local ok, result = pcall(fn)
			if ok then
				return true, result
			end
			lastError = result
			if attempt < settings.StoreAttempts then
				wait(delayFor(attempt))
			end
		end
		return false, lastError
	end

	return table.freeze({ run = run, delayFor = delayFor })
end

return table.freeze(Retry)

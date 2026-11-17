--!strict
-- Binds the pet and egg cores to the real Config, the way PetService and EggService do in Roblox:
-- the real catalogue, Formulas.Pets, Rng odds and CurrencyCore. `on(getProfile, options)` builds
-- one game; specs pass DataCore.getData from the DataService harness or a plain profile table.

local E = require("./Economy")
local FakeClock = require("./FakeClock")
local SeededRandom = require("./SeededRandom")
local CurrencyConfig = require("../../src/shared/Config/Currency")
local DataConfig = require("../../src/shared/Config/Data")
local EggsConfig = require("../../src/shared/Config/Eggs")
local NetConfig = require("../../src/shared/Config/Net")
local Catalogue = require("../../src/shared/PetCatalogue/Catalogue")
local CurrencyCore = require("../../src/server/Services/CurrencyService/CurrencyCore")
local PetCore = require("../../src/places/social/server/PetService/PetCore")
local EggCore = require("../../src/places/simulator/server/EggService/EggCore")

local catalogue = Catalogue.new(E.Config.Pets :: any, EggsConfig :: any, E.Config.Rarity.Order, E.Pets.petBonus)

export type Options = {
	seed: number?,
	clock: FakeClock.FakeClock?,
	forced: (() -> string?)?,
	bonusOf: ((record: any) -> number?)?,
	slotsPass: boolean?,
}

export type Game = {
	currency: any,
	pets: PetCore.Core,
	eggs: EggCore.Core,
	clock: FakeClock.FakeClock,
	petEvents: { any },
	eggEvents: { any },
}

local Pets = {}

Pets.Catalogue = catalogue
Pets.EggsConfig = EggsConfig

function Pets.on(getProfile: (userId: number) -> any, options: Options?): Game
	local opts = options or {}
	local clock = opts.clock or FakeClock.new(100)
	local generator = SeededRandom.new(opts.seed or 41)
	local serial = 0
	local currency = CurrencyCore.new({ config = CurrencyConfig :: any, getProfile = getProfile, log = function() end })
	local pets = PetCore.new({
		catalogue = {
			isKind = catalogue.isKind,
			bonusOf = opts.bonusOf or catalogue.bonusOf,
		},
		formulas = E.Pets,
		defaultInventorySize = DataConfig.InventorySize,
		maxUidLength = NetConfig.Pets.MaxUidLength,
		getProfile = getProfile,
		newUid = function(userId: number): string
			serial += 1
			return string.format("%d_%x_%04x", userId, 1_700_000_000, serial)
		end,
		hasSlotsPass = function()
			return opts.slotsPass == true
		end,
		log = function() end,
	})
	local eggs = EggCore.new({
		config = EggsConfig :: any,
		catalogue = catalogue,
		eggCount = E.Pets.eggCount,
		eggPrice = E.Pets.eggPrice,
		eggOdds = E.Odds.eggOdds,
		pick = E.Weighted.pick,
		generator = generator,
		now = clock.now,
		forcedRarity = opts.forced or function()
			return nil
		end,
		hasRoom = pets.hasRoom,
		addPet = pets.add,
		spendCoins = function(userId: number, amount: number, reason: string)
			return currency.spend(userId, "Coins", amount, reason)
		end,
		log = function() end,
	})
	local game: Game = {
		currency = currency,
		pets = pets,
		eggs = eggs,
		clock = clock,
		petEvents = {},
		eggEvents = {},
	}
	pets.subscribe(function(event)
		table.insert(game.petEvents, event)
	end)
	eggs.subscribe(function(event)
		table.insert(game.eggEvents, event)
	end)
	return game
end

return table.freeze(Pets)

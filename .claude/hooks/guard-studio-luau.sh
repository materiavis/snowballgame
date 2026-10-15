#!/usr/bin/env bash
# PreToolUse-Hook für mcp__Roblox_Studio__execute_luau (Playtester).
# Blockt Luau-Code mit Netzwerk, DataStore-Schreibzugriffen, Publish, Käufen, Teleports
# und Änderungen am Place. Exit 2 = blockieren, stderr geht an den Agent zurück.
# Läuft in Git Bash, braucht kein jq.

input="$(cat)"

deny() {
  echo "Blockiert vom Playtester-Hook: $1. execute_luau ist nur zum Lesen von Zustand erlaubt." >&2
  exit 2
}

check() {
  # $1 = Regex (case-insensitive), $2 = Grund
  if printf '%s' "$input" | grep -Eiq "$1"; then deny "$2"; fi
}

# Netzwerk
check 'HttpService|HttpGet|HttpPost|RequestAsync|GetAsync\(|PostAsync\(|loadstring' 'HTTP / dynamischer Code'
# DataStores / persistente Daten
check 'DataStoreService|MemoryStoreService|SetAsync|UpdateAsync|IncrementAsync|RemoveAsync|OrderedDataStore' 'DataStore-Zugriff'
# Publish / Speichern / Assets
check 'SavePlace|PublishAsync|AssetService|InsertService|LoadAsset|CreatePlaceAsync' 'Publish / Asset-Laden'
# Käufe
check 'MarketplaceService|PromptPurchase|PromptProductPurchase|PromptGamePassPurchase|ProcessReceipt' 'Käufe'
# Teleports
check 'TeleportService|TeleportAsync|:Teleport\(' 'Teleport'
# Place verändern (nur Lesen erlaubt)
check 'Instance\.new|:Destroy\(|:Clone\(|:ClearAllChildren\(|\.Parent[[:space:]]*=|\.Source[[:space:]]*=|ChangeHistoryService|require\([[:space:]]*[0-9]' 'Änderung am Place / externes require'

exit 0
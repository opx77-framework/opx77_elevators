resource "opx77_elevators"
version "0.2.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "local" -- no CEF surface; the server re-adopts from the next client sighting

shared_script "config.lua"
shared_script "shared/access.lua"

server_script "server/main.lua"

client_script "client/state.lua"
client_script "client/main.lua"
client_script "client/panel.lua"
client_script "client/exports.lua"

permissions {
  "network.events",
  "world.elevators", -- adopt a native lift, lock it, and move the cabin
  "elevators.read",
}

--- @author DemiAutomatic
--- @file open77.lua
--- @description Resource manifest declaring scripts, permissions and reload policy.

resource "opx77_elevators"
version "0.4.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "local"

shared_script "config.lua"
shared_script "shared/text.lua"
shared_script "shared/locale.lua"
shared_script "locales/en.lua"
shared_script "locales/fr.lua"
shared_script "shared/access.lua"

server_script "server/main.lua"

client_script "client/state.lua"
client_script "client/main.lua"
client_script "client/panel.lua"
client_script "client/exports.lua"

permissions {
  "network.events",
  "world.elevators",
  "elevators.read",
  "acl.read",
}

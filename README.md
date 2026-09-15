# opx77_elevators

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time
> without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

> [!IMPORTANT]
> **The job check is a client-side hint: the Open77 server runtime has no cross-resource event
> bus, so this resource's server half cannot ask `opx77_core` for a job and cannot re-derive
> the check.**
>
> It re-derives everything else — the elevator, the floor, the player's position and routing
> bucket, the rate. Gate flavour on the job, never money or a body count; an unforgeable
> decision belongs in `opx77_core`'s server VM.

Job-gated in-world elevators for **Opx77**. A floor list on the lifts Night City already has,
with each floor opened or closed by the job a character holds in `opx77_core`.

An Arasaka executive floor, the NCPD holding level, a ripperdoc's back room: the jobs, the
grades and the wording all live in `config.lua`.

## Features

- Floors gated by job, grade and duty state, changing the instant a promotion lands
- A refused floor is greyed with the operator's own wording, or hidden entirely
- One panel for the whole shaft: an elevator is callable from every one of its own floors
- Native lifts adopted on sight and locked, so the cabin answers this resource alone
- The panel is `opx77_menu`'s, and optional — a missing menu costs one log line

## Exports

| Export | Does |
|---|---|
| `floors` | every floor at an elevator, each with whether the player may take it and why not |
| `isFloorAllowed` | would this floor be allowed? decides nothing and sends nothing |
| `requestFloor` | ask for a floor; the verdict arrives on the event |
| `openPanel` | open the floor list through `opx77_menu` |
| `nearestElevator` | which configured elevator the player is standing at |
| `state` | what this client knows: the job, how old the reading is, the lifts in range |

`floors` defaults to the elevator the player is standing at and returns its key, so a caller
drawing its own panel needs nothing else.

Every export answers a table carrying `ok` and never raises; the `error` codes are listed, with
the half that decides each, in `std/types.lua` (`ElevatorError`). `ok = true` from
`requestFloor` means asked: the server's verdict arrives on the local event named by `EVENT`.

## Commands

| Command | Gated |
|---|---|
| `opx77.elevators.where [key]` | ACL — each configured elevator: position, floors, adoption and the native lift's state |

The name is `COMMAND` in `config.lua`, and `false` registers nothing. Given a key it reports
that elevator alone. The report is a diagnostic dump, so it stays text: printed to the server
console, and sent to a player who ran it as chat lines, one per elevator, each through
`chat:addMessage` rather than `open77:command:result`, whose accepted answers `opx77_chat` does
not print. Its chat suggestion, with the configured keys as the argument's help, is
sent only to a player the ACL grants `command.<name>`; that read is why the manifest declares
`acl.read`, and a host without the ACL reader suggests it to nobody.

## Configuration

`config.lua`. Each elevator by a durable key: where the shaft is, how many floors the native
device has, and the stops this resource offers with their job requirements. Job names must exist
in `opx77_core/data/jobs.lua`; this resource cannot check them.

| Key | Default | Meaning |
|---|---|---|
| `LOCALE` | `"en"` | which `locales/*.lua` catalogue player-facing text is read from |
| `DENIED_FLOORS` | `"shown"` | floors the player cannot reach: `"shown"` greyed with their reason, or `"hidden"` |
| `MEMBERSHIP` | `"primary"` | `"primary"` reads the job being worked, `"any"` the whole membership map (grades only: duty is always the primary job's) |
| `JOB_MAX_AGE_MS` | `60000` | past this snapshot age every gated floor closes; public floors never do |
| `POLL_MS` | `15000` | how often the client re-reads the character from `opx77_core` |
| `SCAN_MS` | `2000` | how often the client looks for native lifts; a sighting is believed for two scans |
| `EVENT` | `"opx77:elevators"` | local client event raised after every decision |
| `MATCH_RADIUS` | `6.0` | metres, across the ground, a native lift may stand from a declared position |
| `USE_RADIUS` | `4.0` | metres, across the ground, the player may stand from it to use the panel |
| `SCAN_RADIUS` | `40.0` | metres from the player a client's sighting report is believed |
| `TRAVEL_MS` | `8000` | how long the cabin takes to travel |
| `REQUEST_WINDOW_MS` | `10000` | the rate limit window, per player |
| `REQUESTS_PER_WINDOW` | `6` | floor requests one player may make in that window |
| `COMMAND` | `"opx77.elevators.where"` | the ACL-gated diagnostic command, or `false` for none |
| `ELEVATORS` | four samples | elevator key -> definition, below |

Each `ELEVATORS` entry:

| Field | Meaning |
|---|---|
| `LABEL` | the panel title |
| `X`, `Y`, `Z` | where the shaft is; the shipped positions are placeholders, probe real ones with `open77:elevators:nearby` |
| `BUCKET` | routing bucket, `0` when omitted; an elevator in a bucket is invisible to players outside it |
| `ENTITY` | optional native lift hash (`"0x"` and 16 hex digits); pins which shaft a lift is when two stand close |
| `FLOOR_COUNT` | the native device's floor count, not the length of `FLOORS` |
| `FLOORS` | the stops offered, in panel order |
| `FLOORS[].INDEX` | the native floor index, 0-based |
| `FLOORS[].LABEL` | the row label |
| `FLOORS[].JOBS` | job name -> minimum grade level, e.g. `{ ncpd = 0 }`; a floor without `JOBS` is public |
| `FLOORS[].ON_DUTY` | also require the character to be on duty in that job |
| `FLOORS[].REASON` | shown beside a refused row |

An elevator's `X` and `Y` place the shaft and are the only pair a distance is measured on;
`Z` is recorded and never compared. `MATCH_RADIUS` decides which shaft a native lift is and
`USE_RADIUS` decides whether the player may work the panel, both across the ground and on both
halves — so one panel serves the whole shaft and a character on the twelfth storey is as close
to it as one in the lobby. A client that cannot read its own position falls back to the host's
3D distance to the cabin, which measures something else: it can offer the panel up to
`MATCH_RADIUS` further out than the server accepts, and withhold it on a floor the cabin is not
on. The server's answer is the one that counts.

Every radius and every timer in `config.lua` is checked at boot; one that is missing or is not
a positive number is named in a warning and read as zero, rather than raising mid-request.

Every adopted lift is locked with the host's own flag, so the elevator authority refuses a
request sent straight off a client and this resource is the only way the cabin moves.

## Architecture

Why the resource is written the way it is — the manifest order, what the server re-derives, how
adoption and the sweep work, and the known limits — is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (French). LuaLS types and stubs live in `std/`.

## Locales

Player-facing text lives in `locales/en.lua` and `locales/fr.lua`, keyed `elevators.<thing>`.
`LOCALE` in `config.lua` picks one; a key missing from it falls back to `en`, and then to the
key itself. Each resource carries its own catalogue, so this is set here as well as in
`opx77_core`.

To add a language, copy `locales/en.lua` to `locales/<code>.lua`, change the code in the
`register` call and translate the values — every key must be present in every file. Add
`shared_script "locales/<code>.lua"` to `open77.lua` beside the others, above every file that
renders a string, then set `LOCALE = "<code>"`.

A floor's `REASON` and `LABEL` in `config.lua` are the server owner's own words and are never
translated: a refused floor is shown with its `REASON` where there is one, and with this
resource's own wording only where there is not. `Open77.log` lines, the diagnostic command's report
and the error codes the exports return stay English; its chat suggestion is translated.

## Community & Support

Join the Open77 and Opx77 communities to discover the platform, share your projects, and
connect with other developers.

<!-- TODO: replace with the final URLs before publication. -->

* [Open77](#)
* [Open77 GitHub](#)
* [OPX Discord](#)

## License

opx77_elevators is licensed under the [**MIT License**](LICENSE).

Copyright © 2026 **Luis MOUTA**.

<p align="center">
    <sub>opx77_elevators is an independent community project and is not affiliated with or
    endorsed by CD PROJEKT RED.</sub>
</p>

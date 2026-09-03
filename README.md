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

## Configuration

`config.lua`. Each elevator by a durable key: where the shaft is, how many floors the native
device has, and the stops this resource offers with their job requirements.

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
resource's own wording only where there is not. `Open77.log` lines, the diagnostic command and
the error codes the exports return stay English.

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

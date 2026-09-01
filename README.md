# opx77_elevators

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

> [!IMPORTANT]
> **The job check on these elevators is a client-side hint, and no setting turns it into anything else.**
>
> The Open77 server runtime has no cross-resource event bus, so this resource's server half cannot ask `opx77_core` for a player's job. It re-derives everything else — the elevator, the floor, the player's position and routing bucket, the rate — but not the job.
>
> **Do not gate money, contraband or a body count on it.** Gate the flavour: which floor a lift stops at, which corridor a story happens in. A decision that has to be unforgeable belongs in `opx77_core`'s server VM, where the job is already in memory.

Job-gated in-world elevators for **Opx77**. A floor list on the lifts Night City already has, with each floor opened or closed by the job a character holds in `opx77_core`.

An Arasaka executive floor, the NCPD holding level, a ripperdoc's back room: the jobs, the grades and the wording all live in `config.lua`.

## Features

- Floors gated by job, grade and duty state, changing the instant a promotion lands
- A refused floor is greyed with the operator's own wording, or hidden entirely
- Native lifts adopted on sight and locked, so the cabin answers this resource alone
- The panel is `opx77_menu`'s, and optional — a missing menu costs one log line

## Exports

| Export | Does |
|---|---|
| `floors` | every floor at an elevator, each with whether the player may take it and why not |
| `use` | select a floor |
| `panel` | open the floor list through `opx77_menu` |

`floors` defaults to the elevator the player is standing at and returns its key, so a caller drawing its own panel needs nothing else.

## Configuration

`config.lua`. Each elevator by a durable key: where the shaft is, how many floors the native device has, and the stops this resource offers with their job requirements.

Every adopted lift is locked with the host's own flag, so the elevator authority refuses a request sent straight off a client and this resource is the only way the cabin moves.

## Community & Support

Join the Open77 and Opx77 communities to discover the platform, share your projects, and connect with other developers.

<!-- TODO: replace with the final URLs before publication. -->

* [Open77](#)
* [Open77 GitHub](#)
* [OPX Discord](#)

## License

opx77_elevators is licensed under the [**MIT License**](LICENSE).

Copyright © 2026 **Luis MOUTA**.

<p align="center">
    <sub>opx77_elevators is an independent community project and is not affiliated with or endorsed by CD PROJEKT RED.</sub>
</p>

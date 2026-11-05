# Changelog

## 0.1.0 (2026-11-04)

First release.

- Shows an icon with a cooldown sweep and a countdown after each proc of Touch of the Grave.
- Finds a proc from `UNIT_COMBAT`: Shadow damage on your target and a heal on you.
- The icon shows "Ready", flashes and plays a sound when the internal cooldown (15 s) is over.
- A tooltip shows the state, the internal cooldown, the time since the last proc and the shortest gap between two procs.
- An options page in Game Menu > Options > AddOns: internal cooldown, sound, sound choice, flash, countdown text, lock and scale.
- Commands: `/totg options`, `lock`, `unlock`, `reset`, `test`, `icd`, `sound`, `debug`, `stats`, `clearlog`.
- Loads only for Undead characters.

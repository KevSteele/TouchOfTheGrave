# Changelog

## 0.1.6 (2026-11-09)

- A hit on your target alone no longer counts as a proc. The heal on you must come with it, for all classes. The client hides the damage amounts, so the heal is the only sign that tells a proc from other Shadow damage.
- In debug mode, the chat also shows each hit that the addon drops, with its unit and school. A test on a Rogue with Thorncursed Grips showed that their damage is Nature (school 8) on you and on your target, so the addon never counted it.

## 0.1.5 (2026-11-05)

- First release on CurseForge, project 1785132. The TOC now has the project ID, so the release workflow can upload the zip.
- A logo image for the project page is in `docs/logo.png`. It is not part of the addon zip.


## 0.1.4 (2026-11-04)

- A left-click on the icon turns the sound alert on or off. A drag does not. The chat tells you the new state.
- While the sound alert is off, a small speaker with a red line through it shows in the bottom right corner of the icon. It is 40% of the icon size.
- The tooltip shows the state of the sound alert and the left-click hint.

## 0.1.3 (2026-11-04)

- The tooltip now opens at the default tooltip place (the bottom right of the screen, or the place set in Edit Mode), as the tooltips of the action bars do. Before, it opened at the right side of the icon.

## 0.1.2 (2026-11-04)

- No more "Ready" text below the icon. When the cooldown is over, the icon at full brightness shows the ready state, with the flash and the sound if they are on.
- The countdown number is now in the center of the icon, over the cooldown sweep. Its font is about 40% of the icon size, with an outline. The option "Show the countdown text" still turns it on or off.

## 0.1.1 (2026-11-04)

- The blue background behind the icon is gone. An unlocked frame shows a thin white outline, so that you can find it. A locked frame shows only the icon and the countdown text.
- New icon size setting, 24 to 96 pixels (default 40): a slider on the options page and the command `/totg size <pixels>`. It replaces the frame scale setting. A saved scale changes to the same size the first time.

## 0.1.0 (2026-11-04)

First release.

- Shows an icon with a cooldown sweep and a countdown after each proc of Touch of the Grave.
- Finds a proc from `UNIT_COMBAT`: Shadow damage on your target and a heal on you.
- The icon shows "Ready", flashes and plays a sound when the internal cooldown (15 s) is over.
- A tooltip shows the state, the internal cooldown, the time since the last proc and the shortest gap between two procs.
- An options page in Game Menu > Options > AddOns: internal cooldown, sound, sound choice, flash, countdown text, lock and scale.
- Commands: `/totg options`, `lock`, `unlock`, `reset`, `test`, `icd`, `sound`, `debug`, `stats`, `clearlog`.
- Loads only for Undead characters.

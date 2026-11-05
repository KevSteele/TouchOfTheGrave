# Touch of the Grave Timer

A small timer for the Undead racial Touch of the Grave on **World of Warcraft: Forever**.

Touch of the Grave has an internal cooldown between procs, and the game shows no
timer for it. This addon shows one icon. When Touch of the Grave procs, the icon
goes grey, a cooldown sweep starts, and the seconds left show below it. When the
cooldown is over, the icon shows "Ready", flashes and plays a sound. Then your
next hit can proc again.

## Requirements

- World of Warcraft: Forever only (game version 1.60.1). The addon does not work on Retail or Classic.
- Undead characters only. On other races the addon stays off and tells you so one time.
- No libraries.

## How it finds a proc

Forever does not let addons read the combat log. Thus the addon uses the
`UNIT_COMBAT` event. A proc does Shadow damage to your target and heals you by
the same amount:

- Warrior, Paladin, Rogue and Mage: when the icon shows "Ready", one Shadow hit on your target is the proc.
- Priest and Warlock: the heal on you must come with the Shadow hit. The addon also ignores your channeled spells (Drain Life, Mind Flay), and it stops for the time of Devouring Plague, Siphon Life and Death Coil.

## The internal cooldown

The default is 15 seconds, from the WoW Forever development notes of
October 2026. To change it, use the options page or type `/totg icd <seconds>`.
If a proc comes before the timer ends, the chat tells you the shorter time.

## Options

Open the options with a right-click on the icon, with `/totg options`, or in
Game Menu > Options > AddOns > Touch of the Grave Timer:

- Internal cooldown (5 to 60 seconds)
- Sound when ready, and the sound to play
- Flash when ready
- Show the countdown text
- Lock the frame
- Icon size (24 to 96 pixels)

Move the mouse onto the icon to see the state, the internal cooldown, the time
since the last proc and the shortest gap between two procs.

## Commands

- `/totg options`: open the options.
- `/totg lock`, `/totg unlock`: lock or unlock the frame.
- `/totg reset`: move the frame to the default position and clear the timer.
- `/totg test`: start the timer one time, to see the display.
- `/totg icd <seconds>`: set the internal cooldown.
- `/totg size <pixels>`: set the icon size.
- `/totg sound`: set the sound on or off.
- `/totg debug`: show the Shadow hits, the heals and the procs in chat.
- `/totg stats`: show the last procs and the shortest gap.
- `/totg clearlog`: clear the proc log.

## Limits

- The addon sees only procs on your current target. Keep the monster that you attack as your target.
- In a group, Shadow damage from another player on your target can look like a proc when the icon shows "Ready".

## Related addon

[Touch of the Grave - Tracker](https://www.curseforge.com/wow/addons/touch-of-the-grave-tracker)
by Wakamama does the same task, with proc rate statistics. The two addons both
use the `/totg` command. Install only one of them.

## License

MIT

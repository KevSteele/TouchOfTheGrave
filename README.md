# Touch of the Grave Timer

This addon shows an icon with a cooldown sweep and a countdown. When the internal
cooldown (ICD) of the Undead racial "Touch of the Grave" is over, the icon shows
"Ready", flashes, and plays a sound. The addon loads only for Undead characters.
It works only on World of Warcraft: Forever (Interface 16001, game version 1.60.1).

## Repository layout

- `TouchOfTheGrave/`: the addon folder. Only this folder goes into a release.
- `docs/curseforge.md`: the text for the CurseForge project page.
- `tools/zip.ps1`: builds a release zip by hand.
- `.pkgmeta` and `.github/workflows/release.yml`: the release with the BigWigs packager.
- `CHANGELOG.md`, `LICENSE` (MIT).

## Install for development

The game loads the addon through a directory junction, thus a change in the
repository is in the game after `/reload`:

```bat
cmd /c mklink /J "D:\World of Warcraft\_forever_\Interface\AddOns\TouchOfTheGrave" "D:\dev\TouchOfTheGrave\TouchOfTheGrave"
```

## Release

Do these steps one time before the first release:

1. Create the CurseForge project for World of Warcraft, flavor "Forever". Use the text in `docs/curseforge.md`.
2. In `TouchOfTheGrave/TouchOfTheGrave.toc`, remove the `# ` before the `## X-Curse-Project-ID:` line and write the project ID.
3. Create the GitHub repository and push `main`. Remove the `# ` before the `## X-Website:` line and write the URL.
4. In the GitHub repository settings, add the secret `CF_API_KEY` with a CurseForge API token.

For each release, use one of these two ways:

- **Through GitHub:** write the new version in the TOC (`## Version:`) and in `CHANGELOG.md`, commit, then push a tag `vX.Y.Z` (for example `git tag v0.1.0` and `git push origin v0.1.0`). The workflow packages the addon and uploads it to CurseForge and to GitHub Releases.
- **By hand:** run `powershell -ExecutionPolicy Bypass -File tools\zip.ps1`. Then upload `dist\TouchOfTheGrave-<version>.zip` on the CurseForge project page, with game version 1.60.1.

## What is known

| Item | Value | Status |
|---|---|---|
| Passive (Warrior, Paladin, Rogue) | spell 1260189, 20% chance | Confirmed (forever.warcraftdb.com) |
| Passive (Priest, Mage, Warlock) | spell 1260201, 30% chance | Confirmed (forever.warcraftdb.com) |
| Proc effect | spell 1260198, Shadow, Health Leech of 5% of your maximum health | Confirmed (forever.warcraftdb.com) |
| Internal cooldown | 15 seconds (was 25) | From the Forever beta notes of 2026-10-27. The Tracker addon (see below) also changed to 15 s in its version of 2026-11-03. Not yet measured on the live client. |
| An internal cooldown exists | 25 s before the change | The Tracker author reports that 135 of 136 procs on a Paladin came 25 s or more apart (before the change to 15 s). Their report, not our measurement. |
| How the addon finds a proc | `UNIT_COMBAT`: Shadow damage on the target and a heal on the player | Confirmed in game on 2026-11-04 on a Rogue. The Tracker addon uses the same method. |
| `UNIT_SPELLCAST_SUCCEEDED` (the cast event) | cannot identify the proc | Confirmed in game on 2026-11-04. The spell ID is a secret value for all casts except some of your own attacks. |
| `C_Spell.GetSpellCooldown` on spell 1260198 | cannot give the ICD | Confirmed in game on 2026-11-04. The value is always secret. |

Addons cannot read the combat log on this client. `COMBAT_LOG_EVENT_UNFILTERED`
is forbidden and `CombatLogGetCurrentEventInfo` does not exist. The cast event
and the cooldown API give only secret values. Thus the addon uses only
`UNIT_COMBAT`.

### How the addon finds a proc

The proc does Shadow damage to your target and heals you by the same amount.

- If the icon shows "Ready" and your class has no Shadow damage of its own (Warrior, Paladin, Rogue, Mage), one Shadow hit on your target is a proc.
- In all other cases, a heal on you must come in 0.5 seconds before or after the Shadow hit, with the same amount.
- Priest and Warlock: the addon ignores Shadow hits while you channel a spell (Drain Life, Mind Flay). It also stops for the time of Devouring Plague (24 s), Siphon Life (30 s) and Death Coil (3 s) after you cast them, because these spells also do Shadow damage and heal you. For this, the addon reads the cast event on Priest and Warlock characters only. If the client gives the spell ID as a secret value, the addon cannot see the cast, and a tick of these spells can count as a proc. This is not tested.
- The addon ignores Shadow damage when you are out of combat, but it accepts it in the first 2 seconds after combat ends.

Limits:

- The addon sees only procs on your current target. Keep the monster that you attack as your target.
- In a group, Shadow damage from another player on your target can look like a proc when the icon shows "Ready". Play alone for the tests.

### The other addon

"Touch of the Grave - Tracker" by Wakamama (CurseForge project 1755767, version
2.3.2, MIT License) does the same task, with proc rate statistics and a panel.
This addon does not use its code. Both addons use the `/totg` command. Do not
install both, because only one of them can own the command.

## The frame

- The icon is the Touch of the Grave icon from the client. The addon asks for the icon of spell 1260189, then 1260201, then 1260198, and uses the first icon that it gets. If the client gives no icon, the addon uses file data ID 136157 (`Interface\Icons\Spell_Shadow_FingerOfDeath`), which forever.warcraftdb.com shows for both passives.
- Move the mouse onto the icon to see a tooltip: the state ("Ready" or the seconds left), the internal cooldown setting, the time since the last proc, and the shortest gap between two procs.
- Right-click the icon to open the options.
- If the frame is unlocked, drag it with the left mouse button. An unlocked frame shows a thin white outline, so that you can find it. A locked frame shows only the icon and the countdown text.

## Options

Open the options with a right-click on the icon, with `/totg options`, or in
Game Menu > Options > AddOns > Touch of the Grave Timer. If you are in combat,
the options open when combat ends.

- Internal cooldown: 5 to 60 seconds. The default is 15.
- Sound when ready: on or off.
- Sound: raid warning, ready check, alarm clock or soft click. The addon plays the sound when you select it.
- Flash when ready: on or off.
- Show the countdown text: show "Ready" or the seconds left below the icon.
- Lock the frame: stop the frame from moving. A locked frame still shows the tooltip and opens the options.
- Icon size: 24 to 96 pixels. The default is 40.

## Commands

- `/totg options`: open the options.
- `/totg lock` and `/totg unlock`: lock or unlock the frame. Drag the unlocked frame with the left mouse button.
- `/totg reset`: move the frame to the default position and clear the timer.
- `/totg test`: start the timer one time, to see the display.
- `/totg icd <seconds>`: set the internal cooldown. The default is 15.
- `/totg size <pixels>`: set the icon size, 24 to 96. The default is 40.
- `/totg sound`: set the sound on or off.
- `/totg debug`: show each Shadow hit on your target, each heal on you, and each proc in chat.
- `/totg stats`: show the procs in the log and the shortest gap between two procs.
- `/totg clearlog`: clear the proc log.

## In-game test 1: does the addon see the proc?

1. Log in on your Undead character.
2. Make sure that the icon shows below the center of the screen. Type `/totg test` and make sure that the countdown starts.
3. Type `/totg debug`.
4. Target a monster and attack it for one to two minutes. Keep it as your target.
5. Examine the chat for these lines:
   - `unit combat: target WOUND <amount>`: a Shadow hit on your target.
   - `unit combat: player HEAL <amount>`: a heal on you.
   - `proc found, gap <seconds> s`: the addon found a proc and started the timer.
6. Type `/totg debug` again to stop the debug lines.

If the "Combat Log" chat tab shows a Touch of the Grave hit, but no `unit
combat:` line shows at the same time, then the client did not send
`UNIT_COMBAT` for that hit. Make sure that the monster was your target. If it
was, report this result.

## In-game test 2: what is the real internal cooldown?

The addon cannot read the combat log, but the game can write it to a file.

1. Go to an area with many monsters that you can kill one after another. Play alone, because another Undead player in your group adds lines to the log.
2. Type `/combatlog`. The chat shows "Combat being logged to Logs\WoWCombatLog.txt".
3. Attack monsters without a stop for about 10 minutes. Many hits give many chances to proc, so the procs come soon after each ICD ends.
4. Type `/combatlog` again to stop the log.
5. Run this command in PowerShell. It shows the ten shortest gaps between two procs:

```powershell
$f = Get-ChildItem "D:\World of Warcraft\_forever_\Logs\WoWCombatLog*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1; $last = $null; $gaps = foreach ($line in (Select-String -Path $f.FullName -Pattern '1260198' | ForEach-Object Line)) { if ($line -match '(\d+):(\d+):(\d+\.\d+)') { $t = [int]$matches[1] * 3600 + [int]$matches[2] * 60 + [double]$matches[3]; if ($null -eq $last -or $t - $last -gt 1) { if ($null -ne $last) { $t - $last }; $last = $t } } }; $gaps | Sort-Object | Select-Object -First 10 | ForEach-Object { '{0:N1} s' -f $_ }
```

6. Read the shortest gaps. The ICD is a little less than the shortest gap. Example: if the shortest gaps are 15.2, 15.4 and 15.9 seconds, the ICD is 15 seconds.
7. If the ICD is not 15 seconds, type `/totg icd <seconds>`.

The addon also helps. If a proc comes before the timer ends, the chat shows
"proc came ... s after the last proc". Type `/totg stats` to see the shortest gap
that the addon recorded.

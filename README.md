# Nameplate Quest Markers

A personal fork, for retail and WoW: Forever, of [ForeverQuestMark](https://www.curseforge.com/projects/1702963) by
**Ugge Zen**: shows an icon on the nameplates of units related to your active quests.

The addon folder is `NameplateQuestMarkers`. It keeps upstream's `ForeverQuestMarkDB` saved variable, so don't install
it alongside the upstream addon.

## Changes from upstream

- **Kill / loot / other icons from the quest log.** Each objective line on a unit's tooltip is matched to your quest
  log, and Blizzard's own objective type decides the icon: kill (`monster`), loot (`item`) or a new **other** icon
  for everything else (talk to, interact, use, non-kill progress bars). Kill wording ("slain", "killed", "defeat")
  is the fallback when the quest log can't tell.
- **Talk-to NPCs.** Units whose tooltip lists no objective, but that the game reports as part of an active quest,
  get the other icon. A speech bubble (`Crosshair_speak_32`) is available for it in the icon list.
- **Position**: left, center or right of the nameplate (Left mirrors the second icon and progress text outward).
- **Two icons** side by side for a unit that counts for objectives of two different kinds, each with its progress.
- **Progress-bar percentages** ("35%") next to the icon, like "3/8" counts.
- **Refresh fixes.** Retail nameplates store their unit as `unitToken`; upstream looked up `namePlateUnitToken`, so
  icons never refreshed when quest progress changed or after `/reload`. Also: quest log bursts are batched into
  one rescan per 0.2s, and each new nameplate is checked again after 0.5s.
- **Instances and scenarios.** Tooltip lines are hidden from addons there, so the icon is guessed from the quest
  log using the same classification (so "… slain" progress bars count as kills); enemies prefer a kill objective,
  then loot; progress bars show their percentage. The own-nameplate check is secret-value safe.
- **Plain saving.** The Forever-beta SavedVariables workaround (per-character mirror, save stamps, `!ForeverData`
  setup scripts) is removed; settings save the normal way (Blizzard fixed the bug in Forever beta build 70009).
- Cleanup: unused parts of the shared settings kit (Edit Mode overlays, list/number/text controls) removed;
  `/fqm debug` shows every mark; slash commands refresh an open settings page.
- The CurseForge project id has been removed from the TOC on purpose, so managers won't replace this with upstream.

Slash commands: `/fqm` (settings), `/fqm kill|loot|other <atlas>`, `/fqm x|y|size <n>`, `/fqm side left|center|right`, `/fqm reset`, `/fqm debug`.

## Install

Download `NameplateQuestMarkers-<version>.zip` from the [latest release](../../releases/latest) and extract the
`NameplateQuestMarkers` folder into `World of Warcraft\_retail_\Interface\AddOns\` (for WoW: Forever, `_forever_` instead of `_retail_`).

An addon manager that installs from GitHub releases (e.g. WowUp: *Install from URL* with this repo's URL) can also
install and update it, **but only if the repository is public**.

To update from the command line (works for a private repo, needs `gh auth login` once):

```powershell
.\scripts\update-from-release.ps1
```

## Developing / releasing

- Test local changes: `.\scripts\install-local.ps1` copies the addon folder into `AddOns`, then `/reload`.
- After a WoW patch: bump `## Interface:` in `NameplateQuestMarkers/NameplateQuestMarkers.toc`.
- Release: `git tag v1.3.1 && git push --tags`. The [Release workflow](.github/workflows/release.yml) stamps the
  version into the TOC, builds the zip (with a `release.json` so addon managers see it's a retail and Forever build), and
  publishes the GitHub release.

## Credits and license

ForeverQuestMark was created by **Ugge Zen**. Licensed under the **MIT License**, the same as upstream
([`LICENSE`](LICENSE), also included in the addon folder).

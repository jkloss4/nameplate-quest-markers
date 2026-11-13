# Nameplate Quest Markers

A personal fork, for retail and WoW: Forever, of [ForeverQuestMark](https://www.curseforge.com/projects/1702963) by
**Ugge Zen**: shows an icon on the nameplates of units related to your active quests.

The addon folder is `NameplateQuestMarkers`. It keeps upstream's `ForeverQuestMarkDB` saved variable, so don't install
it alongside the upstream addon.

## Changes from upstream

- **Six objective categories from the quest log**, each with its own icon setting (the same split as Questie's).
  Each objective line on a unit's tooltip is matched to your quest log, and Blizzard's own objective type decides:
  - **Slay**: `monster` objectives on units you can attack, kill wording ("slain", "killed", "defeat"), and progress
    bars on units you can attack (filled by killing them);
  - **Loot**: `item` objectives;
  - **Object**: `object` objectives;
  - **Event**: `event` and `log` objectives, and progress bars on units you can't attack;
  - **Talk**: `monster` objectives on units you can't attack (the quest log types "Speak with X" as `monster`);
  - **Interact**: any other type, and units whose tooltip lists no objective but that the game reports as part of
    an active quest.

  An icon missing on the client falls back to the gear (`Crosshair_Interact_32`). The old single "Other" icon
  setting carries over as the Interact icon.
- **Questie's categories when Questie is loaded** (optional). Questie's database knows each creature's part in each
  quest, and picks its Talk and Interact objectives by hand, so for a creature Questie lists, its category wins:
  matched to the tooltip's objective line by text, or, when the tooltip lists none, from Questie's open objectives
  on that creature (with Questie's count). That also marks creatures the game doesn't tie to a quest at all, such
  as ones dropping a quest item its data leaves out. Read from `QuestieTooltips.lookupByKey` (the table Questie's
  own nameplates and Plater use); nothing of Questie's is copied. Without Questie, or for creatures it doesn't
  list, the quest log rules above decide. `/fqm debug` lists Questie's objectives on the target.
- **Position**: left, center or right of the nameplate. The horizontal offset is measured from the icon's left edge (Right), the progress text's right edge (Left) or the middle of the icon and text (Center).
- **Avoid Auras** (on by default): while the nameplate shows aura icons on the mark's side, the mark moves past them: right of the crowd control icons (Right), left of the buff icons (Left), above the debuff icons (Center), **Aura Spacing** (2 px by default) away. Nameplates can't be measured by addons on this client, so the mark is anchored to the aura row rather than nudged only as far as needed.
- **Two icons** side by side for a unit that counts for objectives of two different kinds, each with its progress.
- **Groups.** A unit's tooltip also lists party members' objectives for a shared quest, under their names;
  only your own count, so a mark (and its progress) goes away once your part is done. With **Group Objectives**
  (off by default), a unit a party member still needs keeps its icon, without progress (the count is theirs), after
  your own marks. Completion is read from the tooltip line's own completed flag where the client gives it.
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

Slash commands: `/fqm` (settings), `/fqm kill|loot|object|event|talk|interact <atlas>`, `/fqm x|y|size <n>`, `/fqm side left|center|right`, `/fqm reset`, `/fqm debug`.

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

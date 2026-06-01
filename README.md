# BluForge

A Blue Mage focused [Ashita v4](https://www.ashitaxi.com/) addon for **Final Fantasy XI** that combines the
spell-set management of [BluSets](https://github.com/AshitaXI/Addons) with an in-game ImGui interface inspired by
[BluCheck](https://github.com/AshitaXI/Addons), plus a job-trait planner.

## Features

- **Spell set editor** — define spell sets and assign spells to 20 visual slots that map to the in-game Blue Magic
  set slots.
- **Spell browser** — known/unknown spells are color coded, with a "Known only" filter, a "Hide non-settable" filter,
  and a name search. Non-settable spells (no set cost) are shown muted and cannot be slotted.
- **Set point awareness** — tracks set point usage against the value reported by the game, automatically respecting
  BLU main vs. sub job availability, and blocks assignments that would exceed your capacity.
- **Save / load / delete** named spell sets. Set files are plain text (one spell name per line) and are
  cross-compatible with BluSets set files.
- **Apply to game** — sets your Blue Magic in-game using BluSets' fast packet mode, fully clearing the current set
  first and confirming the reset before writing the new spells.
- **Trait planner** — identifies the job traits a set will grant, with tier thresholds and contributing spells. The
  Job Point trait-bonus level is detected automatically from your BLU job points spent.
- **Spell information** — element, MP cost, cast/recast, level, set cost, the traits a spell contributes to, and the
  monsters/zones a spell can be learned from.

## Compatibility

> **Tested only on retail FFXI with Ashita v4.30.** It has not been tested on private servers or other Ashita
> versions. Memory signatures and packet behavior (used for reading set points and applying spells) may differ
> elsewhere, so results on other setups are not guaranteed.

## Installation

Copy the `bluforge` folder into your Ashita `addons` directory, then load it in-game:

```
/addon load bluforge
```

## Commands

| Command | Description |
| --- | --- |
| `/bluforge` (or `/bf`, `/bforge`) | Toggle the BluForge window. |
| `/bluforge load <name>` | Load the named spell set into the editor. |
| `/bluforge apply` | Apply the current editor set to the game (fast mode). |
| `/bluforge help` | Show command help. |

## Usage

1. Open the window with `/bluforge`.
2. In the **Editor** tab, click a spell in the browser, then click a slot to place it (or double-click a spell to
   fill the next free slot). Click a filled slot to clear it.
3. Use the **Set** controls to save your set, or load/delete a saved one.
4. Click **Apply to Game (Fast)** to set the spells in-game.
5. Check the **Traits** tab to see which job traits the current set grants.

## Credits

- Derived from atom0s' **BluSets** and **BluCheck** addons (Ashita Development Team).
- Blue Magic set-point and job-trait data sourced from [BG-Wiki](https://www.bg-wiki.com/ffxi/Blue_Mage_Job_Traits).

## License

Released under the GNU General Public License v3.0, matching the BluSets / BluCheck addons it is derived from. See
[LICENSE](LICENSE).

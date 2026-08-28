# AltoWeed

A World of Warcraft 3.3.5a addon, built for the [Project Ascension](https://ascension.gg/) private server, that remembers what's in every character's bags, bank, currency, Personal Storage, and professions — even when you're not logged into them.

Log into an alt, and AltoWeed quietly records what it sees. Log into a different character later, and you can still pull up everyone else's last-known inventory and professions from a single window.

## Features

- **Bags, Bank, Currency, and Personal Storage tracking** — records the contents of all 4 bag slots, the bank (including bank bags), your currency tab (Emblems, Marks, etc. plus gold/silver/copper), and Ascension's "Personal Bank" chest storage (a Guild Bank–backed personal stash). Shown under the **Personal Stash** tab.
- **Profession tracking** — records every profession's skill rank/max rank (including pure-gathering skills like Herbalism, Mining, and Skinning), plus every crafting recipe/schematic you've learned, grouped the same way they're grouped in the trade skill window. Shown under the **Professions** tab. See the note below on recipes.
- **Linkable items and recipes** — hover any item or recipe icon for its tooltip, or shift-click it to insert the link into chat, same as any item icon in the default UI.
- **Persists across characters** — data is stored account-wide, so every character you've ever logged into stays browsable, not just your current one.
- **Minimap button** — left-click to open the AltoWeed window.
- **Character list** — a sortable, class-colored list of every character you've visited, most recent first. Click one to see its stored data.
- **Search** — type an item, currency, or recipe name into the search field and press Enter or click the magnifying glass to highlight every match currently on screen, on either tab.
- **Delete** — remove a character (and everything recorded about them) from the list, with a confirmation prompt.
- **Close** — click the X or just press Escape.

### A note on recipes

Skill rank/max rank for every profession is recorded automatically, any time. **Recipes and schematics, however, are only recorded once you open that profession's trade skill window** while logged into that character (the game only exposes a profession's known recipes while its window is open — the same reason the bank and Personal Storage chest also require opening them at least once). Pure-gathering skills like Herbalism, Mining, and Skinning have no such window and no recipes, so only their skill rank is ever tracked.

## Installation

Drop the `AltoWeed` folder into:

```
Interface/AddOns/
```

then `/reload` or restart the client.

## Usage

- Click the minimap button (bag icon) to open the window.
- Click a character on the left to view their data on the right.
- Switch between the **Personal Stash** and **Professions** tabs at the top of the right panel.
- Type into the search field and press **Enter** (or click the magnifying glass) to highlight matching items/recipes with a gold glow. Clear the field and search again to remove the highlight.
- Shift-click any item or recipe icon to link it in chat.
- Click **Delete** to forget a character.
- Press **Escape** or click the **X** to close the window.

Data updates automatically while you play — opening your bank, Personal Storage chest, or a trade skill window, gaining currency or skill-ups, or picking up items all refresh what's stored for your current character.

## About this project

AltoWeed was designed and written entirely by [Claude Code](https://claude.com/claude-code), Anthropic's AI coding assistant, working directly from a description of the desired features — including reverse-engineering how Ascension's custom "Personal Bank" storage works under the hood (it turned out to be backed by the standard Guild Bank API), and working around a couple of APIs (`GetProfessions()`) that this custom client doesn't expose, by reading profession data from the generic Skills list instead. No hand-written code went into this addon.

## License

AltoWeed is released under the [BSD 2-Clause License](LICENSE) — free to use, modify, and redistribute, with no warranty.

## Author

Oathmeal — Rexxar (Ascension)

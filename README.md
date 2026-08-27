# AltoWeed

A World of Warcraft 3.3.5a addon, built for the [Project Ascension](https://ascension.gg/) private server, that remembers what's in every character's bags, bank, currency tab, and Personal Storage — even when you're not logged into them.

Log into an alt, and AltoWeed quietly records what it sees. Log into a different character later, and you can still pull up everyone else's last-known inventory from a single window.

## Features

- **Bags, Bank, Currency, and Personal Storage tracking** — records the contents of all 4 bag slots, the bank (including bank bags), your currency tab (Emblems, Marks, etc. plus gold/silver/copper), and Ascension's "Personal Bank" chest storage (a Guild Bank–backed personal stash).
- **Persists across characters** — data is stored account-wide, so every character you've ever logged into stays browsable, not just your current one.
- **Minimap button** — left-click to open the AltoWeed window.
- **Character list** — a sortable, class-colored list of every character you've visited, most recent first. Click one to see its stored inventory.
- **Search** — type an item (or currency) name into the search field and press Enter or click the magnifying glass to highlight every matching item currently on screen.
- **Delete** — remove a character (and everything recorded about them) from the list, with a confirmation prompt.
- **Close** — click the X or just press Escape.

## Installation

Drop the `AltoWeed` folder into:

```
Interface/AddOns/
```

then `/reload` or restart the client.

## Usage

- Click the minimap button (bag icon) to open the window.
- Click a character on the left to view their bags, bank, currency, and Personal Storage on the right.
- Type into the search field and press **Enter** (or click the magnifying glass) to highlight matching items with a gold glow. Clear the field and search again to remove the highlight.
- Click **Delete** to forget a character.
- Press **Escape** or click the **X** to close the window.

Data updates automatically while you play — opening your bank or Personal Storage chest, gaining currency, or picking up items all refresh what's stored for your current character.

## About this project

AltoWeed was designed and written entirely by [Claude Code](https://claude.com/claude-code), Anthropic's AI coding assistant, working directly from a description of the desired features — including reverse-engineering how Ascension's custom "Personal Bank" storage works under the hood (it turned out to be backed by the standard Guild Bank API). No hand-written code went into this addon.

## License

AltoWeed is released under the [BSD 2-Clause License](LICENSE) — free to use, modify, and redistribute, with no warranty.

## Author

Oathmeal — Rexxar (Ascension)

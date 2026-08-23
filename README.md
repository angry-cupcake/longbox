# Longbox

A comic pull-list widget for the Omarchy Quattro bar.

Longbox shows your public pull list from [leagueofcomicgeeks.com](https://leagueofcomicgeeks.com) as a bar count, with a popup panel listing this week's pulls: cover art, publisher, price, and release status. It can also browse the general weekly release sheet for any past or future week. No login required.

## Install

```sh
omarchy plugin add https://github.com/angry-cupcake/longbox.git --enable
```

## Usage

- **Left-click** the book icon to open the panel
- **Right-click** to open your pull list on leagueofcomicgeeks.com
- On first open, Longbox asks for your League of Comic Geeks username. Leave it blank to track general weekly releases instead.
- Hover a comic to preview it; click to open its LoCG page
- Hover actions mark comics as collected, read, or wishlisted (stored locally)

### Week navigation

The arrow buttons in the panel move between weeks. Releases can browse any week live. Pull lists are only public on LoCG while current, so previous weeks come from your local archive: when archiving is enabled, each week's pulls are snapshotted while they are current and history builds up over time.

### Settings tab

Everything is configurable in the panel's Settings tab:

- Profile: your LoCG username, validated live against the site
- Source: your pull list or the full weekly releases
- View: compact list or a poster grid
- Variant covers, cover art, refresh interval
- Storage: local caching of fetched data (on by default) and pull-list archiving (off by default)

Marks, profile, and preferences always persist locally in `~/.local/state/omarchy/settings/longbox.json`. Turning off "Store comic data locally" clears cached issues and archives immediately; the widget then re-fetches after every restart (not recommended: slower panel opens and no offline data).

## Configure via shell.json

Settings live in `~/.config/omarchy/shell.json` under the widget entry. These seed the initial state only; changes made in the panel's Settings tab take precedence afterward.

| Key | Default | Description |
|-----|---------|-------------|
| `username` | *(empty)* | Your LoCG username; leave blank for general weekly releases |
| `source` | `pulls` | `pulls` or `releases` (everything shipping that week) |
| `excludeVariants` | `true` | Hide variant covers (releases mode only) |
| `showCovers` | `true` | Cover thumbnails in the panel |
| `refreshIntervalMin` | `60` | Fetch interval; be gentle, LoCG rate-limits |

## Dependencies

- [curl](https://curl.se/) (preinstalled on Omarchy) — used to fetch data from leagueofcomicgeeks.com over HTTPS. No other external commands are executed.
- The test suite needs Node.js (`node --test`).

## Known limitations

- Pull lists are only public for the current week. Past weeks appear from your local archive once archiving has had time to collect them; nothing before installation is recoverable anonymously.
- Marks are local to this device. Syncing them to a LoCG account would need an authenticated session.
- Data comes from parsing the public page HTML; if LoCG changes their markup the widget will tell you rather than show an empty list.

## Development

Run the test suite (no dependencies beyond Node):

```sh
node --test "tests/*.test.js"
```

HTML fixtures under `tests/fixtures/` were captured from real LoCG pages and keep the parser honest.

## Remove

```sh
omarchy plugin remove angry-cupcake.longbox
```

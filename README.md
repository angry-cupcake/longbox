# Comic Releases (hari.comics)

A League of Comic Geeks pull-list widget for the Omarchy Quattro bar.

Shows your public pull list from [leagueofcomicgeeks.com](https://leagueofcomicgeeks.com) as a bar count, with a popup panel listing this week's pulls — cover art, publisher, price, and release status. No login required: LoCG pull lists are public.

## Install

```sh
omarchy plugin add https://github.com/hari/hari.comics.git --enable
```

## Usage

- **Left-click** the book icon to open the panel
- **Right-click** to open your pull list on leagueofcomicgeeks.com

## Configure

Settings live in `~/.config/omarchy/shell.json` under the widget entry:

| Key | Default | Description |
|-----|---------|-------------|
| `username` | `cupcakeisangry` | Your LoCG username; leave blank for general weekly releases |
| `source` | `pulls` | `pulls` or `releases` (everything shipping this week) |
| `excludeVariants` | `true` | Hide variant covers (releases mode only) |
| `showCovers` | `true` | Cover thumbnails in the panel |
| `refreshIntervalMin` | `60` | Fetch interval; be gentle, LoCG rate-limits |

## Known limitations

- Only the current week is available publicly — past-week history on LoCG needs an authenticated session.
- Data comes from parsing the public page HTML; if LoCG changes their markup the widget may need an update.

## Remove

```sh
omarchy plugin remove hari.comics
```

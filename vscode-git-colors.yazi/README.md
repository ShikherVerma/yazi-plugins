# vscode-git-colors.yazi

VS Code style git status colors and marks on file names in yazi.

File and directory names are colored by their git status, and each entry
gets a VS Code style badge: a status letter for files, a colored dot for
directories. This works in every column: the file list, the hovered row,
the parent column, and the directory preview.

| status | file badge | dir badge | default color |
| --- | --- | --- | --- |
| modified | `M` | `●` | `#e2c08d` |
| added | `A` | `●` | `#81b88b` |
| untracked | `U` | `●` | `#73c991` |
| deleted | `D` | `●` | `#c74e39` |
| conflict | `M` | `●` | `#e4676b` |
| ignored | none | none | `#8c8c8c` (dim) |

Directories take the strongest status of their contents. Everything inside
an untracked directory shows as untracked, and everything inside an ignored
directory shows dim, just like the VS Code explorer. Badges are display
only; file names on disk are never touched.

Fetcher logic adapted from
[yazi-rs/plugins git.yazi](https://github.com/yazi-rs/plugins/tree/main/git.yazi)
(MIT).

## Screenshots

TODO

## Install

```sh
ya pkg add ShikherVerma/yazi-plugins:vscode-git-colors
```

Built and tested against yazi 26.5.6. Yazi's plugin API changes between
releases; expect small fixes needed on other versions.

## Setup

`~/.config/yazi/init.lua`:

```lua
require("vscode-git-colors"):setup()
```

`~/.config/yazi/yazi.toml`:

```toml
[[plugin.prepend_fetchers]]
group = "vscode-git-colors"
url = "*"
run = "vscode-git-colors"

[[plugin.prepend_fetchers]]
group = "vscode-git-colors"
url = "*/"
run = "vscode-git-colors"
```

## Options

Pass options to `setup()`. Defaults shown; colors accept a hex string, a
theme style table, or a `ui.Style()`.

```lua
require("vscode-git-colors"):setup {
	modified = "#e2c08d",
	added = "#81b88b",
	untracked = "#73c991",
	deleted = "#c74e39",
	updated = "#e4676b",  -- conflict color
	ignored = "#8c8c8c",
	modified_sign = "M",
	added_sign = "A",
	untracked_sign = "U",
	deleted_sign = "D",
	updated_sign = "M",
	ignored_sign = "",
	dir_sign = "●",
	order = 1500,         -- linemode child order of the badge column
}
```

You can also theme it from `theme.toml` with a `[git_name]` section using
the same keys. Precedence for colors: `setup()` options, then `[git_name]`,
then git.yazi's `[git]` section, then the VS Code defaults above.

## Using alongside git.yazi

You do not need git.yazi for this plugin. If you keep it, blank its signs
in `theme.toml` so letters do not render twice:

```toml
[git]
modified_sign = ""
untracked_sign = ""
added_sign = ""
deleted_sign = ""
updated_sign = ""
ignored_sign = ""
```

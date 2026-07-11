# mobile-auto-layout.yazi

Column widths that adapt to content, screen size, and what you are doing.
Built for phone terminals, comfortable on laptops too.

While you browse, the file list and parent column shrink to fit their
longest names, so the preview gets all the leftover space. When you scroll
the preview (J/K or the mouse or touch wheel), the layout flips to reading
mode and the preview takes over the screen. Moving the hover or tapping a
file flips back to browsing.

On narrow terminals (phone width) you never get more than two columns, and
reading mode shrinks the file list to a thin sliver so nearly the whole
screen is preview. The status bar is reduced to just the hovered file's
name.

## Screenshots

TODO

## Install

```sh
ya pkg add ShikherVerma/yazi-plugins:mobile-auto-layout
```

Built and tested against yazi 26.5.6. Yazi's plugin API changes between
releases; expect small fixes needed on other versions.

## Setup

`~/.config/yazi/init.lua` (after other plugins that register previewers):

```lua
require("mobile-auto-layout"):setup()
```

Enable mouse events in `~/.config/yazi/yazi.toml` so wheel scrolling and
taps are seen:

```toml
[mgr]
mouse_events = ["click", "scroll"]
```

## Options

Defaults shown:

```lua
require("mobile-auto-layout"):setup {
	threshold = 90,      -- columns; below this the terminal counts as phone
	parent_max = 30,     -- parent column width cap
	current_max = 30,    -- file list width cap
	min_width = 10,      -- floor for fit-to-content columns
	reading_frac = 0.10, -- phone reading mode: file list sliver fraction
	padding = 5,         -- icon and spacing added on top of the longest name
	previewers = { "vscode-git-gutter", "code" }, -- previewers watched for scrolling
}
```

The `previewers` list names the previewer plugins whose scrolling should
trigger reading mode. The default watches
[vscode-git-gutter](../vscode-git-gutter.yazi/) and falls back to yazi's
built-in `code` previewer; if you use a different text previewer, add its
name here.

## Known limitations

- Scrolling image, video, pdf, or folder previews does not enter reading
  mode unless you add those previewers, and the hook is only correct for
  text style previewers.
- The status bar replacement hides status segments added by other plugins.
- Do not combine with other plugins that set the column ratio, such as
  toggle-pane; the last writer wins.

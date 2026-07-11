# vscode-git-gutter.yazi

VS Code style git change gutter in yazi's text preview, with instant
scrolling.

You get a syntax highlighted preview (via `bat`) with dim line numbers and
a change gutter on the left: a green bar for added lines, a blue bar for
modified lines, and red marks where lines were deleted. Staged changes are
included. Scrolling is instant, even over slow connections like mosh: the
file is rendered once and every scroll step is served from memory.

```
▎ 10 local marker = 10     <- blue bar:  modified line
▎198 local added = true    <- green bar: added line
▁ 99 local other = 99      <- red mark:  lines deleted just below
▔  1 first line            <- red mark:  lines deleted above line 1
  15 local same = 15       <- unchanged
```

Untracked files, unchanged files, and files outside a git repo preview
without a gutter, matching VS Code. If `bat` is missing the preview falls
back to plain text.

## Screenshots

![Preview pane with the change gutter: blue bars on modified lines, a green bar on added lines, red marks where lines were deleted](../screenshots/git-gutter.png)

## Install

```sh
ya pkg add ShikherVerma/yazi-plugins:vscode-git-gutter
```

Built and tested against yazi 26.5.6. Yazi's plugin API changes between
releases; expect small fixes needed on other versions.

Requires [`bat`](https://github.com/sharkdp/bat) for syntax highlighting.

## Setup

`~/.config/yazi/yazi.toml`:

```toml
[[plugin.prepend_previewers]]
mime = "text/*"
run  = "vscode-git-gutter"
```

## Options

There are no `setup()` options. Built-in limits:

- files larger than 10 MiB show a "too large" message
- rendering stops at 5000 lines, with a truncation notice
- individual lines are capped at 4096 bytes
- the last 6 previewed files stay cached in memory

## Known limitations

- The cache key is path, mtime, and size. Changing only git state (staging,
  committing, switching branches) does not refresh an already cached file;
  touch the file or reopen yazi.
- Files with exactly 5000 lines show a spurious truncation notice.

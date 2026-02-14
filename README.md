# org-excalidraw

An Emacs package for managing [Excalidraw](https://excalidraw.com) drawings in Org mode.

## Background

This project is inspired by [wdavew/org-excalidraw](https://github.com/wdavew/org-excalidraw) but has been completely rewritten to address several critical issues in the original library.

### Relationship with the Original Library

[wdavew/org-excalidraw](https://github.com/wdavew/org-excalidraw) was the first package to integrate Excalidraw into Org mode. Its core idea -- using a custom `excalidraw:` link type to manage drawings -- is excellent. This project inherits that concept but fundamentally changes the implementation.

### Issues with the Original Library

1. **Broken inline image display** -- The original library relied on the `:image-data-fun` property of `org-link-set-parameters` for inline image rendering. However, Org mode 9.7 removed support for `:image-data-fun`, causing custom link types to completely fail at displaying inline images. Running `org-display-inline-images` results in "No images to display inline".

2. **Incomplete file watching** -- The original `file-notify` callback only listened for `renamed` events. On macOS, saving a file produces a `changed` event, so auto-regeneration of SVG after saving in Excalidraw silently fails.

3. **Inconsistent SVG filenames** -- When using Excalidraw's built-in export function, the generated SVG filename does not match the source filename, causing broken links.

4. **No batch operations** -- There was no way to batch re-export all drawings, forcing users to handle them one by one during migration or recovery.

### How This Library Solves These Issues

This library is a complete rewrite with the following key technical changes:

- **Inline display**: Extends `org-display-inline-images` via `:after` advice. After the original function processes `file:` and `attachment:` links, the advice additionally scans for `excalidraw:` links and creates image overlays. This is compatible with Org 9.7+ and works seamlessly with `org-remove-inline-images`.
- **Link type**: Still uses `org-link-set-parameters` to register the `excalidraw:` link type, but only for `:follow` (open source file) and `:export` (HTML/LaTeX export). No longer depends on the deprecated `:image-data-fun`.
- **File watching**: Responds to both `renamed` and `changed` events, ensuring auto-export works correctly on macOS and Linux.
- **Width control**: Supports a global default width and per-image override via `#+ATTR_ORG: :width`, solving the issue of SVG images displaying too small.
- **Cross-platform**: Automatically detects the operating system and selects the correct open command (macOS `open` / Linux `xdg-open` / Windows `start`).

## Features

- Custom `excalidraw:` link type: `[[excalidraw:uuid.excalidraw]]`
- Inline SVG image display in Org buffers (compatible with Org 9.7+)
- `C-c C-o` opens the Excalidraw source file for editing
- Auto-regenerates SVG when `.excalidraw` files are saved
- HTML / LaTeX export support
- Configurable image display width
- Batch export all drawings

## Prerequisites

- Emacs 27.1+
- Org mode 9.3+
- [excalidraw_export](https://github.com/nichochar/excalidraw-export) CLI tool
- [Excalidraw](https://excalidraw.com) desktop app or PWA

### Installing excalidraw_export

```bash
npm install -g excalidraw_export
```

### Installing Excalidraw Fonts

To ensure SVGs render correctly, install the fonts used by Excalidraw. These can be obtained from the [excalidraw_export repository](https://github.com/nichochar/excalidraw-export).

## Installation

### Doom Emacs

`packages.el`:

```elisp
(package! org-excalidraw
  :recipe (:host github :repo "YOUR_USERNAME/org-excalidraw"))
```

`config.el`:

```elisp
(use-package! org-excalidraw
  :after org
  :config
  (setq org-excalidraw-directory "~/draws"
        org-excalidraw-image-width 800)
  (org-excalidraw-setup))

(map! :after org
      :map org-mode-map
      "C-c e c" #'org-excalidraw-create-drawing
      "C-c e a" #'org-excalidraw-export-all)
```

### use-package + straight.el

```elisp
(use-package org-excalidraw
  :straight (:type git :host github :repo "YOUR_USERNAME/org-excalidraw")
  :after org
  :config
  (setq org-excalidraw-directory "~/draws"
        org-excalidraw-image-width 800)
  (org-excalidraw-setup))
```

### Manual Installation

Add `org-excalidraw.el` to your `load-path`, then:

```elisp
(require 'org-excalidraw)
(setq org-excalidraw-directory "~/draws")
(with-eval-after-load 'org
  (org-excalidraw-setup))
```

## Usage

### Creating a Drawing

Run `M-x org-excalidraw-create-drawing` (or `C-c e c`) in an Org buffer:

1. Creates a new `.excalidraw` file in `org-excalidraw-directory`
2. Immediately exports it to SVG
3. Inserts an `[[excalidraw:uuid.excalidraw]]` link at point
4. Opens Excalidraw with the system application for editing

### Viewing Drawings

Press `C-c C-x C-v` (`org-toggle-inline-images`) to display SVG images inline in the buffer.

### Editing Drawings

Press `C-c C-o` on a link to open the corresponding `.excalidraw` source file. After saving in Excalidraw, the SVG is automatically regenerated.

### Batch Export

Run `M-x org-excalidraw-export-all` (or `C-c e a`) to re-export all `.excalidraw` files in the directory.

### Controlling Image Size

Global default width:

```elisp
(setq org-excalidraw-image-width 1000)
```

Per-image override:

```org
#+ATTR_ORG: :width 600
[[excalidraw:uuid.excalidraw]]
```

## Customization

| Variable | Default | Description |
|----------|---------|-------------|
| `org-excalidraw-directory` | `"~/draws"` | Directory to store `.excalidraw` files |
| `org-excalidraw-image-width` | `800` | Default width (px) for inline display and HTML export. `nil` for actual size |
| `org-excalidraw-export-command` | `"excalidraw_export --rename_fonts=true"` | Shell command for SVG export |
| `org-excalidraw-open-command` | Auto-detected | System command to open `.excalidraw` files |
| `org-excalidraw-file-watch-p` | `t` | Whether to watch for file changes and auto-export |

## Commands

| Command | Description |
|---------|-------------|
| `org-excalidraw-create-drawing` | Create a new drawing and insert a link |
| `org-excalidraw-export-all` | Batch export all drawings to SVG |
| `org-excalidraw-setup` | Initialize (register link type + advice + file watching) |
| `org-excalidraw-teardown` | Deactivate (remove advice + stop file watching) |

## License

GPL-3.0

# OMP Sessions for Tern

See what OMP is doing in Tern’s sidebar, expand live split-pane titles, and jump to a specific pane with the keyboard. Search local OMP session history and resume a saved session in a new tab. The plugin runs inside Tern, with no web server or npm dependencies.

![Tern sidebar with two fictional session groups, expanded split-pane titles, five status icons, and an idle tab](./assets/sidebar-screenshot.png)

*Captured in a separate Tern window with fictional sessions and simulated states. Only the session sidebar is shown; no real projects appear in the image.*

## Install

- Tested on Windows with Tern 0.9.13, OMP 18.18.2, and Node.js 24. Other platforms and versions have not been verified.
- Make sure `tern.com`, `node.exe`, and `omp.exe` are on the **Tern desktop process’s PATH**. Adding them only in a PowerShell startup script is not enough. Restart Tern and its session daemon after changing the system or user PATH. On Windows, resuming a saved session uses PowerShell 7 as the Tern shell.

With Git on PATH, install directly from GitHub:

```powershell
tern plugin install https://github.com/yizixu/tern-omp-sessions.git
tern plugin list
```

If you downloaded the source instead, run `tern plugin install .` from the directory containing `plugin.toml`.

The plugin ID is `omp-sessions`. Enable **vertical tabs** in Tern to see the sidebar changes. You can open the session panel with a shortcut or from the command palette.

## Use

| Action | Shortcut or command |
| --- | --- |
| Open the session panel | `Ctrl+Alt+O` or **Open OMP Sessions** |
| Find and jump to a pane | `Ctrl+Alt+J` or **Jump to Pane** |
| Open the selected session | Click the row or press `Enter` |
| Cycle **All**, **Open**, and **History** | `Tab` or `Shift+Tab` |
| Focus search | `Ctrl+L` or `/` |
| Clear search | `Esc` |
| Refresh | `F5` |

### Sidebar

- Tabs with multiple panes show every live pane title. Hover over the tab to see long titles in full. Clicking the sidebar still switches the whole tab; use **Jump to Pane** to go directly to a split.
- Status icons have a fixed slot, so titles do not move when a status appears or clears. A blue ring means **Working**, a yellow `?` means **Waiting for input**, a green `✓` means **Done**, a red `✕` means **Failed**, and a purple `!` means **Alert**. Idle tabs leave the slot empty. The blue ring does not spin when reduced motion is enabled.
- If multiple native icons report a status for the same tab, the sidebar shows the highest priority: Failed, Waiting for input, Alert, Done, then Working. Status comes from Tern. The plugin does not add notifications or change tab colors.
- The close button appears on hover, at the bottom left of a tab with multiple panes. On a single-line tab, it temporarily replaces the icon. The plugin does not rename sessions, rearrange panes, or modify Tern preferences.

### Session panel

Type or paste search terms to match session titles, project paths, IDs, or excerpts from first messages. All terms must match. Open sessions jump to their existing terminal; saved sessions reopen from the original file in a new tab. The plugin checks for an active terminal again before resuming so an outdated list does not start a duplicate. The list refreshes every eight seconds and keeps the selected session by path.

## Local data and limits

- Scanning is read-only. The plugin uses `tern inspect --json` to find open sessions and reads saved sessions under `~/.omp/agent/sessions/<project>/*.jsonl`. If `OMP_AGENT_DIR` points to an existing directory in the plugin process’s environment, it scans that directory instead. It reads at most the first 32 KiB per file and does not descend into subagent or attachment directories.
- OMP resumes the session normally. If the original file or project directory is missing, the plugin reports an error instead of relocating the session. The plugin does not upload titles, paths, or message excerpts.
- Nerd Font icon alignment reads local font files and caches glyph offsets. It never modifies fonts. CFF fonts and fonts that cannot be located are left unchanged.

## Local development

Use `tern plugin link .` to link the source, and `tern plugin reload omp-sessions` after changes. A copied installation and a linked installation cannot share the same plugin ID.

## Release notes

### 1.1.7

Moved runtime lookup to Tern’s PATH instead of a machine-specific configuration file. Added English UI copy, installation instructions, and a native sidebar screenshot.

### 1.1.6

Replaced status pills with 16 px icons, freeing about 40 px for tab titles.

### 1.1.5

Fixed icons and status indicators being pushed down and clipped when closing a split leaves one pane in a tab.

### 1.1.4

Removed leading symbols from the status labels to give the text more space.

### 1.1.3

Moved status to a fixed slot on the right of the title row so state changes do not shift the layout. Moved the close button to the bottom left and made it appear on hover.

### 1.1.2

Aligned sidebar icons by their glyph outlines and removed the pane-count badge over the icon.

### 1.1.1

Aligned icons and titles, displayed status as a rounded label below the title, and added a tree of pane titles.

### 1.1.0

Added live OMP status in the native sidebar, expanded split-pane titles, and direct pane navigation. The existing history panel shortcut stayed the same.

### 1.0.0

Added the native session panel, multi-term search with Chinese text support, live status, navigation across Tern session groups, and resuming from the original file path. Verified mouse and keyboard selection, `Ctrl+Alt+O`, editing Chinese and non-BMP characters, resuming paths with spaces, apostrophes, or Chinese characters, and reusing an existing terminal.

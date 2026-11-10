# OMP Sessions for Tern

Track OMP activity in Tern's native sidebar with theme-aware session cards, actual split-layout silhouettes, saved conversation titles, and independent per-pane status icons. Jump straight to a pane, or search local session history and resume a saved conversation in a new tab. No web server or npm installation step is required.

![Native Tern sidebar in dark and light themes, showing split-layout silhouettes, per-pane status overlays, full-width titles, and right-side hover close buttons](./assets/sidebar-screenshot.png)

*Captured in an isolated native Tern window with fictional session titles and previewed status states. Dark theme on the left, light theme on the right; only the sidebar is shown.*

## Install

- Verified on Windows with Tern 0.9.14, OMP 18.18.6, and Node.js 24.19.0. Other platforms and versions have not been verified.
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

- Tabs with multiple panes show every live pane. Pane and window focus changes keep the caption list in place without waiting for a refresh. Clicking the sidebar still switches the whole tab; use **Jump to Pane** to go directly to a split.
- Each tab is an opaque themed card with a subtle elevation shadow and high-contrast edges. Selection adds an accent-tinted surface and an inset accent rail. Session headings remain semibold and fully opaque while working; fixed border width preserves the tree layout and floating indicator alignment.
- OMP captions and **Jump to Pane** use saved conversation names instead of child-process terminal titles such as `node (vitest 3)`. Unnamed conversations use their first user message or session filename. A custom tab name is preserved; an unnamed OMP tab uses its focused conversation's name. Other terminals retain their native titles.
- Conversation names are checked about every two seconds and cached in memory. Process-title events on known OMP panes do not refresh the caption stylesheet; actual conversation-name changes still update normally. Tern's native hover tooltip may retain raw terminal details.
- Each tab's parent icon is a window-layout silhouette drawn from its actual split tree and floating panes, including split direction and proportions. Focus changes do not change the layout icon; geometry changes are checked once a second.
- Pane captions are 24 px tree rows with 16 px icon tiles, aligned titles, and independently overlaid status icons. Icon surfaces pick up a subtle tint from the current theme's accent: light surfaces with dark artwork in dark themes, and soft charcoal surfaces with white artwork in light themes. Accent changes apply directly through CSS; light/dark artwork follows Tern's actual `data-theme` attribute rather than the OS preference. Nerd Font title icons keep their original glyph; plain titles use a terminal, Git, browser, or file icon. All pane tiles retain a light shadow, without gradients.
- The tree rail aligns with the parent icon's horizontal centre, with an 8 px gap below the parent title. Each branch leaves 6 px before the pane icon and 8 px between the icon and title. The tree stops at the final row.
- Titles and pane captions use the full content width, with no reserved status gutter. Active status icons float over the text on a card-colored backdrop with a 16 px left fade. The backdrop matches normal, hovered, and selected card fills in both themes; idle rows have no backdrop. Split panes keep independent indicators, and single-pane tabs use the same overlay over the main title. Status changes do not move text, and Working animations leave the fade backgrounds fixed.
- A blue ring means **Working**, a yellow `?` means **Waiting for input**, a green `✓` means **Done**, a red `✕` means **Failed**, and a purple `!` means **Alert**. Each pane's shape and color are independent. Only working rings animate, and reduced motion stops them. Focus changes switch the visible native icon node without destroying its animation host. Acknowledging another pane's completion leaves the working ring's animation tracks unchanged.
- State comes from Tern's per-pane agent activity and native alerts, checked about once a second. Viewed alerts clear normally. Every pane is covered, not just the focused one. The plugin does not add notifications or change tab colors.
- The 14 px native close glyph floats at the right end of the main title row on hover or press, in a 16 px click target with a card-colored backdrop and 16 px left fade. It reserves no title width. Left-side layout silhouettes remain visible instead of swapping with the close button. For single-pane tabs, the close backdrop covers the title's status while hovered without stopping its animation; the status shows again when the pointer leaves. Split-pane indicators remain below the title. The fade does not intercept pointer input, hidden close buttons do not take hits, and native close confirmation is unchanged. The plugin does not rename sessions, rearrange panes, or modify Tern preferences.

The `Ctrl+Shift+1` hint in Tern's tooltip is its first-tab shortcut, not a split-pane number or a plugin shortcut. The plugin hides the duplicate shortcut text and empty metadata nodes so neither leaves a trailing flex gap; the native tooltip and binding remain unchanged.

### Session panel

Type or paste search terms to match session titles, project paths, IDs, or excerpts from first messages. All terms must match. Open sessions jump to their existing terminal; saved sessions reopen from the original file in a new tab. The plugin checks for an active terminal again before resuming so an outdated list does not start a duplicate. The list refreshes every eight seconds and keeps the selected session by path.

## Local data and limits

- Scanning is read-only. The plugin uses `tern inspect --json` to find open sessions and reads saved sessions under `~/.omp/agent/sessions/<project>/*.jsonl`. If `OMP_AGENT_DIR` points to an existing directory in the plugin process’s environment, it scans that directory instead. It reads at most the first 32 KiB per file and does not descend into subagent or attachment directories.
- OMP resumes the session normally. If the original file or project directory is missing, the plugin reports an error instead of relocating the session. The plugin does not upload titles, paths, or message excerpts.
- Nerd Font icons are extracted from local font files as centered vector outlines. Only icons currently in use are extracted and cached. Fonts are never modified or uploaded. A title without a readable glyph uses its pane-type icon.
- The pane-status reader queries the current Tern window locally through `tern ctl state`. The snapshot is used in memory to identify native alerts; it is not written to disk or uploaded.
- The sidebar reuses the live-session scanner for its title cache. It reads only local session metadata and never modifies terminal titles, session files, or saved conversation names.

## Local development

Use `tern plugin link .` to link the source, and `tern plugin reload omp-sessions` after changes. A copied installation and a linked installation cannot share the same plugin ID.

Run `node --test glyphs.test.mjs` to check that fractional font scaling preserves complete SVG icon outlines. The check generates an isolated font fixture and does not require a system font or a running Tern window.

Font parsing uses bundled [opentype.js 2.0.0](https://www.npmjs.com/package/opentype.js/v/2.0.0), under the [MIT license](./vendor/opentype.LICENSE). No package download or network request is needed at runtime.

## Release notes

See [CHANGELOG.md](./CHANGELOG.md) for the release history.


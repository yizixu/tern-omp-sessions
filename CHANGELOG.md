# Changelog

## Unreleased

- Refined the sidebar with opaque theme-aware cards, accent-tinted selection, and window-layout silhouettes based on actual split directions, proportions, and floating panes. Icon surfaces pick up a subtle accent tint in both light and dark themes.
- Let titles and pane captions use the full width. Per-pane status icons float over matching card-colored backdrops with a soft left fade; idle rows reserve no status space. The 14 px native close glyph uses the same right-side overlay on hover, while the left layout silhouette stays visible.
- Smoothed Working rings to a 60 fps sprite target with a seamless 900 ms loop. Stable native animation hosts and fixed background tracks keep other panes animating when focus changes or a completion is acknowledged. Reduced-motion settings still stop animation.
- Kept saved OMP conversation titles in pane captions, the pane jumper, and unnamed tabs instead of child-process terminal titles. Focus changes no longer collapse caption lists, and process-title events do not refresh known OMP captions.
- Fixed incomplete Nerd Font outlines by quantizing fractional coordinates before SVG serialization, refreshing the glyph cache, and adding a deterministic font-outline regression check.
- Updated the native dark/light sidebar screenshot and documentation for layout silhouettes, floating statuses, and right-side close controls.

## 1.1.7

Moved runtime lookup to Tern’s PATH instead of a machine-specific configuration file. Added English UI copy, installation instructions, and a native sidebar screenshot.

## 1.1.6

Replaced status pills with 16 px icons, freeing about 40 px for tab titles.

## 1.1.5

Fixed icons and status indicators being pushed down and clipped when closing a split leaves one pane in a tab.

## 1.1.4

Removed leading symbols from the status labels to give the text more space.

## 1.1.3

Moved status to a fixed slot on the right of the title row so state changes do not shift the layout. Moved the close button to the bottom left and made it appear on hover.

## 1.1.2

Aligned sidebar icons by their glyph outlines and removed the pane-count badge over the icon.

## 1.1.1

Aligned icons and titles, displayed status as a rounded label below the title, and added a tree of pane titles.

## 1.1.0

Added live OMP status in the native sidebar, expanded split-pane titles, and direct pane navigation. The existing history panel shortcut stayed the same.

## 1.0.0

Added the native session panel, multi-term search with Chinese text support, live status, navigation across Tern session groups, and resuming from the original file path. Verified mouse and keyboard selection, `Ctrl+Alt+O`, editing Chinese and non-BMP characters, resuming paths with spaces, apostrophes, or Chinese characters, and reusing an existing terminal.

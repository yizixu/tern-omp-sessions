# Changelog

## Unreleased

### Changed

- Updated sidebar cards and icon colors for light and dark themes.
- Session icons now show each tab's split layout.
- Titles use the full width, with status icons floating over the text. The close button appears on the right when hovered, leaving the layout icon visible on the left.
- Refreshed the sidebar screenshot and usage guide.

### Fixed

- Fixed loading indicators freezing when switching to a completed pane.
- Fixed icon colors following the system theme instead of Tern's selected theme.
- Fixed missing parts of Nerd Font icons.
- Fixed gaps and uneven edges along selected cards' left borders.

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

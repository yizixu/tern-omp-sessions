# Changelog

## Unreleased

Kept a single native parent icon instead of layered duplicates now that every pane has its own icon. The tree begins at the parent icon's horizontal centre.

Fixed caption lists briefly collapsing when pane focus changes. Every potential front icon has the same title rules in advance, and focus-only changes no longer replace the caption stylesheet.

Moved split-pane status from a shared tab-level slot to the corresponding caption row, with independent animated icons and an unchanged layout. Single-pane tabs retain their original status slot.

Upgraded pane captions to icon-and-title rows while retaining tree connectors, independent status slots, and stable focus changes. Custom title icons are rendered as vector outlines rather than font text, so they remain visible in Tern's SVG renderer.

Increased pane rows to 24 px, added space below the parent title, and widened both sides of pane icons without shifting the tree rail. Status icons follow the same row pitch. The hover close button replaces the parent icon rather than covering the final tree branch.

Removed the opacity-transition gap when swapping the parent icon and close button. Both now use the same hover state for immediate visibility, and the hidden button no longer intercepts the pointer.

Use saved OMP conversation titles in pane captions, the pane picker, and unnamed tab headers. Child-process title changes no longer trigger the plugin's caption stylesheet refresh. Existing status animations are unchanged; this does not replace Tern's native animation lifecycle.

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

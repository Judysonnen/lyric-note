# LyricNote · 标唱

A small browser-based tool for annotating song lyrics while learning to sing.

I built this for myself. When I'm practicing a song I want to mark up the lyrics
with breath points, slurs, accents, and notes to myself, the way you'd mark up
sheet music. Existing lyric apps are built for reading along, not for studying,
so this is a tiny single-page app that does just that.

> **Live demo:** https://judysonnen.github.io/lyric-note/  *(enable GitHub Pages to activate)*

## What it does

**Annotate**
- Highlight lines/phrases with a custom color palette
- Mark text with: wavy / solid / dashed / dotted / double underlines, slurs (above), accents (>), breath marks (before/after), triangle for register changes, dot-below for light/weak syllables
- Bold, italic, custom text colors, font picker (multiple Chinese fonts)
- Per-line margin notes (right side) and overall practice notes (bottom)
- Voice input for notes (useful when your hands are busy)

**Organize**
- Multiple songs, each with its own annotations
- Section labels (verse / chorus / bridge etc.)
- Auto-split lyrics by punctuation and line breaks on import

**Export & sync**
- Export annotated lyrics as PDF or image
- Optional cloud sync via Supabase (login/register), so annotations follow you across devices
- Zoom 50%–280%

## Stack

- One file, no build step: `index.html` (~4400 lines, vanilla HTML/CSS/JS)
- [jsPDF](https://github.com/parallax/jsPDF) + [html2canvas](https://github.com/niklasvh/html2canvas) for export
- [Supabase](https://supabase.com/) for auth + sync
- Web Speech API for voice input

## Run locally

```bash
git clone https://github.com/Judysonnen/lyric-note.git
cd lyric-note
open index.html      # macOS, or just double-click the file
```

That's it. No install, no server. Cloud sync needs Supabase credentials configured
in the file; without them everything still works against `localStorage`.

## Status

Personal tool, used regularly. UI is in Chinese because that's what I sing in.
I add features when I run into something that annoys me during practice.

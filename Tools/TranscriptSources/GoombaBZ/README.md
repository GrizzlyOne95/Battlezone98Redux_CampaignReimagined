# GoombaBZ manual transcript source

These CSV files are the canonical manual transcript data supplied by **GoombaBZ**.

- `campaigns.csv` contains 778 campaign / briefing / training voice lines. CR generates the matching `Text/*.txt` subtitle assets from this file with `Tools/Import-GoombaTranscripts.py`.
- `units.csv` contains 766 unit-chatter voice lines. It is retained as source data for future unit-chatter subtitle work, but CR does not generate runtime files from it yet because ordinary ODF-driven unit chatter does not pass through `ScriptSubtitles.Play()`.

The CSV source files are kept verbatim. CR's current bitmap overlay font contains only printable ASCII glyphs, so generated campaign subtitle assets apply display-only normalization:

1. typographic quotes/dashes/ellipsis are converted to ASCII;
2. Cyrillic phrases carrying `{{English gloss}}` annotations are replaced by their supplied English gloss;
3. non-Cyrillic `{{annotation}}` text is rendered parenthetically;
4. remaining Cyrillic without a supplied gloss is transliterated to ASCII.

The source transcript is therefore preserved even when the runtime display text must be constrained for the current font.

Run:

```text
python Tools/Import-GoombaTranscripts.py
python Tools/Import-GoombaTranscripts.py --check
```

The check also verifies that CR's subtitle-shaped `Text/*.txt` filename set remains identical to the campaign CSV, while unrelated files in `Text/` are ignored.

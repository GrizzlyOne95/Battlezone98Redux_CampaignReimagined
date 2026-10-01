# Workshop "how to start" images

Annotated menu screenshots for the Workshop description's Install and Play
section. Steam descriptions can only show hosted images, so upload each PNG
(imgur, like the banner) and replace the `URL_*` placeholders below.

Rebuild after retaking the screenshots at 2560x1440:

```
python Tools/Assets/Make-WorkshopGuide.py --main-menu MAIN.png --single-player SP.png --instant-action IA.png --campaign CAMPAIGN.png
```

The button boxes are fixed 2560x1440 coordinates in `STEPS` inside that script.

## BBCode for the Install and Play section

```
[b]1. First-time install[/b]
[list=1]
[*] Subscribe and let Steam finish downloading. Do [b]not[/b] enable anything in the Mods menu.
[*] Launch the game and open [b]Single Player[/b].
[img]URL_STEP1[/img]
[*] Open [b]Instant Action[/b] (bottom right).
[img]URL_STEP2[/img]
[*] Select [b]! SETUP / REPAIR - Open Community Patch[/b] and press [b]Launch[/b]. It installs the complete OpenShim suite and shows the result.
[img]URL_STEP3[/img]
[*] If it says [b]RESTART REQUIRED[/b], [b]exit the game completely[/b], then start it again. The files are put in place while the game is closed.
[/list]

[b]2. Where the campaign is[/b]
Open [b]Single Player > Custom Campaign[/b] (top right), select [b]Campaign Reimagined[/b] and press [b]Launch[/b].
[img]URL_STEP4[/img]
[img]URL_STEP5[/img]
```

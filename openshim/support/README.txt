OpenShim session log upload - opt-in, for testers
=================================================

Nothing in this folder runs unless you deliberately set it up.

Installing or subscribing to Campaign Reimagined does NOT enable any
upload. These are just files sitting in the mod folder. Two separate
things both have to be true before a single byte is ever sent:

  1. A webhook URL has been saved on your machine, by you, by running
     the setup step below. There is no webhook in this mod, in the
     repository, or anywhere in the downloaded content.

  2. The wrapper has been added to your Steam launch options. The game
     starts the wrapper; the wrapper does not start itself. Empty launch
     options means nothing ever uploads, no matter what is in here.

Remove either one and uploading stops. If you did not go looking for
this, you are already in the default state and there is nothing to do.


Who this is for
---------------

The test crew, and anyone who wants to hand over a full session's logs
after hitting a bug instead of hunting down files by hand. You need the
webhook URL, which is pinned in the project's private Discord channel -
ask there if you want to be included.

If you just want to report a bug, you do not need any of this. A clear
description of what you were doing is worth more than a log dump.


What it sends, when it is on
----------------------------

After each wrapped session it compresses and posts:

  - openshim.log and openshim_crash.log
  - a snapshot of the previous session's openshim.log, taken before
    launch, because the game overwrites it on the next start
  - BZLogger.txt and its pre-launch snapshot
  - winmm_proxy.log / dsound_proxy.log if present
  - multi.ini
  - session crash minidumps and buffer-capture files
  - a small meta.txt: UTC time, hostname, in-game player name, exit
    code, wrapper version

Your hostname and in-game name are in that list. If you are not
comfortable with that, do not set this up.

It runs outside the game process, so it still fires after a crash -
which is the whole point.


Setup (Windows)
---------------

Copy the wrapper somewhere stable and run its setup once:

  mkdir "%LOCALAPPDATA%\openshim"
  copy openshim_wrap.ps1 "%LOCALAPPDATA%\openshim\"
  copy openshim_wrap.bat "%LOCALAPPDATA%\openshim\"
  powershell -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\openshim\openshim_wrap.ps1" -Setup

Then set Steam launch options (Steam -> Battlezone 98 Redux ->
Properties -> Launch Options):

  cmd /c ""%LOCALAPPDATA%\openshim\openshim_wrap.bat" %command%"

The doubled quotes are load-bearing. Copy that line exactly.

A console window stays open while you play - that is the wrapper
waiting to bundle on exit. Closing it cancels the upload, not the game.


Setup (Linux / Steam Deck)
--------------------------

  mkdir -p ~/.local/share/openshim
  cp openshim_wrap.sh ~/.local/share/openshim/
  ~/.local/share/openshim/openshim_wrap.sh --setup

Launch options, native or Flatpak:

  WINEDLLOVERRIDES="winmm=n,b;dsound=n,b" "${XDG_DATA_HOME:-$HOME/.local/share}/openshim/openshim_wrap.sh" %command%

Snap needs its own line, because snapd remaps HOME:

  WINEDLLOVERRIDES="winmm=n,b;dsound=n,b" "$SNAP_USER_COMMON/.local/share/openshim/openshim_wrap.sh" %command%

The Steam snap runtime has neither curl nor python3, so bundles park in
the outbox and a host-side systemd user timer drains them.


Turning it off
--------------

Clear your Steam launch options. That is enough - the wrapper is never
invoked again. To also remove the saved webhook, delete the upload.conf
next to the wrapper (%LOCALAPPDATA%\openshim on Windows,
~/.local/share/openshim on Linux).


Where this comes from
---------------------

These files are a copy of the upload/ directory in
GrizzlyOne95/Battlezone98Redux_Shim, refreshed automatically when the
Workshop package is built. Report problems there, not against the
campaign content.

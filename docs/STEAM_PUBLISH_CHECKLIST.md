# Steam Workshop publish checklist

This checklist defines when a Campaign Reimagined Workshop publication is complete.
It applies to real uploads of Workshop item `3686673790`. Dry runs do not require
public Steam edits.

## Canonical public-text sources

Keep the different Steam surfaces separate:

| Surface | Canonical source |
|---|---|
| Workshop item description | `docs/workshop_description.bbcode` in Campaign Reimagined |
| Workshop update/change note | `change_note` supplied to the publish workflow |
| Project changelog | `CHANGELOG.md` in Campaign Reimagined |
| Roadmap discussion | `Docs/STEAM_ROADMAP_BBCODE.txt` in `GrizzlyOne95/Battlezone98Redux_Shim` |

Roadmap discussion:

`https://steamcommunity.com/workshop/filedetails/discussion/3686673790/216888303627073611/`

The OpenShim BBCode file is the canonical editable source for that discussion.
Do not maintain a second independent copy in Campaign Reimagined.

## Before a real Workshop upload

1. Confirm the candidate has completed the normal GOG deploy/test path.
2. Update `CHANGELOG.md` for player-facing changes included in the candidate.
3. Review `docs/workshop_description.bbcode` and update it if the public item
   description needs to change.
4. Review all OpenShim, EXU, bzfile, and CR changes entering the upload against
   `Battlezone98Redux_Shim/Docs/STEAM_ROADMAP_BBCODE.txt`.
5. Update the roadmap BBCode so completed work, changed implementation status,
   newly discovered constraints, and newly relevant roadmap items accurately
   reflect the build being published.
6. Supply a concise `change_note` describing the actual Workshop update.

A real publish should not knowingly ship roadmap-relevant changes while leaving
`STEAM_ROADMAP_BBCODE.txt` stale.

## After the Workshop upload succeeds

1. Open the Steam Roadmap discussion:
   `https://steamcommunity.com/workshop/filedetails/discussion/3686673790/216888303627073611/`
2. Edit the discussion post.
3. Replace its body with the complete current contents of
   `Battlezone98Redux_Shim/Docs/STEAM_ROADMAP_BBCODE.txt`.
4. Save the Steam post and verify the rendered discussion matches the canonical
   BBCode source closely enough that no section was truncated, reverted, or
   accidentally reformatted.
5. Let Steam download Workshop item `3686673790` and perform the normal final
   Steam runtime verification.

**The Workshop publication is not considered complete until the Roadmap
 discussion has been synchronized.**

Even when an upload does not materially change roadmap status, perform the
synchronization check. The live Steam post should never be allowed to drift from
the canonical `STEAM_ROADMAP_BBCODE.txt` source.

## Publication completion record

When reporting that a Workshop publish is complete, include all of the
following:

- Workshop upload succeeded;
- Workshop change note used;
- Roadmap BBCode reviewed/updated;
- Steam Roadmap discussion synchronized;
- subscribed Workshop item downloaded for final verification;
- final Steam test result.

If the upload succeeds but the Roadmap discussion cannot be updated, report the
publication as **uploaded but not fully synchronized**, with the Roadmap update
left as an explicit outstanding action.

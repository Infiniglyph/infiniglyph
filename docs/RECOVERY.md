# Recovering the first public checkpoint

The annotated tag `checkpoint-2026-11-08` is the baseline to return to if a
later change breaks the game. Keep this tag fixed; give later checkpoints new
names. A commit only exists online after it has been pushed.

## Restore without touching current work

The Greefer milestone is preserved by `checkpoint-2026-11-09-greefer` on
`feat/greefer-encounter`. Its independent offline bundle is
`infiniglyph-greefer-2026-11-09.bundle` in the parent workspace's `backups`
folder. Use that tag/bundle in the commands below to recover the first boss
encounter. `checkpoint-2026-11-08-defender-exhaustion` retains the immediately
preceding combat update; all earlier tags remain unchanged.

Run this from a parent folder, choosing an unused destination:

```powershell
git clone --branch checkpoint-2026-11-08 https://github.com/Infiniglyph/infiniglyph.git infiniglyph-recovered
```

Open `infiniglyph-recovered/project.godot` in Godot 4.7.2 and run with F5.
Godot regenerates its `.godot` cache. The clone starts at the checkpoint in
detached HEAD mode. To develop a fix there, run:

```powershell
git -C infiniglyph-recovered switch -c recovery-fix
```

Your original working folder remains available, including any uncommitted work.
You can also inspect the checkpoint directly at
[the recovery tag](https://github.com/Infiniglyph/infiniglyph/tree/checkpoint-2026-11-08).

## Offline backup

An independent Git bundle named `infiniglyph-checkpoint-2026-11-08.bundle` is
stored in the parent workspace's `backups` folder. It contains the repository's
commits, branch and checkpoint tag. Copy it to another drive for an additional
offline copy. Restore it into a new folder:

```powershell
git clone "C:\path\to\infiniglyph-checkpoint-2026-11-08.bundle" infiniglyph-offline
git -C infiniglyph-offline switch --detach checkpoint-2026-11-08
```

## Save future work

The expanded city/suburbs/countryside is preserved by
`checkpoint-2026-11-10-outer-world` on `feat/outer-world`. Its independent
complete-history offline bundle is `infiniglyph-outer-world-2026-11-10.bundle`
in the parent workspace's `backups` directory. All previous checkpoints remain
available, including the compact HUD and Greefer milestones.

The compact player HUD is preserved by `checkpoint-2026-11-09-minimal-hud`
on `ui/minimal-player-hud`. Its independent complete-history offline bundle is
`infiniglyph-minimal-hud-2026-11-09.bundle` in the parent workspace's `backups`
directory.

The Greefer rematch and animation/contact pass is preserved separately by
`checkpoint-2026-11-09-greefer-readability` on `fix/greefer-readability`.
Its complete-history offline bundle is
`infiniglyph-greefer-readability-2026-11-09.bundle` in the parent workspace's
`backups` directory. The original Greefer checkpoint remains unchanged.

From the game repository:

```powershell
git status
git add .
git commit -m "Describe the working change"
git push
```

For another tested milestone, create a new annotated tag and push it:

```powershell
git tag -a checkpoint-YYYY-MM-DD -m "Describe this verified milestone"
git push origin checkpoint-YYYY-MM-DD
```

The source backup excludes generated caches, captures, logs, credentials and
personal save files. Inventory saves stay in Godot's per-user application-data
folder; source recovery does not restore or erase them.

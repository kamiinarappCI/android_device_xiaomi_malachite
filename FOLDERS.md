# Malachite folder layout

Everything for the Malachite ROM project lives in this one folder
(E:\LineageOS-23.2-Malachite). Sessions and memory are keyed to this path.

Tracked in git (branch master): notes, patches, tools, src, handoff files, org drafts.

Not tracked (listed in .git/info/exclude), large or generated:
- builds\                 release and test zips/images
- firmware\               stock images
- backups\                keys and repo bundles
- ksu-modules\            KSU module builds
- TelegramGroupBot\       group moderator worker
- malachite-research\     datasets and code traces
- rom-analysis\           other ROMs taken apart (still at E:\Android\Malachite\rom-analysis, locked by a process)
- evox-port\              loose Evolution X port files
- crdroid-17.0-workspace\ git worktree on feature/crdroid-17.0

Old scripts that still say E:\Android\Malachite\... need that path to point here
(see the junction note once rom-analysis has moved).

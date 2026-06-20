# YSL ReaPack

REAPER tools by **Yoon-Soo Lee**.

## Packages

### Region Sync Manager

A region collaboration and management tool for REAPER.

- Staged region editing
- CSV import and export
- UID-based diff and 3-way merge
- Region QC and bulk tools
- Automatic backups and crash-recovery drafts
- English and Korean interface

### Sound Lib Manager Pro

A keyword and tag manager for sound libraries.

- Fast keyword and tag search
- Favorites, usage sorting, and Smart Collections
- Automatic tag suggestions
- Media Explorer handoff
- External JSON storage and rotating backups
- CSV import and export
- 8-second delete undo
- English and Korean interface

## Requirements

- REAPER
- ReaPack
- ReaImGui
- `js_ReaScriptAPI` is optional for Region Sync Manager file dialogs

## Install with ReaPack

After this repository has been uploaded to GitHub and the `deploy` workflow has finished successfully, import this URL in REAPER:

```text
https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YSL-ReaPack/main/index.xml
```

In REAPER:

1. Open **Extensions > ReaPack > Import repositories**
2. Paste the URL above after replacing `YOUR_GITHUB_USERNAME`
3. Synchronize packages
4. Search for `Region Sync Manager` or `Sound Lib Manager Pro`

## Repository maintenance

The GitHub Actions workflows validate the script metadata and automatically rebuild `index.xml` with the official `reapack-index` tool whenever the `main` or `master` branch is updated.

For a new public release:

1. Update the script's `@version`
2. Update `@changelog`
3. Commit and push
4. Wait for the `deploy` workflow to finish

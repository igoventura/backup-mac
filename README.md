# backup-mac

Interactive macOS backup/restore/validate utility. Backs up what matters — apps, Homebrew packages, fonts, dotfiles, Claude config, projects, Desktop, Documents, and Downloads — with human-in-the-loop selection via `fzf`.

## Quick start

```
./bm.sh
```

Opens a menu to pick backup, restore, or validation.

## Scripts

### `bm.sh`

Main menu — launches any of the 4 scripts below.

### `backup-mac.sh`

Creates a backup on your Desktop.

```
./backup-mac.sh
```

| Step | What | Interactive? |
|------|------|:---:|
| 1 | Brewfile — all top-level brew formulae + casks | fzf |
| 2 | Mac Apps — from `/Applications` and `~/Applications` | fzf |
| 3 | Fonts — from `~/Library/Fonts` and `/Library/Fonts` | fzf |
| 4 | Dotfiles — `.zshrc`, `.gitconfig`, `.ssh/config`, `~/.config/`, etc. | fzf |
| 5 | Claude config — files from `~/.claude/` (CLAUDE.md, agents, skills, hooks…) | Yes/No + fzf |
| 6 | Projects — git repos from `~/dev` and `~/Developer/Personal` (copy with rsync) | Yes/No + fzf |
| 7 | Desktop — full `~/Desktop/` copy | Yes/No |
| 8 | Documents — full `~/Documents/` copy | Yes/No |
| 9 | Downloads — full `~/Downloads/` copy | Yes/No |
| 10 | Zip — compress into 1GB split parts for upload | Yes/No |

Output: `~/Desktop/backup-YYYY-MM-DD-HHMMSS/` (or `.zip.part-*` if zipped).

Repos with unpushed commits are flagged `[UNPUSHED: N]` in the fzf picker.

### `restore-mac.sh`

Restore from a backup directory or zip parts.

```
./restore-mac.sh ~/Desktop/backup-2026-06-20-143022/
./restore-mac.sh ~/Desktop/backup-2026-06-20-143022.zip.part-aa
```

Flow:
1. If zip parts detected → reassemble and extract
2. Brewfile (`brew bundle install`)
3. Dotfiles → `~/`
4. Claude config → `~/.claude/`
5. Projects → directory of your choice
6. Desktop / Documents / Downloads
7. Print manual reinstall lists (apps, fonts)

Defaults: Brewfile and dotfiles default to **Yes**. Everything else defaults to **No**.

### `validate-backup.sh`

Check a zip file's integrity and preview contents.

```
./validate-backup.sh ~/Desktop/backup-2026-06-20-143022.zip.part-aa
```

Checks: gzip integrity, tar readability, entry count, category coverage.

Tree views for: Claude config files, dotfiles, Mac Apps list (`apps.txt`), and Brew apps (`Brewfile`). Uses the `tree` command if installed (prompts to `brew install tree` on first run), with a depth-indented fallback.

Sample tree output:

```
── Claude config ──
    └── .claude
        ├── agents
        │   └── orchestrator.agent.md
        ├── CLAUDE.md
        └── settings.json

── Dotfiles ──
    ├── .zprofile
    ├── .zshenv
    └── .zshrc
```

### `validate-restore.sh`

Compare what's restored on the current machine vs what's in a backup.

```
./validate-restore.sh ~/Desktop/backup-2026-06-20-143022/
```

Reports ✓ present / ✗ missing for: Brewfile, Mac Apps, Fonts, Dotfiles, Claude config, Projects, Desktop/Documents/Downloads file counts.

## Example workflow

```bash
# 1. Back up
./backup-mac.sh

# 2. Validate the zip
./validate-backup.sh ~/Desktop/backup-2026-06-20-143022.zip.part-aa

# 3. Upload zip parts to Google Drive (manual)

# 4. On new machine: download zip parts, then
./restore-mac.sh ~/Desktop/backup-2026-06-20-143022.zip.part-aa

# 5. Check what made it
./validate-restore.sh ~/Desktop/backup-2026-06-20-143022/
```

## Notes

- **Zip parts**: 1GB each, upload all parts to Google Drive.
- **Projects**: excludes `node_modules`, `.venv`, `venv`, `__pycache__`, `*.pyc`.
- **Large folders**: Desktop/Documents/Downloads warn if > 1GB before copying.

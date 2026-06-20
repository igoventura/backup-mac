# backup-mac

Interactive macOS backup/restore/verify utility. Backs up what matters — apps, Homebrew packages, fonts, dotfiles, projects, Desktop, Documents, and Downloads — with human-in-the-loop selection via `fzf`.

## Requirements

- **fzf** — `brew install fzf`
- **Homebrew** — for Brewfile backup/restore
- **Git** — for project scanning

## Scripts

### `backup-mac.sh`

Creates a backup on your Desktop.

```
./backup-mac.sh
```

Walks through each category, letting you pick what to keep via `fzf` multiselect:

| Step | What | Interactive? |
|------|------|:---:|
| 1 | Brewfile — all top-level brew formulae + casks | Auto |
| 2 | Mac Apps — from `/Applications` and `~/Applications` | fzf |
| 3 | Fonts — from `~/Library/Fonts` and `/Library/Fonts` | fzf |
| 4 | Dotfiles — `.zshrc`, `.gitconfig`, `.ssh/config`, `~/.config/`, etc. | fzf |
| 5 | Projects — git repos from `~/dev` and `~/Developer/Personal` (copy with rsync) | Yes/No + fzf |
| 6 | Desktop — full `~/Desktop/` copy | Yes/No |
| 7 | Documents — full `~/Documents/` copy | Yes/No |
| 8 | Downloads — full `~/Downloads/` copy | Yes/No |
| 9 | Zip — compress into 1GB split parts for upload | Yes/No |

Output lands in `~/Desktop/backup-YYYY-MM-DD-HHMMSS/` (or `.zip.part-*` files if zipped).

**Projects with unpushed commits** are flagged in the fzf list as `[UNPUSHED: N]` so you know which repos have local work not yet pushed to remote.

### `restore-mac.sh`

Restore from a backup directory or zip parts.

```
./restore-mac.sh ~/Desktop/backup-2026-06-20-143022/
# or from zip parts:
./restore-mac.sh ~/Desktop/backup-2026-06-20-143022.zip.part-aa
```

Flow:
1. If zip parts detected → reassemble and extract
2. Restore Brewfile (`brew bundle install`)
3. Restore dotfiles to `~/`
4. Restore projects to a directory of your choice
5. Restore Desktop / Documents / Downloads
6. Print manual reinstall lists (apps, fonts)

Defaults: Brewfile and dotfiles default to **Yes**. Desktop, Documents, Downloads, and Projects default to **No** (to avoid overwriting).

### `verify-mac.sh`

Check what's been restored vs what's in the backup.

```
./verify-mac.sh ~/Desktop/backup-2026-06-20-143022/
```

Reports per category:
- ✓ present / installed
- ✗ missing

Covers: Brewfile formulae + casks, Mac Apps, Fonts, Dotfiles, Projects, Desktop/Documents/Downloads file counts.

## Example workflow

```bash
# 1. Back up your machine
./backup-mac.sh
# Creates ~/Desktop/backup-2026-06-20-143022/

# 2. Zip for upload (or do it from the script)
# Script asks at the last step — say yes

# 3. Upload to Google Drive (manual)
# Files: backup-2026-06-20-143022.zip.part-aa, .part-ab, ...

# 4. On new machine: download zip parts to ~/Desktop/

# 5. Restore
./restore-mac.sh ~/Desktop/backup-2026-06-20-143022.zip.part-aa

# 6. Verify
./verify-mac.sh ~/Desktop/backup-2026-06-20-143022/
```

## Notes

- **Zip parts**: 1GB each. Google Drive free tier is 15GB. Manually upload/download all parts.
- **Projects**: `rsync` excludes `node_modules`, `.venv`, `venv`, `__pycache__`, `*.pyc`.
- **Projects**: Repos with unpushed local commits are flagged `[UNPUSHED: N]` in the fzf picker.
- **Desktop/Documents/Downloads**: Warns if folder is larger than 1GB before copying.

# Moving this configuration to another machine

## The design

Keep three kinds of settings separate:

| Location | Responsibility | In Git? |
| --- | --- | --- |
| `init.el`, `early-init.el`, `lisp/init-*.el` | Startup and feature configuration | Yes, except the overrides below |
| `lisp/init-personal.el` | Shared theme, preferences, enabled personal modules | Yes |
| `lisp/init-local-package-manifest.el` | Local package URLs, recorded commits and patches | Yes |
| `lisp/init-preload-local.el` | Machine-specific choices needed before modules load | No |
| `lisp/init-local.el`, `custom.el` | Machine-specific paths, fonts and final overrides | No |
| `pkg/` | Independent package checkouts and local native tools | No; restore from the manifest |
| `elpa-*`, `tree-sitter/`, `.cache/`, history and session files | Installed dependencies and generated state | No |

Startup checks package entry files and minimum Emacs versions. It does not run
Git, update repositories, or build native tools. Personal packages load on first
use through ordinary autoloads. The restore command and health report are also
autoloaded, so their implementations are not read during startup.

ELPA packages retain Purcell's existing installation workflow: the first start
can download missing packages, while later starts use installed packages. There
is no second package manager or custom dependency resolver.

The personal layer was measured separately on Windows/Emacs 31.1 on 2026-09-23,
after package activation, in three fresh batch processes per version. Its median
load time fell from 349 ms to 58 ms after making comb-grid lazy. This is a bounded
comparison of the personal layer, not a measurement of full graphical startup.

## First installation

Install Emacs and Git. Emacs 29.1 or newer is needed for the complete personal
setup; the base configuration retains its 28.1 minimum and skips comb-grid on
older versions. SVG support is needed for the grid editor and libxml2 support
for EPUB rendering.

Clone this repository into the directory that Emacs uses as
`user-emacs-directory`, usually `~/.emacs.d`:

```sh
git clone https://github.com/ZEPHYR65537/emacs.d.git ~/.emacs.d
cd ~/.emacs.d
emacs -Q --batch -l scripts/bootstrap-local-packages.el -f sanityinc/bootstrap-local-packages
```

The restore script determines the configuration root from its own location, so
it also works when invoked using an absolute filename from another directory.
In PowerShell, use `& 'C:/path/to/emacs.exe'` if Emacs is not on PATH. A different
home directory or an XDG configuration directory is supported: use its actual
path rather than copying the example literally.

The script restores the four independent packages at the recorded commits and
reapplies the small MMIX patch from `patches/`. It never resets, updates or deletes
existing checkouts. A checkout at another revision is reported for manual review;
an existing dirty checkout is never patched. The already-applied recorded patch
is accepted. A failed clone/checkout is retained for inspection, not deleted.

Start Emacs, let the normal ELPA installation finish, and run
`M-x sanityinc/config-doctor`. Restart after restoring packages that were missing
at startup. Missing local packages leave their features disabled and print an
installation hint in `*Messages*`; they do not stop the rest of startup.

## Machine-specific choices

To enable fewer personal modules, create `lisp/init-preload-local.el`:

```elisp
(setq sanityinc/personal-modules '(init-nov init-comb-grid))
(provide 'init-preload-local)
```

Leave the list at its default to enable all four. Feature-specific code remains
in its own adapter. Packages with broken installed code still report real errors;
the loader only skips missing or unsupported packages.

Use `lisp/init-local.el` for final display preferences:

```elisp
(custom-set-faces '(default ((t (:height 180)))))
(provide 'init-local)
```

An executable location used while a module loads, such as
`sanityinc/mmix-bin-directory`, belongs in `init-preload-local.el`. Prefer PATH
where possible. Store portable preferences in `init-personal.el` so they travel
with the configuration. Neither override file is required for startup.

## Native dependencies

Install native programs for the destination OS and CPU. Do not copy Windows
executables, native compilation caches, or tree-sitter DLLs to macOS/Linux.

| Feature | External requirements |
| --- | --- |
| LaTeX | TeX distribution, latexmk, Ghostscript; optional Texlab, ChkTeX, latexindent and a PDF viewer |
| LaTeX on Windows | A POSIX shell such as Git for Windows' `sh`, discoverable from PATH |
| Typst | Typst, Tinymist and a compatible Typst tree-sitter grammar |
| MMIX | `mmix`, `mmixal`, `mmotype` on PATH or under `pkg/mmix/` |
| EPUB | `unzip` on PATH and Emacs with libxml2; NOV also supports configured alternatives such as bsdtar |
| Static site | The project's build tools; preview/build may need Node or make4ht, deployment may need rsync and ssh |
| Grid editor | Emacs 29.1+ with SVG image support |

See [the LaTeX/Typst guide](latex-typst.md) for tool discovery and grammar setup.
The tree-sitter loader only remaps modes when their grammar is actually loadable.
Install or rebuild grammars on the destination machine.

### Building MMIX

Prebuilt tools on PATH are sufficient. To build, obtain the recorded MMIXware
source and install a C compiler plus CWEB's `ctangle`:

```sh
git clone https://gitlab.lrz.de/mmix/mmixware.git .cache/mmixware
git -C .cache/mmixware checkout --detach 90d53fbf5871d697506ca71a8bb3c0b2f670737e
```

On Windows, from the configuration directory, run:

```powershell
./scripts/build-mmix.ps1 -SourceDirectory .cache/mmixware
```

This uses GCC and ctangle, builds all three programs before installing them,
and avoids CPU-specific optimization flags. It never runs during Emacs startup.
On Linux/macOS, use MMIXware's Makefile with CWEB, Make and a C compiler:

```sh
make -C .cache/mmixware CC=cc CFLAGS='-std=gnu17 -O2' mmix mmixal mmotype
mkdir -p pkg/mmix
cp .cache/mmixware/mmix .cache/mmixware/mmixal .cache/mmixware/mmotype pkg/mmix/
```

These are native build recipes, not a claim that every toolchain has been tested.

## Updates and reproducibility

Commit and push the portable configuration, manifest, scripts and patches before
migrating through Git. Uncommitted files are not included in a clone. Do not force
add ignored caches, native binaries or whole nested repositories.

Local package commits are pinned. When developing a package, keep using its own
repository normally. After testing an update, publish that package commit and
update its revision in the manifest. Keep any intentional local patch under
`patches/`; the recorded MMIX patch is expected to appear as a working-tree change.
Run the restore command again to verify recorded revisions without updating them.

ELPA versions are **not locked**: a fresh install gets currently available
versions, as in the original configuration. Updates remain explicit through
`M-x package-list-packages`, then `U`, then `x`. Test package updates before
replicating them, especially changes to AUCTeX or preview-auto. Exact historical
ELPA reproduction would require retaining the corresponding source archives;
copying compiled package trees across platforms is not a replacement.

## Checks

From an isolated copy of the configuration:

```sh
emacs -Q --batch -l tests/init-portability-test.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l scripts/test-startup.el
```

The first command is offline and covers missing packages, lazy loading, version
gates, grammar availability, and restoration that preserves existing work. The
second performs normal startup, including early-init, personal modules and
after-init hooks; it can download ELPA packages and write generated state.

CI keeps the Linux Emacs-version matrix and adds Linux/macOS/Windows checks for
the personal setup. CI does not replace graphical checks of fonts, SVG, EPUB,
LaTeX preview or external viewers. Measure normal graphical startup separately
if startup speed changes; `M-x sanityinc/require-times` shows module load costs.

# Production LaTeX and Typst environment

This configuration extends Purcell's Emacs setup with a maintainable,
cross-platform authoring environment for LaTeX and Typst.  Windows, GNU/Linux,
and macOS use the same core modules; the few platform-specific details are
isolated to executable discovery and PDF viewer integration.

The configuration follows Purcell's existing `package.el` conventions:
required packages use `require-package`, optional or version-dependent features
use `maybe-require-package`, and each language has a focused module under
`lisp/`.

## Architecture

### LaTeX

| Component | Responsibility |
| --- | --- |
| AUCTeX | Major mode, document parsing, engine selection, compilation, and viewer integration |
| RefTeX | Labels, references, citations, and multi-file navigation |
| preview-latex + preview-auto | Incremental in-buffer rendering near the editing point |
| CDLaTeX | Structured, TAB-driven insertion of environments and commands |
| Laas | Fast, context-aware mathematical snippets |
| Corfu | Displays AUCTeX and Eglot completion-at-point candidates |
| Texlab + Eglot | Completion, navigation, formatting, and diagnostics |
| latexmk | Reliable one-shot and explicitly enabled continuous document builds |

Texlab does not build PDFs on save in this setup.  AUCTeX/latexmk owns document
builds, while Texlab owns language intelligence and diagnostics.  This prevents
two build systems from compiling the same document.

When Texlab is unavailable, the buffer remains fully editable and AUCTeX's
ChkTeX Flymake backend is enabled if `chktex` is installed.

### Typst

| Component | Responsibility |
| --- | --- |
| typst-ts-mode | Tree-sitter syntax highlighting, indentation, editing, and compile/watch commands |
| Tinymist + Eglot | Completion, navigation, formatting, and diagnostics |
| typst-preview.el + Tinymist | Browser live preview with partial rendering |
| Typst CLI | One-shot PDF compilation and continuous watch |

Tinymist's LSP-side PDF export is disabled.  PDF generation belongs to the
explicit compile, watch, or preview command, so editing does not create a
second background export pipeline.

If the Typst grammar is missing, `.typ` files open in `text-mode` instead of
failing.  After installing the grammar and restarting Emacs they open in
`typst-ts-mode`.

## Compatibility

The repository follows the Emacs versions supported by upstream Purcell.
AUCTeX supports the full baseline.  `typst-ts-mode` additionally requires
Emacs 29.1 or newer and a tree-sitter-enabled build.

Emacs 30.2 is the current local validation baseline, not a hard-coded runtime
requirement.  Later stable Emacs releases, including 31.x, should be validated
with the test matrix below before becoming the primary runtime.

The modules do not encode an Emacs installation path, a username, a TeX Live
release year, or an operating-system package-manager path.

## Startup performance

The lightweight LaTeX and Typst registrations are loaded during startup, but
AUCTeX major modes, Eglot servers, preview engines, and document watchers do
not load or start until a matching document is opened.  Unrelated language
configuration uses `sanityinc/require-config-after-load`: an already-installed
mode loads its configuration on first use, while a missing mode still loads
its original module immediately so Purcell's `require-package` declaration can
install it.  Projectile loads on the first `C-c p`, Diff-hl on the first file,
and optional Pulsar highlighting during idle time.

The working target remains a warm graphical startup median of at most 5
seconds, with starts above 10 seconds investigated as performance failures.
On the current Windows validation machine, the latest three normal Emacs 30.2
GUI starts measured 38.4, 34.5, and 39.2 seconds: a 38.4-second median.  Their
main-init median was 19.4 seconds.  An earlier single optimized run reached
28.1 seconds, down from the original 47.1 seconds, but repeated measurements
show that it was not a reliable median.  The target is not met and remains an
explicit limitation rather than being hidden by moving LaTeX/Typst
initialization onto the first edit.

Purcell's `lisp/.dir-locals.el` deliberately sets `no-byte-compile` for the
configuration modules.  A local byte-compilation experiment was therefore
rejected rather than bypassing that repository policy.  Reconsidering compiled
or generated configuration would be a separate architectural decision, not a
routine startup tweak.

The always-on `require` timing advice was also tested in an otherwise identical
isolated launch.  Enabling and disabling it both took about 14.3 seconds before
the normal after-init hooks, so it was retained; removing useful diagnostics
would not solve the measured bottleneck.  On machines where native Windows
file loading remains slow, keeping one server process alive and using
`emacsclient` avoids paying the full startup cost for each document.

Measure several fresh processes after package installation or upgrades.  The
first launch may legitimately spend extra time compiling packages and should
be recorded separately from warm starts.  Purcell's `M-x
sanityinc/require-times` view identifies expensive module loads.

## External tools

Packages installed from GNU ELPA, NonGNU ELPA, and MELPA are declared in the
modules and installed by Purcell's normal startup machinery.  Native programs
remain the responsibility of the operating system or the user.

### Required for the complete LaTeX workflow

- A TeX distribution containing `latex`, a PDF-capable engine, and `latexmk`.
- `chktex` for diagnostics.
- `latexindent` for formatting through Texlab.
- [Texlab](https://github.com/latex-lsp/texlab) for LSP features.
- Ghostscript for preview-latex image generation.  TeX Live's `rungs` wrapper,
  MiKTeX's `mgs`, and a normal `gs` executable are discovered by AUCTeX.
- On Windows, a POSIX-compatible shell supported by AUCTeX.  Git for Windows'
  `sh.exe`, MSYS2, or Cygwin is suitable; discovery is automatic when `sh` or
  `git` is on `PATH`.
- A PDF viewer; SyncTeX support is strongly recommended.

Typical distributions are TeX Live on GNU/Linux and Windows, MacTeX on macOS,
or MiKTeX where preferred.  Use the distribution's supported installer and
ensure its command-line programs are visible on `PATH`.

### Required for the complete Typst workflow

- [Typst](https://typst.app/docs/) for compilation and watch mode.
- [Tinymist](https://github.com/Myriad-Dreamin/tinymist) for Eglot and browser
  live preview.
- The [Typst tree-sitter grammar](https://github.com/uben0/tree-sitter-typst).

### PDF viewers

- Windows: SumatraPDF is selected automatically when available and is
  configured for forward and inverse SyncTeX.
- macOS: AUCTeX's built-in `open`, Preview.app, Skim, and `displayline`
  integrations remain available.  Skim/`displayline` is the usual choice for
  SyncTeX.
- GNU/Linux: AUCTeX's built-in Evince, Okular, Zathura, Sioyek, and `xdg-open`
  integrations remain available.  Select one that is installed locally.

Typst's one-shot preview uses SumatraPDF on Windows when present and otherwise
uses Emacs's portable file-URL opener.  This can be replaced by customizing
`typst-ts-preview-function`.

## Executable discovery and local overrides

The normal, portable installation is to put `texlab`, `typst`, and `tinymist`
on `PATH`.  Graphical macOS/Linux sessions import the login-shell environment
through the existing `exec-path-from-shell` setup.

For a machine-local installation that must not affect system `PATH`, executables
can be placed under the ignored configuration cache:

```text
.cache/bin/texlab[.exe]
.cache/bin/typst[.exe]
.cache/bin/SumatraPDF.exe
.cache/lsp/tinymist/tinymist[.exe]
```

Platform suffixes are resolved automatically.  These cache paths are fallback
locations and are not required by the versioned configuration.

Explicit per-machine overrides can be stored in the ignored `custom.el` with
Customize:

- `sanityinc/latex-texlab-program`
- `sanityinc/typst-compiler-program`
- `sanityinc/typst-tinymist-program`

An override may be a command name on `PATH` or an absolute executable path.

## Installing the Typst grammar

On a tree-sitter-enabled Emacs, evaluate or run interactively:

```text
M-x treesit-install-language-grammar RET typst RET
```

Emacs obtains the source from the grammar URL registered by `init-typst.el`.
A working C/C++ toolchain may be required to compile it.  Alternatively, place
a compatible precompiled library named for Emacs's tree-sitter loader in
`~/.emacs.d/tree-sitter/`.

Restart Emacs after installation so the `.typ` auto-mode decision is made from
the newly available grammar.

## LaTeX workflow

### Project metadata

A standalone document is detected from `\\documentclass` and treated as its
own AUCTeX master.  For multi-file documents, set `TeX-master` in each included
file.  A typical main file ends with:

```latex
%%% Local Variables:
%%% mode: latex
%%% TeX-master: t
%%% TeX-engine: default
%%% End:
```

An included chapter can use:

```latex
%%% Local Variables:
%%% mode: latex
%%% TeX-master: "../main"
%%% End:
```

Use `default`, `xetex`, or `luatex` for `TeX-engine`.  AUCTeX, continuous
latexmk, and preview settings are refreshed after file-local variables are
applied, so the selected engine stays consistent across the workflow.

### Generated files and cleanup

The default `TeX-output-dir` is the project-local `build/` directory, resolved
relative to the AUCTeX master document.  AUCTeX creates it when needed.  The
one-shot LaTeXMk command, continuous latexmk watcher, SyncTeX-aware output
lookup, preview-latex region files, preamble dumps, and rendered preview images
all use this directory.  Source directories therefore contain one generated
directory instead of loose `.aux`, `.log`, `.fls`, `.synctex.gz`, preview PNG,
and `_region_.*` files.

Add `/build/` to each LaTeX project's `.gitignore`; the generated directory is
not part of the Emacs configuration repository.  Stop continuous latexmk with
`C-c C-w` before deleting `build/`.  It is safe to delete the directory when no
build is running; the next build or inline preview recreates it.

AUCTeX's `auto/` directory is separate: it stores parsed editor metadata used
for completion, references, and multi-file navigation, and is controlled by
`TeX-auto-save`, not `TeX-output-dir`.  Ignore `/auto/` in projects where it is
generated.  It should not contain compiler or preview output.

Some unusual classes or packages require intermediate files beside the master
document.  Such a project can opt out without changing the shared module:

```elisp
((LaTeX-mode . ((TeX-output-dir . nil))))
```

Place that value in the project's `.dir-locals.el`.  Setting a different
non-hidden relative directory there is also supported.  For multi-file
documents the default `build/` remains relative to the declared `TeX-master`,
so included chapters share the master's output directory.

### Editing and completion

- Corfu displays completion candidates contributed by AUCTeX and Texlab.
- CDLaTeX provides structured insertion and TAB navigation.
- Laas expands common mathematical sequences only in mathematical context;
  for example, `->`, `AA`, fractions, subscripts, and Greek-letter snippets.
- RefTeX supplies labels, references, citations, and table-of-contents
  navigation.
- AUCTeX fontification provides command, section, math, subscript, and
  superscript highlighting.

Useful standard bindings include:

| Binding | Action |
| --- | --- |
| `C-c C-c` | Run the context-sensitive AUCTeX command; the default build command is LaTeXMk |
| `C-c C-v` | View output with the selected AUCTeX viewer |
| `C-c =` | RefTeX table of contents |
| `C-c (` | Insert a label with RefTeX |
| `C-c )` | Insert a reference with RefTeX |
| `C-c [` | Insert a citation with RefTeX |
| `C-c C-q` | Format the buffer through Eglot/Texlab |
| `C-c C-w` | Toggle continuous latexmk for the current master document |
| `C-c C-p C-a` | Toggle automatic inline preview |

Formatting requires both a connected Texlab server and `latexindent`.

### Builds and diagnostics

The default AUCTeX command is LaTeXMk.  It handles repeated TeX passes,
bibliographies, indexes, and cross-reference stabilization.

Continuous mode is deliberately opt-in with `C-c C-w`.  It uses `latexmk
-pvc`, watches saved files, and chooses pdfLaTeX, XeLaTeX, or LuaLaTeX from the
buffer's `TeX-engine`.  The key controls `auctex-cont-latexmk-mode` directly,
so its optional Flymake backend is not installed alongside Texlab.  Stop the
watcher with the same binding before deleting or renaming project files.

Texlab checks the document on open/save, not on every edit, with a short
diagnostics delay.  This keeps large documents responsive.  The AUCTeX ChkTeX
backend is removed before Eglot starts; without Texlab it becomes the fallback
backend instead.

### Incremental inline preview

`preview-auto-mode` scans a bounded region around point after a short idle
interval.  Its upstream implementation retains valid overlays and renders the
nearest stale region, so unchanged formulas are not regenerated.  A full
document build is not launched after every keystroke.

Preamble caching is enabled for pdfLaTeX, where preview-latex can obtain the
largest speed-up.  It is disabled for XeLaTeX and LuaLaTeX because upstream
support is absent or restricted for those engines.

The production default keeps AUCTeX's documented PDF/PS-to-PNG pipeline.
Forcing pdfLaTeX into DVI mode is faster on simple documents, but it fails for
CTeX and custom classes that emit dvipdfmx font specials such as
`pdf:mapline`.  AUCTeX keeps one asynchronous Ghostscript process for a
preview run and prioritizes visible fragments, while preview-auto still avoids
regenerating valid overlays.  Compatible projects may opt into AUCTeX's public
`dvi*`/`dvipng` path with a project-local `preview-image-type`, but that is an
explicit performance tradeoff rather than the portable default.

On Windows, AUCTeX's documented MSYS/Cygwin-style shell requirement is met by
discovering `sh` on `PATH` or deriving Git for Windows' shell from the active
`git` executable.  Only AUCTeX's `TeX-shell` is changed; PowerShell, the user's
interactive shell, and `M-x shell` are untouched.  TeX subprocess buffers use
the portable `C` locale, and `MSYS2_ARG_CONV_EXCL=*` prevents MSYS from
rewriting preview-latex's `/AUCTEXINPUT{...}` macro as a Windows path.

## Typst workflow

When the grammar is ready, opening a `.typ` file enables full tree-sitter
fontification and starts Tinymist through Eglot for file-backed buffers.

| Binding | Action |
| --- | --- |
| `C-c C-c` | Compile the current Typst file and open its PDF |
| `C-c C-p` | Toggle Tinymist browser live preview with partial rendering |
| `C-c C-w` | Toggle `typst watch` continuous compilation |
| `C-c C-q` | Format the buffer through Eglot/Tinymist |

Browser preview may ask for a master file the first time.  Saving that choice
as a file-local value is useful in multi-file Typst projects.  Partial
rendering is enabled, so Tinymist sends the visible portion rather than
rerendering the entire document where its current preview protocol supports
that optimization.

The compiler/watch commands and browser live preview are independent.  Use
watch when another PDF viewer should receive updated files; use browser preview
for source-position-aware interactive work.  Avoid enabling both unless the
project specifically benefits from both outputs.

## Project-local language-server settings

The modules merge conservative Texlab and Tinymist sections into Eglot's
default workspace configuration.  A project can replace these settings in
`.dir-locals.el`, following Eglot's documented format.  For example:

```elisp
((LaTeX-mode
  . ((eglot-workspace-configuration
      . (:texlab
         (:build (:onSave :json-false)
          :chktex (:onOpenAndSave t :onEdit :json-false)
          :diagnosticsDelay 800)))))
 (typst-ts-mode
  . ((eglot-workspace-configuration
      . (:tinymist
         (:exportPdf "never"
          :formatterMode "typstyle"))))))
```

Directory-local values replace the default value for that project.  Include
every setting the project needs rather than assuming a deep merge.

## Graceful degradation

| Missing capability | Result |
| --- | --- |
| Texlab | LaTeX editing/build/preview remain available; AUCTeX uses ChkTeX if present |
| ChkTeX | LaTeX editing/build/preview still work; no fallback lint diagnostics |
| latexindent | Texlab formatting fails cleanly; other LSP features continue |
| Ghostscript | LaTeX source and builds work; inline image preview is unavailable |
| Typst grammar | `.typ` opens in `text-mode` and remains editable |
| Typst CLI | Syntax/LSP features can work; compile and watch commands are unavailable |
| Tinymist | Typst tree-sitter editing and CLI builds work; LSP and browser preview are unavailable |
| PDF viewer | Documents compile; use another viewer or customize the preview function |

No missing optional executable should prevent graphical Emacs from starting.

## Troubleshooting

### Typst opens in text-mode

Evaluate `(treesit-ready-p 'typst t)`.  If it is nil, install the grammar as
described above and restart.  Do not force `typst-ts-mode` before the grammar is
available; upstream mode initialization correctly rejects that state.

### Eglot does not start

Check the resolved executable by evaluating one of:

```elisp
(sanityinc/latex-texlab-executable)
(sanityinc/typst-tinymist-executable)
```

Then check `M-x eglot-events-buffer`.  After changing a server executable or
project configuration, use `M-x eglot-shutdown` and reopen the source file.

### LaTeX preview repeats an error

First disable automatic preview with `C-c C-p C-a`, then run a normal AUCTeX
preview command on a small region.  Fix the TeX/preview-latex error before
reenabling the timer.  If a preview subprocess is stuck, use `C-g` and
`M-x TeX-kill-job`.

### Flymake reports stale-state errors

A managed LaTeX buffer should normally contain only
`eglot-flymake-backend`.  Without Texlab it may contain `LaTeX-flymake`.
Continuous latexmk is configured as a build watcher only and does not add its
Flymake backend.  Do not manually enable flymake-flycheck's `tex-chktex`
backend in the same buffer.

### SyncTeX does not return to Emacs

Ensure an Emacs server is running and that the viewer's inverse-search command
can find `emacsclient` (`emacsclientw.exe` on Windows).  Viewer-specific setup
may still be required for Skim, Zathura, Okular, or Sioyek.

## Maintenance

1. Pull upstream Purcell changes and review conflicts in the two language
   modules and shared Eglot/executable helpers.
2. Update Emacs packages using Purcell's documented package-list workflow:
   `M-x package-list-packages`, then `U`, then `x`.
3. Restart Emacs after package updates; Purcell keeps separate package trees for
   each Emacs major/minor version.
4. Update Texlab, Typst, and Tinymist independently and read their release
   notes for renamed configuration keys.
5. Rebuild the Typst grammar when its ABI or typst-ts-mode queries require it.
6. Run the verification matrix before changing the primary Emacs version.
7. Keep comments and this document synchronized with configuration changes.

Package activation uses Emacs's official quickstart cache in the
version-specific `elpa-MAJOR.MINOR` directory.  `early-init.el` disables the
earlier default activation pass; `init-elpa.el` remains the single owner of
package initialization and Purcell's package selection workflow.

## Verification matrix

For each supported operating system and candidate Emacs version, verify in a
normal graphical session:

- clean startup and a second startup;
- at least three warm-start measurements, with the median and slowest module
  recorded;
- opening standalone and multi-file LaTeX documents;
- placement of one-shot, continuous, and preview-latex output under the
  master's `build/` directory, with no compiler output beside source files;
- AUCTeX parsing, RefTeX labels/citations, CDLaTeX, Laas, and Corfu;
- Texlab connection, completion, navigation, formatting, and exactly one
  diagnostics backend;
- one-shot latexmk, continuous latexmk start/stop, and SyncTeX viewing;
- automatic preview creation, edit invalidation, unchanged-overlay retention,
  and cleanup when the buffer closes;
- Typst grammar/mode/fontification and the no-grammar fallback;
- Tinymist completion, navigation, diagnostics, and formatting;
- Typst one-shot compile, watch start/stop, browser preview, and partial
  rendering;
- behavior with each optional executable deliberately unavailable.

Batch mode may be used for bounded syntax checks, but it is not an acceptance
environment for images, GUI timers, frames, menus, fonts, or external viewer
integration.

## Upstream documentation

- [Purcell emacs.d](https://github.com/purcell/emacs.d)
- [AUCTeX manual](https://www.gnu.org/software/auctex/manual/auctex.html)
- [AUCTeX installation on Windows](https://www.gnu.org/software/auctex/manual/auctex/Installation-under-MS-Windows.html)
- [preview-latex manual](https://www.gnu.org/software/auctex/manual/preview-latex.html)
- [GNU Emacs package quickstart](https://www.gnu.org/software/emacs/manual/html_node/emacs/Package-Installation.html)
- [GNU Emacs Eglot manual](https://www.gnu.org/software/emacs/manual/html_node/eglot/)
- [GNU Emacs tree-sitter manual](https://www.gnu.org/software/emacs/manual/html_node/elisp/Parsing-Program-Source.html)
- [Texlab configuration](https://github.com/latex-lsp/texlab/wiki/Configuration)
- [Laas](https://github.com/tecosaur/LaTeX-auto-activating-snippets)
- [typst-ts-mode](https://codeberg.org/meow_king/typst-ts-mode)
- [typst-preview.el](https://github.com/havarddj/typst-preview.el)
- [Tinymist configuration](https://github.com/Myriad-Dreamin/tinymist/blob/main/editors/neovim/Configuration.md)
- [Typst documentation](https://typst.app/docs/)

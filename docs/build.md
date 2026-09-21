# Build

Read when changing what `rebuild_comfyui.ps1` does, or when a submodule sits at
the wrong commit.

## Submodule lifecycle

The three submodules are not treated alike, and the split is the whole contract.

| Submodule                         | Tracks   | Per build                                  |
| --------------------------------- | -------- | ------------------------------------------ |
| `vendor/ComfyUI`                  | `master` | advanced to upstream's `releases/latest`   |
| `vendor/ComfyUI-GGUF`             | `main`   | restored to the commit recorded here       |
| `vendor/ComfyUI-VideoHelperSuite` | `main`   | restored to the commit recorded here       |

**`vendor/ComfyUI` is wiped and re-checked-out on every build.** The version
comes from the GitHub API's `releases/latest` for the submodule's own remote,
which is deliberate: upstream's `master` carries unstable commits, and a release
tag is the coarsest thing that still moves. Local edits under `vendor/ComfyUI/`
are lost by design. `-version` checks out one tag or commit instead, which is how
a benchmark is re-measured against the version that produced it.

**The custom nodes are never advanced by the build script.** Advancing one is a
decision that gets its own commit, not a side effect of rebuilding. To bump:

```PowerShell
git -C vendor/ComfyUI-GGUF fetch
git -C vendor/ComfyUI-GGUF checkout <sha>
git add vendor/ComfyUI-GGUF
git commit
```

The next build then mirrors the committed pin into the working tree, so a
hand-edit inside a custom-node submodule does not survive a rebuild. The paths
are discovered from `.gitmodules` rather than listed, so a fourth submodule is
pinned by default and only `vendor/ComfyUI` is special-cased by name.

A single `git submodule update --remote` cannot serve all three: it would defeat
the custom-node pins, and it resolves one branch name where these repositories
use two.

**What a tag therefore pins.** The scripts, the workflow set, the custom-node
commits and the `requirements_override.txt` versions. Not ComfyUI, which floats
to whatever upstream released most recently unless `-version` says otherwise. A
benchmark under `docs/hardware-*.md` names the ComfyUI version it was measured
on for that reason; the tag cannot carry it.

## Python requirements

`requirements_override.txt` is the only file `pip` is pointed at. It layers three
things: the CUDA-specific torch pins, then ComfyUI's own `requirements.txt`, then
each custom node's. The torch lines are exact `==` pins, so they hold whatever
the imported files ask for.

Which versions those are, and what caps them, is a comment in the file itself.
That is where it belongs, because it changes whenever one of the three publishes
a new build, and a copy here would be the one that goes stale.

Installation runs with `--upgrade --upgrade-strategy eager`, so a rebuild moves
every unpinned dependency forward. That is the same decision as tracking
ComfyUI's latest release: the build stays current by default, and a version that
has to hold still is named explicitly.

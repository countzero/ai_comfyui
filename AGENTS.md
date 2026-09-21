# AGENTS.md

This file is the canonical agent-instructions source for this repository, read natively by both OpenCode and Claude Code. The repository is a thin wrapper around ComfyUI as a git submodule: three PowerShell scripts, a tracked set of workflow JSON files, and the measured settings for the hardware they run on. It carries the always-on rules as one invariant per area; the contracts behind them are the documents under `docs/`, read on demand through *Reference* at the end.

## Environment invariants

- **Always activate conda in the same command.** The shell is fresh per invocation: `conda activate ComfyUI; python .\vendor\ComfyUI\main.py ...`.
- **`conda run` gives false negatives.** `conda run -n ComfyUI python -c "import torch"` from a non-activated shell reports `ModuleNotFoundError` while torch is installed and working. It resolves to the identical interpreter (`C:\Miniconda\envs\ComfyUI\python.exe`), so the interpreter is not the variable. Never conclude that a package is missing from a bare `conda run`.
- **Nine conda environments exist on this machine and only `ComfyUI` is correct.**
- **Two machines share this repository and neither profile is "the current box".** Confirm the GPU from `GET /system_stats` before trusting any measured number, because the installed model set differs too. `docs/hardware-24gb-blackwell.md`, `docs/hardware-16gb-ada.md`.
- **Do not run `rebuild_comfyui.ps1` without a reason.** It moves submodules. Pass `-version` whenever a specific one is wanted: the default asks the GitHub API for `releases/latest`, which lags a tag that was pushed without being cut as a release, so a bare run can silently reinstall the version already checked out.
- The launch flags, and the benchmark behind each one, are the header comment of `start_comfyui.ps1`.

## Layout

Only the parts that are not obvious from a directory listing:

```
workflows/                   durable copies, tracked, a UI and an API twin each
vendor/ComfyUI/              submodule
  models/                    gitignored, never tracked here
  user/default/workflows/    deployed copies, gitignored, wiped by a re-clone
  blueprints/                upstream's own templates, a separate system
  output/                    generated images
```

## Workflows

`workflows/` is the durable copy; `vendor/ComfyUI/user/default/workflows/` is a publication target that a submodule re-clone wipes. `deploy_workflows.ps1` republishes it and `start_comfyui.ps1` calls that on every launch. Its `$workflows` table is the only place the repo-file-to-sidebar-path mapping is written. Every UI workflow needs an API twin and vice versa. `docs/workflows.md`.

## Measurement discipline

- **Re-read a file before asserting its contents.** Memory of `requirements_override.txt`, of the installed package set, and of a benchmark number is unreliable after context pruning. Read the file.
- **Never quote a timing taken from client wall-clock**, and check `execution_cached` before believing a fast run. `docs/http-api.md` → *Timing a run*.
- A measurement that contradicts a document is a result. Correct the document in the same change rather than leaving both.

## Tool selection

- **`curl` or `Invoke-RestMethod` drive everything.** They cover the whole API, and their output can be filtered before it reaches context.
- **chrome-devtools looks, it does not drive.** Good for screenshots, `list_console_messages`, and `app.loadGraphData` to confirm that a UI workflow opens cleanly. The graph is a `<canvas>` (litegraph), so `take_snapshot` yields a useless accessibility tree and `click(uid)` cannot reach a node. It caches `/api/userdata` aggressively, so cache-bust after a redeploy.
- **No MCP server is installed and none is needed.**

## Context safety

Never read a `.safetensors` or `.gguf` file, and never request `GET /object_info` without a node class; both are megabytes. Filter server output before it reaches the transcript.

## Documentation

`AGENTS.md` carries orientation and repo-global rules only, one invariant per area, each ending in a pointer. A rule stated elsewhere appears here as `` `docs/<file>.md` → *Section* ``, and a pointed-at heading is an interface: renaming one means re-pointing its callers. Describe the **current** shape only, and when a design leaves the repository its prose leaves in the same change. Budgets, measured with `(Get-Item <file>).Length`: this file about 12,000 bytes and never over 18,500; a reference document about 12,000 and never over 24,000.

Where a new paragraph goes is decided by its kind, not by its topic:

| Kind of information                                | Home                                                     |
| -------------------------------------------------- | -------------------------------------------------------- |
| A rule that applies in every session               | `AGENTS.md`: one invariant per area, ending in a pointer |
| The contract or the reasoning behind one subsystem | that subsystem's document under `docs/`                  |
| How one script works, and why it is written so     | a comment in that script                                 |
| A number measured on one machine                   | the hardware profile it was measured on                  |
| What a user of this repository does                | `README.md`                                              |
| An inventory that changes on its own               | nowhere: point at the file that defines it               |
| The history of this repository                     | git, never a document                                    |

`README.md` and the documents under `docs/` describe the same mechanics for different readers, which makes them the pair most likely to grow a second copy. `README.md` says what a user does; a reference document says what the contract is and which file owns it. The pointers run one way only, so the two cannot loop.

## Default Change Workflow

Commit only when explicitly asked, push only when explicitly asked, and "commit" does not imply "push".

## Code Comments

Comments explain **why**, not **what**. Default to no comment and prefer a clearer name. A why-comment longer than about three lines is a smell unless it records something unrecoverable from the code, such as a measured number or a platform fact; the launch-flag block in `start_comfyui.ps1` is the reference example of one that earns its length. `docs/conventions.md` → *Comments*.

## Scratch files

Ad-hoc artifacts (test renders, diffs, scratch scripts, traces) go under `.tmp/sessions/<session-id>/`, which is gitignored. Never write them to the repository root, to `docs/`, or to `workflows/`.

## Version Control

- LF line endings, enforced by `.gitattributes`. One long-lived branch, `main`.
- Commits take the [Conventional Commits](https://www.conventionalcommits.org/) form, `type(scope): imperative summary`, with the reasoning in the body and no `Co-Authored-By` trailer. `docs/conventions.md` → *Commit messages*.
- `vendor/ComfyUI` is a submodule, so a bumped pointer is its own commit rather than a side effect of another change.

## Output Formatting

The em dash (`—`) is reserved for a genuine emphatic interruption or a sudden break in thought. Everywhere else reach for the specific mark: a comma for a short aside, parentheses for a tangential one, a colon to introduce, a semicolon or a period to join two independent clauses, an en dash (`–`) for a range, a hyphen for a compound modifier. Pad every cell of a markdown table so that all cells in a column share one width. American spelling in code, comments and prose. `docs/conventions.md` → *Punctuation*, *Spelling*.

## Reference

All under `docs/`; the sentence is the document's own opening line.

| Document                     | When to read                                                                  |
| ---------------------------- | ----------------------------------------------------------------------------- |
| `conventions.md`             | Read when writing or reviewing code, a comment, a commit message or prose     |
| `workflows.md`               | Read when building or editing a workflow graph, or when the sidebar is wrong  |
| `benchmarks.md`              | Read when measuring a model, or before quoting a number one of these produced |
| `http-api.md`                | Read when driving the server over HTTP, or when timing a run                  |
| `hardware-16gb-ada.md`       | Read when working on the RTX 4070 Ti SUPER box                                |
| `hardware-24gb-blackwell.md` | Read when working on the RTX PRO 5000 Blackwell box                           |
| `models.md`                  | Read when installing, replacing or sourcing a model file                      |

# Conventions

Read when writing or reviewing code, a comment, a commit message or prose.

## Comments

Comments explain **why**, not **what**. The code already states what it does, and
a comment that restates it drifts out of sync.

- **Default to no comment.** Prefer a clearer name or a smaller function, and
  comment only where the reason is not recoverable from the code.
- **One source of truth per rationale.** Write a non-obvious decision down once
  at the authoritative place and reference it tersely from anywhere else.
- **History lives in git.** Never write "previously X" or "the old behavior was
  Y"; the commit message and `git blame` carry that.
- **Length is a smell.** A why-comment over about three lines usually signals
  unclear code. Fix the code first.
- **Earn the exception.** A long comment is justified when it records something
  unrecoverable from the code: a measured number, a platform fact, or a decision
  with a real cost if reversed. The launch-flag block in `start_comfyui.ps1` is
  the reference example, since every flag there is a benchmark result and no
  reader could derive it from the line itself. The comment-based help in
  `deploy_workflows.ps1` is the second, because it records why a publication
  target exists at all.

## Punctuation

The em dash (`—`) is reserved for a genuine emphatic interruption or a sudden
break in thought. For every other use reach for the more specific mark, and
rewriting the sentence is also fine: a comma for a short aside bound tightly to
the sentence; parentheses for a tangential one; a colon to introduce an
explanation, a list or a summary; a semicolon or a period to join two related
independent clauses; an en dash (`–`) for a numeric or date range; a hyphen for a
compound modifier. Do not strip a dash where it is the right mark. The rule is
only to stop using `—` as a default joiner.

Pad every cell of a markdown table so that all cells in a column share one width.

## Spelling

Identifiers, comments and prose use **American** spelling: `behavior`, not
`behaviour`; `optimize`, not `optimise`; `canceled`, not `cancelled`. The rule
reaches code, comments and every document in the repository.

It applies to what you touch rather than as a sweep, so a paragraph still
carrying a British form is not a precedent.

## PowerShell and CLI style

- **Full cmdlet names, never aliases.** `Get-ChildItem`, not `gci` or `ls`;
  `Where-Object`, not `?`. An alias resolves against the caller's session, which
  an interactive shell and a `-NoProfile` run do not agree on.
- **Full parameter names, never a unique prefix.** `-Recurse`, not `-rec`. A
  prefix that is unique today stops being unique when a parameter is added.
- **`-LiteralPath`, not `-Path`, for any operation on a workflow or model file.**
  Paths here come from a hash table and from the user's checkout directory,
  neither of which is escaped, so a bracket anywhere in a parent path would
  otherwise be globbed.
- **Variable names are case-insensitive.** `$wf` and `$Wf` are the same variable,
  which makes a casing typo silent rather than an error. Do not rely on case to
  distinguish two variables.
- **Quote a Python one-liner with a single-quoted PowerShell string** and use
  double quotes inside the Python. PowerShell mangles escaped quotes inside an
  f-string format spec, which surfaces as a `SyntaxError` from the interpreter
  rather than as a shell error, and sends you looking in the wrong place.
- **Spell out long-form options in `README.md` and in documentation** where the
  tool offers them: `--recurse-submodules`, not a short form. A short form stays
  fine where no long form exists.

## Commit messages

Commits take the [Conventional Commits](https://www.conventionalcommits.org/)
form, `type(scope): imperative summary`, with the reasoning in the body and no
`Co-Authored-By` trailer. The scope names the subsystem the change touches, and
is omitted when the change is repository-wide.

The summary says what changed. The body says why, which is the part no reader can
reconstruct later: what was measured, what was tried and rejected, and what the
change gives up. A commit that only restates its diff in English has an empty
body's worth of information in twice the space.

The scopes carry a structure no directory boundary separates. `rebuild`,
`deploy`, `workflows`, `preview` and `hardware` name parts of a three-script
repository, and `git log --oneline` is the only place that structure is visible.
A commit scope and a `CHANGELOG.md` component tag answer different questions and
are not kept in sync.

`vendor/ComfyUI` is a submodule, so a bumped pointer is its own commit. Mixing a
pointer bump into a functional change hides which of the two a later bisect
lands on.

## Changelog

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
It is read by someone deciding whether to pull a new version, so a bullet records
**a change that reader can observe by running the repository**: a script's
behavior, a workflow graph, a launch flag, a model requirement, a submodule pin.
A commit that changes one of those carries its entry in the same commit; versions
are bumped per change, there is no release branch collecting them afterwards, and
a change with no entry is invisible to everyone who was not in the session.

One bullet is **one change, not one commit**. Six commits converging on a single
shipped retune are one bullet naming the retune, not six naming the steps that
found it.

Prose is not something a reader can run, and earns a bullet in four cases only:

- A reference document under `docs/` is added or removed.
- A restructure moves where a reader looks for something.
- A `README.md` passage a reader copies or acts on changes.
- A published claim a reader could have acted on is corrected.

The case this rules out is the finding measured while tuning, which is most of
this repository's traffic. It has a home already, in the hardware profile that
owns the number and in the commit that measured it; a bullet restating it is the
second copy that drifts once the number is re-measured, and it buries the shipped
change under prose about prose.

The bullet itself:

- One physical line, never broken by hand; let the editor soft-wrap.
- `- [Component] <verb> <thing>`, under `Added`, `Changed`, `Removed` or `Fixed`.
- No rationale, no file paths, no line numbers, no explanatory prose. Rationale
  lives in `AGENTS.md`, the matching `docs/` file, or the commit message.

A component names the part a reader would look in, not the directory the diff
touched. `[Build]`, `[Workflows]`, `[Server]`, `[Vendor]`, `[Documentation]`,
`[Agents]` and `[Project]` are the ones in use; add one when none fits rather
than stretching a tag to cover it.

## Releases

A release is a tag on `main` and a `CHANGELOG.md` entry. No asset is built.
GitHub's own source archive already carries `workflows/` and the `docs/` that say
which model file each graph needs, and it compresses to less than the raw
workflow JSON does, so a hand-built bundle would be larger and carry less.
`vendor/` is empty in that archive, because `git archive` does not recurse into
submodules, so nothing of ComfyUI's GPL-3.0 code ships under this repository's
MIT.

What a version pins is the scripts, the workflow set, the custom-node commits and
the `requirements_override.txt` versions. It does **not** pin ComfyUI, which each
build advances to upstream's latest release unless `-version` says otherwise.
`docs/build.md` → *Submodule lifecycle*.

| Bump  | What it means here                                                                |
| ----- | --------------------------------------------------------------------------------- |
| MAJOR | A renamed or removed workflow, a removed script parameter, a newly required model |
| MINOR | A new workflow, a new script parameter, a custom-node bump that adds a capability |
| PATCH | A fix that changes no interface, including a retuned sampler setting              |

Cutting one:

1. Confirm `git status` is clean and the custom-node pins are the intended ones.
2. Commit the change with its `CHANGELOG.md` version heading and bullets.
3. `git tag -a v<x.y.z> -m "v<x.y.z>"`, then push `main` and the tag.
4. `gh release create v<x.y.z>` with a body of exactly two links, the changelog
   entry and the compare against the previous tag, and nothing else. What a
   reader needs is in the changelog; prose on the release page is a second copy
   that drifts from it. A first release has no previous tag, so it links its
   commit list instead.

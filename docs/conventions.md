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

Common Changelog, which `CHANGELOG.md` follows, argues against this convention in
[§4.2](https://common-changelog.org/#42-conventional-commits): the machine-readable
prefix has to be stripped again to produce a readable changelog line, so writing
the readable form once would serve both.

That argument is accepted and overridden. The prefixes carry a scope this
repository actually uses when reading its own history. `rebuild`, `deploy`,
`workflows`, `preview` and `hardware` name parts that no directory boundary
separates, and `git log --oneline` is the only place that structure is visible.
The conversion cost §4.2 warns about is not paid here either, because
`CHANGELOG.md` is curated by hand at release time rather than generated from
history. The decision is reversible at any release; nothing reads the prefixes.

`vendor/ComfyUI` is a submodule, so a bumped pointer is its own commit. Mixing a
pointer bump into a functional change hides which of the two a later bisect
lands on.

## Changelog

`CHANGELOG.md` follows [Common Changelog](https://common-changelog.org) with two
deliberate deviations. They share one reason: this is a single-maintainer
repository whose git history is public and reachable, so the changelog is written
for a reader deciding whether to upgrade, not as an index into commits.

| Deviation                                       | Spec                                              | Why                                                                                                                                                                                                                                        |
| ----------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| No commit or pull-request reference on an entry | §2.4.2, "changes must reference relevant commits" | A reference exists to let a reader reach the reasoning. The reasoning is in the commit body, and `git log --grep` reaches it from any phrase in the entry. One on every entry would be maintenance with no reader.                         |
| An `Unreleased` section exists                  | §6.2                                              | The objection in §6.2 is that a contributor cannot add self-references to an unreleased entry. Having declined references, the objection does not apply, and it is how work in progress stays visible on a repository with one branch.     |

Everything else holds: the four categories in order (`Changed`, `Added`,
`Removed`, `Fixed`), imperative mood, `**BREAKING**` in bold on a breaking
change, ISO dates, a release link per version heading as a reference-link block
at the foot of the file, and no entry for a change a consumer cannot observe.
That last clause is what keeps this changelog short: most traffic here is a
measurement written into a hardware profile, which changes nothing a user runs.

An entry is **one line**: what changed, not why. Around 100 characters, and past
200 it is either two changes or a sentence of reasoning that belongs in the
commit. §3.6 sends the long form to "commits or other references", and declining
the references does not make the commits unreachable.

A version heading may carry one **italic line** beneath it: §2.3's notice, and
per that section **one sentence**. It is for anything that makes upgrading more
than a pull, which is to say a prerequisite, a manual step, or a change a reader
would otherwise meet by surprise: a new model file to fetch, a renamed sidebar
entry, a changed launch flag, a ComfyUI floor. It is the first thing a reader
deciding whether to upgrade sees, and the one place a longer sentence earns its
room.

It states only that delta. Two things therefore stay out of it. The baseline
upgrade mechanics, because `git pull --recurse-submodules` is what upgrading
always is here; a line repeating it on every release is the notice spending its
position on nothing. And a summary of the entries below it, because the
categories already sort those by impact and a reader who skips the notice must
lose nothing.

## Releases

A release is a tag on `main` and a `CHANGELOG.md` entry. No asset is built.
GitHub's own source archive already carries `workflows/` and the `docs/` that say
which model file each graph needs, and it compresses to less than the raw
workflow JSON does, so a hand-built bundle would be larger and carry less.
`vendor/` is empty in that archive, because `git archive` does not recurse into
submodules, so nothing of ComfyUI's GPL-3.0 code ships under this repository's
MIT.

What a version pins is the **composition**: the three scripts, the recorded
submodule pointers, the workflow set and the `requirements_override.txt` pins,
known to run together on the profiles under `docs/`. That is the whole point of
tagging a repository that builds nothing.

| Bump  | What it means here                                                                 |
| ----- | ---------------------------------------------------------------------------------- |
| MAJOR | A renamed or removed workflow, a removed script parameter, a newly required model  |
| MINOR | A new workflow, a new script parameter, a submodule bump that adds a capability    |
| PATCH | A fix that changes no interface, including a retuned sampler setting               |

Cutting one:

1. Confirm `git status` is clean and the submodule pointers are the intended ones.
2. Rename the `Unreleased` heading to the version, with today's date, and add its
   reference link at the foot of the file.
3. Commit as `chore(release): v<x.y.z>`.
4. `git tag -a v<x.y.z> -m "v<x.y.z>"`, then push `main` and the tag.
5. `gh release create v<x.y.z>` with a body linking the changelog entry and the
   compare against the previous tag.

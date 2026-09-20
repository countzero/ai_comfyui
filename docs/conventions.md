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

`vendor/ComfyUI` is a submodule, so a bumped pointer is its own commit. Mixing a
pointer bump into a functional change hides which of the two a later bisect
lands on.

---
name: code-tour
description:
  Build or update a guided code tour for Neovim from the current git changes,
  so each change can be walked stop-by-stop with its justification in a
  floating window. Use when the user asks for a tour, a guided tour, a code
  walk, or to explain/justify their changes as a tour. Also use to process
  tour feedback: notes the user attached to stops/sections from nvim, to be
  answered or acted on.
---

# Build a code tour from git changes

A tour is a Lua file of ordered stops. Each stop anchors to a string in a file
and carries the justification for that change: what necessity the code
satisfies and what requirement (ticket clause, PR goal) it covers. The
code-tours.nvim runner jumps stop to stop and shows the body in a floating
window.

**Language:** write the tour in the language the user prefers. If they have
stated a preference (in the conversation or in memory), use it; otherwise use
the language they are speaking to you in. Code patterns, identifiers, and
UI terms stay as-is; quote ticket or requirement lines in their original
language followed by a short gloss in the tour's language when they differ.
If the user has a preferred speech voice, set `voice = "<name>"` at the
tour's top level; the runner passes it to the speech command (macOS `say -v`
by default). Siri voices never work with `say`; only voices listed by
`say -v '?'` do.

## Tour file contract

Write to the runner's tours directory: `~/.local/share/nvim/code-tours/<name>.lua`
by default (if the user configured `dir` in the plugin's setup, use that).
`<name>` is kebab-case, usually ticket/branch and phase (`proj-83-phase1`).
The file returns:

```lua
return {
  title = "Short human title",
  root = "/absolute/path/to/git/root",
  voice = "Juan",
  stops = {
    {
      file = "app/services/example.rb",
      pattern = "def exact_unique_string",
      title = "One-line claim about this change",
      body = "**Necessity:** why this code exists.\n**Covers:** the requirement it satisfies.",
    },
  },
}
```

Stops may also carry `sections`. Pressing the explain key (`ge` by default) on
any stop walks **every section of that stop's file** (aggregated across all
its stops, in tour order), each one highlighted in the buffer while its
explanation shows, then returns to the tour. Attach each section to the stop
whose topic it belongs to; the walk stitches them together per file.

```lua
sections = {
  {
    pattern = "visible = value(:tabs).reject",
    lines = 1,
    title = "Collect the visible tab ids",
    body = "**What it does:** ...",
  },
},
```

- A section's `pattern` anchors its first line (same uniqueness rule as a
  stop's); the highlight covers `lines` lines from there, or through the line
  matched by `last` (a pattern searched forward from the anchor). Default is
  the single anchor line.
- Each section `body` explains what that fragment does and the non-obvious
  detail in it, same formatting rules as stop bodies.
- **Coverage:** every function, step, declaration, and setup block in a file
  the tour visits must be explained by a stop or a section; a reader stepping
  through should be able to account for every line of the changed code. Before
  reporting, list the file's definitions (`grep -nE 'def |let\(|^\s*[A-Z_]+ ='`
  or the language's equivalent) and confirm each is covered.

Both stops and sections may carry `feedback`: notes the user attached from
inside nvim (the annotate key, `ga` by default, appends one and rewrites the
tour file). Each entry is `{ text = "...", at = "YYYY-MM-DD" }`, plus
`answer = "..."` once handled. The float renders `text` as a `>>` line and
`answer` as `<<` under it.

- `file` is relative to `root`.
- `pattern` is a verbatim substring of the file's current text (the runner
  searches it literally, `\V`). It must occur exactly once in the file; prefer
  a definition line (`def issue`, `check :observer_pairing`).
- `title` ≤ 60 chars, the claim alone.
- `body` is markdown and must read as skimmable, self-contained prose:
  - **Audience:** someone who did NOT watch the implementation and has not
    read any planning document. Write what the code does mechanically in
    plain words before any why ("**Plain words first:**" openers are
    welcome). Never lean on session shorthand: "the agreed default" or "the
    usual pattern" say nothing to this reader — state the actual behavior or
    pattern instead. If a value was invented (fictional hostnames, fixture
    names, answer-key constants), say so explicitly and name what constrains
    it; "where does this value come from?" must never be left open.
  - **Self-contained:** the reader is not a computer that memorized the
    ticket. Referencing the ticket is welcome, even encouraged, but every
    code or shorthand must be glossed in plain words where it appears:
    "the ticket's deliverables list (item 2)", never a bare `M9.2` or
    `Dev #1`. Gloss on every stop that uses one, not just the first, because
    stops are read out of order. Project concepts (grader, fixture, tenant,
    middleware — whatever the codebase's jargon is) get a one-line gloss at
    every stop that uses them, for the same reason. Quoting the ticket's own
    words is the clearest reference of all.
  - **Breaklines:** one idea per chunk, each chunk 1-3 short lines starting
    with a **bold label** (`**Why:**`, `**What this checks:**`,
    `**Feedback:**`), separated by blank lines (`\n\n`). No walls of text.
  - **Template:** stops open with `**What you're looking at:**` (the
    mechanics, plain words), then `**What changed:**` / `**What it checks:**`,
    then the why, then `**Covers:**` quoting or glossing the requirement.
    Sections use `**Plain words first:**` when a domain concept appears, then
    `**What it does:**` (code) or `**What it proves:**` (tests). Parallel
    items get numbered titles ("Check 2 of 5") so the reader always knows
    where they are.
  - No comments in the generated Lua.

## Process

0. **Read `lessons.md` in this skill's directory** (next to SKILL.md) and
   apply every lesson while writing bodies. It holds generalized rules
   extracted from past tour feedback. If it doesn't exist, continue.
1. **Scope the changes from git.** In the repo: `git rev-parse --show-toplevel`
   for `root`; enumerate changes with
   `git diff --name-status $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)`
   plus `git status --porcelain` for uncommitted and untracked work. The user
   may narrow scope (a phase, a commit range, named files); otherwise the tour
   covers everything changed on the branch and in the working tree.
2. **Read the changed hunks**, not whole files, to pick anchors and understand
   each change.
3. **Source the justifications.** Use the conversation, the ticket or issue,
   and any design or research doc the project keeps. Never invent a
   requirement mapping; if a change has no known justification, say so in the
   body ("refactor, no ticket clause") rather than fabricate one.
4. **Order stops as a narrative**, not by diff order: entry point or wiring
   first, then the core logic in reading order, then tests, then unrelated
   fixes last.
5. **Verify every pattern** before writing, stop and section alike:
   `grep -cF -- '<pattern>' <file>` must print 1. Adjust anchors until each
   does.
6. **Cold-reader pass before writing to disk.** Re-read every body pretending
   you never saw this branch, the conversation, or any planning doc. A
   mechanical lint catches the worst offenders — none of these may appear in a
   body unless the sentence itself states the content they stand for:
   `grep -nE "research doc|house pattern|as discussed|as planned|the default|our convention" <tour-file>`
   plus bare requirement IDs (`grep -nE '[^(]M[0-9]+\.[0-9]+'`). For every
   constant or literal a body mentions, the body must say where the value
   comes from, or that it is invented and what must stay in sync with it.
7. **Write the tour file**, then validate it loads:
   `nvim --headless --clean "+lua local t=assert(loadfile('<path>'))(); assert(type(t.stops)=='table' and #t.stops>0)" +q`
   must exit 0.
8. **Updating an existing tour** (same branch, new changes): regenerate the
   whole file from the current diff; stale stops rot because patterns drift.
   **Always carry existing `feedback` entries over**, matched by file +
   pattern; user feedback is never lost to a regeneration.

## Feedback rounds

When the user asks to process, answer, or act on tour feedback (e.g.
"/code-tour feedback proj-83-phase1", "check the feedback in the tour"), read
the tour file and handle every `feedback` entry that has no `answer`:

- **Question:** set `answer` to a plain-words reply, same formatting and
  glossing rules as bodies.
- **Change request:** make the change (code, tour body, or both), then set
  `answer` to one line saying what changed. A code change goes through the
  normal workflow (tests, the project's rules).
- Never delete an entry; the user removes threads when done (via `:TourEdit`
  or by asking). Entries already carrying an `answer` are settled unless the
  user says otherwise.
- Revalidate the tour file loads after editing it (same headless check as the
  write step), and tell the user which stops got answers so they can rerun the
  tour.
- **Extract lessons.** When a feedback entry reveals a confusion future tours
  could preempt (a question a body should have answered, a shorthand that
  meant nothing), append one bullet to `lessons.md` in this skill's directory:
  the symptom in the user's words, then the rule that prevents it. Skip
  one-off factual questions; capture only what generalizes.

## Report back

Name the tour and say how to run it: `:Tour <name>` in nvim (`:TourList` to
pick; with default keys `]t` / `[t` to move, `ge` to walk a stop's
highlighted sections, `gs` to speak the current stop or section through the
speakers (press again to stop), `gq` to back out of sections or end the
tour). Don't start the tour remotely unless the user asked; if `$NVIM` is set
and they did ask, use
`nvim --server "$NVIM" --remote-expr 'execute("Tour <name>")'`.

## Management (for answering questions)

- `:Tour <name>` start (tab-completes), `:Tour` with no arg = picker
- `:TourList` picker with titles
- `:TourNext` / `:TourPrev` / `:TourExplain` / `:TourAnnotate` / `:TourRead` /
  `:TourHere` / `:TourQuit` (while touring, with default keys: `]t`, `[t`,
  `ge` for sections, `ga` feedback, `gs` speaks the current stop or section
  aloud, pressing it again or moving stops the speech, `gh` re-opens the
  current stop/section after wandering through the code or closing the float,
  `gq`; the runner saves and restores whatever those keys were mapped to;
  `gr` is avoided because Neovim 0.11 uses it as the LSP prefix)
- Section mode: next/prev move between highlighted sections, past the last
  one (or the quit key) returns to the tour stop; the highlight group is
  `TourSection`, linked to `Visual` by default
- `:TourVoice [name]` picks the speech voice for the session (no arg: picker
  that speaks each voice's sample); it overrides the tour's `voice` and the
  configured fallback
- `:TourEdit <name>` / `:TourDelete <name>` (confirms)
- `:TourInstallSkill` reinstalls this skill from the plugin
- Global keybindings, set only when the key is free so they never overwrite
  an existing mapping (defaults): `<leader>TT` pick and start, `<leader>Th`
  re-open the current stop, `<leader>Tq` end the tour, `<leader>Te` edit a
  tour file
- Tour files live in `~/.local/share/nvim/code-tours/` (or the configured
  `dir`); the runner is the code-tours.nvim plugin, set up via
  `require("tours").setup()`.

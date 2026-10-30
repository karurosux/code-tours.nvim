# code-tours.nvim

Guided, narrated walkthroughs of code changes, inside Neovim.

A tour is a plain Lua file of ordered **stops**. Each stop anchors to a line
in a file and explains, in a floating window, what that change does and why
it exists. Stops can carry **sections** that highlight and explain every
fragment of a file, one at a time. You can **speak** any stop aloud, leave
**feedback** on it without leaving the editor, and have an AI assistant
answer that feedback in place.

Born as a code-review tool: an AI agent (Claude Code) writes the tour from a
git diff, and the human walks it stop by stop, asking questions with `ga`
where something is unclear. The bundled skill (see below) teaches the agent
the format and the quality bar. Tours are just Lua files, though — you can
write them by hand for onboarding, teaching, or PR reviews.

## Requirements

- Neovim >= 0.9
- macOS `say` for speech out of the box (optional; any TTS CLI works via
  `speech.build`)

## Install

lazy.nvim:

```lua
{
  "karurosux/code-tours.nvim",
  opts = {},
}
```

Or with explicit setup:

```lua
require("tours").setup()
```

## Quick start

1. Put a tour file in `~/.local/share/nvim/code-tours/` (see format below),
   or have the Claude Code skill generate one from your current branch.
2. `:Tour <name>` (tab-completes) or `<Space>TT` to pick from a list.
3. Walk it: `]t` / `[t` next and previous, `ge` to walk the current file's
   highlighted sections, `gs` to hear the stop through your speakers, `ga`
   to attach feedback, `gh` to re-open the float after wandering off, `gq`
   to back out of sections or end the tour.

The in-tour keys exist only while a tour is running: the runner saves
whatever those keys were mapped to and restores them when the tour ends.
`gr` is deliberately not used because Neovim 0.11 reserves it as the LSP
prefix.

## Tour file format

`~/.local/share/nvim/code-tours/<name>.lua`:

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
      body = "**What you're looking at:** ...\n\n**Covers:** ...",
      sections = {
        {
          pattern = "def helper",
          lines = 3,
          title = "What this helper does",
          body = "**What it does:** ...",
        },
      },
    },
  },
}
```

- `file` is relative to `root`.
- `pattern` is a **verbatim substring** of the file, searched literally; it
  must occur exactly once. The stop jumps there.
- `body` is markdown, rendered in the float.
- A section highlights `lines` lines from its pattern, or through the line
  matched by `last` (a pattern searched forward). `ge` on a stop walks every
  section of that stop's file, across all stops, in tour order.
- `voice` (optional) is passed to the speech command (`say -v` by default).
- `feedback` entries (`{ text, at, answer }`) are appended by `ga` and
  rendered as `>>` question / `<<` answer threads in the float.

## Commands

| Command | What it does |
| --- | --- |
| `:Tour <name>` | Start a tour (no arg: picker) |
| `:TourList` | Picker with titles |
| `:TourNext` / `:TourPrev` | Move between stops/sections |
| `:TourExplain` | Walk the current file's sections |
| `:TourAnnotate` | Attach feedback to the current stop/section |
| `:TourRead` | Speak the current stop/section (again stops) |
| `:TourHere` | Re-open the current stop's float and position |
| `:TourQuit` | End the tour |
| `:TourEdit <name>` | Open a tour file |
| `:TourDelete <name>` | Delete a tour (confirms) |
| `:TourInstallSkill` | Install the Claude Code skill (see below) |

## Configuration

Defaults shown:

```lua
require("tours").setup({
  dir = vim.fn.stdpath("data") .. "/code-tours",
  keys = {
    next = "]t",
    prev = "[t",
    explain = "ge",
    annotate = "ga",
    speak = "gs",
    here = "gh",
    quit = "gq",
  },
  leader_maps = {
    ["<leader>TT"] = "list",
    ["<leader>Th"] = "here",
    ["<leader>Tq"] = "quit",
    ["<leader>Te"] = "edit",
  },
  speech = {
    rate = 190,
    voice = nil,
    build = nil,
  },
  skill_dest = "~/.claude/skills/code-tour",
})
```

- `leader_maps` are set **only when the key is free**, so they never
  overwrite an existing mapping. Set `leader_maps = false` to skip them.
- `speech.voice` is a fallback for tours that don't set their own. On macOS,
  only voices listed by `say -v '?'` work (Siri voices don't); download
  Enhanced voices in System Settings > Accessibility > Spoken Content.
- `speech.build` replaces the speech command entirely, for non-macOS TTS:

```lua
speech = {
  build = function(text, voice)
    return { "espeak-ng", "-s", "160", "-v", voice or "en", text }
  end,
},
```

- The `TourSection` highlight group links to `Visual`; redefine it to taste.

## Claude Code skill

The plugin ships a skill that teaches Claude Code to generate tours from
your git changes: scoping the diff, anchoring stops to unique patterns,
writing self-contained bodies a cold reader can follow, validating the file,
and processing your `ga` feedback (it answers questions inside the tour file,
so the answers show up under your notes next time you run the tour).

Install it with `:TourInstallSkill` (copies the bundled skill to
`~/.claude/skills/code-tour`), then ask Claude Code for a tour:

```
/code-tour
```

or just "give me a tour of these changes". To get your feedback answered:

```
/code-tour feedback <tour-name>
```

The skill keeps a `lessons.md` next to itself where generalized lessons from
your feedback accumulate, so tours get better over time.

## License

MIT

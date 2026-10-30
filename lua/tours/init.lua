local M = {}

local ns = vim.api.nvim_create_namespace("code_tours")

local defaults = {
  dir = nil,
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
}

local config = vim.deepcopy(defaults)

local state = {
  tour = nil,
  name = nil,
  index = 0,
  section = nil,
  float = nil,
  saved_maps = nil,
  hl_buf = nil,
}

local function tours_dir()
  return config.dir or (vim.fn.stdpath("data") .. "/code-tours")
end

local function tour_path(name)
  return tours_dir() .. "/" .. name .. ".lua"
end

local function tour_names()
  local names = {}
  for _, path in ipairs(vim.fn.glob(tours_dir() .. "/*.lua", false, true)) do
    names[#names + 1] = vim.fn.fnamemodify(path, ":t:r")
  end
  table.sort(names)
  return names
end

local function load_tour(name)
  local path = tour_path(name)
  if vim.fn.filereadable(path) == 0 then
    vim.notify("No tour named " .. name, vim.log.levels.ERROR)
    return nil
  end
  local chunk, err = loadfile(path)
  if not chunk then
    vim.notify("Broken tour file: " .. err, vim.log.levels.ERROR)
    return nil
  end
  local ok, tour = pcall(chunk)
  if not ok or type(tour) ~= "table" or type(tour.stops) ~= "table" or #tour.stops == 0 then
    vim.notify("Tour " .. name .. " has no stops", vim.log.levels.ERROR)
    return nil
  end
  return tour
end

local function current_stop()
  return state.tour and state.tour.stops[state.index]
end

local function close_float()
  if state.float and vim.api.nvim_win_is_valid(state.float) then
    vim.api.nvim_win_close(state.float, true)
  end
  state.float = nil
end

local function clear_highlight()
  if state.hl_buf and vim.api.nvim_buf_is_valid(state.hl_buf) then
    vim.api.nvim_buf_clear_namespace(state.hl_buf, ns, 0, -1)
  end
  state.hl_buf = nil
end

local function stop_speech()
  if state.say then
    pcall(vim.fn.jobstop, state.say)
    state.say = nil
  end
end

local function speech_text(title, body)
  local text = (title or "") .. ". " .. (body or "")
  text = text:gsub("%*%*", ""):gsub("`", "")
  text = text:gsub("\n\n+", ". "):gsub("\n", " ")
  return text
end

local function speech_command(text, voice)
  if config.speech.build then
    return config.speech.build(text, voice)
  end
  local cmd = { "say", "-r", tostring(config.speech.rate) }
  if voice then
    vim.list_extend(cmd, { "-v", voice })
  end
  cmd[#cmd + 1] = text
  return cmd
end

function M.read()
  if not state.tour then
    return vim.notify("No tour is running", vim.log.levels.WARN)
  end
  if state.say then
    return stop_speech()
  end
  local target = state.section and state.walk[state.section] or current_stop()
  local voice = state.tour.voice or config.speech.voice
  local cmd = speech_command(speech_text(target.title, target.body), voice)
  if vim.fn.executable(cmd[1]) == 0 then
    return vim.notify("No '" .. cmd[1] .. "' command on this system", vim.log.levels.WARN)
  end
  local id = vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      state.say = nil
      if code ~= 0 and code ~= 143 then
        vim.schedule(function()
          vim.notify(cmd[1] .. " exited with code " .. code, vim.log.levels.ERROR)
        end)
      end
    end,
  })
  if id <= 0 then
    return vim.notify("Couldn't start the speech command", vim.log.levels.ERROR)
  end
  state.say = id
  vim.notify("Speaking (" .. config.keys.speak .. " stops)")
end

local function show_float(header, body, footer, feedback)
  close_float()
  local lines = { header, "" }
  for _, line in ipairs(vim.split(body or "", "\n", { plain = true })) do
    lines[#lines + 1] = line
  end
  if feedback and #feedback > 0 then
    lines[#lines + 1] = ""
    for _, entry in ipairs(feedback) do
      lines[#lines + 1] = ">> " .. entry.text
      if entry.answer then
        for i, answer_line in ipairs(vim.split(entry.answer, "\n", { plain = true })) do
          lines[#lines + 1] = (i == 1 and "<< " or "   ") .. answer_line
        end
      end
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = footer
  local width = math.max(40, math.min(72, math.floor(vim.o.columns * 0.4)))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  state.float = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    anchor = "NE",
    row = 0,
    col = vim.o.columns - 1,
    width = width,
    height = vim.o.lines - 4,
    style = "minimal",
    border = "rounded",
    title = " " .. (state.tour.title or state.name) .. " ",
    title_pos = "center",
    focusable = true,
  })
  vim.wo[state.float].wrap = true
  vim.keymap.set("n", "q", M.back_or_quit, { buffer = buf })
end

local function search_from_top(pattern)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return vim.fn.search([[\V]] .. vim.fn.escape(pattern, [[\]]), "cW")
end

local function open_stop_file(stop)
  local root = state.tour.root or (vim.uv or vim.loop).cwd()
  local path = stop.file
  if not path:match("^[/~]") then
    path = root .. "/" .. path
  end
  vim.cmd.edit(vim.fn.fnameescape(vim.fn.expand(path)))
end

local function file_sections(stop)
  local walk = {}
  for _, other in ipairs(state.tour.stops) do
    if other.file == stop.file and other.sections then
      for _, sec in ipairs(other.sections) do
        walk[#walk + 1] = sec
      end
    end
  end
  return walk
end

local function stop_footer(stop)
  local k = config.keys
  local keys = k.next .. " next · " .. k.prev .. " prev"
  if #file_sections(stop) > 0 then
    keys = keys .. " · " .. k.explain .. " explain this file"
  end
  return keys
    .. " · " .. k.annotate .. " feedback · " .. k.speak .. " speak · "
    .. k.here .. " here · " .. k.quit .. " end tour"
end

local function section_footer()
  local k = config.keys
  return k.next .. " next section · " .. k.prev .. " prev · " .. k.annotate
    .. " feedback · " .. k.speak .. " speak · " .. k.quit .. " back to tour"
end

local function goto_stop()
  stop_speech()
  clear_highlight()
  state.section = nil
  state.walk = nil
  local stop = current_stop()
  open_stop_file(stop)
  if stop.pattern then
    if search_from_top(stop.pattern) == 0 then
      vim.notify("Tour pattern not found in file: " .. stop.pattern, vim.log.levels.WARN)
    else
      vim.cmd("normal! zz")
    end
  end
  local header = ("Stop %d/%d · %s"):format(state.index, #state.tour.stops, stop.title or "")
  show_float(header, stop.body, stop_footer(stop), stop.feedback)
end

local function goto_section()
  stop_speech()
  local stop = current_stop()
  local sec = state.walk[state.section]
  open_stop_file(stop)
  clear_highlight()
  local first = search_from_top(sec.pattern)
  if first == 0 then
    vim.notify("Section pattern not found: " .. sec.pattern, vim.log.levels.WARN)
  else
    local last = first
    if sec.last then
      local found = vim.fn.search([[\V]] .. vim.fn.escape(sec.last, [[\]]), "nW")
      if found > 0 then
        last = found
      end
    elseif sec.lines then
      last = first + sec.lines - 1
    end
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_extmark(buf, ns, first - 1, 0, {
      end_row = last,
      end_col = 0,
      hl_group = "TourSection",
      hl_eol = true,
      strict = false,
    })
    state.hl_buf = buf
    vim.cmd("normal! zz")
  end
  local header = ("%s · Section %d/%d · %s"):format(
    vim.fn.fnamemodify(stop.file, ":t"),
    state.section,
    #state.walk,
    sec.title or ""
  )
  show_float(header, sec.body, section_footer(), sec.feedback)
end

local actions = {
  next = { fn = function() M.next() end, desc = "Next tour stop/section" },
  prev = { fn = function() M.prev() end, desc = "Previous tour stop/section" },
  explain = { fn = function() M.explain() end, desc = "Explain this stop's code sections" },
  annotate = { fn = function() M.annotate() end, desc = "Attach feedback to this stop/section" },
  speak = { fn = function() M.read() end, desc = "Speak this stop/section aloud (again stops)" },
  here = { fn = function() M.here() end, desc = "Re-open the current tour stop/section" },
  quit = { fn = function() M.back_or_quit() end, desc = "Back to tour / end tour" },
}

local function set_maps()
  state.saved_maps = {}
  for action, lhs in pairs(config.keys) do
    state.saved_maps[lhs] = vim.fn.maparg(lhs, "n", false, true)
    vim.keymap.set("n", lhs, actions[action].fn, { desc = actions[action].desc })
  end
end

local function restore_maps()
  if not state.saved_maps then
    return
  end
  for lhs, saved in pairs(state.saved_maps) do
    pcall(vim.keymap.del, "n", lhs)
    if saved and not vim.tbl_isempty(saved) then
      vim.fn.mapset("n", false, saved)
    end
  end
  state.saved_maps = nil
end

function M.start(name)
  if not name or name == "" then
    return M.list()
  end
  local tour = load_tour(name)
  if not tour then
    return
  end
  M.quit()
  state.tour = tour
  state.name = name
  state.index = 1
  set_maps()
  goto_stop()
end

function M.explain()
  local stop = current_stop()
  if not stop then
    return vim.notify("No tour is running", vim.log.levels.WARN)
  end
  local walk = file_sections(stop)
  if #walk == 0 then
    return vim.notify("No section walkthrough for this file")
  end
  state.walk = walk
  state.section = 1
  goto_section()
end

function M.annotate()
  if not state.tour then
    return vim.notify("No tour is running", vim.log.levels.WARN)
  end
  local target = state.section and state.walk[state.section] or current_stop()
  vim.ui.input({ prompt = "Feedback: " }, function(text)
    if not text or text == "" then
      return
    end
    target.feedback = target.feedback or {}
    target.feedback[#target.feedback + 1] = { text = text, at = os.date("%Y-%m-%d") }
    local file = assert(io.open(tour_path(state.name), "w"))
    file:write("return " .. vim.inspect(state.tour) .. "\n")
    file:close()
    vim.notify("Feedback saved into the tour file")
    if state.section then
      goto_section()
    else
      goto_stop()
    end
  end)
end

function M.here()
  if not state.tour then
    return vim.notify("No tour is running", vim.log.levels.WARN)
  end
  if state.section then
    return goto_section()
  end
  goto_stop()
end

function M.next()
  if not state.tour then
    return
  end
  if state.section then
    if state.section >= #state.walk then
      vim.notify("Sections done, back to the tour")
      return goto_stop()
    end
    state.section = state.section + 1
    return goto_section()
  end
  if state.index >= #state.tour.stops then
    vim.notify("Tour finished: " .. (state.tour.title or state.name))
    return M.quit()
  end
  state.index = state.index + 1
  goto_stop()
end

function M.prev()
  if not state.tour then
    return
  end
  if state.section then
    if state.section <= 1 then
      return goto_stop()
    end
    state.section = state.section - 1
    return goto_section()
  end
  state.index = math.max(1, state.index - 1)
  goto_stop()
end

function M.back_or_quit()
  if state.section then
    return goto_stop()
  end
  M.quit()
end

function M.quit()
  stop_speech()
  close_float()
  clear_highlight()
  restore_maps()
  state.tour = nil
  state.name = nil
  state.index = 0
  state.section = nil
  state.walk = nil
end

local function pick(prompt, on_choice)
  local names = tour_names()
  if #names == 0 then
    return vim.notify("No tours in " .. tours_dir(), vim.log.levels.WARN)
  end
  local items = {}
  for _, name in ipairs(names) do
    local tour = load_tour(name)
    items[#items + 1] = { name = name, label = name .. "  —  " .. (tour and tour.title or "?") }
  end
  vim.ui.select(items, {
    prompt = prompt,
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      on_choice(choice.name)
    end
  end)
end

function M.list()
  pick("Start tour", M.start)
end

function M.delete(name)
  if not name or name == "" then
    return pick("Delete tour", M.delete)
  end
  if vim.fn.confirm("Delete tour " .. name .. "?", "&Yes\n&No", 2) ~= 1 then
    return
  end
  if state.name == name then
    M.quit()
  end
  if os.remove(tour_path(name)) then
    vim.notify("Deleted tour " .. name)
  else
    vim.notify("No tour named " .. name, vim.log.levels.ERROR)
  end
end

function M.edit(name)
  if not name or name == "" then
    return pick("Edit tour", M.edit)
  end
  vim.cmd.edit(vim.fn.fnameescape(tour_path(name)))
end

local function plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":h:h:h")
end

function M.install_skill()
  local src = plugin_root() .. "/skill/code-tour"
  local dest = vim.fn.expand(config.skill_dest)
  if vim.fn.isdirectory(src) == 0 then
    return vim.notify("Bundled skill not found at " .. src, vim.log.levels.ERROR)
  end
  if vim.fn.filereadable(dest .. "/SKILL.md") == 1 then
    if vim.fn.confirm("Overwrite the skill at " .. dest .. "?", "&Yes\n&No", 2) ~= 1 then
      return
    end
  end
  vim.fn.mkdir(dest, "p")
  for _, path in ipairs(vim.fn.glob(src .. "/*", false, true)) do
    local name = vim.fn.fnamemodify(path, ":t")
    vim.fn.writefile(vim.fn.readfile(path, "b"), dest .. "/" .. name, "b")
  end
  vim.notify("Claude Code skill installed at " .. dest .. " — tours land in " .. tours_dir())
end

local function complete_names()
  return tour_names()
end

local function map_if_free(lhs, fn, desc)
  local existing = vim.fn.maparg(lhs, "n", false, true)
  if vim.tbl_isempty(existing) or (existing.desc or ""):match("^Tours: ") then
    vim.keymap.set("n", lhs, fn, { desc = desc })
  end
end

local leader_actions = {
  list = { fn = function() M.list() end, desc = "Tours: pick and start" },
  here = { fn = function() M.here() end, desc = "Tours: re-open the current stop" },
  quit = { fn = function() M.quit() end, desc = "Tours: end the tour" },
  edit = { fn = function() M.edit() end, desc = "Tours: edit a tour file" },
}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  vim.fn.mkdir(tours_dir(), "p")
  vim.api.nvim_set_hl(0, "TourSection", { link = "Visual", default = true })
  vim.api.nvim_create_user_command("Tour", function(cmd)
    M.start(cmd.args)
  end, { nargs = "?", complete = complete_names, desc = "Start a code tour (no arg: pick one)" })
  vim.api.nvim_create_user_command("TourList", M.list, { desc = "Pick and start a code tour" })
  vim.api.nvim_create_user_command("TourNext", M.next, { desc = "Next tour stop/section" })
  vim.api.nvim_create_user_command("TourPrev", M.prev, { desc = "Previous tour stop/section" })
  vim.api.nvim_create_user_command("TourExplain", M.explain, { desc = "Walk this stop's code sections" })
  vim.api.nvim_create_user_command("TourAnnotate", M.annotate, { desc = "Attach feedback to this stop/section" })
  vim.api.nvim_create_user_command("TourRead", M.read, { desc = "Read this stop/section aloud (again stops)" })
  vim.api.nvim_create_user_command("TourHere", M.here, { desc = "Re-open the current tour stop/section" })
  vim.api.nvim_create_user_command("TourQuit", M.quit, { desc = "End the tour" })
  vim.api.nvim_create_user_command("TourInstallSkill", M.install_skill,
    { desc = "Install the bundled Claude Code skill into ~/.claude/skills" })
  vim.api.nvim_create_user_command("TourDelete", function(cmd)
    M.delete(cmd.args)
  end, { nargs = "?", complete = complete_names, desc = "Delete a code tour (no arg: pick one)" })
  vim.api.nvim_create_user_command("TourEdit", function(cmd)
    M.edit(cmd.args)
  end, { nargs = "?", complete = complete_names, desc = "Edit a code tour file (no arg: pick one)" })
  if config.leader_maps then
    for lhs, action in pairs(config.leader_maps) do
      map_if_free(lhs, leader_actions[action].fn, leader_actions[action].desc)
    end
  end
end

return M

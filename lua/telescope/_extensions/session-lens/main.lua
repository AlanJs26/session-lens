local Lib = require('telescope._extensions.session-lens.session-lens-library')
local AutoSession = require('auto-session')
local SessionLensActions = require("telescope._extensions.session-lens.session-lens-actions")
local telescope_config = require("telescope.config").values

----------- Setup ----------
local SessionLens = {
  conf = {}
}

local defaultConf = {
  theme_conf = { winblend = 10, border = true },
  previewer = false
}

-- Set default config on plugin load
SessionLens.conf = defaultConf

function SessionLens.setup(config)
  SessionLens.conf = Lib.Config.normalize(config, SessionLens.conf)
end


local themes = require('telescope.themes')
local actions = require('telescope.actions')

local sorters = require("telescope.sorters")

local modification_date_sorter = function(cwd)

  return function(opts)
    opts = opts or {}
    local fzy = opts.fzy_mod or require "telescope.algos.fzy"
    local OFFSET = -fzy.get_score_floor()

    return sorters.Sorter:new {
      discard = true,

      scoring_function = function(_, prompt, line)

        -- Check for actual matches before running the scoring alogrithm.
        if not fzy.has_match(prompt, line) then
          return -1
        end


        local file_path = cwd..line

        local score = 1

        modification_timestamp = vim.fn.getftime(file_path)

        if modification_timestamp ~= -1 and prompt == '' then
          timestamp = vim.fn.strftime("%s")-vim.fn.getftime(file_path)
          score = timestamp
        end

        local fzy_score = fzy.score(prompt, line)

        -- The fzy score is -inf for empty queries and overlong strings.  Since
        -- this function converts all scores into the range (0, 1), we can
        -- convert these to 1 as a suitable "worst score" value.
        if fzy_score == fzy.get_score_min() then
          return score
        end

        -- Poor non-empty matches can also have negative values. Offset the score
        -- so that all values are positive, then invert to match the
        -- telescope.Sorter "smaller is better" convention. Note that for exact
        -- matches, fzy returns +inf, which when inverted becomes 0.
        score = (1 / (fzy_score + OFFSET))

        return score

      end,

      -- The fzy.positions function, which returns an array of string indices, is
      -- compatible with telescope's conventions. It's moderately wasteful to
      -- call call fzy.score(x,y) followed by fzy.positions(x,y): both call the
      -- fzy.compute function, which does all the work. But, this doesn't affect
      -- perceived performance.
      highlighter = function(_, prompt, display)
        return fzy.positions(prompt, display)
      end,
    }
  end
end


SessionLens.search_session = function(custom_opts)
  custom_opts = (Lib.isEmptyTable(custom_opts) or custom_opts == nil) and SessionLens.conf or custom_opts

  -- Use auto_session_root_dir from the Auto Session plugin
  local cwd = AutoSession.conf.auto_session_root_dir

  if custom_opts.shorten_path ~= nil then
    Lib.logger.error('`shorten_path` config is deprecated, use the new `path_display` config instead')
    if custom_opts.shorten_path then
      custom_opts.path_display = {'shorten'}
    else
      custom_opts.path_display = nil
    end

    custom_opts.shorten_path = nil
  end

  local theme_opts = themes.get_dropdown(custom_opts.theme_conf)
  custom_opts["theme_conf"] = nil

  -- Ignore last session dir on finder if feature is enabled
  if AutoSession.conf.auto_session_enable_last_session then
    if AutoSession.conf.auto_session_last_session_dir then
      local last_session_dir = AutoSession.conf.auto_session_last_session_dir:gsub(cwd, "")
      custom_opts["file_ignore_patterns"] = {last_session_dir}
    end
  end

  -- Use default previewer config by setting the value to nil if some sets previewer to true in the custom config.
  -- Passing in the boolean value errors out in the telescope code with the picker trying to index a boolean instead of a table.
  -- This fixes it but also allows for someone to pass in a table with the actual preview configs if they want to.
  if custom_opts.previewer ~= false and custom_opts.previewer == true then
    custom_opts["previewer"] = nil
  end
  custom_opts["cwd"] = cwd

  local opts = {
    prompt_title = 'Sessions',
    entry_maker = Lib.make_entry.gen_from_file(custom_opts),
    cwd = cwd,
    -- sorter = telescope_config.generic_sorter(),
    layout_config = {
      height = 0.55,
      width = 0.7
    },
    attach_mappings = function(_, map)
      actions.select_default:replace(SessionLensActions.source_session)
      map("i", "<c-d>", SessionLensActions.delete_session)
      return true
    end,
  }

  local find_files_conf = vim.tbl_deep_extend("force", theme_opts, opts, custom_opts or {})

  local teleconf = require("telescope.config").values
  default_sorter = teleconf.file_sorter

  teleconf.file_sorter = modification_date_sorter(cwd)
  require("telescope.builtin").find_files(find_files_conf)
  teleconf.file_sorter = default_sorter
end

return SessionLens

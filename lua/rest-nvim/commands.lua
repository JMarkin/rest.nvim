---@mod rest-nvim.commands rest.nvim commands
---
---@brief [[
---
--- `:Rest {command {args?}}`
---
--- command                         action
---------------------------------------------------------------------------------
---
--- run {scope?}                    Execute one or several HTTP requests depending
---                                 on given `scope`. This scope can be either `last`,
---                                 `cursor` (default) or `document`.
---
--- last                            Re-run the last executed request, alias to `run last`
---                                 to retain backwards compatibility with the old keybinds
---                                 layout.
---
--- logs                            Open the rest.nvim logs file in a new tab.
---
--- env {action?} {path?}           Manage the environment file that is currently in use while
---                                 running requests. If you choose to `set` the environment,
---                                 you must provide a `path` to the environment file. The
---                                 default action is `show`, which displays the current
---                                 environment file path.
---
--- result {direction?}             Cycle through the results buffer winbar panes. The cycle
---                                 direction can be either `next` or `prev`.
---
---@brief ]]

-- HACK: what is the type of opts here?

---@class RestCmd
---@field impl fun(args:string[], opts: any) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] Command completions callback, taking the lead of the subcommand's argument

local commands = {}

local dotenv = require("rest-nvim.dotenv")
local request = require("rest-nvim.request")
local logger = require("rest-nvim.logger")
local parser = require("rest-nvim.parser")


---@type table<string, RestCmd>
local rest_command_tbl = {
  run = {
    -- TODO: run request by name
    impl = function(args, opts)
      if #args > 1 then
        vim.notify("Running multiple request isn't supported yet", vim.log.levels.WARN)
        return
      elseif #args == 1 then
        -- TODO: get request by name
        request.run_by_name(args[1])
        return
      end
      -- TODO: open result window here (use `:horizontal`)
      request.run()
    end,
    ---@return string[]
    complete = function (args)
      local names = parser.get_request_names(0)
      local matches = vim.iter(names):filter(function (name)
        return name:find("^" .. vim.pesc(args))
      end):map(function (name)
        name = name:gsub("%s+", "\\ ")
        return name
      end):totable()
      return matches
    end
  },
  last = {
    impl = function(_, _)
      request.run_last()
    end,
  },
  logs = {
    impl = function(_, opts)
      local is_split = opts.smods.vertiacal or opts.smods.horizontal
      local is_tab = opts.smods.tab ~= -1
      if is_split or is_tab then
        ---@diagnostic disable-next-line: invisible
        vim.cmd(opts.mods .. " split " .. logger.get_logfile())
      else
        ---@diagnostic disable-next-line: invisible
        vim.cmd.edit(logger.get_logfile())
      end
    end,
  },
  env = {
    impl = function(args, _)
      if not args[1] or args[1] == "show" then
        dotenv.show_registered_file()
        return
      elseif args[1] == "set" then
        if #args < 2 then
          vim.notify("Not enough arguments were passed to the 'env' command: 2 argument were expected, 1 was passed", vim.log.levels.ERROR)
          return
        end
        dotenv.register_file(args[2])
      elseif args[1] == "select" then
        dotenv.select_file()
      else
        vim.notify("Invalid action '" .. args[1] .. "' provided to 'env' command", vim.log.levels.ERROR)
      end
    end,
    ---@return string[]
    complete = function(args)
      local actions = { "show", "set", "select" }
      if #args < 1 then
        return actions
      end

      -- If the completion arguments have a whitespace then treat them as a table instead for easiness
      if args:find(" ") then
        args = vim.split(args, " ", { trimempty = true })
      end
      -- If the completion arguments is a table and `set` is the desired action then
      -- return a list of files in the current working directory for completion
      if type(args) == "table" and args[1]:match("set") then
        return dotenv.find_env_files()
      end

      local match = vim.tbl_filter(function(action)
        if string.find(action, "^" .. args) then
          return action
          ---@diagnostic disable-next-line missing-return
        end
      end, actions)

      return match
    end,
  },
}

local function rest(opts)
  local fargs = opts.fargs
  local cmd = fargs[1]
  local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
  local command = rest_command_tbl[cmd]

  if not command then
    logger.error("Unknown command: " .. cmd)
    vim.notify("Unknown command: " .. cmd)
    return
  end

  command.impl(args, opts)
end

---@package
function commands.init(bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, "Rest", rest, {
    nargs = "+",
    desc = "Run your HTTP requests",
    complete = function(arg_lead, cmdline, _)
      local rest_commands = vim.tbl_keys(rest_command_tbl)
      local subcmd, subcmd_arg_lead = cmdline:match("^Rest*%s(%S+)%s(.*)$")
      if subcmd and subcmd_arg_lead and rest_command_tbl[subcmd] and rest_command_tbl[subcmd].complete then
        return rest_command_tbl[subcmd].complete(subcmd_arg_lead)
      end
      if cmdline:match("^Rest*%s+%w*$") then
        return vim.tbl_filter(function(cmd)
          if string.find(cmd, "^" .. arg_lead) then
            return cmd
            ---@diagnostic disable-next-line missing-return
          end
        end, rest_commands)
      end
    end,
  })
end

---Register a new `:Rest` subcommand
---@see vim.api.nvim_buf_create_user_command
---@param name string The name of the subcommand
---@param cmd RestCmd The implementation and optional completions
---@package
function commands.register_subcommand(name, cmd)
  vim.validate({ name = { name, "string" } })
  vim.validate({ impl = { cmd.impl, "function" }, complete = { cmd.complete, "function", true } })

  rest_command_tbl[name] = cmd
end

return commands

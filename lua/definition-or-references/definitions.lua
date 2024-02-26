local log = require("definition-or-references.util.debug")
local methods = require("definition-or-references.methods_state")
local util = require("definition-or-references.utils")
local references = require("definition-or-references.references")
local config = require("definition-or-references.config")

local function definitions()
  local current_cursor = vim.api.nvim_win_get_cursor(0)
  local current_bufnr = vim.fn.bufnr("%")

  log.trace("definitions", "Starting definitions request")
  methods.definitions.cancel_function = vim.lsp.buf_request_all(
    0,
    methods.definitions.name,
    util.make_params(),
    function(results)
      log.trace("definitions", "Starting definitions request handling")
      methods.definitions.is_pending = false

      local flat_results = {}
      for client_id, r in pairs(results) do
        local err = r.error
        local result = r.result
        if err then
          if config.get_notify_option("errors") then
            vim.notify(
              string.format("client_id: %s; %s", client_id, err.message),
              vim.log.levels.ERROR
            )
          end
        else
          vim.list_extend(flat_results, util.parse_result(result))
        end
      end

      local result = util.dedup_results(flat_results)
      methods.definitions.result = result

      -- I assume that the we care about only one (first) definition
      if result and #result > 0 then
        local first_definition = result[1]

        if util.cursor_not_on_result(current_bufnr, current_cursor, first_definition) then
          -- hack
          local client_id = vim.tbl_keys(results)[1]

          methods.clear_references()
          log.trace("definitions", "Current cursor not on result")
          vim.lsp.util.jump_to_location(
            first_definition,
            vim.lsp.get_client_by_id(client_id).offset_encoding
          )
          return
        end
      end

      -- I've found a case when there is no definition and there are references
      -- in such case fallback to references
      log.trace("definitions", "Current cursor on only definition")

      if not methods.references.is_pending then
        log.trace("definitions", "handle_references_response")
        references.handle_references_response()
      end
    end
  )

  methods.definitions.is_pending = true
end

return definitions

local log = require("definition-or-references.util.debug")
local methods = require("definition-or-references.methods_state")
local util = require("definition-or-references.utils")
local references = require("definition-or-references.references")
local config = require("definition-or-references.config")

local ms = require("vim.lsp.protocol").Methods

local nio = require("nio")

local function definitions()
  nio.run(function()
    local cursor = nio.api.nvim_win_get_cursor(0)
    local bufnr = nio.api.nvim_get_current_buf()

    local clients = nio.lsp.get_clients({ bufnr = bufnr, method = ms.textDocument_definition })
    ---@type nio.lsp.types.TextDocumentPositionParams
    local params = vim.lsp.util.make_position_params(0)

    methods.definitions.is_pending = true

    log.trace("definitions", "Starting definitions request")

    local fns = {}
    for _, c in ipairs(clients) do
      fns[#fns + 1] = function()
        local err, result = c.request.textDocument_definition(params, bufnr, { timeout = 1500 })
        return { err, result }
      end
    end

    local results = nio.gather(fns)

    local errors = {}
    local flat_results = {}
    for _, r in ipairs(results) do
      local err, res = unpack(r)
      if err then
        errors[#errors + 1] = err
      elseif res ~= nil then
        vim.list_extend(flat_results, util.parse_result(res))
      end
    end

    if config.get_notify_option("errors") then
      for _, error in pairs(errors) do
        vim.api.nvim_err_writeln(error.message)
      end
    end

    local result = util.dedup_results(flat_results)
    methods.definitions.result = result
    methods.definitions.is_pending = false

    -- assume that we care about only one (first) definition
    if result and #result > 0 then
      local first_definition = result[1]
      if util.cursor_not_on_result(bufnr, cursor, first_definition) then
        local offset_encoding = vim.lsp.get_clients({
          method = ms.textDocument_definition,
          bufnr = bufnr,
        })[1].offset_encoding

        methods.clear_references()

        log.trace("definitions", "Current cursor not on result")
        vim.lsp.util.jump_to_location(first_definition, offset_encoding)
        return
      end
    end

    references.send_references_request(false)

    -- I've found a case when there is no definition and there are references
    -- in such case fallback to references
    log.trace("definitions", "Current cursor on only definition")

    if not methods.references.is_pending then
      log.trace("definitions", "handle_references_response")
      references.handle_references_response()
    end
  end)
end

return definitions

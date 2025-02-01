local log = require("definition-or-references.util.debug")
local methods = require("definition-or-references.methods_state")
local util = require("definition-or-references.utils")
local references = require("definition-or-references.references")
local config = require("definition-or-references.config")

local ms = require("vim.lsp.protocol").Methods

local nio = require("nio")

local function definitions()
  local c = vim
    .iter(vim.lsp.get_clients({
      method = ms.textDocument_definition,
      bufnr = 0,
    }))
    :find(function(c)
      return c.name ~= "null-ls"
    end)

  local position_encoding = c and c.offset_encoding

  methods.definitions.is_pending = true

  nio.run(function()
    local cursor = nio.api.nvim_win_get_cursor(0)
    local bufnr = nio.api.nvim_get_current_buf()
    local params = vim.lsp.util.make_position_params(0, position_encoding)

    log.trace("definitions", "Starting definitions request")

    local clients = vim
      .iter(nio.lsp.get_clients({ bufnr = bufnr, method = ms.textDocument_definition }))
      :filter(function(c)
        return vim.tbl_get(c, "server_capabilities", "definitionProvider")
      end)
      :totable()

    local fns = {}
    for _, c in ipairs(clients) do
      fns[#fns + 1] = function()
        -- TODO position/offset_encoding
        -- needs nio to expose id, name, and position/offset_encoding

        -- local params = vim.lsp.util.make_position_params(window)
        ---@diagnostic disable-next-line: param-type-mismatch
        local err, result = c.request.textDocument_definition(params, bufnr, { timeout = 1500 })
        return { err, result }
      end
    end

    local results = nio.gather(fns)

    local result_count = 0
    local errors = {}
    local flat_results = {}
    for _, r in ipairs(results) do
      local client_id, _ = next(r)
      local err, res = unpack(r)

      if err then
        errors[#errors + 1] = { client_id = client_id, err = err }
      elseif res ~= nil then
        for _, v in ipairs(util.parse_result(res)) do
          result_count = result_count + 1
          if util.cursor_not_on_result(bufnr, cursor, v) then
            flat_results[#flat_results + 1] = { client_id = client_id, result = v }
          end
        end
      end
    end

    if config.get_notify_option("errors") then
      for _, error in pairs(errors) do
        vim.api.nvim_err_writeln(error.client_id .. " " .. error.err.message)
      end
    end

    methods.definitions.result_count = result_count
    methods.definitions.is_pending = false

    results = util.dedup_results(flat_results)

    -- assume that we care about only one (first) definition
    if results and #results > 0 then
      methods.clear_references()

      local client_id = results[1].client_id
      local first_definition = results[1].result
      local client = vim.lsp.get_client_by_id(client_id)

      local offset_encoding = client and client.offset_encoding
        or vim
          .iter(vim.lsp.get_clients({
            method = ms.textDocument_definition,
            bufnr = bufnr,
          }))
          :find(function(c)
            return c.name ~= "null-ls"
          end).offset_encoding

      log.trace("definitions", "Current cursor not on result")
      vim.lsp.util.show_document(
        first_definition,
        offset_encoding,
        { focus = true, reuse_win = true }
      )
      return
    end

    references.send_references_request()

    -- I've found a case when there is no definition and there are references
    -- in such case fallback to references
    log.trace("definitions", "Current cursor on only definition")

    nio.scheduler()
    if not methods.references.is_pending then
      log.trace("definitions", "handle_references_response")
      references.handle_references_response()
    end
  end)
end

return definitions

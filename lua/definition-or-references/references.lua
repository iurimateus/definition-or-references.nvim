local methods = require("definition-or-references.methods_state")
local utils = require("definition-or-references.utils")
local log = require("definition-or-references.util.debug")
local config = require("definition-or-references.config")
local ms = require("vim.lsp.protocol").Methods

local function handle_references_response()
  log.trace("handle_references_response", "handle_references_response")
  local result_entries = methods.references.result

  if not result_entries or vim.tbl_isempty(result_entries) then
    if
      (methods.definitions.result_count and methods.definitions.result_count > 0)
      and config.get_notify_option("on_definition_no_reference")
    then
      vim.notify("Cursor on definition and no references found")
    elseif
      (not methods.definitions.result_count or methods.definitions.result_count == 0)
      and config.get_notify_option("no_definition_no_reference")
    then
      vim.notify("No definition or references found")
    end
    return
  end

  if #result_entries == 1 then
    if
      methods.definitions.result_count
      and config.get_notify_option("on_definition_one_reference")
    then
      vim.notify("Cursor on definition and only one reference found")
    elseif
      (not methods.definitions.result_count or methods.definitions.result_count == 0)
      and config.get_notify_option("no_definition_one_reference")
    then
      vim.notify("No definition but single reference found")
    end

    local client_id = result_entries[1].client_id
    local client = vim.lsp.get_client_by_id(client_id)

    local position_encoding = client and client.offset_encoding
      or vim
        .iter(vim.lsp.get_({
          method = ms.textDocument_references,
          -- bufnr = bufnr,
        }))
        :find(function(c)
          return c.name ~= "null-ls"
        end).offset_encoding

    vim.lsp.util.show_document(
      result_entries[1].result,
      position_encoding,
      { focus = true, reuse_win = true }
    )
    return
  end

  local on_references_result = config.get_config().on_references_result

  if on_references_result then
    local entries = vim.tbl_map(function(x)
      return x.result
    end, result_entries)

    return on_references_result(entries)
  end
end

local function send_references_request(includeDeclaration)
  includeDeclaration = vim.F.if_nil(includeDeclaration, true)

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)

  log.trace("send_references_request", "Starting references request")
  methods.references.cancel_function = vim.lsp.buf_request_all(
    bufnr,
    methods.references.name,
    utils.make_params(includeDeclaration),
    function(results)
      log.trace("send_references_request", "Starting references request handling")
      -- sometimes when cancel function was called after request has been fulfilled this would be called
      -- if cancel_function is nil that means that references was cancelled
      if methods.references.cancel_function == nil then
        return
      end

      methods.references.is_pending = false

      local flat_results = {}
      for client_id, res in pairs(results) do
        local err = res.err
        if err then
          if config.get_notify_option("errors") then
            vim.notify(
              string.format("client_id: %s; %s", client_id, err.message),
              vim.log.levels.ERROR
            )
          end
        else
          for _, v in ipairs(utils.parse_result(res.result)) do
            if utils.cursor_not_on_result(bufnr, cursor, v) then
              flat_results[#flat_results + 1] = { client_id = client_id, result = v }
            end
          end
        end
      end

      methods.references.result = utils.dedup_results(flat_results)

      if not methods.definitions.is_pending then
        log.trace("send_references_request", "handle_references_response")
        handle_references_response()
      end
    end
  )

  methods.references.is_pending = true
end

return {
  send_references_request = send_references_request,
  handle_references_response = handle_references_response,
}

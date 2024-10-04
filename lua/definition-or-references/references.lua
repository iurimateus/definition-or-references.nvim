local methods = require("definition-or-references.methods_state")
local utils = require("definition-or-references.utils")
local log = require("definition-or-references.util.debug")
local config = require("definition-or-references.config")

local function handle_references_response()
  log.trace("handle_references_response", "handle_references_response")
  local result_entries = methods.references.result

  if not result_entries or vim.tbl_isempty(result_entries) then
    if
      (methods.definitions.result and #methods.definitions.result > 0)
      and config.get_notify_option("on_definition_no_reference")
    then
      vim.notify("Cursor on definition and no references found")
    elseif
      (not methods.definitions.result or #methods.definitions.result == 0)
      and config.get_notify_option("no_definition_no_reference")
    then
      vim.notify("No definition or references found")
    end
    return
  end

  if #result_entries == 1 then
    if
      methods.definitions.result
      and #methods.definitions.result > 0
      and config.get_notify_option("on_definition_one_reference")
    then
      vim.notify("Cursor on definition and only one reference found")
    elseif
      (not methods.definitions.result or #methods.definitions.result == 0)
      and config.get_notify_option("no_definition_one_reference")
    then
      vim.notify("No definition but single reference found")
    end

    -- vim.print(result_entries, result_entries[1])
    vim.lsp.util.jump_to_location(result_entries[1], "utf-16", true)
    return
  end

  local on_references_result = config.get_config().on_references_result

  if on_references_result then
    return on_references_result(result_entries)
  end
end

local function send_references_request(includeDeclaration)
  includeDeclaration = vim.F.if_nil(includeDeclaration, true)

  log.trace("send_references_request", "Starting references request")
  methods.references.cancel_function = vim.lsp.buf_request_all(
    0,
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
        local err = res.error
        if err then
          if config.get_notify_option("errors") then
            vim.notify(
              string.format("client_id: %s; %s", client_id, err.message),
              vim.log.levels.ERROR
            )
          end
        else
          vim.list_extend(flat_results, utils.parse_result(res.result))
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

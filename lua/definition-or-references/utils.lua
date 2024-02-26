local config = require("definition-or-references.config")

local M = {}

function M.parse_result(v)
  if not v then
    return {}
  end

  local parsed = {}
  -- if has `range` than result is a single value
  if v.range then
    table.insert(parsed, v)
  else -- otherwise it is a table of results
    for _, vv in ipairs(v) do
      table.insert(parsed, vv)
    end
  end

  return parsed
end

function M.dedup_results(result)
  if #result <= 1 then
    return result
  end

  local seen = {}
  local filtered_result = {}
  for _, r in pairs(result) do
    local uri = r.uri or r.targetUri
    if not seen[uri] then
      seen[uri] = {}
    end

    local range = r.range or r.targetRange
    local start_line = range.start.line
    if not seen[uri][start_line] then
      seen[uri][start_line] = true
      filtered_result[#filtered_result + 1] = r
    end
  end

  return filtered_result
end

function M.cursor_not_on_result(bufnr, cursor, result)
  local target_uri = result.targetUri or result.uri
  local target_range = result.targetRange or result.range

  local target_bufnr = vim.uri_to_bufnr(target_uri)
  local target_row_start = target_range.start.line + 1
  local target_row_end = target_range["end"].line + 1
  local target_col_start = target_range.start.character + 1
  local target_col_end = target_range["end"].character + 1

  local current_bufnr = bufnr
  local current_range = cursor
  local current_row = current_range[1]
  local current_col = current_range[2] + 1 -- +1 because if cursor highlights first character its a column behind

  return target_bufnr ~= current_bufnr
    or current_row < target_row_start
    or current_row > target_row_end
    or (current_row == target_row_start and current_col < target_col_start)
    or (current_row == target_row_end and current_col > target_col_end)
end

function M.get_filename_fn()
  local bufnr_name_cache = {}
  return function(bufnr)
    bufnr = vim.F.if_nil(bufnr, 0)
    local c = bufnr_name_cache[bufnr]
    if c then
      return c
    end

    local n = vim.api.nvim_buf_get_name(bufnr)
    bufnr_name_cache[bufnr] = n
    return n
  end
end

function M.make_params()
  local params = vim.lsp.util.make_position_params(0)

  params.context = { includeDeclaration = false }

  return params
end

return M

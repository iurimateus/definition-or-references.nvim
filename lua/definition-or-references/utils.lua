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
  elseif type(v) == "table" then
    -- otherwise it is a table of results
    for _, vv in ipairs(v) do
      parsed[#parsed + 1] = vv
    end
  end

  return parsed
end

function M.dedup_results(results)
  if #results <= 1 then
    return results
  end

  local seen = {}
  local filtered_result = {}
  if results[1].client_id or results[1].result then
    for _, t in pairs(results) do
      local r = t.result
      local uri = r.uri or r.targetUri
      if not seen[uri] then
        seen[uri] = {}
      end

      local range = r.range or r.targetRange
      local start_line = range.start.line
      if not seen[uri][start_line] then
        seen[uri][start_line] = true
        filtered_result[#filtered_result + 1] = { client_id = t.client_id, result = r }
      end
    end

    return filtered_result
  end

  for _, r in pairs(results) do
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

  if
    target_bufnr ~= current_bufnr
    or current_row < target_row_start
    or current_row > target_row_end
  then
    return true
  end

  if current_row == target_row_start and target_row_start == target_row_end then
    return false
  elseif
    (current_row == target_row_start and current_col < target_col_start)
    or (current_row == target_row_end and current_col > target_col_end)
  then
    return true
  end
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

function M.make_params(includeDeclaration)
  local params = vim.lsp.util.make_position_params(0)
  includeDeclaration = vim.F.if_nil(includeDeclaration, false)
  params.context = { includeDeclaration = includeDeclaration }

  return params
end

return M

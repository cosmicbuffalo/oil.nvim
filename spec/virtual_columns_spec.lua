local columns = require('oil.columns')
local config = require('oil.config')
local constants = require('oil.constants')
local parser = require('oil.mutator.parser')
local test_adapter = require('oil.adapters.test')
local test_util = require('spec.test_util')

local FIELD_ID = constants.FIELD_ID

describe('virtual columns', function()
  after_each(function()
    test_util.reset_editor()
  end)

  it('keeps virtual values out of buffer text and renders a virtual header', function()
    require('oil').setup({
      adapters = { ['oil-test://'] = 'test' },
      columns = {
        { 'type', align = 'right' },
        'name',
        { 'type', align = 'left' },
      },
      virtual_text_columns = true,
      show_header = true,
      header_format = function(text)
        return text == 'TYPE' and 'KIND' or text
      end,
    })
    local file = test_adapter.test_set('/foo/a.txt', 'file')
    test_adapter.test_set('/foo/long-directory', 'directory')

    vim.cmd.edit({ args = { 'oil-test:///foo/' } })
    test_util.wait_oil_ready()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    assert.are.equal(2, #lines)
    assert.matches('^/%d+%s+long%-directory/$', lines[1])
    assert.matches('^/%d+%s+a%.txt$', lines[2])
    assert.not_matches('directory%s+long%-directory', lines[1])
    assert.not_matches('file%s+a%.txt', lines[2])

    local column_ns = vim.api.nvim_create_namespace('OilVirtualColumns')
    local header_ns = vim.api.nvim_create_namespace('OilColumnHeader')
    local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, column_ns, 0, -1, { details = true })
    local headers = vim.api.nvim_buf_get_extmarks(bufnr, header_ns, 0, -1, { details = true })
    assert.are.equal(2, #extmarks)
    assert.are.equal(1, #headers)
    assert.matches('KIND', headers[1][4].virt_lines[1][1][1])

    vim.bo[bufnr].modifiable = true
    lines[2] = lines[2]:gsub('a%.txt$', 'b.txt')
    vim.api.nvim_buf_set_lines(bufnr, 1, 2, true, { lines[2] })
    local diffs, errors = parser.parse(bufnr)
    assert.are.same({}, errors)
    assert.are.same({
      { type = 'new', id = file[FIELD_ID], name = 'b.txt', entry_type = 'file' },
      { type = 'delete', id = file[FIELD_ID], name = 'a.txt' },
    }, diffs)
  end)

  it('supports function formatters for virtual time columns', function()
    config.setup({ virtual_text_columns = true })
    local adapter = require('oil.adapters.files')
    local entry = { 1, 'a.txt', 'file', { stat = { mtime = { sec = 3600 } } } }
    local chunk = columns.render_col(adapter, {
      'mtime',
      format = function(seconds, formatted_entry, bufnr)
        assert.are.equal('a.txt', formatted_entry.name)
        assert.are.equal(7, bufnr)
        return string.format('%dh ago', seconds / 3600)
      end,
    }, entry, 7)
    assert.are.equal('1h ago', chunk)
  end)

  it('keeps editable columns physical when virtual columns are interleaved', function()
    columns.register('test-editable', {
      render = function()
        return 'rw'
      end,
      parse = function(line)
        return line:match('^(%S+)%s+(.*)$')
      end,
      perform_action = function(_, callback)
        callback()
      end,
    })
    require('oil').setup({
      adapters = { ['oil-test://'] = 'test' },
      columns = { 'type', 'test-editable', 'type', 'name' },
      virtual_text_columns = true,
    })
    test_adapter.test_set('/foo/a.txt', 'file')
    vim.cmd.edit({ args = { 'oil-test:///foo/' } })
    test_util.wait_oil_ready()

    local line = vim.api.nvim_buf_get_lines(0, 0, 1, true)[1]
    assert.matches('^/%d+%s+rw%s+a%.txt$', line)
    assert.not_matches('file', line)
    local result =
      assert(parser.parse_line(test_adapter, line, columns.get_editable_columns(test_adapter)))
    assert.are.equal('rw', result.data['test-editable'])
    assert.are.equal('a.txt', result.data.name)
  end)

  it('can show headers while columns remain in buffer text', function()
    require('oil').setup({
      adapters = { ['oil-test://'] = 'test' },
      columns = { 'type' },
      show_header = true,
    })
    test_adapter.test_set('/foo/a.txt', 'file')
    vim.cmd.edit({ args = { 'oil-test:///foo/' } })
    test_util.wait_oil_ready()

    local header_ns = vim.api.nvim_create_namespace('OilColumnHeader')
    local headers = vim.api.nvim_buf_get_extmarks(0, header_ns, 0, -1, { details = true })
    assert.are.equal(1, #headers)
    assert.matches('TYPE', headers[1][4].virt_lines[1][1][1])
  end)

  it('rejects function formatters when columns are stored in buffer text', function()
    config.setup({ virtual_text_columns = false })
    local adapter = require('oil.adapters.files')
    local entry = { 1, 'a.txt', 'file', { stat = { mtime = { sec = 3600 } } } }
    assert.has_error(function()
      columns.render_col(adapter, {
        'mtime',
        format = function()
          return 'custom'
        end,
      }, entry, 1)
    end, 'Function formatters for time columns require virtual_text_columns = true')
  end)

  it('rejects editable columns after the filename', function()
    config.setup({ virtual_text_columns = true, columns = { 'name', 'permissions' } })
    local adapter = require('oil.adapters.files')
    assert.has_error(function()
      columns.get_column_layout(adapter)
    end, 'Editable column "permissions" cannot be configured after the "name" column')
  end)
end)

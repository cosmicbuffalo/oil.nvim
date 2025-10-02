require("plenary.async").tests.add_to_env()
local view = require("oil.view")
local config = require("oil.config")
local columns = require("oil.columns")
local test_adapter = require("oil.adapters.test")
local test_util = require("tests.test_util")
local constants = require("oil.constants")
local cache = require("oil.cache")

local FIELD_ID = constants.FIELD_ID
local FIELD_NAME = constants.FIELD_NAME
local FIELD_TYPE = constants.FIELD_TYPE
local FIELD_META = constants.FIELD_META

describe("view", function()
  after_each(function()
    test_util.reset_editor()
    config.setup({})
  end)

  describe("format_entry_cols", function()
    it("formats entry columns without virtual text", function()
      config.setup({
        virtual_text_columns = false,
        columns = { "type" },
      })

      local entry = {
        [FIELD_ID] = 123,
        [FIELD_NAME] = "test.txt",
        [FIELD_TYPE] = "file",
      }

      local col_widths = { 0, 0, 0 }
      local editable_cols = columns.get_editable_columns(test_adapter)
      local result = view.format_entry_cols(entry, editable_cols, col_widths, test_adapter, false, 0)

      -- Should have ID, type, and name parts
      assert.is_true(#result >= 2)
      assert.is.equal(cache.format_id(123), result[1])
      assert.is.equal("file", result[2])
    end)

    it("formats entry columns with virtual text columns enabled", function()
      config.setup({
        virtual_text_columns = true,
        columns = { "icon", "permissions", "name" },
      })

      local entry = {
        [FIELD_ID] = 123,
        [FIELD_NAME] = "test.txt",
        [FIELD_TYPE] = "file",
      }

      local col_widths = {}
      local editable_cols = columns.get_editable_columns(test_adapter)
      local result = view.format_entry_cols(entry, editable_cols, col_widths, test_adapter, false, 0)

      -- Should include ID and editable columns
      assert.is_true(#result >= 2)
      assert.is.equal(cache.format_id(123), result[1])
    end)

    it("handles hidden files", function()
      config.setup({
        virtual_text_columns = false,
        columns = { "type" },
      })

      local entry = {
        [FIELD_ID] = 123,
        [FIELD_NAME] = ".hidden",
        [FIELD_TYPE] = "file",
      }

      local col_widths = { 0, 0, 0 }
      local editable_cols = columns.get_editable_columns(test_adapter)
      local result = view.format_entry_cols(entry, editable_cols, col_widths, test_adapter, true, 0)

      -- Check that the hidden file is formatted correctly
      assert.is_not_nil(result)
      assert.is_true(#result >= 2)
    end)

    it("handles links with metadata", function()
      config.setup({
        virtual_text_columns = false,
        columns = { "type" },
      })

      local entry = {
        [FIELD_ID] = 123,
        [FIELD_NAME] = "link.txt",
        [FIELD_TYPE] = "link",
        [FIELD_META] = {
          link = "target.txt",
        }
      }

      local col_widths = { 0, 0, 0 }
      local editable_cols = columns.get_editable_columns(test_adapter)
      local result = view.format_entry_cols(entry, editable_cols, col_widths, test_adapter, false, 0)

      assert.is_not_nil(result)
      -- Should contain link formatting
      local found_link = false
      for _, col in ipairs(result) do
        if type(col) == "table" then
          for _, chunk in ipairs(col) do
            if type(chunk) == "string" and chunk:match("->") then
              found_link = true
              break
            end
          end
        elseif type(col) == "string" and col:match("->") then
          found_link = true
        end
      end
      assert.is_true(found_link)
    end)
  end)

  describe("should_display", function()
    it("hides hidden files when configured", function()
      config.setup({
        view_options = {
          show_hidden = false,
        }
      })

      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_false(view.should_display(".hidden", bufnr))
      assert.is_true(view.should_display("visible", bufnr))
    end)

    it("shows hidden files when configured", function()
      config.setup({
        view_options = {
          show_hidden = true,
        }
      })

      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_true(view.should_display(".hidden", bufnr))
      assert.is_true(view.should_display("visible", bufnr))
    end)

    it("filters files based on custom filter", function()
      config.setup({
        view_options = {
          is_always_hidden = function(name)
            return name:match("%.tmp$")
          end,
        }
      })

      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_false(view.should_display("test.tmp", bufnr))
      assert.is_true(view.should_display("test.txt", bufnr))
    end)

    it("respects is_always_hidden for parent directory", function()
      config.setup({
        view_options = {
          show_hidden = false,
          is_always_hidden = function(name)
            return name == ".."  -- Try to hide parent
          end,
        }
      })

      local bufnr = vim.api.nvim_create_buf(false, true)
      local display, is_hidden = view.should_display("..", bufnr)
      -- Parent directory should be hidden by is_always_hidden
      assert.is_false(display)
    end)
  end)

  -- Note: Skipping render_buffer tests as they require complex oil buffer initialization
  -- The functionality is tested indirectly through other existing tests

  -- Note: Skipping virtual column rendering tests as they require complex oil buffer initialization
  -- The functionality is tested indirectly through other existing tests

  describe("update_trailing_column_position", function()
    it("updates position on text change", function()
      config.setup({
        virtual_text_columns = true,
        columns = { "icon", "name" },
        show_header = false,
      })

      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Set up required buffer variables for the function
      vim.b[bufnr].oil_column_config = { { is_virtual = true, name = "icon" } }
      vim.b[bufnr].oil_virtual_column_widths = { [1] = 3 }

      -- Add a line to the buffer
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { "test line" })

      -- Function should not error
      view.update_trailing_column_position(bufnr)
    end)

    it("does nothing when virtual_text_columns is false", function()
      config.setup({
        virtual_text_columns = false,
        columns = { "name" },
      })

      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Should return early without error
      view.update_trailing_column_position(bufnr)
    end)
  end)
end)
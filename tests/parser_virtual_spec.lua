require("plenary.async").tests.add_to_env()
local constants = require("oil.constants")
local parser = require("oil.mutator.parser")
local test_adapter = require("oil.adapters.test")
local test_util = require("tests.test_util")
local columns = require("oil.columns")
local config = require("oil.config")

describe("parser with virtual columns", function()
  after_each(function()
    test_util.reset_editor()
  end)

  describe("parse_line", function()
    it("uses editable columns when virtual_text_columns is enabled", function()
      config.setup({
        virtual_text_columns = true,
        columns = { "icon", "type", "name" },
        adapters = {
          ["oil-test://"] = "test",
        },
      })

      -- Create a test entry first to get an ID
      local entry = test_adapter.test_set("/test/test_dir/", "directory")
      local id = entry[1] -- FIELD_ID

      local line = string.format("/%d test_dir/", id)
      local editable_cols = columns.get_editable_columns(test_adapter)
      local result = parser.parse_line(test_adapter, line, editable_cols)

      assert.is_not_nil(result)
      assert.is_not_nil(result.data)
      assert.is.equal("test_dir", result.data.name)
      assert.is.equal("directory", result.data._type)
    end)

    it("handles name column correctly when virtual_text_columns is true", function()
      config.setup({
        virtual_text_columns = true,
        columns = { "icon", "name" },
        adapters = {
          ["oil-test://"] = "test",
        },
      })

      -- Create a test entry first
      local entry = test_adapter.test_set("/test/test_file.txt", "file")
      local id = entry[1] -- FIELD_ID

      local line = string.format("/%d test_file.txt", id)
      local editable_cols = columns.get_editable_columns(test_adapter)
      local result = parser.parse_line(test_adapter, line, editable_cols)

      assert.is_not_nil(result)
      assert.is_not_nil(result.data)
      -- Name should still be parsed from the remaining text
      assert.is.equal("test_file.txt", result.data.name)
    end)

    it("parses normally when virtual_text_columns is false", function()
      config.setup({
        virtual_text_columns = false,
        columns = { "type" },
        adapters = {
          ["oil-test://"] = "test",
        },
      })

      -- Create a test entry
      local entry = test_adapter.test_set("/test/test_dir/", "directory")
      local id = entry[1] -- FIELD_ID

      local line = string.format("/%d dir test_dir/", id)
      local editable_cols = columns.get_editable_columns(test_adapter)
      local result = parser.parse_line(test_adapter, line, editable_cols)

      assert.is_not_nil(result)
      assert.is_not_nil(result.data)
      assert.is.equal("test_dir", result.data.name)
      assert.is.equal("directory", result.data._type)
    end)
  end)

  -- Note: Skipping parse buffer tests as they require complex oil buffer initialization
  -- The parse_line tests above cover the essential functionality
end)
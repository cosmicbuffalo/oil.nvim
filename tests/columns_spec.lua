require("plenary.async").tests.add_to_env()
local columns = require("oil.columns")
local config = require("oil.config")
local test_adapter = require("oil.adapters.test")
local test_util = require("tests.test_util")
local constants = require("oil.constants")

local FIELD_NAME = constants.FIELD_NAME
local FIELD_TYPE = constants.FIELD_TYPE
local FIELD_ID = constants.FIELD_ID
local FIELD_META = constants.FIELD_META

describe("columns", function()
  after_each(function()
    test_util.reset_editor()
    config.setup({})
  end)

  describe("get_editable_columns", function()
    it("returns all columns when virtual_text_columns is false", function()
      config.setup({
        virtual_text_columns = false,
        columns = { "icon", "permissions", "name" },
      })
      local editable = columns.get_editable_columns(test_adapter)
      local supported = columns.get_supported_columns(test_adapter)
      assert.are.same(supported, editable)
    end)

    it("returns only editable columns when virtual_text_columns is true", function()
      config.setup({
        virtual_text_columns = true,
        columns = { "icon", "type", "name" },
      })

      local editable = columns.get_editable_columns(test_adapter)

      -- Type and name are editable (type has no perform_action but isn't editable)
      -- Icon is not editable
      local has_name = false
      local has_type = false
      local has_icon = false

      for _, col in ipairs(editable) do
        if col == "name" then has_name = true end
        if col == "type" then has_type = true end
        if col == "icon" then has_icon = true end
      end

      -- name is always editable
      assert.is_true(has_name)
      -- type and icon are not editable (no perform_action)
      assert.is_false(has_type)
      assert.is_false(has_icon)
    end)
  end)

  describe("is_editable_column", function()
    it("always returns true for name column", function()
      assert.is_true(columns.is_editable_column(test_adapter, "name"))
    end)

    it("returns false for type column (no perform_action)", function()
      -- Type column doesn't have perform_action
      assert.is_false(columns.is_editable_column(test_adapter, "type"))
    end)

    it("returns false for icon column (no perform_action)", function()
      -- Icon column doesn't have perform_action
      local result = columns.is_editable_column(test_adapter, "icon")
      assert.is_falsy(result)
    end)

    it("returns false for non-existent columns", function()
      local result = columns.is_editable_column(test_adapter, "nonexistent")
      assert.is_falsy(result)
    end)
  end)

  describe("render_col", function()
    it("renders icon column", function()
      local entry = {
        [FIELD_ID] = 1,
        [FIELD_NAME] = "test.txt",
        [FIELD_TYPE] = "file",
      }

      local chunk = columns.render_col(test_adapter, "icon", entry, 0)
      assert.is_not_nil(chunk)
    end)

    it("renders type column", function()
      local entry = {
        [FIELD_ID] = 1,
        [FIELD_NAME] = "test_dir",
        [FIELD_TYPE] = "directory",
      }

      local chunk = columns.render_col(test_adapter, "type", entry, 0)
      assert.is.equal("dir", chunk)
    end)

    it("renders type column for links", function()
      local entry = {
        [FIELD_ID] = 1,
        [FIELD_NAME] = "test_link",
        [FIELD_TYPE] = "link",
        [FIELD_META] = {
          link = "target.txt",
          link_stat = { type = "file" }
        }
      }

      local chunk = columns.render_col(test_adapter, "type", entry, 0)
      assert.is.equal("link", chunk)
    end)

    it("returns EMPTY for whitespace-only renders", function()
      -- Mock a column that returns whitespace
      columns.register("test_empty", {
        render = function() return "  " end,
        parse = function(line) return line:match("^(%s+)(.*)$") end,
      })

      local entry = {
        [FIELD_ID] = 1,
        [FIELD_NAME] = "test.txt",
        [FIELD_TYPE] = "file",
      }

      local chunk = columns.render_col(test_adapter, "test_empty", entry, 0)
      assert.are.same(columns.EMPTY, chunk)
    end)

    it("applies custom highlight from config", function()
      local entry = {
        [FIELD_ID] = 1,
        [FIELD_NAME] = "test.txt",
        [FIELD_TYPE] = "file",
      }

      columns.register("test_highlight", {
        render = function() return "test" end,
        parse = function(line) return line:match("^(%S+)%s+(.*)$") end,
      })

      local chunk = columns.render_col(
        test_adapter,
        { "test_highlight", highlight = "Comment" },
        entry,
        0
      )
      assert.are.same({ "test", "Comment" }, chunk)
    end)

    it("applies functional highlight from config", function()
      local entry = {
        [FIELD_ID] = 1,
        [FIELD_NAME] = "test.txt",
        [FIELD_TYPE] = "file",
      }

      columns.register("test_func_highlight", {
        render = function() return "test" end,
        parse = function(line) return line:match("^(%S+)%s+(.*)$") end,
      })

      local chunk = columns.render_col(
        test_adapter,
        { "test_func_highlight", highlight = function(text) return text == "test" and "Special" or "Normal" end },
        entry,
        0
      )
      assert.are.same({ "test", "Special" }, chunk)
    end)
  end)

  describe("parse_col", function()
    it("parses type column", function()
      local line = "file remaining text"
      local parsed, remaining = columns.parse_col(test_adapter, line, "type")
      assert.is.equal("file", parsed)
      assert.is.equal("remaining text", remaining)
    end)

    it("handles empty column marker", function()
      local line = "-  remaining text"
      local parsed, remaining = columns.parse_col(test_adapter, line, "type")
      assert.is_nil(parsed)
      assert.is.equal("remaining text", remaining)
    end)

    it("returns nil for non-existent columns", function()
      -- Nonexistent columns return nil
      local line = "test remaining text"
      local parsed, remaining = columns.parse_col(test_adapter, line, "nonexistent")
      assert.is_nil(parsed)
      assert.is_nil(remaining)
    end)
  end)

  describe("get_sort_value", function()
    it("sorts directories before files for type column", function()
      local dir_entry = {
        [FIELD_ID] = 1,
        [FIELD_NAME] = "dir",
        [FIELD_TYPE] = "directory",
      }

      local file_entry = {
        [FIELD_ID] = 2,
        [FIELD_NAME] = "file",
        [FIELD_TYPE] = "file",
      }

      local type_col = columns.get_column(test_adapter, "type")
      assert.is_not_nil(type_col.get_sort_value)

      local dir_sort = type_col.get_sort_value(dir_entry)
      local file_sort = type_col.get_sort_value(file_entry)

      assert.is_true(dir_sort < file_sort)
    end)

    it("sorts directory links as directories", function()
      local dir_link = {
        [FIELD_ID] = 1,
        [FIELD_NAME] = "link",
        [FIELD_TYPE] = "link",
        [FIELD_META] = {
          link_stat = { type = "directory" }
        }
      }

      local file_entry = {
        [FIELD_ID] = 2,
        [FIELD_NAME] = "file",
        [FIELD_TYPE] = "file",
      }

      local type_col = columns.get_column(test_adapter, "type")
      local link_sort = type_col.get_sort_value(dir_link)
      local file_sort = type_col.get_sort_value(file_entry)

      assert.is_true(link_sort < file_sort)
    end)
  end)

  describe("name column sorting", function()
    it("supports natural ordering for numbers", function()
      config.setup({
        view_options = {
          natural_order = true,
          case_insensitive = false,
        }
      })

      local name_col = columns.get_column(test_adapter, "name")
      local factory = name_col.create_sort_value_factory(10)

      local entry1 = { [FIELD_NAME] = "file1.txt" }
      local entry2 = { [FIELD_NAME] = "file10.txt" }
      local entry3 = { [FIELD_NAME] = "file2.txt" }

      local sort1 = factory(entry1)
      local sort2 = factory(entry2)
      local sort3 = factory(entry3)

      -- Natural order: file1 < file2 < file10
      assert.is_true(sort1 < sort3)
      assert.is_true(sort3 < sort2)
    end)

    it("supports case insensitive sorting", function()
      config.setup({
        view_options = {
          natural_order = false,
          case_insensitive = true,
        }
      })

      local name_col = columns.get_column(test_adapter, "name")
      local factory = name_col.create_sort_value_factory(10)

      local entry1 = { [FIELD_NAME] = "ABC.txt" }
      local entry2 = { [FIELD_NAME] = "abc.txt" }

      local sort1 = factory(entry1)
      local sort2 = factory(entry2)

      assert.is.equal(sort1, sort2)
    end)

    it("disables natural ordering for large file counts", function()
      config.setup({
        view_options = {
          natural_order = "fast",
          case_insensitive = false,
        }
      })

      local name_col = columns.get_column(test_adapter, "name")
      -- Create factory with > 5000 entries
      local factory = name_col.create_sort_value_factory(5001)

      local entry1 = { [FIELD_NAME] = "file10.txt" }
      local entry2 = { [FIELD_NAME] = "file2.txt" }

      local sort1 = factory(entry1)
      local sort2 = factory(entry2)

      -- Without natural order: file10 < file2 (lexicographic)
      assert.is_true(sort1 < sort2)
    end)
  end)
end)
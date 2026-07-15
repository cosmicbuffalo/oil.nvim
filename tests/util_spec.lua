local util = require("oil.util")
describe("util", function()
  it("url_escape", function()
    local cases = {
      { "foobar", "foobar" },
      { "foo bar", "foo%20bar" },
      { "/foo/bar", "%2Ffoo%2Fbar" },
    }
    for _, case in ipairs(cases) do
      local input, expected = unpack(case)
      local output = util.url_escape(input)
      assert.equals(expected, output)
    end
  end)

  it("url_unescape", function()
    local cases = {
      { "foobar", "foobar" },
      { "foo%20bar", "foo bar" },
      { "%2Ffoo%2Fbar", "/foo/bar" },
      { "foo%%bar", "foo%%bar" },
    }
    for _, case in ipairs(cases) do
      local input, expected = unpack(case)
      local output = util.url_unescape(input)
      assert.equals(expected, output)
    end
  end)

  it("renders a custom column gap without widening the internal ID separator", function()
    local lines, highlights = util.render_table(
      { { "/001", { "x", "TestHighlight" }, "name" } },
      { 4, 1, 4 },
      nil,
      3,
      1
    )

    assert.same({ "/001 x   name" }, lines)
    assert.same({ { "TestHighlight", 0, 5, 6 } }, highlights)
  end)
end)

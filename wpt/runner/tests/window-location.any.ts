export const tests = [
  {
    name: "window.location updates URL parts",
    run({ assert, createWindow }) {
      const window = createWindow();
      window.location.href = "http://example.test/path";
      window.location.search = "?q=zig";
      window.location.hash = "#state";

      assert.equal(window.location.hostname, "example.test");
      assert.equal(window.location.search, "?q=zig");
      assert.equal(window.location.hash, "#state");
      window.close();
    }
  }
];

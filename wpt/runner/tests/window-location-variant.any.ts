export const tests = [
  {
    name: "variant is reflected in window location search",
    run({ assert, createWindow }) {
      const window = createWindow();
      assert.equal(window.location.search, "?mode=variant");
      window.close();
    }
  }
];

export const tests = [
  {
    name: "single manifest variant sets location search",
    run({ assert, createWindow }) {
      const window = createWindow();
      assert.equal(window.location.search, "?single");
      window.close();
    }
  }
];

export const tests = [
  {
    name: "createElement lowercases tag names",
    run({ assert, createWindow }) {
      const window = createWindow();
      const { document } = window;
      const element = document.createElement("DiV");
      assert.equal(element.nodeName, "DIV");
      window.close();
    }
  }
];

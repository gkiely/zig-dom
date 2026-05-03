export const tests = [
  {
    name: "appendChild attaches nodes in order",
    run({ assert, createWindow }) {
      const window = createWindow();
      const { document } = window;
      const parent = document.createElement("div");
      const first = document.createElement("span");
      const second = document.createElement("span");
      parent.appendChild(first);
      parent.appendChild(second);

      assert.equal(parent.firstChild, first);
      assert.equal(first.nextSibling, second);
      window.close();
    }
  }
];

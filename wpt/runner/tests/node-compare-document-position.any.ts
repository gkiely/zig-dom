export const tests = [
  {
    name: "compareDocumentPosition reports sibling order",
    run({ assert, createWindow }) {
      const window = createWindow();
      const { document, Node } = window;

      const parent = document.createElement("div");
      const first = document.createElement("span");
      const second = document.createElement("span");
      parent.appendChild(first);
      parent.appendChild(second);

      const relation = first.compareDocumentPosition(second);
      assert.ok((relation & Node.DOCUMENT_POSITION_FOLLOWING) !== 0, "second should follow first");

      window.close();
    }
  }
];

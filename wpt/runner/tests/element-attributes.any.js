export const tests = [
  {
    name: "setAttribute/getAttribute round-trip",
    run({ assert, createWindow }) {
      const window = createWindow();
      const { document } = window;
      const element = document.createElement("button");
      element.setAttribute("data-id", "123");
      assert.equal(element.getAttribute("data-id"), "123");
      element.removeAttribute("data-id");
      assert.equal(element.getAttribute("data-id"), null);
      window.close();
    }
  }
];

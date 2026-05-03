export const tests = [
  {
    name: "dataset reflects data-* attributes",
    run({ assert, createWindow }) {
      const window = createWindow();
      const element = window.document.createElement("div");

      element.dataset.userId = "42";
      assert.equal(element.getAttribute("data-user-id"), "42");

      element.setAttribute("data-display-name", "Ada");
      assert.equal(element.dataset.displayName, "Ada");

      delete element.dataset.userId;
      assert.equal(element.getAttribute("data-user-id"), null);
      window.close();
    }
  }
];

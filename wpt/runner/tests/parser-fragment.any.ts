export const tests = [
  {
    name: "innerHTML decodes entities and keeps comments",
    run({ assert, createWindow }) {
      const window = createWindow();
      const { document } = window;
      const host = document.createElement("div");
      host.innerHTML = "<p title=\"A &amp; B\">Hello &lt;world&gt;</p><!--note-->";

      const paragraph = host.querySelector("p");
      assert.ok(paragraph);
      assert.equal(paragraph?.getAttribute("title"), "A & B");
      assert.equal(paragraph?.textContent, "Hello <world>");
      assert.equal(host.childNodes.length, 2);
      window.close();
    }
  }
];

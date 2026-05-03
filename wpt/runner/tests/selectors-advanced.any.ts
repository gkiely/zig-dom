export const tests = [
  {
    name: "child/grouped/attribute selector support",
    run({ assert, createWindow }) {
      const window = createWindow();
      const { document } = window;
      document.body.innerHTML = `
        <main>
          <section id="scope">
            <h1>Title</h1>
            <p class="lead" data-kind="alpha-beta">Lead</p>
            <p class="copy" data-kind="beta">Copy</p>
          </section>
        </main>
      `;

      assert.equal(document.querySelectorAll("section > p").length, 2);
      assert.equal(document.querySelectorAll("h1 + p").length, 1);
      assert.equal(document.querySelectorAll("#scope, .copy").length, 2);
      assert.equal(document.querySelectorAll("[data-kind|='alpha']").length, 1);
      window.close();
    }
  }
];

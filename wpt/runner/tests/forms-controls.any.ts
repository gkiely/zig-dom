export const tests = [
  {
    name: "form reset uses default values",
    run({ assert, createWindow }) {
      const window = createWindow();
      const { document } = window;
      const form = document.createElement("form");
      form.innerHTML = `
        <input id="name" value="Grace" />
        <textarea value="Initial note"></textarea>
        <select>
          <option value="a">A</option>
          <option value="b" selected>B</option>
        </select>
      `;
      document.body.appendChild(form);

      const input = form.querySelector("input");
      const textarea = form.querySelector("textarea");
      const select = form.querySelector("select");
      if (!input || !textarea || !select) {
        throw new Error("missing controls");
      }

      input.value = "Updated";
      textarea.value = "Changed";
      select.value = "a";
      form.reset();

      assert.equal(input.value, "Grace");
      assert.equal(textarea.value, "Initial note");
      assert.equal(select.value, "b");
      window.close();
    }
  }
];

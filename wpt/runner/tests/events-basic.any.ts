export const tests = [
  {
    name: "once option and composedPath basics",
    run({ assert, createWindow }) {
      const window = createWindow();
      const { document } = window;
      const host = document.createElement("section");
      const button = document.createElement("button");
      host.appendChild(button);
      document.body.appendChild(host);

      let onceCalls = 0;
      button.addEventListener("click", () => {
        onceCalls += 1;
      }, { once: true });

      const event = new window.MouseEvent("click", { bubbles: true, composed: true });
      button.dispatchEvent(event);
      button.dispatchEvent(new window.MouseEvent("click", { bubbles: true, composed: true }));

      assert.equal(onceCalls, 1);
      assert.ok(event.composedPath().includes(host));
      window.close();
    }
  }
];

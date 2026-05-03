export const tests = [
  {
    name: "custom element upgrade and shadow root shape",
    async run({ assert, createWindow }) {
      const window = createWindow();
      const { document } = window;

      const before = document.createElement("wpt-box");
      document.body.appendChild(before);

      class WptBox extends window.HTMLElement {
        static observedAttributes = ["data-state"];
      }

      window.customElements.define("wpt-box", WptBox);
      await window.customElements.whenDefined("wpt-box");

      assert.ok(before instanceof WptBox);

      const host = document.createElement("div");
      const root = host.attachShadow({ mode: "open" });
      assert.ok(root !== null);
      assert.equal(host.shadowRoot, root);
      window.close();
    }
  }
];

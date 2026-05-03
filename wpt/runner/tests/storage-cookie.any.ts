export const tests = [
  {
    name: "storage and cookie basics",
    run({ assert, createWindow }) {
      const window = createWindow();
      window.localStorage.setItem("token", "abc");
      assert.equal(window.localStorage.getItem("token"), "abc");

      window.document.cookie = "theme=light";
      assert.ok(window.document.cookie.includes("theme=light"));
      window.close();
    }
  }
];

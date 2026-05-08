import { afterEach, expect } from "bun:test";

if (process.env.ZIG_DOM_SKIP_TESTING_LIBRARY !== "1") {
  const { cleanup } = await import("@testing-library/react");

  afterEach(() => {
    cleanup();
    document.body.innerHTML = "";
    document.head.innerHTML = "";
    localStorage.clear();
    sessionStorage.clear();
  });
}

import { describe, expect, test } from "bun:test";

describe("storage and cookie compatibility", () => {
  test("localStorage and sessionStorage support key/value operations", () => {
    localStorage.clear();
    sessionStorage.clear();

    localStorage.setItem("token", "abc");
    localStorage.setItem("user", "ada");

    expect(localStorage.length).toBe(2);
    expect(localStorage.getItem("token")).toBe("abc");
    expect(localStorage.key(0)).not.toBeNull();

    localStorage.removeItem("token");
    expect(localStorage.getItem("token")).toBeNull();

    sessionStorage.setItem("draft", "1");
    expect(sessionStorage.getItem("draft")).toBe("1");

    sessionStorage.clear();
    expect(sessionStorage.length).toBe(0);
  });

  test("document.cookie stores simple name/value pairs", () => {
    document.cookie = "theme=light";
    document.cookie = "lang=en-US; Path=/";

    expect(document.cookie).toContain("theme=light");
    expect(document.cookie).toContain("lang=en-US");
  });

  test("storage and cookies can be cleared between tests", () => {
    localStorage.setItem("persist", "x");
    sessionStorage.setItem("draft", "1");
    document.cookie = "session=active";

    localStorage.clear();
    sessionStorage.clear();
    document.cookie = "session=; Max-Age=0";

    expect(localStorage.length).toBe(0);
    expect(sessionStorage.length).toBe(0);
    expect(document.cookie).toBe("");
  });
});

if (typeof document === "undefined") {
  throw new Error("native DOM setup requires running the test runner with --dom");
}

globalThis.location.href = "http://localhost:3000/";

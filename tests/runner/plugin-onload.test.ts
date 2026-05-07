import { plugin } from "bun";
import { expect, test } from "bun:test";

plugin({
  name: "replace-onload-target",
  setup(build) {
    build.onLoad({ filter: /onload-target\.tsx$/ }, async ({ path }) => {
      return {
        loader: "ts",
        contents: `export const hookValue: number = 77;\nexport const hookPath = ${JSON.stringify(path)};\n`
      };
    });
  }
});

test("plugin onLoad can replace module source before transform", async () => {
  const hooked = await import("./fixtures/plugin/onload-target.tsx");
  expect(hooked.hookValue).toBe(77);
  expect(hooked.hookPath.endsWith("onload-target.tsx")).toBe(true);
});

plugin({
  name: "replace-onload-json",
  setup(build) {
    build.onLoad({ filter: /onload-data\.json$/ }, () => {
      return {
        loader: "json",
        contents: JSON.stringify({ value: "hooked-json" })
      };
    });
  }
});

test("plugin onLoad can replace json module source", async () => {
  const hooked = await import("./fixtures/plugin/onload-data.json");
  expect(hooked.default.value).toBe("hooked-json");
});

plugin({
  name: "replace-onload-js-tree-shake",
  setup(build) {
    build.onLoad({ filter: /onload-js-tree-shake\.js$/ }, () => {
      return {
        loader: "js",
        contents: [
          "export const kept = 77;",
          "export const dropped = (() => { throw new Error('unrequested onLoad export executed'); })();"
        ].join("\n")
      };
    });
  }
});

test("plugin onLoad js keeps requested exports only", async () => {
  const hooked = await import("./fixtures/plugin/onload-js-tree-shake-consumer.ts");
  expect(hooked.result).toBe(77);
});

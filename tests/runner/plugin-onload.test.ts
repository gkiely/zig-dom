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

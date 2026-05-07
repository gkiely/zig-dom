import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import ts from "typescript";

type Entry = {
  file: string;
  loader: "ts" | "tsx" | "jsx" | "js";
  out: string;
};

type Loader = Entry["loader"];

function parseArgs() {
  let cacheDir = ".zig-dom-cache/transformed";
  const entries: Entry[] = [];

  for (let index = 2; index < process.argv.length; index += 1) {
    const token = process.argv[index];

    if (token === "--cache-dir") {
      const value = process.argv[index + 1];
      if (!value) {
        throw new Error("Missing value for --cache-dir");
      }
      cacheDir = value;
      index += 1;
      continue;
    }

    if (token === "--file") {
      const file = process.argv[index + 1];
      const loaderToken = process.argv[index + 2];
      const loaderValue = process.argv[index + 3];
      const outToken = process.argv[index + 4];
      const out = process.argv[index + 5];

      if (!file || loaderToken !== "--loader" || !loaderValue || outToken !== "--out" || !out) {
        throw new Error("Expected --file <path> --loader <ts|tsx|jsx|js> --out <path>");
      }

      if (loaderValue !== "ts" && loaderValue !== "tsx" && loaderValue !== "jsx" && loaderValue !== "js") {
        throw new Error(`Unsupported loader ${loaderValue}`);
      }

      entries.push({ file, loader: loaderValue as Loader, out });
      index += 5;
      continue;
    }

    throw new Error(`Unknown argument ${token}`);
  }

  return { cacheDir, entries };
}

const { cacheDir, entries } = parseArgs();
if (entries.length === 0) {
  process.exit(0);
}

mkdirSync(resolve(cacheDir), { recursive: true });
const transpilers: Record<Loader, Bun.Transpiler> = {
  js: new Bun.Transpiler({ loader: "js" }),
  ts: new Bun.Transpiler({ loader: "ts" }),
  jsx: new Bun.Transpiler({
    loader: "jsx",
    tsconfig: {
      compilerOptions: {
        jsx: "react",
        jsxFactory: "React.createElement",
        jsxFragmentFactory: "React.Fragment"
      }
    }
  }),
  tsx: new Bun.Transpiler({
    loader: "tsx",
    tsconfig: {
      compilerOptions: {
        jsx: "react",
        jsxFactory: "React.createElement",
        jsxFragmentFactory: "React.Fragment"
      }
    }
  })
};

for (const entry of entries) {
  const source = await Bun.file(resolve(entry.file)).text();
  const transformed = transpilers[entry.loader].transformSync(source);
  const commonJs = ts.transpileModule(transformed, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020,
      jsx: ts.JsxEmit.React,
      esModuleInterop: true,
      allowSyntheticDefaultImports: true
    }
  }).outputText;
  const outPath = resolve(entry.out);

  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, commonJs, "utf8");
}

console.log(`Transformed ${entries.length} file(s).`);

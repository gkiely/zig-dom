import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

type Entry = {
  file: string;
  loader: "ts" | "tsx" | "jsx" | "cjs";
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
        throw new Error("Expected --file <path> --loader <ts|tsx|jsx> --out <path>");
      }

      if (loaderValue !== "ts" && loaderValue !== "tsx" && loaderValue !== "jsx" && loaderValue !== "cjs") {
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

function addCommonJsNamedExports(source: string): string {
  const names = new Set<string>();
  for (const match of source.matchAll(/\bexports\.([A-Za-z_$][\w$]*)\b/g)) {
    const name = match[1];
    if (name !== "default" && name !== "__esModule") {
      names.add(name);
    }
  }

  for (const match of source.matchAll(/Object\.defineProperty\(\s*exports\s*,\s*["']([A-Za-z_$][\w$]*)["']/g)) {
    const name = match[1];
    if (name !== "default" && name !== "__esModule") {
      names.add(name);
    }
  }

  if (names.size === 0) {
    return source;
  }

  const defaultExport = source.match(/export default ([^;\n]+);?\s*$/);
  if (!defaultExport) {
    return source;
  }

  const defaultExpression = defaultExport[1];
  const replacement = [
    `const __zigCommonJsDefault = ${defaultExpression};`,
    `export default __zigCommonJsDefault && Object.prototype.hasOwnProperty.call(__zigCommonJsDefault, "default") ? __zigCommonJsDefault.default : __zigCommonJsDefault;`,
    ...Array.from(names)
      .sort()
      .map((name) => `export const ${name} = __zigCommonJsDefault.${name};`)
  ].join("\n");

  return source.slice(0, defaultExport.index) + replacement + "\n";
}

function normalizeCommonJsDefaultExport(source: string): string {
  if (source.includes("const __zigCommonJsDefault =")) {
    return source;
  }

  const defaultExport = source.match(/export default ([^;\n]+);?\s*$/);
  if (!defaultExport) {
    return source;
  }

  const defaultExpression = defaultExport[1];
  const replacement = [
    `const __zigCommonJsDefault = ${defaultExpression};`,
    `export default __zigCommonJsDefault && Object.prototype.hasOwnProperty.call(__zigCommonJsDefault, "default") ? __zigCommonJsDefault.default : __zigCommonJsDefault;`
  ].join("\n");

  return source.slice(0, defaultExport.index) + replacement + "\n";
}

function allowAssignedNamespaceImports(source: string): string {
  return source.replace(
    /^import \* as ([A-Za-z_$][\w$]*) from (["'][^"']+["']);$/gm,
    (statement, local: string, specifier: string) => {
      const assignment = new RegExp(`(^|[^\\w$])${local}\\s*=`, "m");
      if (!assignment.test(source)) {
        return statement;
      }

      const alias = `__zigCjsImport_${local}`;
      return `import * as ${alias} from ${specifier};\nvar ${local} = ${alias};`;
    }
  );
}

function ensureClassicReactImport(source: string): string {
  if (!source.includes("React.createElement") && !source.includes("React.Fragment")) {
    return source;
  }

  if (/\bimport\s+React\b/.test(source) || /\bimport\s+\*\s+as\s+React\b/.test(source)) {
    return source;
  }

  return `import React from "react";\n${source}`;
}

mkdirSync(resolve(cacheDir), { recursive: true });
const transpilers: Record<Loader, Bun.Transpiler> = {
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
  }),
  cjs: new Bun.Transpiler({ loader: "js" })
};

for (const entry of entries) {
  if (process.env.ZIG_DOM_TRANSFORM_DEBUG === "1") {
    console.error(`[zig-dom transform] ${entry.loader} ${entry.file} -> ${entry.out}`);
  }

  let normalized: string;
  if (entry.loader === "cjs") {
    const bundled = await Bun.build({
      entrypoints: [resolve(entry.file)],
      format: "esm",
      target: "bun",
      bundle: true,
      external: ["react", "react-dom", "react-dom/client", "react-dom/test-utils", "react/jsx-runtime", "react/jsx-dev-runtime"],
      write: false
    });

    if (!bundled.success || bundled.outputs.length === 0) {
      const firstLog = bundled.logs[0];
      throw new Error(firstLog ? firstLog.message : `Failed to transform CommonJS module ${entry.file}`);
    }

    normalized = (await bundled.outputs[0].text())
      .replaceAll("import.meta.env", "globalThis.__zigImportMetaEnv")
      .replaceAll("import.meta.require", "globalThis.__zigImportMetaRequire");
    normalized = allowAssignedNamespaceImports(normalized);
    normalized = addCommonJsNamedExports(normalized);
    normalized = normalizeCommonJsDefaultExport(normalized);
  } else {
    const source = await Bun.file(resolve(entry.file)).text();
    const transformed = transpilers[entry.loader].transformSync(source);
    normalized = transformed
      .replaceAll("import.meta.env", "globalThis.__zigImportMetaEnv")
      .replaceAll("import.meta.require", "globalThis.__zigImportMetaRequire");
    if (entry.loader === "tsx" || entry.loader === "jsx") {
      normalized = ensureClassicReactImport(normalized);
    }
  }
  const outPath = resolve(entry.out);

  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, normalized, "utf8");
}

console.log(`Transformed ${entries.length} file(s).`);

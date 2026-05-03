import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

type AnyWindow = {
  document: Document;
  close?: () => void;
  happyDOM?: {
    reset?: () => void;
    close?: () => void;
  };
  Node?: typeof Node;
  Element?: typeof Element;
  HTMLElement?: typeof HTMLElement;
  Document?: typeof Document;
  Event?: typeof Event;
  CustomEvent?: typeof CustomEvent;
  MouseEvent?: typeof MouseEvent;
  KeyboardEvent?: typeof KeyboardEvent;
  InputEvent?: typeof InputEvent;
};

type DomEnv = {
  window: AnyWindow;
  document: Document;
  reset: () => void;
  close: () => void;
};

type Adapter = {
  name: "zig-dom" | "happy-dom" | "jsdom";
  importMs: number;
  createEnv: () => Promise<DomEnv>;
};

type MetricRow = {
  metric: string;
  "zig-dom": number | null;
  "happy-dom": number | null;
  "jsdom": number | null;
};

const ELEMENT_COUNT = 10_000;
const RESET_COUNT = 500;
const COMMON_HTML = `
  <main class="layout" data-x="1">
    <header><button class="primary" data-x="save">Save</button></header>
    <section>
      <article class="card"><h2>Title</h2><p>Body</p></article>
      <article class="card"><h2>More</h2><p>Text</p></article>
    </section>
    <footer><input value="abc" /></footer>
  </main>
`;

function now(): number {
  return performance.now();
}

async function measureImport<T>(loader: () => Promise<T>): Promise<{ mod: T; ms: number }> {
  const start = now();
  const mod = await loader();
  return { mod, ms: now() - start };
}

async function measureMetric(metric: () => void | Promise<void>): Promise<number> {
  const start = now();
  await metric();
  return now() - start;
}

function resetByClearing(windowLike: AnyWindow): void {
  windowLike.document.head.replaceChildren();
  windowLike.document.body.replaceChildren();
}

async function loadAdapters(): Promise<Adapter[]> {
  const zigImport = await measureImport(() => import("../dist/index.js"));
  const happyImport = await measureImport(() => import("happy-dom"));
  // @ts-ignore Bun executes this script directly; jsdom is loaded dynamically at runtime.
  const jsdomImport = await measureImport(() => import("jsdom"));

  const zigMod = zigImport.mod as unknown as {
    Window: new (options?: { url?: string }) => AnyWindow;
  };

  const happyMod = happyImport.mod as unknown as {
    Window: new (options?: { url?: string }) => AnyWindow;
  };

  const jsdomMod = jsdomImport.mod as {
    JSDOM: new (html?: string, options?: { url?: string }) => {
      window: AnyWindow;
    };
  };

  return [
    {
      name: "zig-dom",
      importMs: zigImport.ms,
      async createEnv(): Promise<DomEnv> {
        const window = new zigMod.Window({ url: "http://localhost/" });
        return {
          window,
          document: window.document,
          reset: () => {
            if (window.happyDOM?.reset) {
              window.happyDOM.reset();
            } else {
              resetByClearing(window);
            }
          },
          close: () => {
            if (window.happyDOM?.close) {
              window.happyDOM.close();
            } else {
              window.close?.();
            }
          }
        };
      }
    },
    {
      name: "happy-dom",
      importMs: happyImport.ms,
      async createEnv(): Promise<DomEnv> {
        const window = new happyMod.Window({ url: "http://localhost/" });
        if (!(window as { SyntaxError?: unknown }).SyntaxError) {
          Object.defineProperty(window, "SyntaxError", {
            value: globalThis.SyntaxError,
            configurable: true,
            writable: true
          });
        }
        return {
          window,
          document: window.document,
          reset: () => {
            if (window.happyDOM?.reset) {
              window.happyDOM.reset();
            } else {
              resetByClearing(window);
            }
          },
          close: () => {
            if (window.happyDOM?.close) {
              window.happyDOM.close();
            } else {
              window.close?.();
            }
          }
        };
      }
    },
    {
      name: "jsdom",
      importMs: jsdomImport.ms,
      async createEnv(): Promise<DomEnv> {
        const dom = new jsdomMod.JSDOM("<!doctype html><html><head></head><body></body></html>", { url: "http://localhost/" });
        return {
          window: dom.window,
          document: dom.window.document,
          reset: () => {
            resetByClearing(dom.window);
          },
          close: () => {
            dom.window.close?.();
          }
        };
      }
    }
  ];
}

function buildSelectorFixture(document: Document): HTMLElement {
  const container = document.createElement("div");
  for (let i = 0; i < ELEMENT_COUNT; i += 1) {
    const child = document.createElement("div");
    child.className = "item";
    child.setAttribute("data-x", String(i));
    container.appendChild(child);
  }
  document.body.appendChild(container);
  return container;
}

async function measureReactRender(adapterName: string, env: DomEnv): Promise<number> {
  const React = await import("react");
  const ReactDOMClient = await import("react-dom/client");

  const previous = {
    window: globalThis.window,
    document: globalThis.document
  };

  const win = env.window;
  (globalThis as Record<string, unknown>).window = win;
  (globalThis as Record<string, unknown>).document = env.document;

  try {
    const container = env.document.createElement("div");
    env.document.body.appendChild(container);

    const root = ReactDOMClient.createRoot(container);
    const elapsed = await measureMetric(async () => {
      root.render(
        React.createElement("main", { "data-testid": "bench-root" }, `hello from ${adapterName}`)
      );
      await new Promise((resolve) => setTimeout(resolve, 0));
    });
    root.unmount();
    return elapsed;
  } finally {
    (globalThis as Record<string, unknown>).window = previous.window;
    (globalThis as Record<string, unknown>).document = previous.document;
  }
}

async function runForAdapter(adapter: Adapter): Promise<Record<string, number | null>> {
  const results: Record<string, number | null> = {
    import_time_ms: adapter.importMs
  };

  async function withEnv(metricName: string, action: (env: DomEnv) => Promise<number> | number): Promise<void> {
    const env = await adapter.createEnv();
    try {
      const ms = await action(env);
      results[metricName] = ms;
    } catch (error) {
      console.warn(`benchmark metric failed: adapter=${adapter.name} metric=${metricName} error=${error instanceof Error ? error.message : String(error)}`);
      results[metricName] = null;
    } finally {
      env.close();
    }
  }

  await withEnv("global_register_ms", async (_env) => {
    if (adapter.name === "jsdom") {
      return NaN;
    }

    if (adapter.name === "zig-dom") {
      const mod = (await import("../dist/index.js")) as {
        GlobalRegistrator: {
          register: (opts?: { forceNewWindow?: boolean; url?: string }) => unknown;
          unregister: () => void;
        };
      };
      return measureMetric(() => {
        mod.GlobalRegistrator.register({ forceNewWindow: true, url: "http://localhost/" });
        mod.GlobalRegistrator.unregister();
      });
    }

    const mod = (await import("happy-dom")) as {
      GlobalRegistrator?: {
        register: () => void;
        unregister?: () => void;
      };
    };

    if (!mod.GlobalRegistrator) {
      return NaN;
    }

    return measureMetric(() => {
      mod.GlobalRegistrator?.register();
      mod.GlobalRegistrator?.unregister?.();
    });
  });

  await withEnv("reset_500x_ms", async (env) => {
    return measureMetric(() => {
      for (let i = 0; i < RESET_COUNT; i += 1) {
        env.reset();
      }
    });
  });

  await withEnv("create_10k_elements_ms", async (env) => {
    return measureMetric(() => {
      for (let i = 0; i < ELEMENT_COUNT; i += 1) {
        env.document.createElement("div");
      }
    });
  });

  await withEnv("append_10k_children_ms", async (env) => {
    const children: Element[] = [];
    for (let i = 0; i < ELEMENT_COUNT; i += 1) {
      children.push(env.document.createElement("div"));
    }

    return measureMetric(() => {
      const parent = env.document.createElement("section");
      for (let i = 0; i < ELEMENT_COUNT; i += 1) {
        const child = children[i];
        if (child) {
          parent.appendChild(child);
        }
      }
      env.document.body.appendChild(parent);
    });
  });

  await withEnv("set_get_10k_attributes_ms", async (env) => {
    const elements: Element[] = [];
    for (let i = 0; i < ELEMENT_COUNT; i += 1) {
      const element = env.document.createElement("div");
      elements.push(element);
    }

    return measureMetric(() => {
      for (let i = 0; i < ELEMENT_COUNT; i += 1) {
        elements[i]?.setAttribute("data-x", String(i));
      }
      for (let i = 0; i < ELEMENT_COUNT; i += 1) {
        elements[i]?.getAttribute("data-x");
      }
    });
  });

  await withEnv("query_all_div_10k_ms", async (env) => {
    buildSelectorFixture(env.document);
    return measureMetric(() => {
      env.document.querySelectorAll("div");
    });
  });

  await withEnv("query_all_class_10k_ms", async (env) => {
    buildSelectorFixture(env.document);
    return measureMetric(() => {
      env.document.querySelectorAll(".item");
    });
  });

  await withEnv("query_all_attr_10k_ms", async (env) => {
    buildSelectorFixture(env.document);
    return measureMetric(() => {
      env.document.querySelectorAll("[data-x]");
    });
  });

  await withEnv("inner_html_parse_ms", async (env) => {
    const container = env.document.createElement("div");
    env.document.body.appendChild(container);
    return measureMetric(() => {
      container.innerHTML = COMMON_HTML.repeat(100);
    });
  });

  await withEnv("outer_html_serialize_ms", async (env) => {
    const container = env.document.createElement("div");
    container.innerHTML = COMMON_HTML.repeat(100);
    env.document.body.appendChild(container);
    return measureMetric(() => {
      void container.outerHTML;
    });
  });

  if (adapter.name === "zig-dom") {
    results.react_render_smoke_ms = await measureMetric(() => {
      const run = spawnSync("bun", ["test", "tests/integration/react/render.test.tsx"], {
        stdio: "ignore"
      });
      if (run.status !== 0) {
        throw new Error(`react smoke exited with code ${run.status ?? -1}`);
      }
    });
  } else {
    results.react_render_smoke_ms = null;
  }

  for (const [key, value] of Object.entries(results)) {
    if (typeof value === "number" && Number.isNaN(value)) {
      results[key] = null;
    }
  }

  return results;
}

function toFixed(value: number | null): string {
  return value == null ? "n/a" : value.toFixed(2);
}

function buildRows(data: Record<string, Record<string, number | null>>): MetricRow[] {
  const metrics = new Set<string>();
  for (const adapterData of Object.values(data)) {
    for (const metric of Object.keys(adapterData)) {
      metrics.add(metric);
    }
  }

  return [...metrics].sort().map((metric) => ({
    metric,
    "zig-dom": data["zig-dom"]?.[metric] ?? null,
    "happy-dom": data["happy-dom"]?.[metric] ?? null,
    "jsdom": data["jsdom"]?.[metric] ?? null
  }));
}

function printTable(rows: MetricRow[]): void {
  console.log("metric,zig-dom_ms,happy-dom_ms,jsdom_ms");
  for (const row of rows) {
    console.log(`${row.metric},${toFixed(row["zig-dom"])},${toFixed(row["happy-dom"])},${toFixed(row["jsdom"])}`);
  }
}

function writeBenchmarkArtifact(rows: MetricRow[]): void {
  const target = resolve(process.cwd(), "docs", "benchmarks", "latest.json");
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, JSON.stringify({
    generatedAt: new Date().toISOString(),
    rows
  }, null, 2));
}

const adapters = await loadAdapters();
const resultByAdapter: Record<string, Record<string, number | null>> = {};
for (const adapter of adapters) {
  resultByAdapter[adapter.name] = await runForAdapter(adapter);
}

const rows = buildRows(resultByAdapter);
printTable(rows);
writeBenchmarkArtifact(rows);
console.log("wrote docs/benchmarks/latest.json");

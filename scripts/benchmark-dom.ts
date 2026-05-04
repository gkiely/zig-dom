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
const SMALL_ELEMENT_COUNT = 1_000;
const RESET_COUNT = 500;
const APPEND_SAMPLE_COUNT = 7;
const CREATE_SAMPLE_COUNT = 7;
const WORKFLOW_SAMPLE_COUNT = 5;
const QUERY_SAMPLE_COUNT = 7;
const REACT_SAMPLE_COUNT = 7;
const REACT_ROW_COUNT = 1_000;
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

async function medianSample(samples: () => Promise<number> | number, count: number): Promise<number> {
  const values: number[] = [];
  for (let index = 0; index < count; index += 1) {
    values.push(await samples());
  }
  values.sort((left, right) => left - right);
  return values[Math.floor(values.length / 2)] ?? 0;
}

async function withGlobalDOM<T>(env: DomEnv, action: () => Promise<T> | T): Promise<T> {
  const keys = [
    "window",
    "document",
    "Node",
    "Element",
    "HTMLElement",
    "Document",
    "Event",
    "CustomEvent",
    "MouseEvent",
    "KeyboardEvent",
    "InputEvent",
    "navigator"
  ] as const;
  const previous = new Map<string, unknown>();
  const globalScope = globalThis as Record<string, unknown>;

  for (const key of keys) {
    previous.set(key, globalScope[key]);
  }

  globalScope.window = env.window;
  globalScope.document = env.document;
  globalScope.Node = env.window.Node;
  globalScope.Element = env.window.Element;
  globalScope.HTMLElement = env.window.HTMLElement;
  globalScope.Document = env.window.Document;
  globalScope.Event = env.window.Event;
  globalScope.CustomEvent = env.window.CustomEvent;
  globalScope.MouseEvent = env.window.MouseEvent;
  globalScope.KeyboardEvent = env.window.KeyboardEvent;
  globalScope.InputEvent = env.window.InputEvent;
  globalScope.navigator = { userAgent: "zig-dom-benchmark" };

  try {
    return await action();
  } finally {
    for (const key of keys) {
      const value = previous.get(key);
      if (value === undefined) {
        delete globalScope[key];
      } else {
        globalScope[key] = value;
      }
    }
  }
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
  return withGlobalDOM(env, async () => {
    const React = await import("react");
    const { flushSync } = await import("react-dom");
    const ReactDOMClient = await import("react-dom/client");
    const container = env.document.createElement("div");
    env.document.body.appendChild(container);

    const root = ReactDOMClient.createRoot(container);
    const elapsed = await measureMetric(async () => {
      flushSync(() => {
        root.render(
          React.createElement("main", { "data-testid": "bench-root" }, `hello from ${adapterName}`)
        );
      });
    });
    root.unmount();
    return elapsed;
  });
}

async function measureReactRows(env: DomEnv): Promise<number> {
  return withGlobalDOM(env, async () => {
    const React = await import("react");
    const { flushSync } = await import("react-dom");
    const ReactDOMClient = await import("react-dom/client");

    return medianSample(() => {
      const container = env.document.createElement("div");
      env.document.body.appendChild(container);

      const root = ReactDOMClient.createRoot(container);
      const elapsed = measureMetric(async () => {
        flushSync(() => {
          root.render(
            React.createElement("ul", null,
              Array.from({ length: REACT_ROW_COUNT }, (_, index) =>
                React.createElement("li", { key: index, "data-row": index }, `row ${index}`)
              )
            )
          );
        });
      });
      root.unmount();
      return elapsed;
    }, REACT_SAMPLE_COUNT);
  });
}

async function measureReactRowsUpdate(env: DomEnv): Promise<number> {
  return withGlobalDOM(env, async () => {
    const React = await import("react");
    const { flushSync } = await import("react-dom");
    const ReactDOMClient = await import("react-dom/client");
    const renderRows = (offset: number) =>
      React.createElement("ul", null,
        Array.from({ length: REACT_ROW_COUNT }, (_, index) =>
          React.createElement("li", { key: index, "data-row": index }, `row ${index + offset}`)
        )
      );

    return medianSample(() => {
      const container = env.document.createElement("div");
      env.document.body.appendChild(container);

      const root = ReactDOMClient.createRoot(container);
      flushSync(() => {
        root.render(renderRows(0));
      });

      const elapsed = measureMetric(async () => {
        flushSync(() => {
          root.render(renderRows(1));
        });
      });
      root.unmount();
      return elapsed;
    }, REACT_SAMPLE_COUNT);
  });
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
    return medianSample(() => measureMetric(() => {
      for (let i = 0; i < ELEMENT_COUNT; i += 1) {
        env.document.createElement("div");
      }
    }), CREATE_SAMPLE_COUNT);
  });

  await withEnv("append_10k_children_ms", async (env) => {
    return medianSample(() => {
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
    }, APPEND_SAMPLE_COUNT);
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

  await withEnv("fragment_append_10k_children_ms", async (env) => {
    return medianSample(() => {
      const fragment = env.document.createDocumentFragment();
      for (let i = 0; i < ELEMENT_COUNT; i += 1) {
        fragment.appendChild(env.document.createElement("div"));
      }

      return measureMetric(() => {
        env.document.body.appendChild(fragment);
      });
    }, APPEND_SAMPLE_COUNT);
  });

  await withEnv("replace_children_1k_ms", async (env) => {
    return medianSample(() => {
      const container = env.document.createElement("div");
      env.document.body.appendChild(container);
      const nodes: Element[] = [];
      for (let i = 0; i < SMALL_ELEMENT_COUNT; i += 1) {
        const child = env.document.createElement("span");
        child.textContent = String(i);
        nodes.push(child);
      }

      return measureMetric(() => {
        container.replaceChildren(...nodes);
      });
    }, QUERY_SAMPLE_COUNT);
  });

  await withEnv("mixed_dom_workflow_1k_ms", async (env) => {
    return medianSample(() => measureMetric(() => {
      const container = env.document.createElement("section");
      for (let i = 0; i < SMALL_ELEMENT_COUNT; i += 1) {
        const child = env.document.createElement(i % 5 === 0 ? "button" : "div");
        child.className = i % 2 === 0 ? "even item" : "odd item";
        child.setAttribute("data-index", String(i));
        child.textContent = `item ${i}`;
        container.appendChild(child);
      }
      env.document.body.appendChild(container);
      void container.querySelectorAll(".item");
      void container.querySelectorAll("[data-index]");
      container.remove();
    }), WORKFLOW_SAMPLE_COUNT);
  });

  await withEnv("custom_elements_create_append_1k_ms", async (env) => {
    if (!env.window.customElements || !env.window.HTMLElement) {
      return NaN;
    }
    const name = `x-bench-${adapter.name}`;
    if (!env.window.customElements.get(name)) {
      env.window.customElements.define(name, class extends env.window.HTMLElement {});
    }

    return medianSample(() => measureMetric(() => {
      const container = env.document.createElement("div");
      for (let i = 0; i < SMALL_ELEMENT_COUNT; i += 1) {
        container.appendChild(env.document.createElement(name));
      }
      env.document.body.appendChild(container);
    }), WORKFLOW_SAMPLE_COUNT);
  });

  await withEnv("mutation_observer_append_1k_ms", async (env) => {
    const MutationObserverCtor = (env.window as AnyWindow & { MutationObserver?: typeof MutationObserver }).MutationObserver;
    if (!MutationObserverCtor) {
      return NaN;
    }

    return medianSample(() => {
      const container = env.document.createElement("div");
      env.document.body.appendChild(container);
      const observer = new MutationObserverCtor(() => {});
      observer.observe(container, { childList: true });

      return measureMetric(() => {
        for (let i = 0; i < SMALL_ELEMENT_COUNT; i += 1) {
          container.appendChild(env.document.createElement("div"));
        }
        observer.disconnect();
      });
    }, WORKFLOW_SAMPLE_COUNT);
  });

  await withEnv("query_all_div_10k_ms", async (env) => {
    return medianSample(() => {
      env.reset();
      buildSelectorFixture(env.document);
      return measureMetric(() => {
      env.document.querySelectorAll("div");
      });
    }, QUERY_SAMPLE_COUNT);
  });

  await withEnv("query_all_class_10k_ms", async (env) => {
    return medianSample(() => {
      env.reset();
      buildSelectorFixture(env.document);
      return measureMetric(() => {
        env.document.querySelectorAll(".item");
      });
    }, QUERY_SAMPLE_COUNT);
  });

  await withEnv("query_all_attr_10k_ms", async (env) => {
    return medianSample(() => {
      env.reset();
      buildSelectorFixture(env.document);
      return measureMetric(() => {
        env.document.querySelectorAll("[data-x]");
      });
    }, QUERY_SAMPLE_COUNT);
  });

  await withEnv("element_query_all_class_10k_ms", async (env) => {
    return medianSample(() => {
      env.reset();
      const container = buildSelectorFixture(env.document);
      return measureMetric(() => {
        container.querySelectorAll(".item");
      });
    }, QUERY_SAMPLE_COUNT);
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

  await withEnv("react_render_1k_rows_ms", async (env) => {
    return measureReactRows(env);
  });

  await withEnv("react_update_1k_rows_ms", async (env) => {
    return measureReactRowsUpdate(env);
  });

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

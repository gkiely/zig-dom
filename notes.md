    The repeated body exposed the large issue clearly: Bun does 30 menu open/close cycles in ~658ms, zig-dom takes ~3328ms with zero pending jobs. That is not module loading or async cleanup. I’m taking a
  native sample of that long body now.

  ---
• Sampled and found a real larger issue.

  It is not primarily native DOM. In the repeated Tree menu body:

  - Native DOM work was tiny: selectors ~1.4ms, create/append/setAttr ~1.6ms, event dispatch callbacks ~25ms.
  - The CPU sample was QuickJS interpreter/property allocation/GC/regexp.
  - The pathological hotspot was our built-in expect(menu).not.toBeInTheDocument() path.

  Concrete timing for 30 menu open/close cycles:

  - Bun: ~666ms total; not.toBeInTheDocument ~0.28ms.
  - zig-dom before experiment: ~3365ms total; not.toBeInTheDocument ~1260ms.
  - Direct DOM checks were cheap in zig-dom: getRootNode ~0.1ms, deep clone ~27ms, so the matcher plumbing/timer drain was the issue.

  The root cause: src/host/assertions.zig eagerly calls drainPendingJobsAndTimers() for inverted toBeInTheDocument. That runs MUI/React timer work inside the assertion. I tried a targeted drain that stops
  once the element is detached; it cut that matcher hotspot to ~388ms, but full Tree.test.tsx did not improve meaningfully because the deferred work moved into later pending-job cleanup. Per your instruction,
  I added that failed experiment to AGENTS.md.

  I also tested letting expect.extend override built-ins, since youneedawiki’s Bun setup has a lightweight custom matcher. That made the file faster, but broke two matcher expectations (toHaveStyle,
  toBeVisible), so I reverted it.

  Verification:

  - Restored ../youneedawiki-zig-dom/src/components/Tree/Tree.test.tsx; no downstream diff remains.
  - Rebuilt zig-dom successfully with gtimeout 120s zig build -Doptimize=ReleaseFast --summary none.


  ---
  Our file scanner is really slow:
bun run test:perf ../youneedawiki-zig-dom/src/elements/Buttons/

real	0m0.290s
user	0m0.269s
sys	0m0.020s

Compared to: 
bun run test:perf ../youneedawiki-zig-dom/src/elements/Buttons/Edit.test.tsx
real	0m0.152s
user	0m0.139s
sys	0m0.012s



---
The corrected Bun run confirms your CPU observation: Bun used 2.60s CPU over 1.53s wall, while zig-dom used 3.41s CPU over 3.58s wall. The bigger problem is also visible: zig-dom retired about twice the instructions (38.3B vs 19.0B), so parallelism alone would hide but not fix all of it.

Perf prompt: confirm it's not due to event/query/render with logging, and add temp logging to the test or library files to find the specific line that's causing it.

Perf investigation
---
• Now it’s confirmed: not query, not event construction, and not native dispatchEvent. The multiplier is almost entirely after dispatchEvent, inside React Testing Library’s act() flush: Bun rtl-eventWrapper-act≈410ms, zig-dom ≈1492ms, while dispatch totals are both under ~10ms per event type. Next I’m instrumenting React’s act path to find which flush line is expanding.
• The next layer is React’s own act() implementation. I’m adding temporary counters around the callback and flushActQueue(queue) so we know whether the time is before React flushes, inside the queue flush, or in wrapper bookkeeping.
• That narrows it to React’s flushActQueue(queue): Bun flushes 489 callbacks in ~430ms, zig-dom flushes 490 callbacks in ~1482ms. The specific React line is var continuation = callback(false) inside node_modules/react/cjs/react.development.js; I’m now tracing which React DOM callback body is responsible, since the callback count is the same but each callback is much slower in QuickJS.
• The slow callback is now specific: processRootScheduleInMicrotask() dominates the act flush, not passive effects. Bun spends ~401ms there for 243 calls; zig-dom spends ~1478ms for the same 243 calls. I’m instrumenting that function’s internal branches next.
• Inside processRootScheduleInMicrotask, the slow line is now flushSyncWorkAcrossRoots_impl(syncTransitionLanes, false): Bun ~400ms, zig-dom ~1486ms. Scheduling bookkeeping is basically zero. I’m drilling into that React DOM flush next.
• flushSyncWorkAcrossRoots is almost entirely performSyncWorkOnRoot(root, lanes), not lane selection. I’m splitting that into flushPendingEffects() versus performWorkOnRoot().
• performSyncWorkOnRoot is almost entirely performWorkOnRoot(root, lanes, true). That’s actual React render/commit work, not queries or event dispatch. I’m splitting performWorkOnRoot into render and commit phases.
• The largest specific phase is React render, not DOM commit: Bun renderRootSync≈214ms, zig-dom ≈1265ms; commit is closer (219ms vs 293ms). I’m splitting the render loop into beginWork versus completeUnitOfWork.
• That confirms the render multiplier is specifically React beginWork: Bun ~191ms, zig-dom ~1184ms for ~30k fibers. Commit is much smaller. I’m checking which fiber tags dominate beginWork, because that tells us whether it’s function component calls, host DOM reconciliation, context, memo, etc.
• At this point the logging has found the path precisely: the extra time is the React render beginWork loop. It is concentrated in function component fibers (tag 0, ~548ms zig vs ~74ms Bun) and forwardRef fibers (tag 11, ~517ms zig vs ~98ms Bun), with the same general fiber volume. I’m going to remove the temporary downstream/library instrumentation before making any repo changes, then use the finding against zig-dom itself.
• I saved the temporary logging diff to /tmp/tree-temp-logging.diff for reference. I’m reverting only the temporary instrumentation I just added in the downstream test and installed library files.
• Increased test time to: [1419.00ms] for zig-dom but lead to 37 Tree tests failed in both zig-dom and Bun:
```
const { cleanup, configure } = await import('@testing-library/react');
configure({ eventWrapper: (cb) => cb() });
```
• dispatch never crossed 5ms, query/assert steps are sub-ms to a few ms, and the repeated slow entries are React’s flushSyncWorkAcrossRoots_impl -> performSyncWorkOnRoot inside RTL act().

•  The strongest new signal is that QuickJS object-clone patterns are dramatically slower in this workload (Object.assign/object spread microbench is ~6–7x slower than Bun), which matches the beginWork hotspot profile and points to prop-object churn during render rather than DOM/query/event overhead.

• I found a concrete hotspot: raw button.click() is ~25x slower in zig-dom (280ms vs 11ms for 10k clicks). I’m now tracing the DOM event dispatch/click path in Zig to remove that overhead.

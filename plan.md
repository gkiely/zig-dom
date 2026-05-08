Agent handoff: remove supported upstream DOM WPT skips

## Goal

Remove supported `status: "skip"` entries from `wpt/expected/upstream-dom.json`, one test at a time.

Do not remove skips for:

- `subtest: "__timeout__"`
- legacy coverage, including legacy API-dependent tests
- WebKit-prefixed coverage

## Loop

1. Pick one supported skipped entry from `wpt/expected/upstream-dom.json`.
   This can be a whole-file skip (`subtest: "__all__"`) or a named subtest
   skip. Leave unrelated skips untouched.

2. Find the matching index in `wpt/manifest/upstream-dom.json`.

3. Temporarily unskip only that entry and reproduce it with:

   ```sh
   bun run test:wpt -- --start-entry <index> --entry-count 1 --batch-size 1 --timeout-ms 30000
   ```

4. Fix the DOM/runtime behavior for that one WPT.
   Prefer spec-compatible behavior and happy-dom parity over test-specific
   hacks. Keep changes near the relevant DOM implementation area.

5. Verify the same one-entry WPT command again.

6. Run the perf guard:

   ```sh
   bun run build:perf
   ```

7. If WPT passes and there is no measurable perf regression, delete the
   selected skip from `wpt/expected/upstream-dom.json`.

8. Repeat for the next supported skip.

Stop if the fix stops being small, requires broad DOM architecture work, or
causes a `build:perf` regression that is not obvious.

Keep WPT iteration native-only. Do not reintroduce `js/wrappers`.

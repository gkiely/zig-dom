Agent handoff: remove supported upstream DOM WPT skips

## Goal

Remove as many supported `status: "skip"` entries from
`wpt/expected/upstream-dom.json` as possible, one test at a time. Keep looping;
do not stop after the first successful fix.

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

4. If the one-entry run times out, restore the selected skip as a timeout
   expectation instead of fixing it:

   ```json
   {
     "file": "<same file>",
     "subtest": "__timeout__",
     "reason": "30s timeout budget in skip-removal loop"
   }
   ```

   Then continue with the next supported skip.

5. Fix the DOM/runtime behavior for that one WPT.
   Prefer spec-compatible behavior and happy-dom parity over test-specific
   hacks. Keep changes near the relevant DOM implementation area.

6. Verify the same one-entry WPT command again.

7. Run the perf guard:

   ```sh
   bun run test:perf:gate --timeout=.15 ../youneedawiki/src/elements/Buttons/Edit.test.tsx
   ```

8. If WPT passes and the warm perf run stays within the 150ms gate, delete the
   selected skip from `wpt/expected/upstream-dom.json`.

9. Repeat for the next supported skip.

If one skip is blocked because the fix stops being small, requires broad DOM
architecture work, or causes a non-obvious `test:perf:gate` regression, restore
that skip, note the blocker, and continue with the next supported skip.

Stop only when there are no supported skips left, the remaining skips are all
blocked/unsupported, or the working tree has grown too risky to keep extending
without review.

Keep WPT iteration native-only. Do not reintroduce `js/wrappers`.

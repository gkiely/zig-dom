V1 [x]
- zig-dom
- JS classes, bun:ffi for operations

V2 []
- DOM and test runner that is faster than bun for all tests using QuickJS
- Yuku
- Native DOM and test selector
- Parallel test workers
- Multi-threading: 
https://github.com/bellard/quickjs/issues/362
https://github.com/quickjs-ng/quickjs/commit/5ce2957e

V3 []
- Use crate: https://github.com/zig-whatwg/crane
- If quickJS is not fast enough evaluate JSC: https://zoo.js.org

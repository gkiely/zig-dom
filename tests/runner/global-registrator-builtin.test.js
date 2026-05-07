import { expect, test } from "bun:test";

import defaultRegistratorModule, {
  GlobalRegistrator,
} from "zig-dom/global-registrator";
import defaultRegistrarModule, {
  GlobalRegistrator as AliasedGlobalRegistrator,
} from "zig-dom/global-registrar";

test("runner global registrator bridge keeps native DOM identity", async () => {
  const nativeWindow = globalThis.window;
  const nativeDocument = globalThis.document;
  const originalHref = globalThis.location ? globalThis.location.href : null;
  const url = "https://example.test/runner-global-registrator/path?query=1#hash";

  expect(defaultRegistratorModule.GlobalRegistrator).toBe(GlobalRegistrator);
  expect(defaultRegistrarModule.GlobalRegistrator).toBe(AliasedGlobalRegistrator);

  const returnedWindow = GlobalRegistrator.register({ url });

  expect(returnedWindow).toBe(nativeWindow);
  expect(globalThis.window).toBe(returnedWindow);
  expect(globalThis.document).toBe(nativeDocument);
  expect(returnedWindow.document).toBe(nativeDocument);

  expect(globalThis.location.href).toBe(url);
  expect(globalThis.location.pathname).toBe("/runner-global-registrator/path");

  expect(typeof returnedWindow.happyDOM.reset).toBe("function");
  expect(typeof returnedWindow.happyDOM.setURL).toBe("function");
  expect(typeof returnedWindow.happyDOM.whenAsyncComplete).toBe("function");

  document.body.innerHTML = "<div id=\"fill\">filled</div>";
  returnedWindow.happyDOM.reset();
  expect(document.body.innerHTML).toBe("");

  document.body.innerHTML = "<div id=\"fill\">filled-again</div>";
  GlobalRegistrator.reset();
  expect(document.body.innerHTML).toBe("");

  await returnedWindow.happyDOM.whenAsyncComplete();

  AliasedGlobalRegistrator.unregister();
  expect(AliasedGlobalRegistrator.currentWindow()).toBe(nativeWindow);

  if (originalHref) {
    returnedWindow.happyDOM.setURL(originalHref);
  }
});

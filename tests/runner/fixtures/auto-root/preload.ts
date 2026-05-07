const setupGlobal = globalThis as typeof globalThis & {
  __zigAutoRootPreload?: boolean;
};

setupGlobal.__zigAutoRootPreload = true;

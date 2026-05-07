import { setupToken } from "./shared.ts";

const setupGlobal = globalThis as typeof globalThis & {
	__zigSetupToken?: string;
};

setupGlobal.__zigSetupToken = setupToken;

import { nestedValue } from "./nested/index";

export const nestedNumber = 7;

export function getMessage() {
  return `hello-${nestedValue}`;
}

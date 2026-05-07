"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.nestedNumber = void 0;
exports.getMessage = getMessage;
const index_1 = require("./nested/index");
exports.nestedNumber = 7;
function getMessage() {
    return `hello-${index_1.nestedValue}`;
}

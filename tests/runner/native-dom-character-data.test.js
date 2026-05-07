import { expect, test } from "bun:test";

test("native DOM text/comment character data operations", () => {
  const text = document.createTextNode("hello world");
  text.appendData("!");
  expect(text.data).toBe("hello world!");

  text.deleteData(5, 1);
  expect(text.data).toBe("helloworld!");

  text.insertData(5, " ");
  expect(text.data).toBe("hello world!");

  text.replaceData(6, 5, "zig");
  expect(text.data).toBe("hello zig!");
  expect(text.substringData(0, 5)).toBe("hello");

  const host = document.createElement("div");
  host.appendChild(text);

  const tail = text.splitText(6);
  expect(text.data).toBe("hello ");
  expect(tail.data).toBe("zig!");
  expect(host.childNodes.length).toBe(2);
  expect(host.childNodes.item(1)).toBe(tail);

  const comment = document.createComment("note");
  expect(comment.data).toBe("note");

  comment.insertData(4, "-x");
  expect(comment.data).toBe("note-x");
  comment.replaceData(0, 4, "memo");
  expect(comment.textContent).toBe("memo-x");
});

import { expect, spyOn, test } from "bun:test";
import { fireEvent } from "@testing-library/dom";

test("FormData(form) reads updated input values", () => {
  document.body.innerHTML = '<form><input name="input" value="Untitled document" /></form>';
  const form = document.querySelector("form");
  const input = document.querySelector("input");

  input.value = "Test Page";

  const data = new FormData(form);
  expect(data.get("input")).toBe("Test Page");
});

test("FormData(form) reads fireEvent.change updates", () => {
  document.body.innerHTML = '<form><input name="input" value="Untitled document" /></form>';
  const form = document.querySelector("form");
  const input = document.querySelector("input");

  fireEvent.change(input, { target: { value: "Test Page" } });

  const data = new FormData(form);
  expect(data.get("input")).toBe("Test Page");
});

test("toHaveBeenNthCalledWith works with stacked spyOn + objectContaining", () => {
  const api = {
    request(args) {
      return args;
    }
  };

  const first = spyOn(api, "request");
  api.request({ path: "https://www.googleapis.com/drive/v3/files", method: "GET" });

  const second = spyOn(api, "request");
  api.request({
    path: "https://www.googleapis.com/drive/v3/files",
    method: "POST",
    body: {
      name: "Test Page",
      parents: ["1"]
    }
  });

  expect(first).toBe(second);
  expect(second).toHaveBeenNthCalledWith(
    2,
    expect.objectContaining({
      path: "https://www.googleapis.com/drive/v3/files",
      method: "POST",
      body: {
        name: "Test Page",
        parents: ["1"]
      }
    })
  );
});

test("fireEvent.click on submit button triggers form submit default action", () => {
  document.body.innerHTML =
    '<form><input name="input" value="Untitled document" /><button type="submit">Create</button></form>';

  const form = document.querySelector("form");
  const input = document.querySelector("input");
  const button = document.querySelector("button");

  const api = { request: (_args) => ({}) };
  const first = spyOn(api, "request");

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(form);
    api.request({
      path: "https://www.googleapis.com/drive/v3/files",
      method: "POST",
      body: {
        name: data.get("input")
      }
    });
  });

  fireEvent.change(input, { target: { value: "Test Page" } });
  fireEvent.click(button);

  const second = spyOn(api, "request");
  expect(first).toBe(second);
  expect(second).toHaveBeenNthCalledWith(
    1,
    expect.objectContaining({
      path: "https://www.googleapis.com/drive/v3/files",
      method: "POST",
      body: {
        name: "Test Page"
      }
    })
  );
});

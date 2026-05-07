import { expect, test } from "bun:test";

test("native DOM form/common element constructors and properties", () => {
  const form = document.createElement("form");
  const input = document.createElement("input");
  const button = document.createElement("button");
  const select = document.createElement("select");
  const option = document.createElement("option");
  const textarea = document.createElement("textarea");
  const label = document.createElement("label");

  option.value = "one";
  option.textContent = "One";
  select.appendChild(option);

  form.appendChild(label);
  form.appendChild(input);
  form.appendChild(button);
  form.appendChild(select);
  form.appendChild(textarea);
  document.body.appendChild(form);

  expect(form instanceof HTMLFormElement).toBe(true);
  expect(input instanceof HTMLInputElement).toBe(true);
  expect(button instanceof HTMLButtonElement).toBe(true);
  expect(select instanceof HTMLSelectElement).toBe(true);
  expect(option instanceof HTMLOptionElement).toBe(true);
  expect(textarea instanceof HTMLTextAreaElement).toBe(true);
  expect(label instanceof HTMLLabelElement).toBe(true);

  input.name = "email";
  input.type = "email";
  input.value = "ada@example.com";
  input.checked = true;
  input.disabled = true;

  expect(input.name).toBe("email");
  expect(input.type).toBe("email");
  expect(input.value).toBe("ada@example.com");
  expect(input.checked).toBe(true);
  expect(input.disabled).toBe(true);
  expect(input.form).toBe(form);

  expect(form.elements.length).toBe(6);
  expect(select.options.length).toBe(1);
});

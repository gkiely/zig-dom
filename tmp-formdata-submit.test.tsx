import { expect, test } from 'bun:test';

test('FormData can be constructed from submitted form target', () => {
  const form = document.createElement('form');
  const input = document.createElement('input');
  const button = document.createElement('button');

  input.name = 'input';
  input.value = 'Test Page';
  button.type = 'submit';

  form.appendChild(input);
  form.appendChild(button);
  document.body.appendChild(form);

  let value = '';
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const data = new FormData(form);
    const maybeValue = data.get('input');
    value = typeof maybeValue === 'string' ? maybeValue : '';
  });

  button.click();

  expect(value).toBe('Test Page');
});

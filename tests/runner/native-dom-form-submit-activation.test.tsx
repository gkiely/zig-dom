import { expect, test } from 'bun:test';

test('submit and reset button activation dispatches bubbling form events', () => {
  const form = document.createElement('form');
  const submit = document.createElement('button');
  const reset = document.createElement('button');
  const input = document.createElement('input');

  submit.type = 'submit';
  reset.type = 'reset';
  input.name = 'title';
  input.value = 'before';

  form.appendChild(input);
  form.appendChild(submit);
  form.appendChild(reset);
  document.body.appendChild(form);

  let submitTarget = 0;
  let submitBubbled = 0;
  let resetTarget = 0;
  let resetBubbled = 0;
  let submitterTag = '';

  form.addEventListener('submit', (event) => {
    submitTarget += 1;
    const submitter = (event as Event & { submitter?: Element | null }).submitter;
    if (submitter instanceof Element) submitterTag = submitter.tagName;
    event.preventDefault();
  });
  form.addEventListener('reset', (event) => {
    resetTarget += 1;
    event.preventDefault();
  });
  document.addEventListener('submit', () => {
    submitBubbled += 1;
  });
  document.addEventListener('reset', () => {
    resetBubbled += 1;
  });

  submit.click();
  reset.click();

  expect(submitTarget).toBe(1);
  expect(submitBubbled).toBe(1);
  expect(submitterTag).toBe('BUTTON');
  expect(resetTarget).toBe(1);
  expect(resetBubbled).toBe(1);
});

test('requestSubmit dispatches submit with the provided submitter', () => {
  const form = document.createElement('form');
  const submit = document.createElement('button');
  submit.type = 'submit';
  submit.name = 'commit';
  submit.value = 'save';
  form.appendChild(submit);
  document.body.appendChild(form);

  let submitCount = 0;
  let submitterName = '';

  form.addEventListener('submit', (event) => {
    submitCount += 1;
    const submitter = (event as Event & { submitter?: Element | null }).submitter;
    if (submitter instanceof HTMLButtonElement) submitterName = submitter.name;
    event.preventDefault();
  });

  form.requestSubmit(submit);

  expect(submitCount).toBe(1);
  expect(submitterName).toBe('commit');
});

import { test } from 'bun:test';

test('element.matches combinator diagnostics', () => {
  document.body.innerHTML = `<section><h1>T</h1><p class="lead">Lead</p><p class="body">Body</p></section>`;
  const pLead = document.querySelector('p.lead');
  if (!pLead) throw new Error('missing p');
  const descendant = pLead.matches('section p');
  const child = pLead.matches('section > p');
  throw new Error(JSON.stringify({ descendant, child }));
});

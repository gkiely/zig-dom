test('debug children collection', () => {
  const container = document.createElement('div');
  container.innerHTML = '<img><img id="foo"><img id="foo"><img name="bar">';
  document.body.appendChild(container);
  let child = document.createElementNS('', 'img');
  child.setAttribute('id', 'baz');
  container.appendChild(child);
  child = document.createElementNS('', 'img');
  child.setAttribute('name', 'qux');
  container.appendChild(child);
  const list = container.children;
  const result = [];
  for (const p in list) {
    if (list.hasOwnProperty(p)) result.push(p);
  }
  throw new Error(JSON.stringify({
    forin: result,
    own: Object.getOwnPropertyNames(list),
    foo: [list.foo === list.item(1), list.namedItem('foo') === list.item(1)],
    baz: ['baz' in list, list.baz === list.item(4)],
    qux: ['qux' in list, list.namedItem('qux')]
  }));
});

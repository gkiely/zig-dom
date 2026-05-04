import { describe, expect, test } from "bun:test";

describe("selector engine", () => {
  test("supports child, adjacent, sibling, and grouped selectors", () => {
    document.body.innerHTML = `
      <main id="root">
        <section class="group">
          <h1 id="title">Title</h1>
          <p class="lead">Lead</p>
          <p class="body">Body</p>
        </section>
      </main>
    `;

    expect(document.querySelectorAll("section > p").length).toBe(2);
    expect(document.querySelector("h1 + p")?.className).toBe("lead");
    expect(document.querySelectorAll("h1 ~ p").length).toBe(2);
    expect(document.querySelectorAll("#title, .body").length).toBe(2);
    expect(document.querySelectorAll("[class~='lead'], section > h1").length).toBe(2);
  });

  test("supports attribute operators and pseudo-classes", () => {
    document.body.innerHTML = `
      <ul id="items">
        <li data-kind="alpha">a</li>
        <li data-kind="alpha-beta" data-tags="chip primary">b</li>
        <li data-kind="beta" data-tags="chip">c</li>
      </ul>
    `;

    expect(document.querySelectorAll("[data-kind^='alpha']").length).toBe(2);
    expect(document.querySelectorAll("[data-kind$='beta']").length).toBe(2);
    expect(document.querySelectorAll("[data-kind*='pha']").length).toBe(2);
    expect(document.querySelectorAll("[data-kind|='alpha']").length).toBe(2);
    expect(document.querySelectorAll("[data-tags~='primary']").length).toBe(1);
    expect(document.querySelectorAll("*[data-tags~='chip'], [data-kind='beta']").length).toBe(2);

    expect(document.querySelector("#items > li:first-child")?.textContent).toBe("a");
    expect(document.querySelector("#items > li:last-child")?.textContent).toBe("c");
    expect(document.querySelector("#items > li:nth-child(2)")?.textContent).toBe("b");
    expect(document.querySelectorAll("#items > li:not(:first-child)").length).toBe(2);
  });

  test("element scoped querySelectorAll does not include the scope root", () => {
    document.body.innerHTML = `<section id="scope" class="match"><div class="match"></div></section>`;
    const scope = document.getElementById("scope");
    expect(scope?.querySelectorAll(".match").length).toBe(1);
  });
});

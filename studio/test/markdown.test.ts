import { renderToStaticMarkup } from "react-dom/server";
import { createElement } from "react";
import { describe, expect, it } from "vitest";
import { Markdown } from "../src/brain/markdown";

const html = (text: string) => renderToStaticMarkup(createElement(Markdown, { text }));

describe("Markdown", () => {
  it("renders headings, lists, quotes and code", () => {
    const out = html("# Title\n\nA para\nthat wraps.\n\n- one\n- two\n\n> _source: x_\n\n```\ncode\n```\n");
    expect(out).toContain('<h2 class="md-h">Title</h2>');
    expect(out).toContain('<p class="md-p">A para that wraps.</p>');
    expect(out).toContain("<li>one</li><li>two</li>");
    expect(out).toContain('<blockquote class="md-quote">_source: x_</blockquote>');
    expect(out).toContain('<pre class="md-code">code</pre>');
  });
  it("never passes markup through", () => {
    const out = html("<script>alert(1)</script>\n\n# <img src=x onerror=alert(1)>");
    expect(out).not.toContain("<script>");
    expect(out).not.toContain("<img");
    expect(out).toContain("&lt;script&gt;");
  });
});

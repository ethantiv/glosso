import Foundation

/// The reader window's page: a self-contained HTML template (kept as a Swift
/// constant — a second bundle resource plus load plumbing would be pure overhead)
/// and the small helpers the controller uses to talk to it.
///
/// Template JS contract:
/// - `glossoSetArticle(title, byline, html)` inserts the extracted article, tags
///   translatable top-level blocks with `data-glosso-id` + `.glosso-pending`
///   (the dimmed original text is its own skeleton) and returns the block list
///   as a JSON string for Swift to loop over.
/// - `glossoApply(id, html)` swaps in one block's translation.
/// - `glossoStatus(msg)` shows progress/errors in the bottom bar ('' hides it).
enum ReaderTemplate {
    /// One tagged block of the rendered article, as returned by glossoSetArticle.
    /// `translate == false` marks blocks kept verbatim (figures, code, empty).
    struct Block: Decodable {
        let id: Int
        let html: String
        let translate: Bool
    }

    /// Gemma occasionally wraps the fragment in Markdown fences despite the
    /// prompt; peel them so raw ``` never lands in the article.
    static func stripFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        trimmed = trimmed.replacingOccurrences(
            of: #"\A```[a-zA-Z]*\s*"#, with: "", options: .regularExpression)
        trimmed = trimmed.replacingOccurrences(
            of: #"\s*```\z"#, with: "", options: .regularExpression)
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a JS call with every argument passed as a JSON string literal —
    /// never raw interpolation, so quotes/newlines/script tags in article text
    /// can't break out of the call.
    static func call(_ function: String, _ arguments: String...) -> String {
        let encoded = arguments.map { argument -> String in
            let data = try? JSONEncoder().encode(argument)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        }
        return "\(function)(\(encoded.joined(separator: ", ")))"
    }

    static let html = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      body { font-family: -apple-system, system-ui, sans-serif; font-size: 17px;
             line-height: 1.6; max-width: 42em; margin: 0 auto;
             padding: 2em 1.5em 4em; overflow-wrap: break-word; }
      h1#glosso-title { font-size: 1.9em; line-height: 1.25; margin-bottom: .3em; }
      #glosso-byline { color: color-mix(in srgb, CanvasText 55%, Canvas);
                       margin-bottom: 2em; }
      img, video { max-width: 100%; height: auto; border-radius: 4px; }
      figure { margin: 1.5em 0; }
      figcaption { font-size: .85em; opacity: .7; }
      blockquote { border-left: 3px solid color-mix(in srgb, CanvasText 25%, Canvas);
                   margin-left: 0; padding-left: 1em; opacity: .9; }
      pre { overflow-x: auto; background: color-mix(in srgb, CanvasText 7%, Canvas);
            padding: 1em; border-radius: 6px; font-size: .85em; }
      code { font-family: ui-monospace, monospace; }
      a { color: #4F5BD8; }
      .glosso-pending { opacity: .45; }
      #glosso-status { position: fixed; bottom: 0; left: 0; right: 0;
                       padding: .5em 1em; font-size: .85em; background: Canvas;
                       border-top: 1px solid color-mix(in srgb, CanvasText 15%, Canvas);
                       display: none; }
    </style>
    </head>
    <body>
    <h1 id="glosso-title"></h1>
    <div id="glosso-byline"></div>
    <div id="glosso-content"></div>
    <div id="glosso-status"></div>
    <script>
    function glossoSetArticle(title, byline, html) {
      document.title = title;
      document.getElementById('glosso-title').textContent = title;
      document.getElementById('glosso-byline').textContent = byline || '';
      const content = document.getElementById('glosso-content');
      content.innerHTML = html;
      const SKIP = ['FIGURE', 'IMG', 'HR', 'TABLE', 'PRE', 'VIDEO', 'IFRAME'];
      const blocks = [];
      (function walk(node) {
        for (const el of Array.from(node.children)) {
          // Readability wraps everything in div.page containers — recurse through
          // structural wrappers, treat everything else (whole ul/ol/blockquote
          // included) as one block.
          if (['DIV', 'SECTION', 'ARTICLE', 'MAIN'].includes(el.tagName)) { walk(el); continue; }
          const id = blocks.length;
          el.dataset.glossoId = id;
          const text = el.textContent.trim();
          // ponytail: 4000-char cap — an oversized block would hit the model's
          // token ceiling and truncate; it stays untranslated instead. Split in
          // two if it ever bites.
          const translate = !SKIP.includes(el.tagName) && text.length > 0 && text.length < 4000;
          if (translate) el.classList.add('glosso-pending');
          blocks.push({id: id, html: el.innerHTML, translate: translate});
        }
      })(content);
      return JSON.stringify(blocks);
    }
    function glossoApply(id, html) {
      const el = document.querySelector('[data-glosso-id="' + id + '"]');
      if (!el) { return; }
      // The model occasionally drops an <img> while translating a mixed block;
      // re-append any image the replacement lost so translation never costs
      // pictures (position within the block may shift — acceptable).
      const had = Array.from(el.querySelectorAll('img'));
      el.innerHTML = html;
      const have = new Set(Array.from(el.querySelectorAll('img')).map(img => img.getAttribute('src')));
      for (const img of had) {
        if (!have.has(img.getAttribute('src'))) { el.appendChild(img); }
      }
      el.classList.remove('glosso-pending');
    }
    function glossoStatus(msg) {
      const status = document.getElementById('glosso-status');
      status.textContent = msg;
      status.style.display = msg ? 'block' : 'none';
    }
    </script>
    </body>
    </html>
    """
}

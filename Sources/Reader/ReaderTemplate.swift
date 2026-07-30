import Foundation

enum ReaderTemplate {
    struct Block: Decodable {
        let id: Int
        let html: String
        let translate: Bool
    }

    /// Kept under GeminiClient.outputTokenLimit so a batch's numPredict can never hit the clamp and truncate — at the
    /// largest batch any catalog asks for (20) that is min(4640, 8192), structurally unreachable. It is also the second
    /// throttle on every batch: at the measured corpus mean of 192 bytes per block it fits ~20 blocks, so it stops
    /// binding right where the largest batch size sits and quietly shrinks batches on above-average articles instead.
    private static let batchByteBudget = 4000

    /// Greedy packing under both a count and a byte cap. An oversized block gets its own batch rather than being split.
    ///
    /// The count ramps 1, 2, 4, … up to `maxCount` instead of starting there: the first request carries a single block,
    /// so something paints while the big batches are still being packed. Measured on Gemma, that moves the first
    /// paragraph from ~26s to ~7s. The ramp is a geometric prefix, so it costs a fixed handful of extra requests once
    /// per article rather than a share of it, and at `maxCount` 1 it degenerates to today's per-block behaviour.
    static func batches(_ blocks: [Block], maxCount: Int) -> [[Block]] {
        var packed: [[Block]] = []
        var current: [Block] = []
        var bytes = 0
        var cap = 1
        for block in blocks {
            let size = block.html.utf8.count
            if !current.isEmpty, current.count >= cap || bytes + size > batchByteBudget {
                packed.append(current)
                cap = min(cap * 2, maxCount)
                current = []
                bytes = 0
            }
            current.append(block)
            bytes += size
        }
        if !current.isEmpty { packed.append(current) }
        return packed
    }

    /// Peels what a model wraps its answer in: a markdown fence and an echoed prompt wrapper, in either nesting order.
    static func unwrap(_ text: String) -> String {
        var current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<3 {
            let before = current
            current = peelWrapper(peelFence(current))
            if current == before { break }
        }
        return current
    }

    private static func peelFence(_ text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        var peeled = text.replacingOccurrences(
            of: #"\A```[a-zA-Z]*\s*"#, with: "", options: .regularExpression)
        peeled = peeled.replacingOccurrences(
            of: #"\s*```\z"#, with: "", options: .regularExpression)
        return peeled.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Both ends anchored and the same tag required on both, so a legitimate inline tag can never be mistaken for a wrapper.
    private static func peelWrapper(_ text: String) -> String {
        let peeled = text.replacingOccurrences(
            of: #"(?is)\A<\s*(block|text|article)\s*>\s*(.*?)\s*<\s*/\s*\1\s*>\z"#,
            with: "$2", options: .regularExpression)
        return peeled == text ? text : peeled.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Chat answers arrive with markdown emphasis whatever the prompt asks for; render the few marks models actually use.
    static func markdown(_ text: String) -> String {
        // Escaping first is what makes this safe: afterwards the only tags in the string are the ones we add ourselves.
        var html = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        html = html.replacingOccurrences(
            of: #"`([^`\n]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        // Before the emphasis rules: a list marker would otherwise go looking for a closing asterisk.
        html = html.replacingOccurrences(
            of: #"(?m)^[ \t]*[-*+][ \t]+"#, with: "• ", options: .regularExpression)
        html = html.replacingOccurrences(
            of: #"(?m)^[ \t]*#{1,6}[ \t]+(.+)$"#, with: "<strong>$1</strong>", options: .regularExpression)
        // Bold before italic, or `**x**` falls apart into two empty emphases. Both marks must hug their
        // text, as in CommonMark — otherwise "3 * 4 = 12 * 2" would italicise the middle of the sentence.
        html = html.replacingOccurrences(
            of: #"\*\*([^\s*]([^*\n]*[^\s*])?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(
            of: #"\*([^\s*]([^*\n]*[^\s*])?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        return html
    }

    static func call(_ function: String, _ arguments: String...) -> String {
        let encoded = arguments.map { argument -> String in
            let data = try? JSONEncoder().encode(argument)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        }
        return "\(function)(\(encoded.joined(separator: ", ")))"
    }

    static var html: String { """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark;
              --accent: light-dark(#4F5BD8, #98A2F8);
              --accent-ink: light-dark(#4350C4, #A7B0FA);
              --ink-soft: light-dark(#605D6C, #A29FB0);
              --hairline: light-dark(#E6E4EA, #37343E);
              --ui-font: "Avenir Next", -apple-system, system-ui, sans-serif; }
      #glosso-progress { position: fixed; top: 0; left: 0; right: 0; height: 6px;
                         background: color-mix(in srgb, var(--accent) 22%, Canvas);
                         z-index: 20; }
      #glosso-progress div { height: 100%; background: var(--accent);
                             transform-origin: left; transform: scaleX(1); }
      body { font-family: "Athelas", "Palatino", ui-serif, Georgia, serif;
             font-size: 18px; line-height: 1.72; max-width: 41em; margin: 0 auto;
             padding: 2.2em 1.5em 4em; overflow-wrap: break-word; }
      h1#glosso-title { font-size: 2.5em; line-height: 1.18; margin: 0 auto .4em;
                        font-weight: 400; text-align: center; letter-spacing: 0; }
      #glosso-fleuron { display: none; text-align: center; color: var(--accent);
                        font-size: 1.1em; letter-spacing: .6em; margin: .4em 0; }
      #glosso-byline { text-align: center; font-variant-caps: small-caps;
                       letter-spacing: .12em; font-size: .95em;
                       color: var(--ink-soft); margin-bottom: 2.6em; }
      #glosso-summary { border-top: 1px solid CanvasText;
                        border-bottom: 1px solid CanvasText;
                        padding: 1.1em .2em; margin: 0 0 2.8em;
                        font-size: .92em; line-height: 1.6; display: none; }
      #glosso-summary::before { content: "\(loc("Od tłumacza · TL;DR", "Translator's note · TL;DR"))";
                                display: block; font-family: var(--ui-font);
                                font-size: .68rem; font-weight: 600; letter-spacing: .2em;
                                text-transform: uppercase; color: var(--accent-ink);
                                margin-bottom: .5em; }
      #glosso-content figcaption { font-family: var(--ui-font); text-align: center; }
      #glosso-pills { position: fixed; top: .9em; right: .9em; z-index: 10;
                      display: none; gap: .5em; font-family: var(--ui-font); }
      #glosso-pills { transition: right .25s ease-in-out; }
      body.glosso-chat-open #glosso-pills { right: calc(320px + .9em); }
      .glosso-pill { display: flex; align-items: center; gap: .4em;
                     font-family: var(--ui-font); font-size: .74rem; font-weight: 600;
                     padding: .4em .8em;
                     border-radius: 999px; cursor: pointer;
                     color: var(--accent-ink);
                     background: color-mix(in srgb, var(--accent) 9%, Canvas);
                     border: 1px solid color-mix(in srgb, var(--accent) 26%, Canvas); }
      .glosso-pill:hover { background: color-mix(in srgb, var(--accent) 16%, Canvas); }
      .glosso-pill svg { width: 1.05em; height: 1.05em; }
      #glosso-seg { display: flex; padding: 0; border-radius: 999px; overflow: hidden;
                    cursor: pointer; color: var(--accent-ink);
                    background: color-mix(in srgb, var(--accent) 9%, Canvas);
                    border: 1px solid color-mix(in srgb, var(--accent) 26%, Canvas); }
      #glosso-seg button { font-family: var(--ui-font); font-size: .74rem; font-weight: 600;
                           border: 0; padding: .4em .9em; cursor: pointer;
                           background: transparent; color: inherit; letter-spacing: .04em; }
      #glosso-seg button[aria-pressed="true"] { background: var(--accent);
                                                color: light-dark(#fff, #14163B); }
      img, video { max-width: 100%; height: auto; }
      /* Embedded players carry fixed width/height attributes and would overflow
         the column; cap them and let aspect-ratio keep the video shape.
         ponytail: 16:9 covers YouTube/Vimeo; a rare non-video iframe gets that
         shape too — revisit if one ever matters. */
      iframe, embed, object { max-width: 100%; border-radius: 4px; }
      iframe { width: 100%; aspect-ratio: 16 / 9; height: auto; }
      figure { margin: 2.2em 0; }
      figcaption { font-size: .78em; opacity: .8; margin-top: .7em; }
      blockquote { margin: 1.8em 0; padding-left: 1.5em; text-align: left;
                   border-left: 3px solid color-mix(in srgb, CanvasText 65%, Canvas);
                   font-size: 1.08em; font-style: italic; line-height: 1.55; }
      pre { overflow-x: auto; background: color-mix(in srgb, CanvasText 7%, Canvas);
            padding: 1em; border-radius: 6px; font-size: .8em; text-align: left; }
      code { font-family: ui-monospace, monospace; }
      a { color: var(--accent-ink); }
      .glosso-pending { opacity: .45; }
      .glosso-dual { cursor: pointer; }
      .glosso-interlinear { margin: .5em 0 .2em 1.6em; font-style: italic;
                            font-size: .9em; line-height: 1.6; cursor: default;
                            color: color-mix(in srgb, CanvasText 74%, Canvas); }
      .glosso-interlinear-lang { font-family: var(--ui-font); font-style: normal;
                                 font-size: .64rem; font-weight: 700; letter-spacing: .14em;
                                 text-transform: uppercase; color: var(--accent-ink);
                                 display: block; margin-bottom: .3em; }
      #glosso-chat-panel { position: fixed; top: 6px; right: 0; bottom: 0; width: 320px;
                           display: flex; flex-direction: column; gap: .9em;
                           transform: translateX(100%); visibility: hidden;
                           transition: transform .25s ease-in-out, visibility 0s .25s;
                           background: color-mix(in srgb, var(--accent) 3%, Canvas);
                           z-index: 5; box-sizing: border-box;
                           border-left: 1px solid var(--hairline);
                           padding: 1.1em 1.2em 1em; font-size: .92em; }
      body.glosso-chat-open #glosso-chat-panel { transform: none; visibility: visible;
                                                 transition: transform .25s ease-in-out,
                                                             visibility 0s; }
      body.glosso-chat-open { margin-right: 340px; }
      .glosso-chat-label { font-family: var(--ui-font); font-size: .68rem;
                           font-weight: 600; letter-spacing: .2em;
                           text-transform: uppercase; text-align: center;
                           color: var(--accent-ink); }
      #glosso-chat-messages { flex: 1; overflow-y: auto; padding-right: .6em;
                              display: flex; flex-direction: column;
                              counter-reset: glosso-footnote; }
      .glosso-chat-q { align-self: flex-end; max-width: 88%; margin-bottom: .8em;
                       font-family: var(--ui-font); font-size: .88em; line-height: 1.5;
                       background: var(--accent);
                       color: light-dark(#fff, #14163B);
                       border-radius: 11px; border-bottom-right-radius: 4px;
                       padding: .45em .7em; }
      .glosso-chat-a { white-space: pre-wrap; margin-bottom: 1.2em;
                       border-top: 1px solid var(--hairline); padding-top: .7em;
                       font-size: .92em; line-height: 1.6; }
      .glosso-chat-a::before { content: counter(glosso-footnote);
                               counter-increment: glosso-footnote;
                               font-size: .72em; vertical-align: .45em;
                               margin-right: .45em; color: var(--accent-ink);
                               font-weight: 600; }
      .glosso-chat-error { color: color-mix(in srgb, red 70%, CanvasText); }
      #glosso-suggest-label { font-family: var(--ui-font); font-size: .62rem;
                              font-weight: 600; letter-spacing: .16em;
                              text-transform: uppercase; margin-bottom: -.45em;
                              color: var(--ink-soft);
                              display: none; }
      #glosso-chat-suggestions { display: flex; flex-direction: column; }
      .glosso-chat-started #glosso-suggest-label { display: none !important; }
      .glosso-chat-started #glosso-chat-suggestions { flex-direction: row;
                                                      overflow-x: auto; flex: none;
                                                      gap: 1em; padding-bottom: .7em; }
      .glosso-chat-started .glosso-chip { flex: none; max-width: 15em;
                                          white-space: nowrap; overflow: hidden;
                                          text-overflow: ellipsis; border-top: 0; }
      .glosso-chip { font-family: inherit; font-style: italic; font-size: .88em;
                     line-height: 1.45; text-align: left; cursor: pointer;
                     color: CanvasText; background: transparent; border: 0;
                     border-top: 1px solid var(--hairline);
                     padding: .55em .1em .55em 1.2em; position: relative; }
      .glosso-chip::before { content: "»"; position: absolute; left: 0;
                             font-style: normal; color: var(--accent-ink); }
      .glosso-chip:hover { color: var(--accent-ink); }
      .glosso-chip:disabled, #glosso-chat-form button:disabled { opacity: .4; cursor: default; }
      #glosso-chat-form { display: flex; gap: .5em; align-items: center; }
      #glosso-chat-input { flex: 1; font-family: inherit; font-size: .9em;
                           padding: .45em .65em; border-radius: 10px;
                           border: 1px solid var(--hairline);
                           background: Canvas; color: CanvasText;
                           resize: none; max-height: 8em; overflow-y: auto; line-height: 1.4; }
      .glosso-spin { display: inline-block; width: 1em; height: 1em; border-radius: 50%;
                     border: 2px solid color-mix(in srgb, CanvasText 25%, Canvas);
                     border-top-color: transparent; animation: glosso-spin 1s linear infinite; }
      @keyframes glosso-spin { to { transform: rotate(360deg); } }
      #glosso-footer { position: fixed; bottom: 0; left: 0; right: 0;
                       font-family: var(--ui-font); font-size: .76rem;
                       letter-spacing: .06em;
                       padding: .55em 1em; background: Canvas; color: var(--ink-soft);
                       border-top: 1px solid var(--hairline);
                       display: none; gap: 1em; align-items: baseline;
                       transition: right .25s ease-in-out; }
      body.glosso-chat-open #glosso-footer { right: 340px; }
      /* min-width: 0 or the status' longest word wins the row and pushes the model name out of the bar. */
      #glosso-status { flex: 1; min-width: 0; text-align: left;
                       white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      #glosso-engine { white-space: nowrap; }
    </style>
    </head>
    <body>
    <div id="glosso-progress"><div></div></div>
    <div id="glosso-pills">
      <button id="glosso-refresh" class="glosso-pill" type="button" title="\(loc("Przetłumacz ponownie", "Translate again"))">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M21 12a9 9 0 1 1-2.6-6.4"/>
          <path d="M21 3v6h-6"/>
        </svg>
      </button>
      <div id="glosso-seg" role="group" title="\(loc("Przełącz oryginał / tłumaczenie", "Toggle original / translation"))">
        <button id="glosso-seg-translated" type="button" aria-pressed="true">\(loc("Tłumaczenie", "Translation"))</button>
        <button id="glosso-seg-original" type="button" aria-pressed="false">\(loc("Oryginał", "Original"))</button>
      </div>
      <button id="glosso-chat" class="glosso-pill" type="button" title="\(loc("Zapytaj artykuł", "Ask the article"))">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M21 11.5a8.4 8.4 0 0 1-8.5 8.3 8.9 8.9 0 0 1-3.2-.6L3 21l1.8-5.1a8.1 8.1 0 0 1-1.3-4.4A8.4 8.4 0 0 1 12 3.2a8.4 8.4 0 0 1 9 8.3Z"/>
        </svg>
      </button>
    </div>
    <h1 id="glosso-title"></h1>
    <div id="glosso-fleuron">&#10086;</div>
    <div id="glosso-byline"></div>
    <div id="glosso-summary"></div>
    <div id="glosso-content"></div>
    <div id="glosso-chat-panel">
      <div class="glosso-chat-label">\(loc("Zapytaj artykuł", "Ask the article"))</div>
      <div id="glosso-chat-messages"></div>
      <div id="glosso-suggest-label">\(loc("Podpowiedzi", "Suggestions"))</div>
      <div id="glosso-chat-suggestions"></div>
      <form id="glosso-chat-form">
        <textarea id="glosso-chat-input" rows="1" autocomplete="off" placeholder="\(loc("Zadaj pytanie…", "Ask a question…"))"></textarea>
        <button type="submit" class="glosso-pill">\(loc("Wyślij", "Send"))</button>
      </form>
    </div>
    <div id="glosso-footer">
      <span id="glosso-status"></span>
      <span id="glosso-engine"></span>
    </div>
    <script>
    function glossoSanitize(root) {
      for (const el of root.querySelectorAll('*')) {
        for (const attr of Array.from(el.attributes)) {
          const name = attr.name.toLowerCase();
          if (name.startsWith('on') || name === 'srcdoc') { el.removeAttribute(attr.name); continue; }
          if (['href', 'src', 'data', 'xlink:href'].includes(name)
              && attr.value.trim().toLowerCase().startsWith('javascript:')) {
            el.removeAttribute(attr.name);
          }
        }
      }
    }
    const glosso = {
      mode: 'translated',
      original: {},          // id -> original innerHTML
      translated: {},        // id -> translated innerHTML
      pending: new Set(),    // translatable ids still awaiting a translation
      originalTitle: '',
      translatedTitle: '',
      summary: '',
      engine: '',               // provider · model label, right side of the footer
      chatBusy: false,          // one question in flight at a time
      questionsRequested: false, // suggestions are generated once, lazily
      asked: []                 // questions already asked — their chips stay gone
    };
    function glossoSetArticle(title, byline, html) {
      glosso.originalTitle = title;
      document.title = title;
      const heading = document.getElementById('glosso-title');
      heading.textContent = title;
      heading.classList.add('glosso-pending');
      document.getElementById('glosso-byline').textContent = byline || '';
      const content = document.getElementById('glosso-content');
      content.innerHTML = html;
      glossoSanitize(content);
      const SKIP = ['IMG', 'HR', 'TABLE', 'PRE', 'VIDEO', 'IFRAME'];
      const blocks = [];
      const register = function(el, translatable) {
        const id = blocks.length;
        el.dataset.glossoId = id;
        const text = el.textContent.trim();
        // ponytail: 4000-char cap — an oversized block would hit the model's
        // token ceiling and truncate; it stays untranslated instead. Split in
        // two if it ever bites.
        const translate = translatable && text.length > 0 && text.length < 4000;
        if (translate) { el.classList.add('glosso-pending'); glosso.pending.add(id); }
        glosso.original[id] = el.innerHTML;
        blocks.push({id: id, html: el.innerHTML, translate: translate});
      };
      (function walk(node) {
        for (const el of Array.from(node.children)) {
          if (['DIV', 'SECTION', 'ARTICLE', 'MAIN'].includes(el.tagName)
              && el.children.length > 0) { walk(el); continue; }
          if (el.tagName === 'FIGURE') {
            for (const caption of el.querySelectorAll('figcaption')) { register(caption, true); }
            continue;
          }
          if (['UL', 'OL'].includes(el.tagName)) {
            for (const li of el.querySelectorAll(':scope > li')) { register(li, true); }
            continue;
          }
          register(el, !SKIP.includes(el.tagName));
        }
      })(content);
      document.getElementById('glosso-pills').style.display = 'flex';
      // The ornament belongs to the loaded title page, not the empty template.
      document.getElementById('glosso-fleuron').style.display = 'block';
      glossoProgress();
      return JSON.stringify(blocks);
    }
    function glossoRender(id, html) {
      const el = document.querySelector('[data-glosso-id="' + id + '"]');
      if (!el) { return; }
      const had = Array.from(el.querySelectorAll('img'));
      el.innerHTML = html;
      glossoSanitize(el);
      const have = new Set(Array.from(el.querySelectorAll('img')).map(img => img.getAttribute('src')));
      for (const img of had) {
        if (!have.has(img.getAttribute('src'))) { el.appendChild(img); }
      }
      el.classList.remove('glosso-pending');
    }
    function glossoApply(id, html) {
      glosso.translated[id] = html;
      glosso.pending.delete(Number(id));
      const el = document.querySelector('[data-glosso-id="' + id + '"]');
      if (el) { el.classList.add('glosso-dual'); }
      if (glosso.mode === 'translated') { glossoRender(id, html); }
    }
    function glossoSetLanguages(translated, original) {
      document.getElementById('glosso-seg-translated').textContent = translated;
      document.getElementById('glosso-seg-original').textContent = original;
    }
    function glossoSetTitle(title) {
      glosso.translatedTitle = title;
      if (glosso.mode === 'translated') {
        document.title = title;
        const heading = document.getElementById('glosso-title');
        heading.textContent = title;
        heading.classList.remove('glosso-pending');
      }
    }
    function glossoSetSummary(text) {
      glosso.summary = text;
      glossoRefreshSummary();
    }
    function glossoRefreshSummary() {
      const summary = document.getElementById('glosso-summary');
      summary.textContent = glosso.summary;
      summary.style.display = (glosso.summary && glosso.mode === 'translated') ? 'block' : 'none';
    }
    function glossoToggleOriginal() {
      const toOriginal = glosso.mode === 'translated';
      glosso.mode = toOriginal ? 'original' : 'translated';
      for (const id of Object.keys(glosso.translated)) {
        glossoRender(id, toOriginal ? glosso.original[id] : glosso.translated[id]);
      }
      for (const id of glosso.pending) {
        const el = document.querySelector('[data-glosso-id="' + id + '"]');
        if (el) { el.classList.toggle('glosso-pending', !toOriginal); }
      }
      const heading = document.getElementById('glosso-title');
      const title = toOriginal ? glosso.originalTitle : (glosso.translatedTitle || glosso.originalTitle);
      heading.textContent = title;
      document.title = title;
      heading.classList.toggle('glosso-pending', !toOriginal && !glosso.translatedTitle);
      glossoRefreshSummary();
      document.body.classList.toggle('glosso-original', toOriginal);
      document.getElementById('glosso-seg-translated').setAttribute('aria-pressed', String(!toOriginal));
      document.getElementById('glosso-seg-original').setAttribute('aria-pressed', String(toOriginal));
    }
    function glossoAbort() {
      glosso.pending.clear();
      glosso.translatedTitle = glosso.translatedTitle || glosso.originalTitle;
      for (const el of document.querySelectorAll('.glosso-pending')) {
        el.classList.remove('glosso-pending');
      }
    }
    function glossoStatus(msg) {
      document.getElementById('glosso-status').textContent = msg;
      glossoFooter();
    }
    function glossoSetEngine(label) {
      glosso.engine = label;
      document.getElementById('glosso-engine').textContent = label;
      glossoFooter();
    }
    // The bar outlives the status text now, so visibility follows either half.
    function glossoFooter() {
      const footer = document.getElementById('glosso-footer');
      const filled = glosso.engine || document.getElementById('glosso-status').textContent;
      footer.style.display = filled ? 'flex' : 'none';
    }
    function glossoToggleChat() {
      const open = !document.body.classList.contains('glosso-chat-open');
      const cs = getComputedStyle(document.body);
      document.body.style.width = cs.width;
      document.body.style.marginLeft = cs.marginLeft;
      clearTimeout(glosso.chatPin);
      glosso.chatPin = setTimeout(() => {
        document.body.style.width = '';
        document.body.style.marginLeft = '';
      }, 300);
      document.body.classList.toggle('glosso-chat-open', open);
      window.webkit?.messageHandlers?.glosso?.postMessage({action: 'panel', open: open ? '1' : ''});
      if (open && !glosso.questionsRequested) {
        glosso.questionsRequested = true;
        const spin = document.createElement('span');
        spin.className = 'glosso-spin';
        document.getElementById('glosso-chat-suggestions').appendChild(spin);
        window.webkit?.messageHandlers?.glosso?.postMessage({action: 'suggest'});
      }
      if (open) { document.getElementById('glosso-chat-input').focus(); }
    }
    function glossoSetQuestions(json) {
      const box = document.getElementById('glosso-chat-suggestions');
      box.textContent = '';
      let questions = [];
      try { questions = JSON.parse(json); } catch (e) {}
      if (!questions.length) { glosso.questionsRequested = false; return; }
      for (const q of questions) {
        if (glosso.asked.includes(q.trim())) { continue; }
        const chip = document.createElement('button');
        chip.type = 'button';
        chip.className = 'glosso-chip';
        chip.textContent = q;
        chip.title = q;
        chip.addEventListener('click', function() { glossoAsk(q); });
        box.appendChild(chip);
      }
      glossoSuggestLabel();
    }
    function glossoSuggestLabel() {
      const any = document.querySelector('#glosso-chat-suggestions .glosso-chip');
      document.getElementById('glosso-suggest-label').style.display = any ? 'block' : 'none';
    }
    function glossoChatBusy(busy) {
      glosso.chatBusy = busy;
      document.querySelector('#glosso-chat-form button').disabled = busy;
      for (const chip of document.querySelectorAll('.glosso-chip')) { chip.disabled = busy; }
    }
    function glossoAsk(question) {
      question = question.trim();
      if (!question || glosso.chatBusy) { return; }
      glosso.asked.push(question);
      document.getElementById('glosso-chat-panel').classList.add('glosso-chat-started');
      for (const chip of document.querySelectorAll('.glosso-chip')) {
        if (chip.textContent.trim() === question) { chip.remove(); }
      }
      glossoSuggestLabel();
      const messages = document.getElementById('glosso-chat-messages');
      const q = document.createElement('div');
      q.className = 'glosso-chat-q';
      q.textContent = question;
      const a = document.createElement('div');
      a.className = 'glosso-chat-a glosso-chat-pending';
      const spin = document.createElement('span');
      spin.className = 'glosso-spin';
      a.appendChild(spin);
      messages.appendChild(q);
      messages.appendChild(a);
      messages.scrollTop = messages.scrollHeight;
      glossoChatBusy(true);
      window.webkit?.messageHandlers?.glosso?.postMessage({action: 'ask', question: question});
    }
    function glossoAnswer(answer, error) {
      const pending = document.querySelector('.glosso-chat-pending');
      if (!pending) { return; }
      pending.classList.remove('glosso-chat-pending');
      // The answer arrives as rendered markdown; the error is our own string and stays text.
      if (answer) { pending.innerHTML = answer; glossoSanitize(pending); }
      else { pending.textContent = error; pending.classList.add('glosso-chat-error'); }
      glossoChatBusy(false);
      const messages = document.getElementById('glosso-chat-messages');
      messages.scrollTop = messages.scrollHeight;
      document.getElementById('glosso-chat-input').focus();
    }
    document.getElementById('glosso-seg-original').addEventListener('click', function() {
      if (glosso.mode !== 'original') { glossoToggleOriginal(); }
    });
    document.getElementById('glosso-seg-translated').addEventListener('click', function() {
      if (glosso.mode !== 'translated') { glossoToggleOriginal(); }
    });
    document.getElementById('glosso-chat').addEventListener('click', glossoToggleChat);
    document.getElementById('glosso-content').addEventListener('click', function(e) {
      if (glosso.mode !== 'translated' || e.target.closest('a')) { return; }
      const block = e.target.closest('[data-glosso-id]');
      if (!block || !(block.dataset.glossoId in glosso.translated)) { return; }
      const open = block.querySelector('.glosso-interlinear');
      if (open) { open.remove(); return; }
      const note = document.createElement('div');
      note.className = 'glosso-interlinear';
      const lang = document.createElement('span');
      lang.className = 'glosso-interlinear-lang';
      lang.textContent = '\(loc("Oryginał", "Original"))';
      const text = document.createElement('div');
      text.innerHTML = glosso.original[block.dataset.glossoId];
      glossoSanitize(text);
      note.appendChild(lang);
      note.appendChild(text);
      block.appendChild(note);
    });
    function glossoGrowInput() {
      const input = document.getElementById('glosso-chat-input');
      input.style.height = 'auto';
      input.style.height = input.scrollHeight + 'px';
    }
    document.getElementById('glosso-chat-form').addEventListener('submit', function(e) {
      e.preventDefault();
      const input = document.getElementById('glosso-chat-input');
      if (glosso.chatBusy) { return; }
      glossoAsk(input.value);
      input.value = '';
      glossoGrowInput();
    });
    document.getElementById('glosso-chat-input').addEventListener('input', glossoGrowInput);
    document.getElementById('glosso-chat-input').addEventListener('keydown', function(e) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        document.getElementById('glosso-chat-form').requestSubmit();
      }
    });
    document.getElementById('glosso-refresh').addEventListener('click', function() {
      window.webkit?.messageHandlers?.glosso?.postMessage('refresh');
    });
    function glossoProgress() {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const fraction = max > 0 ? Math.min(1, window.scrollY / max) : 1;
      document.querySelector('#glosso-progress div').style.transform = 'scaleX(' + fraction + ')';
    }
    document.addEventListener('scroll', glossoProgress, {passive: true});
    window.addEventListener('resize', glossoProgress);
    </script>
    </body>
    </html>
    """
    }
}

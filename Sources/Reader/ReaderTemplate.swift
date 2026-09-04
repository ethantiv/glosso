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
              /* Controls follow the user's accent; anything belonging to the article reads as ink, not a brand colour. */
              --accent: AccentColor;
              /* Paper, not Canvas: a warm off-white page with warm ink, and sepia where the article annotates
                 itself (links, the quote rule, the interlinear language tag). Controls keep the system accent. */
              --paper: light-dark(#FBF7EF, #1C1A17);
              --paper-2: light-dark(#F2ECE0, #262320);
              --ink: light-dark(#2A2622, #E7E0D4);
              --ink-soft: light-dark(#6B645B, #A39B8E);
              --sepia: light-dark(#8A6A3E, #C8A46A);
              --hairline: light-dark(#E4DDD0, #3A3631);
              /* The chat's filled surfaces. One definition because the question bubble and the send button sit next to
                 each other and any drift between them is visible. Darkened in both appearances, not only in light:
                 contrast is a property of the pair alone, and macOS's dark-mode accent is the lighter of the two, so
                 white on the raw colour measures the same ~3.6:1 the mix exists to fix. */
              --chat-accent: color-mix(in srgb, AccentColor 82%, black);
              /* Mixing the colour costs `AccentColorText`, which only pairs with an unmixed `AccentColor`. White is
                 right for the six dark system accents and wrong for yellow (~2.4:1), so the ink is asked to follow the
                 fill where the engine can do it; the plain `#fff` below stays as the fallback. */
              --chat-ink: #fff;
              --ui-font: "Avenir Next", -apple-system, system-ui, sans-serif; }
      @supports (color: contrast-color(black)) {
        :root { --chat-ink: contrast-color(var(--chat-accent)); }
      }
      #glosso-progress { position: fixed; top: 0; left: 0; right: 0; height: 6px;
                         background: color-mix(in srgb, var(--sepia) 18%, var(--paper));
                         z-index: 20; }
      #glosso-progress div { height: 100%; background: var(--accent);
                             transform-origin: left; transform: scaleX(1); }
      html { background: var(--paper); }
      body { font-family: "Athelas", "Palatino", ui-serif, Georgia, serif;
             font-size: 18px; line-height: 1.72; max-width: 41em; margin: 0 auto;
             padding: 2.2em 1.5em 4em; overflow-wrap: break-word;
             color: var(--ink); background: var(--paper); }
      /* The grain of the sheet: one tiled noise, faint enough to read as texture and not as dirt. */
      body::before { content: ""; position: fixed; inset: 0; pointer-events: none; z-index: 30;
                     opacity: .05; mix-blend-mode: multiply;
                     background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='180' height='180'%3E%3Cfilter id='g'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 .6 0'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23g)'/%3E%3C/svg%3E"); }
      @media (prefers-color-scheme: dark) { body::before { opacity: .08; mix-blend-mode: screen; } }
      ::selection { background: color-mix(in srgb, var(--sepia) 28%, var(--paper)); }
      #glosso-content h2, #glosso-content h3 { font-weight: 600; line-height: 1.25; margin: 1.8em 0 .6em; }
      #glosso-content h2 { font-size: 1.35em; }
      #glosso-content h3 { font-size: 1.12em; }
      h1#glosso-title { font-size: 2.5em; line-height: 1.18; margin: 0 auto .4em;
                        font-weight: 400; text-align: center; letter-spacing: 0; }
      #glosso-fleuron { display: none; text-align: center; color: var(--sepia);
                        font-size: 1.1em; letter-spacing: .6em; margin: .4em 0; }
      #glosso-byline { text-align: center; font-variant-caps: small-caps;
                       letter-spacing: .12em; font-size: .95em;
                       color: var(--ink-soft); margin-bottom: 2.6em; }
      #glosso-summary { border-top: 1px solid var(--ink);
                        border-bottom: 1px solid var(--ink);
                        padding: 1.1em 1em; margin: 0 0 2.8em; background: var(--paper-2);
                        font-size: .92em; line-height: 1.6; display: none; }
      #glosso-summary::before { content: "\(loc("Od tłumacza · TL;DR", "Translator's note · TL;DR"))";
                                display: block; font-family: var(--ui-font);
                                font-size: .68rem; font-weight: 600; letter-spacing: .2em;
                                text-transform: uppercase; color: var(--sepia);
                                margin-bottom: .5em; }
      #glosso-content figcaption { font-family: var(--ui-font); text-align: center; }
      /* A circle with an arrow, like the Messages compose button. The word "Send" moves to aria-label: it never
         draws but still names the control for VoiceOver. */
      .glosso-send { font-family: var(--ui-font); font-size: .9rem; font-weight: 600;
                     width: 28px; height: 28px; flex: none; padding: 0; line-height: 1;
                     border-radius: 50%; cursor: pointer;
                     color: var(--chat-ink); background: var(--chat-accent); border: 0; }
      img, video { display: block; margin-inline: auto; max-width: 100%; height: auto; border-radius: 2px; }
      /* Embedded players carry fixed width/height attributes and would overflow
         the column; cap them and let aspect-ratio keep the video shape.
         ponytail: 16:9 covers YouTube/Vimeo; a rare non-video iframe gets that
         shape too — revisit if one ever matters. */
      iframe, embed, object { max-width: 100%; border-radius: 4px; }
      iframe { width: 100%; aspect-ratio: 16 / 9; height: auto; }
      figure { margin: 2.2em 0; }
      figcaption { font-size: .78em; opacity: .8; margin-top: .7em; }
      blockquote { margin: 1.8em 0; padding-left: 1.5em; text-align: left;
                   border-left: 3px solid var(--sepia); opacity: .92;
                   font-size: 1.08em; font-style: italic; line-height: 1.55; }
      pre { overflow-x: auto; background: var(--paper-2); border: 1px solid var(--hairline);
            padding: 1em; border-radius: 4px; font-size: .8em; text-align: left; }
      code { font-family: ui-monospace, monospace; }
      /* A link is an annotation in the text, not browser chrome: ink-coloured, with a thin sepia underline. */
      a { color: inherit; text-decoration: underline; text-decoration-color: var(--sepia);
          text-decoration-thickness: 1px; text-underline-offset: .18em; }
      a:hover { color: var(--sepia); }
      .glosso-pending { opacity: .45; }
      .glosso-dual { cursor: pointer; }
      .glosso-interlinear { margin: .5em 0 .2em 1.6em; font-style: italic;
                            font-size: .9em; line-height: 1.6; cursor: default;
                            color: var(--ink-soft); }
      .glosso-interlinear-lang { font-family: var(--ui-font); font-style: normal;
                                 font-size: .64rem; font-weight: 700; letter-spacing: .14em;
                                 text-transform: uppercase; color: var(--sepia);
                                 display: block; margin-bottom: .3em; }
      /* The one part of the page that deliberately leaves the "Dwugłos" typography behind: a conversation reads as a
         Messages thread, not as a critical apparatus. Hence the UI font here, and bubbles below. */
      #glosso-chat-panel { position: fixed; top: 6px; right: 0; bottom: 0;
                           width: calc(var(--glosso-chat-w, 340px) - 20px);
                           display: flex; flex-direction: column; gap: .9em;
                           transform: translateX(100%); visibility: hidden;
                           transition: transform .25s ease-in-out, visibility 0s .25s;
                           background: var(--paper-2); color: var(--ink);
                           font-family: var(--ui-font);
                           z-index: 5; box-sizing: border-box;
                           border-left: 1px solid var(--hairline);
                           padding: 1.1em 1.2em 1em; font-size: .92em; }
      body.glosso-chat-open #glosso-chat-panel { transform: none; visibility: visible;
                                                 transition: transform .25s ease-in-out,
                                                             visibility 0s; }
      body.glosso-chat-open { margin-right: var(--glosso-chat-w, 340px); }
      /* Title case, not caps: HIG asks for it, and the panel isn't a section header in a book any more. */
      .glosso-chat-label { font-size: .78rem; font-weight: 600; text-align: center;
                           color: var(--ink-soft); }
      /* The chat and the saved-articles list share the one panel; Swift picks which body shows. */
      #glosso-chat-body, #glosso-saved-body { display: flex; flex-direction: column;
                                              gap: .9em; flex: 1; min-height: 0; }
      body.glosso-saved-mode #glosso-chat-body { display: none; }
      body:not(.glosso-saved-mode) #glosso-saved-body { display: none; }
      .glosso-saved-header { display: flex; justify-content: space-between; align-items: center; }
      .glosso-saved-header .glosso-chat-label { text-align: left; }
      #glosso-retention { font-family: inherit; font-size: .78rem; color: var(--ink-soft);
                          background: var(--paper); border: 1px solid var(--hairline);
                          border-radius: 1.6em; padding: .15em .5em; }
      #glosso-saved-list { flex: 1; overflow-y: auto; padding-right: .6em; }
      /* A file listing, not a stack of cards: bare rows, the title reads as a link, and the hover
         reveals where the original lives. */
      .glosso-saved-row { display: flex; align-items: flex-start; gap: .4em;
                          border-radius: 8px; padding: .55em .5em; }
      .glosso-saved-row + .glosso-saved-row { border-top: 1px solid var(--hairline); }
      .glosso-saved-row:hover { background: color-mix(in srgb, var(--ink) 5%, var(--paper-2)); }
      /* font-size too: buttons don't inherit it, and WebKit's 13px default is what made the list read small. */
      .glosso-saved-open { flex: 1; min-width: 0; text-align: left; cursor: pointer;
                           font-family: inherit; font-size: inherit; background: none;
                           color: var(--ink); border: 0; padding: 0; }
      /* Two lines, a step under the panel's body size — full size read as a second article column. */
      .glosso-saved-title { display: -webkit-box; -webkit-line-clamp: 2;
                            -webkit-box-orient: vertical; overflow: hidden;
                            font-size: .88em; line-height: 1.4; }
      .glosso-saved-open:hover .glosso-saved-title { text-decoration: underline; }
      /* One meta line, two tenants: the age by default, the original's URL while hovered. */
      .glosso-saved-meta { display: block; font-size: .82em; margin-top: .15em;
                           color: var(--ink-soft);
                           overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .glosso-saved-row:hover .glosso-saved-age { display: none; }
      .glosso-saved-url { display: none; }
      .glosso-saved-row:hover .glosso-saved-url { display: inline; }
      /* The pin is drawn, not typed: a stroke icon in currentColor keeps it in the panel's ink like the
         toolbar's SF Symbols. Unpinned rows reveal theirs on hover only, the way Finder hides row controls. */
      .glosso-saved-pin { flex: none; cursor: pointer; background: none; border: 0;
                          padding: .2em; margin-top: .1em; color: var(--ink-soft);
                          display: flex; align-items: center; visibility: hidden; }
      .glosso-saved-row:hover .glosso-saved-pin,
      .glosso-saved-pin.glosso-pinned { visibility: visible; }
      .glosso-saved-pin:hover { color: var(--ink); }
      .glosso-saved-pin.glosso-pinned { color: var(--sepia); }
      #glosso-saved-empty { display: none; font-size: .85em; color: var(--ink-soft);
                            text-align: center; margin-top: 1em; }
      #glosso-chat-messages { flex: 1; overflow-y: auto; padding-right: .6em;
                              display: flex; flex-direction: column; }
      .glosso-chat-q, .glosso-chat-a { max-width: 88%; margin-bottom: .5em;
                                       font-size: .92em; line-height: 1.5;
                                       border-radius: 18px; padding: .5em .85em; }
      .glosso-chat-q { align-self: flex-end; border-bottom-right-radius: 5px;
                       background: var(--chat-accent); color: var(--chat-ink); }
      .glosso-chat-a { align-self: flex-start; border-bottom-left-radius: 5px;
                       background: light-dark(#E9E4DA, #3A3632); color: var(--ink);
                       white-space: pre-wrap; }
      /* A tinted bubble, not tinted text: red on the received-bubble gray is barely a signal. */
      .glosso-chat-error { background: color-mix(in srgb, red 12%, var(--paper));
                           color: color-mix(in srgb, red 70%, var(--ink)); }
      #glosso-suggest-label { font-size: .72rem; font-weight: 600;
                              margin-bottom: -.45em; color: var(--ink-soft);
                              display: none; }
      /* The same wrapped list before and during the conversation — `glossoAsk` already removes a chip once it has been
         asked, so the list shrinks on its own and doesn't need a second, truncated layout to squeeze into. */
      #glosso-chat-suggestions { display: flex; flex-wrap: wrap; gap: .4em; }
      /* 1.6em, not 999px: the browser clamps it to a pill up to two lines, and past that the corner stops eating the padding of the first and last line. */
      .glosso-chip { font-family: inherit; font-size: .82em; line-height: 1.4;
                     text-align: left; cursor: pointer; color: var(--ink);
                     background: var(--paper); border: 1px solid var(--hairline);
                     border-radius: 1.6em; padding: .4em .9em; }
      .glosso-chip:hover { background: color-mix(in srgb, var(--ink) 6%, var(--paper)); }
      .glosso-chip:disabled, #glosso-chat-form button:disabled { opacity: .4; cursor: default; }
      #glosso-chat-form { display: flex; gap: .5em; align-items: center; }
      #glosso-chat-input { flex: 1; font-family: inherit; font-size: .9em;
                           padding: .5em .9em; border-radius: 999px;
                           border: 1px solid var(--hairline);
                           background: var(--paper); color: var(--ink);
                           resize: none; max-height: 8em; overflow-y: auto; line-height: 1.4; }
      .glosso-spin { display: inline-block; width: 1em; height: 1em; border-radius: 50%;
                     border: 2px solid color-mix(in srgb, var(--ink) 25%, var(--paper));
                     border-top-color: transparent; animation: glosso-spin 1s linear infinite; }
      @keyframes glosso-spin { to { transform: rotate(360deg); } }
      @media (prefers-reduced-motion: reduce) {
        *, *::before, *::after { transition: none !important; animation: none !important; }
      }
    </style>
    </head>
    <body>
    <div id="glosso-progress"><div></div></div>
    <h1 id="glosso-title"></h1>
    <div id="glosso-fleuron">&#10086;</div>
    <div id="glosso-byline"></div>
    <div id="glosso-summary"></div>
    <div id="glosso-content"></div>
    <div id="glosso-chat-panel">
      <div id="glosso-chat-body">
        <div class="glosso-chat-label">\(loc("Zapytaj artykuł", "Ask the article"))</div>
        <div id="glosso-chat-messages"></div>
        <div id="glosso-suggest-label">\(loc("Podpowiedzi", "Suggestions"))</div>
        <div id="glosso-chat-suggestions"></div>
        <form id="glosso-chat-form">
          <textarea id="glosso-chat-input" rows="1" autocomplete="off" placeholder="\(loc("Zadaj pytanie…", "Ask a question…"))"></textarea>
          <button type="submit" class="glosso-send" aria-label="\(loc("Wyślij", "Send"))">↑</button>
        </form>
      </div>
      <div id="glosso-saved-body">
        <div class="glosso-saved-header">
          <div class="glosso-chat-label">\(loc("Artykuły", "Articles"))</div>
          <select id="glosso-retention" aria-label="\(loc("Okres przechowywania", "Retention period"))" title="\(loc("Przypięte artykuły nie wygasają.", "Pinned articles never expire."))">
            <option value="7">\(loc("7 dni", "7 days"))</option>
            <option value="30">\(loc("30 dni", "30 days"))</option>
            <option value="90">\(loc("90 dni", "90 days"))</option>
          </select>
        </div>
        <div id="glosso-saved-list"></div>
        <div id="glosso-saved-empty">\(loc("Brak zapisanych artykułów.", "No saved articles yet."))</div>
      </div>
    </div>
    <script>
    function glossoSanitize(root) {
      for (const el of root.querySelectorAll('*')) {
        // META can navigate (http-equiv=refresh) and BASE rewrites every relative URL on the page.
        if (el.tagName === 'META' || el.tagName === 'BASE') { el.remove(); continue; }
        for (const attr of Array.from(el.attributes)) {
          const name = attr.name.toLowerCase();
          if (name.startsWith('on') || name === 'srcdoc') { el.removeAttribute(attr.name); continue; }
          if (['href', 'src', 'data', 'xlink:href', 'action', 'formaction'].includes(name)
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
      chatBusy: false,          // one question in flight at a time
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
    // An idempotent setter, not a toggle: the toolbar's segmented control owns this state and sets it outright.
    function glossoSetMode(mode) {
      const toOriginal = mode === 'original';
      if (toOriginal === (glosso.mode === 'original')) { return; }
      glosso.mode = mode;
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
    }
    function glossoAbort() {
      glosso.pending.clear();
      glosso.translatedTitle = glosso.translatedTitle || glosso.originalTitle;
      for (const el of document.querySelectorAll('.glosso-pending')) {
        el.classList.remove('glosso-pending');
      }
    }
    // Swift owns whether the panel is open — it animates the window's width to match, so the page only applies it.
    // `width` is the real growth the screen allowed, e.g. "297px"; empty keeps the 340px default.
    function glossoSetChat(open, width) {
      // Swift passes "1"/"" — `call` JSON-encodes every argument as a string, so coerce before comparing.
      open = !!open;
      if (width) { document.body.style.setProperty('--glosso-chat-w', width); }
      if (open === document.body.classList.contains('glosso-chat-open')) { return; }
      const cs = getComputedStyle(document.body);
      document.body.style.width = cs.width;
      document.body.style.marginLeft = cs.marginLeft;
      clearTimeout(glosso.chatPin);
      glosso.chatPin = setTimeout(() => {
        document.body.style.width = '';
        document.body.style.marginLeft = '';
      }, 300);
      document.body.classList.toggle('glosso-chat-open', open);
      // Only when the chat body is the visible one — focusing a display:none input drops focus to <body>.
      if (open && !document.body.classList.contains('glosso-saved-mode')) {
        document.getElementById('glosso-chat-input').focus();
      }
    }
    // An idempotent setter like glossoSetMode: Swift owns the retention choice; the page only shows it.
    function glossoSetRetention(days) {
      document.getElementById('glosso-retention').value = days;
    }
    document.getElementById('glosso-retention').addEventListener('change', function() {
      window.webkit?.messageHandlers?.glosso?.postMessage({action: 'retention', days: this.value});
    });
    // An idempotent setter like glossoSetMode: Swift owns which body the shared panel shows.
    function glossoPanelMode(mode) {
      const savedMode = mode === 'saved';
      document.body.classList.toggle('glosso-saved-mode', savedMode);
      // The saved→chat swap keeps the panel open, so glossoSetChat's focus never fires — do it here.
      if (!savedMode && document.body.classList.contains('glosso-chat-open')) {
        document.getElementById('glosso-chat-input').focus();
      }
    }
    function glossoSetSaved(json) {
      const box = document.getElementById('glosso-saved-list');
      box.textContent = '';
      let rows = [];
      try { rows = JSON.parse(json); } catch (e) {}
      document.getElementById('glosso-saved-empty').style.display = rows.length ? 'none' : 'block';
      for (const row of rows) {
        const item = document.createElement('div');
        item.className = 'glosso-saved-row';
        const open = document.createElement('button');
        open.type = 'button';
        open.className = 'glosso-saved-open';
        const title = document.createElement('span');
        title.className = 'glosso-saved-title';
        title.textContent = row.title;
        // The tooltip describes the original; the hover line below shows where it lives.
        open.title = row.original && row.original !== row.title ? row.original : row.url;
        const meta = document.createElement('span');
        meta.className = 'glosso-saved-meta';
        const age = document.createElement('span');
        age.className = 'glosso-saved-age';
        age.textContent = row.age || '';
        const link = document.createElement('span');
        link.className = 'glosso-saved-url';
        link.textContent = row.url;
        meta.appendChild(age);
        meta.appendChild(link);
        open.appendChild(title);
        open.appendChild(meta);
        open.addEventListener('click', function() {
          window.webkit?.messageHandlers?.glosso?.postMessage({action: 'open', url: row.url});
        });
        const pin = document.createElement('button');
        pin.type = 'button';
        pin.className = 'glosso-saved-pin' + (row.pinned ? ' glosso-pinned' : '');
        pin.innerHTML = '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true">'
          + '<path d="M5.5 1.75h5v4.75l1.75 2.25h-8.5l1.75-2.25z M8 8.75v5.5" '
          + 'fill="' + (row.pinned ? 'currentColor' : 'none') + '" stroke="currentColor" '
          + 'stroke-width="1.3" stroke-linejoin="round" stroke-linecap="round"/></svg>';
        glossoSanitize(pin);
        pin.setAttribute('aria-label', row.pinned ? '\(loc("Odepnij", "Unpin"))' : '\(loc("Przypnij", "Pin"))');
        pin.addEventListener('click', function() {
          window.webkit?.messageHandlers?.glosso?.postMessage({action: 'pin', url: row.url, on: row.pinned ? '' : '1'});
        });
        item.appendChild(open);
        item.appendChild(pin);
        box.appendChild(item);
      }
    }
    function glossoSuggesting() {
      const spin = document.createElement('span');
      spin.className = 'glosso-spin';
      document.getElementById('glosso-chat-suggestions').appendChild(spin);
    }
    function glossoSetQuestions(json) {
      const box = document.getElementById('glosso-chat-suggestions');
      box.textContent = '';
      let questions = [];
      try { questions = JSON.parse(json); } catch (e) {}
      if (!questions.length) { return; }
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

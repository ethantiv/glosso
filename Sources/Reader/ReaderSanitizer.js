// Runs only in Glosso's isolated world. Never attach untrusted markup to the live document.
const glossoVideoHosts = new Set([
  'dailymotion.com', 'www.dailymotion.com', 'youtube.com', 'www.youtube.com',
  'youtube-nocookie.com', 'www.youtube-nocookie.com', 'player.vimeo.com', 'www.player.vimeo.com',
  'v.qq.com', 'www.v.qq.com', 'player.twitch.tv', 'www.player.twitch.tv'
]);
function glossoSafeURL(value, kind) {
  if (!value) return null;
  if (kind === 'href' && value.startsWith('#')) return value;
  let url;
  try { url = new URL(value, glossoSourceURL); } catch (_) { return null; }
  if (kind === 'iframe') {
    return url.protocol === 'https:' && !url.username && !url.password &&
      (!url.port || url.port === '443') && glossoVideoHosts.has(url.hostname) ? url.href : null;
  }
  if (url.protocol === 'https:' || url.protocol === 'http:') return url.href;
  if (kind === 'href' && url.protocol === 'mailto:') return url.href;
  if (kind === 'img' && /^data:image\/(png|jpeg|gif|webp|avif|bmp);base64,[a-z0-9+/=\s]+$/i.test(value)) return value;
  return null;
}
// Parse candidates before validating URLs: commas can belong to a URL (notably data images).
// Rebuild from accepted candidates so rejected schemes or descriptors never reach the DOM.
function glossoSafeSrcset(value) {
  const candidates = [];
  let rest = value;
  while (rest.length) {
    rest = rest.replace(/^[\t\n\f\r ,]+/, '');
    if (!rest) break;
    const token = /^[^\t\n\f\r ]+/.exec(rest)[0];
    rest = rest.slice(token.length);
    let raw = token;
    let descriptor = '';
    if (raw.endsWith(',')) {
      raw = raw.replace(/,+$/, '');
    } else {
      const comma = rest.indexOf(',');
      descriptor = (comma < 0 ? rest : rest.slice(0, comma)).trim();
      rest = comma < 0 ? '' : rest.slice(comma + 1);
    }
    if (descriptor && !(/^[1-9][0-9]*w$/.test(descriptor) ||
        (/^(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)x$/.test(descriptor) && parseFloat(descriptor) > 0))) continue;
    const url = glossoSafeURL(raw, 'img');
    if (url) candidates.push(url + (descriptor ? ' ' + descriptor : ''));
  }
  return candidates.join(', ');
}
// Let DOMPurify inspect the normalized candidate list instead of dropping the entire
// attribute when only its first candidate has a forbidden scheme.
DOMPurify.addHook('uponSanitizeAttribute', function(element, attribute) {
  if (attribute.attrName !== 'srcset') return;
  const image = element.tagName === 'IMG' || (element.tagName === 'SOURCE' && element.parentElement?.tagName === 'PICTURE');
  attribute.attrValue = image ? glossoSafeSrcset(attribute.attrValue) : '';
  if (!attribute.attrValue) attribute.keepAttr = false;
});
function glossoClean(html) {
  const fragment = DOMPurify.sanitize(html, {
    RETURN_DOM_FRAGMENT: true,
    // The hook validates every candidate, including raster data URLs; the generic
    // single-URL check cannot validate a srcset list.
    ADD_URI_SAFE_ATTR: ['srcset'],
    ALLOWED_TAGS: ['p','div','section','article','main','aside','span','br','hr','h1','h2','h3','h4','h5','h6',
      'b','strong','i','em','u','s','del','ins','sub','sup','small','mark','abbr','blockquote','q','cite',
      'ul','ol','li','dl','dt','dd','pre','code','kbd','samp','table','caption','thead','tbody','tfoot','tr','th','td',
      'figure','figcaption','a','img','picture','video','audio','source','iframe'],
    ALLOWED_ATTR: ['href','src','alt','title','width','height','colspan','rowspan','scope','start','reversed',
      'type','controls','poster','srcset','sizes','media'],
    ALLOW_DATA_ATTR: false,
    ALLOW_ARIA_ATTR: false,
    SANITIZE_NAMED_PROPS: true
  });
  for (const el of fragment.querySelectorAll('*')) {
    for (const attr of ['href', 'src', 'poster']) {
      if (!el.hasAttribute(attr)) continue;
      const kind = attr === 'href' ? 'href' : (el.tagName === 'IFRAME' ? 'iframe' :
        (el.tagName === 'IMG' || attr === 'poster' ? 'img' : 'media'));
      const url = glossoSafeURL(el.getAttribute(attr), kind);
      if (url) el.setAttribute(attr, url); else el.removeAttribute(attr);
    }
    if (el.tagName === 'IFRAME') {
      if (!el.hasAttribute('src')) { el.remove(); continue; }
      el.setAttribute('sandbox', 'allow-scripts allow-same-origin');
      el.setAttribute('referrerpolicy', 'no-referrer');
      el.setAttribute('allow', 'fullscreen');
    }
    if (el.tagName === 'A') el.setAttribute('rel', 'noopener noreferrer');
    if (el.tagName === 'VIDEO' || el.tagName === 'AUDIO') el.setAttribute('controls', '');
  }
  return fragment;
}
function glossoSetHTML(element, html) { element.replaceChildren(glossoClean(html)); }
function glossoPost(body) {
  window.webkit.messageHandlers.glosso.postMessage({...body, session: glossoDocumentID});
}

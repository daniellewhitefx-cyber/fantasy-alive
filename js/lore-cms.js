const LORE_SUPABASE_URL = 'https://xdchluuvicuuqyqsejnq.supabase.co';
const LORE_SUPABASE_ANON_KEY = 'sb_publishable_JL4nY9-fcOAwYzwpwiJa9w_nypZCt99';
const loreSupabase = window.supabase.createClient(LORE_SUPABASE_URL, LORE_SUPABASE_ANON_KEY);

const LORE_IMAGE_BUCKET = 'lore-images';

async function loreLoadEntries(){
  const { data, error } = await loreSupabase
    .from('lore_entries')
    .select('id, slug, title, category, body, body_format, sort_order, updated_at')
    .order('sort_order', { ascending: true })
    .order('title', { ascending: true });
  if(error) throw error;
  return data || [];
}

async function loreGetEditorRole(){
  const { data } = await loreSupabase.auth.getSession();
  const session = data && data.session;
  if(!session) return null;
  const meta = session.user.app_metadata || {};
  return { user: session.user, isEditor: meta.role === 'lore_editor' || !!meta.site_admin };
}

function loreSlugify(title){
  return title.toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
    .slice(0, 80) || 'entry';
}

async function loreCreateEntry({ title, category, body, body_format }){
  const baseSlug = loreSlugify(title);
  let slug = baseSlug;
  let attempt = 1;
  while(true){
    const { data, error } = await loreSupabase.from('lore_entries').select('id').eq('slug', slug).maybeSingle();
    if(error) throw error;
    if(!data) break;
    attempt++;
    slug = baseSlug + '-' + attempt;
  }
  const { data: maxRow } = await loreSupabase
    .from('lore_entries').select('sort_order').eq('category', category)
    .order('sort_order', { ascending: false }).limit(1).maybeSingle();
  const nextOrder = maxRow ? (maxRow.sort_order || 0) + 10 : 10;
  const { data: session } = await loreSupabase.auth.getSession();
  const { error: insertError } = await loreSupabase.from('lore_entries').insert({
    slug, title, category, body, body_format: body_format || 'markdown', sort_order: nextOrder,
    created_by: session.session ? session.session.user.id : null
  });
  if(insertError) throw insertError;
}

async function loreUpdateEntry(id, { title, category, body, body_format }){
  const { error } = await loreSupabase
    .from('lore_entries')
    .update({ title, category, body, body_format: body_format || 'markdown', updated_at: new Date().toISOString() })
    .eq('id', id);
  if(error) throw error;
}

async function loreDeleteEntry(id){
  const { error } = await loreSupabase.from('lore_entries').delete().eq('id', id);
  if(error) throw error;
}

async function loreSwapOrder(idA, orderA, idB, orderB){
  const { error: e1 } = await loreSupabase.from('lore_entries').update({ sort_order: orderB }).eq('id', idA);
  if(e1) throw e1;
  const { error: e2 } = await loreSupabase.from('lore_entries').update({ sort_order: orderA }).eq('id', idB);
  if(e2) throw e2;
}

async function loreUploadImage(file){
  file = await stripImageExif(file);
  const ext = (file.name.split('.').pop() || 'png').toLowerCase();
  const path = Date.now() + '-' + Math.random().toString(36).slice(2, 8) + '.' + ext;
  const { error } = await loreSupabase.storage.from(LORE_IMAGE_BUCKET).upload(path, file);
  if(error) throw error;
  const { data } = loreSupabase.storage.from(LORE_IMAGE_BUCKET).getPublicUrl(path);
  return data.publicUrl;
}

function loreEscapeHtml(str){
  return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function loreIsSafeUrl(url){
  return !/^\s*(javascript|data|vbscript):/i.test(url || '');
}

function loreAutoLinkTerm(title){
  const m = title.match(/^(.*)\s+\([^)]*\)$/);
  return m ? m[1].trim() : title;
}

function loreAutoLink(escapedText, ownTitle, allTitles, linkedSoFar){
  if(!ownTitle || !allTitles || !allTitles.length) return escapedText;

  const protectedRe = /\[\[[^\]]*\]\]|!\[[^\]]*\]\([^)]*\)|\[[^\]]*\]\([^)]*\)/g;
  const protectedSpans = [];
  let pm;
  while((pm = protectedRe.exec(escapedText))){
    protectedSpans.push([pm.index, pm.index + pm[0].length]);
  }

  const linked = linkedSoFar || new Set();
  const candidates = allTitles
    .filter(t => t && t.toLowerCase() !== ownTitle.toLowerCase())
    .filter(t => !linked.has(t.toLowerCase()))
    .map(t => ({ title: t, term: loreAutoLinkTerm(t) }))
    .filter(c => c.term)
    .sort((a, b) => b.term.length - a.term.length);

  const edits = [];
  for(const { title, term } of candidates){
    const escapedTerm = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const re = new RegExp(escapedTerm, 'g');
    let match;
    let found = null;
    while((match = re.exec(escapedText))){
      const start = match.index;
      const end = start + match[0].length;
      const before = start > 0 ? escapedText[start - 1] : ' ';
      const after = end < escapedText.length ? escapedText[end] : ' ';
      if(/[a-z0-9]/i.test(before) || /[a-z0-9]/i.test(after)) continue;
      const overlaps = protectedSpans.some(([ps, pe]) => start < pe && end > ps) ||
        edits.some(e => start < e.end && end > e.start);
      if(overlaps) continue;
      found = { start, end, text: match[0] };
      break;
    }
    if(found){
      edits.push({ start: found.start, end: found.end, title, text: found.text });
      linked.add(title.toLowerCase());
    }
  }

  if(!edits.length) return escapedText;
  edits.sort((a, b) => b.start - a.start);
  let out = escapedText;
  for(const e of edits){
    const term = loreAutoLinkTerm(e.title);
    const replacement = term === e.title ? `[[${e.title}]]` : `[[${e.title}|${e.text}]]`;
    out = out.slice(0, e.start) + replacement + out.slice(e.end);
  }
  return out;
}

function loreInline(escapedText, ownTitle, allTitles, linkedSoFar, titleToSlug){
  let out = loreAutoLink(escapedText, ownTitle, allTitles, linkedSoFar);
  out = out.replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, (m, target, display) => {
    const cleanTarget = target.trim();
    const cleanDisplay = (display || target).trim();
    const slug = titleToSlug && titleToSlug[cleanTarget.toLowerCase()];
    const href = slug ? `lore.html?open=${encodeURIComponent(slug)}` : '#';
    return `<a href="${href}" onclick="return lore_goto(event, '${cleanTarget.replace(/'/g, "\\'")}')">${cleanDisplay}</a>`;
  });
  out = out.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (m, text, url) => {
    const cleanUrl = url.trim();
    if(!loreIsSafeUrl(cleanUrl)) return text;
    return `<a href="${cleanUrl}" target="_blank" rel="noopener">${text}</a>`;
  });
  return out;
}

const LORE_HTML_ALLOWED_TAGS = {
  P: [], BR: [], B: [], STRONG: [], I: [], EM: [], U: [],
  H2: [], H3: [], H4: [],
  UL: [], OL: [], LI: [],
  BLOCKQUOTE: [], CITE: [],
  TABLE: [], THEAD: [], TBODY: [], TR: [], TH: [], TD: [],
  IMG: ['src', 'alt', 'style'],
  FIGURE: ['style'], FIGCAPTION: [],
  A: ['href', 'target', 'rel', 'onclick'],
  DIV: ['style', 'class'], SPAN: ['style']
};

const LORE_SAFE_STYLE_PROPS = new Set([
  'width', 'max-width', 'height', 'float', 'text-align',
  'margin', 'margin-left', 'margin-right', 'margin-top', 'margin-bottom'
]);

function loreSanitizeStyle(styleText){
  const out = [];
  String(styleText || '').split(';').forEach(decl => {
    const idx = decl.indexOf(':');
    if(idx === -1) return;
    const prop = decl.slice(0, idx).trim().toLowerCase();
    const value = decl.slice(idx + 1).trim();
    if(!LORE_SAFE_STYLE_PROPS.has(prop)) return;
    if(!/^[a-zA-Z0-9%.\-\s]+$/.test(value)) return;
    out.push(`${prop}: ${value}`);
  });
  return out.join('; ');
}

function loreSanitizeElement(node){
  const tag = node.tagName;
  const allowedAttrs = LORE_HTML_ALLOWED_TAGS[tag];
  if(allowedAttrs === undefined){
    const parent = node.parentNode;
    if(!parent) return;
    while(node.firstChild) parent.insertBefore(node.firstChild, node);
    parent.removeChild(node);
    return;
  }
  Array.from(node.attributes).forEach(attr => {
    const name = attr.name.toLowerCase();
    if(!allowedAttrs.includes(name)){
      node.removeAttribute(attr.name);
      return;
    }
    if(name === 'class' && tag === 'DIV' && attr.value !== 'lore-quote'){
      node.removeAttribute('class');
      return;
    }
    if((name === 'href' || name === 'src') && !loreIsSafeUrl(attr.value)){
      node.removeAttribute(attr.name);
      return;
    }
    if(name === 'style'){
      node.setAttribute('style', loreSanitizeStyle(attr.value));
    }
    if(name === 'onclick' && !/^return lore_goto\(event, '[^']*'\)$/.test(attr.value)){
      node.removeAttribute('onclick');
    }
  });
  if(tag === 'A'){
    node.setAttribute('rel', 'noopener');
    const href = node.getAttribute('href');
    if(href && href !== '#') node.setAttribute('target', '_blank');
  }
}

function loreSanitizeHtml(html){
  const wrapper = document.createElement('div');
  wrapper.innerHTML = String(html || '');
  Array.from(wrapper.querySelectorAll('*')).forEach(loreSanitizeElement);
  return wrapper.innerHTML;
}

function loreAutoLinkHtmlNode(root, ownTitle, allTitles, titleToSlug){
  if(!ownTitle || !allTitles || !allTitles.length) return;

  const linked = new Set();
  root.querySelectorAll('a[onclick^="return lore_goto"]').forEach(a => {
    const m = a.getAttribute('onclick').match(/lore_goto\(event, '([^']*)'\)/);
    if(m) linked.add(m[1].toLowerCase());
  });

  const candidates = allTitles
    .filter(t => t && t.toLowerCase() !== ownTitle.toLowerCase())
    .map(t => ({ title: t, term: loreAutoLinkTerm(t) }))
    .filter(c => c.term)
    .sort((a, b) => b.term.length - a.term.length);

  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode(n){
      let p = n.parentNode;
      while(p && p !== root){
        if(p.nodeName === 'A') return NodeFilter.FILTER_REJECT;
        p = p.parentNode;
      }
      return NodeFilter.FILTER_ACCEPT;
    }
  });
  const textNodes = [];
  let walked;
  while((walked = walker.nextNode())) textNodes.push(walked);

  textNodes.forEach(startNode => {
    let textNode = startNode;
    for(const { title, term } of candidates){
      if(linked.has(title.toLowerCase())) continue;
      const text = textNode.nodeValue;
      if(!text || !text.trim()) continue;
      const escapedTerm = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const match = new RegExp(escapedTerm).exec(text);
      if(!match) continue;
      const start = match.index;
      const end = start + match[0].length;
      const before = start > 0 ? text[start - 1] : ' ';
      const after = end < text.length ? text[end] : ' ';
      if(/[a-z0-9]/i.test(before) || /[a-z0-9]/i.test(after)) continue;

      const parent = textNode.parentNode;
      if(!parent) continue;
      const afterNode = document.createTextNode(text.slice(end));
      const link = document.createElement('a');
      const slug = titleToSlug && titleToSlug[title.toLowerCase()];
      link.setAttribute('href', slug ? `lore.html?open=${encodeURIComponent(slug)}` : '#');
      link.setAttribute('onclick', `return lore_goto(event, '${title.replace(/'/g, "\\'")}')`);
      link.textContent = text.slice(start, end);

      parent.insertBefore(document.createTextNode(text.slice(0, start)), textNode);
      parent.insertBefore(link, textNode);
      parent.insertBefore(afterNode, textNode);
      parent.removeChild(textNode);

      linked.add(title.toLowerCase());
      textNode = afterNode;
    }
  });
}

function loreRenderHtmlBody(html, ownTitle, allTitles, titleToSlug){
  const wrapper = document.createElement('div');
  wrapper.innerHTML = loreSanitizeHtml(html);
  loreAutoLinkHtmlNode(wrapper, ownTitle, allTitles, titleToSlug);
  return wrapper.innerHTML;
}

function loreParseImageLine(line){
  const m = line.match(/^!\[([^\]]*)\]\(([^)"\s]+)(?:\s+"([^"]*)")?(?:\s+(float-left|float-right|small))?\)\s*$/);
  if(!m) return null;
  const [, alt, url, caption, layout] = m;
  if(!loreIsSafeUrl(url.trim())) return null;
  const layoutClass = layout ? ` class="lore-img-${layout}"` : '';
  const imgTag = `<img src="${loreEscapeHtml(url.trim())}" alt="${loreEscapeHtml(alt)}"${caption ? '' : layoutClass}>`;
  if(caption){
    return `<figure${layoutClass}>${imgTag}<figcaption>${loreEscapeHtml(caption)}</figcaption></figure>`;
  }
  return imgTag;
}

function loreParseTable(lines, ownTitle, allTitles, linkedSoFar, titleToSlug){
  const parseRow = line => line.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim());
  const header = parseRow(lines[0]);
  const rows = lines.slice(2).map(parseRow);
  const thead = '<thead><tr>' + header.map(h => `<th>${loreInline(loreEscapeHtml(h), ownTitle, allTitles, linkedSoFar, titleToSlug)}</th>`).join('') + '</tr></thead>';
  const tbody = '<tbody>' + rows.map(r => '<tr>' + r.map(c => `<td>${loreInline(loreEscapeHtml(c), ownTitle, allTitles, linkedSoFar, titleToSlug)}</td>`).join('') + '</tr>').join('') + '</tbody>';
  return `<table>${thead}${tbody}</table>`;
}

const BULLET_RE = /^[-*]\s+\S/;
const ORDERED_RE = /^\d+\.\s+\S/;

function loreParseMarkup(source, ownTitle, allTitles, titleToSlug){
  const raw = String(source || '');
  const linkedSoFar = new Set();
  const existingLinkRe = /\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/g;
  let lm;
  while((lm = existingLinkRe.exec(raw))){
    linkedSoFar.add(lm[1].trim().toLowerCase());
  }

  const blocks = raw.replace(/\r\n/g, '\n').split(/\n\s*\n/).map(b => b.trim()).filter(Boolean);
  const inline = text => loreInline(loreEscapeHtml(text), ownTitle, allTitles, linkedSoFar, titleToSlug);

  const isBulletBlock = b => !b.includes('\n') && BULLET_RE.test(b);
  const isOrderedBlock = b => !b.includes('\n') && ORDERED_RE.test(b);

  const out = [];
  let i = 0;
  while(i < blocks.length){
    const block = blocks[i];

    if(isBulletBlock(block) || isOrderedBlock(block)){
      const ordered = isOrderedBlock(block);
      const matches = ordered ? isOrderedBlock : isBulletBlock;
      const stripRe = ordered ? /^\d+\.\s+/ : /^[-*]\s+/;
      const items = [];
      while(i < blocks.length && matches(blocks[i])){
        items.push(blocks[i].replace(stripRe, ''));
        i++;
      }
      if(items.length === 1){
        out.push(`<p class="lore-citation">${inline(items[0])}</p>`);
      } else {
        const tag = ordered ? 'ol' : 'ul';
        out.push(`<${tag}>${items.map(it => `<li>${inline(it)}</li>`).join('')}</${tag}>`);
      }
      continue;
    }

    const lines = block.split('\n');

    if(lines[0].startsWith('### ')){
      out.push(`<h4>${inline(lines[0].slice(4).trim())}</h4>`);
    } else if(lines[0].startsWith('## ')){
      out.push(`<h3>${inline(lines[0].slice(3).trim())}</h3>`);
    } else if(lines[0].startsWith('~ ')){
      out.push(`<p class="lore-attribution">${inline(lines[0].slice(2).trim())}</p>`);
    } else if(lines.every(l => l.startsWith('>'))){
      let cite = '';
      const bodyLines = [];
      lines.forEach(l => {
        const content = l.replace(/^>\s?/, '');
        const citeMatch = content.match(/^--\s*(.+)$/);
        if(citeMatch) cite = citeMatch[1].trim();
        else bodyLines.push(content);
      });
      const body = inline(bodyLines.join(' ').trim());
      out.push(`<div class="lore-quote">${body}${cite ? `<cite>${inline(cite)}</cite>` : ''}</div>`);
    } else if(lines.length === 1 && loreParseImageLine(lines[0])){
      out.push(loreParseImageLine(lines[0]));
    } else if(lines.length >= 2 && lines[0].trim().startsWith('|') && /^[\s|:-]+$/.test(lines[1]) && lines[1].includes('-')){
      out.push(loreParseTable(lines, ownTitle, allTitles, linkedSoFar, titleToSlug));
    } else {
      out.push(`<p>${inline(lines.join(' '))}</p>`);
    }
    i++;
  }

  return out.join('\n');
}

window.loreLoadEntries = loreLoadEntries;
window.loreGetEditorRole = loreGetEditorRole;
window.loreCreateEntry = loreCreateEntry;
window.loreUpdateEntry = loreUpdateEntry;
window.loreDeleteEntry = loreDeleteEntry;
window.loreSwapOrder = loreSwapOrder;
window.loreUploadImage = loreUploadImage;
window.loreParseMarkup = loreParseMarkup;
window.loreEscapeHtml = loreEscapeHtml;
window.loreSanitizeHtml = loreSanitizeHtml;
window.loreRenderHtmlBody = loreRenderHtmlBody;

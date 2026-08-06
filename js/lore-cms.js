// Data layer for the Lore page: loads entries from Supabase instead of
// static files, parses the lightweight markup lore writers use into the
// same HTML the reading engine (js/lore-engine.js) already expects, and
// provides the Add/Edit/Delete operations for accounts with the
// "lore_editor" role.
//
// Markup cheat sheet (what a lore writer actually types in the body box):
//   Blank line              -> new paragraph
//   ## Heading               -> section heading
//   ### Smaller Heading      -> sub-heading
//   > Quote text
//   > -- Attribution         -> a quote block with attribution
//   [[Other Article Title]]  -> link to another lore article by exact title
//   [link text](https://...) -> a normal external link
//   ![alt text](https://...) -> an image
//   ![alt text](https://... "Caption shown under the image") -> image with caption
//   ~ Authored by ...         -> small attribution line at the end
//   | A | B |
//   | --- | --- |
//   | 1 | 2 |                 -> a table

const LORE_SUPABASE_URL = 'https://xdchluuvicuuqyqsejnq.supabase.co';
const LORE_SUPABASE_ANON_KEY = 'sb_publishable_JL4nY9-fcOAwYzwpwiJa9w_nypZCt99';
const loreSupabase = window.supabase.createClient(LORE_SUPABASE_URL, LORE_SUPABASE_ANON_KEY);

const LORE_IMAGE_BUCKET = 'lore-images';

// ---------- data loading ----------

async function loreLoadEntries(){
  const { data, error } = await loreSupabase
    .from('lore_entries')
    .select('id, slug, title, category, body, updated_at')
    .order('title', { ascending: true });
  if(error) throw error;
  return data || [];
}

async function loreGetEditorRole(){
  const { data } = await loreSupabase.auth.getSession();
  const session = data && data.session;
  if(!session) return null;
  const role = session.user.app_metadata && session.user.app_metadata.role;
  return { user: session.user, isEditor: role === 'lore_editor' };
}

function loreSlugify(title){
  return title.toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
    .slice(0, 80) || 'entry';
}

async function loreCreateEntry({ title, category, body }){
  const baseSlug = loreSlugify(title);
  let slug = baseSlug;
  let attempt = 1;
  // Slugs must be unique; if there's a collision, just add -2, -3, etc.
  while(true){
    const { data, error } = await loreSupabase.from('lore_entries').select('id').eq('slug', slug).maybeSingle();
    if(error) throw error;
    if(!data) break;
    attempt++;
    slug = baseSlug + '-' + attempt;
  }
  const { data: session } = await loreSupabase.auth.getSession();
  const { error: insertError } = await loreSupabase.from('lore_entries').insert({
    slug, title, category, body,
    created_by: session.session ? session.session.user.id : null
  });
  if(insertError) throw insertError;
}

async function loreUpdateEntry(id, { title, category, body }){
  const { error } = await loreSupabase
    .from('lore_entries')
    .update({ title, category, body, updated_at: new Date().toISOString() })
    .eq('id', id);
  if(error) throw error;
}

async function loreDeleteEntry(id){
  const { error } = await loreSupabase.from('lore_entries').delete().eq('id', id);
  if(error) throw error;
}

async function loreUploadImage(file){
  const ext = (file.name.split('.').pop() || 'png').toLowerCase();
  const path = Date.now() + '-' + Math.random().toString(36).slice(2, 8) + '.' + ext;
  const { error } = await loreSupabase.storage.from(LORE_IMAGE_BUCKET).upload(path, file);
  if(error) throw error;
  const { data } = loreSupabase.storage.from(LORE_IMAGE_BUCKET).getPublicUrl(path);
  return data.publicUrl;
}

// ---------- markup parsing ----------

function loreEscapeHtml(str){
  return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function loreIsSafeUrl(url){
  return !/^\s*(javascript|data|vbscript):/i.test(url || '');
}

// Applies inline transforms (links, internal links) to already-escaped text.
function loreInline(escapedText){
  let out = escapedText;
  // [[Article Title]] -> internal cross-link via the existing lore_goto()
  out = out.replace(/\[\[([^\]]+)\]\]/g, (m, title) => {
    const clean = title.trim();
    return `<a href="#" onclick="return lore_goto('${clean.replace(/'/g, "\\'")}')">${clean}</a>`;
  });
  // [text](url) -> external link
  out = out.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (m, text, url) => {
    const cleanUrl = url.trim();
    if(!loreIsSafeUrl(cleanUrl)) return text;
    return `<a href="${loreEscapeHtml(cleanUrl)}" target="_blank" rel="noopener">${text}</a>`;
  });
  return out;
}

function loreParseImageLine(line){
  const m = line.match(/^!\[([^\]]*)\]\(([^)"]+)(?:\s+"([^"]*)")?\)\s*$/);
  if(!m) return null;
  const [, alt, url, caption] = m;
  if(!loreIsSafeUrl(url.trim())) return null;
  const imgTag = `<img src="${loreEscapeHtml(url.trim())}" alt="${loreEscapeHtml(alt)}">`;
  if(caption){
    return `<figure>${imgTag}<figcaption>${loreEscapeHtml(caption)}</figcaption></figure>`;
  }
  return imgTag;
}

function loreParseTable(lines){
  const parseRow = line => line.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim());
  const header = parseRow(lines[0]);
  const rows = lines.slice(2).map(parseRow);
  const thead = '<thead><tr>' + header.map(h => `<th>${loreInline(loreEscapeHtml(h))}</th>`).join('') + '</tr></thead>';
  const tbody = '<tbody>' + rows.map(r => '<tr>' + r.map(c => `<td>${loreInline(loreEscapeHtml(c))}</td>`).join('') + '</tr>').join('') + '</tbody>';
  return `<table>${thead}${tbody}</table>`;
}

function loreParseMarkup(source){
  const blocks = String(source || '').replace(/\r\n/g, '\n').split(/\n\s*\n/).map(b => b.trim()).filter(Boolean);

  return blocks.map(block => {
    const lines = block.split('\n');

    if(lines[0].startsWith('### ')){
      return `<h4>${loreInline(loreEscapeHtml(lines[0].slice(4).trim()))}</h4>`;
    }
    if(lines[0].startsWith('## ')){
      return `<h3>${loreInline(loreEscapeHtml(lines[0].slice(3).trim()))}</h3>`;
    }
    if(lines[0].startsWith('~ ')){
      return `<p class="lore-attribution">${loreInline(loreEscapeHtml(lines[0].slice(2).trim()))}</p>`;
    }
    if(lines.every(l => l.startsWith('>'))){
      let cite = '';
      const bodyLines = [];
      lines.forEach(l => {
        const content = l.replace(/^>\s?/, '');
        const citeMatch = content.match(/^(--|—)\s*(.+)$/);
        if(citeMatch) cite = citeMatch[2].trim();
        else bodyLines.push(content);
      });
      const body = loreInline(loreEscapeHtml(bodyLines.join(' ').trim()));
      return `<div class="lore-quote">${body}${cite ? `<cite>${loreInline(loreEscapeHtml(cite))}</cite>` : ''}</div>`;
    }
    if(lines.length === 1){
      const img = loreParseImageLine(lines[0]);
      if(img) return img;
    }
    if(lines.length >= 2 && lines[0].trim().startsWith('|') && /^[\s|:-]+$/.test(lines[1]) && lines[1].includes('-')){
      return loreParseTable(lines);
    }
    return `<p>${loreInline(loreEscapeHtml(lines.join(' ')))}</p>`;
  }).join('\n');
}

window.loreLoadEntries = loreLoadEntries;
window.loreGetEditorRole = loreGetEditorRole;
window.loreCreateEntry = loreCreateEntry;
window.loreUpdateEntry = loreUpdateEntry;
window.loreDeleteEntry = loreDeleteEntry;
window.loreUploadImage = loreUploadImage;
window.loreParseMarkup = loreParseMarkup;
window.loreEscapeHtml = loreEscapeHtml;

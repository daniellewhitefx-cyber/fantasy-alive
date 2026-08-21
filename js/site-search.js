
const SITE_SEARCH_ORDINAL_LEVEL_NAMES = {
  '1': '1st Level', '2': '2nd Level', '3': '3rd Level', '4': '4th Level',
  '5': '5th Level', '6': '6th Level', '7': '7th Level', '8': '8th Level', '9': '9th Level'
};

const SITE_SEARCH_SOURCES = [
  { type: 'Skill', url: 'skill-list.html', csv: 'https://docs.google.com/spreadsheets/d/1ywI52NIOEB6EKIe5WvLzerY6w0ZmU0bAkOrKq5ggrP8/export?format=csv', titleCol: 'name', groupCol: 'category' },
  { type: 'Recipe', url: 'recipes.html', csv: 'https://docs.google.com/spreadsheets/d/1ItjkOYamXrQ0vLIZlkdMCqwF0PGw0DV82J4bk9zhu3c/export?format=csv', titleCol: 'name', groupCol: 'category' },
  { type: 'Spell', url: 'spell-compendium.html', csv: 'https://docs.google.com/spreadsheets/d/1JEUuwBntPy8VxTATpzjb6juloHflbGBW4EgBXY7bSZE/export?format=csv', titleCol: 'name', groupCol: 'lvl',
    groupTransform: raw => SITE_SEARCH_ORDINAL_LEVEL_NAMES[(raw || '').trim()] || (raw || '').trim() || 'Unsorted' }
];
const SITE_SEARCH_LORE_URL = 'https://xdchluuvicuuqyqsejnq.supabase.co';
const SITE_SEARCH_LORE_KEY = 'sb_publishable_JL4nY9-fcOAwYzwpwiJa9w_nypZCt99';

let siteSearchIndex = null;
let siteSearchLoading = null;

function siteSearchParseCSV(text){
  const rows = [];
  let row = [], field = '', inQuotes = false;
  for(let i = 0; i < text.length; i++){
    const c = text[i];
    if(inQuotes){
      if(c === '"'){
        if(text[i + 1] === '"'){ field += '"'; i++; }
        else { inQuotes = false; }
      } else {
        field += c;
      }
    } else if(c === '"'){
      inQuotes = true;
    } else if(c === ','){
      row.push(field); field = '';
    } else if(c === '\n'){
      row.push(field); rows.push(row); row = []; field = '';
    } else if(c === '\r'){
    } else {
      field += c;
    }
  }
  if(field.length || row.length){ row.push(field); rows.push(row); }
  return rows;
}

async function siteSearchLoadCsvSource(source){
  const res = await fetch(source.csv, { cache: 'no-store' });
  if(!res.ok) throw new Error('Sheet request failed');
  const csvText = await res.text();
  const rows = siteSearchParseCSV(csvText).filter(r => r.some(cell => (cell || '').trim() !== ''));
  const header = (rows.shift() || []).map(h => h.trim().toLowerCase());
  const col = name => header.indexOf(name);
  const iTitle = col(source.titleCol);
  const iGroup = col(source.groupCol);

  return rows
    .map(r => {
      const rawGroup = (r[iGroup] || '').trim();
      return {
        type: source.type,
        title: (r[iTitle] || '').trim(),
        group: source.groupTransform ? source.groupTransform(rawGroup) : rawGroup,
        url: source.url
      };
    })
    .filter(e => e.title);
}

async function siteSearchLoadLore(){
  const res = await fetch(SITE_SEARCH_LORE_URL + '/rest/v1/lore_entries?select=title,category&order=title.asc', {
    headers: { apikey: SITE_SEARCH_LORE_KEY, Authorization: 'Bearer ' + SITE_SEARCH_LORE_KEY }
  });
  if(!res.ok) throw new Error('Lore request failed');
  const rows = await res.json();
  return rows.map(r => ({ type: 'Lore', title: r.title, group: r.category, url: 'lore.html' }));
}

async function siteSearchBuildIndex(){
  if(siteSearchIndex) return siteSearchIndex;
  if(siteSearchLoading) return siteSearchLoading;

  siteSearchLoading = Promise.allSettled([
    ...SITE_SEARCH_SOURCES.map(siteSearchLoadCsvSource),
    siteSearchLoadLore()
  ]).then(results => {
    siteSearchIndex = results
      .filter(r => r.status === 'fulfilled')
      .flatMap(r => r.value);
    return siteSearchIndex;
  });

  return siteSearchLoading;
}

function siteSearchEscapeHtml(str){
  return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function siteSearchResultUrl(entry){
  return entry.url + '?open=' + encodeURIComponent(entry.title) + '&cat=' + encodeURIComponent(entry.group || '');
}

async function siteSearchRun(query){
  const resultsEl = document.getElementById('site-search-results');
  const q = query.trim().toLowerCase();
  if(!q){ resultsEl.innerHTML = ''; return; }

  resultsEl.innerHTML = '<p class="site-search-empty">Searching&hellip;</p>';
  const index = await siteSearchBuildIndex();

  const matches = index
    .map(e => {
      const lower = e.title.toLowerCase();
      if(!lower.includes(q)) return null;
      return { ...e, rank: lower.startsWith(q) ? 0 : 1 };
    })
    .filter(Boolean)
    .sort((a, b) => a.rank - b.rank || a.title.localeCompare(b.title))
    .slice(0, 30);

  if(!matches.length){
    resultsEl.innerHTML = '<p class="site-search-empty">No results for &ldquo;' + siteSearchEscapeHtml(query.trim()) + '&rdquo;.</p>';
    return;
  }

  resultsEl.innerHTML = matches.map(m => `
    <a class="site-search-result" href="${siteSearchResultUrl(m)}">
      <span class="ssr-type">${siteSearchEscapeHtml(m.type)}</span>
      <span class="ssr-title">${siteSearchEscapeHtml(m.title)}</span>
      <span class="ssr-group">${siteSearchEscapeHtml(m.group || '')}</span>
    </a>
  `).join('');
}

let siteSearchDebounce = null;
function siteSearchOnInput(value){
  clearTimeout(siteSearchDebounce);
  siteSearchDebounce = setTimeout(() => siteSearchRun(value), 150);
}

function siteSearchOpen(){
  document.getElementById('site-search-overlay').style.display = 'flex';
  const input = document.getElementById('site-search-input');
  input.value = '';
  document.getElementById('site-search-results').innerHTML = '';
  setTimeout(() => input.focus(), 10);
  document.addEventListener('keydown', siteSearchEscHandler);
}

function siteSearchClose(){
  document.getElementById('site-search-overlay').style.display = 'none';
  document.removeEventListener('keydown', siteSearchEscHandler);
}

function siteSearchEscHandler(e){
  if(e.key === 'Escape') siteSearchClose();
}

function siteSearchBackdropClick(e){
  if(e.target.id === 'site-search-overlay') siteSearchClose();
}

function siteSearchInjectUI(){
  if(document.getElementById('site-search-overlay')) return;
  const overlay = document.createElement('div');
  overlay.id = 'site-search-overlay';
  overlay.className = 'site-search-overlay';
  overlay.onclick = siteSearchBackdropClick;
  overlay.innerHTML = `
    <div class="site-search-panel">
      <input type="text" id="site-search-input" class="site-search-input" placeholder="Search skills, recipes, spells, lore&hellip;" oninput="siteSearchOnInput(this.value)">
      <div id="site-search-results" class="site-search-results"></div>
    </div>
  `;
  document.body.appendChild(overlay);

  const btn = document.getElementById('site-search-btn');
  if(btn) btn.addEventListener('click', siteSearchOpen);
}

siteSearchInjectUI();

window.siteSearchOpen = siteSearchOpen;
window.siteSearchClose = siteSearchClose;
window.siteSearchOnInput = siteSearchOnInput;

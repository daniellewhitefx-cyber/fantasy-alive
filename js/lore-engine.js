(function(){
// Fixed display order for categories; anything not listed falls to the end, alphabetically
const CATEGORY_ORDER = [
  'Getting Started', 'History', 'Kingdoms & Regions', 'Towns & Settlements',
  'Cosmology & Planes', 'Mortal Races', 'Other Beings', 'Deities',
  'Magic', 'Crafting & Trade', 'Culture & Society'
];

let articles = []; // populated by loadAllArticles(): { category, title, file, html, key }
let activeKey = null;

async function loadAllArticles(){
  const loaded = await Promise.all(LORE_MANIFEST.map(async entry => {
    try{
      const res = await fetch(entry.file);
      if(!res.ok) throw new Error(res.status);
      const html = await res.text();
      return { ...entry, html, key: entry.category + '||' + entry.title };
    } catch(err){
      console.error('Could not load lore article:', entry.file, err);
      return { ...entry, html: '<p>This article failed to load.</p>', key: entry.category + '||' + entry.title };
    }
  }));
  articles = loaded;
}

function lore_selectItem(key){
  activeKey = key;
  const searchInput = document.getElementById('lore-search-input');
  if(searchInput) searchInput.value = '';
  renderDisplay();
  renderSidebar();
}

function lore_toggleCat(catName){
  const el = document.querySelector(`.lore-cat[data-cat="${CSS.escape(catName)}"]`);
  if(el) el.classList.toggle('open');
}

function byCategory(){
  const grouped = {};
  articles.forEach(a => {
    if(!grouped[a.category]) grouped[a.category] = [];
    grouped[a.category].push(a);
  });
  return grouped;
}

function orderedCategories(grouped){
  const known = CATEGORY_ORDER.filter(c => grouped[c]);
  const unknown = Object.keys(grouped).filter(c => !CATEGORY_ORDER.includes(c)).sort();
  return [...known, ...unknown];
}

function renderSidebar(){
  const grouped = byCategory();
  const cats = orderedCategories(grouped);
  const target = document.getElementById('lore-sidebar-content');

  if(cats.length === 0){
    target.innerHTML = '<p class="lore-empty" style="padding:1rem;">No lore items found yet.</p>';
    return;
  }

  target.innerHTML = cats.map(cat => {
    const items = grouped[cat];
    const isOpenAlready = document.querySelector(`.lore-cat[data-cat="${CSS.escape(cat)}"]`)?.classList.contains('open');
    const containsActive = items.some(i => i.key === activeKey);
    const shouldOpen = isOpenAlready || containsActive;
    return `
      <div class="lore-cat ${shouldOpen ? 'open' : ''}" data-cat="${cat}">
        <button class="lore-cat-header" onclick="lore_toggleCat('${cat.replace(/'/g, "\\'")}')">
          <span>${cat}</span><span class="chev">&#9656;</span>
        </button>
        <div class="lore-cat-items">
          ${items.map(i => `<button class="${i.key===activeKey?'active':''}" onclick="lore_selectItem('${i.key.replace(/'/g, "\\'")}')">${i.title}</button>`).join('')}
        </div>
      </div>`;
  }).join('');
}

function escapeHtml(str){
  return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function stripTags(html){
  const div = document.createElement('div');
  div.innerHTML = html;
  return div.textContent.replace(/\s+/g, ' ').trim();
}

function makeExcerpt(text, query){
  const lower = text.toLowerCase();
  const idx = lower.indexOf(query.toLowerCase());
  if(idx === -1) return escapeHtml(text.slice(0, 140)) + (text.length > 140 ? '&hellip;' : '');
  const start = Math.max(0, idx - 50);
  const end = Math.min(text.length, idx + query.length + 90);
  const before = escapeHtml(text.slice(start, idx));
  const match = escapeHtml(text.slice(idx, idx + query.length));
  const after = escapeHtml(text.slice(idx + query.length, end));
  return (start > 0 ? '&hellip;' : '') + before + '<mark>' + match + '</mark>' + after + (end < text.length ? '&hellip;' : '');
}

function lore_search(rawQuery){
  const query = rawQuery.trim();
  const target = document.getElementById('lore-sidebar-content');

  if(!query){
    renderSidebar();
    return;
  }

  const lowerQuery = query.toLowerCase();

  const results = articles.map(a => {
    const bodyText = stripTags(a.html);
    const titleMatch = a.title.toLowerCase().includes(lowerQuery);
    const bodyMatch = bodyText.toLowerCase().includes(lowerQuery);
    if(!titleMatch && !bodyMatch) return null;
    return { key: a.key, title: a.title, cat: a.category, bodyText, rank: titleMatch ? 0 : 1 };
  }).filter(Boolean).sort((a, b) => a.rank - b.rank || a.title.localeCompare(b.title));

  if(results.length === 0){
    target.innerHTML = '<p class="lore-search-empty">No results for &ldquo;' + escapeHtml(query) + '&rdquo;.</p>';
    return;
  }

  target.innerHTML = '<div class="lore-search-results">' + results.map(r => `
    <button class="lore-search-result" onclick="lore_selectItem('${r.key.replace(/'/g, "\\'")}')">
      <div class="lsr-cat">${escapeHtml(r.cat)}</div>
      <div class="lsr-title">${escapeHtml(r.title)}</div>
      <div class="lsr-excerpt">${r.rank === 0 ? escapeHtml(r.bodyText.slice(0, 140)) + (r.bodyText.length > 140 ? '&hellip;' : '') : makeExcerpt(r.bodyText, query)}</div>
    </button>
  `).join('') + '</div>';
}

function renderDisplay(){
  const display = document.getElementById('lore-display');
  const found = articles.find(a => a.key === activeKey);

  if(!found){
    display.innerHTML = '<p class="lore-empty">Select a topic from the list to begin reading.</p>';
    return;
  }

  display.innerHTML = `<h2>${found.title}</h2>` + found.html;
}

function lore_goto(title){
  const match = articles.find(a => a.title.toLowerCase() === title.toLowerCase());
  if(match){
    lore_selectItem(match.key);
    document.getElementById('lore-display').scrollIntoView({behavior:'smooth', block:'start'});
  } else {
    alert('That article isn\'t available yet: ' + title);
  }
  return false;
}

function lore_toggleDark(){
  const page = document.getElementById('lore-page');
  const btn = document.getElementById('lore-dark-toggle');
  const isDark = page.classList.toggle('lore-dark');
  btn.classList.toggle('on', isDark);
  try{ localStorage.setItem('fa-lore-dark', isDark ? '1' : '0'); }catch(e){}
}

window.lore_selectItem = lore_selectItem;
window.lore_toggleCat = lore_toggleCat;
window.lore_search = lore_search;
window.lore_goto = lore_goto;
window.lore_toggleDark = lore_toggleDark;

async function init(){
  document.getElementById('lore-sidebar-content').innerHTML = '<p class="lore-empty" style="padding:1rem;">Loading&hellip;</p>';
  await loadAllArticles();
  renderSidebar();
  renderDisplay();
  let savedDark = false;
  try{ savedDark = localStorage.getItem('fa-lore-dark') === '1'; }catch(e){}
  if(savedDark){
    document.getElementById('lore-page').classList.add('lore-dark');
    document.getElementById('lore-dark-toggle').classList.add('on');
  }
}

if(document.readyState === 'loading'){
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
})();

(function(){
const CATEGORY_ORDER = [
  'Getting Started', 'History', 'Kingdoms & Regions', 'Towns & Settlements',
  'Cosmology & Planes', 'Mortal Races', 'Other Beings', 'Deities',
  'Magic', 'Crafting & Trade', 'Culture & Society'
];

let articles = [];
let activeKey = null;
let editorUser = null;

async function loadAllArticles(){
  const rows = await loreLoadEntries();
  articles = rows.map(row => ({
    ...row,
    html: loreParseMarkup(row.body),
    key: row.id
  }));
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
          ${items.map(i => `<button class="${i.key===activeKey?'active':''}" onclick="lore_selectItem('${i.key}')">${i.title}</button>`).join('')}
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
    <button class="lore-search-result" onclick="lore_selectItem('${r.key}')">
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

  const editorControls = (editorUser && editorUser.isEditor)
    ? `<div class="lore-editor-controls">
         <button class="lore-editor-btn" onclick="lore_openEditor('${found.key}')">Edit Entry</button>
         <button class="lore-editor-btn danger" onclick="lore_confirmDelete('${found.key}')">Delete Entry</button>
       </div>`
    : '';

  display.innerHTML = `<div class="lore-article-head"><h2>${found.title}</h2>${editorControls}</div>` + found.html;
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

function renderAddButton(){
  const target = document.getElementById('lore-add-entry-wrap');
  if(!target) return;
  target.innerHTML = (editorUser && editorUser.isEditor)
    ? `<button class="lore-editor-btn add" onclick="lore_openEditor(null)">+ Add Entry</button>`
    : '';
}

function lore_openEditor(key){
  const existing = key ? articles.find(a => a.key === key) : null;
  const modal = document.getElementById('lore-editor-modal');

  const categories = [...new Set([...CATEGORY_ORDER, ...articles.map(a => a.category)])];

  modal.innerHTML = `
    <div class="lore-modal-backdrop" onclick="lore_closeEditor()"></div>
    <div class="lore-modal">
      <h3>${existing ? 'Edit Entry' : 'Add Entry'}</h3>

      <label class="lore-field-label" for="lore-edit-title">Title</label>
      <input type="text" id="lore-edit-title" value="${existing ? loreEscapeHtml(existing.title) : ''}">

      <label class="lore-field-label" for="lore-edit-category">Category</label>
      <input type="text" id="lore-edit-category" list="lore-category-options" value="${existing ? loreEscapeHtml(existing.category) : ''}">
      <datalist id="lore-category-options">
        ${categories.map(c => `<option value="${loreEscapeHtml(c)}">`).join('')}
      </datalist>

      <label class="lore-field-label" for="lore-edit-body">Content</label>
      <div class="lore-editor-help">
        Blank line = new paragraph &bull; <code>## Heading</code> &bull; <code>&gt; quote</code> then <code>&gt; -- who said it</code> &bull;
        <code>[[Other Article]]</code> to link another entry (or <code>[[Other Article|display text]]</code> to show
        different text) &bull; <code>[text](url)</code> for a link &bull;
        <code>![alt](image url)</code> for an image &bull; <code>~ credit line</code><br>
        Image layout: add <code>float-left</code>, <code>float-right</code>, or <code>small</code> after the image url (and after
        the caption, if there is one) to make it smaller and sit beside the text instead of full-width, e.g.
        <code>![alt](image url float-left)</code>
      </div>
      <textarea id="lore-edit-body" rows="14">${existing ? loreEscapeHtml(existing.body) : ''}</textarea>

      <div class="lore-editor-image-row">
        <input type="file" id="lore-edit-image-file" accept="image/*">
        <select id="lore-edit-image-layout">
          <option value="">Full width</option>
          <option value="float-left">Float left (small)</option>
          <option value="float-right">Float right (small)</option>
          <option value="small">Small, centered</option>
        </select>
        <button class="lore-editor-btn" onclick="lore_uploadImageIntoBody()">Upload Image</button>
        <span id="lore-edit-image-status"></span>
      </div>

      <p class="lore-editor-error" id="lore-edit-error" style="display:none;"></p>

      <div class="lore-modal-actions">
        <button class="lore-editor-btn" onclick="lore_closeEditor()">Cancel</button>
        <button class="lore-editor-btn add" id="lore-edit-save-btn" onclick="lore_saveEditor('${existing ? existing.key : ''}')">Save</button>
      </div>
    </div>
  `;
  modal.style.display = 'block';
}

function lore_closeEditor(){
  const modal = document.getElementById('lore-editor-modal');
  modal.style.display = 'none';
  modal.innerHTML = '';
}

async function lore_uploadImageIntoBody(){
  const fileInput = document.getElementById('lore-edit-image-file');
  const status = document.getElementById('lore-edit-image-status');
  const file = fileInput.files[0];
  if(!file){
    status.textContent = 'Choose a file first.';
    return;
  }
  status.textContent = 'Uploading...';
  try{
    const url = await loreUploadImage(file);
    const layout = document.getElementById('lore-edit-image-layout').value;
    const textarea = document.getElementById('lore-edit-body');
    const markup = `![${file.name.replace(/\.[^.]+$/, '')}](${url}${layout ? ' ' + layout : ''})`;
    const pos = textarea.selectionStart || textarea.value.length;
    textarea.value = textarea.value.slice(0, pos) + '\n\n' + markup + '\n\n' + textarea.value.slice(pos);
    status.textContent = 'Image added below - move the line if you want it elsewhere.';
    fileInput.value = '';
  } catch(err){
    status.textContent = 'Upload failed. Try again.';
  }
}

async function lore_saveEditor(key){
  const title = document.getElementById('lore-edit-title').value.trim();
  const category = document.getElementById('lore-edit-category').value.trim();
  const body = document.getElementById('lore-edit-body').value.trim();
  const errorEl = document.getElementById('lore-edit-error');
  const saveBtn = document.getElementById('lore-edit-save-btn');
  errorEl.style.display = 'none';

  if(!title || !category || !body){
    errorEl.textContent = 'Title, category, and content are all required.';
    errorEl.style.display = 'block';
    return;
  }

  saveBtn.disabled = true;
  saveBtn.textContent = 'Saving...';
  try{
    if(key){
      await loreUpdateEntry(key, { title, category, body });
    } else {
      await loreCreateEntry({ title, category, body });
    }
    lore_closeEditor();
    await loadAllArticles();
    const saved = articles.find(a => a.title === title);
    activeKey = saved ? saved.key : activeKey;
    renderSidebar();
    renderDisplay();
  } catch(err){
    errorEl.textContent = 'Could not save: ' + (err.message || 'unknown error');
    errorEl.style.display = 'block';
    saveBtn.disabled = false;
    saveBtn.textContent = 'Save';
  }
}

function lore_confirmDelete(key){
  const found = articles.find(a => a.key === key);
  if(!found) return;
  if(!confirm(`Delete "${found.title}"? This can't be undone.`)) return;
  lore_deleteEntry(key);
}

async function lore_deleteEntry(key){
  try{
    await loreDeleteEntry(key);
    activeKey = null;
    await loadAllArticles();
    renderSidebar();
    renderDisplay();
  } catch(err){
    alert('Could not delete this entry: ' + (err.message || 'unknown error'));
  }
}

window.lore_selectItem = lore_selectItem;
window.lore_toggleCat = lore_toggleCat;
window.lore_search = lore_search;
window.lore_goto = lore_goto;
window.lore_toggleDark = lore_toggleDark;
window.lore_openEditor = lore_openEditor;
window.lore_closeEditor = lore_closeEditor;
window.lore_uploadImageIntoBody = lore_uploadImageIntoBody;
window.lore_saveEditor = lore_saveEditor;
window.lore_confirmDelete = lore_confirmDelete;

async function init(){
  document.getElementById('lore-sidebar-content').innerHTML = '<p class="lore-empty" style="padding:1rem;">Loading&hellip;</p>';

  try{
    editorUser = await loreGetEditorRole();
  } catch(err){
    editorUser = null;
  }
  renderAddButton();

  await loadAllArticles();
  renderSidebar();
  renderDisplay();

  const openTitle = new URLSearchParams(location.search).get('open');
  if(openTitle) lore_goto(openTitle);

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

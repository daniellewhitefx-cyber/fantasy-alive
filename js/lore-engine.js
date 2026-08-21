(function(){
const CATEGORY_ORDER = [
  'Getting Started', 'History', 'Kingdoms & Regions', 'Towns & Settlements',
  'Cosmology & Planes', 'Mortal Races', 'Other Beings', 'Deities',
  'Magic', 'Crafting & Trade', 'Culture & Society'
];

let articles = [];
let activeKey = null;
let editorUser = null;
let titleToSlugMap = {};

async function loadAllArticles(){
  const rows = await loreLoadEntries();
  const allTitles = rows.map(row => row.title);
  titleToSlugMap = {};
  rows.forEach(row => { titleToSlugMap[row.title.toLowerCase()] = row.slug; });
  articles = rows.map(row => ({
    ...row,
    html: row.body_format === 'html'
      ? loreRenderHtmlBody(row.body, row.title, allTitles, titleToSlugMap)
      : loreParseMarkup(row.body, row.title, allTitles, titleToSlugMap),
    key: row.id
  }));
}

function findArticleBySlugOrTitle(value){
  if(!value) return null;
  const v = String(value).trim().toLowerCase();
  return articles.find(a => (a.slug || '').toLowerCase() === v)
    || articles.find(a => a.title.toLowerCase() === v)
    || null;
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

  const canReorder = !!(editorUser && editorUser.isEditor);

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
          ${items.map((i, idx) => `
            <div class="lore-item-row">
              <a href="lore.html?open=${encodeURIComponent(i.slug)}" class="${i.key===activeKey?'active':''}" onclick="return lore_goto(event, '${(i.slug || '').replace(/'/g, "\\'")}')">${i.title}</a>
              ${canReorder ? `
                <span class="lore-reorder-btns">
                  <button type="button" class="lore-reorder-btn" title="Move up" ${idx===0?'disabled':''} onclick="lore_moveEntry('${i.key}','up')">&#9650;</button>
                  <button type="button" class="lore-reorder-btn" title="Move down" ${idx===items.length-1?'disabled':''} onclick="lore_moveEntry('${i.key}','down')">&#9660;</button>
                </span>` : ''}
            </div>`).join('')}
        </div>
      </div>`;
  }).join('');
}

async function lore_moveEntry(key, dir){
  const grouped = byCategory();
  const found = articles.find(a => a.key === key);
  if(!found) return;
  const items = grouped[found.category];
  const idx = items.findIndex(i => i.key === key);
  const swapIdx = dir === 'up' ? idx - 1 : idx + 1;
  if(idx === -1 || swapIdx < 0 || swapIdx >= items.length) return;
  const a = items[idx], b = items[swapIdx];
  try{
    await loreSwapOrder(a.id, a.sort_order, b.id, b.sort_order);
    await loadAllArticles();
    renderSidebar();
    renderDisplay();
  } catch(err){
    alert('Could not reorder: ' + (err.message || 'unknown error'));
  }
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
    return { key: a.key, slug: a.slug, title: a.title, cat: a.category, bodyText, rank: titleMatch ? 0 : 1 };
  }).filter(Boolean).sort((a, b) => a.rank - b.rank || a.title.localeCompare(b.title));

  if(results.length === 0){
    target.innerHTML = '<p class="lore-search-empty">No results for &ldquo;' + escapeHtml(query) + '&rdquo;.</p>';
    return;
  }

  target.innerHTML = '<div class="lore-search-results">' + results.map(r => `
    <a class="lore-search-result" href="lore.html?open=${encodeURIComponent(r.slug)}" onclick="return lore_goto(event, '${(r.slug || '').replace(/'/g, "\\'")}')">
      <div class="lsr-cat">${escapeHtml(r.cat)}</div>
      <div class="lsr-title">${escapeHtml(r.title)}</div>
      <div class="lsr-excerpt">${r.rank === 0 ? escapeHtml(r.bodyText.slice(0, 140)) + (r.bodyText.length > 140 ? '&hellip;' : '') : makeExcerpt(r.bodyText, query)}</div>
    </a>
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

function lore_openArticle(match, opts){
  opts = opts || {};
  lore_selectItem(match.key);
  if(opts.updateUrl !== false){
    history.pushState(null, '', 'lore.html?open=' + encodeURIComponent(match.slug));
  }
  document.getElementById('lore-display').scrollIntoView({behavior:'smooth', block:'start'});
}

function lore_goto(event, value){
  if(event && (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)) return true;
  if(event) event.preventDefault();
  const match = findArticleBySlugOrTitle(value);
  if(match){
    lore_openArticle(match);
  } else {
    alert('That article isn\'t available yet: ' + value);
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

let richSelectedImage = null;
let richHandleEl = null;
let richImgToolbarEl = null;
let richResizeStart = null;
let richSelectedLink = null;
let richLinkToolbarEl = null;

function lore_openEditor(key){
  const existing = key ? articles.find(a => a.key === key) : null;
  const modal = document.getElementById('lore-editor-modal');

  const categories = [...new Set([...CATEGORY_ORDER, ...articles.map(a => a.category)])];

  let seedHtml = '';
  if(existing){
    seedHtml = existing.body_format === 'html'
      ? loreSanitizeHtml(existing.body)
      : loreParseMarkup(existing.body, existing.title, articles.map(a => a.title), titleToSlugMap);
  }

  modal.innerHTML = `
    <div class="lore-modal-backdrop" onclick="lore_closeEditor()"></div>
    <div class="lore-modal lore-modal-wide">
      <h3>${existing ? 'Edit Entry' : 'Add Entry'}</h3>

      <label class="lore-field-label" for="lore-edit-title">Title</label>
      <input type="text" id="lore-edit-title" value="${existing ? loreEscapeHtml(existing.title) : ''}">

      <label class="lore-field-label" for="lore-edit-category">Category</label>
      <input type="text" id="lore-edit-category" list="lore-category-options" value="${existing ? loreEscapeHtml(existing.category) : ''}">
      <datalist id="lore-category-options">
        ${categories.map(c => `<option value="${loreEscapeHtml(c)}">`).join('')}
      </datalist>

      <label class="lore-field-label">Content</label>
      <div class="lore-rich-toolbar">
        <button type="button" class="lore-rich-btn" title="Bold" onmousedown="event.preventDefault()" onclick="lore_richExec('bold')"><b>B</b></button>
        <button type="button" class="lore-rich-btn" title="Italic" onmousedown="event.preventDefault()" onclick="lore_richExec('italic')"><i>I</i></button>
        <span class="lore-rich-sep"></span>
        <button type="button" class="lore-rich-btn" title="Heading" onmousedown="event.preventDefault()" onclick="lore_richExec('formatBlock', 'H3')">H3</button>
        <button type="button" class="lore-rich-btn" title="Subheading" onmousedown="event.preventDefault()" onclick="lore_richExec('formatBlock', 'H4')">H4</button>
        <button type="button" class="lore-rich-btn" title="Paragraph text" onmousedown="event.preventDefault()" onclick="lore_richExec('formatBlock', 'P')">&para;</button>
        <span class="lore-rich-sep"></span>
        <button type="button" class="lore-rich-btn" title="Bullet list" onmousedown="event.preventDefault()" onclick="lore_richExec('insertUnorderedList')">&bull; List</button>
        <button type="button" class="lore-rich-btn" title="Numbered list" onmousedown="event.preventDefault()" onclick="lore_richExec('insertOrderedList')">1. List</button>
        <button type="button" class="lore-rich-btn" title="Quote" onmousedown="event.preventDefault()" onclick="lore_richExec('formatBlock', 'BLOCKQUOTE')">&ldquo;Quote&rdquo;</button>
        <span class="lore-rich-sep"></span>
        <button type="button" class="lore-rich-btn" title="Insert table" onmousedown="event.preventDefault()" onclick="lore_richInsertTable()">Table</button>
        <button type="button" class="lore-rich-btn" title="Insert link" onmousedown="event.preventDefault()" onclick="lore_richInsertLink()">Link</button>
        <button type="button" class="lore-rich-btn" title="Insert image" onmousedown="event.preventDefault()" onclick="document.getElementById('lore-edit-image-file').click()">Image</button>
        <input type="file" id="lore-edit-image-file" accept="image/*" style="display:none" onchange="lore_richHandleFileInput(this)">
      </div>
      <div class="lore-editor-help">
        Type like a normal document &bull; drag and drop or paste an image straight into the box &bull;
        click an image to resize it (drag the corner handle) or change how text wraps around it &bull;
        click a link to edit its URL or remove it &bull;
        mentioning another lore article by name links it automatically, no need to do anything special.
      </div>
      <div id="lore-edit-body-rich" class="lore-rich-editor" contenteditable="true">${seedHtml}</div>
      <span id="lore-edit-image-status"></span>

      <p class="lore-editor-error" id="lore-edit-error" style="display:none;"></p>

      <div class="lore-modal-actions">
        <button class="lore-editor-btn" onclick="lore_closeEditor()">Cancel</button>
        <button class="lore-editor-btn add" id="lore-edit-save-btn" onclick="lore_saveEditor('${existing ? existing.key : ''}')">Save</button>
      </div>
    </div>
  `;
  modal.style.display = 'block';

  const richEditor = document.getElementById('lore-edit-body-rich');
  richEditor.querySelectorAll('img').forEach(img => { img.draggable = false; });
  richEditor.addEventListener('dragover', lore_richDragOver);
  richEditor.addEventListener('drop', lore_richDrop);
  richEditor.addEventListener('paste', lore_richPaste);
  richEditor.addEventListener('click', lore_richEditorClick);
  document.addEventListener('scroll', lore_richRepositionHandle, true);
  window.addEventListener('resize', lore_richRepositionHandle);
}

function lore_closeEditor(){
  lore_richDeselectImage();
  lore_richDeselectLink();
  if(richHandleEl){ richHandleEl.remove(); richHandleEl = null; }
  if(richImgToolbarEl){ richImgToolbarEl.remove(); richImgToolbarEl = null; }
  if(richLinkToolbarEl){ richLinkToolbarEl.remove(); richLinkToolbarEl = null; }
  document.removeEventListener('scroll', lore_richRepositionHandle, true);
  window.removeEventListener('resize', lore_richRepositionHandle);
  const modal = document.getElementById('lore-editor-modal');
  modal.style.display = 'none';
  modal.innerHTML = '';
}

function lore_richExec(cmd, value){
  document.getElementById('lore-edit-body-rich').focus();
  document.execCommand(cmd, false, value || null);
}

function lore_richInsertTable(){
  const rows = parseInt(prompt('How many rows?', '2'), 10);
  if(!rows || rows < 1) return;
  const cols = parseInt(prompt('How many columns?', '2'), 10);
  if(!cols || cols < 1) return;
  let html = '<table><thead><tr>';
  for(let c = 0; c < cols; c++) html += '<th>Header</th>';
  html += '</tr></thead><tbody>';
  for(let r = 0; r < rows; r++){
    html += '<tr>';
    for(let c = 0; c < cols; c++) html += '<td>&nbsp;</td>';
    html += '</tr>';
  }
  html += '</tbody></table><p><br></p>';
  document.getElementById('lore-edit-body-rich').focus();
  document.execCommand('insertHTML', false, html);
}

function lore_richInsertLink(){
  const url = (prompt('Link URL (https://...)') || '').trim();
  if(!url) return;
  if(!loreIsSafeUrl(url)){
    alert("That URL isn't allowed.");
    return;
  }
  const richEditor = document.getElementById('lore-edit-body-rich');
  richEditor.focus();
  const sel = document.getSelection();
  if(sel && sel.toString().trim()){
    document.execCommand('createLink', false, url);
  } else {
    document.execCommand('insertHTML', false, `<a href="${loreEscapeHtml(url)}">${loreEscapeHtml(url)}</a>`);
  }
}

async function lore_richInsertImageFile(file){
  const status = document.getElementById('lore-edit-image-status');
  if(!file || !file.type || !file.type.startsWith('image/')) return;
  status.textContent = 'Uploading image...';
  try{
    const url = await loreUploadImage(file);
    const richEditor = document.getElementById('lore-edit-body-rich');
    richEditor.focus();
    document.execCommand('insertHTML', false, `<img src="${loreEscapeHtml(url)}" alt="" draggable="false" style="width: 100%;">`);
    status.textContent = '';
  } catch(err){
    status.textContent = 'Image upload failed. Try again.';
  }
}

function lore_richHandleFileInput(input){
  const file = input.files[0];
  input.value = '';
  if(file) lore_richInsertImageFile(file);
}

function lore_richDragOver(e){
  e.preventDefault();
}

function lore_richDrop(e){
  if(e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length){
    e.preventDefault();
    lore_richInsertImageFile(e.dataTransfer.files[0]);
    return;
  }
  if(e.dataTransfer){
    e.preventDefault();
    const text = e.dataTransfer.getData('text/plain');
    if(text) document.execCommand('insertText', false, text);
  }
}

function lore_richPaste(e){
  const items = e.clipboardData && e.clipboardData.items;
  if(items){
    for(const item of items){
      if(item.type && item.type.startsWith('image/')){
        e.preventDefault();
        lore_richInsertImageFile(item.getAsFile());
        return;
      }
    }
  }
  const text = e.clipboardData ? e.clipboardData.getData('text/plain') : '';
  if(text){
    e.preventDefault();
    document.execCommand('insertText', false, text);
  }
}

function lore_richEditorClick(e){
  const richEditor = document.getElementById('lore-edit-body-rich');
  const link = e.target.closest ? e.target.closest('a') : null;
  if(e.target.tagName === 'IMG'){
    lore_richDeselectLink();
    lore_richSelectImage(e.target);
  } else if(link && richEditor.contains(link)){
    lore_richDeselectImage();
    lore_richSelectLink(link);
  } else {
    lore_richDeselectImage();
    lore_richDeselectLink();
  }
}

function lore_richSelectImage(img){
  richSelectedImage = img;
  img.classList.add('lore-rich-img-selected');
  if(!richHandleEl){
    richHandleEl = document.createElement('div');
    richHandleEl.className = 'lore-rich-img-handle';
    richHandleEl.addEventListener('mousedown', lore_richResizeStart);
    document.body.appendChild(richHandleEl);
  }
  if(!richImgToolbarEl){
    richImgToolbarEl = document.createElement('div');
    richImgToolbarEl.className = 'lore-rich-img-toolbar';
    richImgToolbarEl.innerHTML = `
      <button type="button" onmousedown="event.preventDefault()" onclick="lore_richSetImageAlign('none')">Full width</button>
      <button type="button" onmousedown="event.preventDefault()" onclick="lore_richSetImageAlign('left')">Float left</button>
      <button type="button" onmousedown="event.preventDefault()" onclick="lore_richSetImageAlign('right')">Float right</button>
      <button type="button" class="lore-rich-img-remove" onmousedown="event.preventDefault()" onclick="lore_richRemoveImage()">Remove</button>
    `;
    document.body.appendChild(richImgToolbarEl);
  }
  richHandleEl.style.display = 'block';
  richImgToolbarEl.style.display = 'flex';
  lore_richRepositionHandle();
}

function lore_richDeselectImage(){
  if(richSelectedImage) richSelectedImage.classList.remove('lore-rich-img-selected');
  richSelectedImage = null;
  if(richHandleEl) richHandleEl.style.display = 'none';
  if(richImgToolbarEl) richImgToolbarEl.style.display = 'none';
}

function lore_richRepositionHandle(){
  if(richSelectedImage && richHandleEl){
    const rect = richSelectedImage.getBoundingClientRect();
    richHandleEl.style.left = (rect.right - 8) + 'px';
    richHandleEl.style.top = (rect.bottom - 8) + 'px';
    richImgToolbarEl.style.left = Math.max(4, rect.left) + 'px';
    richImgToolbarEl.style.top = Math.max(4, rect.top - 42) + 'px';
  }
  if(richSelectedLink && richLinkToolbarEl){
    const rect = richSelectedLink.getBoundingClientRect();
    richLinkToolbarEl.style.left = Math.max(4, rect.left) + 'px';
    richLinkToolbarEl.style.top = Math.max(4, rect.top - 42) + 'px';
  }
}

function lore_richSelectLink(link){
  richSelectedLink = link;
  link.classList.add('lore-rich-link-selected');
  if(!richLinkToolbarEl){
    richLinkToolbarEl = document.createElement('div');
    richLinkToolbarEl.className = 'lore-rich-img-toolbar';
    richLinkToolbarEl.innerHTML = `
      <button type="button" onmousedown="event.preventDefault()" onclick="lore_richEditLinkUrl()">Edit URL</button>
      <button type="button" class="lore-rich-img-remove" onmousedown="event.preventDefault()" onclick="lore_richRemoveLink()">Remove Link</button>
    `;
    document.body.appendChild(richLinkToolbarEl);
  }
  richLinkToolbarEl.style.display = 'flex';
  lore_richRepositionHandle();
}

function lore_richDeselectLink(){
  if(richSelectedLink) richSelectedLink.classList.remove('lore-rich-link-selected');
  richSelectedLink = null;
  if(richLinkToolbarEl) richLinkToolbarEl.style.display = 'none';
}

function lore_richEditLinkUrl(){
  if(!richSelectedLink) return;
  const current = richSelectedLink.getAttribute('href') || '';
  const url = (prompt('Link URL (https://...)', current) || '').trim();
  if(!url) return;
  if(!loreIsSafeUrl(url)){
    alert("That URL isn't allowed.");
    return;
  }
  richSelectedLink.setAttribute('href', url);
  richSelectedLink.removeAttribute('onclick');
  lore_richRepositionHandle();
}

function lore_richRemoveLink(){
  if(!richSelectedLink) return;
  const parent = richSelectedLink.parentNode;
  if(parent){
    while(richSelectedLink.firstChild) parent.insertBefore(richSelectedLink.firstChild, richSelectedLink);
    parent.removeChild(richSelectedLink);
  }
  lore_richDeselectLink();
}

function lore_richResizeStart(e){
  if(!richSelectedImage) return;
  e.preventDefault();
  const rect = richSelectedImage.getBoundingClientRect();
  richResizeStart = { x: e.clientX, width: rect.width };
  document.addEventListener('mousemove', lore_richResizeMove);
  document.addEventListener('mouseup', lore_richResizeEnd);
}

function lore_richResizeMove(e){
  if(!richSelectedImage || !richResizeStart) return;
  const dx = e.clientX - richResizeStart.x;
  const newWidth = Math.max(40, Math.round(richResizeStart.width + dx));
  richSelectedImage.style.width = newWidth + 'px';
  richSelectedImage.style.height = 'auto';
  richSelectedImage.dataset.richResized = '1';
  lore_richRepositionHandle();
}

function lore_richResizeEnd(){
  document.removeEventListener('mousemove', lore_richResizeMove);
  document.removeEventListener('mouseup', lore_richResizeEnd);
  richResizeStart = null;
}

function lore_richSetImageAlign(align){
  if(!richSelectedImage) return;
  const alreadyResized = richSelectedImage.dataset.richResized === '1';
  if(align === 'left'){
    richSelectedImage.style.float = 'left';
    richSelectedImage.style.margin = '0.3rem 1.6rem 1rem 0';
    if(!alreadyResized) richSelectedImage.style.width = '45%';
  } else if(align === 'right'){
    richSelectedImage.style.float = 'right';
    richSelectedImage.style.margin = '0.3rem 0 1rem 1.6rem';
    if(!alreadyResized) richSelectedImage.style.width = '45%';
  } else {
    richSelectedImage.style.float = 'none';
    richSelectedImage.style.margin = '1rem auto';
    if(!alreadyResized) richSelectedImage.style.width = '100%';
  }
  lore_richRepositionHandle();
}

function lore_richRemoveImage(){
  if(!richSelectedImage) return;
  richSelectedImage.remove();
  lore_richDeselectImage();
}

async function lore_saveEditor(key){
  const title = document.getElementById('lore-edit-title').value.trim();
  const category = document.getElementById('lore-edit-category').value.trim();
  lore_richDeselectImage();
  const body = loreSanitizeHtml(document.getElementById('lore-edit-body-rich').innerHTML).trim();
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
      await loreUpdateEntry(key, { title, category, body, body_format: 'html' });
    } else {
      await loreCreateEntry({ title, category, body, body_format: 'html' });
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
window.lore_saveEditor = lore_saveEditor;
window.lore_confirmDelete = lore_confirmDelete;
window.lore_richExec = lore_richExec;
window.lore_richInsertTable = lore_richInsertTable;
window.lore_richInsertLink = lore_richInsertLink;
window.lore_richEditLinkUrl = lore_richEditLinkUrl;
window.lore_richRemoveLink = lore_richRemoveLink;
window.lore_richHandleFileInput = lore_richHandleFileInput;
window.lore_richSetImageAlign = lore_richSetImageAlign;
window.lore_richRemoveImage = lore_richRemoveImage;
window.lore_moveEntry = lore_moveEntry;

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

  const openParam = new URLSearchParams(location.search).get('open');
  if(openParam){
    const match = findArticleBySlugOrTitle(openParam);
    if(match) lore_openArticle(match, { updateUrl: false });
    else alert('That article isn\'t available yet: ' + openParam);
  }

  let savedDark = false;
  try{ savedDark = localStorage.getItem('fa-lore-dark') === '1'; }catch(e){}
  if(savedDark){
    document.getElementById('lore-page').classList.add('lore-dark');
    document.getElementById('lore-dark-toggle').classList.add('on');
  }
}

window.addEventListener('popstate', () => {
  const openParam = new URLSearchParams(location.search).get('open');
  const match = openParam ? findArticleBySlugOrTitle(openParam) : null;
  lore_selectItem(match ? match.key : null);
});

if(document.readyState === 'loading'){
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
})();

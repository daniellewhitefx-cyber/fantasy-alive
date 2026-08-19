const RECIPE_SHEET_CSV_URL = 'https://docs.google.com/spreadsheets/d/1ItjkOYamXrQ0vLIZlkdMCqwF0PGw0DV82J4bk9zhu3c/export?format=csv';

const RECIPE_CATEGORY_ORDER = ['Alchemical', 'Herbal'];
const RECIPE_CATEGORY_LABELS = { 'Alchemical': 'Alchemist', 'Herbal': 'Herbalist' };

function recipesParseCSV(text){
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

async function recipesLoadFromSheet(){
  const res = await fetch(RECIPE_SHEET_CSV_URL, { cache: 'no-store' });
  if(!res.ok) throw new Error('Sheet request failed (' + res.status + ')');
  const csvText = await res.text();
  const rows = recipesParseCSV(csvText).filter(r => r.some(cell => (cell || '').trim() !== ''));
  const header = (rows.shift() || []).map(h => h.trim().toLowerCase());
  const col = name => header.indexOf(name);

  const iCategory = col('category'), iLevel = col('recipe level'), iName = col('name'),
    iEffect = col('effect'), iType = col('type'), iGas = col('mixed with gas'),
    iIngredients = col('required ingredients/herbs'), iDesc = col('description');

  return rows.map(r => ({
    category: (r[iCategory] || 'Uncategorized').trim(),
    level: (r[iLevel] || '').trim(),
    title: (r[iName] || 'Untitled Recipe').trim(),
    effect: (r[iEffect] || '').trim(),
    type: (r[iType] || '').trim(),
    mixedWithGas: (r[iGas] || '').trim(),
    ingredients: (r[iIngredients] || '').trim(),
    desc: (r[iDesc] || '').trim()
  }));
}

function recipesOrderedCategories(allRecipes){
  const byCategory = {};
  allRecipes.forEach(r => { byCategory[r.category] = true; });
  const known = RECIPE_CATEGORY_ORDER.filter(c => byCategory[c]);
  const unknown = Object.keys(byCategory).filter(c => !RECIPE_CATEGORY_ORDER.includes(c)).sort();
  return [...known, ...unknown];
}

window.RECIPE_SHEET_CSV_URL = RECIPE_SHEET_CSV_URL;
window.RECIPE_CATEGORY_ORDER = RECIPE_CATEGORY_ORDER;
window.RECIPE_CATEGORY_LABELS = RECIPE_CATEGORY_LABELS;
window.recipesLoadFromSheet = recipesLoadFromSheet;
window.recipesOrderedCategories = recipesOrderedCategories;

// Loads the Shoppe item catalog from the shared Google Sheet. Rarity is
// intentionally ignored for now -- the sheet has a Rarity / Availability
// column that isn't used yet.

const SHOPPE_SHEET_CSV_URL = 'https://docs.google.com/spreadsheets/d/1bbNh12O_8XGsAkH06QJ0t3u1T-IXU2Wq7ufadJGB6Kg/export?format=csv';

const SHOPPE_CATEGORY_ORDER = ['Weapon', 'Armour', 'Material/Equipment', 'Mixture', 'Formula', 'Recipe', 'Spell', 'Trap/Lock', 'Luxury'];

async function shoppeLoadFromSheet(){
  const res = await fetch(SHOPPE_SHEET_CSV_URL, { cache: 'no-store' });
  if(!res.ok) throw new Error('Sheet request failed (' + res.status + ')');
  const csvText = await res.text();
  const rows = skillsParseCSV(csvText).filter(r => r.some(cell => (cell || '').trim() !== ''));
  const header = (rows.shift() || []).map(h => h.trim().toLowerCase());
  const col = name => header.indexOf(name);

  const iCategory = col('category'), iItem = col('item'), iCost = col('cost (copper)');

  return rows
    .map(r => ({
      category: (r[iCategory] || 'Uncategorized').trim(),
      name: (r[iItem] || '').trim(),
      costCopper: parseInt((r[iCost] || '0').replace(/[^0-9.-]/g, ''), 10) || 0
    }))
    .filter(item => item.name);
}

function shoppeOrderedCategories(allItems){
  const byCategory = {};
  allItems.forEach(i => { byCategory[i.category] = true; });
  const known = SHOPPE_CATEGORY_ORDER.filter(c => byCategory[c]);
  const unknown = Object.keys(byCategory).filter(c => !SHOPPE_CATEGORY_ORDER.includes(c)).sort();
  return [...known, ...unknown];
}

window.SHOPPE_SHEET_CSV_URL = SHOPPE_SHEET_CSV_URL;
window.SHOPPE_CATEGORY_ORDER = SHOPPE_CATEGORY_ORDER;
window.shoppeLoadFromSheet = shoppeLoadFromSheet;
window.shoppeOrderedCategories = shoppeOrderedCategories;

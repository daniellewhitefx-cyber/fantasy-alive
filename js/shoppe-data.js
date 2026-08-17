// Loads the Shoppe item catalog from the shared Google Sheet.

const SHOPPE_SHEET_CSV_URL = 'https://docs.google.com/spreadsheets/d/1bbNh12O_8XGsAkH06QJ0t3u1T-IXU2Wq7ufadJGB6Kg/export?format=csv';

const SHOPPE_CATEGORY_ORDER = ['Weapon', 'Armour', 'Material/Equipment', 'Mixture', 'Formula', 'Recipe', 'Spell', 'Trap/Lock', 'Luxury'];

// The rulebook's Availability scale for the Merchant skill (1=Common up to
// 6=Unique). Sheet text is inconsistent ("Uncommon*", "Rare or Very Rare
// (see Spells tab)", "Very Uncommon–Very Rare (see Mixtures tab)", "Not
// specified in source"), so this takes the *highest* tier mentioned in the
// text -- a compound/range value should gate at its more restrictive end.
// Rows with no recognizable tier keyword default to Common (tier 1) rather
// than blocking the purchase, since most of them are mundane materials
// (Rope, Wood, Dice, ...) that were simply never tagged.
const SHOPPE_AVAILABILITY_ORDER = ['Common', 'Uncommon', 'Very Uncommon', 'Rare', 'Very Rare', 'Unique'];

function shoppeAvailabilityTier(text){
  const t = (text || '').toLowerCase();
  let tier = 1;
  SHOPPE_AVAILABILITY_ORDER.forEach((label, i) => {
    if(t.includes(label.toLowerCase())) tier = i + 1;
  });
  return tier;
}

async function shoppeLoadFromSheet(){
  const res = await fetch(SHOPPE_SHEET_CSV_URL, { cache: 'no-store' });
  if(!res.ok) throw new Error('Sheet request failed (' + res.status + ')');
  const csvText = await res.text();
  const rows = skillsParseCSV(csvText).filter(r => r.some(cell => (cell || '').trim() !== ''));
  const header = (rows.shift() || []).map(h => h.trim().toLowerCase());
  const col = name => header.indexOf(name);

  const iCategory = col('category'), iItem = col('item'), iCost = col('cost (copper)'),
    iAvailability = col('rarity / availability');

  return rows
    .map(r => {
      const availabilityText = (r[iAvailability] || '').trim();
      return {
        category: (r[iCategory] || 'Uncategorized').trim(),
        name: (r[iItem] || '').trim(),
        costCopper: parseInt((r[iCost] || '0').replace(/[^0-9.-]/g, ''), 10) || 0,
        availabilityText: availabilityText,
        availabilityTier: shoppeAvailabilityTier(availabilityText)
      };
    })
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
window.SHOPPE_AVAILABILITY_ORDER = SHOPPE_AVAILABILITY_ORDER;
window.shoppeAvailabilityTier = shoppeAvailabilityTier;
window.shoppeLoadFromSheet = shoppeLoadFromSheet;
window.shoppeOrderedCategories = shoppeOrderedCategories;

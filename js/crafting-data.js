// Loads the Crafting production list from the shared Google Sheet.

const CRAFTING_SHEET_CSV_URL = 'https://docs.google.com/spreadsheets/d/1pdO_F2fnCTLcLeEXsrpTMymkOkWarMYsgxHEJ8tdPSU/export?format=csv';

// Merchant and Labourer are trade skills but have no "craft a named item"
// mechanic in the rulebook (Merchant is detection/business-oriented,
// Labourer extracts raw materials generically, which the Work tab's
// Copper-earning mechanic already covers), so they're not part of this list.
const CRAFTING_TRADE_ORDER = ['Armour Smith', 'Weapon Smith', 'Mechanic', 'Craftsman', 'Physician', 'Alchemist', 'Herbalist'];

// Materials text looks like "1 Lumber and 1 Hardware", "1 Iron, 2 Lumber
// and 2 Hardware (also requires Armour Smith 4)", or "none". A trailing
// "(...)" is pulled out as a free-text note (dual-trade requirements,
// "plus items dropped", etc.) rather than parsed as a tracked material.
function craftingParseMaterials(text){
  const raw = (text || '').trim();
  if(!raw || raw.toLowerCase() === 'none') return { materials: [], note: null };
  const noteMatch = raw.match(/\(([^)]+)\)\s*$/);
  const note = noteMatch ? noteMatch[1].trim() : null;
  const core = raw.replace(/\([^)]*\)\s*$/, '').trim();
  if(!core) return { materials: [], note };
  const parts = core.split(/,| and /i).map(s => s.trim()).filter(Boolean);
  const materials = parts.map(p => {
    const m = p.match(/^(\d+)\s+(.+)$/);
    return m ? { name: m[2].trim(), qty: parseInt(m[1], 10) } : { name: p, qty: 1 };
  });
  return { materials, note };
}

async function craftingLoadFromSheet(){
  const res = await fetch(CRAFTING_SHEET_CSV_URL, { cache: 'no-store' });
  if(!res.ok) throw new Error('Sheet request failed (' + res.status + ')');
  const csvText = await res.text();
  const rows = skillsParseCSV(csvText).filter(r => r.some(cell => (cell || '').trim() !== ''));
  const header = (rows.shift() || []).map(h => h.trim().toLowerCase());
  const col = name => header.indexOf(name);

  const iTrade = col('trade'), iItem = col('item'), iCategory = col('category'),
    iLevel = col('level required'), iHours = col('time hours'), iQty = col('qty produced'),
    iMaterials = col('materials');

  return rows
    .map(r => {
      const materialsText = (r[iMaterials] || '').trim();
      const { materials, note } = craftingParseMaterials(materialsText);
      const hoursText = (r[iHours] || '').trim();
      return {
        trade: (r[iTrade] || '').trim(),
        name: (r[iItem] || '').trim(),
        category: (r[iCategory] || 'Uncategorized').trim(),
        levelRequired: parseInt(r[iLevel], 10) || 1,
        hours: hoursText ? (parseInt(hoursText, 10) || null) : null,
        qtyProduced: parseInt(r[iQty], 10) || 1,
        materialsText: materialsText,
        materials: materials,
        note: note
      };
    })
    .filter(item => item.name && item.trade);
}

function craftingOrderedTrades(allItems){
  const byTrade = {};
  allItems.forEach(i => { byTrade[i.trade] = true; });
  const known = CRAFTING_TRADE_ORDER.filter(t => byTrade[t]);
  const unknown = Object.keys(byTrade).filter(t => !CRAFTING_TRADE_ORDER.includes(t)).sort();
  return [...known, ...unknown];
}

window.CRAFTING_SHEET_CSV_URL = CRAFTING_SHEET_CSV_URL;
window.CRAFTING_TRADE_ORDER = CRAFTING_TRADE_ORDER;
window.craftingParseMaterials = craftingParseMaterials;
window.craftingLoadFromSheet = craftingLoadFromSheet;
window.craftingOrderedTrades = craftingOrderedTrades;

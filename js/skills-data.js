const SKILL_SHEET_CSV_URL = 'https://docs.google.com/spreadsheets/d/1ywI52NIOEB6EKIe5WvLzerY6w0ZmU0bAkOrKq5ggrP8/export?format=csv';

const SKILL_CATEGORY_ORDER = ['Combat Skill', 'Weapon Skill', 'Academic Skill', 'Trade Skill', 'Ability'];

function skillsParseCSV(text){
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

async function skillsLoadFromSheet(){
  const res = await fetch(SKILL_SHEET_CSV_URL, { cache: 'no-store' });
  if(!res.ok) throw new Error('Sheet request failed (' + res.status + ')');
  const csvText = await res.text();
  const rows = skillsParseCSV(csvText).filter(r => r.some(cell => (cell || '').trim() !== ''));
  const header = (rows.shift() || []).map(h => h.trim().toLowerCase());
  const col = name => header.indexOf(name);

  const iCategory = col('category'), iName = col('name'), iCost = col('cost'),
    iPrereq = col('prerequisite'), iDesc = col('description');

  return rows.map(r => ({
    category: (r[iCategory] || 'Uncategorized').trim(),
    title: (r[iName] || 'Untitled Skill').trim(),
    cost: (r[iCost] || '').trim(),
    prereq: (r[iPrereq] || '').trim(),
    desc: (r[iDesc] || '').trim()
  }));
}

function skillsOrderedCategories(allSkills){
  const byCategory = {};
  allSkills.forEach(s => { byCategory[s.category] = true; });
  const known = SKILL_CATEGORY_ORDER.filter(c => byCategory[c]);
  const unknown = Object.keys(byCategory).filter(c => !SKILL_CATEGORY_ORDER.includes(c)).sort();
  return [...known, ...unknown];
}

// Resolves a sheet "Cost" cell to a numeric SP cost for the given level.
// Flat costs ("10") ignore level. Level-based costs support "N+lvl",
// "N x lvl" / "N times lvl", and "N/pt." (per-level point costs).
// Returns null when the cost text can't be resolved to a number
// (e.g. "See Text"), meaning the skill isn't purchasable through a
// simple points calculation.
function skillsParseCost(costStr, level){
  const lvl = Math.max(1, parseInt(level, 10) || 1);
  const s = (costStr || '').trim();
  if(/^\d+$/.test(s)) return parseInt(s, 10);
  let m = s.match(/^(\d+)\s*\+\s*lvl$/i);
  if(m) return parseInt(m[1], 10) + lvl;
  m = s.match(/^(\d+)\s*[x×*]\s*lvl$/i);
  if(m) return parseInt(m[1], 10) * lvl;
  m = s.match(/^(\d+)\s*\/\s*pt\.?$/i);
  if(m) return parseInt(m[1], 10) * lvl;
  return null;
}

window.SKILL_SHEET_CSV_URL = SKILL_SHEET_CSV_URL;
window.SKILL_CATEGORY_ORDER = SKILL_CATEGORY_ORDER;
window.skillsParseCSV = skillsParseCSV;
window.skillsLoadFromSheet = skillsLoadFromSheet;
window.skillsOrderedCategories = skillsOrderedCategories;
window.skillsParseCost = skillsParseCost;

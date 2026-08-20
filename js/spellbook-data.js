// Shared Spellbook data: the public Spell Compendium sheet (same source
// spell-compendium.html reads) plus per-deity domain data (Shared/Opposed
// Domains and each deity's own per-level spell list) parsed out of the
// Deities lore articles (supabase/lore-import.sql), which already carry
// this exact structure as hand-written markdown -- see e.g. the "Clovis"
// or "Brack" articles for the "Shared Domains: [[X]] Opposed Domain:
// [[Y]]" line and the "| Level | Spells |" table.

const SPELLBOOK_SHEET_CSV_URL = 'https://docs.google.com/spreadsheets/d/1JEUuwBntPy8VxTATpzjb6juloHflbGBW4EgBXY7bSZE/export?format=csv';

// A cleric pays more to draw on a deity outside their own worship: full
// price for their own deity's spells, +5 SE for a Shared Domain deity's
// (gods who share power with allies), +10 SE for an Opposed Domain
// deity's (offered as temptation, not a boon).
const SPELLBOOK_SHARED_DOMAIN_SURCHARGE = 5;
const SPELLBOOK_OPPOSED_DOMAIN_SURCHARGE = 10;

function spellbookParseCSV(text){
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

// Loads the flat spell list: name, circle (1-9), energy cost, incant,
// description, duration, category, MEL, Mix. Keyed by lowercased name
// for matching against the deity spell-list links and Magery selections.
async function spellbookLoadCompendium(){
  const res = await fetch(SPELLBOOK_SHEET_CSV_URL, { cache: 'no-store' });
  if(!res.ok) throw new Error('Spell sheet request failed (' + res.status + ')');
  const csvText = await res.text();
  const rows = spellbookParseCSV(csvText).filter(r => r.some(cell => (cell || '').trim() !== ''));
  const header = (rows.shift() || []).map(h => h.trim().toLowerCase());
  const col = name => header.indexOf(name);

  const iLvl = col('lvl'), iName = col('name'), iEnergy = col('energy'),
    iIncant = col('incant'), iDesc = col('description'), iDuration = col('duration'),
    iCategory = col('category'), iMel = col('mel'), iMix = col('mix');

  const byName = {};
  rows.forEach(r => {
    const name = (r[iName] || '').trim();
    if(!name) return;
    const level = parseInt((r[iLvl] || '').trim(), 10);
    if(!level) return;
    byName[name.toLowerCase()] = {
      name,
      level,
      energy: parseInt((r[iEnergy] || '0').trim(), 10) || 0,
      incant: (r[iIncant] || '').trim(),
      desc: (r[iDesc] || '').trim(),
      duration: (r[iDuration] || '').trim(),
      category: (r[iCategory] || '').trim(),
      mel: (r[iMel] || '0').trim(),
      mix: (r[iMix] || 'No').trim()
    };
  });
  return byName;
}

// Extracts [[Name]]-linked deity names out of a "Shared Domains: [[X]],
// [[Y]] Opposed Domain(s): [[Z]]" line. "None" (no brackets at all)
// yields an empty list.
function spellbookExtractDomainNames(text){
  if(!text) return [];
  const names = [];
  const re = /\[\[([^\]]+)\]\]/g;
  let m;
  while((m = re.exec(text))) names.push(m[1].trim());
  return names;
}

// Parses one Deities lore article body into { sharedDomains, opposedDomains,
// spellsByLevel }. Returns null for lore articles that aren't a deity's own
// page (e.g. "The Pantheon", "Clerics and the Gods") -- they don't have the
// domain line or spell table this needs.
function spellbookParseDeityArticle(body){
  const domainMatch = body.match(/Shared Domains?:\s*(.*?)\s*Opposed Domains?:\s*([^\n]*)/);
  if(!domainMatch) return null;

  const sharedDomains = spellbookExtractDomainNames(domainMatch[1]);
  const opposedDomains = spellbookExtractDomainNames(domainMatch[2]);

  const spellsByLevel = {};
  const rowRe = /\|\s*(\d+)(?:st|nd|rd|th)\s*Level\s*\|\s*(.*?)\s*\|\s*(?:\n|$)/g;
  let rowMatch;
  let found = false;
  while((rowMatch = rowRe.exec(body))){
    found = true;
    const level = parseInt(rowMatch[1], 10);
    const cell = rowMatch[2];
    const names = [];
    const linkRe = /\[([^\]]+)\]\(spell-compendium/g;
    let linkMatch;
    while((linkMatch = linkRe.exec(cell))) names.push(linkMatch[1].trim());
    spellsByLevel[level] = names;
  }
  if(!found) return null;

  return { sharedDomains, opposedDomains, spellsByLevel };
}

// Loads every deity's parsed domain data, keyed by deity name exactly as
// it appears as a Clerical Investment focus (skill_focuses.name), e.g.
// "Clovis", "Brack" -- matches the lore article's title.
async function spellbookLoadDeities(){
  const { data, error } = await membersSupabase
    .from('lore_entries')
    .select('title, body')
    .eq('category', 'Deities');
  if(error) throw new Error(error.message);

  const byDeity = {};
  (data || []).forEach(entry => {
    const parsed = spellbookParseDeityArticle(entry.body || '');
    if(parsed) byDeity[entry.title] = parsed;
  });
  return byDeity;
}

// Resolves the full set of spells a Clerical Investment grants at a given
// level for a given deity: the deity's own list (home cost), every Shared
// Domain deity's list (home cost + surcharge), every Opposed Domain
// deity's list (home cost + steeper surcharge). A spell reachable through
// more than one path (e.g. it's on both the home and a shared deity's
// list) is kept at its cheapest source.
function spellbookClericalSpells(deities, deityName, ciLevel){
  const home = deities[deityName];
  if(!home) return [];

  const bySource = new Map();
  const addFrom = (deity, surcharge) => {
    if(!deity) return;
    for(let lvl = 1; lvl <= ciLevel && lvl <= 9; lvl++){
      (deity.spellsByLevel[lvl] || []).forEach(name => {
        const key = name.toLowerCase();
        if(!bySource.has(key)) bySource.set(key, { name, surcharge });
      });
    }
  };

  addFrom(home, 0);
  (home.sharedDomains || []).forEach(d => addFrom(deities[d], SPELLBOOK_SHARED_DOMAIN_SURCHARGE));
  (home.opposedDomains || []).forEach(d => addFrom(deities[d], SPELLBOOK_OPPOSED_DOMAIN_SURCHARGE));

  return [...bySource.values()];
}

window.SPELLBOOK_SHARED_DOMAIN_SURCHARGE = SPELLBOOK_SHARED_DOMAIN_SURCHARGE;
window.SPELLBOOK_OPPOSED_DOMAIN_SURCHARGE = SPELLBOOK_OPPOSED_DOMAIN_SURCHARGE;
window.spellbookLoadCompendium = spellbookLoadCompendium;
window.spellbookLoadDeities = spellbookLoadDeities;
window.spellbookClericalSpells = spellbookClericalSpells;
window.spellbookParseDeityArticle = spellbookParseDeityArticle;

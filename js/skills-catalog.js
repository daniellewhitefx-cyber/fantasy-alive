// Shared skill-catalog helpers: parsing a sheet skill's name/placeholder,
// the focus options for skills with a placeholder, and prerequisite
// checking against a list of skills a character already knows. Used by
// both the Character Creator and the Current Event Training tab.

const SCHOOLS_OF_MAGIC = ['Armour','Body','Creation','Death','Detection','Divine','Elemental','Healing','Infliction','Magic','Mind','Summoning'];
const DEITIES = ['Alejandero','Alwyn','Anajaream','Apenca','Arkady','Astrid','Atha','Balaxa','Bard','Beldon','Blythe','Brack','Callis','Clovis','Elieff','Fiona','Hemulis','Iccula','Jerroh','Kazzok','Kell','Marius','Sasha','Stasa','Strega'];
const WRITTEN_LANGUAGES = ['Harodonian Common','High Elven','Dwarven Runes','Gnomish Script',"D'shunn Writings",'Lizardfolk Glyphs','Goblin Sigil','Orcsign','High and Low Minotaur','Giant Runes','Ancient Alexandrian','Imperial Lannean','Deep Writings','Arcane Script','Celestial Script','Infernal Script'];
const ENERGY_TYPES = ['Magical Energy','Spiritual Energy'];

function skillNameParts(title){
  const m = title.match(/^(.*?)\s*[\[\(]([^\]\)]+)[\]\)]\s*$/);
  if(m) return { base: m[1].trim(), placeholder: m[2].trim() };
  return { base: title.trim(), placeholder: null };
}

function skillKey(s){ return s.category + '::' + s.title; }

function isLeveledCost(costStr){ return /\+lvl|[x×*]\s*lvl|\/\s*pt\.?/i.test(costStr); }

// knownSkills entries look like { category, title, level }. Weapon type
// options are scoped to Weapon Skills already known, since you can't
// take combat proficiency in a weapon you haven't learned to use.
function focusOptionsFor(s, allSkills, knownSkills){
  const parts = skillNameParts(s.title);
  if(!parts.placeholder) return null;
  if(parts.placeholder.toLowerCase() === 'weapon type'){
    const known = knownSkills || [];
    const types = known.filter(k => k.category === 'Weapon Skill').map(k => k.title);
    return [...new Set(types)];
  }
  if(parts.base === 'Channel Spell') return ENERGY_TYPES;
  if(parts.base === 'Clerical Investment') return DEITIES;
  if(parts.base === 'Arcane Research') return SCHOOLS_OF_MAGIC;
  if(parts.base === 'Read & Write') return WRITTEN_LANGUAGES;
  return null;
}

// knownSkills entries look like { category, title, level }.
function hasKnownSkill(knownSkills, name, minLevel){
  const norm = name.trim().toLowerCase();
  if(norm === 'weapon skill') return knownSkills.some(s => s.category === 'Weapon Skill');
  if(norm === 'trade skill') return knownSkills.some(s => s.category === 'Trade Skill' && s.level >= minLevel);
  return knownSkills.some(s => s.title.toLowerCase() === norm && s.level >= minLevel);
}

function evalAtomicPrereq(raw, knownSkills){
  let part = raw.trim();
  if(!part) return true;
  part = part.replace(/^at least\s+/i, '');
  part = part.replace(/\([^)]*\)/g, '').trim();
  part = part.replace(/\s+for large shields$/i, '').replace(/\s+in ranged$/i, '').trim();
  if(!part) return true;
  if(/^\d+\s*lp$/i.test(part)) return true;

  let m = part.match(/^(\d+)\s+(.+)$/);
  if(m) return hasKnownSkill(knownSkills, m[2], parseInt(m[1], 10));

  m = part.match(/^(.+?)\s+(\d+)(?:\s*\/\s*\d+)?$/);
  if(m) return hasKnownSkill(knownSkills, m[1], parseInt(m[2], 10));

  return hasKnownSkill(knownSkills, part, 1);
}

function evalClausePrereq(clause, knownSkills){
  clause = clause.trim();
  if(!clause) return true;
  if(/\bor\b/i.test(clause)) return clause.split(/\s+or\s+/i).some(p => evalAtomicPrereq(p, knownSkills));
  return evalAtomicPrereq(clause, knownSkills);
}

function isPrereqMet(text, knownSkills){
  const expanded = (text || '')
    .replace(/\bCI\b/g, 'Clerical Investment')
    .replace(/\bSE\b/g, 'Spiritual Energy')
    .replace(/\bME\b/g, 'Magical Energy')
    .trim();
  if(!expanded || expanded.toLowerCase() === 'none') return true;
  return expanded.split(/[,&]/).every(clause => evalClausePrereq(clause, knownSkills));
}

window.skillNameParts = skillNameParts;
window.skillKey = skillKey;
window.isLeveledCost = isLeveledCost;
window.focusOptionsFor = focusOptionsFor;
window.hasKnownSkill = hasKnownSkill;
window.isPrereqMet = isPrereqMet;

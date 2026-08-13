// Shared derived-stat math (LP, SE, ME, Resurrections Left from race +
// skills), used wherever a prerequisite or display needs a character's
// real stats rather than a raw skill purchase. Mirrors the RACE_STATS
// table used on the Characters page.

const RACE_STATS = {
  'Curtainborn': { baseLp: 4, maxLp: 10, baseResurrections: 2, baseSe: 5, baseMe: 0 },
  'D\'Shunn': { baseLp: 4, maxLp: 10, baseResurrections: 2, baseSe: 0, baseMe: 0 },
  'Dwarf': { baseLp: 6, maxLp: 15, baseResurrections: 2, baseSe: 0, baseMe: 0 },
  'Elf': { baseLp: 4, maxLp: 10, baseResurrections: 1, baseSe: 0, baseMe: 5 },
  'Gnome': { baseLp: 4, maxLp: 8, baseResurrections: 2, baseSe: 0, baseMe: 0 },
  'Goblin': { baseLp: 4, maxLp: 8, baseResurrections: 3, baseSe: 0, baseMe: 0 },
  'Human': { baseLp: 5, maxLp: 10, baseResurrections: 2, baseSe: 0, baseMe: 0 },
  'Lizardfolk': { baseLp: 6, maxLp: 15, baseResurrections: 2, baseSe: 0, baseMe: 0 },
  'Malkin': { baseLp: 6, maxLp: 12, baseResurrections: 2, baseSe: 0, baseMe: 0 },
  'Minotaur': { baseLp: 8, maxLp: 20, baseResurrections: 2, baseSe: 0, baseMe: 0 },
  'Orc': { baseLp: 7, maxLp: 15, baseResurrections: 2, baseSe: 0, baseMe: 0 }
};
const MAX_RESURRECTIONS = 5;

// skills: [{ name, level }]
function faSkillLevelTotal(skills, name){
  return skills
    .filter(s => s.name.trim().toLowerCase() === name.toLowerCase())
    .reduce((sum, s) => sum + (s.level || 0), 0);
}

function faHasSkillNamed(skills, name){
  return skills.some(s => s.name.trim().toLowerCase() === name.toLowerCase());
}

function faDeriveStats(race, skills){
  const r = RACE_STATS[race] || { baseLp: 5, maxLp: 10, baseResurrections: 2, baseSe: 0, baseMe: 0 };
  skills = skills || [];

  const lp = Math.min(r.baseLp + faSkillLevelTotal(skills, 'Physical Endurance'), r.maxLp);
  const resurrectionsLeft = Math.min(r.baseResurrections + faSkillLevelTotal(skills, 'Spiritual Endurance'), MAX_RESURRECTIONS);
  const se = r.baseSe + faSkillLevelTotal(skills, 'Spiritual Energy') + (faHasSkillNamed(skills, 'Theology') ? 1 : 0);
  const me = r.baseMe + faSkillLevelTotal(skills, 'Magical Energy') + (faHasSkillNamed(skills, 'Magery') ? 1 : 0);

  return { lp, se, me, resurrectionsLeft };
}

window.RACE_STATS = RACE_STATS;
window.MAX_RESURRECTIONS = MAX_RESURRECTIONS;
window.faDeriveStats = faDeriveStats;

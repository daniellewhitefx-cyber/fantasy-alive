// Shared skill-catalog helpers built on the real relational skill/focus/
// prerequisite data (js/skills-data.js): resolving a skill's cost and
// prerequisites for a given race and (if it takes one) chosen focus, and
// the focus options a skill offers. Used by Character Creator, Character
// Edit (remort), the Current Event Training tab, and (in an unrestricted
// mode) the staff character tool.

function skillKey(s){ return s.category + '::' + s.title; }

// A skill's cost/prerequisites can have a race-specific override; this
// resolves the one that actually applies, falling back to the skill's
// default (race-unrestricted) row. Works the same way for a focus's own
// cost row.
function skillDetailFor(skill, race){
  if(race && skill.costByRace && skill.costByRace[race]) return skill.costByRace[race];
  return skill.costDefault;
}
function focusDetailFor(focus, race){
  if(race && focus.costByRace && focus.costByRace[race]) return focus.costByRace[race];
  return focus.costDefault;
}

function findFocus(skill, focusName){
  if(!focusName) return null;
  return (skill.focusOptions || []).find(f => f.name === focusName) || null;
}

// Some skills (weapon proficiencies, craftsman/labourer specialties) get
// their real price from the chosen focus rather than the skill itself --
// the skill's own row is either a placeholder (no cost at all, e.g.
// Weapon Skill, where every real price lives on the weapon-type focus) or
// deliberately overridden per focus (overwriteCostForFocus). A skill with
// its own real cost and no override -- e.g. Backstab, which shares the
// same weapon-type focus catalog as Weapon Skill but always costs the
// same regardless of which weapon it's taken with -- always uses its own
// price and never looks at the focus's. When neither resolves to a real
// number (no focus chosen yet, for a skill that needs one), there's no
// computable cost.
//
// A race-specific override on the skill itself (e.g. Craftsman costing a
// Dwarf less and a Curtainborn more than the default) always wins outright,
// even for skills whose default price is normally replaced by the chosen
// focus's -- it's this race's aptitude for the whole trade, and applies no
// matter which specialty is picked within it. Only when there's no
// race-specific row does the focus's (usually race-invariant) price apply.
function resolveCostDetail(skill, level, race, focusName){
  const skillDetail = skillDetailFor(skill, race);
  const isRaceSpecific = !!(race && skill.costByRace && skill.costByRace[race] === skillDetail);
  const skillHasOwnCost = skillDetail && skillDetail.value !== null && skillDetail.value !== undefined;

  if(isRaceSpecific && skillHasOwnCost) return skillDetail;
  if(skillHasOwnCost && !skill.overwriteCostForFocus) return skillDetail;

  const focus = findFocus(skill, focusName);
  if(focus){
    const focusDetail = focusDetailFor(focus, race);
    if(focusDetail && focusDetail.value !== null && focusDetail.value !== undefined) return focusDetail;
  }
  return skillDetail;
}

// Resolves the SP cost of a skill at a given level, for a given race and
// (if applicable) chosen focus. Returns null when there's no computable
// cost yet (e.g. a focus is required but not chosen).
function skillsParseCost(skill, level, race, focusName){
  const detail = resolveCostDetail(skill, level, race, focusName);
  if(!detail || detail.value === null || detail.value === undefined) return null;
  const lvl = Math.max(1, parseInt(level, 10) || 1);
  if(detail.levelCost === '+') return detail.value + lvl;
  if(detail.levelCost === '*') return detail.value * lvl;
  return detail.value;
}

// Whether purchasing further levels of this skill is a real mechanic
// (cost scales with level) rather than a flat one-time purchase.
function isLeveledCost(skill, race, focusName){
  const detail = resolveCostDetail(skill, null, race, focusName);
  return !!(detail && detail.levelCost);
}

// focusName, when given, requires the known skill to have been learned
// with that specific focus -- e.g. Lethal Hands needs Weapon Skill known
// specifically in Hand to Hand, not just any weapon type. This is
// distinct from mustMatchFocus (used elsewhere), which instead requires
// a skill's own chosen focus to match whatever focus its prerequisite
// was learned with.
function hasKnownSkillLevel(knownSkills, name, minLevel, focusName){
  const norm = (name || '').trim().toLowerCase();
  const normFocus = focusName ? focusName.trim().toLowerCase() : null;
  return (knownSkills || []).some(k => {
    if(k.title.trim().toLowerCase() !== norm || k.level < minLevel) return false;
    if(normFocus && (k.focus || '').trim().toLowerCase() !== normFocus) return false;
    return true;
  });
}

function prereqGroupSatisfied(group, knownSkills){
  if(!hasKnownSkillLevel(knownSkills, group.skill1.name, group.skill1.level, group.requiredFocusName)) return false;
  if(group.skill2 && !hasKnownSkillLevel(knownSkills, group.skill2.name, group.skill2.level)) return false;
  return true;
}

// stats is the character's derived { lp, se, me } from faDeriveStats().
// When stats is omitted (race not chosen yet), these checks pass
// permissively rather than blocking on data that isn't available.
function energyPrereqMet(detail, stats){
  if(!detail.energyPrereq) return true;
  if(!stats) return true;
  return stats.se >= detail.energyPrereq || stats.me >= detail.energyPrereq;
}
function lpPrereqMet(detail, stats){
  if(!detail.lpPrereq) return true;
  if(!stats) return true;
  return stats.lp >= detail.lpPrereq;
}

// A skill's own prerequisite groups are alternatives (satisfying any ONE
// group is enough); within a group, both skill1 and skill2 (if present)
// are required together. Some focuses (e.g. 2-Handed Sword requiring
// Physical Prowess, where 1-Handed Sword requires nothing extra) add
// their own prerequisite on top, required in addition to the skill's own.
function isPrereqMet(skill, race, focusName, knownSkills, stats){
  const detail = skillDetailFor(skill, race);
  const skillOk = !detail || detail.prereqGroups.length === 0 || detail.prereqGroups.some(g => prereqGroupSatisfied(g, knownSkills));
  const energyOk = !detail || energyPrereqMet(detail, stats);
  const lpOk = !detail || lpPrereqMet(detail, stats);

  const focus = findFocus(skill, focusName);
  const focusOk = !focus || focus.prereqs.every(p => hasKnownSkillLevel(knownSkills, p.name, p.level));

  return skillOk && energyOk && lpOk && focusOk;
}

function describePrereqPart(s, focusName){
  const base = s.level > 1 ? `${s.name} ${s.level}` : s.name;
  return focusName ? `${base} [${focusName}]` : base;
}
function describePrereqGroup(g){
  const part1 = describePrereqPart(g.skill1, g.requiredFocusName);
  return g.skill2 ? `${part1} and ${describePrereqPart(g.skill2)}` : part1;
}

// Human-readable text for the prerequisite(s) not yet met, or null once
// they are. Reuses the same evaluation as isPrereqMet so the two can
// never disagree on whether a skill is actually locked.
function unmetPrereqText(skill, race, focusName, knownSkills, stats){
  const detail = skillDetailFor(skill, race);
  const parts = [];

  if(detail){
    const skillOk = detail.prereqGroups.length === 0 || detail.prereqGroups.some(g => prereqGroupSatisfied(g, knownSkills));
    if(!skillOk) parts.push(detail.prereqGroups.map(describePrereqGroup).join(' or '));
    if(!energyPrereqMet(detail, stats)) parts.push(`${detail.energyPrereq} SE or ME`);
    if(!lpPrereqMet(detail, stats)) parts.push(`${detail.lpPrereq} LP`);
  }

  const focus = findFocus(skill, focusName);
  if(focus){
    const unmetFocusPrereqs = focus.prereqs.filter(p => !hasKnownSkillLevel(knownSkills, p.name, p.level));
    if(unmetFocusPrereqs.length) parts.push(unmetFocusPrereqs.map(describePrereqPart).join(' and '));
  }

  return parts.length ? parts.join(', ') : null;
}

// The full set of focus values a skill can be taken with (weapon types,
// deities, craftsman/labourer specialties, spell schools, and so on),
// drawn from the real focus-type catalog rather than a hardcoded list.
// Returns null for skills that don't take a focus at all.
//
// Some skills (e.g. combat techniques keyed to a specific weapon type)
// require the chosen focus to match a focus the character already has in
// a prerequisite skill -- e.g. you can only take Backstab [Dagger] if you
// already know Weapon Skill [Dagger]. That's opt-out with
// unrestricted:true for the staff tool, which grants skills freely.
function focusOptionsFor(skill, knownSkills, race, opts){
  opts = opts || {};
  if(!skill.focusTypeId) return null;
  const names = skill.focusOptions.map(f => f.name);
  if(opts.unrestricted) return names;

  const detail = skillDetailFor(skill, race);
  const matchGroup = detail && detail.prereqGroups.find(g => g.mustMatchFocus);
  if(!matchGroup) return names;

  const norm = (matchGroup.skill1.name || '').trim().toLowerCase();
  const knownFociForSkill = (knownSkills || [])
    .filter(k => k.title.trim().toLowerCase() === norm && k.focus)
    .map(k => k.focus);
  return names.filter(n => knownFociForSkill.includes(n));
}

// Clerical Investment locks a character to one deity: "A character may
// not be invested with more than 1 deity at any time and switching
// religions means losing all spells and abilities gained from the
// previous investment" (rulebook). Once already invested, players should
// just be releveling their existing god, not re-picking one -- changing
// which god it's locked to is left to staff via the admin tool, which
// grants focuses unrestricted.
function clericalInvestmentLockedFocus(knownSkills){
  const existing = (knownSkills || []).find(s => s.title === 'Clerical Investment' && s.focus);
  return existing ? existing.focus : null;
}

window.skillKey = skillKey;
window.skillDetailFor = skillDetailFor;
window.skillsParseCost = skillsParseCost;
window.isLeveledCost = isLeveledCost;
window.isPrereqMet = isPrereqMet;
window.unmetPrereqText = unmetPrereqText;
window.focusOptionsFor = focusOptionsFor;
window.clericalInvestmentLockedFocus = clericalInvestmentLockedFocus;

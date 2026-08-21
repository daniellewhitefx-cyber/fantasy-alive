
function skillKey(s){ return s.category + '::' + s.title; }

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

function skillsParseCost(skill, level, race, focusName){
  const detail = resolveCostDetail(skill, level, race, focusName);
  if(!detail || detail.value === null || detail.value === undefined) return null;
  const lvl = Math.max(1, parseInt(level, 10) || 1);
  if(detail.levelCost === '+') return detail.value + lvl;
  if(detail.levelCost === '*') return detail.value * lvl;
  return detail.value;
}

function isLeveledCost(skill, race, focusName){
  const detail = resolveCostDetail(skill, null, race, focusName);
  return !!(detail && (detail.levelCost || skill.levelable));
}

function skillsCumulativeCost(skill, level, race, focusName){
  if(!isLeveledCost(skill, race, focusName)) return skillsParseCost(skill, 1, race, focusName);
  const lvl = Math.max(1, parseInt(level, 10) || 1);
  let total = 0;
  for(let l = 1; l <= lvl; l++){
    const cost = skillsParseCost(skill, l, race, focusName);
    if(cost === null) return null;
    total += cost;
  }
  return total;
}

function skillsLevelLimit(skill, race, focusName){
  const detail = resolveCostDetail(skill, null, race, focusName);
  return detail ? detail.levelLimit : null;
}

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

function focusOptionsFor(skill, knownSkills, race, opts){
  opts = opts || {};
  if(!skill.focusTypeId) return null;
  const names = skill.focusOptions.map(f => f.name);
  if(opts.unrestricted) return names;

  const detail = skillDetailFor(skill, race);
  const matchGroups = detail ? detail.prereqGroups.filter(g => g.mustMatchFocus) : [];
  if(!matchGroups.length) return names;

  const knownFoci = new Set();
  matchGroups.forEach(g => {
    const norm = (g.skill1.name || '').trim().toLowerCase();
    (knownSkills || [])
      .filter(k => k.title.trim().toLowerCase() === norm && k.focus)
      .forEach(k => knownFoci.add(k.focus));
  });
  return names.filter(n => knownFoci.has(n));
}

function skillNextLevel(skill, chosen, focusName){
  const key = skill.focusTypeId ? (focusName || '').trim() : '';
  const existing = (chosen || []).find(c => c.title === skill.title && c.focus === key);
  return existing ? existing.level + 1 : 1;
}

function racialGrantEntries(allSkills, raceStartingSkills, race){
  const grants = (raceStartingSkills && raceStartingSkills[race]) || [];
  return grants.map(g => {
    const skill = allSkills.find(s => s.id === g.skillId);
    if(!skill) return null;
    return {
      category: skill.category,
      title: skill.title,
      focus: '',
      level: g.level,
      cost: 0,
      racial: true,
      needsFocus: !!skill.focusTypeId
    };
  }).filter(Boolean);
}

function applyRacialGrants(chosen, allSkills, raceStartingSkills, race){
  const grants = racialGrantEntries(allSkills, raceStartingSkills, race);
  const result = chosen.filter(s => !s.racial);
  grants.forEach(g => {
    const idx = result.findIndex(c => c.title === g.title && (g.needsFocus || c.focus === g.focus));
    if(idx === -1){
      result.push(g);
    } else {
      result[idx] = Object.assign({}, result[idx], { racial: true, needsFocus: g.needsFocus });
    }
  });
  return result;
}

function skillFullyOwned(skill, owned){
  const matches = (owned || []).filter(o => o.title === skill.title);
  if(!matches.length) return false;
  if(!skill.focusTypeId) return matches.some(o => !o.focus);
  const ownedFoci = new Set(matches.map(o => o.focus || ''));
  return skill.focusOptions.every(f => ownedFoci.has(f.name));
}

function mergeChosenSkill(chosen, entry, isLeveled){
  const existing = chosen.find(c => c.title === entry.title && c.focus === entry.focus);
  if(!existing){
    chosen.push(entry);
    return;
  }
  if(isLeveled){
    existing.level = entry.level;
    existing.cost = entry.cost;
  } else {
    existing.level += entry.level;
    existing.cost += entry.cost;
  }
}

function clericalInvestmentLockedFocus(knownSkills){
  const existing = (knownSkills || []).find(s => s.title === 'Clerical Investment' && s.focus);
  return existing ? existing.focus : null;
}

window.mergeChosenSkill = mergeChosenSkill;
window.racialGrantEntries = racialGrantEntries;
window.applyRacialGrants = applyRacialGrants;
window.skillFullyOwned = skillFullyOwned;
window.skillNextLevel = skillNextLevel;
window.skillKey = skillKey;
window.skillDetailFor = skillDetailFor;
window.skillsParseCost = skillsParseCost;
window.isLeveledCost = isLeveledCost;
window.isPrereqMet = isPrereqMet;
window.unmetPrereqText = unmetPrereqText;
window.focusOptionsFor = focusOptionsFor;
window.clericalInvestmentLockedFocus = clericalInvestmentLockedFocus;

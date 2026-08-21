
const SKILL_CATEGORY_ORDER = ['Combat Skill', 'Weapon Skill', 'Academic Skill', 'Trade Skill', 'Ability'];

function skillsCategoryName(skillTypeName){
  return skillTypeName === 'Ability' ? 'Ability' : skillTypeName + ' Skill';
}

async function skillsFetchAllRows(table, select){
  const pageSize = 1000;
  let rows = [];
  let from = 0;
  while(true){
    const { data, error } = await membersSupabase.from(table).select(select).range(from, from + pageSize - 1);
    if(error) throw new Error(error.message);
    rows = rows.concat(data || []);
    if(!data || data.length < pageSize) break;
    from += pageSize;
  }
  return rows;
}

function skillsBuildCostDetail(row, prereqGroups){
  return {
    id: row.id,
    value: row.cost,
    tutor: row.tutor,
    levelCost: row.level_cost,
    levelLimit: row.level_limit != null ? row.level_limit : null,
    focusLimit: row.focus_limit != null ? row.focus_limit : null,
    minCost: row.min_cost != null ? row.min_cost : null,
    energyPrereq: row.energy_prereq != null ? row.energy_prereq : null,
    lpPrereq: row.lp_prereq != null ? row.lp_prereq : null,
    uniqueSkill: !!row.unique_skill,
    prereqGroups: prereqGroups
  };
}

async function skillsLoadCatalog(){
  const [skillTypes, skills, focuses, focusTypeMap, details, focusDetails, prereqs, focusPrereqs] = await Promise.all([
    skillsFetchAllRows('skill_types', 'id, name'),
    skillsFetchAllRows('skills', 'id, name, skill_type_id, focus_type_id, levelable, overwrite_cost_for_focus, description'),
    skillsFetchAllRows('skill_focuses', 'id, name, cost, tutor, level_cost, description'),
    skillsFetchAllRows('skill_focus_type_map', 'focus_id, focus_type_id'),
    skillsFetchAllRows('skill_details', 'id, skill_id, race, cost, tutor, level_limit, focus_limit, min_cost, level_cost, energy_prereq, lp_prereq, unique_skill'),
    skillsFetchAllRows('skill_focus_details', 'id, focus_id, race, cost, tutor, level_cost'),
    skillsFetchAllRows('skill_prerequisites', 'skill_detail_id, prerequisite_skill_id, prerequisite_level, prerequisite_skill2_id, prerequisite_level2, must_match_focus, prerequisite_focus_id, prerequisite_focus_level'),
    skillsFetchAllRows('skill_focus_prerequisites', 'focus_id, prerequisite_skill_id, prerequisite_level')
  ]);

  const skillTypeNameById = {};
  skillTypes.forEach(t => { skillTypeNameById[t.id] = t.name; });

  const skillById = {};
  skills.forEach(s => { skillById[s.id] = s; });

  const focusNameById = {};
  focuses.forEach(f => { focusNameById[f.id] = f.name; });

  const prereqGroupsBySkillDetail = {};
  prereqs.forEach(p => {
    (prereqGroupsBySkillDetail[p.skill_detail_id] = prereqGroupsBySkillDetail[p.skill_detail_id] || []).push({
      skill1: { id: p.prerequisite_skill_id, name: (skillById[p.prerequisite_skill_id] || {}).name, level: p.prerequisite_level },
      skill2: p.prerequisite_skill2_id
        ? { id: p.prerequisite_skill2_id, name: (skillById[p.prerequisite_skill2_id] || {}).name, level: p.prerequisite_level2 }
        : null,
      mustMatchFocus: !!p.must_match_focus,
      requiredFocusName: p.prerequisite_focus_id ? (focusNameById[p.prerequisite_focus_id] || null) : null
    });
  });

  const focusPrereqsByFocus = {};
  focusPrereqs.forEach(p => {
    (focusPrereqsByFocus[p.focus_id] = focusPrereqsByFocus[p.focus_id] || []).push({
      id: p.prerequisite_skill_id, name: (skillById[p.prerequisite_skill_id] || {}).name, level: p.prerequisite_level
    });
  });

  const focusDetailsByFocus = {};
  focusDetails.forEach(d => { (focusDetailsByFocus[d.focus_id] = focusDetailsByFocus[d.focus_id] || []).push(d); });

  const focusById = {};
  focuses.forEach(f => {
    const rows = focusDetailsByFocus[f.id] || [];
    const costByRace = {};
    rows.forEach(d => {
      if(d.race !== null) costByRace[d.race] = skillsBuildCostDetail(d, []);
    });
    focusById[f.id] = {
      id: f.id,
      name: f.name,
      desc: f.description || '',
      costDefault: skillsBuildCostDetail(f, []),
      costByRace: costByRace,
      prereqs: focusPrereqsByFocus[f.id] || []
    };
  });

  const focusesByType = {};
  focusTypeMap.forEach(m => {
    const focus = focusById[m.focus_id];
    if(!focus) return;
    (focusesByType[m.focus_type_id] = focusesByType[m.focus_type_id] || []).push(focus);
  });

  const detailsBySkill = {};
  details.forEach(d => { (detailsBySkill[d.skill_id] = detailsBySkill[d.skill_id] || []).push(d); });

  return skills.map(s => {
    const skillDetails = detailsBySkill[s.id] || [];
    const defaultRow = skillDetails.find(d => d.race === null) || skillDetails[0] || null;
    const costByRace = {};
    skillDetails.forEach(d => {
      if(d.race !== null) costByRace[d.race] = skillsBuildCostDetail(d, prereqGroupsBySkillDetail[d.id] || []);
    });

    return {
      id: s.id,
      category: skillsCategoryName(skillTypeNameById[s.skill_type_id] || ''),
      title: s.name,
      focusTypeId: s.focus_type_id,
      focusOptions: s.focus_type_id
        ? (focusesByType[s.focus_type_id] || []).slice().sort((a, b) => a.name.localeCompare(b.name))
        : [],
      overwriteCostForFocus: !!s.overwrite_cost_for_focus,
      desc: s.description || '',
      costDefault: defaultRow ? skillsBuildCostDetail(defaultRow, prereqGroupsBySkillDetail[defaultRow.id] || []) : null,
      costByRace: costByRace
    };
  });
}

function skillsOrderedCategories(allSkills){
  const byCategory = {};
  allSkills.forEach(s => { byCategory[s.category] = true; });
  const known = SKILL_CATEGORY_ORDER.filter(c => byCategory[c]);
  const unknown = Object.keys(byCategory).filter(c => !SKILL_CATEGORY_ORDER.includes(c)).sort();
  return [...known, ...unknown];
}

window.SKILL_CATEGORY_ORDER = SKILL_CATEGORY_ORDER;
window.skillsLoadCatalog = skillsLoadCatalog;
window.skillsOrderedCategories = skillsOrderedCategories;

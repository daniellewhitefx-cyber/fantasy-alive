
const CRAFTING_TRADE_ORDER = ['Armour Smith', 'Weapon Smith', 'Mechanic', 'Craftsman', 'Physician', 'Alchemist', 'Herbalist'];

const CRAFTING_TRADE_SKILL_NAMES = {
  'Armoursmith': 'Armour Smith',
  'Weaponsmith': 'Weapon Smith',
  'Mechanic': 'Mechanic',
  'Craftsman': 'Craftsman',
  'Physician': 'Physician',
  'Alchemist': 'Alchemist',
  'Herbalist': 'Herbalist'
};

function craftingRequirementLabel(name){
  if(name.endsWith(' - Spell')) return `knows ${name.slice(0, -' - Spell'.length)}`;
  const parts = name.split(' - ');
  const head = parts[0];
  const rest = parts.slice(1);
  if(head === 'Luxury') return `access to a ${rest.join(' ')}`;
  if(head === 'Tools') return `access to ${rest.slice().reverse().join(' ')} Tools`;
  return rest.length ? `access to ${head} ${rest.join(' ')}` : `access to ${head}`;
}

async function craftingFetchAllRows(table, select){
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

async function craftingLoadFromSheet(){
  const [items, categories, recipes, materials, requirements, skillReqs] = await Promise.all([
    craftingFetchAllRows('items', 'id, name, category_id'),
    craftingFetchAllRows('item_category', 'id, name'),
    craftingFetchAllRows('recipes', 'id, item_id, quantity_produced, hours'),
    craftingFetchAllRows('recipe_materials', 'recipe_id, item_id, quantity'),
    craftingFetchAllRows('recipe_requirements', 'recipe_id, item_id, quantity'),
    craftingFetchAllRows('recipe_skill_requirements', 'recipe_id, skill_name, level, focus_name')
  ]);

  const categoryNameById = {};
  categories.forEach(c => { categoryNameById[c.id] = c.name; });

  const itemById = {};
  items.forEach(i => { itemById[i.id] = { name: i.name, category: categoryNameById[i.category_id] || 'Uncategorized' }; });

  const materialsByRecipe = {};
  materials.forEach(m => {
    const item = itemById[m.item_id];
    if(!item) return;
    (materialsByRecipe[m.recipe_id] = materialsByRecipe[m.recipe_id] || []).push({ name: item.name, qty: Number(m.quantity) });
  });

  const requirementsByRecipe = {};
  requirements.forEach(r => {
    const item = itemById[r.item_id];
    if(!item) return;
    (requirementsByRecipe[r.recipe_id] = requirementsByRecipe[r.recipe_id] || []).push({ name: item.name, qty: r.quantity });
  });

  const skillReqsByRecipe = {};
  skillReqs.forEach(s => {
    (skillReqsByRecipe[s.recipe_id] = skillReqsByRecipe[s.recipe_id] || []).push(s);
  });

  const out = [];
  recipes.forEach(r => {
    const item = itemById[r.item_id];
    if(!item) return;

    const recipeMaterials = materialsByRecipe[r.id] || [];
    const materialsText = recipeMaterials.length
      ? recipeMaterials.map(m => `${m.qty} ${m.name}`).join(', ')
      : 'none';

    const recipeSkillReqs = skillReqsByRecipe[r.id] || [];
    const tradeReqs = recipeSkillReqs.filter(s => CRAFTING_TRADE_SKILL_NAMES[s.skill_name]);
    if(!tradeReqs.length) return;

    const otherSkillNotes = recipeSkillReqs
      .filter(s => !CRAFTING_TRADE_SKILL_NAMES[s.skill_name])
      .map(s => `${s.skill_name} ${s.level}${s.focus_name ? ' (' + s.focus_name + ' focus)' : ''}`);
    const requirementNotes = (requirementsByRecipe[r.id] || []).map(req => craftingRequirementLabel(req.name));
    const noteParts = [...otherSkillNotes, ...requirementNotes];
    const note = noteParts.length ? noteParts.join('; ') : null;

    tradeReqs.forEach(sr => {
      out.push({
        trade: CRAFTING_TRADE_SKILL_NAMES[sr.skill_name],
        name: item.name,
        category: item.category,
        levelRequired: sr.level,
        focusRequired: sr.focus_name || null,
        hours: r.hours === null || r.hours === undefined ? null : Number(r.hours),
        qtyProduced: r.quantity_produced,
        materialsText: materialsText,
        materials: recipeMaterials,
        note: note
      });
    });
  });

  return out;
}

function craftingOrderedTrades(allItems){
  const byTrade = {};
  allItems.forEach(i => { byTrade[i.trade] = true; });
  const known = CRAFTING_TRADE_ORDER.filter(t => byTrade[t]);
  const unknown = Object.keys(byTrade).filter(t => !CRAFTING_TRADE_ORDER.includes(t)).sort();
  return [...known, ...unknown];
}

window.CRAFTING_TRADE_ORDER = CRAFTING_TRADE_ORDER;
window.craftingLoadFromSheet = craftingLoadFromSheet;
window.craftingOrderedTrades = craftingOrderedTrades;

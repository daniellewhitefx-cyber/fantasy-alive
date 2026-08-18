// Loads the Crafting production list from the real item/recipe catalog
// (migrated from the legacy database into Supabase; see
// supabase/item-catalog-schema.sql), grouped by the trade skill(s) each
// recipe requires.

// Merchant and Labourer are trade skills but have no "craft a named item"
// mechanic in the rulebook (Merchant is detection/business-oriented,
// Labourer extracts raw materials generically, which the Work tab's
// Copper-earning mechanic already covers), so they're not part of this list.
const CRAFTING_TRADE_ORDER = ['Armour Smith', 'Weapon Smith', 'Mechanic', 'Craftsman', 'Physician', 'Alchemist', 'Herbalist'];

// The catalog's skill names differ slightly in spacing/casing from the
// trade names shown on this page (and from the character skill list).
const CRAFTING_TRADE_SKILL_NAMES = {
  'Armoursmith': 'Armour Smith',
  'Weaponsmith': 'Weapon Smith',
  'Mechanic': 'Mechanic',
  'Craftsman': 'Craftsman',
  'Physician': 'Physician',
  'Alchemist': 'Alchemist',
  'Herbalist': 'Herbalist'
};

// Supabase caps a single request at 1000 rows; several of these tables
// have more than that, so every table is paged through in full.
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
    if(!tradeReqs.length) return; // no craft-trade gate -- a knowledge item (Scroll/Formula/Tutor Book/...), sold in the Shoppe instead

    const otherSkillNotes = recipeSkillReqs
      .filter(s => !CRAFTING_TRADE_SKILL_NAMES[s.skill_name])
      .map(s => `${s.skill_name} ${s.level}${s.focus_name ? ' (' + s.focus_name + ' focus)' : ''}`);
    const requirementNotes = (requirementsByRecipe[r.id] || []).map(req => `access to ${req.name}`);
    const noteParts = [...otherSkillNotes, ...requirementNotes];
    const note = noteParts.length ? noteParts.join('; ') : null;

    tradeReqs.forEach(sr => {
      out.push({
        trade: CRAFTING_TRADE_SKILL_NAMES[sr.skill_name],
        name: item.name,
        category: item.category,
        levelRequired: sr.level,
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

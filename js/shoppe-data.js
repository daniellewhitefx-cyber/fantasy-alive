
const SHOPPE_CATEGORY_ORDER = [
  'Weapon', 'Armour', 'Equipment', 'Mechanical',
  'Herb', 'Ingredient', 'Magical Comp.', 'Mixture - Alch', 'Mixture - Herb', 'Potion/Oil',
  'Formula', 'Recipe', 'Scroll', 'Spell', 'Instruction', 'Tutor Book'
];

const SHOPPE_EXCLUDED_CATEGORIES = ['Luxuries'];

const SHOPPE_AVAILABILITY_ORDER = ['Common', 'Uncommon', 'Very Uncommon', 'Rare', 'Very Rare', 'Unique', 'Illegal', 'Super Powered'];

function shoppeAvailabilityTier(text){
  const idx = SHOPPE_AVAILABILITY_ORDER.findIndex(label => label.toLowerCase() === (text || '').toLowerCase());
  return idx === -1 ? 1 : idx + 1;
}

async function shoppeFetchAllRows(table, select){
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

async function shoppeLoadFromSheet(){
  const [items, categories, availabilities] = await Promise.all([
    shoppeFetchAllRows('items', 'name, copper_value, category_id, availability_id'),
    shoppeFetchAllRows('item_category', 'id, name'),
    shoppeFetchAllRows('item_availability', 'id, name')
  ]);

  const categoryNameById = {};
  categories.forEach(c => { categoryNameById[c.id] = c.name; });
  const availabilityById = {};
  availabilities.forEach(a => { availabilityById[a.id] = a.name; });

  return items
    .filter(item => categoryNameById[item.category_id] && availabilityById[item.availability_id])
    .filter(item => !SHOPPE_EXCLUDED_CATEGORIES.includes(categoryNameById[item.category_id]))
    .map(item => ({
      category: categoryNameById[item.category_id],
      name: item.name,
      costCopper: item.copper_value,
      availabilityText: availabilityById[item.availability_id],
      availabilityTier: item.availability_id
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

async function shoppeLoadLuxuries(){
  const [items, categories, recipes] = await Promise.all([
    shoppeFetchAllRows('items', 'id, name, copper_value, category_id'),
    shoppeFetchAllRows('item_category', 'id, name'),
    shoppeFetchAllRows('luxury_recipes', 'item_id, skill_text, ingredients_text, craft_hours, effect_text')
  ]);
  const luxuryCategoryId = (categories.find(c => c.name === 'Luxuries') || {}).id;
  const recipeByItem = {};
  recipes.forEach(r => { recipeByItem[r.item_id] = r; });
  return items
    .filter(item => item.category_id === luxuryCategoryId)
    .map(item => {
      const r = recipeByItem[item.id] || {};
      return {
        id: item.id,
        name: item.name,
        costCopper: item.copper_value,
        skillText: r.skill_text || null,
        ingredientsText: r.ingredients_text || null,
        craftHours: r.craft_hours || null,
        effectText: r.effect_text || null
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

async function shoppeLoadPriceTiers(){
  return shoppeFetchAllRows('merchant_price_tiers', 'merchant_level, buy_pct, sell_pct');
}

function shoppeMerchantPct(tiers, level){
  const lvl = Math.max(0, Math.min(10, level || 0));
  const row = (tiers || []).find(t => t.merchant_level === lvl);
  return row || { buy_pct: 100, sell_pct: 25 };
}

function shoppeOrderedCategories(allItems){
  const byCategory = {};
  allItems.forEach(i => { byCategory[i.category] = true; });
  const known = SHOPPE_CATEGORY_ORDER.filter(c => byCategory[c]);
  const unknown = Object.keys(byCategory).filter(c => !SHOPPE_CATEGORY_ORDER.includes(c)).sort();
  return [...known, ...unknown];
}

window.SHOPPE_CATEGORY_ORDER = SHOPPE_CATEGORY_ORDER;
window.SHOPPE_AVAILABILITY_ORDER = SHOPPE_AVAILABILITY_ORDER;
window.shoppeAvailabilityTier = shoppeAvailabilityTier;
window.shoppeLoadFromSheet = shoppeLoadFromSheet;
window.shoppeLoadLuxuries = shoppeLoadLuxuries;
window.shoppeLoadPriceTiers = shoppeLoadPriceTiers;
window.shoppeMerchantPct = shoppeMerchantPct;
window.shoppeOrderedCategories = shoppeOrderedCategories;

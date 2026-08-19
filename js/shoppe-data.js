// Loads the Shoppe item catalog from the real item catalog (migrated from
// the legacy database into Supabase; see supabase/item-catalog-schema.sql).

const SHOPPE_CATEGORY_ORDER = [
  'Weapon', 'Armour', 'Equipment', 'Mechanical',
  'Herb', 'Ingredient', 'Magical Comp.', 'Mixture - Alch', 'Mixture - Herb', 'Potion/Oil',
  'Formula', 'Recipe', 'Scroll', 'Spell', 'Instruction', 'Tutor Book'
];

// Luxuries aren't a Copper purchase like everything else here -- they're
// a per-event checklist (see the Luxuries tab / event_log_luxuries),
// matching how the old site tracked them. Keep them out of the Shoppe.
const SHOPPE_EXCLUDED_CATEGORIES = ['Luxuries'];

// The item catalog's own availability tier (1=Common up to 8=Super
// Powered), gated against a character's Merchant trade skill level.
const SHOPPE_AVAILABILITY_ORDER = ['Common', 'Uncommon', 'Very Uncommon', 'Rare', 'Very Rare', 'Unique', 'Illegal', 'Super Powered'];

function shoppeAvailabilityTier(text){
  const idx = SHOPPE_AVAILABILITY_ORDER.findIndex(label => label.toLowerCase() === (text || '').toLowerCase());
  return idx === -1 ? 1 : idx + 1;
}

// Supabase caps a single request at 1000 rows; the item table has more
// than that, so it's paged through in full.
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

// The Luxuries item list (id + name + reference Copper cost), for the
// per-event Luxuries checklist rather than the Shoppe purchase flow.
async function shoppeLoadLuxuries(){
  const [items, categories] = await Promise.all([
    shoppeFetchAllRows('items', 'id, name, copper_value, category_id'),
    shoppeFetchAllRows('item_category', 'id, name')
  ]);
  const luxuryCategoryId = (categories.find(c => c.name === 'Luxuries') || {}).id;
  return items
    .filter(item => item.category_id === luxuryCategoryId)
    .map(item => ({ id: item.id, name: item.name, costCopper: item.copper_value }))
    .sort((a, b) => a.name.localeCompare(b.name));
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
window.shoppeOrderedCategories = shoppeOrderedCategories;

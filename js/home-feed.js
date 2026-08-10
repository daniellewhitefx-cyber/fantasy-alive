const HOME_FEED_SUPABASE_URL = 'https://xdchluuvicuuqyqsejnq.supabase.co';
const HOME_FEED_SUPABASE_ANON_KEY = 'sb_publishable_JL4nY9-fcOAwYzwpwiJa9w_nypZCt99';
const homeFeedSupabase = window.supabase.createClient(HOME_FEED_SUPABASE_URL, HOME_FEED_SUPABASE_ANON_KEY);

async function homeFeedLoad(){
  const { data, error } = await homeFeedSupabase
    .from('home_feed_items')
    .select('id, title, description, image_url, link_url, badge, sort_order, created_at')
    .order('sort_order', { ascending: true })
    .order('created_at', { ascending: false });
  if(error) throw error;
  return data || [];
}

function homeFeedIsSafeUrl(url){
  return !/^\s*(javascript|data|vbscript):/i.test(url || '');
}

window.homeFeedLoad = homeFeedLoad;
window.homeFeedIsSafeUrl = homeFeedIsSafeUrl;

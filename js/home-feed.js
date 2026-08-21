const HOME_FEED_SUPABASE_URL = 'https://xdchluuvicuuqyqsejnq.supabase.co';
const HOME_FEED_SUPABASE_ANON_KEY = 'sb_publishable_JL4nY9-fcOAwYzwpwiJa9w_nypZCt99';
const homeFeedSupabase = window.supabase.createClient(HOME_FEED_SUPABASE_URL, HOME_FEED_SUPABASE_ANON_KEY);

const HOME_FEED_IMAGE_BUCKET = 'home-feed-images';

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

async function homeFeedGetAdminSession(){
  const { data } = await homeFeedSupabase.auth.getSession();
  const session = data && data.session;
  if(!session) return null;
  const isAdmin = !!(session.user.app_metadata && session.user.app_metadata.site_admin);
  return { user: session.user, isAdmin };
}

async function homeFeedUploadImage(file){
  file = await stripImageExif(file);
  const ext = (file.name.split('.').pop() || 'png').toLowerCase();
  const path = Date.now() + '-' + Math.random().toString(36).slice(2, 8) + '.' + ext;
  const { error } = await homeFeedSupabase.storage.from(HOME_FEED_IMAGE_BUCKET).upload(path, file);
  if(error) throw error;
  const { data } = homeFeedSupabase.storage.from(HOME_FEED_IMAGE_BUCKET).getPublicUrl(path);
  return data.publicUrl;
}

async function homeFeedCreate({ title, description, imageUrl, linkUrl, badge, sortOrder }){
  const { error } = await homeFeedSupabase.rpc('home_feed_create', {
    p_title: title, p_description: description, p_image_url: imageUrl,
    p_link_url: linkUrl, p_badge: badge, p_sort_order: sortOrder || 0
  });
  if(error) throw error;
}

async function homeFeedUpdate(id, { title, description, imageUrl, linkUrl, badge, sortOrder }){
  const { error } = await homeFeedSupabase.rpc('home_feed_update', {
    p_id: id, p_title: title, p_description: description, p_image_url: imageUrl,
    p_link_url: linkUrl, p_badge: badge, p_sort_order: sortOrder || 0
  });
  if(error) throw error;
}

async function homeFeedDelete(id){
  const { error } = await homeFeedSupabase.rpc('home_feed_delete', { p_id: id });
  if(error) throw error;
}

window.homeFeedLoad = homeFeedLoad;
window.homeFeedIsSafeUrl = homeFeedIsSafeUrl;
window.homeFeedGetAdminSession = homeFeedGetAdminSession;
window.homeFeedUploadImage = homeFeedUploadImage;
window.homeFeedCreate = homeFeedCreate;
window.homeFeedUpdate = homeFeedUpdate;
window.homeFeedDelete = homeFeedDelete;

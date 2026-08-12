
const SUPABASE_URL = 'https://xdchluuvicuuqyqsejnq.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_JL4nY9-fcOAwYzwpwiJa9w_nypZCt99';
const membersSupabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

function waitForSidebar(){
  return new Promise(resolve => {
    (function check(){
      if(document.getElementById('member-account-name')) resolve();
      else setTimeout(check, 30);
    })();
  });
}

function markActiveNavLink(){
  const current = location.pathname.split('/').pop();
  document.querySelectorAll('.side-nav a[data-page]').forEach(a => {
    if(a.getAttribute('data-page') === current) a.classList.add('active');
  });
}

async function membersSignOut(){
  await membersSupabase.auth.signOut();
  window.location.href = 'login.html';
}

async function needsCharacterCreation(playerId){
  const current = location.pathname.split('/').pop();
  if(current === 'character-creator.html') return false;

  const { count } = await membersSupabase
    .from('characters')
    .select('id', { count: 'exact', head: true })
    .eq('player_id', playerId);

  if((count || 0) > 0) return false;

  const { data: profile } = await membersSupabase.from('profiles').select('is_cast').eq('id', playerId).maybeSingle();
  return !(profile && profile.is_cast);
}

async function refreshNotifBadge(){
  const badge = document.getElementById('member-notif-badge');
  if(!badge) return;
  try{
    const { data } = await membersSupabase.rpc('notifications_summary');
    const total = data && data.total ? data.total : 0;
    if(total > 0){
      badge.textContent = total;
      badge.style.display = 'inline-block';
    } else {
      badge.style.display = 'none';
    }
  } catch(err){
  }
}

async function refreshMessagesBadge(){
  const badge = document.getElementById('member-messages-badge');
  if(!badge) return;
  try{
    const { data } = await membersSupabase.rpc('message_unread_count');
    const count = data || 0;
    if(count > 0){
      badge.textContent = count;
      badge.style.display = 'inline-block';
    } else {
      badge.style.display = 'none';
    }
  } catch(err){
  }
}

async function initMembersPage(){
  const { data } = await membersSupabase.auth.getSession();
  if(!data.session){
    window.location.href = 'login.html';
    return;
  }

  try{ await membersSupabase.rpc('ensure_profile'); } catch(err){}

  if(await needsCharacterCreation(data.session.user.id)){
    window.location.href = 'character-creator.html';
    return;
  }

  await waitForSidebar();

  const user = data.session.user;
  const displayName = (user.user_metadata && user.user_metadata.display_name) || user.email;
  document.getElementById('member-account-name').textContent = displayName;
  markActiveNavLink();

  const meta = user.app_metadata || {};
  const isSiteAdmin = !!meta.site_admin;
  const staffLinks = [
    ['member-manage-characters-link', meta.character_staff || isSiteAdmin],
    ['member-banking-tools-link', meta.bank_staff || isSiteAdmin],
    ['member-manage-auctions-link', meta.auction_staff || isSiteAdmin],
    ['member-permissions-link', isSiteAdmin],
  ];
  let anyStaffAccess = false;
  staffLinks.forEach(([id, allowed]) => {
    if(!allowed) return;
    anyStaffAccess = true;
    const el = document.getElementById(id);
    if(el) el.style.display = '';
  });
  if(anyStaffAccess){
    const staffGroup = document.getElementById('member-staff-group');
    if(staffGroup) staffGroup.style.display = '';
  }

  window.faCurrentUser = user;
  document.body.classList.add('members-ready');
  document.dispatchEvent(new CustomEvent('fa-members-ready', { detail: { user } }));
  refreshNotifBadge();
  refreshMessagesBadge();
}

window.membersSignOut = membersSignOut;

if(document.readyState === 'loading'){
  document.addEventListener('DOMContentLoaded', initMembersPage);
} else {
  initMembersPage();
}

// Shared login gate for every page in the Members area. Include this
// after the Supabase script tag and after js/include.js. It redirects
// signed-out visitors to login.html, then fills in the signed-in
// player's name and highlights the current page in the sidebar.

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

async function initMembersPage(){
  const { data } = await membersSupabase.auth.getSession();
  if(!data.session){
    window.location.href = 'login.html';
    return;
  }

  await waitForSidebar();

  const user = data.session.user;
  const displayName = (user.user_metadata && user.user_metadata.display_name) || user.email;
  document.getElementById('member-account-name').textContent = displayName;
  markActiveNavLink();

  document.body.classList.add('members-ready');
}

window.membersSignOut = membersSignOut;

if(document.readyState === 'loading'){
  document.addEventListener('DOMContentLoaded', initMembersPage);
} else {
  initMembersPage();
}

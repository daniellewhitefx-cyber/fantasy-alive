
const SUPABASE_URL = 'https://xdchluuvicuuqyqsejnq.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_JL4nY9-fcOAwYzwpwiJa9w_nypZCt99';
const membersSupabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Supabase caps a single request at 1000 rows. Any unfiltered (or loosely
// filtered) full-table fetch -- profiles chief among them, since it's one
// row per registered player -- needs to page through in full rather than
// silently dropping everything past the cutoff.
async function faFetchAllRows(table, select){
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
window.faFetchAllRows = faFetchAllRows;

function loadTutorialScript(){
  return new Promise(resolve => {
    if(window.faTutorialLoaded){ resolve(); return; }
    const s = document.createElement('script');
    s.src = 'js/tutorial.js';
    s.onload = resolve;
    s.onerror = resolve;
    document.body.appendChild(s);
  });
}

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
  // Also skip on the two waiver pages themselves, or a player with zero
  // characters gets bounced to character-creator.html while still in the
  // middle of the waiver gate, which bounces them right back, forever.
  if(current === 'character-creator.html' || current === 'liability-waiver.html' || current === 'emergency-contact.html') return false;

  const { count } = await membersSupabase
    .from('characters')
    .select('id', { count: 'exact', head: true })
    .eq('player_id', playerId);

  if((count || 0) > 0) return false;

  const { data: profile } = await membersSupabase.from('profiles').select('is_cast, is_townsperson').eq('id', playerId).maybeSingle();
  return !(profile && (profile.is_cast || profile.is_townsperson));
}

// New players must sign the liability waiver and submit an emergency
// contact form before doing anything else on the site, including creating
// a character. Returns the page to redirect to, or null if both are done
// (or the current page is one of the two waiver pages themselves).
async function needsWaiverCompletion(playerId){
  const current = location.pathname.split('/').pop();
  if(current === 'liability-waiver.html' || current === 'emergency-contact.html') return null;

  const { data: waiver } = await membersSupabase
    .from('liability_waivers')
    .select('player_id')
    .eq('player_id', playerId)
    .maybeSingle();
  if(!waiver) return 'liability-waiver.html';

  const { data: contact } = await membersSupabase
    .from('emergency_contact_forms')
    .select('player_id')
    .eq('player_id', playerId)
    .maybeSingle();
  if(!contact) return 'emergency-contact.html';

  return null;
}

// Waivers don't expire outright, but a year on, we want players nudged to
// confirm their liability waiver and emergency contact info are still
// accurate rather than silently relying on year-old details. This is a
// soft reminder (dismissible, shown at most once a day), not a hard gate
// like needsWaiverCompletion above.
const WAIVER_RENEWAL_DAYS = 365;

async function checkWaiverExpiry(playerId){
  const current = location.pathname.split('/').pop();
  if(current === 'liability-waiver.html' || current === 'emergency-contact.html') return [];

  const cutoff = new Date(Date.now() - WAIVER_RENEWAL_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const stale = [];

  const { data: waiver } = await membersSupabase
    .from('liability_waivers')
    .select('signed_at')
    .eq('player_id', playerId)
    .maybeSingle();
  if(waiver && waiver.signed_at && waiver.signed_at < cutoff){
    stale.push({ label: 'Liability Waiver', href: 'liability-waiver.html' });
  }

  const { data: contact } = await membersSupabase
    .from('emergency_contact_forms')
    .select('updated_at')
    .eq('player_id', playerId)
    .maybeSingle();
  if(contact && contact.updated_at && contact.updated_at < cutoff){
    stale.push({ label: 'Emergency Contact Form', href: 'emergency-contact.html' });
  }

  return stale;
}

function showWaiverRenewalPrompt(items){
  const today = new Date().toISOString().slice(0, 10);
  try{
    if(localStorage.getItem('fa-waiver-renewal-prompt-date') === today) return;
    localStorage.setItem('fa-waiver-renewal-prompt-date', today);
  } catch(err){}

  const overlay = document.createElement('div');
  overlay.id = 'fa-waiver-renewal-overlay';
  overlay.innerHTML = `
    <div class="fa-waiver-renewal-modal">
      <h3>Time for a quick check-in</h3>
      <p>It's been about a year since you last confirmed the following, so they're due for a fresh look:</p>
      <ul>${items.map(i => `<li>${i.label}</li>`).join('')}</ul>
      <p>Please review and resign whenever it's convenient.</p>
      <div class="fa-waiver-renewal-actions">
        <button class="fa-waiver-renewal-dismiss" type="button">Remind Me Later</button>
        <a class="fa-waiver-renewal-go btn-gold" href="${items[0].href}">Review Now</a>
      </div>
    </div>
  `;
  document.body.appendChild(overlay);
  overlay.querySelector('.fa-waiver-renewal-dismiss').addEventListener('click', () => overlay.remove());
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

async function refreshRequestsBadge(){
  const badge = document.getElementById('member-requests-badge');
  if(!badge) return;
  try{
    const { data } = await membersSupabase.rpc('requests_pending_count');
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
  const current = location.pathname.split('/').pop();

  const { data } = await membersSupabase.auth.getSession();
  if(!data.session){
    window.location.href = 'login.html';
    return;
  }

  try{ await membersSupabase.rpc('ensure_profile'); } catch(err){}

  const waiverRedirect = await needsWaiverCompletion(data.session.user.id);
  if(waiverRedirect){
    window.location.href = waiverRedirect;
    return;
  }

  if(await needsCharacterCreation(data.session.user.id)){
    window.location.href = 'character-creator.html';
    return;
  }

  checkWaiverExpiry(data.session.user.id).then(stale => {
    if(stale.length) showWaiverRenewalPrompt(stale);
  });

  await waitForSidebar();

  const user = data.session.user;
  const displayName = (user.user_metadata && user.user_metadata.display_name) || user.email;
  document.getElementById('member-account-name').textContent = displayName;
  markActiveNavLink();

  // Nav is trimmed down for Cast-only and Townsperson-only accounts, since
  // neither has a character to spend coin/XP/OC on or attend events as.
  // The moment either account creates a real character, hasCharacters
  // flips true and the full nav comes back, regardless of whether the
  // is_cast/is_townsperson flag itself ever gets cleared.
  const { count: charCount } = await membersSupabase
    .from('characters')
    .select('id', { count: 'exact', head: true })
    .eq('player_id', user.id);
  const hasCharacters = (charCount || 0) > 0;

  const { data: acctProfile } = await membersSupabase.from('profiles').select('is_cast, is_townsperson, has_seen_tutorial').eq('id', user.id).maybeSingle();
  const isCastOnly = !hasCharacters && !!(acctProfile && acctProfile.is_cast);
  const isTownspersonOnly = !hasCharacters && !!(acctProfile && acctProfile.is_townsperson);
  window.faIsCastOnly = isCastOnly;
  window.faIsTownspersonOnly = isTownspersonOnly;

  function hideNavLinks(ids){
    ids.forEach(id => {
      const el = document.getElementById(id);
      if(el) el.style.display = 'none';
    });
  }

  if(isCastOnly){
    hideNavLinks(['member-teachable-skills-link', 'member-bank-link', 'member-inventory-link', 'member-friends-link']);
    const eventsGroup = document.getElementById('member-events-group');
    if(eventsGroup) eventsGroup.style.display = 'none';
  }

  if(isTownspersonOnly){
    hideNavLinks(['member-bank-link', 'member-auction-link', 'member-oc-submission-link', 'member-xp-oc-log-link', 'member-inventory-link', 'member-friends-link', 'member-teachable-skills-link']);
    // Every item in the Progress group is hidden for a Townsperson, so
    // hide the now-empty group heading too, the same way Events is hidden.
    const eventsGroup = document.getElementById('member-events-group');
    if(eventsGroup) eventsGroup.style.display = 'none';
    const progressGroup = document.getElementById('member-progress-group');
    if(progressGroup) progressGroup.style.display = 'none';
  }

  const meta = user.app_metadata || {};
  const isSiteAdmin = !!meta.site_admin;
  let canSeeRequests = isSiteAdmin;
  if(!canSeeRequests){
    try{
      const { data } = await membersSupabase.rpc('fa_is_logistics_or_admin');
      canSeeRequests = !!data;
    } catch(err){
    }
  }
  let canSeeBackstoryRequests = isSiteAdmin || meta.role === 'lore_editor';
  if(!canSeeBackstoryRequests){
    try{
      const { data } = await membersSupabase.rpc('fa_is_backstory_viewer');
      canSeeBackstoryRequests = !!data;
    } catch(err){
    }
  }
  let canSeePlot = isSiteAdmin;
  if(!canSeePlot){
    try{
      const { data } = await membersSupabase.rpc('fa_is_plot_or_admin');
      canSeePlot = !!data;
    } catch(err){
    }
  }
  const staffLinks = [
    ['member-manage-characters-link', meta.character_staff || isSiteAdmin],
    ['member-banking-tools-link', meta.bank_staff || isSiteAdmin],
    ['member-manage-auctions-link', meta.auction_staff || isSiteAdmin],
    ['member-requests-link', canSeeRequests || canSeeBackstoryRequests],
    ['member-plot-link', canSeePlot],
    ['member-permissions-link', isSiteAdmin],
    ['member-print-sheets-link', canSeeRequests],
    ['member-registrations-link', canSeeRequests],
    ['member-print-tags-link', canSeeRequests],
    ['member-waivers-link', canSeeRequests],
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
  refreshRequestsBadge();

  // The walkthrough tutorial auto-plays once, the first time a player
  // reaches the members area -- which for a brand-new account is the
  // liability waiver page, since that's the first hard gate. It's never
  // auto-played on top of the emergency contact or character-creator
  // forms themselves (the player is already mid-flow at that point), but
  // the Replay Tutorial sidebar link works everywhere.
  const skipAutoTutorialPages = ['emergency-contact.html', 'character-creator.html'];
  loadTutorialScript().then(() => {
    if(!skipAutoTutorialPages.includes(current) && !(acctProfile && acctProfile.has_seen_tutorial)){
      if(window.faOpenTutorial) window.faOpenTutorial();
    }
  });
}

window.membersSignOut = membersSignOut;

if(document.readyState === 'loading'){
  document.addEventListener('DOMContentLoaded', initMembersPage);
} else {
  initMembersPage();
}

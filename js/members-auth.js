
const SUPABASE_URL = 'https://xdchluuvicuuqyqsejnq.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_JL4nY9-fcOAwYzwpwiJa9w_nypZCt99';
const membersSupabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

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

function faMaxBirthdayDate(){
  const d = new Date();
  d.setFullYear(d.getFullYear() - 18);
  return d.toISOString().slice(0, 10);
}
window.faMaxBirthdayDate = faMaxBirthdayDate;

function faIsAtLeast18(dateStr){
  if(!dateStr) return false;
  const bday = new Date(dateStr + 'T00:00:00');
  if(isNaN(bday.getTime())) return false;
  const today = new Date();
  let age = today.getFullYear() - bday.getFullYear();
  const m = today.getMonth() - bday.getMonth();
  if(m < 0 || (m === 0 && today.getDate() < bday.getDate())) age--;
  return age >= 18;
}
window.faIsAtLeast18 = faIsAtLeast18;

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
  if(current === 'character-creator.html' || current === 'liability-waiver.html' || current === 'emergency-contact.html') return false;

  const { count } = await membersSupabase
    .from('characters')
    .select('id', { count: 'exact', head: true })
    .eq('player_id', playerId);

  if((count || 0) > 0) return false;

  const { data: profile } = await membersSupabase.from('profiles').select('is_cast, is_townsperson').eq('id', playerId).maybeSingle();
  return !(profile && (profile.is_cast || profile.is_townsperson));
}

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

async function refreshBugReportsBadge(){
  const badge = document.getElementById('member-bug-reports-badge');
  if(!badge) return;
  try{
    const { data } = await membersSupabase.rpc('bug_reports_open_count');
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

  const { data: lockProfile } = await membersSupabase.from('profiles').select('locked, locked_reason').eq('id', data.session.user.id).maybeSingle();
  if(lockProfile && lockProfile.locked){
    await membersSupabase.auth.signOut();
    const params = new URLSearchParams({ locked: '1' });
    if(lockProfile.locked_reason) params.set('reason', lockProfile.locked_reason);
    window.location.href = 'login.html?' + params.toString();
    return;
  }

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
  insertBugReportButton();
  markActiveNavLink();

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
    ['member-manage-downtime-link', canSeeRequests],
    ['member-plot-link', canSeePlot],
    ['member-bug-reports-link', isSiteAdmin],
    ['member-printing-link', canSeeRequests],
    ['member-registrations-link', canSeeRequests],
    ['member-manage-players-link', canSeeRequests],
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
  refreshBugReportsBadge();

  const skipAutoTutorialPages = ['emergency-contact.html', 'character-creator.html'];
  loadTutorialScript().then(() => {
    if(!skipAutoTutorialPages.includes(current) && !(acctProfile && acctProfile.has_seen_tutorial)){
      if(window.faOpenTutorial) window.faOpenTutorial();
    }
  });
}

function insertBugReportButton(){
  if(document.getElementById('bug-report-btn')) return;

  const nameEl = document.getElementById('member-account-name');
  if(!nameEl) return;

  const btn = document.createElement('button');
  btn.type = 'button';
  btn.id = 'bug-report-btn';
  btn.className = 'bug-report-btn';
  btn.textContent = 'Report a Bug';
  nameEl.insertAdjacentElement('afterend', btn);

  const overlay = document.createElement('div');
  overlay.id = 'bug-report-overlay';
  overlay.className = 'bug-report-overlay';
  overlay.style.display = 'none';
  overlay.innerHTML = `
    <div class="bug-report-backdrop"></div>
    <div class="bug-report-modal">
      <button type="button" class="bug-report-close" aria-label="Close">&times;</button>
      <h3>Report a Bug</h3>
      <p class="page-subhead">Tell us what went wrong -- what you were doing, what you expected, and what happened instead. It gets sent straight to the admins.</p>
      <textarea id="bug-report-text" rows="6" placeholder="What's broken?"></textarea>
      <div class="bug-report-actions">
        <button type="button" class="btn-outline" id="bug-report-cancel">Cancel</button>
        <button type="button" class="btn-gold" id="bug-report-send">Send Report</button>
      </div>
      <p class="reg-success-note" id="bug-report-success" style="display:none;"></p>
      <p class="reg-error-note" id="bug-report-error" style="display:none;"></p>
    </div>
  `;
  document.body.appendChild(overlay);

  const textEl = document.getElementById('bug-report-text');
  const successEl = document.getElementById('bug-report-success');
  const errorEl = document.getElementById('bug-report-error');
  const sendBtn = document.getElementById('bug-report-send');

  const openModal = () => {
    textEl.value = '';
    successEl.style.display = 'none';
    errorEl.style.display = 'none';
    overlay.style.display = 'block';
    textEl.focus();
  };
  const closeModal = () => { overlay.style.display = 'none'; };

  btn.addEventListener('click', openModal);
  document.getElementById('bug-report-cancel').addEventListener('click', closeModal);
  document.querySelector('.bug-report-close').addEventListener('click', closeModal);
  document.querySelector('.bug-report-backdrop').addEventListener('click', closeModal);

  sendBtn.addEventListener('click', async () => {
    successEl.style.display = 'none';
    errorEl.style.display = 'none';

    const { error } = await membersSupabase.rpc('bug_report_submit', {
      p_description: textEl.value,
      p_page_url: window.location.pathname
    });

    if(error){
      errorEl.textContent = error.message;
      errorEl.style.display = 'block';
      return;
    }

    textEl.value = '';
    successEl.textContent = 'Thanks -- your report has been sent to the admins.';
    successEl.style.display = 'block';
  });
}

window.membersSignOut = membersSignOut;

if(document.readyState === 'loading'){
  document.addEventListener('DOMContentLoaded', initMembersPage);
} else {
  initMembersPage();
}

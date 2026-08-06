// Shared event/registration data for the Members area. Include this
// after js/members-auth.js and before each page's own script. Provides
// a single source of truth for the event list and the endpoint used to
// both submit and check registrations, so register.html and any other
// page (like characters.html) agree on the same data.

const FA_REGISTRATION_ENDPOINT = 'https://script.google.com/macros/s/AKfycbzDzyi7jPDy_EwueBo_q8CPeOUY2sBVjWPBKRBBPoY5wKJpX8WMdzerUKOnI3Kx6614pA/exec';

const FA_EVENTS = [
  { value:'aug-7-9', label:'Aug 7-9, Welcome to the Mysterious Faire',
    days:[{ id:'fri', label:'Friday, Aug 7' }, { id:'sat', label:'Saturday, Aug 8' }, { id:'sun', label:'Sunday, Aug 9' }] },
  { value:'sep-4-6', label:'Sep 4-6, The Silent Guilds',
    days:[{ id:'fri', label:'Friday, Sep 4' }, { id:'sat', label:'Saturday, Sep 5' }, { id:'sun', label:'Sunday, Sep 6' }] },
  { value:'oct-2-4', label:'Oct 2-4, Ruins of the Lakes Region',
    days:[{ id:'fri', label:'Friday, Oct 2' }, { id:'sat', label:'Saturday, Oct 3' }, { id:'sun', label:'Sunday, Oct 4' }] }
];

// The site currently treats the first event in the list as "the next
// event" everywhere (nav banner, homepage banner). Keep this list
// ordered with the soonest event first.
const FA_NEXT_EVENT = FA_EVENTS[0];

// Resolves once the signed-in user is known, whether members-auth.js
// has already finished its session check or is still working on it.
function faGetCurrentUser(){
  if(window.faCurrentUser) return Promise.resolve(window.faCurrentUser);
  return new Promise(resolve => {
    document.addEventListener('fa-members-ready', e => resolve(e.detail.user), { once: true });
    setTimeout(() => resolve(window.faCurrentUser || null), 5000);
  });
}

// Asks the registration spreadsheet (via the Apps Script Web App) whether
// this player already has a registration row for this event + who/character
// combination. Returns { registered: false } or { registered: true, registration: {...} }.
async function faCheckRegistration(eventLabel, who, characterName, playerEmail){
  const url = FA_REGISTRATION_ENDPOINT
    + '?action=check'
    + '&event=' + encodeURIComponent(eventLabel)
    + '&who=' + encodeURIComponent(who)
    + '&character=' + encodeURIComponent(characterName || '')
    + '&email=' + encodeURIComponent(playerEmail || '');
  const res = await fetch(url, { cache: 'no-store' });
  if(!res.ok) throw new Error('Registration check failed (' + res.status + ')');
  return res.json();
}

window.FA_REGISTRATION_ENDPOINT = FA_REGISTRATION_ENDPOINT;
window.FA_EVENTS = FA_EVENTS;
window.FA_NEXT_EVENT = FA_NEXT_EVENT;
window.faGetCurrentUser = faGetCurrentUser;
window.faCheckRegistration = faCheckRegistration;

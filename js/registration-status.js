const FA_REGISTRATION_ENDPOINT = 'https://script.google.com/macros/s/AKfycbzDzyi7jPDy_EwueBo_q8CPeOUY2sBVjWPBKRBBPoY5wKJpX8WMdzerUKOnI3Kx6614pA/exec';

const FA_EVENT_DEFS = [
  { start: '2026-09-11', end: '2026-09-13' },
  { start: '2026-10-30', end: '2026-11-01' },
  { start: '2026-11-27', end: '2026-11-29' }
];

const FA_MONTH_SHORT = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const FA_MONTH_LONG = ['January','February','March','April','May','June','July','August','September','October','November','December'];
const FA_WEEKDAY_LONG = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
const FA_WEEKDAY_ID = ['sun','mon','tue','wed','thu','fri','sat'];

function faParseDateOnly(iso){
  const parts = iso.split('-').map(Number);
  return new Date(parts[0], parts[1] - 1, parts[2]);
}

function faDateOnly(d){
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function faShortRangeLabel(start, end){
  if(start.getMonth() === end.getMonth()){
    return FA_MONTH_SHORT[start.getMonth()] + ' ' + start.getDate() + '–' + end.getDate();
  }
  return FA_MONTH_SHORT[start.getMonth()] + ' ' + start.getDate() + ' – ' + FA_MONTH_SHORT[end.getMonth()] + ' ' + end.getDate();
}

function faLongRangeLabel(start, end){
  if(start.getMonth() === end.getMonth()){
    return FA_MONTH_LONG[start.getMonth()] + ' ' + start.getDate() + ' to ' + end.getDate();
  }
  return FA_MONTH_LONG[start.getMonth()] + ' ' + start.getDate() + ' to ' + FA_MONTH_LONG[end.getMonth()] + ' ' + end.getDate();
}

function faEventSlug(start, end){
  const prefix = FA_MONTH_SHORT[start.getMonth()].toLowerCase() + '-' + start.getDate();
  if(start.getMonth() === end.getMonth()) return prefix + '-' + end.getDate();
  return prefix + '-' + FA_MONTH_SHORT[end.getMonth()].toLowerCase() + '-' + end.getDate();
}

function faDaysInRange(start, end){
  const days = [];
  const cur = new Date(start);
  while(cur <= end){
    days.push({
      id: FA_WEEKDAY_ID[cur.getDay()],
      label: FA_WEEKDAY_LONG[cur.getDay()] + ', ' + FA_MONTH_SHORT[cur.getMonth()] + ' ' + cur.getDate()
    });
    cur.setDate(cur.getDate() + 1);
  }
  return days;
}

function faBuildEvent(def){
  const start = faParseDateOnly(def.start);
  const end = faParseDateOnly(def.end);
  return {
    value: faEventSlug(start, end),
    label: faShortRangeLabel(start, end),
    longLabel: faLongRangeLabel(start, end),
    start: start,
    end: end,
    days: faDaysInRange(start, end)
  };
}

const FA_TODAY = faDateOnly(new Date());

const FA_EVENTS = FA_EVENT_DEFS
  .map(faBuildEvent)
  .filter(e => e.end >= FA_TODAY)
  .sort((a, b) => a.start - b.start);

const FA_NEXT_EVENT = FA_EVENTS.length ? FA_EVENTS[0] : null;

function faWaitForElement(selector){
  return new Promise(resolve => {
    (function check(){
      const el = document.querySelector(selector);
      if(el) resolve(el);
      else setTimeout(check, 30);
    })();
  });
}

async function faUpdateNextEventDisplays(){
  const dateEl = await faWaitForElement('.next-event-date');
  dateEl.textContent = FA_NEXT_EVENT ? FA_NEXT_EVENT.label : 'TBA';

  const chip = document.getElementById('fa-next-event-chip');
  if(chip) chip.textContent = FA_NEXT_EVENT ? FA_NEXT_EVENT.longLabel : 'To be announced';
}

faUpdateNextEventDisplays();

function faGetCurrentUser(){
  if(window.faCurrentUser) return Promise.resolve(window.faCurrentUser);
  return new Promise(resolve => {
    document.addEventListener('fa-members-ready', e => resolve(e.detail.user), { once: true });
    setTimeout(() => resolve(window.faCurrentUser || null), 5000);
  });
}

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

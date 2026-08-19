const FA_EVENT_DEFS = [
  { start: '2026-01-24', end: '2026-01-24' },
  { start: '2026-02-13', end: '2026-02-15' },
  { start: '2026-03-13', end: '2026-03-15' },
  { start: '2026-04-10', end: '2026-04-12' },
  { start: '2026-05-08', end: '2026-05-10' },
  { start: '2026-06-12', end: '2026-06-14' },
  { start: '2026-07-03', end: '2026-07-05' },
  { start: '2026-08-07', end: '2026-08-09' },
  { start: '2026-09-11', end: '2026-09-13' },
  { start: '2026-10-10', end: '2026-10-10' },
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
  if(start.getTime() === end.getTime()){
    return FA_MONTH_SHORT[start.getMonth()] + ' ' + start.getDate();
  }
  if(start.getMonth() === end.getMonth()){
    return FA_MONTH_SHORT[start.getMonth()] + ' ' + start.getDate() + '–' + end.getDate();
  }
  return FA_MONTH_SHORT[start.getMonth()] + ' ' + start.getDate() + ' – ' + FA_MONTH_SHORT[end.getMonth()] + ' ' + end.getDate();
}

function faLongRangeLabel(start, end){
  if(start.getTime() === end.getTime()){
    return FA_MONTH_LONG[start.getMonth()] + ' ' + start.getDate();
  }
  if(start.getMonth() === end.getMonth()){
    return FA_MONTH_LONG[start.getMonth()] + ' ' + start.getDate() + ' to ' + end.getDate();
  }
  return FA_MONTH_LONG[start.getMonth()] + ' ' + start.getDate() + ' to ' + FA_MONTH_LONG[end.getMonth()] + ' ' + end.getDate();
}

function faEventSlug(start, end){
  const prefix = FA_MONTH_SHORT[start.getMonth()].toLowerCase() + '-' + start.getDate();
  if(start.getTime() === end.getTime()) return prefix;
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
    isDayEvent: start.getTime() === end.getTime(),
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

const FA_PAST_EVENTS = FA_EVENT_DEFS
  .map(faBuildEvent)
  .filter(e => e.end < FA_TODAY)
  .sort((a, b) => b.start - a.start);

const FA_ALL_EVENTS = FA_EVENT_DEFS
  .map(faBuildEvent)
  .map(e => Object.assign(e, { isPast: e.end < FA_TODAY }))
  .sort((a, b) => a.start - b.start);

// The log for an event opens two weeks before it starts at 6pm, and
// closes the Monday before the event at 9pm.
function faLogWindow(event){
  const opensAt = new Date(event.start);
  opensAt.setDate(opensAt.getDate() - 14);
  opensAt.setHours(18, 0, 0, 0);

  const closesAt = new Date(event.start);
  const day = closesAt.getDay();
  let daysBack = day === 0 ? 6 : day - 1;
  if(daysBack === 0) daysBack = 7;
  closesAt.setDate(closesAt.getDate() - daysBack);
  closesAt.setHours(21, 0, 0, 0);

  // TEMPORARY (testing only): force the Sep 11-13 log open early so it
  // can be tried out before its real Aug 28 open date. Remove this block
  // once testing is done.
  if(event.value === 'sep-11-13') opensAt.setTime(Date.now() - 60000);

  return { opensAt, closesAt };
}

function faLogStatus(event){
  const { opensAt, closesAt } = faLogWindow(event);
  const now = new Date();
  if(now < opensAt) return { state: 'not-open', opensAt, closesAt };
  if(now > closesAt) return { state: 'closed', opensAt, closesAt };
  return { state: 'open', opensAt, closesAt };
}

// Downtime hours available to spend on Training during an event's log:
// 100 hours per week between the previous event's end and this event's
// start. The first tracked event has no prior event to measure from,
// so it gets a flat 400 hours (about four weeks' worth).
function faTrainingHoursBudget(event){
  const idx = FA_EVENT_DEFS.findIndex(d => faEventSlug(faParseDateOnly(d.start), faParseDateOnly(d.end)) === event.value);
  if(idx > 0){
    const prevEnd = faParseDateOnly(FA_EVENT_DEFS[idx - 1].end);
    const weeks = Math.round((event.start - prevEnd) / (7 * 24 * 60 * 60 * 1000));
    return Math.max(0, weeks * 100);
  }
  return 400;
}

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
window.FA_EVENTS = FA_EVENTS;
window.FA_NEXT_EVENT = FA_NEXT_EVENT;
window.FA_PAST_EVENTS = FA_PAST_EVENTS;
window.FA_ALL_EVENTS = FA_ALL_EVENTS;
window.faGetCurrentUser = faGetCurrentUser;
window.faLogWindow = faLogWindow;
window.faLogStatus = faLogStatus;
window.faTrainingHoursBudget = faTrainingHoursBudget;

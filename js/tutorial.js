(function(){

const TUTORIAL_STEPS = [
  { target: null, title: 'Welcome to Fantasy Alive!', body: "Let's take a quick, friendly tour of the Members area so you always know where to find things. It only takes a couple of minutes, and you can skip it whenever you like." },
  { target: 'member-register-link', title: 'Register for an Event', body: "This is where you sign up for events. You can register as one of your characters, as Cast/NPC for the weekend, or as a Townsperson if you'd rather just roleplay without building a full character." },
  { target: 'member-liability-waiver-link', title: 'Consent & Waiver', body: 'Everyone signs this before doing anything else on the site. It only takes a minute, and you only have to fill it out once.' },
  { target: 'member-emergency-contact-link', title: 'Emergency Contact', body: "This one's required too. It just makes sure we know who to reach if something comes up at an event." },
  { target: 'member-home-link', title: 'Home', body: 'Your dashboard. Your next event, quick links, and anything else worth knowing at a glance.' },
  { target: 'member-account-link', title: 'Account Info', body: 'Update your display name and other account details here.' },
  { target: 'member-notifications-link', title: 'Notifications', body: "Approvals, decisions, and updates land here. That little badge means something's new." },
  { target: 'member-messages-link', title: 'Messages', body: 'Send and receive messages with other players and staff.' },
  { target: 'member-characters-link', title: 'Characters', body: "Create and manage your characters here, up to two at a time. You can always add one later, even if you started as Cast or a Townsperson." },
  { target: 'member-bank-link', title: 'Bank', body: 'Track the coin your character has earned and spent.' },
  { target: 'member-inventory-link', title: 'Inventory', body: 'See the items and tags your character is carrying.' },
  { target: 'member-auction-link', title: 'Auction', body: "Bid real money on items up for auction." },
  { target: 'member-friends-link', title: 'Friends', body: "Connect with other players you've met in and out of character." },
  { target: 'member-kudos-link', title: 'Kudos', body: 'Give and receive shout-outs for great roleplay or a helping hand.' },
  { target: 'member-oc-submission-link', title: 'OC Submission', body: 'Submit real-world contributions, like driving, casting, or cleanup, to earn OC between events.' },
  { target: 'member-xp-oc-log-link', title: 'XP/OC Log', body: "A full history of the XP and OC your character has earned and spent." },
  { target: 'member-teachable-skills-link', title: 'Teachable Skills', body: 'See what skills your characters can teach to other players.' },
  { target: 'member-current-event-link', title: 'Current Event', body: "Once an event's log window opens, this is where you spend your downtime hours." },
  { target: 'member-past-events-link', title: 'Past Events', body: "A record of every event you've attended." },
  { target: 'member-future-events-link', title: 'Future Events', body: "See what's coming up so you can plan ahead." },
  { target: 'member-replay-tutorial-link', title: 'Come Back Anytime', body: 'Forget something? Click here whenever you want to run this tour again.' },
  { target: null, title: "That's Everything!", body: "You're all set. Welcome to Fantasy Alive, adventurer, we'll see you at the next event!" }
];

let overlayEls = null;
let currentStep = 0;
let tutorialActive = false;
let steps = TUTORIAL_STEPS;

// Cast-only and Townsperson-only accounts have some sidebar links hidden
// (see members-auth.js). Skip those steps rather than spotlighting an
// invisible, zero-size element.
function isNavHidden(el){
  if(el.style.display === 'none') return true;
  const group = el.closest('.side-nav-group');
  return !!(group && group.style.display === 'none');
}

function getActiveSteps(){
  return TUTORIAL_STEPS.filter(step => {
    if(!step.target) return true;
    const el = document.getElementById(step.target);
    return !!(el && !isNavHidden(el));
  });
}

function buildOverlay(){
  if(overlayEls) return overlayEls;

  const clickblock = document.createElement('div');
  clickblock.className = 'tut-clickblock';

  const spotlight = document.createElement('div');
  spotlight.className = 'tut-spotlight';

  const tooltip = document.createElement('div');
  tooltip.className = 'tut-tooltip';
  tooltip.innerHTML =
    '<div class="tut-tooltip-title" id="tut-title"></div>' +
    '<p class="tut-tooltip-body" id="tut-body"></p>' +
    '<div class="tut-tooltip-progress" id="tut-progress"></div>' +
    '<div class="tut-tooltip-actions">' +
      '<button type="button" class="tut-btn tut-btn-skip" id="tut-skip">Skip Tutorial</button>' +
      '<div class="tut-tooltip-nav">' +
        '<button type="button" class="tut-btn tut-btn-back" id="tut-back">Back</button>' +
        '<button type="button" class="tut-btn tut-btn-next" id="tut-next">Next</button>' +
      '</div>' +
    '</div>';

  document.body.appendChild(clickblock);
  document.body.appendChild(spotlight);
  document.body.appendChild(tooltip);

  tooltip.querySelector('#tut-skip').addEventListener('click', endTutorial);
  tooltip.querySelector('#tut-back').addEventListener('click', () => goToStep(currentStep - 1));
  tooltip.querySelector('#tut-next').addEventListener('click', () => {
    if(currentStep >= steps.length - 1) endTutorial();
    else goToStep(currentStep + 1);
  });

  window.addEventListener('resize', () => { if(tutorialActive) positionForStep(steps[currentStep]); });

  overlayEls = { clickblock, spotlight, tooltip };
  return overlayEls;
}

function positionTooltip(tooltip, rect){
  const margin = 16;
  // Matches the CSS width:320px / max-width:calc(100vw - 32px) rule, so
  // the clamps below account for the tooltip's actual footprint instead
  // of just its top-left corner.
  const effectiveWidth = Math.min(320, window.innerWidth - margin * 2);
  const effectiveHeight = 220;
  let top = rect.top;
  let left = rect.right + margin;

  if(left + effectiveWidth > window.innerWidth - margin){
    left = rect.left;
    top = rect.bottom + margin;
    if(top + effectiveHeight > window.innerHeight - margin){
      top = rect.top - effectiveHeight - margin;
    }
  }

  left = Math.min(Math.max(margin, left), window.innerWidth - margin - effectiveWidth);
  top = Math.min(Math.max(margin, top), window.innerHeight - margin - effectiveHeight);

  tooltip.style.top = top + 'px';
  tooltip.style.left = left + 'px';
}

function centerTooltip(tooltip){
  tooltip.style.top = '50%';
  tooltip.style.left = '50%';
  tooltip.style.transform = 'translate(-50%, -50%)';
}

function positionForStep(step){
  const { spotlight, tooltip } = buildOverlay();
  const target = step.target ? document.getElementById(step.target) : null;

  if(target){
    const toggle = document.getElementById('side-nav-toggle-input');
    if(toggle && !toggle.checked) toggle.checked = true;
    target.scrollIntoView({ block: 'center', behavior: 'auto' });
  }

  requestAnimationFrame(() => {
    if(target){
      const rect = target.getBoundingClientRect();
      const pad = 8;
      spotlight.style.display = 'block';
      spotlight.style.top = (rect.top - pad) + 'px';
      spotlight.style.left = (rect.left - pad) + 'px';
      spotlight.style.width = (rect.width + pad * 2) + 'px';
      spotlight.style.height = (rect.height + pad * 2) + 'px';
      tooltip.style.transform = 'none';
      positionTooltip(tooltip, rect);
    } else {
      // No target for this step (the welcome/closing cards): keep the
      // spotlight element itself as the sole darkening layer, just sized
      // to nothing so its shadow covers the entire screen with no hole.
      spotlight.style.display = 'block';
      spotlight.style.top = '50%';
      spotlight.style.left = '50%';
      spotlight.style.width = '0px';
      spotlight.style.height = '0px';
      centerTooltip(tooltip);
    }
  });
}

function renderStep(){
  const step = steps[currentStep];
  const { tooltip } = buildOverlay();
  tooltip.querySelector('#tut-title').textContent = step.title;
  tooltip.querySelector('#tut-body').textContent = step.body;
  tooltip.querySelector('#tut-progress').textContent = 'Step ' + (currentStep + 1) + ' of ' + steps.length;

  const backBtn = tooltip.querySelector('#tut-back');
  backBtn.classList.toggle('tut-hidden', currentStep === 0);

  const nextBtn = tooltip.querySelector('#tut-next');
  nextBtn.textContent = currentStep === steps.length - 1 ? "Let's Go!" : 'Next';

  positionForStep(step);
}

function goToStep(idx){
  currentStep = Math.max(0, Math.min(steps.length - 1, idx));
  renderStep();
}

function startTutorial(){
  tutorialActive = true;
  currentStep = 0;
  steps = getActiveSteps();
  const { clickblock, tooltip } = buildOverlay();
  clickblock.style.display = 'block';
  tooltip.style.display = 'block';
  renderStep();
}

async function endTutorial(){
  tutorialActive = false;
  if(overlayEls){
    overlayEls.clickblock.style.display = 'none';
    overlayEls.spotlight.style.display = 'none';
    overlayEls.tooltip.style.display = 'none';
  }
  try{ await membersSupabase.rpc('player_mark_tutorial_seen'); } catch(err){}
}

window.faOpenTutorial = startTutorial;
window.faTutorialLoaded = true;

})();

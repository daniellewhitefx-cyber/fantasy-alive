function loadIncludes(){
  const targets = document.querySelectorAll('[data-include]');
  const loads = [];
  targets.forEach(el => {
    const file = el.getAttribute('data-include');
    const load = fetch(file)
      .then(res => {
        if(!res.ok) throw new Error('Could not load ' + file + ' (' + res.status + ')');
        return res.text();
      })
      .then(html => { el.innerHTML = html; })
      .catch(err => {
        console.error(err);
        el.innerHTML = '<p style="padding:1rem;color:#a33b2f;">Failed to load ' + file + '</p>';
      });
    loads.push(load);
    if(file === 'partials/header.html') load.then(injectSiteSearch);
    if(file === 'partials/footer.html') load.then(setFooterCopyrightYear);
  });
}

function injectSiteSearch(){
  if(document.querySelector('script[src="js/site-search.js"]')) return;
  const script = document.createElement('script');
  script.src = 'js/site-search.js';
  document.body.appendChild(script);
}

function setFooterCopyrightYear(){
  const el = document.getElementById('footer-copyright-year');
  if(el) el.textContent = new Date().getFullYear();
}

function initBackToTop(){
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'back-to-top-btn';
  btn.setAttribute('aria-label', 'Back to top');
  btn.innerHTML = '<svg viewBox="0 0 24 24"><path d="M12 4l-8 8h5v8h6v-8h5z"/></svg>';
  btn.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));
  document.body.appendChild(btn);

  window.addEventListener('scroll', () => {
    btn.classList.toggle('visible', window.scrollY > 600);
  }, { passive: true });
}

if(document.readyState === 'loading'){
  document.addEventListener('DOMContentLoaded', loadIncludes);
  document.addEventListener('DOMContentLoaded', initBackToTop);
} else {
  loadIncludes();
  initBackToTop();
}

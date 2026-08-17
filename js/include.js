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

// partials/header.html is loaded via innerHTML, so any <script> tag inside
// it never runs -- the site search module is injected as a real script
// element here instead, once the header (and its search button) exists.
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

if(document.readyState === 'loading'){
  document.addEventListener('DOMContentLoaded', loadIncludes);
} else {
  loadIncludes();
}

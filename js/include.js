// Fetches whatever partial file is named in each [data-include] element
// and injects it in place. Used for the shared header and footer so
// they only ever need to be edited in one place: /partials/
function loadIncludes(){
  const targets = document.querySelectorAll('[data-include]');
  targets.forEach(el => {
    const file = el.getAttribute('data-include');
    fetch(file)
      .then(res => {
        if(!res.ok) throw new Error('Could not load ' + file + ' (' + res.status + ')');
        return res.text();
      })
      .then(html => { el.innerHTML = html; })
      .catch(err => {
        console.error(err);
        el.innerHTML = '<p style="padding:1rem;color:#a33b2f;">Failed to load ' + file + '</p>';
      });
  });
}

if(document.readyState === 'loading'){
  document.addEventListener('DOMContentLoaded', loadIncludes);
} else {
  loadIncludes();
}

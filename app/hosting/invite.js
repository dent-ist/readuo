'use strict';
const match = /^\/invite\/([A-Z0-9]{6})$/.exec(location.pathname);
if (match && !location.search && !location.hash) {
  const code = match[1];
  document.getElementById('invitation').hidden = false;
  document.getElementById('invalid').hidden = true;
  document.getElementById('code').textContent = `${code.slice(0, 3)}-${code.slice(3)}`;
  const fallback = encodeURIComponent(`https://readuo-b2f24.web.app/invite/${code}`);
  document.getElementById('open').href = `intent://readuo-b2f24.web.app/invite/${code}#Intent;scheme=https;package=com.zipdosa.readuo;S.browser_fallback_url=${fallback};end`;
}

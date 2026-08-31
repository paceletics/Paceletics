(function(){
'use strict';
if(typeof document==='undefined'||typeof document.write!=='function')return;
document.write('<script src="paceletics-shell-core.js?v=1.2.0"><\/script>');
const page=(location.pathname.split('/').pop()||'').toLowerCase();
if(page==='athlete.html'){
  document.write('<script src="paceletics-athlete-profile-powerof10.js?v=1.0.0-dev"><\/script>');
}
})();

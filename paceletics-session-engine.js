(function(){
'use strict';
if(typeof document==='undefined'||typeof document.write!=='function')return;
document.write('<script src="paceletics-session-engine-core.js?v=1.0.0"><\/script>');
if(/Athlete Dashboard/i.test(document.title)){
  document.write('<script src="paceletics-powerof10.js?v=1.0.0"><\/script>');
}
})();

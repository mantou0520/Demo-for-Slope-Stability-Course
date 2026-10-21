/* UI 冒烟测试：用打桩的 DOM / Canvas 把整段 <script> 跑一遍，
 * 覆盖三个标签页、三种方法、参数滑块、表行点击等分支，抓运行时报错。
 * 运行： node verify_ui_smoke.js
 */
const fs = require('fs');
const html = fs.readFileSync(__dirname + '/index.html', 'utf8');
const m = html.match(/<script>([\s\S]*)<\/script>/);
if (!m) { console.error('未找到 <script>'); process.exit(1); }
const code = m[1];

/* ---------- Canvas 2D 打桩 ---------- */
function makeCtx(){
  const base = {
    measureText: () => ({ width: 20 }),
    createRadialGradient: () => ({ addColorStop(){} }),
    createLinearGradient: () => ({ addColorStop(){} }),
    getImageData: () => ({ data: [] })
  };
  return new Proxy(base, {
    get(t,k){ if (k in t) return t[k]; return () => {}; },
    set(t,k,v){ t[k] = v; return true; }
  });
}

/* ---------- 元素打桩 ---------- */
const HANDLERS = new Map();     /* element -> {event: fn} */
function makeEl(id, tag){
  const d = {
    id, tagName: tag || 'div',
    clientWidth: 900, clientHeight: 560,
    value: '', max: '100', min: '0',
    textContent: '', innerHTML: '',
    dataset: {}, style: {},
    width: 900, height: 560,
    classList: {
      _s: new Set(['tab']),
      add(c){ this._s.add(c); }, remove(c){ this._s.delete(c); },
      contains(c){ return this._s.has(c); },
      toggle(c,v){ if (v) this._s.add(c); else this._s.delete(c); }
    }
  };
  const el = new Proxy(d, {
    get(t,k){
      if (k === 'addEventListener') return (ev, fn) => {
        if (!HANDLERS.has(el)) HANDLERS.set(el, {});
        HANDLERS.get(el)[ev] = fn;
      };
      if (k === 'getContext') return () => makeCtx();
      if (k === 'querySelector') return (sel) => {
        t._q = t._q || {};
        if (!t._q[sel]) t._q[sel] = makeEl(id + '::' + sel, sel);
        return t._q[sel];
      };
      if (k === 'closest') return () => null;
      if (k === 'setPointerCapture' || k === 'releasePointerCapture') return () => {};
      if (k === 'focus') return () => {};
      if (k === 'getBoundingClientRect') return () => ({left:0, top:0, width:900, height:560});
      if (k in t) return t[k];
      return () => {};
    },
    set(t,k,v){ t[k] = v; return true; }
  });
  return el;
}

const els = {};
const TAB_DEFS = ['v1','v2','v3'];
const tabs = TAB_DEFS.map(v => { const e = makeEl('tab_'+v,'div'); e.dataset.v = v; e.classList._s = new Set(['tab']); return e; });
const views = TAB_DEFS.map(v => { const e = makeEl('view_'+v,'section'); e.id = v; return e; });
const mmBtns = ['general','swedish','bishop'].map(mm => { const e = makeEl('mm_'+mm,'button'); e.dataset.mm = mm; return e; });
const slices = [];

const rafQ = [], timers = [];
global.window = {
  devicePixelRatio: 2,
  location: { hash: '' },
  addEventListener: (ev, fn) => { (global.__WIN__ = global.__WIN__ || {})[ev] = fn; },
  requestAnimationFrame: (fn) => { rafQ.push(fn); return rafQ.length; }
};
global.document = {
  readyState: 'complete',
  getElementById: (id) => els[id] || (els[id] = makeEl(id)),
  querySelectorAll: (sel) => {
    if (sel === '.tab') return tabs;
    if (sel === '.view') return views;
    if (sel === '.methodsel button') return mmBtns;
    return [];
  },
  addEventListener: () => {}
};
global.setTimeout = (fn) => { timers.push(fn); return timers.length; };
global.requestAnimationFrame = global.window.requestAnimationFrame;

let count = 0;
function flush(){
  while (rafQ.length){ const f = rafQ.shift(); f(); count++; }
  while (timers.length){ const f = timers.shift(); f(); count++; }
}
function click(el, ev){
  const h = HANDLERS.get(el);
  if (h && h[ev || 'click']) { h[ev || 'click']({ clientX: 400, clientY: 300, pointerId: 1, preventDefault(){}, deltaY: 100, target: el }); count++; }
}

try {
  eval(code);
  flush();

  const resHTML = els.res ? els.res.innerHTML : '';
  const has4 = (resHTML.match(/class="item/g) || []).length;
  console.log('\n[1] 初始渲染');
  console.log('  结果卡片条数 =', has4, has4 >= 4 ? 'ok' : 'FAIL');
  console.log('  土条表行数 =', ((els.tbl.querySelector('tbody').innerHTML.match(/<tr/g) || []).length), '(应为 8)');

  /* 标签页切换 */
  console.log('\n[2] 标签页');
  for (const t of tabs) { click(t); flush(); }
  console.log('  三个标签页切换完成，无异常');

  /* 三种方法（第 2 页） */
  console.log('\n[3] 未知量计数：三种方法');
  for (const b of mmBtns){
    click(b);
    flush();
    console.log('  ' + b.dataset.mm + '：未知量 ' + els.unkTotal.textContent + '，方程 ' + els.eqTotal.textContent +
      '，状态 ' + (els.statusBox.className || ''));
  }

  /* 第 2 页 n 滑块：2..40 */
  console.log('\n[4] n 从 2 到 40 遍历');
  const n2 = els.sN2;
  for (let v=2; v<=40; v++){
    n2.value = String(v);
    click(n2, 'input');
    flush();
  }
  console.log('  完成，末值：未知量 ' + els.unkTotal.textContent + '（n=40，瑞典法应为 81）');

  /* 第 1 页各类滑块 */
  console.log('\n[5] 第 1 页参数与滑弧滑块');
  const ids = ['sH','sM','sG','sC','sP','sR','sN','sX','sY','sRad'];
  for (const id of ids){
    const el = els[id];
    const vals = id === 'sP' ? [0, 5, 15, 30, 40]
               : id === 'sN' ? [3, 8, 20, 40]
               : id === 'sR' ? [0, 0.2, 0.6]
               : id === 'sM' ? [0.5, 1.5, 4]
               : id === 'sH' ? [4, 10, 30]
               : id === 'sX' ? [-4, 8, 40]
               : id === 'sY' ? [2, 12, 40]
               : id === 'sRad' ? [3, 15, 50]
               : id === 'sG' ? [14, 18, 22] : [0, 20, 60];
    for (const v of vals){ el.value = String(v); click(el, 'input'); flush(); }
  }
  console.log('  全部滑块遍历完成');

  /* 按钮 */
  console.log('\n[6] 按钮');
  click(els.btnReset); flush();
  const readFs = () => parseFloat((els.res.innerHTML.match(/class="fs">([\d.]+)/) || [])[1]);
  const f0 = readFs();
  click(els.btnSearch); flush();
  const f1 = readFs();
  console.log('  恢复默认 F_s =', f0);
  console.log('  搜索后   F_s =', f1, (f1 <= f0 + 1e-9) ? '（不劣于初始滑弧，ok）' : '（反而变大，FAIL）');
  if (!(f1 <= f0 + 1e-9)) throw new Error('最危险滑弧搜索结果劣于初始滑弧');
  click(els.btnReset); flush();
  console.log('  恢复默认完成');

  /* 画布交互 */
  console.log('\n[7] 画布拖动与滚轮');
  const c1 = els.c1;
  click(c1, 'pointerdown');
  click(c1, 'pointermove');
  click(c1, 'pointerup');
  click(c1, 'wheel');
  flush();
  console.log('  指针/滚轮事件处理完成');

  /* 表格行点击 */
  console.log('\n[8] 表行点击（closest 打桩返回 null，走保护分支）');
  click(els.tbl);
  flush();
  console.log('  无异常');

  console.log('\n[UI 冒烟测试] 完成：执行 ' + count + ' 次回调，无异常抛出。\n');
} catch (e){
  console.error('\n[UI 冒烟测试] 失败：', e && e.stack ? e.stack : e);
  process.exit(1);
}

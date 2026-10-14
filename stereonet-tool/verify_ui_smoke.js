/* UI 冒烟测试：用极简 DOM/Canvas 打桩，把 index.html 里的 <script> 完整执行一遍，
   并对 半球约定 × 投影方式 × 动画进度 × 显示开关 × 各种产状 做穷举调用，
   用于捕获运行时报错（ReferenceError / TypeError 等）。为开发/二次修改时的自检工具。
   运行： node verify_ui_smoke.js                                          */
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

/* ---------- Canvas 2D 上下文打桩 ---------- */
function makeCtx(){
  const data = {
    measureText: () => ({ width: 10 }),
    createRadialGradient: () => ({ addColorStop(){} }),
    createLinearGradient: () => ({ addColorStop(){} })
  };
  return new Proxy(data, {
    get(t,k){ return (k in t) ? t[k] : ()=>{}; },
    set(t,k,v){ t[k] = v; return true; }
  });
}
/* ---------- 元素打桩 ---------- */
const els = {};
const EL_HANDLERS = new Map();          // 元素 -> {事件: [回调]}，便于测试脚本主动触发
const valueOf = (id) => {
  if (id === 'a_2' || id === 'q_2') return '210';
  if (/d$|phi/.test(id)) return '45';
  return '120';
};
function makeEl(id, dataset){
  const data = {
    id, clientWidth: 680, clientHeight: 520, value: valueOf(id),
    dataset: dataset || {}, textContent: '', style: {},
    classList: { add(){}, remove(){}, contains(){ return true; }, toggle(){} },
    getContext: () => makeCtx(),
    setPointerCapture(){}, releasePointerCapture(){}, focus(){}
  };
  return new Proxy(data, {
    get(t,k){ if (k in t) return t[k]; if (k === 'addEventListener') return ()=>{}; return ()=>{}; },
    set(t,k,v){ t[k] = v; return true; }
  });
}
/* 带真实事件登记的元素（用于标签页等需要主动触发的元素） */
function makeElLive(id, dataset){
  const data = {
    id, clientWidth: 680, clientHeight: 520, value: valueOf(id),
    dataset: dataset || {}, textContent: '', style: {},
    classList: { add(){}, remove(){}, contains(){ return true; }, toggle(){} },
    getContext: () => makeCtx(),
    setPointerCapture(){}, releasePointerCapture(){}, focus(){},
    addEventListener: (ev, fn) => {
      const rec = EL_HANDLERS.get(data) || {};
      (rec[ev] = rec[ev] || []).push(fn);
      EL_HANDLERS.set(data, rec);
    }
  };
  return data;
}
const qsel = {};
const rafQueue = [];
const listeners = {};
global.window = {
  devicePixelRatio: 1,
  addEventListener: (ev, fn) => { (listeners[ev] = listeners[ev] || []).push(fn); }
};
global.document = {
  getElementById: (id) => els[id] || (els[id] = makeEl(id)),
  querySelectorAll: (sel) => {
    if (!qsel[sel]){
      if (sel === '.tab')       qsel[sel] = ['v1','v2','v3'].map(v => makeElLive('tab_'+v, {v}));
      else if (sel === '.view') qsel[sel] = ['v1','v2','v3'].map(v => makeElLive('view_'+v));
      else if (sel === 'canvas')qsel[sel] = [document.getElementById('c3d'), document.getElementById('cs2d')];
      else                      qsel[sel] = [];
    }
    return qsel[sel];
  },
  addEventListener: () => {}
};
global.requestAnimationFrame = (fn) => { rafQueue.push(fn); return rafQueue.length; };
global.performance = { now: () => 0 };
global.location = { hash: '' };
global.history = { replaceState(){} };

/* ---------- 载入脚本 + 追加穷举自检 ---------- */
const harness = `
;(function(){
  const out = [];
  const hems = ['lower','upper'], modes = ['angle','area'], anims = [0.001, 0.5, 1];
  const atts = [[0,0],[120,45],[359,90],[200,60],[90,90],[30,10],[180,1]];
  let n = 0;
  for (const h of hems) for (const m of modes) for (const a of anims){
    S1.hemi = h; S1.mode = m; S1.anim = a;
    for (const [az,dip] of atts){
      for (const k of ['gc','rays','pole','dip','grid']) S1.show[k] = true;
      S1.show.rays = (a > 0.001); S1.show.gc = (a > 0.001);
      S1.az = az; S1.dip = dip;
      draw3D(); draw2D(); updateReadout(); n++;
    }
  }
  /* 关掉所有显示开关，走另一条分支 */
  S1.hemi='lower'; S1.mode='angle'; S1.anim=1; S1.az=120; S1.dip=45;
  for (const k of ['gc','rays','pole','dip','grid']) S1.show[k] = false;
  draw3D(); draw2D(); updateReadout(); n++;
  for (const k of ['gc','rays','pole','dip','grid']) S1.show[k] = true;
  /* 边坡判别面板：正常 + 极端输入 */
  const setv = (id,v)=>{ document.getElementById(id).value = String(v); };
  for (const [cs,csd,ns,nsd,j1,j1d,j2,j2d,phi] of [
      [110,60,110,25,115,45,250,75,30],
      [0,90,0,0,90,90,0,90,0],
      [359,1,180,89,270,89,180,1,60],
      [110,60,110,25,110,60,110,60,30]   /* 两组结构面重合 -> 交棱线退化 */
  ]){
    setv('a_cs',cs); setv('a_csd',csd); setv('a_ns',ns); setv('a_nsd',nsd);
    setv('a_1',j1); setv('a_1d',j1d); setv('a_2',j2); setv('a_2d',j2d); setv('a_phi',phi);
    drawCase(); n++;
  }
  global.__SMOKE__ = { n, judge: document.getElementById('judge').innerHTML.length,
                       ro: document.getElementById('ro').innerHTML.length };
})();
`;

try {
  eval(script + harness);
  /* 触发 load 事件处理函数（注册 DOM 事件、绑定控件、首次绘制） */
  (listeners['load'] || []).forEach(fn => fn());
  /* 模拟点击三个标签页：走一遍 activate 的"切换显示 → rAF 重绘"分支。
     这一步专门用来防"隐藏页里的画布尺寸为 0 → 切过去空白"这类只在切页时才暴露的问题 */
  let tabSwitches = 0;
  const tabs = document.querySelectorAll('.tab');
  for (const v of ['v2', 'v3', 'v1', 'v2']){
    const t = tabs.find(x => x.dataset.v === v);
    ((EL_HANDLERS.get(t) || {}).click || []).forEach(fn => fn());
    tabSwitches++;
  }
  /* 执行 activate / 首次绘制注册到 rAF 的回调，再跑一遍 resize 回调 */
  rafQueue.slice().forEach(fn => { try { fn(); } catch(e){ throw e; } });
  (listeners['resize'] || []).forEach(fn => fn());

  const s = global.__SMOKE__ || {};
  console.log(`\n[UI 冒烟测试] 完成：绘图组合 ${s.n} 次 + 标签页切换 ${tabSwitches} 次，无异常抛出。`);
  console.log(`  读数面板已生成 ${s.ro} 字符；判别结果区已生成 ${s.judge} 字符。`);
  console.log('  覆盖：2 种半球约定 × 2 种投影网 × 3 个动画阶段 × 7 组产状 + 全开关关闭分支'
            + ' + 4 组边坡算例（含退化输入）+ 三页切换\n');
} catch (e) {
  console.error('\n[UI 冒烟测试] 抛出异常：');
  console.error(e && e.stack ? e.stack : e);
  process.exit(1);
}

/* 核心数学校验：把 index.html 里 CORE MATH 段抽出来逐项断言。
 * 运行： node verify_core_math.js
 */
const fs = require('fs');
const html = fs.readFileSync(__dirname + '/index.html', 'utf8');
const m = html.match(/CORE MATH START[\s\S]*?\*\/([\s\S]*?)\/\* =+ CORE MATH END/);
if (!m) { console.error('未找到 CORE MATH 段'); process.exit(1); }
eval(m[1]);

let pass = 0, fail = 0;
function T(name, ok, info){
  if (ok) { pass++; console.log('  ok   ' + name + (info ? '  [' + info + ']' : '')); }
  else { fail++; console.log('  FAIL ' + name + (info ? '  [' + info + ']' : '')); }
}
const near = (a,b,tol) => Math.abs(a-b) <= (tol===undefined?1e-9:tol);

const base = {H:10, m:1.5, gamma:18, c:20, phi:15, ru:0, n:8, xc:8.25, yc:12.5, R:15};

console.log('\n[1] 坡面线');
T('groundY(mH) = H', near(groundY(base.m*base.H, base.H, base.m), base.H));
T('groundY(0) = 0', near(groundY(0, base.H, base.m), 0));
T('坡面中点 y = x/m', near(groundY(0.5*base.m*base.H, base.H, base.m), 0.5*base.H));
T('坡脚外侧恒为 0', near(groundY(-3, base.H, base.m), 0));

console.log('\n[2] 滑弧与分条几何');
const c0 = {xc:base.xc, yc:base.yc, R:base.R};
const span = findSpan(c0, base.H, base.m);
T('默认圆心能交出两个交点', !!span, span ? `x1=${span.x1.toFixed(2)} x2=${span.x2.toFixed(2)}` : 'null');
const sl = buildSlices(c0, span, base);
T('分条数 = n', sl.length === base.n);
T('各条宽度之和 = 交点间距', near(sl.reduce((a,s)=>a+s.b,0), span.x2-span.x1, 1e-9));
T('Σ l·cosα = 交点间距（弧长投影一致）',
  near(sl.reduce((a,s)=>a+s.l*s.cosA,0), span.x2-span.x1, 1e-9));
T('两个端点恰在坡面上',
  Math.abs(groundY(span.x1,base.H,base.m)-arcY(span.x1,c0)) < 1e-6 &&
  Math.abs(groundY(span.x2,base.H,base.m)-arcY(span.x2,c0)) < 1e-6);
T('α 满足 sinα = (x−x₀)/R',
  sl.every(s => near(s.sinA, (s.xm-c0.xc)/c0.R, 1e-12)));

console.log('\n[3] 力矩一致性：ΣW·sinα 应与 ΣW(x−x₀)/R 相等');
{
  const a = sl.reduce((s,x)=>s + x.W*x.sinA, 0);
  const b = sl.reduce((s,x)=>s + x.W*(x.xm-c0.xc)/c0.R, 0);
  T('两种写法一致', near(a,b,1e-9), `${a.toFixed(6)} vs ${b.toFixed(6)}`);
}

console.log('\n[4] φ=0 时三法必须重合（最有力的自检）');
{
  const S = Object.assign({}, base, {phi:0});
  const sp = findSpan(c0, S.H, S.m);
  const ss = buildSlices(c0, sp, S);
  const sw = fsSwedish(ss,S).F, bi = fsBishop(ss,S).F, p0 = fsPhi0(ss,c0,S.c).F;
  T('瑞典 = Bishop', near(sw, bi, 1e-8), `${sw.toFixed(8)} / ${bi.toFixed(8)}`);
  T('瑞典 = 整体圆弧法', near(sw, p0, 1e-8), `${sw.toFixed(8)} / ${p0.toFixed(8)}`);
  T('数值有限且为正（φ=0 时该深滑弧 Fs 可小于 1，属正常）',
    isFinite(sw) && sw > 0.1 && sw < 6, sw.toFixed(3));
}

console.log('\n[5] 随 φ 单调递增');
{
  let prev = -1, mono = true, vals = [];
  for (const phi of [0,5,10,15,20,25,30]){
    const S = Object.assign({}, base, {phi:phi});
    const sp = findSpan(c0,S.H,S.m), ss = buildSlices(c0,sp,S);
    const f = fsBishop(ss,S).F;
    vals.push(f.toFixed(3));
    if (f <= prev) mono = false;
    prev = f;
  }
  T('Bishop 随 φ 递增', mono, vals.join(' < '));
}

console.log('\n[6] Bishop 应不小于瑞典法（同一滑弧、φ>0）');
{
  const sp = findSpan(c0,base.H,base.m), ss = buildSlices(c0,sp,base);
  const sw = fsSwedish(ss,base).F, bi = fsBishop(ss,base).F;
  T('Bishop ≥ 瑞典', bi >= sw, `${bi.toFixed(3)} vs ${sw.toFixed(3)}`);
  T('相差不超过 30%（否则可能程序中漏项）', (bi-sw)/sw < 0.30, ((bi-sw)/sw*100).toFixed(1) + '%');
}

console.log('\n[7] n 增大应收敛');
{
  const get = n => {
    const S = Object.assign({}, base, {n:n});
    const sp = findSpan(c0,S.H,S.m), ss = buildSlices(c0,sp,S);
    return fsBishop(ss,S).F;
  };
  const f8 = get(8), f30 = get(30), f80 = get(80);
  T('n=30 与 n=80 相差 < 1%', Math.abs(f30-f80)/f80 < 0.01, `${f30.toFixed(4)} / ${f80.toFixed(4)}`);
  T('n=8 与 n=80 相差 < 5%', Math.abs(f8-f80)/f80 < 0.05, `${f8.toFixed(4)} / ${f80.toFixed(4)}`);
}

console.log('\n[8] Janbu 与 Bishop 量级接近');
{
  const sp = findSpan(c0,base.H,base.m), ss = buildSlices(c0,sp,base);
  const bi = fsBishop(ss,base).F, ja = fsJanbu(ss,base).F;
  T('相差 < 15%', Math.abs(ja-bi)/bi < 0.15, `${ja.toFixed(3)} vs ${bi.toFixed(3)}`);
}

console.log('\n[9] 孔压使 Fs 下降');
{
  const S1 = Object.assign({}, base, {ru:0});
  const S2 = Object.assign({}, base, {ru:0.4});
  const sp = findSpan(c0,S1.H,S1.m);
  const f1 = fsBishop(buildSlices(c0,sp,S1),S1).F;
  const f2 = fsBishop(buildSlices(c0,sp,S2),S2).F;
  T('ru=0.4 时 Fs 更小', f2 < f1, `${f1.toFixed(3)} → ${f2.toFixed(3)}`);
}

console.log('\n[10] 未知量计数恒等式');
{
  let ok1 = true, ok2 = true, ok3 = true;
  for (let n=2;n<=20;n++){
    if (countModel(n,'general').total !== 5*n-2) ok1 = false;
    if (countModel(n,'swedish').total !== 2*n+1) ok2 = false;
    if (countModel(n,'bishop').total  !== 4*n-1) ok3 = false;
    if (countModel(n,'general').eqTotal !== 4*n) ok1 = false;
  }
  T('通用模型 = 5n−2', ok1);
  T('瑞典 = 2n+1', ok2);
  T('简化 Bishop = 4n−1', ok3);
  T('5n−2 − 3(n−1) = 2n+1（代数恒等）',
    [2,3,5,8,10,20].every(n => 5*n-2-3*(n-1) === 2*n+1));
  T('5n−2 − (n−1) = 4n−1（代数恒等）',
    [2,3,5,8,10,20].every(n => 5*n-2-(n-1) === 4*n-1));
  T('n=10：超静定 8 次', countModel(10,'general').diff === 8);
  T('totalExpr 与 countModel 一致',
    ['general','swedish','bishop'].every(md => [2,5,8,12].every(n => totalExpr(n,md).v === countModel(n,md).total)));
}

console.log('\n[11] 无效圆弧应被识别');
{
  const bad = {xc:5, yc:100, R:2};          /* 远离坡面的小圆 */
  T('返回 null', findSpan(bad, base.H, base.m) === null);
}

console.log('\n[12] 推导链自洽：在算出的 F 上，平衡残差应为零');
{
  const t  = Math.tan(base.phi*Math.PI/180);
  const sp = findSpan(c0, base.H, base.m);
  const ss = buildSlices(c0, sp, base);

  /* ---- Bishop：对圆心的力矩残差 ΣT − ΣW·sinα ---- */
  const Fb = fsBishop(ss, base).F;
  let momT = 0, momW = 0;
  for (const s of ss){
    const ma = s.cosA + s.sinA*t/Fb;
    momT += (base.c*s.b + (s.W - base.ru*base.gamma*s.h*s.b)*t)/ma/Fb;
    momW += s.W*s.sinA;
  }
  T('Bishop：力矩平衡 ΣT = ΣW·sinα',
    Math.abs(momT-momW)/momW < 1e-6,
    `残差 ${((momT-momW)/momW*100).toExponential(2)} %`);

  /* ---- Janbu：水平力残差 Σ(T·cosα − N·sinα) ---- */
  const Fj = fsJanbu(ss, base).F;
  let hx = 0, sumWtan = 0;
  for (const s of ss){
    const ma = s.cosA + s.sinA*t/Fj;
    const Np = (s.W - base.ru*base.gamma*s.h*s.b - base.c*s.l*s.sinA/Fj)/ma;
    const Ti = (base.c*s.l + Np*t)/Fj;
    const Ni = Np + base.ru*base.gamma*s.h*s.l;      /* 总法向力 = 有效法向力 + 孔压合力 */
    hx += Ti*s.cosA - Ni*s.sinA;
    sumWtan += s.W*Math.tan(s.alpha);
  }
  T('Janbu：水平力平衡 Σ(T·cosα − N·sinα) = 0',
    Math.abs(hx)/Math.abs(sumWtan) < 1e-6,
    `残差 ${(hx/sumWtan*100).toExponential(2)} %`);

  /* ---- 瑞典法：N′ 由条底法向投影直接得出，再验整体力矩 ---- */
  const Fsw = fsSwedish(ss, base).F;
  let momS = 0, momWS = 0;
  for (const s of ss){
    const Np = s.W*s.cosA - base.ru*base.gamma*s.h*s.l;      /* 径向投影，不含 F */
    momS += (base.c*s.l + Np*t)/Fsw;
    momWS += s.W*s.sinA;
  }
  T('瑞典：按文档公式 N′=Wcosα−ul 重构，与实现的 ΣT/ΣWsinα 同式',
    Math.abs(momS-momWS)/momWS < 1e-9,
    `残差 ${((momS-momWS)/momWS*100).toExponential(2)} %（该式即 F 的定义，故恒为 0，用于核对实现与文档一致）`);

  /* ---- 关键代数恒等式 ---- */
  let id1 = true, id2 = true;
  for (const s of ss){
    const ma = s.cosA + s.sinA*t/1.5;
    /* c'l·m_α − c'l·sinα·tanφ/F = c'b */
    if (Math.abs(base.c*s.l*ma - base.c*s.l*s.sinA*t/1.5 - base.c*s.b) > 1e-9) id1 = false;
    /* n_α = cosα·m_α */
    const na = s.cosA*s.cosA*(1 + Math.tan(s.alpha)*t/1.5);
    if (Math.abs(na - s.cosA*ma) > 1e-12) id2 = false;
  }
  T('代数恒等 1：c′l·m_α − c′l·sinα·tanφ/F = c′b', id1);
  T('代数恒等 2：n_α = cosα · m_α', id2);

  /* cosα + sinα·tanα = 1/cosα */
  T('代数恒等 3：cosα + sinα·tanα = 1/cosα',
    ss.every(s => Math.abs(s.cosA + s.sinA*Math.tan(s.alpha) - 1/s.cosA) < 1e-12));
}

console.log('\n[13] 教材算例回归：H=8 m、坡角 55°、γ=20、φ=12°、c=20 kPa');
{
  const S = {H:8, m:1/Math.tan(55*Math.PI/180), gamma:20, c:20, phi:12, ru:0, n:10};
  /* 顶点埋在土中的圆（弧的一端未穿出地面）必须判为无效 */
  T('弧端未穿出地面的圆应返回 null', findSpan({xc:0.5, yc:6.5, R:6.5}, S.H, S.m) === null);

  const c = {xc:-0.4, yc:8.0, R:8.01};
  const sp = findSpan(c, S.H, S.m);
  T('圆心在坡趾左侧（x₀=-0.4）仍是有效滑弧', !!sp,
    sp ? `滑弧 ${sp.x1.toFixed(2)} ~ ${sp.x2.toFixed(2)}` : 'null');
  if (sp){
    const sl = buildSlices(c, sp, S);
    const sw = fsSwedish(sl, S).F, bi = fsBishop(sl, S).F;
    T('瑞典法 ≈ 教材 1.045（±0.02）', Math.abs(sw-1.045) < 0.02, sw.toFixed(4));
    T('同一圆 Bishop 不小于瑞典法', bi >= sw, `${bi.toFixed(4)} vs ${sw.toFixed(4)}`);
  }
}

console.log(`\n===== 结果：${pass} 通过，${fail} 失败 =====\n`);
process.exit(fail ? 1 : 0);

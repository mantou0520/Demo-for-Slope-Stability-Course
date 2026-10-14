/* 校验脚本：从 index.html 中抽取 CORE MATH 代码段，用解析解逐项验证
   运行： node verify_core_math.js                                       */
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const m = html.match(/CORE MATH START[\s\S]*?\*\/([\s\S]*?)\/\* =+ CORE MATH END/);
if (!m) { console.error('未找到 CORE MATH 代码段'); process.exit(1); }
eval(m[1]);   // 载入被测函数

let pass = 0, fail = 0;
const T = (name, ok, info) => {
  if (ok) { pass++; console.log('  ok   ' + name + (info ? '   ' + info : '')); }
  else    { fail++; console.log('  FAIL ' + name + (info ? '   ' + info : '')); }
};
const near = (a, b, tol=1e-6) => Math.abs(a-b) <= tol;
const D = 180/Math.PI;

console.log('\n[1] 平面三要素（倾向 0°/30°）');
{
  const f = planeFrame(0, 30);
  T('走向为东西向 (1,0,0)', near(f.strike[0],1) && near(f.strike[1],0));
  T('倾向线 z = -sin30 = -0.5', near(f.down[2], -0.5));
  T('上法线 = (0, sin30, cos30)', near(f.nUp[0],0) && near(f.nUp[1],0.5) && near(f.nUp[2],Math.cos(30/D)));
  T('法线 ⊥ 倾向线', near(vdot(f.nUp, f.down), 0));
  T('法线 ⊥ 走向',   near(vdot(f.nUp, f.strike), 0));
}
console.log('\n[2] 大圆采样点都在平面上、且在单位球上');
{
  for (const [az,dip] of [[120,45],[0,30],[200,60],[90,90],[30,10]]){
    const f = planeFrame(az,dip);
    const gc = greatCircle(az,dip,240);
    const onPlane = gc.every(p => Math.abs(vdot(p, f.nUp)) < 1e-12);
    const onSphere = gc.every(p => Math.abs(vlen(p)-1) < 1e-12);
    T(`α=${az} β=${dip}：241 点均在平面 ∩ 单位球上`, onPlane && onSphere);
  }
}
console.log('\n[3] 下半球投影：关键点半径（解析解）');
{
  for (const [az,dip] of [[0,30],[120,45],[200,60],[90,90],[30,10],[0,0]]){
    const f = planeFrame(az,dip);
    const st = stereo(f.strike, 'lower', 'angle');
    const dp = stereo(f.down,   'lower', 'angle');
    const po = stereo(f.nDown,  'lower', 'angle');
    const rArc  = Math.tan((45 - dip/2)/D);       // 弧顶半径
    const rPole = Math.tan((dip/2)/D);            // 极点半径
    T(`α=${az} β=${dip}：走向点落在基圆上 (r=1)`, near(st.r, 1, 1e-12), `r=${st.r.toFixed(6)}`);
    T(`α=${az} β=${dip}：弧顶半径 = tan(45-β/2)`, near(dp.r, rArc, 1e-9), `${dp.r.toFixed(6)} vs ${rArc.toFixed(6)}`);
    T(`α=${az} β=${dip}：极点半径 = tan(β/2)`,   near(po.r, rPole, 1e-9), `${po.r.toFixed(6)} vs ${rPole.toFixed(6)}`);
  }
}
console.log('\n[4] 方位关系（下半球约定）');
{
  const [az,dip] = [120,45];
  const f = planeFrame(az,dip);
  const dp = stereo(f.down,  'lower', 'angle');   // 弧顶
  const po = stereo(f.nDown, 'lower', 'angle');   // 极点
  const azOf = (p)=>{ let a=Math.atan2(p.E,p.N)*D; return (a+360)%360; };
  T('弧顶方位 = 倾向 120°', near(azOf(dp), az, 1e-9), azOf(dp).toFixed(3));
  T('极点方位 = 倾向+180° = 300°', near(azOf(po), (az+180)%360, 1e-9), azOf(po).toFixed(3));
  T('弧顶位于基圆内 (r<1)', dp.r < 1);
}
console.log('\n[5] 上半球投影与下半球投影互为 180° 旋转');
{
  for (const [az,dip] of [[120,45],[200,60],[35,15]]){
    const f = planeFrame(az,dip);
    const a = stereo(f.nDown,'lower','angle');
    const b = stereo(f.nUp,  'upper','angle');
    T(`α=${az} β=${dip}：极点 r 相同`, near(a.r,b.r,1e-12), `${a.r.toFixed(6)} = ${b.r.toFixed(6)}`);
    T(`α=${az} β=${dip}：极点方向相反`, near(a.E+b.E,0,1e-12) && near(a.N+b.N,0,1e-12));
    const c = stereo(f.down,'lower','angle');
    const d = stereo(f.down,'upper','angle');
    T(`α=${az} β=${dip}：弧顶 r 相同且方向相反`, near(c.r,d.r,1e-12) && near(c.E+d.E,0,1e-12) && near(c.N+d.N,0,1e-12),
      `lower=(${c.E.toFixed(4)},${c.N.toFixed(4)}) upper=(${d.E.toFixed(4)},${d.N.toFixed(4)})`);
  }
}
console.log('\n[6] 极点是面上任意方向的 90° 角距（下半球投影的核心性质）');
{
  const [az,dip] = [200,60];
  const f = planeFrame(az,dip);
  const pole = stereo(f.nDown,'lower','angle');
  let maxErr = 0;
  for (let i=0;i<=180;i++){
    const t = Math.PI*i/180;
    const p = [ f.strike[0]*Math.cos(t)+f.down[0]*Math.sin(t),
                f.strike[1]*Math.cos(t)+f.down[1]*Math.sin(t),
                f.strike[2]*Math.cos(t)+f.down[2]*Math.sin(t) ];
    if (p[2] > 0) continue;
    maxErr = Math.max(maxErr, Math.abs(vdot(p, f.nDown)));   // 应为 0
  }
  T('面上所有下半球方向 ⊥ 极点方向', maxErr < 1e-12, `max|cos| = ${maxErr.toExponential(2)}`);
  /* 极点半径 tan(β/2) 与弧顶半径 tan(45-β/2) 的大小关系：β>45° 时极点更靠外 */
  const rPole = Math.tan((dip/2)/D), rArc = Math.tan((45-dip/2)/D);
  const rel = Math.sign(pole.r - rArc), expect = Math.sign(dip - 45);
  T('β=60>45° 时极点比弧顶更靠外圆（极点近水平）', rel === expect,
    `r_pole=${rPole.toFixed(4)}, r_arc=${rArc.toFixed(4)}`);
  T('临界 β=45° 时二者相等（均为 tan22.5°）',
    near(Math.tan(22.5/D), Math.tan(22.5/D), 1e-12));
}
console.log('\n[7] 等角 vs 等面积投影');
{
  const f = planeFrame(0,30);
  const ang = stereo(f.down,'lower','angle');
  const area= stereo(f.down,'lower','area');
  T('等面积半径 = √2·sin(θ/2)，θ=90-β=60°', near(area.r, Math.SQRT2*Math.sin(30/D), 1e-12),
    `${area.r.toFixed(6)} vs ${(Math.SQRT2*Math.sin(30/D)).toFixed(6)}`);
  /* 严格关系：r_area / r_angle = √2·cos(θ/2)，θ<90° 时恒 >1 */
  for (const [az,dip] of [[0,10],[0,30],[0,60],[0,89]]){
    const th = (90-dip)/D;
    const a1 = stereo(planeFrame(az,dip).down,'lower','angle').r;
    const a2 = stereo(planeFrame(az,dip).down,'lower','area').r;
    T(`α=${az} β=${dip}：r_面积/r_等角 = √2·cos(θ/2)`, near(a2/a1, Math.SQRT2*Math.cos(th/2), 1e-12),
      `比值=${(a2/a1).toFixed(6)}, √2cos(θ/2)=${(Math.SQRT2*Math.cos(th/2)).toFixed(6)}`);
  }
  T('等面积半径 > 等角半径（θ<90° 时）', area.r > ang.r);
  T('等面积在基圆上仍为 1（θ=90°）', near(stereo(f.strike,'lower','area').r, 1, 1e-12));
}
console.log('\n[8] 两平面交棱线');
{
  // 构造已知交线：两个竖直面的交线是竖直的
  const L1 = intersectionLine(90, 90, 0, 90);          // 直立面(走向南北) ∩ 直立面(走向东西)
  const a1 = lineAttitude(L1);
  T('两竖直面交线为竖直（倾伏角 90°）', near(a1.plunge, 90, 1e-6), `plunge=${a1.plunge.toFixed(4)}`);
  // 水平面 ∩ 倾斜面 -> 交线为走向线
  const L2 = intersectionLine(120, 45, 0, 0);          // 0°∠0° 为水平面
  const a2 = lineAttitude(L2);
  T('水平面 ∩ 120∠45 面 -> 交线沿走向（倾伏角 0°，方位 30° 或 210°）',
    near(a2.plunge, 0, 1e-6) && (near(a2.azimuth,30,1e-6) || near(a2.azimuth,210,1e-6)),
    `plunge=${a2.plunge.toFixed(4)} az=${a2.azimuth.toFixed(3)}`);
  // 交线同时位于两个平面上
  const L3 = intersectionLine(60,50,160,65);
  const i1 = planeFrame(60,50).nUp, i2 = planeFrame(160,65).nUp;
  T('交线同时位于两个平面上', Math.abs(vdot(L3,i1))<1e-12 && Math.abs(vdot(L3,i2))<1e-12);
}
console.log('\n[9] 与规范/教材算例对照');
{
  // 走向南北、向东倾斜、倾角 40°：弧应凸向东，弧顶半径 tan(25°)
  const f = planeFrame(90,40);
  const dp = stereo(f.down,'lower','angle');
  T('走向南北、东倾 40°：弧顶指向正东', near(dp.E, Math.tan(25/D), 1e-9) && near(dp.N, 0, 1e-12),
    `E=${dp.E.toFixed(6)} (tan25°=${Math.tan(25/D).toFixed(6)})`);
  const po = stereo(f.nDown,'lower','angle');
  T('其极点指向正西、半径 tan(20°)', near(po.E, -Math.tan(20/D), 1e-9) && near(po.N,0,1e-12),
    `E=${po.E.toFixed(6)}`);
}

console.log(`\n===== 通过 ${pass} 项，失败 ${fail} 项 =====\n`);
process.exit(fail ? 1 : 0);

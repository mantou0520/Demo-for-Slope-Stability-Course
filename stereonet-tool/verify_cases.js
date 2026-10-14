/* 边坡判别算例回归测试：核对工具②页三个判据在四个典型算例上的命中情况
   运行： node verify_cases.js                                            */
const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
eval(html.match(/CORE MATH START[\s\S]*?\*\/([\s\S]*?)\/\* =+ CORE MATH END/)[1]);
const angDiff = (a,b) => Math.abs(((a-b)%360+540)%360-180);

const cases = {
  '平面滑动算例': { cs:[110,60], j1:[115,45], j2:[250,75], phi:30 },
  '楔形体算例':   { cs:[110,60], j1:[60,50],  j2:[160,65], phi:30 },
  '倾倒算例':     { cs:[110,65], j1:[290,80], j2:[200,40], phi:32 },
  '稳定算例':     { cs:[110,60], j1:[300,35], j2:[210,45], phi:35 }
};
const expect = { '平面滑动算例':1, '楔形体算例':1, '倾倒算例':1, '稳定算例':0 };

let total = 0, fails = 0;
for (const k of Object.keys(cases)){
  const c = cases[k], csa = c.cs[0], csd = c.cs[1], phi = c.phi;
  const M = lineAttitude(intersectionLine(c.j1[0],c.j1[1],c.j2[0],c.j2[1]));
  let n = 0;
  console.log('\n== ' + k + ' ==  (坡面 ' + csa + '∠' + csd + ', φ=' + phi + ')');
  for (const nm of ['j1','j2']){
    const J = c[nm];
    /* 平面滑动：倾向与坡向一致(≤20°) + 倾角>φ + 倾角<坡角 */
    const hitP = angDiff(J[0],csa) <= 20 && J[1] > phi && J[1] < csd;
    if (hitP) n++;
    console.log('   平面滑动 ' + nm.toUpperCase() + '：倾向差 ' + angDiff(J[0],csa).toFixed(0) +
      '°, 倾角 ' + J[1] + '° → ' + (hitP ? '【命中】' : '不满足'));
    /* 倾倒：结构面倾向 ≈ 反坡向 ±20°（倾向坡内）+ 极点伏角≤30° + 坡角≥30° */
    const P = lineAttitude(planeFrame(J[0],J[1]).nDown), anti = (csa+180)%360;
    const hitT = angDiff(J[0],anti) <= 20 && P.plunge <= 30 && csd >= 30;
    if (hitT) n++;
    console.log('   倾倒破坏 ' + nm.toUpperCase() + '：倾向与反坡向(' + anti + '°)差 ' +
      angDiff(J[0],anti).toFixed(0) + '°, 极点伏角 ' + P.plunge.toFixed(1) +
      '°（Goodman 限值 ' + (csd-phi).toFixed(1) + '°）→ ' + (hitT ? '【命中】' : '不满足'));
  }
  /* 楔形滑动：交棱线 M 的倾伏向与坡向差≤20° + 倾伏角>φ + 倾伏角<坡角 */
  const hitW = angDiff(M.azimuth,csa) <= 20 && M.plunge > phi && M.plunge < csd;
  if (hitW) n++;
  console.log('   楔形滑动 M ：倾伏向 ' + M.azimuth.toFixed(1) + '°, 倾伏角 ' + M.plunge.toFixed(1) +
    '° → ' + (hitW ? '【命中】' : '不满足'));
  total += n;
  const ok = (n === expect[k]);
  if (!ok) fails++;
  console.log('   → 命中 ' + n + ' 项，预期 ' + expect[k] + ' 项   ' + (ok ? 'OK' : 'FAIL'));
}
console.log('\n合计命中 ' + total + ' 项；断言失败 ' + fails + ' 个');
process.exit(fails ? 1 : 0);

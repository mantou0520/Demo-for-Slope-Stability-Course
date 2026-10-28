function Fs = slope_fem(varargin)
%SLOPE_FEM  均质黏性土边坡：平面应变弹塑性有限元 + 强度折减法
%
%   单元：四节点等参元（Q4），2×2 高斯积分，平面应变
%   本构：Mohr-Coulomb 理想弹塑性，非关联流动（剪胀角 psi，默认 0）
%   求解：两阶段 ——
%         阶段 I  自重固结：真实强度下分级加载至重力全载，得地应力场，位移清零
%         阶段 II 强度折减：c、tanφ 同除 F，分步折减，位移与塑性应变从零计
%         每级修正 Newton 迭代（切线模量随塑性状态更新）
%   失稳：二分法搜索临界折减系数 Fs，判据为迭代不收敛或位移失控
%   输出：网格图、位移云图、应力云图、von Mises 云图、塑性剪应变云图、滑裂带图
%
%   注：弹性模量 E 只影响位移的量级（u ∝ 1/E），不改变 Fs 与变形模式。
%
%   用法：
%     slope_fem                                        % 默认算例，出全套云图
%     slope_fem('H',12,'beta',50,'c',25,'phi',18)      % 改几何与强度参数
%     slope_fem('beta',60,'phi',12,'export',false)     % 不导出图片
%     slope_fem('sweep',true)                          % 扫坡角 30/45/60°
%     slope_fem('sweep',true,'sweepBeta',[30 40 50 60 70])
%     slope_fem('Fplot',1.20,'save','res.mat')         % 指定绘图折减系数并存解
%
%   单位：长度 m，应力/模量 kPa，重度 kN/m^3（1 kPa = 1 kN/m^2）
%         例：E = 20000 kPa(=20 MPa)，c = 20 kPa，γ = 18 kN/m^3
%
%   说明：
%     1) 理想弹塑性，无硬化/软化；破坏判据为「Newton 迭代不收敛」或「位移失控」。
%     2) 平面应变 MC 的等价形式（压应力为负）：f = t + p·sinφ − c·cosφ，
%        p = (σx+σy)/2，t = sqrt(((σx−σy)/2)^2 + τxy^2)。
%        这是教学代码常用的简化（未严格求解 σz；von Mises 图里 σz 按弹性式 ν(σx+σy) 估）。
%     3) 默认泊松比由 Jaky K0 = 1−sinφ 反算（ν = K0/(1+K0)），
%        使自重固结后的初始地应力处于弹性可容状态，避免深部虚假塑性。
%     4) 与极限平衡法一般相差 5%~10%，属正常（本构、流动法则、网格与判据差异）。

p = parse_opts(varargin);

if p.sweep
    sweep_cases(p);
    Fs = [];
else
    Fs = run_case(p, true);
end
end

%% ========================================================================
%  单个算例
%% ========================================================================
function Fs = run_case(p, doplot)
if ~p.quiet
    fprintf('\n=== 边坡有限元强度折减分析 ===\n');
    fprintf('  H = %.1f m，坡角 β = %.0f°（1:%.2f），γ = %.1f，c = %.1f kPa，φ = %.0f°\n', ...
        p.H, p.beta, cotd(p.beta), p.gamma, p.c, p.phi);
end

[nodes, quads, grd] = make_mesh(p);
if ~p.quiet
    fprintf('  网格：%d 节点，%d 单元\n', size(nodes,1), size(quads,1));
end

mat = make_material(p);
p.nu = mat.nu;                       % 后续绘图（σz 近似）用同一 ν
[edof, Bmat, DJ, bcs, free] = preprocess(nodes, quads);
if ~p.quiet
    if mat.nuAuto
        fprintf('  ν = %.3f（由 Jaky K0=1−sinφ=%.2f 反算），初始地应力弹性可容\n', mat.nu, mat.K0);
    else
        fprintf('  ν = %.3f（指定），K0 = %.2f\n', mat.nu, mat.K0);
    end
end

t0 = tic;
[sig0, uGeo, geoOk] = geostatic(nodes, quads, mat, bcs, edof, Bmat, DJ, free, p);
if ~geoOk && ~p.quiet
    fprintf('  [警告] 自重固结阶段未收敛，地应力场可能不可靠\n');
end

[Fs, info] = find_fs(nodes, quads, mat, bcs, edof, Bmat, DJ, free, p, sig0);
if ~p.quiet
    fprintf('  临界折减系数 Fs = %.3f   （用时 %.1f s，%d 次试算）\n', Fs, toc(t0), info.neval);
    fprintf('  自重固结沉降（位移已清零，仅作记录）%.1f mm\n', uGeo*1e3);
end

if doplot && isfinite(Fs)
    % 绘图点：尽量逼近 Fs（滑裂带才充分发育），逐级回退直到收敛
    if ~isempty(p.Fplot)
        cands = p.Fplot;
    else
        cands = Fs*[0.99 0.96 0.92];
    end
    ok = false;
    for kc = 1:numel(cands)
        Fp = cands(kc);
        [u, sig, ep, ok] = solve_reduction(nodes, quads, mat, bcs, edof, Bmat, DJ, free, p, Fp, sig0);
        if ok, break; end
        if ~p.quiet
            fprintf('  [提示] 绘图用 F=%.3f 未收敛，回退一级\n', Fp);
        end
    end
    if ok
        plot_all(nodes, quads, grd, u, sig, ep, p, Fs, Fp);
    end
end
end

%% ========================================================================
%  几何与网格（贴坡面的结构化四边形网格）
%% ========================================================================
function [nodes, quads, grd] = make_mesh(p)
H = p.H;  m = cotd(p.beta);
xc = m*H;
xL = -p.xLeft*H;
xR = xc + p.xRight*H;
yB = -p.depth*H;
nx = p.nx;  ny = p.ny;

xs = linspace(xL, xR, nx+1);
Xg = zeros(ny+1, nx+1);  Yg = zeros(ny+1, nx+1);
for j = 1:nx+1
    ytop = ground_y(xs(j), H, m);
    Yg(:,j) = linspace(yB, ytop, ny+1);
    Xg(:,j) = xs(j);
end

nodes = [Xg(:), Yg(:)];
quads = zeros(nx*ny, 4);
e = 0;
for j = 1:nx
    for i = 1:ny
        e = e + 1;
        n1 = (j-1)*(ny+1) + i;
        n2 =  j   *(ny+1) + i;
        quads(e,:) = [n1, n2, n2+1, n1+1];
    end
end
grd = struct('X',Xg, 'Y',Yg, 'nx',nx, 'ny',ny, 'm',m, 'xc',xc);
end

function y = ground_y(x, H, m)
if x <= 0
    y = 0;
elseif x >= m*H
    y = H;
else
    y = x/m;
end
end

%% ========================================================================
%  材料与本构
%% ========================================================================
function mat = make_material(p)
mat.E   = p.E;
mat.gam = p.gamma;
mat.c   = p.c;
mat.phi = p.phi*pi/180;
mat.psi = p.psi*pi/180;

% 泊松比：默认由 Jaky 静止侧压力系数反算，使初始地应力处于弹性可容状态
%   K0 = 1 - sinφ  →  ν = K0/(1+K0)
% 若沿用 ν=0.30（K0≈0.43），φ=15°、c=20 kPa 时地面以下约 10 m 的 K0 应力状态
% 已越过 Mohr-Coulomb 屈服面，会在深部产生虚假塑性区（见 README 第五节）。
if isempty(p.nu)
    sp0 = sin(mat.phi);
    K0  = 1 - sp0;
    mat.nu = min(0.45, K0/(1+K0));
    mat.nuAuto = true;
else
    mat.nu = p.nu;
    mat.nuAuto = false;
end
mat.K0 = mat.nu/(1-mat.nu);

E = mat.E; nu = mat.nu;
mat.D = E/((1+nu)*(1-2*nu)) * [1-nu, nu, 0; nu, 1-nu, 0; 0, 0, (1-2*nu)/2];
end

function [sig, dlam, Dep] = mc_update(sig, deps, mat)
% Mohr-Coulomb 返回映射；dlam 为本次塑性乘子增量（可用于塑性应变累积）
D  = mat.D;
sp = sin(mat.phi);  cp = cos(mat.phi);
sy = sin(mat.psi);

sig_tr = sig + D*deps;
sx = sig_tr(1); yy = sig_tr(2); txy = sig_tr(3);
pp = 0.5*(sx+yy);  d = 0.5*(sx-yy);
t  = sqrt(d*d + txy*txy);
% 注意：本程序压应力为负，故 f = t + p·sinφ − c·cosφ
f  = t + pp*sp - mat.c*cp;

if f <= 1e-10 || t < 1e-9
    sig = sig_tr;
    dlam = 0;
    Dep = D;
    return;
end

dlam = 0;
sig  = sig_tr;                 % 从弹性预测点出发做返回映射
a = zeros(3,1);  g = zeros(3,1);
for k = 1:3
    sx = sig(1); yy = sig(2); txy = sig(3);
    pp = 0.5*(sx+yy);  d = 0.5*(sx-yy);
    t  = max(sqrt(d*d + txy*txy), 1e-9);
    a  = [ d/(2*t) + sp/2;  -d/(2*t) + sp/2;   txy/t ];   % ∂f/∂σ
    g  = [ d/(2*t) + sy/2;  -d/(2*t) + sy/2;   txy/t ];   % ∂g/∂σ
    f  = t + pp*sp - mat.c*cp;
    if f <= 1e-10, break; end
    dl = f / (a'*D*g);
    sig  = sig - dl*(D*g);
    dlam = dlam + dl;
end
den = a'*D*g;
if abs(den) < 1e-12
    Dep = D;
else
    Dep = D - (D*g)*(a'*D)/den;
end
end

function Dep = mc_tangent(sig, mat)
D  = mat.D;  sp = sin(mat.phi);  cp = cos(mat.phi);  sy = sin(mat.psi);
sx = sig(1); yy = sig(2); txy = sig(3);
pp = 0.5*(sx+yy);  d = 0.5*(sx-yy);
t  = sqrt(d*d + txy*txy);
f  = t + pp*sp - mat.c*cp;          % 压应力为负
if f <= 0 || t < 1e-9
    Dep = D;
    return;
end
a = [ d/(2*t) + sp/2;  -d/(2*t) + sp/2;  txy/t ];
g = [ d/(2*t) + sy/2;  -d/(2*t) + sy/2;  txy/t ];
den = a'*D*g;
if abs(den) < 1e-12
    Dep = D;
else
    Dep = D - (D*g)*(a'*D)/den;
end
end

%% ========================================================================
%  预处理
%% ========================================================================
function [edof, Bmat, DJ, bcs, free] = preprocess(nodes, quads)
nn = size(nodes,1);  ne = size(quads,1);
ndof = 2*nn;

edof = zeros(ne,8);
for e = 1:ne
    n = quads(e,:);
    edof(e,:) = [2*n(1)-1 2*n(1) 2*n(2)-1 2*n(2) 2*n(3)-1 2*n(3) 2*n(4)-1 2*n(4)];
end

gp = [-1 -1; 1 -1; 1 1; -1 1]/sqrt(3);
Bmat = zeros(3,8,4,ne);
DJ   = zeros(4,ne);
for e = 1:ne
    xy = nodes(quads(e,:),:);
    for g = 1:4
        [B, detJ] = shape_B(xy, gp(g,1), gp(g,2));
        Bmat(:,:,g,e) = B;
        DJ(g,e) = detJ;
    end
end

tol = 1e-8;
xmn = min(nodes(:,1));  xmx = max(nodes(:,1));
ybt = min(nodes(:,2));
bcs = [];
for i = 1:nn
    if abs(nodes(i,2) - ybt) < tol*max(1,abs(ybt))
        bcs = [bcs; 2*i-1; 2*i];                                  %#ok<AGROW>
    elseif abs(nodes(i,1) - xmn) < tol*max(1,abs(xmn)) || abs(nodes(i,1) - xmx) < tol*max(1,abs(xmx))
        bcs = [bcs; 2*i-1];                                       %#ok<AGROW>
    end
end
bcs = unique(bcs);
free = setdiff((1:ndof)', bcs);
end

function [B, detJ, N] = shape_B(xy, s, t)
N  = 0.25*[(1-s)*(1-t), (1+s)*(1-t), (1+s)*(1+t), (1-s)*(1+t)];
dN = 0.25*[-(1-t), (1-t), (1+t), -(1+t); ...
           -(1-s), -(1+s), (1+s),  (1-s)];
J  = dN * xy;                   % 2x2：J = [dx/ds dy/ds; dx/dt dy/dt]
detJ = det(J);
dNdx = J \ dN;                  % 2x4：dN/dx = J^{-1} [dN/ds; dN/dt]
B = [dNdx(1,1) 0 dNdx(1,2) 0 dNdx(1,3) 0 dNdx(1,4) 0; ...
     0 dNdx(2,1) 0 dNdx(2,2) 0 dNdx(2,3) 0 dNdx(2,4); ...
     dNdx(2,1) dNdx(1,1) dNdx(2,2) dNdx(1,2) dNdx(2,3) dNdx(1,3) dNdx(2,4) dNdx(1,4)];
end

function Fg = gravity_load(nodes, quads, Bmat, DJ, gamma)
nn = size(nodes,1);  ne = size(quads,1);
Fg = zeros(2*nn,1);
gp = [-1 -1; 1 -1; 1 1; -1 1]/sqrt(3);
for e = 1:ne
    xy = nodes(quads(e,:),:);
    n = quads(e,:);
    vdof = [2*n(1) 2*n(2) 2*n(3) 2*n(4)];
    for g = 1:4
        [~,~,N] = shape_B(xy, gp(g,1), gp(g,2));
        Fg(vdof) = Fg(vdof) + (N(:)*(-gamma))*DJ(g,e);
    end
end
end

%% ========================================================================
%  非线性求解：阶段 I 自重固结 → 位移清零；阶段 II 强度折减
%% ========================================================================
function [sig0, uGeo, ok] = geostatic(nodes, quads, mat, bcs, edof, Bmat, DJ, free, p)
% 阶段 I：真实强度下把重力加到全载，得到与重力平衡的地应力场。
% 位移只保留作参考（uGeo 为固结沉降量），随后清零，不计入后续云图。
nn = size(nodes,1);  ne = size(quads,1);  ndof = 2*nn;
u   = zeros(ndof,1);
sig = zeros(3,4,ne);
ep  = zeros(4,ne);            % 固结阶段塑性乘子，不进入结果
ok  = true;

Fg0 = gravity_load(nodes, quads, Bmat, DJ, mat.gam);
for st = 1:p.nsteps
    fe = Fg0*(st/p.nsteps);
    [u, sig, ep, conv] = solve_loadstep(quads, mat, bcs, edof, Bmat, DJ, free, ...
                                        ndof, ne, fe, u, sig, ep, p);
    if ~conv
        ok = false;
        break;
    end
end
sig0 = sig;
uGeo = max(abs(u));
end

function [u, sig, ep, ok] = solve_reduction(nodes, quads, mat, bcs, edof, Bmat, DJ, free, p, F, sig0)
% 阶段 II：从地应力场出发，把强度分步折减到 F（c/F、tanφ/F）。
% u、ep 均从零计 —— 云图反映的是"折减引起的附加变形"，即真实破坏机制。
nn = size(nodes,1);  ne = size(quads,1);  ndof = 2*nn;
u   = zeros(ndof,1);
ep  = zeros(4,ne);
sig = sig0;
Fg0 = gravity_load(nodes, quads, Bmat, DJ, mat.gam);
ok  = true;

ns = max(1, p.nReduce);
for s = 1:ns
    Fst = 1 + (F-1)*s/ns;                       % 逐级由 1 降到 F
    mt  = reduce_mat(mat, Fst);
    % 当前应力退回到降低后的屈服面上（产生不平衡力，驱动下一步求解）
    for e = 1:ne
        for g = 1:4
            [snew, dl] = mc_update(sig(:,g,e), zeros(3,1), mt);
            sig(:,g,e) = snew;
            ep(g,e)    = ep(g,e) + dl;
        end
    end
    [u, sig, ep, conv] = solve_loadstep(quads, mt, bcs, edof, Bmat, DJ, free, ...
                                        ndof, ne, Fg0, u, sig, ep, p);
    if ~conv
        ok = false;
        return;
    end
    if max(abs(u)) > p.uMax*p.H
        ok = false;
        return;
    end
end
end

function [u, sig, ep, conv] = solve_loadstep(quads, mat, bcs, edof, Bmat, DJ, free, ...
                                             ndof, ne, fe, u, sig, ep, p)
% 修正 Newton：外力固定为 fe，迭代至残差收敛
fn = norm(fe(free));  if fn < 1e-12, fn = 1; end
conv = false;
for it = 1:p.maxit
    [K, fint] = assemble(quads, sig, mat, edof, Bmat, DJ, ndof);
    R = fe - fint;
    R(bcs) = 0;
    nr = norm(R(free))/fn;
    if p.debug
        fprintf('    [dbg] F=%.3f it=%2d  ||R||/||f|| = %.3e   max|u| = %.3e\n', ...
                mat.phi*180/pi, it, nr, max(abs(u)));
    end
    if nr < p.tol
        conv = true;
        break;
    end
    du = zeros(ndof,1);
    du(free) = K(free,free) \ R(free);
    u = u + du;
    for e = 1:ne
        due = du(edof(e,:));                       % 本步位移增量
        for g = 1:4
            deps = Bmat(:,:,g,e)*due;
            [snew, dlam] = mc_update(sig(:,g,e), deps, mat);
            sig(:,g,e) = snew;
            ep(g,e) = ep(g,e) + dlam;
        end
    end
end
end

function mt = reduce_mat(mat, F)
mt = mat;
mt.c   = mat.c / F;
mt.phi = atan(tan(mat.phi)/F);
end

function [K, fint] = assemble(quads, sig, mat, edof, Bmat, DJ, ndof)
ne = size(quads,1);
fint = zeros(ndof,1);
I = zeros(ne*64,1);  J = zeros(ne*64,1);  V = zeros(ne*64,1);
cnt = 0;
for e = 1:ne
    Ke = zeros(8,8);
    dofs = edof(e,:);
    for g = 1:4
        B  = Bmat(:,:,g,e);
        dj = DJ(g,e);
        Dep = mc_tangent(sig(:,g,e), mat);
        Ke = Ke + (B'*Dep*B)*dj;
        fint(dofs) = fint(dofs) + (B'*sig(:,g,e))*dj;
    end
    [jj,ii] = meshgrid(dofs, dofs);
    idx = cnt + (1:64);
    I(idx) = ii(:);  J(idx) = jj(:);  V(idx) = Ke(:);
    cnt = cnt + 64;
end
K = sparse(I, J, V, ndof, ndof);
end

%% ========================================================================
%  强度折减（二分法）
%% ========================================================================
function [Fs, info] = find_fs(nodes, quads, mat, bcs, edof, Bmat, DJ, free, p, sig0)
info.neval = 0;
lo = p.Fmin;  hi = p.Fmax;

[~,~,~,okLo] = solve_reduction(nodes, quads, mat, bcs, edof, Bmat, DJ, free, p, lo, sig0);
info.neval = info.neval + 1;
if ~okLo
    Fs = NaN;
    if ~p.quiet
        fprintf('  [警告] F=%.2f 仍不收敛：该强度下边坡已失稳（Fs < %.2f）\n', lo, lo);
    end
    return;
end

[~,~,~,okHi] = solve_reduction(nodes, quads, mat, bcs, edof, Bmat, DJ, free, p, hi, sig0);
info.neval = info.neval + 1;
if okHi
    Fs = hi;
    return;
end

for k = 1:p.nF
    mid = 0.5*(lo+hi);
    [~,~,~,ok] = solve_reduction(nodes, quads, mat, bcs, edof, Bmat, DJ, free, p, mid, sig0);
    info.neval = info.neval + 1;
    if ok, lo = mid; else, hi = mid; end
    if ~p.quiet
        fprintf('    试算 F=%.3f → %s（区间 %.3f ~ %.3f）\n', mid, ternary(ok,'收敛','失稳'), lo, hi);
    end
end
Fs = lo;
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

%% ========================================================================
%  绘图
%% ========================================================================
function plot_all(nodes, quads, grd, u, sig, ep, p, Fs, Fp)
ny = grd.ny;  nx = grd.nx;  H = p.H;
Xg = grd.X;  Yg = grd.Y;
ux = reshape(u(1:2:end), ny+1, nx+1);
uy = reshape(u(2:2:end), ny+1, nx+1);
um = sqrt(ux.^2 + uy.^2);

[sx, sy, txy, vm, pe] = gp2node(sig, ep, quads, ny+1, nx+1, size(nodes,1), p.nu);

out = p.outdir;
if p.export
    [okDir, msgDir] = mkdir(out);          % 始终调用，避免 exist 缓存误判
    if ~okDir
        warning('无法创建输出目录 %s：%s', out, msgDir);
        p.export = false;
    end
end
if ~isempty(p.save)
    save(p.save, 'u','sig','ep','Fs','Fp','nodes','quads','grd','p');
end

% 坡面（原始）
xsurf = [-p.xLeft*H, 0, grd.xc, grd.xc + p.xRight*H];
ysurf = [0, 0, H, H];

% ---- 00 网格图 ----
f = figure('Color','w','Position',[80 80 900 560]);
plot(Xg, Yg, '-', 'Color',[.55 .62 .72], 'LineWidth',.5); hold on;
plot(Xg', Yg', '-', 'Color',[.55 .62 .72], 'LineWidth',.5);
plot(Xg(:), Yg(:), '.', 'Color',[.25 .30 .38], 'MarkerSize',5);
plot(xsurf, ysurf, 'k-', 'LineWidth',2.0);
hold off; axis equal tight; box on;
title(sprintf('有限元网格：%d×%d 个 Q4 单元（%d 节点）   β=%.0f°, H=%.0f m', ...
    nx, ny, numel(nodes)/2, p.beta, H), 'FontSize', 11);
xlabel('x (m)'); ylabel('y (m)');
if p.export, exportgraphics(f, fullfile(out,'00_mesh.png'), 'Resolution', 150); end
if ~p.keepfig, close(f); end

figs = {
    um,  '总位移 |u|（相对自重固结状态）',  'disp_mag',  1e3, 'mm'
    uy,  '竖向位移 u_y（相对自重固结状态）', 'disp_y',    1e3, 'mm'
    ux,  '水平位移 u_x（相对自重固结状态）', 'disp_x',    1e3, 'mm'
    sx,  '正应力 \sigma_x',         'stress_x',  1,   'kPa'
    sy,  '正应力 \sigma_y',         'stress_y',  1,   'kPa'
    txy, '剪应力 \tau_{xy}',        'stress_xy', 1,   'kPa'
    vm,  'von Mises 等效应力',      'von_mises', 1,   'kPa'
    pe,  '等效塑性剪应变（折减阶段累计）', 'plastic', 1, ''
};

for k = 1:size(figs,1)
    V = figs{k,1}*figs{k,4};
    isPlastic = strcmp(figs{k,3},'plastic');
    f = figure('Color','w','Position',[80 80 900 560]);
    if isPlastic
        % 塑性剪应变：分级 + 限幅，否则最高值集中在坡趾，滑裂带看不出来
        pmax = max(pe(:));  if pmax <= 0, pmax = 1; end
        lv = [0 0.03 0.07 0.12 0.20 0.32 0.48 0.68 1.00]*pmax;
        contourf(Xg, Yg, V, lv, 'LineColor','none'); hold on;
        contour(Xg, Yg, V, [0.10 0.25 0.50]*pmax, 'LineColor',[.35 .35 .35], 'LineWidth',.7);
        plot(xsurf, ysurf, 'k-', 'LineWidth', 1.3); hold off;
        axis equal tight;  clim([0 0.5*pmax]);
        colormap(f, parula(256)); cb = colorbar;
        cb.Label.String = '等效塑性剪应变';
        title(sprintf('%s（色标上限取峰值的 50%%）   [β=%.0f°, c=%.0f kPa, φ=%.0f°, F_s=%.2f, F=%.2f]', ...
            figs{k,2}, p.beta, p.c, p.phi, Fs, Fp), 'FontSize', 11);
    else
        contourf(Xg, Yg, V, 22, 'LineColor','none'); hold on;
        plot(xsurf, ysurf, 'k-', 'LineWidth', 1.3);
        if strcmp(figs{k,3},'disp_mag')
            js = max(1, round(nx/16));  is = max(1, round(ny/12));
            q = quiver(Xg(1:is:end,1:js:end), Yg(1:is:end,1:js:end), ...
                       ux(1:is:end,1:js:end), uy(1:is:end,1:js:end), 0.55, 'k');
            q.Color = [.15 .15 .15];
        end
        hold off; axis equal tight;
        colormap(f, parula(256)); cb = colorbar; cb.Label.String = figs{k,5};
        title(sprintf('%s   [H=%.0f m, β=%.0f°, c=%.0f kPa, φ=%.0f°, F_s=%.2f]', ...
            figs{k,2}, H, p.beta, p.c, p.phi, Fs), 'FontSize', 11);
    end
    xlabel('x (m)'); ylabel('y (m)');
    if p.export
        exportgraphics(f, fullfile(out, sprintf('%02d_%s.png', k, figs{k,3})), 'Resolution', 150);
    end
    if ~p.keepfig, close(f); end
end

% 变形网格（放大显示）
f = figure('Color','w','Position',[80 80 900 560]);
scale = 0.10*H/max(um(:)+1e-12);
Xd = Xg + scale*ux;  Yd = Yg + scale*uy;
for j = 1:3:nx+1
    plot(Xd(:,j), Yd(:,j), '-', 'Color',[.75 .75 .75], 'LineWidth',.4); hold on;
end
for i = 1:3:ny+1
    plot(Xd(i,:), Yd(i,:), '-', 'Color',[.75 .75 .75], 'LineWidth',.4);
end
contour(Xg, Yg, pe, 8, 'LineColor',[.85 .2 .1], 'LineWidth', .9);
plot(xsurf, ysurf, 'k-', 'LineWidth', 1.6);
hold off; axis equal tight;
title(sprintf('变形网格（位移放大 %.0f 倍）+ 塑性带   F_s=%.2f', scale, Fs), 'FontSize', 11);
xlabel('x (m)'); ylabel('y (m)');
if p.export, exportgraphics(f, fullfile(out,'09_deformed.png'), 'Resolution', 150); end
if ~p.keepfig, close(f); end

% 滑裂带 + 位移矢量
f = figure('Color','w','Position',[80 80 900 560]);
pmax = max(pe(:));  if pmax <= 0, pmax = 1; end
lv = [0 0.03 0.07 0.12 0.20 0.32 0.48 0.68 1.00]*pmax;
contourf(Xg, Yg, pe, lv, 'LineColor','none'); hold on;
contour(Xg, Yg, pe, [0.10 0.25 0.50]*pmax, 'LineColor',[.30 .30 .30], 'LineWidth',.7);
js = max(1, round(nx/16));  is = max(1, round(ny/12));
% 箭头按位移方向归一化，只表示"往哪个方向动"，不按大小缩放
q = quiver(Xg(1:is:end,1:js:end), Yg(1:is:end,1:js:end), ...
           ux(1:is:end,1:js:end), uy(1:is:end,1:js:end), 0.55, 'k');
q.Color = [.15 .15 .15];
plot(xsurf, ysurf, 'k-', 'LineWidth', 1.5);
hold off; axis equal tight; clim([0 0.5*pmax]);
colormap(f, parula(256)); cb = colorbar; cb.Label.String = '等效塑性剪应变';
title(sprintf('潜在滑裂带 = 塑性剪应变集中区（灰线 10%%/25%%/50%% 峰值）   F_s = %.2f，绘图 F = %.2f', Fs, Fp), 'FontSize', 11);
xlabel('x (m)'); ylabel('y (m)');
if p.export, exportgraphics(f, fullfile(out,'10_slip_band.png'), 'Resolution', 150); end
if ~p.keepfig, close(f); end

if p.export, fprintf('  云图已输出到 %s\n', out); end
end

function [sx, sy, txy, vm, pe] = gp2node(sig, ep, quads, ny1, nx1, nn, nu)
sx = zeros(nn,1); sy = sx; txy = sx; vm = sx; pe = sx; cnt = zeros(nn,1);
for e = 1:size(quads,1)
    for g = 1:4
        s = sig(:,g,e);
        sz = nu*(s(1)+s(2));                                  % 平面应变弹性近似
        v  = sqrt(0.5*((s(1)-s(2))^2 + (s(2)-sz)^2 + (sz-s(1))^2) + 3*s(3)^2);
        for k = 1:4
            n = quads(e,k);
            sx(n)  = sx(n)  + s(1);
            sy(n)  = sy(n)  + s(2);
            txy(n) = txy(n) + s(3);
            vm(n)  = vm(n)  + v;
            pe(n)  = pe(n)  + ep(g,e);
            cnt(n) = cnt(n) + 1;
        end
    end
end
cnt(cnt==0) = 1;
sx  = reshape(sx./cnt,  ny1, nx1);
sy  = reshape(sy./cnt,  ny1, nx1);
txy = reshape(txy./cnt, ny1, nx1);
vm  = reshape(vm./cnt,  ny1, nx1);
pe  = reshape(pe./cnt,  ny1, nx1);
end

%% ========================================================================
%  几何形态扫描
%% ========================================================================
function sweep_cases(p)
betas = p.sweepBeta;
fprintf('\n=== 几何形态扫描 ===\n');
fprintf('   H = %.1f m，c = %.1f kPa，φ = %.0f°，γ = %.1f kN/m^3\n', p.H, p.c, p.phi, p.gamma);
fprintf('   %8s %10s %10s\n', '坡角β', '坡率1:m', 'Fs(FEM)');
Fs = zeros(size(betas));
for k = 1:numel(betas)
    q = p;  q.beta = betas(k);  q.quiet = true;  q.sweep = false;
    Fs(k) = run_case(q, false);
    fprintf('   %6.0f° %10.2f %10.3f\n', betas(k), cotd(betas(k)), Fs(k));
end
if p.export
    [okDir, msgDir] = mkdir(p.outdir);
    if ~okDir
        warning('无法创建输出目录：%s', msgDir);
    else
        f = figure('Color','w','Position',[100 100 760 480]);
        plot(betas, Fs, 'o-', 'LineWidth', 1.8, 'MarkerSize', 7, 'MarkerFaceColor','w');
        grid on; xlabel('坡角 β (°)'); ylabel('安全系数 F_s');
        title(sprintf('坡角对稳定性的影响（H=%.0f m，c=%.0f kPa，φ=%.0f°）', p.H, p.c, p.phi));
        exportgraphics(f, fullfile(p.outdir,'20_Fs_vs_beta.png'), 'Resolution', 150);
        if ~p.keepfig, close(f); end
    end
end
end

%% ========================================================================
%  参数解析
%% ========================================================================
function p = parse_opts(args)
p = struct( ...
    'H', 10, 'beta', 45, 'c', 20, 'phi', 15, 'psi', 0, ...
    'gamma', 18, 'E', 20000, 'nu', [], ...
    'nx', 48, 'ny', 24, 'depth', 1.0, 'xLeft', 1.2, 'xRight', 1.2, ...
    'nsteps', 5, 'nReduce', 10, 'maxit', 40, 'tol', 1e-3, 'uMax', 0.02, ...
    'Fmin', 0.60, 'Fmax', 3.00, 'nF', 8, ...
    'sweep', false, 'sweepBeta', [30 45 60], 'Fplot', [], ...
    'export', true, 'outdir', 'figures', 'keepfig', false, 'quiet', false, 'debug', false, ...
    'save', '');
if isempty(args), return; end
if numel(args) == 1 && isstruct(args{1})
    f = fieldnames(args{1});
    for i = 1:numel(f), p.(f{i}) = args{1}.(f{i}); end
    return;
end
for i = 1:2:numel(args)
    key = args{i};
    if ~isfield(p, key), error('未知参数：%s', key); end
    p.(key) = args{i+1};
end
end

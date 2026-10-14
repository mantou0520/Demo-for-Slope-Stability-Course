%% =======================================================================
%  赤平极射投影法 交互式教学演示（MATLAB 版）
%  适用课程：《边坡与支护工程》—— 边坡稳定性分析 / 赤平极射投影法
%
%  功能：
%    - 左侧三维投影球：结构面圆盘、球面大圆、极射线、赤平面上的投影圆弧
%    - 右侧赤平投影图：吴氏网(等角) / 施氏网(等面积)，大圆弧 + 极点
%    - 滑块实时调整倾向 α、倾角 β；单选切换上/下半球约定与投影网类型
%    - 「投射进度」滑块可逐步演示"逐点极射 → 连成圆弧"的全过程
%
%  运行：把本文件放在 MATLAB 当前目录，直接运行（无需任何工具箱，
%        仅用基础 MATLAB 绘图函数；若安装了 Mapping Toolbox 也无需调用）
%
%  坐标系约定：x = 东(E)，y = 北(N)，z = 上(Up)，投影球取单位球 R = 1
%  作者：为教学演示编写，可自由修改用于课堂
% =======================================================================
function stereonet_demo()
clc;

%% ---------- 全局状态 ----------
S = struct();
S.dipAz  = 120;        % 倾向 (°)
S.dip    = 45;         % 倾角 (°)
S.hemi   = 'lower';    % 'lower' 下半球投影 | 'upper' 上半球投影
S.mode   = 'angle';    % 'angle' 等角(吴氏网) | 'area' 等面积(施氏网)
S.anim   = 1;          % 投射进度 0~1

%% ---------- 图形界面 ----------
fig = figure('Name','赤平极射投影法 · 交互演示','NumberTitle','off', ...
             'Color',[0.95 0.97 0.99],'Position',[80 60 1180 640], ...
             'MenuBar','none','ToolBar','figure');
ax3 = axes('Parent',fig,'Position',[0.015 0.26 0.50 0.64]);        % 三维视图
ax2 = axes('Parent',fig,'Position',[0.55 0.22 0.42 0.72]);        % 二维投影图
info = uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.545 0.02 0.44 0.17],'HorizontalAlignment','left', ...
    'BackgroundColor',[1 1 1],'FontSize',9);

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.03 0.235 0.08 0.035],'String','倾向 α (°)','HorizontalAlignment','left', ...
    'BackgroundColor',[0.95 0.97 0.99]);
sAz = uicontrol('Style','slider','Parent',fig,'Units','normalized', ...
    'Position',[0.115 0.235 0.36 0.035],'Min',0,'Max',359,'Value',S.dipAz, ...
    'SliderStep',[1/359 10/359],'Callback',@onSlider);

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.03 0.180 0.08 0.035],'String','倾角 β (°)','HorizontalAlignment','left', ...
    'BackgroundColor',[0.95 0.97 0.99]);
sDip = uicontrol('Style','slider','Parent',fig,'Units','normalized', ...
    'Position',[0.115 0.180 0.36 0.035],'Min',0,'Max',90,'Value',S.dip, ...
    'SliderStep',[1/90 10/90],'Callback',@onSlider);

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.03 0.125 0.08 0.035],'String','投射进度','HorizontalAlignment','left', ...
    'BackgroundColor',[0.95 0.97 0.99]);
sAnim = uicontrol('Style','slider','Parent',fig,'Units','normalized', ...
    'Position',[0.115 0.125 0.36 0.035],'Min',0.02,'Max',1,'Value',1, ...
    'SliderStep',[0.02 0.1],'Callback',@onSlider);

bgHemi = uibuttongroup('Parent',fig,'Units','normalized','Position',[0.55 0.80 0.20 0.14], ...
    'Title','半球约定','BackgroundColor',[0.95 0.97 0.99]);
uicontrol('Style','radiobutton','Parent',bgHemi,'Units','normalized', ...
    'Position',[0.05 0.55 0.9 0.40],'String','下半球投影','Value',1,'Callback',@onRadio);
uicontrol('Style','radiobutton','Parent',bgHemi,'Units','normalized', ...
    'Position',[0.05 0.10 0.9 0.40],'String','上半球投影','Callback',@onRadio);

bgMode = uibuttongroup('Parent',fig,'Units','normalized','Position',[0.77 0.80 0.20 0.14], ...
    'Title','投影网','BackgroundColor',[0.95 0.97 0.99]);
uicontrol('Style','radiobutton','Parent',bgMode,'Units','normalized', ...
    'Position',[0.05 0.55 0.9 0.40],'String','吴氏网(等角)','Value',1,'Callback',@onRadio);
uicontrol('Style','radiobutton','Parent',bgMode,'Units','normalized', ...
    'Position',[0.05 0.10 0.9 0.40],'String','施氏网(等面积)','Callback',@onRadio);

uicontrol('Style','pushbutton','Parent',fig,'Units','normalized', ...
    'Position',[0.55 0.66 0.19 0.055],'String','▶ 播放逐点投射','Callback',@onPlay);
uicontrol('Style','pushbutton','Parent',fig,'Units','normalized', ...
    'Position',[0.76 0.66 0.21 0.055],'String','导出当前图 (PNG)','Callback',@onExport);

draw();                                  % 首次绘制

%% =================== 回调 ===================
    function onSlider(~,~)
        S.dipAz = get(sAz,'Value');
        S.dip   = get(sDip,'Value');
        S.anim  = get(sAnim,'Value');
        draw();
    end

    function onRadio(src,~)
        switch src.String
            case '下半球投影', S.hemi = 'lower';
            case '上半球投影', S.hemi = 'upper';
            case '吴氏网(等角)', S.mode = 'angle';
            case '施氏网(等面积)', S.mode = 'area';
        end
        draw();
    end

    function onPlay(~,~)
        for t = 0.02:0.03:1
            S.anim = t; set(sAnim,'Value',t);
            draw(); pause(0.02);
        end
    end

    function onExport(~,~)
        [f,p] = uiputfile({'*.png','PNG 图片'},'导出当前赤平投影图', ...
                          sprintf('赤平投影_%d_%d.png',round(S.dipAz),round(S.dip)));
        if isequal(f,0), return; end
        exportgraphics(fig, fullfile(p,f), 'Resolution', 200);
        fprintf('已导出：%s\n', fullfile(p,f));
    end

%% =================== 主绘制 ===================
    function draw()
        draw3D();
        draw2D();
        showInfo();
        drawnow limitrate;
    end

%% ---------- 三维投影球 ----------
    function draw3D()
        cla(ax3); hold(ax3,'on');
        f = planeFrame(S.dipAz, S.dip);

        % 球面（透明球 + 经纬线）
        [Xs,Ys,Zs] = sphere(48);
        surf(ax3, Xs,Ys,Zs,'FaceColor',[0.62 0.78 0.92],'FaceAlpha',0.10, ...
             'EdgeColor','none','FaceLighting','none');
        for lon = 0:45:135
            t = linspace(0,2*pi,120);
            plot3(ax3, sin(t)*cosd(lon), sin(t)*sind(lon), cos(t), ...
                  'Color',[0.55 0.66 0.78],'LineWidth',0.5);
        end
        for lat = -45:45:45
            t = linspace(0,2*pi,120);
            plot3(ax3, cosd(lat)*cos(t), cosd(lat)*sin(t), sind(lat)*ones(size(t)), ...
                  'Color',[0.55 0.66 0.78],'LineWidth',0.5);
        end

        % 赤平面
        t = linspace(0,2*pi,180);
        fill3(ax3, cos(t), sin(t), zeros(size(t)), [0.05 0.45 0.56], ...
              'FaceAlpha',0.13,'EdgeColor',[0.05 0.45 0.56],'LineWidth',1.2);

        % 结构面圆盘 + 球面大圆
        gc = greatCircle(S.dipAz, S.dip, 240);
        fill3(ax3, gc(:,1), gc(:,2), gc(:,3), [0.85 0.18 0.13], ...
              'FaceAlpha',0.15,'EdgeColor','none');
        plot3(ax3, gc(:,1), gc(:,2), gc(:,3), 'Color',[0.78 0.12 0.08],'LineWidth',2.4);

        % 走向线（青虚线）与倾斜线（橙实线）
        plot3(ax3, [-f.strike(1) f.strike(1)],[-f.strike(2) f.strike(2)],[0 0], ...
              '--','Color',[0.06 0.46 0.43],'LineWidth',1.8);
        plot3(ax3, [-f.down(1) f.down(1)],[-f.down(2) f.down(2)],[-f.down(3) f.down(3)], ...
              '-','Color',[0.71 0.33 0.04],'LineWidth',2.2);

        % 极点（法线）
        if strcmp(S.hemi,'upper'), pv = f.nUp; else, pv = f.nDown; end
        plot3(ax3, [0 pv(1)],[0 pv(2)],[0 pv(3)],':','Color',[0.76 0.45 0.04],'LineWidth',1.6);
        plot3(ax3, pv(1),pv(2),pv(3),'o','MarkerSize',7, ...
              'MarkerFaceColor',[0.88 0.54 0],'MarkerEdgeColor','w');

        % 极射点
        if strcmp(S.hemi,'upper'), emitter = [0 0 -1]; else, emitter = [0 0 1]; end
        plot3(ax3, emitter(1),emitter(2),emitter(3),'o','MarkerSize',8, ...
              'MarkerFaceColor',[0.07 0.09 0.15],'MarkerEdgeColor','w');
        text(ax3, emitter(1)*1.15, emitter(2), emitter(3)*1.15, ' 极射点', 'FontSize',9);

        % 极射线 + 投影点 + 结果圆弧
        nRay = 12;  kEnd = max(1, round(nRay*S.anim));
        t0 = 0; if strcmp(S.hemi,'upper'), t0 = pi; end
        for i = 1:kEnd
            t = t0 + pi*(i-1)/(nRay-1);
            P = cos(t)*f.strike + sin(t)*f.down;
            u = 1/(1 - sign(emitter(3))*P(3));
            Q = emitter + u*(P - emitter);
            plot3(ax3, [emitter(1) Q(1)],[emitter(2) Q(2)],[emitter(3) Q(3)], ...
                  '--','Color',[0.15 0.39 0.92],'LineWidth',0.6);
            plot3(ax3, [P(1) Q(1)],[P(2) Q(2)],[P(3) Q(3)], ...
                  '-','Color',[0.85 0.18 0.13],'LineWidth',0.9);
            plot3(ax3, Q(1),Q(2),0,'.','Color',[0.11 0.31 0.85],'MarkerSize',7);
        end
        tt = t0 + pi*linspace(0,S.anim,120);
        Pt = cos(tt)'*f.strike + sin(tt)'*f.down;
        uu = 1./(1 - sign(emitter(3))*Pt(:,3));
        Qs = emitter + uu.*(Pt - emitter);  Qs(:,3) = 0;
        plot3(ax3, Qs(:,1), Qs(:,2), Qs(:,3), 'Color',[0.11 0.31 0.85],'LineWidth',2.6);

        % 方位标记与坐标轴设置
        text(ax3, 1.25,0,0,'E 东','FontSize',8,'Color',[0.20 0.25 0.31]);
        text(ax3, -1.35,0,0,'W 西','FontSize',8,'Color',[0.20 0.25 0.31]);
        text(ax3, 0,1.25,0,'N 北','FontSize',8,'Color',[0.20 0.25 0.31]);
        text(ax3, 0,-1.30,0,'S 南','FontSize',8,'Color',[0.20 0.25 0.31]);
        text(ax3, 0.72,0.72,0.02,'赤平面','FontSize',8,'Color',[0.05 0.45 0.56]);

        daspect(ax3,[1 1 1]);
        xlim(ax3,[-1.12 1.12]); ylim(ax3,[-1.12 1.12]); zlim(ax3,[-1.12 1.12]);
        grid(ax3,'off'); axis(ax3,'off');
        ax3.CameraViewAngle = 6.0;          % 收紧视场角，让投影球充满子图
        view(ax3,-48,22);
        title(ax3, sprintf('三维投影球与极射光路（结构面 %g°∠%g°）', S.dipAz, S.dip), ...
              'FontSize',10,'Color',[0.09 0.13 0.18],'FontWeight','normal');
    end

%% ---------- 二维赤平投影图 ----------
    function draw2D()
        cla(ax2); hold(ax2,'on'); axis(ax2,'equal'); axis(ax2,'off');

        % 基圆
        t = linspace(0,2*pi,400);
        fill(ax2, cos(t), sin(t), [0.98 0.99 1], 'EdgeColor',[0.20 0.25 0.31],'LineWidth',1.8);

        % 投影网
        curves = netCurves();
        for k = 1:numel(curves)
            c = curves{k};
            if strcmp(S.hemi,'lower'), c = c(c(:,3) <= 1e-9, :); else, c = c(c(:,3) >= -1e-9, :); end
            if size(c,1) < 2, continue; end
            xy = stereo(c, S.hemi, S.mode);
            plot(ax2, xy(:,1), xy(:,2), '-', 'Color',[0.72 0.79 0.86],'LineWidth',0.5);
        end
        plot(ax2, [-1 1],[0 0],'-','Color',[0.55 0.62 0.70],'LineWidth',0.7);
        plot(ax2, [0 0],[-1 1],'-','Color',[0.55 0.62 0.70],'LineWidth',0.7);
        text(ax2,0,1.09,'N','HorizontalAlignment','center','FontWeight','bold','FontSize',12);
        text(ax2,0,-1.16,'S','HorizontalAlignment','center','FontWeight','bold','FontSize',12);
        text(ax2,1.06,-0.03,'E','FontWeight','bold','FontSize',12);
        text(ax2,-1.06,-0.03,'W','HorizontalAlignment','right','FontWeight','bold','FontSize',12);

        % 大圆弧（随投射进度增长）
        gc = greatCircle(S.dipAz, S.dip, 480);
        if strcmp(S.hemi,'lower'), gc = gc(gc(:,3) <= 1e-9, :); else, gc = gc(gc(:,3) >= -1e-9, :); end
        n = max(2, round(size(gc,1)*S.anim));
        xy = stereo(gc(1:n,:), S.hemi, S.mode);
        plot(ax2, xy(:,1), xy(:,2), '-', 'Color',[0.78 0.12 0.08],'LineWidth',3);
        if S.anim > 0.98    % 弧画完后标注走向点、弧顶、极点
            f = planeFrame(S.dipAz, S.dip);
            sp = stereo(f.strike, S.hemi, S.mode);
            dp = stereo(f.down,   S.hemi, S.mode);
            pp = stereo(selectPole(f, S.hemi), S.hemi, S.mode);
            plot(ax2, sp(1),sp(2),'o','MarkerSize',5, ...
                 'MarkerFaceColor',[0.06 0.46 0.43],'MarkerEdgeColor','w');
            plot(ax2, [0 dp(1)],[0 dp(2)],'-','Color',[0.71 0.33 0.04],'LineWidth',1.8);
            plot(ax2, pp(1),pp(2),'o','MarkerSize',6.5, ...
                 'MarkerFaceColor',[0.88 0.54 0],'MarkerEdgeColor','w');
            plot(ax2, [0 pp(1)],[0 pp(2)],':','Color',[0.88 0.54 0],'LineWidth',1.2);
            text(ax2, pp(1)+0.05, pp(2)+0.03, '极点','FontSize',9,'Color',[0.76 0.45 0.04], ...
                 'FontWeight','bold');
            text(ax2, dp(1)+0.05, dp(2)-0.05, '弧顶(最陡倾斜线)','FontSize',9, ...
                 'Color',[0.71 0.33 0.04],'FontWeight','bold');
            text(ax2, sp(1)+0.03, sp(2)-0.09, '走向点','FontSize',9, ...
                 'Color',[0.06 0.46 0.43],'FontWeight','bold');
        end
        axis(ax2,[-1.25 1.25 -1.25 1.25]); daspect(ax2,[1 1 1]);
        title(ax2, sprintf('赤平投影图（%s + %s）', ...
              ternary(strcmp(S.hemi,'lower'),'下半球投影','上半球投影'), ...
              ternary(strcmp(S.mode,'angle'),'吴氏网/等角','施氏网/等面积')), 'FontSize',11);
    end

%% ---------- 文字读数 ----------
    function showInfo()
        f = planeFrame(S.dipAz, S.dip);
        [plunge, paz] = lineAttitude(selectPole(f, S.hemi));
        rArc  = tand(45 - S.dip/2);
        rPole = tand(S.dip/2);
        stroke = mod(S.dipAz + 90, 360);
        apexAz = ternary(strcmp(S.hemi,'lower'), S.dipAz, mod(S.dipAz+180,360));
        set(info,'String',{ ...
            sprintf('产状 %g°∠%g°   走向 %g° / %g°   弧顶方位 %g°', S.dipAz, S.dip, stroke, mod(stroke+180,360), apexAz), ...
            sprintf('弧顶半径 r/R = tan(45°-β/2) = %.4f      极点半径 r/R = tan(β/2) = %.4f', rArc, rPole), ...
            sprintf('极点方位 %.1f°  伏角 %.1f°   （极点伏角 = 90° - 倾角）', paz, plunge), ...
            '读数口诀：弧端方位=走向；弧顶方位=倾向；弧顶越靠圆心→倾角越陡；β=0° 时大圆与基圆重合，β=90° 时退化为过圆心的直径。'});
    end
end                                        % ==== 主函数结束 ====


%% =======================================================================
%  以下为核心数学函数（与 index.html / stereonet_demo.py 完全一致，已数值校验）
%% =======================================================================
function f = planeFrame(dipAz, dip)
% 由产状求平面三要素：走向 strike、倾向线 down（指向下方）、上法线 nUp
a = dipAz*pi/180;  b = dip*pi/180;
f.strike = [cos(a), -sin(a), 0];
f.down   = [cos(b)*sin(a), cos(b)*cos(a), -sin(b)];
f.nUp    = [sin(b)*sin(a), sin(b)*cos(a),  cos(b)];
f.nDown  = -f.nUp;
end

function gc = greatCircle(dipAz, dip, n)
% 过球心大圆的采样点 g(t) = cos t·走向 + sin t·倾向线
% t∈[0,π] 在下半球，t∈[π,2π] 在上半球
f  = planeFrame(dipAz, dip);
t  = linspace(0, 2*pi, n+1)';
gc = cos(t)*f.strike + sin(t)*f.down;
end

function xy = stereo(P, hemi, mode)
% 极射赤平投影：把单位球面点 P 投到赤平面上，返回 [E, N]（半径 ≤ 1）
% hemi='lower' 下半球投影（自上极点发射）；'upper' 上半球投影（自下极点发射）
% mode='angle' 等角(吴氏网) r=tan(θ/2)；'area' 等面积(施氏网) r=√2·sin(θ/2)
    axisSign = 1; if strcmp(hemi,'lower'), axisSign = -1; end
    V = P;
    flip = V(:,3)*axisSign < 0;
    V(flip,:) = -V(flip,:);
    cosT = max(-1, min(1, V(:,3)*axisSign));
    th   = acos(cosT);
    if strcmp(mode,'area')
        r = sqrt(2)*sin(th/2);
    else
        r = tan(th/2);
    end
    m  = sqrt(V(:,1).^2 + V(:,2).^2);
    ex = zeros(size(m));  ey = zeros(size(m));
    ok = m > 1e-12;
    ex(ok) = V(ok,1)./m(ok);  ey(ok) = V(ok,2)./m(ok);
    xy = [ex.*r, ey.*r];
end

function [plunge, az] = lineAttitude(L)
% 空间直线的下半球产状：倾伏角 plunge、倾伏向 az
v = L(:)';
if v(3) > 0, v = -v; end
plunge = asin(max(-1,min(1,-v(3))))*180/pi;
az = mod(atan2(v(1), v(2))*180/pi, 360);
end

function L = intersectionLine(az1, dip1, az2, dip2)
% 两平面交棱线方向（单位向量）
L = cross(planeFrame(az1,dip1).nUp, planeFrame(az2,dip2).nUp);
L = L / (norm(L) + eps);
end

function pv = selectPole(f, hemi)
% 按半球约定选取要绘制的极点方向
if strcmp(hemi,'upper'), pv = f.nUp; else, pv = f.nDown; end
end

function c = netCurves()
% 吴氏网/施氏网的网格：经线（过基圆 N、S 两点的大圆）+ 纬线（绕南北水平轴的小圆）
c = {};
for b = 10:10:80
    c{end+1} = greatCircle(90,  b, 160);     % 向东倾
    c{end+1} = greatCircle(270, b, 160);     % 向西倾
end
for g = 10:10:170
    gr  = g*pi/180;
    phi = linspace(pi, 2*pi, 161)';
    c{end+1} = [sin(gr)*cos(phi), cos(gr)*ones(size(phi)), sin(gr)*sin(phi)];
end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end

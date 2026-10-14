# -*- coding: utf-8 -*-
"""
赤平极射投影法 交互式教学演示（Python / matplotlib 版）
======================================================================
为《边坡与支护工程》课程"边坡稳定性分析"章节编写。

功能：
  1) 交互模式（默认）：拖动滑块改变结构面倾向/倾角，左侧三维投影球与右侧赤平
     投影图实时联动；可切换上/下半球约定、吴氏网(等角)/施氏网(等面积)、显示项。
  2) 导出模式（--export）：生成 4 张可直接插入 PPT 的教学图，输出到 figures/。

                运行方式
  ---------------------------------------------------------------
  交互演示：   python stereonet_demo.py
  导出图集：   python stereonet_demo.py --export
  导出+交互：  python stereonet_demo.py --export --also-show

  依赖：numpy, matplotlib        （pip install numpy matplotlib）

坐标系约定：x = 东(E)，y = 北(N)，z = 上(Up)，投影球取单位球 R = 1
======================================================================
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np
import matplotlib
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Circle, Wedge, Polygon
from matplotlib.widgets import Slider, RadioButtons, CheckButtons
from mpl_toolkits.mplot3d.art3d import Poly3DCollection, Line3DCollection

DEG = np.pi / 180.0
RAD = 180.0 / np.pi

# ----------------------------------------------------------------------------
# 0. 中文字体
# ----------------------------------------------------------------------------
def setup_chinese_font() -> bool:
    """挑选一个可用的中文字体，返回是否成功。"""
    cands = ["Microsoft YaHei", "SimHei", "SimSun", "Noto Sans CJK SC",
             "Source Han Sans SC", "WenQuanYi Zen Hei", "PingFang SC", "Heiti SC"]
    from matplotlib import font_manager
    have = {f.name for f in font_manager.fontManager.ttflist}
    for c in cands:
        if c in have:
            matplotlib.rcParams["font.sans-serif"] = [c]
            matplotlib.rcParams["axes.unicode_minus"] = False
            return True
    matplotlib.rcParams["axes.unicode_minus"] = False
    print("[警告] 未找到中文字体，图中中文可能显示为方框。"
          "可安装 SimHei/Microsoft YaHei 或改用英文标签。", file=sys.stderr)
    return False


# ============================================================================
# 1. 核心数学（与 index.html 中的 JS 实现完全一致，已数值校验）
# ============================================================================
def plane_frame(dip_az: float, dip: float) -> dict:
    """由产状求平面三要素。dip_az 倾向(°)，dip 倾角(°)。"""
    a, b = dip_az * DEG, dip * DEG
    strike = np.array([np.cos(a), -np.sin(a), 0.0])                        # 走向
    down = np.array([np.cos(b) * np.sin(a), np.cos(b) * np.cos(a), -np.sin(b)])  # 倾向线
    n_up = np.array([np.sin(b) * np.sin(a), np.sin(b) * np.cos(a), np.cos(b)])   # 上法线
    return {"strike": strike, "down": down, "n_up": n_up, "n_down": -n_up}


def great_circle(dip_az: float, dip: float, n: int = 361) -> np.ndarray:
    """过球心大圆的采样点，返回 (n+1, 3)。t∈[0,π] 在下半球，t∈[π,2π] 在上半球。"""
    f = plane_frame(dip_az, dip)
    t = np.linspace(0.0, 2 * np.pi, n + 1)[:, None]
    return np.cos(t) * f["strike"] + np.sin(t) * f["down"]


def stereo(points: np.ndarray, hemi: str = "lower", mode: str = "angle") -> np.ndarray:
    """极射赤平投影。points: (...,3) 单位向量；返回 (...,2) 的 (E, N) 坐标，半径 ≤ 1。

    hemi='lower' 下半球投影（自上极点发射）；hemi='upper' 上半球投影（自下极点发射）
    mode='angle' 等角(吴氏网)；mode='area' 等面积(施氏网)
    """
    p = np.atleast_2d(np.asarray(points, dtype=float))
    axis = 1.0 if hemi == "upper" else -1.0
    v = p.copy()
    flip = v[:, 2] * axis < 0
    v[flip] = -v[flip]                                   # 取到指定半球的对应点
    cos_t = np.clip(v[:, 2] * axis, -1.0, 1.0)
    th = np.arccos(cos_t)                                # 与轴的夹角 θ∈[0,π/2]
    r = np.sqrt(2.0) * np.sin(th / 2.0) if mode == "area" else np.tan(th / 2.0)
    m = np.hypot(v[:, 0], v[:, 1])
    ex = np.where(m < 1e-12, 0.0, v[:, 0] / np.where(m < 1e-12, 1.0, m))
    ey = np.where(m < 1e-12, 0.0, v[:, 1] / np.where(m < 1e-12, 1.0, m))
    return np.column_stack([ex * r, ey * r])


def line_attitude(L: np.ndarray) -> tuple[float, float]:
    """空间直线的产状 -> (倾伏角 plunge, 倾伏向 azimuth)，均取下半球那一端。"""
    v = np.asarray(L, dtype=float).copy()
    if v[2] > 0:
        v = -v
    plunge = np.arcsin(np.clip(-v[2], -1, 1)) * RAD
    az = np.arctan2(v[0], v[1]) * RAD % 360.0
    return float(plunge), float(az)


def intersection_line(az1, dip1, az2, dip2) -> np.ndarray:
    """两平面交棱线方向（单位向量）。"""
    L = np.cross(plane_frame(az1, dip1)["n_up"], plane_frame(az2, dip2)["n_up"])
    return L / (np.linalg.norm(L) or 1.0)


def ang_diff(a, b) -> float:
    """两个方位角的最小夹角（0~180）。"""
    return abs(((a - b) % 360 + 540) % 360 - 180)


def wulff_curves(n_seg: int = 241):
    """吴氏网/施氏网的网格曲线（返回 [(N,3), ...]，逐条给出三维采样点）。"""
    curves = []
    for b in range(10, 90, 10):                          # 经线：走向南北、向东西倾斜
        curves.append(great_circle(90, b, n_seg))
        curves.append(great_circle(270, b, n_seg))
    for g in range(10, 180, 10):                         # 纬线：绕南北水平轴的小圆
        gr, phi = g * DEG, np.linspace(np.pi, 2 * np.pi, n_seg + 1)
        curves.append(np.column_stack([np.sin(gr) * np.cos(phi),
                                       np.full_like(phi, np.cos(gr)),
                                       np.sin(gr) * np.sin(phi)]))
    return curves


# ============================================================================
# 2. 绘图：三维投影球
# ============================================================================
def draw_3d(ax, dip_az, dip, hemi="lower", mode="angle",
            show_gc=True, show_rays=True, show_pole=True, anim=1.0,
            label=True, elev=20, azim=-48, zoom=1.22):
    """在给定 3D 坐标轴上画出投影球、赤平面、结构面、极射线与投影结果。"""
    ax.clear()
    f = plane_frame(dip_az, dip)
    emitter = np.array([0, 0, 1.0]) if hemi == "lower" else np.array([0, 0, -1.0])

    # --- 球面（半透明）---
    u = np.linspace(0, 2 * np.pi, 61)
    v = np.linspace(0, np.pi, 31)
    X = np.outer(np.cos(u), np.sin(v)); Y = np.outer(np.sin(u), np.sin(v)); Z = np.outer(np.ones_like(u), np.cos(v))
    ax.plot_surface(X, Y, Z, color="#9fc3e8", alpha=0.10, linewidth=0, shade=False, zorder=1)

    # --- 球面网格：经纬线 ---
    for lon in np.arange(0, 180, 30):
        t = np.linspace(0, 2 * np.pi, 121)
        ax.plot(np.sin(t) * np.cos(lon * DEG), np.sin(t) * np.sin(lon * DEG), np.cos(t),
                color="#7f9fc0", lw=0.6, alpha=0.55, zorder=2)
    for lat in np.arange(-60, 61, 30):
        t = np.linspace(0, 2 * np.pi, 121)
        rc, zc = np.cos(lat * DEG), np.sin(lat * DEG)
        ax.plot(rc * np.cos(t), rc * np.sin(t), np.full_like(t, zc),
                color="#7f9fc0", lw=0.6, alpha=0.55, zorder=2)

    # --- 赤平面 ---
    t = np.linspace(0, 2 * np.pi, 181)
    eq = np.column_stack([np.cos(t), np.sin(t), np.zeros_like(t)])
    ax.add_collection3d(Poly3DCollection([eq], color="#0e7490", alpha=0.13, zorder=3))
    ax.plot(eq[:, 0], eq[:, 1], eq[:, 2], color="#0e7490", lw=1.4, alpha=0.85, zorder=4)

    # --- 结构面圆盘 ---
    disk = great_circle(dip_az, dip, 181)
    ax.add_collection3d(Poly3DCollection([disk], color="#d92d20", alpha=0.15, zorder=5))

    # --- 大圆（球面交线）---
    if show_gc:
        gc = great_circle(dip_az, dip, 361)
        ax.plot(gc[:, 0], gc[:, 1], gc[:, 2], color="#c81e14", lw=2.6, zorder=6)

    # --- 走向线 / 倾斜线 ---
    ax.plot(*np.column_stack([-f["strike"], f["strike"]]), color="#0f766e", lw=2.0,
            ls="--", zorder=7)
    ax.plot(*np.column_stack([-f["down"], f["down"]]), color="#b45309", lw=2.4, zorder=7)

    # --- 极点 ---
    pv = f["n_up"] if hemi == "upper" else f["n_down"]
    if show_pole:
        ax.plot([0, pv[0]], [0, pv[1]], [0, pv[2]], color="#c2740a", lw=1.8, ls=":", zorder=8)
        ax.scatter(*pv, s=55, color="#e08a00", edgecolor="w", lw=1.2, zorder=9)

    # --- 极射点 ---
    ax.scatter(*emitter, s=70, color="#111827", edgecolor="w", lw=1.4, zorder=10)
    if label:
        ax.text(*emitter * 1.12, " 极射点", color="#111827", fontsize=9)

    # --- 极射线 + 投影点 + 结果弧 ---
    t0 = np.pi if hemi == "upper" else 0.0
    n_ray = 24
    k_end = max(1, int(round(n_ray * anim)))
    if show_rays:
        for i in range(k_end):
            t = t0 + np.pi * i / (n_ray - 1)
            P = np.cos(t) * f["strike"] + np.sin(t) * f["down"]
            uu = 1.0 / (1.0 - np.sign(emitter[2]) * P[2])
            Q = emitter + uu * (P - emitter)
            ax.plot([emitter[0], Q[0]], [emitter[1], Q[1]], [emitter[2], Q[2]],
                    color="#2563eb", lw=0.7, alpha=0.42, ls=(0, (3, 3)), zorder=11)
            ax.plot([P[0], Q[0]], [P[1], Q[1]], [P[2], Q[2]],
                    color="#d92d20", lw=1.0, alpha=0.55, zorder=11)
            ax.scatter(Q[0], Q[1], 0, s=7, color="#1d4ed8", zorder=12)
        # 结果弧
        tt = t0 + np.pi * np.linspace(0, anim, 121)
        Ptmp = np.cos(tt)[:, None] * f["strike"] + np.sin(tt)[:, None] * f["down"]
        uu = 1.0 / (1.0 - np.sign(emitter[2]) * Ptmp[:, 2])
        Qs = emitter + uu[:, None] * (Ptmp - emitter)
        Qs[:, 2] = 0.0
        ax.plot(Qs[:, 0], Qs[:, 1], Qs[:, 2], color="#1d4ed8", lw=3.0, zorder=13)

    if label:
        ax.text(1.30, 0, 0, " E", color="#334155", fontsize=9)
        ax.text(0, 1.30, 0, " N", color="#334155", fontsize=9)
        ax.text(0, -1.30, 0, " S", color="#334155", fontsize=9)
        ax.text(-1.30, 0, 0, " W", color="#334155", fontsize=9)
        ax.text(0.7, 0.7, 0.02, " 赤平面", color="#0e7490", fontsize=9)

    ax.set_xlim(-1.15, 1.15); ax.set_ylim(-1.15, 1.15); ax.set_zlim(-1.15, 1.15)
    ax.set_box_aspect((1, 1, 1), zoom=zoom)
    ax.set_axis_off()
    ax.view_init(elev=elev, azim=azim)
    return ax


# ============================================================================
# 3. 绘图：二维赤平投影图
# ============================================================================
def draw_net(ax, hemi="lower", mode="angle", lw=0.7, color="#a8b9c9", tick=True):
    """画基圆 + 投影网 + 方位刻度。"""
    ax.set_aspect("equal")
    ax.add_patch(Circle((0, 0), 1.0, facecolor="#fbfdff", edgecolor="#334155", lw=1.8, zorder=1))
    for c in wulff_curves(241):
        pts = c[(c[:, 2] <= 1e-9) if hemi == "lower" else (c[:, 2] >= -1e-9)]
        if len(pts) < 2:
            continue
        xy = stereo(pts, hemi, mode)
        ax.plot(xy[:, 0], xy[:, 1], color=color, lw=lw, zorder=2)
    ax.plot([-1, 1], [0, 0], color="#64768a", lw=0.8, alpha=0.6, zorder=3)
    ax.plot([0, 0], [-1, 1], color="#64768a", lw=0.8, alpha=0.6, zorder=3)
    for txt, x, y, ha in [("N", 0, 1.10, "center"), ("S", 0, -1.16, "center"),
                          ("E", 1.06, -0.04, "left"), ("W", -1.06, -0.04, "right")]:
        ax.text(x, y, txt, ha=ha, va="center", fontsize=12, fontweight="bold", color="#334155")
    if tick:
        for d in range(30, 360, 30):
            if d % 90 == 0:
                continue
            a = (90 - d) * DEG
            ax.plot([np.cos(a), 1.045 * np.cos(a)], [np.sin(a), 1.045 * np.sin(a)],
                    color="#64768a", lw=0.8, alpha=0.6)
    ax.set_xlim(-1.22, 1.22); ax.set_ylim(-1.22, 1.22); ax.axis("off")


def draw_plane(ax, dip_az, dip, hemi="lower", mode="angle",
               color="#c81e14", lw=3.0, label=None, show_pole=True,
               pole_color="#e08a00", zorder=6, frac=1.0, label_pos=0.5):
    """在投影图上画出一条大圆弧及其极点，返回关键点字典。
    frac 控制绘制比例(0~1)；label_pos 控制标注沿弧的位置(0=起点侧, 0.5=弧顶)。"""
    f = plane_frame(dip_az, dip)
    gc = great_circle(dip_az, dip, 481)
    pts = gc[(gc[:, 2] <= 1e-9) if hemi == "lower" else (gc[:, 2] >= -1e-9)]
    if frac < 1.0:
        pts = pts[:max(2, int(round(len(pts) * frac)))]
    xy = stereo(pts, hemi, mode)
    ax.plot(xy[:, 0], xy[:, 1], color=color, lw=lw, solid_capstyle="round", zorder=zorder)
    pole = stereo((f["n_up"] if hemi == "upper" else f["n_down"])[None, :], hemi, mode)[0]
    if show_pole and frac > 0.98:
        ax.scatter(*pole, s=52, color=pole_color, edgecolor="w", lw=1.4, zorder=zorder + 1)
    if label:
        mid = xy[int(np.clip(label_pos, 0, 1) * (len(xy) - 1))]
        ax.text(mid[0] + 0.04, mid[1] + 0.03, label, color=color,
                fontsize=9.5, fontweight="bold", zorder=zorder + 2,
                bbox=dict(fc="white", ec="none", alpha=0.7, pad=0.8))
    return {"xy": xy, "pole": pole, "frame": f}


def friction_circle(ax, phi, color="#7c3aed", ls=(0, (6, 4)), label=True):
    r = np.tan((45 - phi / 2) * DEG)
    ax.add_patch(Circle((0, 0), r, facecolor=color, alpha=0.08, edgecolor="none", zorder=4))
    ax.add_patch(Circle((0, 0), r, facecolor="none", edgecolor=color, lw=1.6,
                        ls=ls, zorder=5))
    if label:
        ax.text(r + 0.03, r * 0.72, f"摩擦圆 φ={phi:g}°", color=color, fontsize=9.5,
                fontweight="bold", zorder=6)
    return r


def daylight_envelope(ax, slope_az, slope_dip, phi, half=20, zorder=4):
    """画出边坡判别的两个判别区 —— 以摩擦圆为分界线（对应工具②页）：

    ① 滑动出露区：r ∈ [tan(45°−坡角/2), tan(45°−φ/2)]，位于坡向 ±20°
       判读对象是"大圆弧顶"；等价条件 φ < 结构面倾角 < 坡角
    ② 倾倒区：r ∈ [tan(45°−φ/2), 1]，位于坡向 ±20°
       判读对象是"极点"；等价条件 极点伏角 ≤ φ 且结构面倾向坡内
    """
    a_mid = 90.0 - slope_az
    t1, t2 = a_mid - half, a_mid + half
    r_fric = np.tan((45 - phi / 2) * DEG)
    r_env = np.tan((45 - slope_dip / 2) * DEG)
    if r_fric > r_env:                                   # φ < 坡角时该区存在
        ax.add_patch(Wedge((0, 0), r_fric, t1, t2, width=r_fric - r_env,
                           facecolor="#f59e0b", alpha=0.30, edgecolor="none", zorder=zorder))
    ax.add_patch(Wedge((0, 0), 1.0, t1, t2, width=1.0 - r_fric,
                       facecolor="#db2777", alpha=0.16, edgecolor="none", zorder=zorder))
    tt = np.linspace(t1, t2, 80) * DEG
    ax.plot(r_env * np.cos(tt), r_env * np.sin(tt), color="#d92d20", lw=1.5,
            ls=(0, (5, 4)), zorder=zorder + 1)
    if r_fric > r_env:
        ax.text((r_env + r_fric) / 2 * np.cos(a_mid * DEG) + 0.05,
                (r_env + r_fric) / 2 * np.sin(a_mid * DEG) + 0.05,
                "滑动出露区", ha="center", va="bottom", rotation=0,
                color="#b45309", fontsize=9, fontweight="bold", zorder=zorder + 3,
                bbox=dict(fc="white", ec="none", alpha=0.75, pad=1.0))
    ax.text((r_fric + 1) / 2 * np.cos(a_mid * DEG),
            (r_fric + 1) / 2 * np.sin(a_mid * DEG),
            "倾倒区", ha="center", va="center",
            color="#be185d", fontsize=9, fontweight="bold", zorder=zorder + 3,
            bbox=dict(fc="white", ec="none", alpha=0.75, pad=1.0))
    return r_env, r_fric


# ============================================================================
# 4. 交互模式
# ============================================================================
class StereonetApp:
    """matplotlib 交互式演示界面。"""

    def __init__(self, dip_az=120.0, dip=45.0):
        self.dip_az, self.dip = dip_az, dip
        self.hemi, self.mode = "lower", "angle"
        self.show = {"gc": True, "rays": True, "pole": True, "net": True}
        self.anim = 1.0

        self.fig = plt.figure(figsize=(13.2, 7.2))
        self.fig.canvas.manager.set_window_title("赤平极射投影法 · 交互演示")
        self.ax3d = self.fig.add_axes([0.02, 0.28, 0.50, 0.66], projection="3d")
        self.ax2d = self.fig.add_axes([0.54, 0.24, 0.44, 0.70])
        self.ax_txt = self.fig.add_axes([0.535, 0.03, 0.45, 0.18]); self.ax_txt.axis("off")
        self.ax_ctrl = self.fig.add_axes([0.02, 0.05, 0.48, 0.19]); self.ax_ctrl.axis("off")

        # 滑块
        self.s_az = Slider(self.fig.add_axes([0.11, 0.205, 0.34, 0.028]),
                           "倾向 α", 0, 359, valinit=dip_az, valstep=1)
        self.s_dip = Slider(self.fig.add_axes([0.11, 0.160, 0.34, 0.028]),
                            "倾角 β", 0, 90, valinit=dip, valstep=1)
        self.s_anim = Slider(self.fig.add_axes([0.11, 0.115, 0.34, 0.028]),
                             "投射进度", 0, 1, valinit=1.0, valstep=0.01)
        # 单选 / 多选
        self.r_hemi = RadioButtons(self.fig.add_axes([0.60, 0.60, 0.18, 0.10]),
                                   ("下半球投影", "上半球投影"), active=0)
        self.r_mode = RadioButtons(self.fig.add_axes([0.60, 0.46, 0.18, 0.10]),
                                   ("吴氏网(等角)", "施氏网(等面积)"), active=0)
        self.c_show = CheckButtons(self.fig.add_axes([0.80, 0.46, 0.18, 0.24]),
                                   ("大圆", "极射线", "极点", "投影网"),
                                   (True, True, True, True))

        self.s_az.on_changed(self._upd); self.s_dip.on_changed(self._upd)
        self.s_anim.on_changed(self._upd)
        self.r_hemi.on_clicked(self._on_hemi); self.r_mode.on_clicked(self._on_mode)
        self.c_show.on_clicked(self._on_show)
        self.redraw()

    # ---- 回调 ----
    def _upd(self, _=None):
        self.dip_az = float(self.s_az.val); self.dip = float(self.s_dip.val)
        self.anim = float(self.s_anim.val)
        self.redraw()

    def _on_hemi(self, lab):
        self.hemi = "upper" if lab.startswith("上半球") else "lower"; self.redraw()

    def _on_mode(self, lab):
        self.mode = "area" if lab.startswith("施氏") else "angle"; self.redraw()

    def _on_show(self, lab):
        key = {"大圆": "gc", "极射线": "rays", "极点": "pole", "投影网": "net"}[lab]
        self.show[key] = not self.show[key]; self.redraw()

    # ---- 重绘 ----
    def redraw(self):
        draw_3d(self.ax3d, self.dip_az, self.dip, self.hemi, self.mode,
                show_gc=self.show["gc"], show_rays=self.show["rays"],
                show_pole=self.show["pole"], anim=self.anim)
        ax = self.ax2d; ax.clear()
        if self.show["net"]:
            draw_net(ax, self.hemi, self.mode)
        else:
            ax.set_aspect("equal"); ax.add_patch(
                Circle((0, 0), 1.0, facecolor="#fbfdff", edgecolor="#334155", lw=1.8))
            ax.set_xlim(-1.22, 1.22); ax.set_ylim(-1.22, 1.22); ax.axis("off")
        draw_plane(ax, self.dip_az, self.dip, self.hemi, self.mode,
                   show_pole=self.show["pole"], label="大圆")
        self._text()
        self.fig.canvas.draw_idle()

    def _text(self):
        ax = self.ax_txt; ax.clear(); ax.axis("off")
        az, dip, hemi = self.dip_az, self.dip, self.hemi
        f = plane_frame(az, dip)
        pv = f["n_up"] if hemi == "upper" else f["n_down"]
        plunge, p_az = line_attitude(pv)
        r_arc = np.tan((45 - dip / 2) * DEG)
        r_pole = np.tan(dip / 2 * DEG)
        stroke = (az + 90) % 360
        conv = "下半球投影（自上极点发射）" if hemi == "lower" else "上半球投影（自下极点发射）"
        netname = "吴氏网 等角" if self.mode == "angle" else "施氏网 等面积"
        lines = [
            f"产状：{az:g}° ∠ {dip:g}°        约定：{conv} + {netname}",
            f"走向（两个）：{stroke:g}° 与 {(stroke + 180) % 360:g}°    弧顶方位："
            f"{(az if hemi == 'lower' else (az + 180) % 360):g}°",
            f"弧顶半径 r/R = tan(45°−β/2) = {r_arc:.4f}      极点半径 r/R = tan(β/2) = {r_pole:.4f}",
            f"极点方位 {p_az:.1f}°、伏角 {plunge:.1f}°；极点与倾向方位相差 180°（下半球约定）",
            f"提示：弧顶越靠近圆心 → 倾角越陡；β=0° 时大圆与基圆重合，β=90° 时退化为过圆心的直径",
        ]
        for i, s in enumerate(lines):
            ax.text(0, 0.90 - i * 0.21, s, fontsize=9.6, color="#1b3a5c",
                    family=matplotlib.rcParams["font.sans-serif"])

    def show(self):
        plt.show()


# ============================================================================
# 5. 教学图导出
# ============================================================================
def export_figures(outdir: str, dip_az=120.0, dip=45.0):
    os.makedirs(outdir, exist_ok=True)
    saved = []

    # ---------- 图1：平面投影图的四步生成过程 ----------
    fig = plt.figure(figsize=(14.0, 8.4))
    fig.suptitle("图1  赤平投影图是怎么得到的：从球面交线到平面大圆弧（下半球投影）",
                 fontsize=14.5, fontweight="bold", y=0.985)
    steps = [(0.02, "① 结构面过球心，与球面交出大圆"),
             (0.32, "② 自上极点（极射点）向大圆上的点连线"),
             (0.66, "③ 极射线与赤平面的交点即投影点"),
             (1.00, "④ 交点连成弧即赤平投影大圆")]
    for i, (prog, title) in enumerate(steps):
        ax = fig.add_axes([0.005 + 0.25 * i, 0.50, 0.245, 0.365], projection="3d")
        draw_3d(ax, dip_az, dip, "lower", "angle", show_rays=True,
                anim=prog, label=(i == 0), elev=24, azim=-52)
        ax.set_title(f"{title}\n结构面 {dip_az:g}°∠{dip:g}°", fontsize=10.5, pad=2)
        axi = fig.add_axes([0.055 + 0.25 * i, 0.05, 0.145, 0.25])
        draw_net(axi, "lower", "angle", lw=0.45, tick=False, color="#c3d0dc")
        draw_plane(axi, dip_az, dip, "lower", "angle", lw=2.2, frac=max(prog, 0.03))
        axi.set_title("赤平投影图（局部放样）" if i == 0 else "", fontsize=9, pad=2)
    fig.text(0.5, 0.445, "上排：三维投影球中的作图过程          下排：赤道平面上得到的赤平投影图",
             ha="center", fontsize=11, color="#334155")
    p = os.path.join(outdir, "图1_投影四步生成过程.png")
    fig.savefig(p, dpi=200, facecolor="w"); plt.close(fig); saved.append(p)

    # ---------- 图2：两种半球约定对比 ----------
    fig = plt.figure(figsize=(14.2, 5.4))
    fig.suptitle("图2  上半球投影与下半球投影：半径相同、整体相差 180°", fontsize=14, fontweight="bold")
    ax3d = fig.add_axes([0.015, 0.05, 0.29, 0.80], projection="3d")
    draw_3d(ax3d, dip_az, dip, "lower", "angle", elev=20, azim=-50)
    ax3d.set_title("三维：下半球投影（自上极点发射）", fontsize=11)
    aL = fig.add_axes([0.345, 0.05, 0.29, 0.80])
    draw_net(aL, "lower", "angle"); draw_plane(aL, dip_az, dip, "lower", "angle")
    aL.set_title(f"下半球投影：弧凸向倾向 {dip_az:g}°、极点在 {(dip_az + 180) % 360:g}°", fontsize=11)
    aU = fig.add_axes([0.665, 0.05, 0.29, 0.80])
    draw_net(aU, "upper", "angle"); draw_plane(aU, dip_az, dip, "upper", "angle")
    aU.set_title(f"上半球投影：弧凸向反倾向 {(dip_az + 180) % 360:g}°、极点在 {dip_az:g}°", fontsize=11)
    fig.text(0.5, 0.025, "两张平面图完全相同，只是整体旋转了 180° —— 这就是读文献时必须先确认半球约定的原因",
             ha="center", fontsize=10.5, color="#334155")
    p = os.path.join(outdir, "图2_上下半球约定对比.png")
    fig.savefig(p, dpi=200, facecolor="w"); plt.close(fig); saved.append(p)

    # ---------- 图3：等角网与等面积网 + 弧顶/极点几何关系 ----------
    dip3 = 30.0          # 特意取 β=30°（若取 β=45° 则 tan(45°−β/2)=tan(β/2) 恰好相等，看不出差别）
    fig, axes = plt.subplots(1, 2, figsize=(11.6, 6.1))
    fig.suptitle(f"图3  吴氏网（等角）与施氏网（等面积）；大圆弧顶与极点的几何关系（结构面 {dip_az:g}°∠{dip3:g}°）",
                 fontsize=13.5, fontweight="bold")
    for ax, md, nm, sub in [
            (axes[0], "angle", "吴氏网（等角投影）", "大圆投影后仍为圆弧，量角直观 → 判稳常用"),
            (axes[1], "area", "施氏网（等面积投影）", "大圆变形为一般曲线，但面积不变 → 极点密度图常用")]:
        draw_net(ax, "lower", md)
        d = draw_plane(ax, dip_az, dip3, "lower", md, show_pole=True, label=None)
        apex = d["xy"][len(d["xy"]) // 2]                     # 弧顶（离圆心最近的点）
        pole = d["pole"]
        ax.plot([0, apex[0]], [0, apex[1]], color="#b45309", lw=1.4)
        ax.plot([0, pole[0]], [0, pole[1]], color="#c2740a", lw=1.2, ls=":")
        ax.scatter(*apex, s=46, color="#8a3b00", edgecolor="w", lw=1.2, zorder=8)
        ax.scatter(*pole, s=46, color="#e08a00", edgecolor="w", lw=1.2, zorder=8)
        bb = dict(fc="white", ec="none", alpha=0.82, pad=1.2)
        ax.text(apex[0] + 0.05, apex[1] - 0.05, "弧顶", color="#8a3b00", fontsize=9.5,
                fontweight="bold", zorder=9, bbox=bb)
        ax.text(pole[0] + 0.05, pole[1] + 0.03, "极点", color="#b06a00", fontsize=9.5,
                fontweight="bold", zorder=9, bbox=bb)
        # 图注放在网下方，避免与网格混在一起
        ax.set_xlim(-1.28, 1.28); ax.set_ylim(-1.62, 1.16)
        ax.scatter(-1.07, -1.30, s=38, color="#8a3b00", edgecolor="w", lw=1.0, zorder=8)
        ax.text(-0.98, -1.33, f"弧顶：最陡倾斜线，r/R = tan(45°−β/2) = {np.tan((45-dip3/2)*DEG):.4f}")
        ax.scatter(-1.07, -1.47, s=38, color="#e08a00", edgecolor="w", lw=1.0, zorder=8)
        ax.text(-0.98, -1.50, f"极点：法线，r/R = tan(β/2) = {np.tan(dip3/2*DEG):.4f}"
                              f"（与弧顶方位相差 180°）")
        ax.set_title(f"{nm}\n{sub}", fontsize=10.5)
    fig.tight_layout(rect=(0, 0, 1, 0.92))
    p = os.path.join(outdir, "图3_两种投影网与极点几何.png")
    fig.savefig(p, dpi=200, facecolor="w"); plt.close(fig); saved.append(p)

    # ---------- 图4：边坡稳定性赤平投影判别（Markland 判据）----------
    cs_az, cs_dip = 110.0, 60.0
    ns_az, ns_dip = 110.0, 25.0
    J1 = (120.0, 45.0); J2 = (60.0, 50.0); phi = 30.0
    fig = plt.figure(figsize=(12.6, 7.4))
    fig.suptitle("图4  边坡稳定性赤平投影判别（下半球等角投影，Markland 运动学判据）",
                 fontsize=14, fontweight="bold")
    ax = fig.add_axes([0.03, 0.06, 0.56, 0.84])
    draw_net(ax, "lower", "angle")
    r_env, r_fric = daylight_envelope(ax, cs_az, cs_dip, phi)
    friction_circle(ax, phi)
    draw_plane(ax, cs_az, cs_dip, label=f"坡面 cs {cs_az:g}°∠{cs_dip:g}°", color="#d92d20", lw=3.4, label_pos=0.18)
    draw_plane(ax, ns_az, ns_dip, label=f"坡顶面 ns {ns_az:g}°∠{ns_dip:g}°", color="#0e7490", lw=2.0, label_pos=0.82)
    draw_plane(ax, J1[0], J1[1], label=f"J1 {J1[0]:g}°∠{J1[1]:g}°", color="#2563eb", lw=2.6, label_pos=0.30)
    draw_plane(ax, J2[0], J2[1], label=f"J2 {J2[0]:g}°∠{J2[1]:g}°", color="#7c3aed", lw=2.6, label_pos=0.70)
    M = intersection_line(J1[0], J1[1], J2[0], J2[1])
    mp = stereo(M[None, :], "lower", "angle")[0]
    ax.plot([0, mp[0]], [0, mp[1]], color="#111827", lw=1.1, ls=":", zorder=9)
    ax.scatter(*mp, s=70, color="#111827", edgecolor="w", lw=1.6, zorder=10, marker="D")
    ax.annotate("M 交棱线", mp, textcoords="offset points", xytext=(8, -12),
                fontsize=10, fontweight="bold", zorder=11)
    ax.set_title(f"坡面 {cs_az:g}°∠{cs_dip:g}°、摩擦角 φ={phi:g}°", fontsize=11)

    # 判别结果文字
    mpl_, maz = line_attitude(M)
    dd = lambda a, b: ang_diff(a, b)
    rows = [("平面滑动 J1", f"倾向差 {dd(J1[0], cs_az):.0f}°，倾角 {J1[1]:g}°",
             dd(J1[0], cs_az) <= 20 and phi < J1[1] < cs_dip),
            ("平面滑动 J2", f"倾向差 {dd(J2[0], cs_az):.0f}°，倾角 {J2[1]:g}°",
             dd(J2[0], cs_az) <= 20 and phi < J2[1] < cs_dip),
            ("楔形滑动 M", f"倾伏向 {maz:.0f}°，倾伏角 {mpl_:.1f}°",
             dd(maz, cs_az) <= 20 and phi < mpl_ < cs_dip),
            ("倾倒 J1", f"倾向与反坡向({(cs_az + 180) % 360:g}°)差 "
                        f"{dd(J1[0], (cs_az + 180) % 360):.0f}°，极点伏角 {90 - J1[1]:.0f}°",
             dd(J1[0], (cs_az + 180) % 360) <= 20 and 90 - J1[1] <= phi and cs_dip >= 30),
            ("倾倒 J2", f"倾向与反坡向差 {dd(J2[0], (cs_az + 180) % 360):.0f}°，"
                        f"极点伏角 {90 - J2[1]:.0f}°",
             dd(J2[0], (cs_az + 180) % 360) <= 20 and 90 - J2[1] <= phi and cs_dip >= 30)]
    axt = fig.add_axes([0.62, 0.06, 0.36, 0.80]); axt.axis("off")
    axt.text(0, 0.99, "判据校核（几何/运动学，不含安全系数）", fontsize=11.5, fontweight="bold", color="#16212e")
    y = 0.90
    for name, info, hit in rows:
        c = "#b42318" if hit else "#067647"
        axt.text(0, y, f"{'■ 命中' if hit else '□ 不满足'}", color=c, fontsize=10.5, fontweight="bold")
        axt.text(0.20, y, name, fontsize=10.5, color="#16212e", fontweight="bold")
        axt.text(0.20, y - 0.048, info, fontsize=9.5, color="#5c6b7d")
        y -= 0.115
    axt.text(0, 0.02, "判别区以摩擦圆为界（圆内判弧、圆外判点）：\n"
                      "粗红弧=坡面 cs；青弧=坡顶面 ns；蓝/紫弧=两组结构面；\n"
                      "橙色区（圆内、坡向±20°）=滑动出露区，判读对象为“大圆弧顶”；\n"
                      "粉色区（圆外、坡向±20°）=倾倒区，判读对象为“极点”；\n"
                      "紫色圆=摩擦圆（半径 r/R = tan(45°−φ/2)）；◆=两组结构面交棱线 M。",
             fontsize=9.0, color="#334155", linespacing=1.55, va="bottom")
    p = os.path.join(outdir, "图4_边坡稳定性赤平投影判别.png")
    fig.savefig(p, dpi=200, facecolor="w"); plt.close(fig); saved.append(p)

    print("已导出教学用图：")
    for s in saved:
        print("   " + s)
    return saved


# ============================================================================
# 6. 入口
# ============================================================================
def main():
    ap = argparse.ArgumentParser(description="赤平极射投影法 教学演示工具")
    ap.add_argument("--export", action="store_true", help="导出教学图集到 figures/")
    ap.add_argument("--also-show", action="store_true", help="导出后仍打开交互窗口")
    ap.add_argument("--outdir", default=None, help="图集输出目录（默认 ./figures）")
    ap.add_argument("--dip-az", type=float, default=120.0, help="演示用结构面倾向（默认 120）")
    ap.add_argument("--dip", type=float, default=45.0, help="演示用结构面倾角（默认 45）")
    args = ap.parse_args()

    setup_chinese_font()
    outdir = args.outdir or os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                         "..", "figures")
    do_gui = (not args.export) or args.also_show
    if args.export:
        export_figures(os.path.abspath(outdir), args.dip_az, args.dip)
    if do_gui:
        if not os.environ.get("DISPLAY") and sys.platform.startswith("linux"):
            print("[提示] 未检测到图形界面（DISPLAY），请改用 --export 导出图片。")
        StereonetApp(args.dip_az, args.dip).show()


if __name__ == "__main__":
    main()

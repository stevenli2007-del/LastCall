/**
 * 临期宝 LastCall 设计 token
 *
 * 唯一来源：仓库根 index.html 交互原型（:root 变量与各组件样式）。
 * 任何界面颜色、圆角、间距、字号都必须从这里取，禁止在组件里硬编码色值。
 *
 * 对应 docs/DESIGN_SYSTEM.md 与 Roadmap T0.5。
 */

// ---------------------------------------------------------------------------
// 颜色
// ---------------------------------------------------------------------------

export const palette = {
  // 基础
  ink: '#17221e',
  muted: '#78847e',
  paper: '#f5f7f2',
  white: '#ffffff',
  line: '#e7ebe5',

  // 品牌
  green: '#187653',
  greenSoft: '#e7f2eb',
  greenActive: '#e8f1e9',
  greenHover: '#f2f5ef',
  greenIcon: '#edf5ee',
  lime: '#d6ef72',

  // 语义
  orange: '#e9a449',
  red: '#d76c59',

  // 表面
  surface: '#ffffff',
  surfaceAlt: '#fbfcf9',
  surfaceDark: '#193d30',
  onDark: '#ffffff',
  onDarkSub: '#c6d6cf',
  onDarkAccent: '#c7e680',

  // 进度条
  track: '#edf1ec',
  fill: '#79ae83',

  // 聚焦
  focusBorder: '#62a477',
  focusRing: '#e9f5eb',
} as const;

/** 商品新鲜度状态色：正常 / 临期 / 过期。状态本身按门店时区动态派生，见 DATABASE.md */
export const statusColors = {
  normal: { bg: '#e9f5ed', fg: '#34764c', border: '#d6e7d8' },
  near: { bg: '#fff2dd', fg: '#a46a1e', border: '#f5dfb8' },
  expired: { bg: '#ffebe8', fg: '#b84f3d', border: '#f2d0c9' },
} as const;

export type FreshnessStatus = keyof typeof statusColors;

export const statusLabel: Record<FreshnessStatus, string> = {
  normal: '正常',
  near: '临期中',
  expired: '已过期',
};

// ---------------------------------------------------------------------------
// 字号（RN 无单位）
// ---------------------------------------------------------------------------

export const fontSize = {
  display: 30, // 页面主标题 h1
  title: 19, // 容器详情标题
  section: 15, // 区块标题
  card: 14, // 卡片标题
  body: 13, // 正文
  bodySm: 12, // 次级正文 / 按钮
  meta: 11, // 说明文字
  micro: 10, // 标签、脚注
  badge: 9, // 状态徽章
} as const;

/** 原型使用了较紧的字重分级，RN 上按最接近的系统字重映射 */
export const fontWeight = {
  regular: '400',
  medium: '500',
  semibold: '600',
  bold: '700',
} as const;

// ---------------------------------------------------------------------------
// 圆角
// ---------------------------------------------------------------------------

export const radius = {
  sm: 9, // 输入框、小按钮
  md: 11, // 主按钮、图标格
  lg: 15, // 统计卡、容器格位
  xl: 17, // 卡片
  pill: 999, // 徽章
} as const;

// ---------------------------------------------------------------------------
// 间距
// ---------------------------------------------------------------------------

export const space = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 22,
  xxl: 33,
} as const;

// ---------------------------------------------------------------------------
// 阴影
// ---------------------------------------------------------------------------

export const shadow = {
  card: {
    shadowColor: '#203426',
    shadowOpacity: 0.05,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 3 },
    elevation: 2,
  },
  raised: {
    shadowColor: '#213a2b',
    shadowOpacity: 0.12,
    shadowRadius: 24,
    shadowOffset: { width: 0, height: 8 },
    elevation: 6,
  },
} as const;

// ---------------------------------------------------------------------------
// 布局
// ---------------------------------------------------------------------------

export const layout = {
  /** 页面左右内边距 */
  screenPadding: 18,
  /** 卡片间间距 */
  cardGap: 14,
  /** 列表行最小可点高度（无障碍） */
  minTouchTarget: 44,
} as const;

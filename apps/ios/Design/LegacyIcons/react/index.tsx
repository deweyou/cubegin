import type { SVGProps } from 'react';

export type CubeginAnimatedIconTrigger = 'auto' | 'hover' | 'loop' | 'manual';

export interface CubeginAnimatedIconProps extends Omit<
  SVGProps<SVGSVGElement>,
  'height' | 'viewBox' | 'width'
> {
  readonly isPlaying?: boolean;
  readonly loading?: boolean;
  readonly size?: number | string;
  readonly title?: string;
  readonly trigger?: CubeginAnimatedIconTrigger;
}

export const CubeginAnimatedIcon = ({
  className,
  isPlaying,
  loading = false,
  size = 100,
  style,
  title,
  trigger = 'loop',
  ...svgProps
}: CubeginAnimatedIconProps) => {
  const accessibleTitle = title ?? 'Cubegin animated mark';
  const classNames = ['cubegin-animated-icon', className].filter(Boolean).join(' ');

  return (
    <svg
      {...svgProps}
      aria-label={svgProps['aria-label'] ?? accessibleTitle}
      className={classNames}
      data-loading={String(loading)}
      data-playing={String(isPlaying ?? trigger !== 'manual')}
      data-trigger={trigger}
      height={size}
      role={svgProps.role ?? 'img'}
      style={style}
      viewBox="16 16 68 68"
      width={size}
      xmlns="http://www.w3.org/2000/svg"
    >
      <title>{accessibleTitle}</title>
      <style>{CUBEGIN_ANIMATED_ICON_STYLES}</style>
      <rect x="22" y="22" width="28" height="28" rx="7" fill="#ffc62e" />
      <rect x="50" y="22" width="28" height="28" rx="7" fill="#ec3b3b" />
      <rect x="22" y="50" width="28" height="28" rx="7" fill="#1eb877" />
      <rect
        className={`cubegin-animated-icon__piece${
          loading ? ' cubegin-animated-icon__loading-piece' : ''
        }`}
        x="50"
        y="50"
        width="28"
        height="28"
        rx="8"
        fill="#2f7ce0"
      />
    </svg>
  );
};

const CUBEGIN_ANIMATED_ICON_STYLES = `
.cubegin-animated-icon__piece{transform-box:fill-box;transform-origin:center}
.cubegin-animated-icon .cubegin-animated-icon__piece{transform:rotate(18deg)}
.cubegin-animated-icon[data-loading="true"] .cubegin-animated-icon__loading-piece{animation:cubegin-beginspin 1.6s cubic-bezier(.16,.67,.27,1) infinite}
@media (prefers-reduced-motion:no-preference){
.cubegin-animated-icon[data-trigger="auto"] .cubegin-animated-icon__piece{animation:cubegin-beginspin 1.1s cubic-bezier(.16,.67,.27,1) forwards}
.cubegin-animated-icon[data-trigger="loop"] .cubegin-animated-icon__piece{animation:cubegin-beginspin 1.6s cubic-bezier(.16,.67,.27,1) infinite}
.cubegin-animated-icon[data-trigger="hover"]:hover .cubegin-animated-icon__piece{animation:cubegin-beginspin 1.1s cubic-bezier(.16,.67,.27,1) forwards}
.cubegin-animated-icon[data-trigger="manual"][data-playing="true"] .cubegin-animated-icon__piece{animation:cubegin-beginspin 1.1s cubic-bezier(.16,.67,.27,1) forwards}
}
@keyframes cubegin-beginspin{0%{transform:rotate(0deg)}100%{transform:rotate(378deg)}}
`;

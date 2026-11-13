import { describe, expect, it } from 'vitest';
import { BRAND_ICON_SVGS } from './brand/index.js';
import { CubeginAnimatedIcon } from './react/index.js';

describe('Cubegin icon asset metadata', () => {
  it('exports imported brand SVG assets as strings', () => {
    expect(Object.keys(BRAND_ICON_SVGS).sort()).toEqual([
      'appicon-dark',
      'appicon-gradient',
      'appicon-white',
      'cubegin-lockup',
      'cubegin-lockup-dark',
      'cubegin-mark',
      'cubegin-wordmark',
      'cubegin-wordmark-dark',
    ]);
    expect(BRAND_ICON_SVGS['cubegin-mark']).toContain('<svg');
    expect(BRAND_ICON_SVGS['cubegin-mark']).toContain('aria-label="cubegin"');
  });

  it('exports the animated React icon component', () => {
    const hoverIcon = CubeginAnimatedIcon({ trigger: 'hover' });
    const loopIcon = CubeginAnimatedIcon({ trigger: 'loop' });
    const loadingIcon = CubeginAnimatedIcon({ loading: true, trigger: 'loop' });

    expect(hoverIcon.props['data-trigger']).toBe('hover');
    expect(loopIcon.props['data-trigger']).toBe('loop');
    expect(loadingIcon.props['data-loading']).toBe('true');
    expect(loopIcon.props.children).toContainEqual(
      expect.objectContaining({
        props: expect.objectContaining({
          children: expect.stringContaining(
            'animation:cubegin-beginspin 1.6s cubic-bezier(.16,.67,.27,1) infinite',
          ),
        }),
      }),
    );
    expect(loadingIcon.props.children).toContainEqual(
      expect.objectContaining({
        props: expect.objectContaining({
          className: 'cubegin-animated-icon__piece cubegin-animated-icon__loading-piece',
        }),
      }),
    );
  });
});

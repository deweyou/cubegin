import { describe, expect, it } from 'vitest';
import { EVENT_IDS } from '@cubegin/scramble-puzzle';
import * as eventIcons from './index.js';
import { EVENT_ICON_333_SVG, EVENT_ICON_FTO_SVG, EVENT_ICON_SVGS } from './index.js';

describe('event icon metadata', () => {
  it('contains one icon for every supported event', () => {
    expect(new Set(Object.keys(EVENT_ICON_SVGS))).toEqual(new Set(EVENT_IDS));
  });

  it('uses platform-agnostic single-color SVG output', () => {
    for (const eventId of EVENT_IDS) {
      const iconSvg = EVENT_ICON_SVGS[eventId];

      expect(iconSvg).toContain('<svg');
      expect(iconSvg).toContain('viewBox="0 0 24 24"');
      expect(iconSvg).toContain('fill="currentColor"');
      expect(iconSvg).not.toMatch(/#[0-9a-f]{3,8}/i);
    }
  });

  it('uses masks instead of visible white artwork for cutouts', () => {
    for (const eventId of EVENT_IDS) {
      const iconSvg = EVENT_ICON_SVGS[eventId];
      const maskCount = iconSvg.match(/<mask /g)?.length ?? 0;
      const whiteFillCount = iconSvg.match(/fill="white"/g)?.length ?? 0;

      expect(iconSvg).not.toContain('stroke="white"');
      expect(whiteFillCount).toBe(maskCount);
    }
  });

  it('renders FTO as rounded triangular stickers', () => {
    expect(EVENT_ICON_FTO_SVG.match(/<path/g)?.length).toBe(36);
    expect(EVENT_ICON_FTO_SVG.match(/Q/g)?.length).toBe(108);
    expect(EVENT_ICON_FTO_SVG).not.toContain('<mask');
    expect(EVENT_ICON_FTO_SVG).not.toContain('stroke-width');
    expect(EVENT_ICON_FTO_SVG).not.toContain('<text');
  });

  it('exports static SVG strings without a public generator API', () => {
    const exportedMembers = eventIcons as Record<string, unknown>;
    const individualSvgExports = Object.entries(exportedMembers).filter(
      ([exportName]) =>
        exportName.startsWith('EVENT_ICON_') &&
        exportName.endsWith('_SVG') &&
        exportName !== 'EVENT_ICON_SVGS',
    );

    expect(EVENT_ICON_333_SVG).toBe(EVENT_ICON_SVGS['333']);
    expect(individualSvgExports).toHaveLength(EVENT_IDS.length);
    expect(exportedMembers.EVENT_ICON_INFO).toBeUndefined();
    expect(exportedMembers.EVENT_ICON_IDS).toBeUndefined();
    expect(exportedMembers.getEventIcon).toBeUndefined();
    expect(exportedMembers.getEventIconSvg).toBeUndefined();
  });
});

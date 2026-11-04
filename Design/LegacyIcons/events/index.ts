type EventIconId =
  | '333'
  | '222'
  | '444'
  | '555'
  | '666'
  | '777'
  | '333bld'
  | '333fm'
  | '333oh'
  | 'clock'
  | 'minx'
  | 'pyram'
  | 'skewb'
  | 'sq1'
  | '444bld'
  | '555bld'
  | '333mbld'
  | 'fto';
type SvgShape = string;
type SvgPoint = readonly [number, number];
type SvgTriangle = readonly [SvgPoint, SvgPoint, SvgPoint];
type PolygonCornerCommand =
  | {
      readonly end: SvgPoint;
      readonly isRounded: false;
      readonly start: SvgPoint;
    }
  | {
      readonly end: SvgPoint;
      readonly isRounded: true;
      readonly point: SvgPoint;
      readonly start: SvgPoint;
    };

const VIEW_BOX = '0 0 24 24' as const;

interface SvgBounds {
  readonly height: number;
  readonly width: number;
  readonly x: number;
  readonly y: number;
}

const svg = (body: readonly SvgShape[], bounds?: SvgBounds): string => {
  return rawSvg(applyBounds(body, bounds));
};

const svgWithCutouts = ({
  body,
  bounds,
  cutouts,
  maskId,
}: {
  readonly body: readonly SvgShape[];
  readonly bounds?: SvgBounds;
  readonly cutouts: readonly SvgShape[];
  readonly maskId: string;
}): string => {
  const mask = `<mask id="${maskId}" maskUnits="userSpaceOnUse" x="-4" y="-4" width="32" height="32"><rect x="-4" y="-4" width="32" height="32" fill="white"></rect>${applyBounds(cutouts, bounds)}</mask>`;

  return rawSvg(`<defs>${mask}</defs><g mask="url(#${maskId})">${applyBounds(body, bounds)}</g>`);
};

const rawSvg = (content: string): string => {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VIEW_BOX}" fill="currentColor" role="img">${content}</svg>`;
};

const applyBounds = (body: readonly SvgShape[], bounds?: SvgBounds): string => {
  return bounds ? `<g transform="${fitToViewBox(bounds)}">${body.join('')}</g>` : body.join('');
};

const fitToViewBox = ({ height, width, x, y }: SvgBounds): string => {
  const scaleX = 24 / width;
  const scaleY = 24 / height;

  return `matrix(${formatTransformNumber(scaleX)} 0 0 ${formatTransformNumber(scaleY)} ${formatTransformNumber(-x * scaleX)} ${formatTransformNumber(-y * scaleY)})`;
};

const path = (d: string): SvgShape => `<path d="${d}"></path>`;

const polygonPath = (points: readonly SvgPoint[]): SvgShape => {
  return path(`${points.map(([x, y], index) => `${index === 0 ? 'M' : 'L'}${x} ${y}`).join(' ')}Z`);
};

const roundedPolygonPath = ({
  points,
  radius,
  roundedIndexes,
}: {
  readonly points: readonly SvgPoint[];
  readonly radius: number;
  readonly roundedIndexes: ReadonlySet<number>;
}): SvgShape => {
  const commands: PolygonCornerCommand[] = points.map((point, index) => {
    if (!roundedIndexes.has(index)) {
      return { end: point, isRounded: false, start: point };
    }

    const previous = points[(index - 1 + points.length) % points.length];
    const next = points[(index + 1) % points.length];
    const start = pointOnSegment(point, previous, radius);
    const end = pointOnSegment(point, next, radius);

    return { end, isRounded: true, point, start };
  });
  const firstCommand = commands[0];

  if (!firstCommand) {
    return path('');
  }

  const remainingCommands = commands.slice(1);
  const parts = [`M${formatPoint(firstCommand.start)}`];

  if (firstCommand.isRounded) {
    parts.push(`Q${formatPoint(firstCommand.point)} ${formatPoint(firstCommand.end)}`);
  }

  for (const command of remainingCommands) {
    parts.push(`L${formatPoint(command.start)}`);

    if (command.isRounded) {
      parts.push(`Q${formatPoint(command.point)} ${formatPoint(command.end)}`);
    }
  }

  parts.push('Z');

  return path(parts.join(' '));
};

const pointOnSegment = (from: SvgPoint, to: SvgPoint, distance: number): SvgPoint => {
  const [fromX, fromY] = from;
  const [toX, toY] = to;
  const deltaX = toX - fromX;
  const deltaY = toY - fromY;
  const length = Math.hypot(deltaX, deltaY);
  const offset = Math.min(distance, length / 2) / length;

  return [round(fromX + deltaX * offset), round(fromY + deltaY * offset)];
};

const formatPoint = ([x, y]: SvgPoint): string => `${x} ${y}`;

const cutoutPath = (d: string, attributes = ''): SvgShape =>
  `<path d="${d}" fill="black"${attributes}></path>`;

const cutoutStroke = (d: string, strokeWidth: number, attributes = ''): SvgShape =>
  `<path d="${d}" fill="none" stroke="black" stroke-width="${strokeWidth}"${attributes}></path>`;

const roundedCellPath = ({
  x,
  y,
  width,
  height,
  radius,
  roundBottomLeft,
  roundBottomRight,
  roundTopLeft,
  roundTopRight,
}: {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
  readonly radius: number;
  readonly roundBottomLeft: boolean;
  readonly roundBottomRight: boolean;
  readonly roundTopLeft: boolean;
  readonly roundTopRight: boolean;
}): SvgShape => {
  const right = round(x + width);
  const bottom = round(y + height);
  const left = round(x);
  const top = round(y);
  const cornerRadius = round(Math.min(radius, width / 2, height / 2));
  const topLeft = roundTopLeft ? cornerRadius : 0;
  const topRight = roundTopRight ? cornerRadius : 0;
  const bottomRight = roundBottomRight ? cornerRadius : 0;
  const bottomLeft = roundBottomLeft ? cornerRadius : 0;

  return path(
    [
      `M${round(left + topLeft)} ${top}`,
      `H${round(right - topRight)}`,
      topRight ? `Q${right} ${top} ${right} ${round(top + topRight)}` : `L${right} ${top}`,
      `V${round(bottom - bottomRight)}`,
      bottomRight
        ? `Q${right} ${bottom} ${round(right - bottomRight)} ${bottom}`
        : `L${right} ${bottom}`,
      `H${round(left + bottomLeft)}`,
      bottomLeft
        ? `Q${left} ${bottom} ${left} ${round(bottom - bottomLeft)}`
        : `L${left} ${bottom}`,
      `V${round(top + topLeft)}`,
      topLeft ? `Q${left} ${top} ${round(left + topLeft)} ${top}` : `L${left} ${top}`,
      'Z',
    ].join(' '),
  );
};

const round = (value: number): number => {
  return Number(value.toFixed(3));
};

const formatTransformNumber = (value: number): string => {
  const formatted = Number(value.toFixed(6));

  return Object.is(formatted, -0) ? '0' : String(formatted);
};

const cubeGridShapes = (order: number): readonly SvgShape[] => {
  const gap = 0.8;
  const outerBoost = order >= 6 ? (order - 5) * 0.18 : 0;
  const innerSize = (24 - gap * (order - 1) - outerBoost * 2) / order;
  const cells: SvgShape[] = [];

  for (let row = 0; row < order; row += 1) {
    for (let column = 0; column < order; column += 1) {
      const isTop = row === 0;
      const isBottom = row === order - 1;
      const isLeft = column === 0;
      const isRight = column === order - 1;
      const x = cellOffset(column, order, innerSize, outerBoost, gap);
      const y = cellOffset(row, order, innerSize, outerBoost, gap);
      const width = innerSize + (isLeft || isRight ? outerBoost : 0);
      const height = innerSize + (isTop || isBottom ? outerBoost : 0);
      const cornerRadius =
        order === 2 ? 3 : order === 3 ? 2 : Math.min(Math.min(width, height) * 0.24, 1.05);

      cells.push(
        roundedCellPath({
          x: round(x),
          y: round(y),
          width: round(width),
          height: round(height),
          radius: cornerRadius,
          roundBottomLeft: !isBottom && !isLeft,
          roundBottomRight: !isBottom && !isRight,
          roundTopLeft: !isTop && !isLeft,
          roundTopRight: !isTop && !isRight,
        }),
      );
    }
  }

  return cells;
};

const cubeGridIcon = (order: number): string => {
  return svg(cubeGridShapes(order));
};

const cellOffset = (
  index: number,
  order: number,
  innerSize: number,
  outerBoost: number,
  gap: number,
): number => {
  let offset = 0;

  for (let previous = 0; previous < index; previous += 1) {
    const isOuter = previous === 0 || previous === order - 1;
    offset += innerSize + (isOuter ? outerBoost : 0) + gap;
  }

  return offset;
};

const blindfoldIcon = (order: 3 | 4 | 5, marker?: string): string => {
  const maskPath =
    'M0 15.1C0 11.4 4.7 9.4 12 9.4s12 2 12 5.7C24 18.8 20.4 24 15.5 24c-1.7 0-2.6-1.3-3.5-1.3S10.2 24 8.5 24C3.6 24 0 18.8 0 15.1Z';
  const cutouts = [
    cutoutStroke(maskPath, 1.2, ' stroke-linejoin="round"'),
    marker ? cutoutPath(MULTI_BLIND_MARKER_PATH) : '',
  ];

  return svgWithCutouts({
    body: [...cubeGridShapes(order), path(maskPath)],
    cutouts,
    maskId: `event-icon-bld-${order}${marker ? '-multi' : ''}`,
  });
};

const MULTI_BLIND_MARKER_PATH =
  'M7.8 15.4h.92l.83.95.83-.95h.92l-1.25 1.35 1.3 1.45h-.95l-.85-.98-.85.98h-.95l1.3-1.45ZM12.2 14.6h1l1.65 2.45V14.6h1.05v4.2h-1l-1.65-2.45v2.45H12.2Z';

const fewestMovesIcon = (): string => {
  const penBodyPath = 'M10.76 21.94 18.76 3.24 22.04 4.76 14.04 23.46Z';
  const penTipPath = 'M18.76 3.24 21.82 0.69 22.04 4.76Z';
  const penTipSeparatorPath = 'M18.76 3.24 22.04 4.76';
  const penCapSeparatorPath = 'M10.76 21.94 14.04 23.46';

  return svgWithCutouts({
    body: [...cubeGridShapes(3), path(penBodyPath), path(penTipPath)],
    cutouts: [
      cutoutStroke(penBodyPath, 0.8, ' stroke-linejoin="round"'),
      cutoutStroke(penTipPath, 0.8, ' stroke-linejoin="round"'),
      cutoutStroke(penTipSeparatorPath, 0.45, ' stroke-linecap="round"'),
      cutoutStroke(penCapSeparatorPath, 0.45, ' stroke-linecap="round"'),
    ],
    maskId: 'event-icon-fewest-moves',
  });
};

const oneHandedIcon = (): string => {
  const handPath =
    'M849.92 489.6c3.92 107.86-15.12 215.38-55.78 314.83-23.86 50.51-66.64 110.88-134.4 110.88h-210.9a97.091 97.091 0 0 1-46.37-23.63A435.234 435.234 0 0 1 290.92 733.2c-85.57-181.66-112-239.01-112.34-239.46-10.42-22.74-3.58-49.84 16.24-64.51 8.74-5.49 19.26-7.06 29.01-4.26 10.86 3.25 19.82 10.98 24.98 21.17 0 0.22 0.22 0.45 0.45 0.45l65.86 121.3c5.26 20.61 24.3 34.5 45.02 32.59 19.26-8.85 29.68-30.58 24.98-51.86V198.4c0-23.97 18.93-43.46 42.22-43.46s42.11 19.49 42.11 43.46v291.2c-0.22 7.95 3.7 15.57 10.42 19.6 6.72 4.14 15.01 4.14 21.73 0 6.61-4.03 10.64-11.65 10.3-19.6v-336c0-15.46 8.06-29.79 21.06-37.52 13.1-7.84 29.23-7.84 42.22 0 13.1 7.73 21.17 22.06 21.17 37.52v336c-0.34 8.06 3.58 15.57 10.3 19.71a21.04 21.04 0 0 0 21.73 0c6.72-4.14 10.64-11.65 10.3-19.71V198.4c0-15.46 8.06-29.79 21.17-37.52a41.132 41.132 0 0 1 42.11 0c13.1 7.73 21.17 22.06 21.17 37.52v336c0 7.84 4.03 15.01 10.64 18.93 6.5 3.92 14.56 3.92 21.17 0 6.61-3.92 10.64-11.09 10.64-18.93V332.8c0-15.46 7.95-29.79 21.06-37.52s29.12-7.73 42.22 0 21.06 22.06 21.06 37.52v156.8z m-42-246.4c-14.9 0-29.57 4.14-42.34 12.1v-56.9c0.56-48.72-37.41-88.82-84.78-89.6-16.8 0-33.15 5.38-46.82 15.23C622.89 88.3 590.64 64 554.13 64c-36.4 0-68.77 24.3-79.97 60.03a80.113 80.113 0 0 0-47.04-15.23c-47.26 0.9-85.01 40.99-84.45 89.6v330.4l-56.78-104.61c-10.53-20.83-28.9-36.29-50.74-42.67-21-6.17-43.65-2.9-62.05 8.96-39.09 26.99-52.98 79.3-32.59 122.86 1.46 2.8 28.34 61.26 112.67 239.68a468.072 468.072 0 0 0 129.36 178.53A118.516 118.516 0 0 0 448.51 960h211.23c36.29-0.11 71.57-13.1 99.57-36.85 31.02-26.99 55.78-60.7 72.58-98.78a805.431 805.431 0 0 0 60.48-334.88V332.8c0.67-48.72-37.08-88.7-84.45-89.6z';
  const handFillPath = handPath.split(' m-42-246.4')[0];
  const transform = 'matrix(-0.0202 0 0 0.0282 18.03 -1.805)';

  return svgWithCutouts({
    body: [...cubeGridShapes(3), `<path d="${handFillPath}" transform="${transform}"></path>`],
    cutouts: [cutoutPath(handPath, ` transform="${transform}"`)],
    maskId: 'event-icon-one-handed',
  });
};

const CLOCK_SOURCE_BOUNDS = {
  height: 895.861,
  width: 896.056,
  x: 63.972,
  y: 64.07,
} as const satisfies SvgBounds;

const CLOCK_DIAL_CENTERS = [
  [266.4, 266.4],
  [512, 266.4],
  [757.6, 266.4],
  [266.4, 512],
  [512, 512],
  [757.6, 512],
  [266.4, 757.64],
  [512, 757.64],
  [757.6, 757.64],
] as const satisfies readonly SvgPoint[];

const clockHandPath = ([centerX, centerY]: SvgPoint): SvgShape => {
  const left = round(centerX - 15);
  const leftInner = round(centerX - 7);
  const leftOuter = round(centerX - 14);
  const right = round(centerX + 15);
  const rightInner = round(centerX + 7);
  const rightOuter = round(centerX + 14);
  const top = round(centerY - 64);
  const upper = round(centerY - 39);
  const lower = round(centerY - 14);
  const bottom = round(centerY + 22);
  const roundedCenterY = round(centerY);
  const bottomShoulder = round(centerY + 13);

  return path(
    [
      `M${centerX} ${top}`,
      `C${rightInner} ${upper} ${rightOuter} ${lower} ${right} ${roundedCenterY}`,
      `C${right} ${bottomShoulder} ${round(centerX + 8)} ${bottom} ${centerX} ${bottom}`,
      `C${round(centerX - 8)} ${bottom} ${left} ${bottomShoulder} ${left} ${roundedCenterY}`,
      `C${leftOuter} ${lower} ${leftInner} ${upper} ${centerX} ${top}`,
      'Z',
    ].join(' '),
  );
};

const clockIcon = (): string =>
  svg(
    [
      path(
        'M880 767.56c50.077-71.314 80.028-159.929 80.028-255.54s-29.951-184.226-80.982-256.975c-4.061-58.601-51.596-106.094-111.203-111.015-71.728-50.047-160.292-79.96-255.843-79.96s-184.115 29.913-256.838 80.886c-58.612 3.995-106.146 51.488-111.132 111.077-50.107 71.762-80.058 160.377-80.058 255.987s29.951 184.226 80.982 256.975c4.078 58.572 51.585 106.038 111.162 110.975 71.729 50.047 160.293 79.961 255.844 79.961s184.115-29.913 256.838-80.886c58.617-3.974 106.165-51.453 111.172-111.036zM757.56 184.8c0.012-0 0.026-0 0.040-0 45.066 0 81.6 36.534 81.6 81.6s-36.534 81.6-81.6 81.6c-45.066 0-81.6-36.534-81.6-81.6 0-0.014 0-0.028 0-0.042 0.023-45.033 36.525-81.535 81.558-81.558zM676 512c-0-45.066 36.534-81.6 81.6-81.6s81.6 36.534 81.6 81.6c0 45.066-36.534 81.6-81.6 81.6s-81.6-36.534-81.6-81.6zM676 757.64c-0-45.066 36.534-81.6 81.6-81.6s81.6 36.534 81.6 81.6c0 45.066-36.534 81.6-81.6 81.6-45.052 0-81.577-36.511-81.6-81.558zM266.4 839.28c-45.066 0-81.6-36.534-81.6-81.6s36.534-81.6 81.6-81.6c45.066 0 81.6 36.534 81.6 81.6s-36.534 81.6-81.6 81.6zM348 266.36c0 0.012 0 0.026 0 0.040 0 45.066-36.534 81.6-81.6 81.6s-81.6-36.534-81.6-81.6c0-45.066 36.534-81.6 81.6-81.6 45.052 0 81.577 36.511 81.6 81.558zM348 512c0 45.066-36.534 81.6-81.6 81.6s-81.6-36.534-81.6-81.6c0-45.066 36.534-81.6 81.6-81.6s81.6 36.534 81.6 81.6zM512 839.24c-45.066 0-81.6-36.534-81.6-81.6s36.534-81.6 81.6-81.6c45.066 0 81.6 36.534 81.6 81.6 0 0.012 0 0.026 0 0.040 0 45.066-36.534 81.6-81.6 81.6zM512 593.6c-45.066 0-81.6-36.534-81.6-81.6s36.534-81.6 81.6-81.6c45.066 0 81.6 36.534 81.6 81.6s-36.534 81.6-81.6 81.6zM512 348c-45.066 0-81.6-36.534-81.6-81.6s36.534-81.6 81.6-81.6c45.066 0 81.6 36.534 81.6 81.6s-36.534 81.6-81.6 81.6z',
      ),
      ...CLOCK_DIAL_CENTERS.map(clockHandPath),
    ],
    CLOCK_SOURCE_BOUNDS,
  );

const MEGAMINX_CORNER_RADIUS = 0.6;

const megaminxIcon = (): string =>
  svg([
    roundedPolygonPath({
      points: [
        [17.073, 3.877],
        [12, 0],
        [6.909, 3.891],
        [11.982, 7.769],
      ],
      radius: MEGAMINX_CORNER_RADIUS,
      roundedIndexes: new Set([3]),
    }),
    roundedPolygonPath({
      points: [
        [11.294, 8.294],
        [6.221, 4.417],
        [5.749, 4.777],
        [7.687, 11.051],
      ],
      radius: MEGAMINX_CORNER_RADIUS,
      roundedIndexes: new Set([0, 3]),
    }),
    polygonPath([
      [0, 9.171],
      [1.938, 15.445],
      [7.008, 11.57],
      [5.071, 5.296],
    ]),
    roundedPolygonPath({
      points: [
        [16.013, 11.901],
        [11.982, 8.82],
        [7.949, 11.901],
        [9.486, 16.875],
        [14.477, 16.875],
      ],
      radius: MEGAMINX_CORNER_RADIUS,
      roundedIndexes: new Set([0, 1, 2, 3, 4]),
    }),
    roundedPolygonPath({
      points: [
        [11.686, 24],
        [12.277, 24],
        [14.213, 17.733],
        [9.751, 17.733],
      ],
      radius: MEGAMINX_CORNER_RADIUS,
      roundedIndexes: new Set([2, 3]),
    }),
    roundedPolygonPath({
      points: [
        [7.271, 12.421],
        [2.2, 16.296],
        [2.38, 16.875],
        [8.647, 16.875],
      ],
      radius: MEGAMINX_CORNER_RADIUS,
      roundedIndexes: new Set([0, 3]),
    }),
    polygonPath([
      [4.58, 24],
      [10.847, 24],
      [8.911, 17.733],
      [2.644, 17.733],
    ]),
    roundedPolygonPath({
      points: [
        [18.221, 4.754],
        [17.761, 4.403],
        [12.67, 8.294],
        [16.277, 11.051],
      ],
      radius: MEGAMINX_CORNER_RADIUS,
      roundedIndexes: new Set([2, 3]),
    }),
    roundedPolygonPath({
      points: [
        [21.793, 16.318],
        [16.692, 12.421],
        [15.316, 16.875],
        [21.62, 16.875],
      ],
      radius: MEGAMINX_CORNER_RADIUS,
      roundedIndexes: new Set([1, 2]),
    }),
    polygonPath([
      [13.116, 24],
      [19.42, 24],
      [21.356, 17.733],
      [15.052, 17.733],
    ]),
    polygonPath([
      [24, 9.171],
      [18.9, 5.274],
      [16.955, 11.57],
      [22.055, 15.468],
    ]),
  ]);

const FTO_STICKER_TRIANGLES = [
  [
    [8, 8],
    [12, 12],
    [16, 8],
  ],
  [
    [4, 4],
    [8, 8],
    [12, 4],
  ],
  [
    [0, 0],
    [4, 4],
    [8, 0],
  ],
  [
    [16, 8],
    [20, 4],
    [12, 4],
  ],
  [
    [12, 4],
    [16, 0],
    [8, 0],
  ],
  [
    [20, 4],
    [24, 0],
    [16, 0],
  ],
  [
    [16, 8],
    [12, 4],
    [8, 8],
  ],
  [
    [12, 4],
    [8, 0],
    [4, 4],
  ],
  [
    [20, 4],
    [16, 0],
    [12, 4],
  ],
  [
    [16, 16],
    [12, 12],
    [8, 16],
  ],
  [
    [16, 16],
    [8, 16],
    [12, 20],
  ],
  [
    [20, 20],
    [12, 20],
    [16, 24],
  ],
  [
    [8, 16],
    [4, 20],
    [12, 20],
  ],
  [
    [12, 20],
    [4, 20],
    [8, 24],
  ],
  [
    [4, 20],
    [0, 24],
    [8, 24],
  ],
  [
    [20, 20],
    [16, 16],
    [12, 20],
  ],
  [
    [8, 24],
    [16, 24],
    [12, 20],
  ],
  [
    [24, 24],
    [20, 20],
    [16, 24],
  ],
  [
    [8, 16],
    [12, 12],
    [8, 8],
  ],
  [
    [4, 20],
    [8, 16],
    [4, 12],
  ],
  [
    [0, 24],
    [4, 20],
    [0, 16],
  ],
  [
    [4, 12],
    [8, 16],
    [8, 8],
  ],
  [
    [0, 16],
    [4, 20],
    [4, 12],
  ],
  [
    [0, 8],
    [4, 12],
    [4, 4],
  ],
  [
    [8, 8],
    [4, 4],
    [4, 12],
  ],
  [
    [4, 12],
    [0, 8],
    [0, 16],
  ],
  [
    [4, 4],
    [0, 0],
    [0, 8],
  ],
  [
    [16, 8],
    [12, 12],
    [16, 16],
  ],
  [
    [16, 16],
    [20, 20],
    [20, 12],
  ],
  [
    [20, 20],
    [24, 24],
    [24, 16],
  ],
  [
    [16, 8],
    [16, 16],
    [20, 12],
  ],
  [
    [20, 20],
    [24, 16],
    [20, 12],
  ],
  [
    [20, 4],
    [20, 12],
    [24, 8],
  ],
  [
    [20, 4],
    [16, 8],
    [20, 12],
  ],
  [
    [24, 16],
    [24, 8],
    [20, 12],
  ],
  [
    [24, 0],
    [20, 4],
    [24, 8],
  ],
] as const satisfies readonly SvgTriangle[];

const FTO_FACE_GAP = 0.62;
const FTO_STICKER_GAP = FTO_FACE_GAP / 2;
const FTO_STICKER_CORNER_RADIUS = 0.65;
const FTO_STICKER_ROUNDED_INDEXES = new Set([0, 1, 2]);

const ftoIcon = (): string =>
  svg(FTO_STICKER_TRIANGLES.map((points) => roundedFtoStickerPath(points)));

const roundedFtoStickerPath = (points: SvgTriangle): SvgShape =>
  roundedPolygonPath({
    points: insetFtoStickerTriangle(points),
    radius: FTO_STICKER_CORNER_RADIUS,
    roundedIndexes: FTO_STICKER_ROUNDED_INDEXES,
  });

const insetFtoStickerTriangle = (points: SvgTriangle): SvgTriangle => {
  const centroid = triangleCentroid(points);
  const insetLines = points.map((pointValue, index) => {
    const nextPoint = points[(index + 1) % points.length];
    return offsetEdgeTowardCentroid(
      pointValue,
      nextPoint,
      centroid,
      ftoEdgeInset(pointValue, nextPoint),
    );
  });

  return [
    intersectLines(insetLines[2], insetLines[0]),
    intersectLines(insetLines[0], insetLines[1]),
    intersectLines(insetLines[1], insetLines[2]),
  ];
};

const triangleCentroid = (points: SvgTriangle): SvgPoint => [
  (points[0][0] + points[1][0] + points[2][0]) / 3,
  (points[0][1] + points[1][1] + points[2][1]) / 3,
];

const ftoEdgeInset = (from: SvgPoint, to: SvgPoint): number => {
  if (isFtoOuterEdge(from, to)) return 0;
  if (isFtoFaceSeamEdge(from, to)) return FTO_FACE_GAP / 2;

  return FTO_STICKER_GAP / 2;
};

const isFtoOuterEdge = ([fromX, fromY]: SvgPoint, [toX, toY]: SvgPoint): boolean =>
  (sameNumber(fromX, toX) && (sameNumber(fromX, 0) || sameNumber(fromX, 24))) ||
  (sameNumber(fromY, toY) && (sameNumber(fromY, 0) || sameNumber(fromY, 24)));

const isFtoFaceSeamEdge = ([fromX, fromY]: SvgPoint, [toX, toY]: SvgPoint): boolean =>
  (sameNumber(fromX - fromY, 0) && sameNumber(toX - toY, 0)) ||
  (sameNumber(fromX + fromY, 24) && sameNumber(toX + toY, 24));

const sameNumber = (first: number, second: number): boolean => Math.abs(first - second) < 0.001;

interface OffsetLine {
  readonly direction: SvgPoint;
  readonly point: SvgPoint;
}

const offsetEdgeTowardCentroid = (
  from: SvgPoint,
  to: SvgPoint,
  centroid: SvgPoint,
  inset: number,
): OffsetLine => {
  const [fromX, fromY] = from;
  const [toX, toY] = to;
  const deltaX = toX - fromX;
  const deltaY = toY - fromY;
  const length = Math.hypot(deltaX, deltaY);
  const normal: SvgPoint = [-deltaY / length, deltaX / length];
  const midpoint: SvgPoint = [(fromX + toX) / 2, (fromY + toY) / 2];
  const centroidDirection =
    (centroid[0] - midpoint[0]) * normal[0] + (centroid[1] - midpoint[1]) * normal[1];
  const inwardNormal: SvgPoint = centroidDirection >= 0 ? normal : [-normal[0], -normal[1]];

  return {
    direction: [deltaX, deltaY],
    point: [fromX + inwardNormal[0] * inset, fromY + inwardNormal[1] * inset],
  };
};

const intersectLines = (first: OffsetLine, second: OffsetLine): SvgPoint => {
  const cross = first.direction[0] * second.direction[1] - first.direction[1] * second.direction[0];
  const deltaX = second.point[0] - first.point[0];
  const deltaY = second.point[1] - first.point[1];
  const offset = (deltaX * second.direction[1] - deltaY * second.direction[0]) / cross;

  return [
    round(first.point[0] + first.direction[0] * offset),
    round(first.point[1] + first.direction[1] * offset),
  ];
};

export const EVENT_ICON_333_SVG = cubeGridIcon(3);
export const EVENT_ICON_222_SVG = cubeGridIcon(2);
export const EVENT_ICON_444_SVG = cubeGridIcon(4);
export const EVENT_ICON_555_SVG = cubeGridIcon(5);
export const EVENT_ICON_666_SVG = cubeGridIcon(6);
export const EVENT_ICON_777_SVG = cubeGridIcon(7);
export const EVENT_ICON_333BLD_SVG = blindfoldIcon(3);
export const EVENT_ICON_333FM_SVG = fewestMovesIcon();
export const EVENT_ICON_333OH_SVG = oneHandedIcon();
export const EVENT_ICON_CLOCK_SVG = clockIcon();
export const EVENT_ICON_MINX_SVG = megaminxIcon();
export const EVENT_ICON_PYRAM_SVG = svg([
  path(
    'M12 1.608 L8.862 7.043 Q8.462 7.736 9.262 7.736 L14.738 7.736 Q15.538 7.736 15.138 7.043 Z',
  ),
  path(
    'M8.169 9.629 Q7.769 8.936 7.369 9.629 L4.631 14.371 Q4.231 15.064 5.031 15.064 L10.507 15.064 Q11.307 15.064 10.907 14.371 Z',
  ),
  path(
    'M16.631 9.629 Q16.231 8.936 15.831 9.629 L13.093 14.371 Q12.693 15.064 13.493 15.064 L18.969 15.064 Q19.769 15.064 19.369 14.371 Z',
  ),
  path(
    'M3.938 16.957 Q3.538 16.264 3.138 16.957 L0 22.392 L6.276 22.392 Q7.076 22.392 6.676 21.699 Z',
  ),
  path(
    'M12.4 16.957 Q12 16.264 11.6 16.957 L8.862 21.699 Q8.462 22.392 9.262 22.392 L14.738 22.392 Q15.538 22.392 15.138 21.699 Z',
  ),
  path(
    'M20.862 16.957 Q20.462 16.264 20.062 16.957 L17.324 21.699 Q16.924 22.392 17.724 22.392 L24 22.392 Z',
  ),
  path(
    'M8.862 9.229 Q8.462 8.536 9.262 8.536 L14.738 8.536 Q15.538 8.536 15.138 9.229 L12.4 13.971 Q12 14.664 11.6 13.971 Z',
  ),
  path(
    'M4.631 16.557 Q4.231 15.864 5.031 15.864 L10.507 15.864 Q11.307 15.864 10.907 16.557 L8.169 21.299 Q7.769 21.992 7.369 21.299 Z',
  ),
  path(
    'M13.093 16.557 Q12.693 15.864 13.493 15.864 L18.969 15.864 Q19.769 15.864 19.369 16.557 L16.631 21.299 Q16.231 21.992 15.831 21.299 Z',
  ),
]);
export const EVENT_ICON_SKEWB_SVG = svg([
  path('M0 0 L9.93 0 Q11.43 0 10.37 1.06 L1.06 10.37 Q0 11.43 0 9.93 Z'),
  path('M13.63 1.06 Q12.57 0 14.07 0 L24 0 L24 9.93 Q24 11.43 22.94 10.37 Z'),
  path(
    'M10.94 1.63 Q12 0.57 13.06 1.63 L22.37 10.94 Q23.43 12 22.37 13.06 L13.06 22.37 Q12 23.43 10.94 22.37 L1.63 13.06 Q0.57 12 1.63 10.94 Z',
  ),
  path('M0 14.07 Q0 12.57 1.06 13.63 L10.37 22.94 Q11.43 24 9.93 24 L0 24 Z'),
  path('M22.94 13.63 Q24 12.57 24 14.07 L24 24 L14.07 24 Q12.57 24 13.63 22.94 Z'),
]);
export const EVENT_ICON_SQ1_SVG = svg([
  path('M9.11 0 L14.89 0 L12.73 7.84 Q12 12 11.27 7.84 Z'),
  path('M15.71 0 L24 0 L24 7.78 L15.88 10.35 Q12 12 13.5 8.06 Z'),
  path('M24 8.62 L24 15.38 L16.12 12.89 Q12 12 16.12 11.11 Z'),
  path('M24 16.22 L24 24 L15.71 24 L13.5 15.94 Q12 12 15.88 13.65 Z'),
  path('M14.89 24 L9.11 24 L11.27 16.16 Q12 12 12.73 16.16 Z'),
  path('M8.29 24 L0 24 L0 16.22 L8.12 13.65 Q12 12 10.5 15.94 Z'),
  path('M0 15.38 L0 8.62 L7.88 11.11 Q12 12 7.88 12.89 Z'),
  path('M0 7.78 L0 0 L8.29 0 L10.5 8.06 Q12 12 8.12 10.35 Z'),
]);
export const EVENT_ICON_444BLD_SVG = blindfoldIcon(4);
export const EVENT_ICON_555BLD_SVG = blindfoldIcon(5);
export const EVENT_ICON_333MBLD_SVG = blindfoldIcon(3, 'xN');
export const EVENT_ICON_FTO_SVG = ftoIcon();

export const EVENT_ICON_SVGS = Object.freeze({
  '333': EVENT_ICON_333_SVG,
  '222': EVENT_ICON_222_SVG,
  '444': EVENT_ICON_444_SVG,
  '555': EVENT_ICON_555_SVG,
  '666': EVENT_ICON_666_SVG,
  '777': EVENT_ICON_777_SVG,
  '333bld': EVENT_ICON_333BLD_SVG,
  '333fm': EVENT_ICON_333FM_SVG,
  '333oh': EVENT_ICON_333OH_SVG,
  clock: EVENT_ICON_CLOCK_SVG,
  minx: EVENT_ICON_MINX_SVG,
  pyram: EVENT_ICON_PYRAM_SVG,
  skewb: EVENT_ICON_SKEWB_SVG,
  sq1: EVENT_ICON_SQ1_SVG,
  '444bld': EVENT_ICON_444BLD_SVG,
  '555bld': EVENT_ICON_555BLD_SVG,
  '333mbld': EVENT_ICON_333MBLD_SVG,
  fto: EVENT_ICON_FTO_SVG,
} satisfies Record<EventIconId, string>);

// Pixel-art perched bird, drawn in the same crisp-edge style as Vibe Island's pet.
// '#' body, 'e' eye, 'b' beak/legs (bright tone), '.' empty.
const BIRD_OPEN = [
  '..........',
  '.....##...',
  '....#e##bb',
  '....####..',
  '..######..',
  '########..',
  '...#####..',
  '....b..b..',
];
const BIRD_SHUT = BIRD_OPEN.map((r, i) => (i === 2 ? '....####bb' : r));

const BIRD_TONES = {
  blocked: ['var(--vi-alert)', 'var(--vi-alert-bright)'],
  question: ['var(--vi-question)', 'var(--vi-question-bright)'],
  working: ['var(--vi-work)', 'var(--vi-work-bright)'],
  done: ['var(--vi-idle)', 'var(--vi-idle-bright)'],
  idle: ['#6b6b6b', '#9a9a9a'],
  offline: ['#3f3f3f', '#555'],
};

function PixelBird({ tone = 'idle', size = 16, motion = true }) {
  const [main, bright] = BIRD_TONES[tone] || BIRD_TONES.idle;
  const rows = tone === 'idle' || tone === 'offline' ? BIRD_SHUT : BIRD_OPEN;
  const rects = [];
  rows.forEach((row, y) => {
    [...row].forEach((c, x) => {
      if (c === '.') return;
      const fill = c === '#' ? main : c === 'e' ? '#000' : bright;
      rects.push(<rect key={`${x}-${y}`} x={x} y={y} width="1" height="1" fill={fill}></rect>);
    });
  });
  const anim = motion ? `bird-${tone}` : '';
  return (
    <svg className={`pixel-bird ${anim}`} width={size * 1.25} height={size} viewBox="0 0 10 8"
      shapeRendering="crispEdges" style={{ color: main }} aria-hidden="true">
      {rects}
    </svg>
  );
}

Object.assign(window, { PixelBird });

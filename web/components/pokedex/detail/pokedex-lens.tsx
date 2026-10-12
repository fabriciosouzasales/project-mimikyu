/**
 * Anel da "lente da Pokédex" (Pokédex P3b): circunferência com marcações, anel
 * pontilhado e o equador interrompido com núcleo — eco do motivo Pokébola do
 * MMKYU. Decorativo (aria-hidden), SVG estático, cor herdada (`currentColor`,
 * definida pelo tipo primário no palco).
 */
export function PokedexLens({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 500 500" fill="none" stroke="currentColor" aria-hidden="true" focusable="false">
      <circle cx="250" cy="250" r="248" strokeWidth="1.2" />
      <circle cx="250" cy="250" r="218" strokeWidth="1" strokeDasharray="2 7" />
      <g strokeWidth="1.2">
      <line x1="250" y1="6" x2="250" y2="22" transform="rotate(0.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(7.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(15.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(22.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(30.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(37.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="22" transform="rotate(45.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(52.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(60.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(67.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(75.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(82.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="22" transform="rotate(90.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(97.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(105.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(112.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(120.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(127.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="22" transform="rotate(135.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(142.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(150.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(157.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(165.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(172.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="22" transform="rotate(180.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(187.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(195.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(202.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(210.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(217.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="22" transform="rotate(225.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(232.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(240.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(247.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(255.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(262.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="22" transform="rotate(270.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(277.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(285.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(292.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(300.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(307.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="22" transform="rotate(315.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(322.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(330.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(337.5 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(345.0 250 250)" />
      <line x1="250" y1="6" x2="250" y2="14" transform="rotate(352.5 250 250)" />
      </g>
      <path d="M2 250H204M296 250H498" strokeWidth="1.2" />
      <circle cx="250" cy="250" r="46" strokeWidth="1.2" />
    </svg>
  );
}

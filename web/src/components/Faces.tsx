/** Marcus, drawn: a flat vector bust in the palette (the right-hand man: flat cap, shades, beard, a dark jacket over a
 *  white tee), clipped to a disc. One drawing at any size; the amber ring around it is the caller's (.mring). */
export function MarcusFace({ size = 40, className = '' }: { size?: number; className?: string }) {
  return (
    <svg className={`face ${className}`.trim()} width={size} height={size} viewBox="0 0 64 64" aria-hidden="true" focusable="false">
      <defs>
        <clipPath id="marcus-disc"><circle cx="32" cy="32" r="32" /></clipPath>
        <linearGradient id="marcus-bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#223129" /><stop offset="1" stopColor="#0f1816" /></linearGradient>
      </defs>
      <g clipPath="url(#marcus-disc)">
        <rect width="64" height="64" fill="url(#marcus-bg)" />
        {/* jacket and the tee */}
        <path d="M2 66 C4 48 17 43 32 43 C47 43 60 48 62 66 Z" fill="#1c2522" />
        <path d="M26 43 L32 52 L38 43 Z" fill="#e8dfcf" />
        <path d="M22 44 L32 56 L42 44" fill="none" stroke="#2b3632" strokeWidth="2" strokeLinejoin="round" />
        {/* neck and head */}
        <rect x="26" y="34" width="12" height="12" fill="#9a6843" />
        <ellipse cx="20.5" cy="29" rx="2.6" ry="3" fill="#a87249" />
        <ellipse cx="43.5" cy="29" rx="2.6" ry="3" fill="#a87249" />
        <path d="M20 22 C20 14 44 14 44 22 L44 31 C44 39 38 43 32 43 C26 43 20 39 20 31 Z" fill="#b8825a" />
        {/* beard and mustache */}
        <path d="M20 30 C20.5 39 26 43.5 32 43.5 C38 43.5 43.5 39 44 30 C42 35.5 37.5 37.5 32 37.5 C26.5 37.5 22 35.5 20 30 Z" fill="#2a211c" />
        <path d="M27 34 Q32 32.2 37 34 Q32 36 27 34 Z" fill="#2a211c" />
        {/* shades */}
        <rect x="21.5" y="26.5" width="9" height="5.5" rx="2.2" fill="#0a1214" />
        <rect x="33.5" y="26.5" width="9" height="5.5" rx="2.2" fill="#0a1214" />
        <path d="M30.5 28.5 L33.5 28.5" stroke="#0a1214" strokeWidth="1.6" />
        <path d="M23.5 27.9 L27 27.9" stroke="#f2a33a" strokeWidth="1" strokeOpacity=".55" strokeLinecap="round" />
        <path d="M35.5 27.9 L39 27.9" stroke="#f2a33a" strokeWidth="1" strokeOpacity=".55" strokeLinecap="round" />
        {/* the flat cap */}
        <path d="M18 22 C18 10 46 10 46 22 L46 23.5 L18 23.5 Z" fill="#26302d" />
        <path d="M19.5 19.5 C23 13.5 41 13.5 44.5 19.5" fill="none" stroke="#33403c" strokeWidth="1.4" strokeLinecap="round" />
        <path d="M18.5 23.5 L45.5 23.5 L50 25.3 L45.5 26.8 L18.5 26.8 C17.2 26.8 17.2 23.5 18.5 23.5 Z" fill="#1b2422" />
      </g>
    </svg>
  )
}

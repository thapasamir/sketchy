<script>
  // A reaction as a riso-printed die-cut sticker: a white cut border, a pink plate printed
  // slightly off-register, then ink line work and flat spot colours with a halftone shade.
  // `id` is one of the names in lib/reactions.js; anything else draws nothing.
  export let id = ''
</script>

<svg viewBox="0 0 64 64" class="block h-full w-full" aria-hidden="true" focusable="false">
  <defs>
    <pattern id="sticker-dots" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(30)">
      <circle cx="2.5" cy="2.5" r="1.1" fill="#FF48B0" />
    </pattern>
    <clipPath id="sticker-disc"><circle cx="32" cy="32" r="25" /></clipPath>
  </defs>

  <!-- die-cut border, and the pink plate sliding out from under the sticker -->
  <circle cx="32" cy="32" r="30" fill="#fff" stroke="#263A6E" stroke-opacity=".25" stroke-width="1" />
  <circle cx="35" cy="35" r="25" fill="#FF48B0" />

  {#if id === 'laugh'}
    <circle cx="32" cy="32" r="25" fill="#FFE800" stroke="#263A6E" stroke-width="2.5" />
    <g clip-path="url(#sticker-disc)"><rect x="9" y="9" width="64" height="64" fill="url(#sticker-dots)" opacity=".55" /></g>
    <path d="M16 25 L25 29 L16 33 M48 25 L39 29 L48 33" fill="none" stroke="#263A6E" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" />
    <path d="M17 38 Q32 58 47 38 Z" fill="#CC0E74" stroke="#263A6E" stroke-width="2.5" stroke-linejoin="round" />
    <path d="M23 42 Q32 47 41 42" fill="none" stroke="#fff" stroke-width="2.5" stroke-linecap="round" />
    <path d="M10 30 q-3 5 0 8 q3 -3 0 -8 M54 30 q3 5 0 8 q-3 -3 0 -8" fill="#0078BF" stroke="#263A6E" stroke-width="1.5" />
  {:else if id === 'think'}
    <circle cx="32" cy="32" r="25" fill="#FFE800" stroke="#263A6E" stroke-width="2.5" />
    <g clip-path="url(#sticker-disc)"><rect x="9" y="9" width="64" height="64" fill="url(#sticker-dots)" opacity=".55" /></g>
    <circle cx="23" cy="27" r="3.2" fill="#263A6E" />
    <circle cx="41" cy="27" r="3.2" fill="#263A6E" />
    <path d="M17 19 L28 21 M36 19 Q42 15 48 19" fill="none" stroke="#263A6E" stroke-width="2.5" stroke-linecap="round" />
    <path d="M24 44 Q30 40 36 43 T44 42" fill="none" stroke="#263A6E" stroke-width="2.5" stroke-linecap="round" />
    <path d="M42 56 Q50 54 50 44 L44 44 Q43 49 38 50 Z" fill="#FFE800" stroke="#263A6E" stroke-width="2" stroke-linejoin="round" />
    <circle cx="51" cy="12" r="9" fill="#0078BF" stroke="#263A6E" stroke-width="2" />
    <text x="51" y="17" text-anchor="middle" font-family="'Bowlby One', Impact, sans-serif" font-size="13" fill="#fff">?</text>
  {:else if id === 'sus'}
    <circle cx="32" cy="32" r="25" fill="#FFE800" stroke="#263A6E" stroke-width="2.5" />
    <g clip-path="url(#sticker-disc)"><rect x="9" y="9" width="64" height="64" fill="url(#sticker-dots)" opacity=".55" /></g>
    <path d="M15 22 L28 22 M36 17 Q43 14 49 19" fill="none" stroke="#263A6E" stroke-width="3" stroke-linecap="round" />
    <ellipse cx="22" cy="29" rx="6" ry="4.5" fill="#fff" stroke="#263A6E" stroke-width="2" />
    <ellipse cx="42" cy="29" rx="6" ry="4.5" fill="#fff" stroke="#263A6E" stroke-width="2" />
    <circle cx="19.5" cy="29.5" r="2.4" fill="#263A6E" />
    <circle cx="39.5" cy="29.5" r="2.4" fill="#263A6E" />
    <path d="M22 44 L44 42" stroke="#263A6E" stroke-width="3" stroke-linecap="round" />
  {:else if id === 'eyes'}
    <circle cx="32" cy="32" r="25" fill="#0078BF" stroke="#263A6E" stroke-width="2.5" />
    <g clip-path="url(#sticker-disc)"><rect x="9" y="9" width="64" height="64" fill="url(#sticker-dots)" opacity=".5" /></g>
    <ellipse cx="22" cy="32" rx="9.5" ry="13" fill="#fff" stroke="#263A6E" stroke-width="2.5" />
    <ellipse cx="42" cy="32" rx="9.5" ry="13" fill="#fff" stroke="#263A6E" stroke-width="2.5" />
    <circle cx="25" cy="34" r="5" fill="#263A6E" />
    <circle cx="45" cy="34" r="5" fill="#263A6E" />
    <circle cx="26.6" cy="32.2" r="1.5" fill="#fff" />
    <circle cx="46.6" cy="32.2" r="1.5" fill="#fff" />
  {:else if id === 'clap'}
    <circle cx="32" cy="32" r="25" fill="#FF48B0" stroke="#263A6E" stroke-width="2.5" />
    <path d="M32 6 V13 M14 12 L19 18 M50 12 L45 18 M7 28 H14 M57 28 H50" stroke="#FFE800" stroke-width="3.5" stroke-linecap="round" />
    <path d="M18 50 L12 33 Q10 28 15 27 Q19 27 21 31 L24 24 Q26 20 30 22 L36 30 Q38 33 36 36 L30 50 Q26 55 21 54 Z" fill="#FFE800" stroke="#263A6E" stroke-width="2.5" stroke-linejoin="round" />
    <path d="M46 50 L52 33 Q54 28 49 27 Q45 27 43 31 L40 24 Q38 20 34 22 L28 30 Q26 33 28 36 L34 50 Q38 55 43 54 Z" fill="#fff" stroke="#263A6E" stroke-width="2.5" stroke-linejoin="round" />
    <path d="M24 33 L30 40 M40 33 L34 40" stroke="#263A6E" stroke-width="2" stroke-linecap="round" />
  {:else if id === 'fire'}
    <circle cx="32" cy="32" r="25" fill="#FFE800" stroke="#263A6E" stroke-width="2.5" />
    <path d="M33 8 Q36 20 45 27 Q53 35 49 45 Q45 55 32 55 Q18 55 15 43 Q13 34 21 27 Q22 33 27 34 Q24 20 33 8 Z" fill="#FF48B0" stroke="#263A6E" stroke-width="2.5" stroke-linejoin="round" />
    <path d="M33 31 Q37 38 41 42 Q43 48 37 51 Q29 53 26 47 Q24 42 29 38 Q31 40 32 40 Q31 36 33 31 Z" fill="#FFE800" stroke="#263A6E" stroke-width="2" stroke-linejoin="round" />
  {/if}
</svg>

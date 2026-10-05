<script>
  // A hat, drawn with the middle of its base at (0, 0) and reaching up (negative y) up to about
  // 0.6. The player drawn under it moves it into place. 0 is no hat; the names and the count are
  // in lib/avatar.js.
  let { index } = $props()

  const INK = '#1b1b1b'
  const PINK = '#ff48b0'
  const BLUE = '#0078bf'
  const YELLOW = '#ffe800'
  const PURPLE = '#8a4fd6'
</script>

<g data-hat={index} stroke={INK} stroke-width="0.05" stroke-linecap="round" stroke-linejoin="round">
  {#if index === 1}
    <!-- party hat: striped cone, dots, a pompom -->
    <path d="M-0.32 0.02 Q-0.04 -0.18 0 -0.6 Q0.04 -0.18 0.32 0.02 Z" fill={YELLOW} />
    <path d="M-0.2 -0.2 L0.2 -0.2" stroke={PINK} stroke-width="0.07" />
    <path d="M-0.1 -0.4 L0.1 -0.4" stroke={PINK} stroke-width="0.06" />
    <circle cx="-0.06" cy="-0.08" r="0.03" fill={BLUE} stroke="none" />
    <circle cx="0.08" cy="-0.1" r="0.03" fill={BLUE} stroke="none" />
    <circle cx="0" cy="-0.62" r="0.08" fill={PINK} />
  {:else if index === 2}
    <!-- crown: three points, jewels, a band -->
    <path d="M-0.36 0.02 L-0.4 -0.44 L-0.18 -0.22 L0 -0.56 L0.18 -0.22 L0.4 -0.44 L0.36 0.02 Z" fill="#ffd23f" />
    <path d="M-0.36 -0.08 H0.36" stroke-width="0.04" />
    <circle cx="-0.4" cy="-0.46" r="0.05" fill={PINK} />
    <circle cx="0" cy="-0.58" r="0.055" fill={BLUE} />
    <circle cx="0.4" cy="-0.46" r="0.05" fill={PINK} />
    <circle cx="0" cy="-0.2" r="0.045" fill={PINK} stroke-width="0.03" />
  {:else if index === 3}
    <!-- baseball cap: panel stripes, a button, a peak -->
    <path d="M-0.4 0.02 Q-0.4 -0.5 0 -0.5 Q0.4 -0.5 0.4 0.02 Z" fill={BLUE} />
    <path d="M0 -0.5 Q-0.14 -0.24 -0.12 0.02" fill="none" stroke-width="0.035" />
    <path d="M0 -0.5 Q0.14 -0.24 0.12 0.02" fill="none" stroke-width="0.035" />
    <path d="M0.16 0.02 H0.66 Q0.7 0.1 0.36 0.1 H0.16 Z" fill="#0a5a8f" />
    <circle cx="0" cy="-0.52" r="0.05" fill="#fff" />
    <path d="M-0.3 -0.28 Q-0.26 -0.4 -0.14 -0.42" fill="none" stroke="#fff" stroke-width="0.04" opacity="0.6" />
  {:else if index === 4}
    <!-- top hat: a band, a buckle, a shine -->
    <rect x="-0.28" y="-0.6" width="0.56" height="0.56" rx="0.04" fill={INK} />
    <rect x="-0.28" y="-0.2" width="0.56" height="0.1" fill={PINK} stroke="none" />
    <rect x="-0.06" y="-0.22" width="0.12" height="0.14" rx="0.02" fill={YELLOW} stroke-width="0.03" />
    <rect x="-0.5" y="-0.07" width="1" height="0.12" rx="0.05" fill={INK} />
    <path d="M-0.2 -0.52 V-0.28" stroke="#fff" stroke-width="0.05" opacity="0.4" />
  {:else if index === 5}
    <!-- knitted beanie: ribs, a turned-up cuff, a fluffy pompom -->
    <path d="M-0.38 -0.02 Q-0.38 -0.5 0 -0.5 Q0.38 -0.5 0.38 -0.02 Z" fill={PINK} />
    <path d="M-0.22 -0.12 V-0.4 M-0.07 -0.12 V-0.46 M0.07 -0.12 V-0.46 M0.22 -0.12 V-0.4" fill="none" stroke-width="0.03" opacity="0.55" />
    <rect x="-0.43" y="-0.12" width="0.86" height="0.16" rx="0.05" fill={YELLOW} />
    <circle cx="0" cy="-0.55" r="0.1" fill="#fff" />
    <circle cx="-0.05" cy="-0.6" r="0.03" fill="none" stroke-width="0.025" />
  {:else if index === 6}
    <!-- a bow with dots -->
    <path d="M0 -0.12 L-0.38 -0.36 Q-0.46 -0.1 -0.38 0.14 Z" fill={PINK} />
    <path d="M0 -0.12 L0.38 -0.36 Q0.46 -0.1 0.38 0.14 Z" fill={PINK} />
    <circle cx="-0.28" cy="-0.12" r="0.03" fill="#fff" stroke="none" />
    <circle cx="0.28" cy="-0.12" r="0.03" fill="#fff" stroke="none" />
    <circle cx="0" cy="-0.12" r="0.09" fill="#d6309a" />
  {:else if index === 7}
    <!-- cat ears -->
    <path d="M-0.46 0.04 Q-0.46 -0.3 -0.38 -0.5 Q-0.2 -0.34 -0.06 -0.06 Z" fill={INK} />
    <path d="M0.46 0.04 Q0.46 -0.3 0.38 -0.5 Q0.2 -0.34 0.06 -0.06 Z" fill={INK} />
    <path d="M-0.38 -0.08 Q-0.38 -0.26 -0.34 -0.34 Q-0.24 -0.24 -0.18 -0.1 Z" fill="#ff7a9c" stroke="none" />
    <path d="M0.38 -0.08 Q0.38 -0.26 0.34 -0.34 Q0.24 -0.24 0.18 -0.1 Z" fill="#ff7a9c" stroke="none" />
  {:else if index === 8}
    <!-- wizard hat: a bent tip, stars, a wide brim -->
    <path d="M-0.3 -0.02 Q-0.1 -0.3 0.04 -0.52 Q0.1 -0.62 0.3 -0.6 Q0.18 -0.5 0.16 -0.38 Q0.2 -0.18 0.3 -0.02 Z" fill={PURPLE} />
    <ellipse cx="0" cy="0" rx="0.5" ry="0.09" fill="#6a37b3" />
    <path d="M-0.04 -0.22 l0.025 0.05 0.055 0.008 -0.04 0.04 0.01 0.055 -0.05 -0.027 -0.05 0.027 0.01 -0.055 -0.04 -0.04 0.055 -0.008 Z" fill={YELLOW} stroke-width="0.02" />
    <circle cx="0.1" cy="-0.34" r="0.025" fill={YELLOW} stroke="none" />
    <circle cx="-0.12" cy="-0.1" r="0.022" fill={YELLOW} stroke="none" />
  {:else if index === 9}
    <!-- pirate hat: a curved brim, a skull and crossbones -->
    <path d="M-0.5 0.02 Q-0.44 -0.34 -0.1 -0.46 Q0 -0.5 0.1 -0.46 Q0.44 -0.34 0.5 0.02 Q0 -0.08 -0.5 0.02 Z" fill={INK} />
    <path d="M-0.46 0.0 Q0 -0.1 0.46 0.0" fill="none" stroke="#ffd23f" stroke-width="0.04" />
    <circle cx="0" cy="-0.26" r="0.075" fill="#fff" stroke-width="0.025" />
    <circle cx="-0.027" cy="-0.27" r="0.016" fill={INK} stroke="none" />
    <circle cx="0.027" cy="-0.27" r="0.016" fill={INK} stroke="none" />
    <path d="M-0.1 -0.13 L0.1 -0.2 M0.1 -0.13 L-0.1 -0.2" stroke="#fff" stroke-width="0.04" />
  {:else if index === 10}
    <!-- chef's hat: a puffy top and a band -->
    <path d="M-0.3 0.02 L-0.3 -0.2 Q-0.5 -0.22 -0.44 -0.42 Q-0.4 -0.56 -0.22 -0.52 Q-0.14 -0.66 0 -0.62 Q0.14 -0.66 0.22 -0.52 Q0.4 -0.56 0.44 -0.42 Q0.5 -0.22 0.3 -0.2 L0.3 0.02 Z" fill="#fff" />
    <path d="M-0.3 -0.1 H0.3" stroke-width="0.04" />
    <path d="M-0.16 -0.34 Q-0.1 -0.44 -0.02 -0.4 M0.12 -0.4 Q0.2 -0.46 0.26 -0.38" fill="none" stroke-width="0.025" opacity="0.5" />
  {:else if index === 11}
    <!-- cowboy hat: a curled brim, a band with a star -->
    <path d="M-0.26 -0.02 Q-0.3 -0.4 -0.1 -0.42 Q0 -0.34 0.1 -0.42 Q0.3 -0.4 0.26 -0.02 Z" fill="#b5651d" />
    <path d="M-0.62 -0.12 Q-0.5 0.08 -0.2 0.02 H0.2 Q0.5 0.08 0.62 -0.12 Q0.5 -0.02 0.3 -0.04 H-0.3 Q-0.5 -0.02 -0.62 -0.12 Z" fill="#8c4a12" />
    <rect x="-0.27" y="-0.14" width="0.54" height="0.08" fill={INK} stroke="none" />
    <path d="M0 -0.18 l0.02 0.04 0.045 0.006 -0.032 0.03 0.008 0.045 -0.04 -0.022 -0.04 0.022 0.008 -0.045 -0.032 -0.03 0.045 -0.006 Z" fill="#ffd23f" stroke-width="0.015" />
  {:else if index === 12}
    <!-- viking helmet: a dome, a band, rivets, two horns -->
    <path d="M-0.36 0.02 Q-0.36 -0.46 0 -0.46 Q0.36 -0.46 0.36 0.02 Z" fill="#9aa4ad" />
    <rect x="-0.38" y="-0.12" width="0.76" height="0.12" rx="0.03" fill="#6b747c" />
    <circle cx="-0.24" cy="-0.06" r="0.025" fill={YELLOW} stroke="none" />
    <circle cx="0" cy="-0.06" r="0.025" fill={YELLOW} stroke="none" />
    <circle cx="0.24" cy="-0.06" r="0.025" fill={YELLOW} stroke="none" />
    <path d="M-0.34 -0.18 Q-0.64 -0.2 -0.6 -0.54 Q-0.5 -0.4 -0.3 -0.36 Z" fill="#f6ead2" />
    <path d="M0.34 -0.18 Q0.64 -0.2 0.6 -0.54 Q0.5 -0.4 0.3 -0.36 Z" fill="#f6ead2" />
    <path d="M-0.18 -0.4 Q-0.1 -0.44 -0.04 -0.43" fill="none" stroke="#fff" stroke-width="0.04" opacity="0.55" />
  {:else if index === 13}
    <!-- santa hat: a fur trim and a drooping pompom -->
    <path d="M-0.38 -0.02 Q-0.34 -0.42 0.0 -0.5 Q0.26 -0.52 0.46 -0.34 Q0.5 -0.22 0.36 -0.28 Q0.18 -0.14 0.38 -0.02 Z" fill="#e63946" />
    <rect x="-0.46" y="-0.1" width="0.92" height="0.16" rx="0.08" fill="#fff" />
    <circle cx="0.5" cy="-0.3" r="0.1" fill="#fff" />
    <path d="M-0.22 -0.34 Q-0.14 -0.42 -0.04 -0.42" fill="none" stroke="#fff" stroke-width="0.04" opacity="0.4" />
  {:else if index === 14}
    <!-- a halo, floating -->
    <ellipse cx="0" cy="-0.24" rx="0.36" ry="0.1" fill="none" stroke={INK} stroke-width="0.17" />
    <ellipse cx="0" cy="-0.24" rx="0.36" ry="0.1" fill="none" stroke="#ffd23f" stroke-width="0.095" />
    <path d="M-0.2 -0.33 Q-0.1 -0.36 0 -0.35" stroke="#fff" stroke-width="0.035" fill="none" />
  {:else if index === 15}
    <!-- bunny ears -->
    <path d="M-0.28 0.02 Q-0.46 -0.3 -0.34 -0.56 Q-0.2 -0.66 -0.14 -0.4 Q-0.1 -0.2 -0.1 0.02 Z" fill="#fff" />
    <path d="M0.28 0.02 Q0.46 -0.3 0.34 -0.56 Q0.2 -0.66 0.14 -0.4 Q0.1 -0.2 0.1 0.02 Z" fill="#fff" />
    <path d="M-0.28 -0.1 Q-0.36 -0.3 -0.3 -0.48 Q-0.22 -0.4 -0.2 -0.24 Z" fill="#ff7a9c" stroke="none" />
    <path d="M0.28 -0.1 Q0.36 -0.3 0.3 -0.48 Q0.22 -0.4 0.2 -0.24 Z" fill="#ff7a9c" stroke="none" />
  {/if}
</g>

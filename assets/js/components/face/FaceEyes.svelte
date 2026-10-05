<script>
  // The eyes, drawn in "face space": the middle of the face is (0, 0) and the face is about 1.2
  // wide. Which ones is `index` (0 to 11; the count and names are in lib/avatar.js).
  let { index } = $props()

  const INK = '#1b1b1b'
</script>

<g data-eyes={index} stroke={INK} stroke-width="0.07" stroke-linecap="round" stroke-linejoin="round" fill="none">
  {#if index === 0}
    <!-- dots, each with a glint -->
    <circle cx="-0.3" cy="-0.12" r="0.1" fill={INK} stroke="none" />
    <circle cx="0.3" cy="-0.12" r="0.1" fill={INK} stroke="none" />
    <circle cx="-0.27" cy="-0.15" r="0.035" fill="#fff" stroke="none" />
    <circle cx="0.33" cy="-0.15" r="0.035" fill="#fff" stroke="none" />
  {:else if index === 1}
    <!-- wide eyes looking sideways -->
    <circle cx="-0.3" cy="-0.12" r="0.19" fill="#fff" stroke-width="0.05" />
    <circle cx="0.3" cy="-0.12" r="0.19" fill="#fff" stroke-width="0.05" />
    <circle cx="-0.25" cy="-0.1" r="0.09" fill={INK} stroke="none" />
    <circle cx="0.35" cy="-0.1" r="0.09" fill={INK} stroke="none" />
    <circle cx="-0.22" cy="-0.13" r="0.03" fill="#fff" stroke="none" />
    <circle cx="0.38" cy="-0.13" r="0.03" fill="#fff" stroke="none" />
  {:else if index === 2}
    <!-- happy, closed -->
    <path d="M-0.47 -0.05 Q-0.3 -0.32 -0.13 -0.05" />
    <path d="M0.13 -0.05 Q0.3 -0.32 0.47 -0.05" />
  {:else if index === 3}
    <!-- sleepy -->
    <path d="M-0.44 -0.1 H-0.16" />
    <path d="M0.16 -0.1 H0.44" />
    <path d="M-0.4 -0.01 Q-0.3 0.07 -0.2 -0.01" stroke-width="0.04" />
    <path d="M0.2 -0.01 Q0.3 0.07 0.4 -0.01" stroke-width="0.04" />
  {:else if index === 4}
    <!-- a wink -->
    <circle cx="-0.3" cy="-0.12" r="0.1" fill={INK} stroke="none" />
    <circle cx="-0.27" cy="-0.15" r="0.035" fill="#fff" stroke="none" />
    <path d="M0.13 -0.07 Q0.3 -0.32 0.47 -0.07" />
  {:else if index === 5}
    <!-- sparkles -->
    <path d="M-0.3 -0.36 L-0.25 -0.18 L-0.08 -0.12 L-0.25 -0.06 L-0.3 0.12 L-0.35 -0.06 L-0.52 -0.12 L-0.35 -0.18 Z" fill={INK} stroke-width="0.03" />
    <path d="M0.3 -0.36 L0.35 -0.18 L0.52 -0.12 L0.35 -0.06 L0.3 0.12 L0.25 -0.06 L0.08 -0.12 L0.25 -0.18 Z" fill={INK} stroke-width="0.03" />
  {:else if index === 6}
    <!-- sunglasses -->
    <rect x="-0.54" y="-0.27" width="0.46" height="0.3" rx="0.1" fill={INK} stroke-width="0.04" />
    <rect x="0.08" y="-0.27" width="0.46" height="0.3" rx="0.1" fill={INK} stroke-width="0.04" />
    <path d="M-0.08 -0.17 H0.08" stroke-width="0.05" />
    <path d="M-0.45 -0.2 L-0.33 -0.2" stroke="#fff" stroke-width="0.05" />
    <path d="M0.17 -0.2 L0.29 -0.2" stroke="#fff" stroke-width="0.05" />
  {:else if index === 7}
    <!-- cross: dots and angry brows -->
    <circle cx="-0.3" cy="-0.07" r="0.085" fill={INK} stroke="none" />
    <circle cx="0.3" cy="-0.07" r="0.085" fill={INK} stroke="none" />
    <path d="M-0.52 -0.38 L-0.14 -0.22" stroke-width="0.09" />
    <path d="M0.52 -0.38 L0.14 -0.22" stroke-width="0.09" />
  {:else if index === 8}
    <!-- hearts -->
    <path d="M-0.3 0.06 C-0.52 -0.1 -0.46 -0.3 -0.3 -0.2 C-0.14 -0.3 -0.08 -0.1 -0.3 0.06 Z" fill="#ff2e6e" stroke-width="0.04" />
    <path d="M0.3 0.06 C0.08 -0.1 0.14 -0.3 0.3 -0.2 C0.46 -0.3 0.52 -0.1 0.3 0.06 Z" fill="#ff2e6e" stroke-width="0.04" />
    <circle cx="-0.38" cy="-0.2" r="0.03" fill="#fff" stroke="none" />
    <circle cx="0.22" cy="-0.2" r="0.03" fill="#fff" stroke="none" />
  {:else if index === 9}
    <!-- dots with long lashes -->
    <circle cx="-0.28" cy="-0.1" r="0.1" fill={INK} stroke="none" />
    <circle cx="0.28" cy="-0.1" r="0.1" fill={INK} stroke="none" />
    <circle cx="-0.25" cy="-0.13" r="0.035" fill="#fff" stroke="none" />
    <circle cx="0.31" cy="-0.13" r="0.035" fill="#fff" stroke="none" />
    <path d="M-0.42 -0.2 L-0.52 -0.3 M-0.36 -0.26 L-0.4 -0.38 M-0.28 -0.28 L-0.28 -0.4" stroke-width="0.045" />
    <path d="M0.42 -0.2 L0.52 -0.3 M0.36 -0.26 L0.4 -0.38 M0.28 -0.28 L0.28 -0.4" stroke-width="0.045" />
  {:else if index === 10}
    <!-- one big eye -->
    <circle cx="0" cy="-0.1" r="0.3" fill="#fff" stroke-width="0.055" />
    <circle cx="0.04" cy="-0.08" r="0.14" fill={INK} stroke="none" />
    <circle cx="0.09" cy="-0.13" r="0.045" fill="#fff" stroke="none" />
  {:else if index === 11}
    <!-- dizzy crosses -->
    <path d="M-0.46 -0.26 L-0.14 0.04 M-0.14 -0.26 L-0.46 0.04" stroke-width="0.08" />
    <path d="M0.14 -0.26 L0.46 0.04 M0.46 -0.26 L0.14 0.04" stroke-width="0.08" />
  {/if}
</g>

<script>
  // The mouth, in "face space" (see FaceEyes). Which one is `index` (0 to 11).
  let { index } = $props()

  const INK = '#1b1b1b'
  const TONGUE = '#ff7a9c'
</script>

<g data-mouth={index} stroke={INK} stroke-width="0.07" stroke-linecap="round" stroke-linejoin="round" fill="none">
  {#if index === 0}
    <!-- a smile -->
    <path d="M-0.3 0.2 Q0 0.52 0.3 0.2" />
  {:else if index === 1}
    <!-- a big open grin -->
    <path d="M-0.34 0.17 H0.34 Q0.34 0.6 0 0.6 Q-0.34 0.6 -0.34 0.17 Z" fill={INK} stroke-width="0.05" />
    <path d="M-0.17 0.56 Q0 0.36 0.17 0.56" fill={TONGUE} stroke="none" />
    <path d="M-0.26 0.17 H0.26 V0.26 H-0.26 Z" fill="#fff" stroke="none" />
  {:else if index === 2}
    <!-- surprised -->
    <ellipse cx="0" cy="0.36" rx="0.11" ry="0.16" fill={INK} stroke="none" />
    <ellipse cx="0" cy="0.4" rx="0.06" ry="0.07" fill={TONGUE} stroke="none" />
  {:else if index === 3}
    <!-- flat -->
    <path d="M-0.24 0.34 H0.24" />
  {:else if index === 4}
    <!-- smile with the tongue out -->
    <path d="M-0.3 0.2 Q0 0.46 0.3 0.2" />
    <path d="M-0.1 0.33 V0.52 Q0 0.63 0.1 0.52 V0.33" fill={TONGUE} stroke-width="0.04" />
    <path d="M0 0.38 V0.5" stroke-width="0.025" />
  {:else if index === 5}
    <!-- cat mouth -->
    <path d="M-0.34 0.26 Q-0.17 0.48 0 0.28 Q0.17 0.48 0.34 0.26" />
    <path d="M0 0.2 V0.28" stroke-width="0.05" />
  {:else if index === 6}
    <!-- sad -->
    <path d="M-0.28 0.48 Q0 0.2 0.28 0.48" />
  {:else if index === 7}
    <!-- a smirk -->
    <path d="M-0.26 0.36 Q0.06 0.42 0.32 0.16" />
    <path d="M0.32 0.16 L0.36 0.12" stroke-width="0.04" />
  {:else if index === 8}
    <!-- a smile with fangs -->
    <path d="M-0.3 0.2 Q0 0.46 0.3 0.2" />
    <path d="M-0.2 0.28 L-0.14 0.46 L-0.08 0.34 Z" fill="#fff" stroke-width="0.035" />
    <path d="M0.2 0.28 L0.14 0.46 L0.08 0.34 Z" fill="#fff" stroke-width="0.035" />
  {:else if index === 9}
    <!-- a curly moustache over a small smile -->
    <path d="M0 0.2 C-0.1 0.1 -0.32 0.08 -0.42 0.2 C-0.32 0.34 -0.14 0.28 0 0.26 C0.14 0.28 0.32 0.34 0.42 0.2 C0.32 0.08 0.1 0.1 0 0.2 Z" fill={INK} stroke-width="0.03" />
    <path d="M-0.12 0.42 Q0 0.52 0.12 0.42" stroke-width="0.055" />
  {:else if index === 10}
    <!-- teeth -->
    <rect x="-0.3" y="0.18" width="0.6" height="0.28" rx="0.09" fill="#fff" stroke-width="0.055" />
    <path d="M-0.15 0.18 V0.46 M0 0.18 V0.46 M0.15 0.18 V0.46 M-0.3 0.32 H0.3" stroke-width="0.035" />
  {:else if index === 11}
    <!-- a kiss -->
    <path d="M-0.15 0.28 Q0 0.18 0.15 0.28 Q0.22 0.37 0.15 0.46 Q0 0.57 -0.15 0.46 Q-0.22 0.37 -0.15 0.28 Z" fill="#ff4d7d" stroke-width="0.045" />
    <path d="M-0.12 0.37 H0.12" stroke-width="0.03" />
  {/if}
</g>

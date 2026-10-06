<script>
  import Marker from './Marker.svelte'
  import Sticker from './Sticker.svelte'

  // The game in one glance, for the first screen: a shared sheet that keeps drawing itself (a
  // cat), a few of the real faces around it reacting with the real stickers, and one line on it
  // that doesn't belong, because someone at the table doesn't know the word.
  const PLAYERS = [
    { id: 'home-a', name: 'Ada', color: '#ffe800', avatar: { eyes: 2, mouth: 1, hat: 1 }, react: 'laugh', at: 0 },
    { id: 'home-b', name: 'Bo', color: '#4aa8e8', avatar: { eyes: 6, mouth: 7, hat: 4 }, react: 'think', at: 1.4 },
    { id: 'home-c', name: 'Cy', color: '#ff7fc2', avatar: { eyes: 5, mouth: 4, hat: 8 }, react: 'fire', at: 2.8 },
    { id: 'home-d', name: 'Di', color: '#7ed08a', avatar: { eyes: 1, mouth: 2, hat: 7 }, react: 'eyes', at: 4.2 },
    { id: 'home-e', name: 'Ed', color: '#ffa94d', avatar: { eyes: 7, mouth: 8, hat: 0 }, react: 'sus', at: 5.6 },
  ]

  // each line of the cat, drawn one after the other
  const LINES = [
    'M60 100 C40 60 60 35 100 35 C140 35 160 60 140 100 C120 118 80 118 60 100 Z',
    'M68 50 L62 20 L88 38',
    'M132 50 L138 20 L112 38',
    'M82 68 h0.1 M118 68 h0.1',
    'M92 82 L100 88 L108 82 M100 88 V95',
    'M58 84 L30 79 M58 93 L30 98 M142 84 L170 79 M142 93 L170 98',
  ]
</script>

<div id="home-scene" class="relative w-full max-w-xs select-none" aria-hidden="true">
  <div class="sheet relative -rotate-2 border-2 border-riso-ink bg-white p-3 shadow-[5px_5px_0_var(--color-riso-pink)]">
    <svg viewBox="0 0 200 130" class="block w-full" fill="none" stroke-linecap="round" stroke-linejoin="round">
      {#each LINES as d, i}
        <path {d} pathLength="1" class="line" style="animation-delay:{i * 1.3}s" stroke="#263A6E" stroke-width="4.5" />
      {/each}
      <!-- the imposter guessed: a line that is not part of a cat -->
      <path d="M68 56 q8 -11 16 0 t16 0 t16 0 t16 0" pathLength="1" class="line" style="animation-delay:{LINES.length * 1.3}s" stroke="#FF48B0" stroke-width="4.5" />
    </svg>
    <span class="stamp absolute -right-3 -top-3 rotate-6 border-2 border-riso-stamp bg-white px-1.5 py-0.5 font-stamp text-[0.65rem] uppercase tracking-widest text-riso-stamp">
      who drew this?
    </span>
  </div>

  <div class="-mt-3 flex items-end justify-center -space-x-1.5">
    {#each PLAYERS as p, i}
      <div class="relative" style="z-index:{i % 2}">
        <span class="react absolute -top-7 left-1/2 h-9 w-9 -translate-x-1/2" style="animation-delay:{p.at}s">
          <Sticker id={p.react} />
        </span>
        <div class="bob" style="animation-delay:{i * 0.35}s"><Marker player={p} size={64} /></div>
      </div>
    {/each}
  </div>
</div>

<style>
  .line {
    stroke-dasharray: 1;
    animation: draw 9s ease-in-out infinite both;
  }
  .react {
    opacity: 0;
    animation: react 7s ease-out infinite both;
  }
  .bob {
    animation: bob 3.2s ease-in-out infinite;
  }

  @keyframes draw {
    0% { stroke-dashoffset: 1; }
    12%, 88% { stroke-dashoffset: 0; }
    96%, 100% { stroke-dashoffset: 1; }
  }
  @keyframes react {
    0% { opacity: 0; transform: translate(-50%, 8px) scale(0.4) rotate(-10deg); }
    6% { opacity: 1; transform: translate(-50%, -4px) scale(1.15) rotate(5deg); }
    10%, 24% { opacity: 1; transform: translate(-50%, 0) scale(1) rotate(-4deg); }
    32%, 100% { opacity: 0; transform: translate(-50%, -14px) scale(0.9) rotate(-4deg); }
  }
  @keyframes bob {
    50% { transform: translateY(-3px); }
  }

  /* for people who asked for less motion: the finished drawing and a few stickers, held still */
  @media (prefers-reduced-motion: reduce) {
    .line { animation: none; stroke-dashoffset: 0; }
    .bob { animation: none; }
    .react { animation: none; opacity: 1; transform: translate(-50%, 0); }
  }
</style>

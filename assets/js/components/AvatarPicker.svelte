<script>
  import AvatarEditor from './AvatarEditor.svelte'
  import Marker from './Marker.svelte'
  import Modal from './Modal.svelte'
  import Button from './Button.svelte'

  // "Your look": the face you will have, and a way to change it, for before you are in a room
  // (the game gives you your colour and shape once you are). `onchange(face)` is called with
  // every change.
  let { face, onchange } = $props()

  let open = $state(false)
  const body = { color: '#ffe800', name: '' }
</script>

<div class="relative flex items-center gap-4 overflow-hidden rounded-[3px] border-2 border-riso-ink bg-riso-yellow/35 p-3 pr-4">
  <!-- a halftone corner, like the sheet on the first screen -->
  <span aria-hidden="true" class="pointer-events-none absolute -right-6 -top-6 h-24 w-24 rounded-full bg-riso-pink/30 [mask-image:radial-gradient(circle,#000_1.2px,transparent_1.6px)] [mask-size:6px_6px]"></span>
  <span class="-rotate-3 rounded-full border-2 border-riso-ink bg-white p-1 shadow-[3px_3px_0_var(--color-riso-pink)]">
    <Marker player={{ ...body, avatar: face }} size={72} />
  </span>
  <div class="relative min-w-0 flex-1">
    <div class="font-display text-base leading-tight">Your look</div>
    <div class="font-stamp text-xs text-riso-muted">Eyes, mouth and a hat.</div>
  </div>
  <Button id="avatar-open" class="relative shrink-0 bg-white px-4 py-2 font-stamp text-sm" onclick={() => (open = true)}>Change</Button>
</div>

{#if open}
  <Modal id="avatar-dialog" title="Your look" onclose={() => (open = false)}>
    <AvatarEditor {face} {onchange} />
    {#snippet footer()}
      <Button id="avatar-done" variant="yellow" class="w-full py-3 text-lg" onclick={() => (open = false)}>Done</Button>
    {/snippet}
  </Modal>
{/if}

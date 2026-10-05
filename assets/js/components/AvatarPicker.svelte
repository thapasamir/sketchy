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

<div class="flex items-center gap-4 rounded-[3px] border-2 border-riso-line bg-white/60 p-3">
  <Marker player={{ ...body, avatar: face }} size={56} />
  <div class="min-w-0 flex-1">
    <div class="font-stamp text-xs uppercase tracking-widest">Your look</div>
    <div class="font-stamp text-xs text-riso-muted">Eyes, mouth and a hat.</div>
  </div>
  <Button id="avatar-open" class="shrink-0 px-4 py-2 font-stamp text-sm" onclick={() => (open = true)}>Change</Button>
</div>

{#if open}
  <Modal id="avatar-dialog" title="Your look" onclose={() => (open = false)}>
    <AvatarEditor {face} {onchange} />
    {#snippet footer()}
      <Button id="avatar-done" variant="yellow" class="w-full py-3 text-lg" onclick={() => (open = false)}>Done</Button>
    {/snippet}
  </Modal>
{/if}

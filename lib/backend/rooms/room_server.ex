defmodule Backend.Rooms.RoomServer do
  @moduledoc """
  One process per room. It owns that room's `Room` struct and is the only thing allowed to change it.

  Other code never touches the struct directly: it sends this process a message
  (`GenServer.call/2`) and the process handles messages one at a time, in order.
  That is why no locks are needed.

  It also knows who is *really* connected. Each player's WebSocket channel process registers with
  `connect/3`, and this process monitors it (`Process.monitor/1`): when the channel dies for any
  reason (tab closed, wifi dropped, crash) the BEAM sends us a `:DOWN` message. A player who is
  away stays in the room for a grace period so a refresh or a network blip doesn't cost them
  their seat; after that they are removed. When the last player is gone the room closes itself.
  """

  # :temporary = if this process crashes, do NOT restart it. A restart would start from empty
  # state (the players would be gone), so a crashed room should just close.
  use GenServer, restart: :temporary

  require Logger

  alias Backend.Rooms.{Dealer, Room, Voting}

  # --- Client API: runs in the CALLER's process ---

  def start_link(opts) do
    code = Keyword.fetch!(opts, :code)
    GenServer.start_link(__MODULE__, opts, name: via(code))
  end

  def get_state(code), do: call(code, :get_state)
  def join(code, player_id, name), do: call(code, {:join, player_id, name})

  @doc "Register `pid` (a channel process) as one of `player_id`'s live connections."
  def connect(code, player_id, pid), do: call(code, {:connect, player_id, pid})

  @doc "The player leaves on purpose: removed immediately, no grace period."
  def leave(code, player_id), do: call(code, {:leave, player_id})

  def update_settings(code, player_id, changes),
    do: call(code, {:update_settings, player_id, changes})

  def start_game(code, player_id), do: call(code, {:start_game, player_id})

  @doc "The current drawer sends a stroke event. `origin` is the sending channel (it already has the stroke)."
  def draw(code, player_id, params, origin), do: call(code, {:draw, player_id, params, origin})

  def undo(code, player_id, origin), do: call(code, {:undo, player_id, origin})

  @doc "Vote for who you think the imposter is (while voting is open)."
  def vote(code, player_id, target_id), do: call(code, {:vote, player_id, target_id})

  @doc "The caught imposter's one guess at the word."
  def guess(code, player_id, text), do: call(code, {:guess, player_id, text})

  @doc "The current drawer hands the pen on early."
  def finish_turn(code, player_id), do: call(code, {:finish_turn, player_id})
  def set_ready(code, player_id, ready?), do: call(code, {:set_ready, player_id, ready?})

  @doc "The host removes another player. They are told, and may rejoin like anyone else."
  def kick(code, host_id, target_id), do: call(code, {:kick, host_id, target_id})

  # Registry.lookup is a cheap in-memory lookup: code -> pid
  defp call(code, message) do
    case Registry.lookup(Backend.RoomRegistry, code) do
      [{pid, _value}] -> call_pid(pid, message)
      [] -> {:error, :room_not_found}
    end
  end

  # The Registry forgets a dead process slightly AFTER it dies, and a room that is closing can
  # exit while we're mid-call. Either way the answer is "that room is gone", not a crash.
  defp call_pid(pid, message) do
    GenServer.call(pid, message)
  catch
    :exit, {reason, _call} when reason in [:noproc, :normal, :shutdown] ->
      {:error, :room_not_found}
  end

  # Registering under {:via, Registry, ...} makes the code the process's name.
  # Starting a second process with the same code fails with {:error, {:already_started, pid}}.
  defp via(code), do: {:via, Registry, {Backend.RoomRegistry, code}}

  # --- Callbacks: run INSIDE the room process ---
  #
  # State is a map:
  #   room     - the Room struct (pure data, what players see)
  #   grace_ms - how long an away player keeps their seat
  #   monitors - %{monitor_ref => player_id}, one entry per live channel connection
  #   expiry   - %{player_id => {token, timer}}, a pending "remove if still away" timer
  #   reveal_ms - how long the reveal lasts
  #   vote_ms / guess_ms - how long the vote, and the caught imposter's guess, last
  #   turn_ms - fixed turn length (tests only); normally the room's draw_time setting is used
  #   drawer_away_ms - how long a turn waits for a drawer who dropped before moving on
  #   phase_timer - {token, timer} for whatever ends the current phase/turn (only one at a time)

  @impl true
  def init(opts) do
    code = Keyword.fetch!(opts, :code)
    host = Keyword.fetch!(opts, :host)

    room = code |> Room.new(host.id) |> Room.add_player(host.id, host.name)
    room = %{room | reveal_ms: Keyword.fetch!(opts, :reveal_ms)}

    state = %{
      room: room,
      grace_ms: Keyword.fetch!(opts, :grace_ms),
      reveal_ms: Keyword.fetch!(opts, :reveal_ms),
      turn_ms: Keyword.get(opts, :turn_ms),
      drawer_away_ms: Keyword.get(opts, :drawer_away_ms, 8_000),
      vote_ms: Keyword.get(opts, :vote_ms, 30_000),
      guess_ms: Keyword.get(opts, :guess_ms, 20_000),
      phase_timer: nil,
      monitors: %{},
      expiry: %{}
    }

    Logger.info("Room #{code} created by #{host.name}")
    # The host isn't connected until their channel joins. If that never happens, the room closes.
    {:ok, schedule_expiry(state, host.id)}
  end

  # Pattern matching on the message picks the clause, like a router for messages.
  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, {:ok, state.room}, state}

  # Check-and-add happens inside ONE message, so two people grabbing the last seat or the same
  # name at the same moment are handled one after the other. The second one is told no.
  # Joining reserves a seat quietly; everyone is told when that player's channel connects.
  def handle_call({:join, player_id, name}, _from, state) do
    case Room.join(state.room, player_id, name) do
      {:ok, room} ->
        {:reply, {:ok, room}, state |> put_room(room) |> schedule_expiry(player_id)}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:connect, player_id, pid}, _from, state) do
    if Room.member?(state.room, player_id) do
      ref = Process.monitor(pid)

      state =
        state
        |> Map.update!(:monitors, &Map.put(&1, ref, player_id))
        |> cancel_expiry(player_id)
        |> put_room(Room.set_connected(state.room, player_id, true))
        |> restore_drawer_timer(player_id)

      broadcast(state.room)
      {:reply, {:ok, state.room}, state}
    else
      {:reply, {:error, :not_a_member}, state}
    end
  end

  def handle_call({:leave, player_id}, _from, state) do
    case remove_player(state, player_id) do
      {:open, state} -> {:reply, :ok, state}
      {:closed, state} -> {:stop, :normal, :ok, state}
    end
  end

  def handle_call({:update_settings, player_id, changes}, _from, state) do
    apply_change(state, Room.update_settings(state.room, player_id, changes))
  end

  def handle_call({:set_ready, player_id, ready?}, _from, state) do
    apply_change(state, Room.set_ready(state.room, player_id, ready?))
  end

  def handle_call({:kick, host_id, target_id}, _from, state) do
    case Room.can_kick(state.room, host_id, target_id) do
      :ok ->
        # tell the kicked player's channel first, then everyone else sees the shorter list
        Phoenix.PubSub.broadcast(
          Backend.PubSub,
          "rooms:" <> state.room.code,
          {:player_kicked, target_id}
        )

        # the host always remains, so the room can't be empty here
        {:open, state} = remove_player(state, target_id)
        {:reply, :ok, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  # The server does the dealing (random word + random imposter). Room only checks the rules
  # and, if they pass, stores the deal. A refused start just throws the deal away.
  def handle_call({:start_game, player_id}, _from, state) do
    case Room.start_game(state.room, player_id, Dealer.deal(state.room)) do
      {:ok, room} ->
        state = state |> put_room(room) |> set_phase_timer(:end_reveal, state.reveal_ms)
        broadcast(room)
        {:reply, {:ok, room}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  # Strokes are streamed to the other channels as they arrive; the whole room is NOT re-sent for
  # every few points. The drawer's own channel already drew it, so it is skipped (`origin`).
  def handle_call({:draw, player_id, params, origin}, _from, state) do
    case Room.draw(state.room, player_id, params) do
      {:ok, room, event} ->
        broadcast_draw(room, origin, event)
        {:reply, :ok, put_room(state, room)}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:undo, player_id, origin}, _from, state) do
    case Room.undo(state.room, player_id) do
      {:ok, room, event} ->
        broadcast_draw(room, origin, event)
        {:reply, {:ok, event}, put_room(state, room)}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  # A vote may be the last one needed, in which case the vote closes on the spot.
  def handle_call({:vote, player_id, target_id}, _from, state) do
    case Voting.vote(state.room, player_id, target_id) do
      {:ok, room} ->
        state = state |> put_room(room) |> close_voting_if_done()
        broadcast(state.room)
        {:reply, :ok, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:guess, player_id, text}, _from, state) do
    case Voting.guess(state.room, player_id, text) do
      {:ok, room} ->
        state = state |> put_room(room) |> arm_phase_timer()
        broadcast(state.room)
        {:reply, :ok, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:finish_turn, player_id}, _from, state) do
    if Room.drawer?(state.room, player_id) do
      {:reply, :ok, advance_turn(state)}
    else
      {:reply, {:error, :not_your_turn}, state}
    end
  end

  # A channel process died. If that was the player's last connection they are now "away".
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _monitors} ->
        {:noreply, state}

      {player_id, monitors} ->
        state = %{state | monitors: monitors}

        if connected?(state, player_id) do
          {:noreply, state}
        else
          state =
            state
            |> put_room(Room.set_connected(state.room, player_id, false))
            |> schedule_expiry(player_id)
            |> hurry_away_drawer(player_id)
            |> close_voting_if_done()

          broadcast(state.room)
          {:noreply, state}
        end
    end
  end

  # The reveal is over: everyone has had time to read their card, so drawing starts.
  def handle_info({:end_reveal, token}, %{phase_timer: {token, _timer}} = state) do
    case Room.end_reveal(state.room, now_ms(), turn_ms(state)) do
      {:ok, room} ->
        state = state |> put_room(room) |> arm_phase_timer()
        broadcast(state.room)
        {:noreply, state}

      {:error, _reason} ->
        {:noreply, %{state | phase_timer: nil}}
    end
  end

  # The turn's time is up: pass the pen on.
  def handle_info({:end_turn, token}, %{phase_timer: {token, _timer}} = state) do
    {:noreply, advance_turn(state)}
  end

  # The vote time is up. Whoever didn't vote simply didn't.
  def handle_info({:end_vote, token}, %{phase_timer: {token, _timer}} = state) do
    state = close_voting(state)
    broadcast(state.room)
    {:noreply, state}
  end

  # The caught imposter ran out of time to guess.
  def handle_info({:end_guess, token}, %{phase_timer: {token, _timer}} = state) do
    {:ok, room} = Voting.give_up(state.room)
    state = state |> put_room(room) |> arm_phase_timer()
    broadcast(state.room)
    {:noreply, state}
  end

  # A timer that has since been replaced or cancelled: ignore it.
  def handle_info({tag, _stale_token}, state)
      when tag in [:end_reveal, :end_turn, :end_vote, :end_guess],
      do: {:noreply, state}

  # The grace period ended. The token check ignores a timer that a reconnect has since replaced.
  def handle_info({:expire, player_id, token}, state) do
    with %{^player_id => {^token, _timer}} <- state.expiry,
         :lobby <- state.room.phase do
      case remove_player(state, player_id) do
        {:open, state} -> {:noreply, state}
        {:closed, state} -> {:stop, :normal, state}
      end
    else
      _ -> {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Room #{state.room.code} closed (#{inspect(reason)})")
  end

  # --- helpers ---

  defp apply_change(state, {:ok, room}) do
    state = put_room(state, room)
    broadcast(room)
    {:reply, {:ok, room}, state}
  end

  defp apply_change(state, {:error, _reason} = error), do: {:reply, error, state}

  defp put_room(state, room), do: %{state | room: room}

  defp connected?(state, player_id), do: player_id in Map.values(state.monitors)

  defp remove_player(state, player_id) do
    # stop watching this player's channels so their later exit isn't treated as a disconnect
    {theirs, others} = Enum.split_with(state.monitors, fn {_ref, id} -> id == player_id end)
    Enum.each(theirs, fn {ref, _id} -> Process.demonitor(ref, [:flush]) end)

    state = %{state | monitors: Map.new(others)} |> cancel_expiry(player_id)
    room = Room.remove_player(state.room, player_id)
    state = put_room(state, room)

    cond do
      map_size(room.players) == 0 ->
        {:closed, state}

      drawer_left?(state, player_id) ->
        {:open, advance_turn(state)}

      true ->
        # if they were the last one the vote was waiting for, it can close now
        state = close_voting_if_done(state)
        broadcast(state.room)
        {:open, state}
    end
  end

  # --- turns ---

  defp now_ms, do: System.system_time(:millisecond)

  defp turn_ms(state), do: state.turn_ms || state.room.settings.draw_time * 1000

  # Replace whatever timer was pending with one that sends `{tag, token}` after `ms`.
  # The token lets a message from a replaced timer that already fired be recognised and ignored.
  defp set_phase_timer(state, tag, ms) do
    with {_token, timer} <- state.phase_timer, do: Process.cancel_timer(timer)
    token = make_ref()
    %{state | phase_timer: {token, Process.send_after(self(), {tag, token}, ms)}}
  end

  defp clear_phase_timer(state) do
    with {_token, timer} <- state.phase_timer, do: Process.cancel_timer(timer)
    %{state | phase_timer: nil}
  end

  # After the room moved to a new phase (or turn): start the timer that will end it, or, when
  # nothing is timed (the lobby, the result), stop timing.
  defp arm_phase_timer(%{room: %{phase: :drawing} = room} = state),
    do: set_phase_timer(state, :end_turn, Room.turn_ms_left(room, now_ms()))

  defp arm_phase_timer(%{room: %{phase: :voting, game: game}} = state),
    do: set_phase_timer(state, :end_vote, max(game.vote_ends_at - now_ms(), 0))

  defp arm_phase_timer(%{room: %{phase: :guess, game: game}} = state),
    do: set_phase_timer(state, :end_guess, max(game.guess_ends_at - now_ms(), 0))

  defp arm_phase_timer(state), do: clear_phase_timer(state)

  defp close_voting_if_done(%{room: %{phase: :voting}} = state) do
    if Voting.all_voted?(state.room), do: close_voting(state), else: state
  end

  defp close_voting_if_done(state), do: state

  # Count the votes. Either the imposter was caught (and gets a guess) or the round is over.
  defp close_voting(state) do
    {:ok, room} = Voting.close(state.room, now_ms(), state.guess_ms)
    state |> put_room(room) |> arm_phase_timer()
  end

  defp advance_turn(state) do
    # A stroke still being drawn when the turn ends will never get its "end" from the drawer (it
    # would be refused: it's no longer their turn). Close it for everyone, or watchers would be
    # left with a stroke that never finishes.
    unfinished = state.room.game.open_stroke
    room = Room.next_turn(state.room, now_ms(), turn_ms(state), state.vote_ms)
    state = state |> put_room(room) |> arm_phase_timer()
    if unfinished, do: broadcast_draw(room, nil, %{type: "end", id: unfinished})
    broadcast(room)
    state
  end

  defp drawer_left?(state, player_id) do
    state.room.phase == :drawing and state.room.game.turn != nil and
      state.room.game.turn.player_id == player_id
  end

  # The drawer dropped (closed the tab, lost wifi, or is just refreshing). Everyone else
  # shouldn't wait out a whole turn, but a refresh shouldn't cost the turn either: give them a
  # short window, and `restore_drawer_timer/2` gives the time back if they return.
  defp hurry_away_drawer(state, player_id) do
    if Room.drawer?(state.room, player_id) do
      left = Room.turn_ms_left(state.room, now_ms())
      set_phase_timer(state, :end_turn, min(left, state.drawer_away_ms))
    else
      state
    end
  end

  defp restore_drawer_timer(state, player_id) do
    if Room.drawer?(state.room, player_id) do
      set_phase_timer(state, :end_turn, Room.turn_ms_left(state.room, now_ms()))
    else
      state
    end
  end

  defp broadcast_draw(room, origin, event) do
    Phoenix.PubSub.broadcast(
      Backend.PubSub,
      "rooms:" <> room.code,
      {:draw_event, origin, event}
    )
  end

  defp schedule_expiry(state, player_id) do
    state = cancel_expiry(state, player_id)
    token = make_ref()
    timer = Process.send_after(self(), {:expire, player_id, token}, state.grace_ms)
    %{state | expiry: Map.put(state.expiry, player_id, {token, timer})}
  end

  defp cancel_expiry(state, player_id) do
    case Map.pop(state.expiry, player_id) do
      {nil, _expiry} ->
        state

      {{_token, timer}, expiry} ->
        Process.cancel_timer(timer)
        %{state | expiry: expiry}
    end
  end

  # Tell everyone watching this room. PubSub = "publish to a topic, every subscriber gets a copy".
  # The room process doesn't know or care who is listening (channels, tests, ...).
  defp broadcast(room) do
    Phoenix.PubSub.broadcast(Backend.PubSub, "rooms:" <> room.code, {:room_updated, room})
  end
end

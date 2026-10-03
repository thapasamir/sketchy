defmodule Backend.Rooms.Room do
  @moduledoc """
  The state of one room. Plain data plus pure functions: no processes, no side effects.

  Every function takes a room and returns a new room (data is immutable).
  `Backend.Rooms.RoomServer` is the process that holds the current value.
  """

  @max_players 8
  @min_players 3
  @round_range 2..4
  @draw_time_range 30..90//10

  # One colour per seat, so everyone can tell who drew what. Eight seats, eight colours.
  @colors ~w(#ff48b0 #0078bf #ff7a1a #14a76c #8a4fd6 #e63946 #c99700 #1fb5b5)

  # Limits on what one browser may send. The server never trusts the client's idea of "reasonable".
  @brush_sizes [1, 2, 3]
  @max_points_per_batch 80
  @max_points_per_stroke 3_000
  @max_strokes_per_turn 30
  @max_strokes 600

  defstruct code: nil,
            host_id: nil,
            phase: :lobby,
            players: %{},
            settings: %{rounds: 3, draw_time: 60},
            # The secret part of a round (word, imposter). NEVER put this in `to_public/1`.
            game: nil,
            reveal_ms: 8_000,
            created_at: nil

  @type t :: %__MODULE__{
          code: String.t(),
          host_id: String.t(),
          phase: atom(),
          players: %{String.t() => map()},
          settings: map(),
          created_at: DateTime.t()
        }

  def new(code, host_id) do
    %__MODULE__{code: code, host_id: host_id, created_at: DateTime.utc_now()}
  end

  def add_player(%__MODULE__{} = room, player_id, name) do
    player = %{
      id: player_id,
      name: name,
      connected?: false,
      ready?: false,
      joined_at: DateTime.utc_now()
    }

    %{room | players: Map.put(room.players, player_id, player)}
  end

  @doc """
  The rules for joining, kept pure so they are trivial to test.
  Returns `{:ok, room}` or `{:error, reason}`.
  """
  def join(%__MODULE__{} = room, player_id, name) do
    cond do
      room.phase != :lobby -> {:error, :game_in_progress}
      player_count(room) >= @max_players -> {:error, :room_full}
      name_taken?(room, name) -> {:error, :name_taken}
      true -> {:ok, add_player(room, player_id, name)}
    end
  end

  def name_taken?(%__MODULE__{} = room, name) do
    wanted = String.downcase(name)
    Enum.any?(room.players, fn {_id, p} -> String.downcase(p.name) == wanted end)
  end

  def set_connected(%__MODULE__{} = room, player_id, connected?) do
    case room.players do
      %{^player_id => player} ->
        %{room | players: Map.put(room.players, player_id, %{player | connected?: connected?})}

      _ ->
        room
    end
  end

  @doc """
  Remove a player. If the host left, the longest-present connected player becomes host
  (or the longest-present player if nobody is connected). An empty room has `host_id: nil`.
  """
  def remove_player(%__MODULE__{} = room, player_id) do
    players = Map.delete(room.players, player_id)
    host_id = if player_id == room.host_id, do: next_host(players), else: room.host_id
    room = %{room | players: players, host_id: host_id}

    if room.game do
      queue = Enum.reject(room.game.queue, fn {_lap, id} -> id == player_id end)
      %{room | game: %{room.game | queue: queue}}
    else
      room
    end
  end

  defp next_host(players) when map_size(players) == 0, do: nil

  defp next_host(players) do
    candidates = Map.values(players)
    pool = Enum.filter(candidates, & &1.connected?)
    pool = if pool == [], do: candidates, else: pool
    Enum.min_by(pool, & &1.joined_at, DateTime).id
  end

  @doc "Host-only. `changes` may hold `:rounds` and/or `:draw_time` as integers."
  def update_settings(%__MODULE__{} = room, player_id, changes) do
    with :ok <- check_host(room, player_id),
         :ok <- check_lobby(room),
         {:ok, settings} <- merge_settings(room.settings, changes) do
      # Everyone said "ready" to the OLD settings, so a real change asks them again.
      players = if settings == room.settings, do: room.players, else: reset_ready(room.players)
      {:ok, %{room | settings: settings, players: players}}
    end
  end

  @doc "A non-host player says they are (or are no longer) ready to start."
  def set_ready(%__MODULE__{} = room, player_id, ready?) when is_boolean(ready?) do
    with :ok <- check_lobby(room),
         :ok <- check_member(room, player_id),
         :ok <- check_not_host(room, player_id) do
      player = %{room.players[player_id] | ready?: ready?}
      {:ok, %{room | players: Map.put(room.players, player_id, player)}}
    end
  end

  def set_ready(_room, _player_id, _ready), do: {:error, :invalid_ready}

  @doc "Host-only. Returns `:ok` if `host_id` may remove `target_id`; the removal itself is `remove_player/2`."
  def can_kick(%__MODULE__{} = room, host_id, target_id) do
    with :ok <- check_host(room, host_id),
         :ok <- check_lobby(room),
         :ok <- check_member(room, target_id),
         :ok <- check_not_host(room, target_id) do
      :ok
    end
  end

  @doc """
  Host-only. Starts the game once enough players are connected and ready. `deal` is the secret
  for the round (see `Backend.Rooms.Dealer`); it is passed in so this function stays pure.
  The room moves to the `:reveal` phase, where everyone looks at their own card.
  """
  def start_game(%__MODULE__{} = room, player_id, deal) do
    with :ok <- check_host(room, player_id),
         :ok <- check_lobby(room),
         :ok <- check_enough_players(room),
         :ok <- check_everyone_ready(room) do
      game = %{
        round: 1,
        imposter_id: deal.imposter_id,
        imposter_history: deal.imposter_history,
        entry: deal.entry,
        hint: deal.hint,
        used_words: deal.used_words,
        turn_order: deal.turn_order,
        colors: assign_colors(room.players),
        # the drawing: newest stroke first (cheap to add to), see `strokes_public/1`
        strokes: [],
        open_stroke: nil,
        queue: [],
        turn: nil,
        turn_n: 0
      }

      {:ok, %{room | phase: :reveal, game: game}}
    end
  end

  @doc """
  Move on from the reveal to the drawing phase and start the first turn. `now` is the current
  time in ms and `turn_ms` how long a turn lasts; they are passed in so this stays pure.
  """
  def end_reveal(%__MODULE__{phase: :reveal} = room, now, turn_ms) do
    # every lap, everyone draws once, in the same order
    queue = for lap <- 1..room.settings.rounds, id <- room.game.turn_order, do: {lap, id}
    room = %{room | phase: :drawing, game: %{room.game | queue: queue}}
    {:ok, next_turn(room, now, turn_ms)}
  end

  def end_reveal(%__MODULE__{}, _now, _turn_ms), do: {:error, :not_revealing}

  @doc """
  Hand the pen to the next player in the queue. Anyone who has left, or is away right now, is
  skipped. When nobody is left the drawing is finished and the room moves on to voting.
  """
  def next_turn(%__MODULE__{game: game} = room, now, turn_ms) do
    {next, rest} = pop_drawer(game.queue, room)

    case next do
      nil ->
        %{room | phase: :voting, game: %{game | queue: [], turn: nil, open_stroke: nil}}

      {lap, player_id} ->
        turn = %{player_id: player_id, lap: lap, n: game.turn_n + 1, ends_at: now + turn_ms}
        %{room | game: %{game | queue: rest, turn: turn, turn_n: turn.n, open_stroke: nil}}
    end
  end

  defp pop_drawer([], _room), do: {nil, []}

  defp pop_drawer([{_lap, id} = next | rest], room) do
    case room.players do
      %{^id => %{connected?: true}} -> {next, rest}
      _ -> pop_drawer(rest, room)
    end
  end

  @doc "Is it `player_id`'s turn to draw right now?"
  def drawer?(%__MODULE__{phase: :drawing, game: %{turn: %{player_id: id}}}, id), do: true
  def drawer?(%__MODULE__{}, _player_id), do: false

  @doc "Milliseconds left in the current turn (0 if there is none)."
  def turn_ms_left(%__MODULE__{game: %{turn: %{ends_at: ends_at}}}, now),
    do: max(ends_at - now, 0)

  def turn_ms_left(%__MODULE__{}, _now), do: 0

  @doc """
  The current drawer sends a drawing event: `%{"type" => "start" | "points" | "end", ...}`.
  Returns `{:ok, room, event}` where `event` is the cleaned version that is safe to show everyone
  else, or `{:error, reason}`. Everything from the browser is checked and clamped here.
  """
  def draw(%__MODULE__{} = room, player_id, %{"type" => "start"} = params) do
    with :ok <- check_drawer(room, player_id),
         {:ok, id} <- parse_id(params),
         {:ok, size} <- parse_size(params),
         {:ok, [point]} <- clean_points([[params["x"], params["y"]]]),
         :ok <- check_stroke_budget(room) do
      game = room.game

      stroke = %{
        id: id,
        player_id: player_id,
        turn: game.turn.n,
        color: game.colors[player_id],
        size: size,
        points: [point],
        count: 1
      }

      room = %{room | game: %{game | strokes: [stroke | game.strokes], open_stroke: id}}

      {:ok, room,
       %{
         type: "start",
         id: id,
         player_id: player_id,
         color: stroke.color,
         size: size,
         points: [point]
       }}
    end
  end

  def draw(%__MODULE__{} = room, player_id, %{"type" => "points", "points" => points} = params)
      when is_list(points) and length(points) in 1..@max_points_per_batch do
    with :ok <- check_drawer(room, player_id),
         {:ok, id} <- parse_id(params),
         {:ok, stroke} <- open_stroke(room, id),
         {:ok, clean} <- clean_points(points),
         :ok <- check_stroke_length(stroke, clean) do
      stroke = %{
        stroke
        | points: Enum.reverse(clean, stroke.points),
          count: stroke.count + length(clean)
      }

      room = put_in(room.game.strokes, [stroke | tl(room.game.strokes)])
      {:ok, room, %{type: "points", id: id, points: clean}}
    end
  end

  def draw(%__MODULE__{} = room, player_id, %{"type" => "end"} = params) do
    with :ok <- check_drawer(room, player_id),
         {:ok, id} <- parse_id(params),
         {:ok, _stroke} <- open_stroke(room, id) do
      {:ok, put_in(room.game.open_stroke, nil), %{type: "end", id: id}}
    end
  end

  def draw(%__MODULE__{}, _player_id, _params), do: {:error, :invalid_event}

  @doc "The drawer takes back their most recent stroke of THIS turn (never anyone else's)."
  def undo(%__MODULE__{} = room, player_id) do
    with :ok <- check_drawer(room, player_id) do
      case room.game.strokes do
        [%{turn: turn, id: id} | rest] when turn == room.game.turn.n ->
          room = %{room | game: %{room.game | strokes: rest, open_stroke: nil}}
          {:ok, room, %{type: "undo", id: id}}

        _ ->
          {:error, :nothing_to_undo}
      end
    end
  end

  @doc "The whole drawing so far, oldest stroke first, as plain data for a browser."
  def strokes_public(%__MODULE__{game: nil}), do: []

  def strokes_public(%__MODULE__{game: game}) do
    game.strokes
    |> Enum.reverse()
    |> Enum.map(fn s ->
      %{
        id: s.id,
        player_id: s.player_id,
        color: s.color,
        size: s.size,
        points: Enum.reverse(s.points)
      }
    end)
  end

  defp check_drawer(room, player_id) do
    if drawer?(room, player_id), do: :ok, else: {:error, :not_your_turn}
  end

  defp parse_id(%{"id" => id}) when is_binary(id) and byte_size(id) in 1..40, do: {:ok, id}
  defp parse_id(_), do: {:error, :invalid_event}

  defp parse_size(%{"size" => size}) when size in @brush_sizes, do: {:ok, size}
  defp parse_size(_), do: {:error, :invalid_event}

  # a stroke that is still being drawn, and only the one the drawer names
  defp open_stroke(%{game: %{open_stroke: id, strokes: [%{id: id} = stroke | _]}}, id),
    do: {:ok, stroke}

  defp open_stroke(_room, _id), do: {:error, :no_such_stroke}

  defp clean_points(points) do
    Enum.reduce_while(points, {:ok, []}, fn
      [x, y], {:ok, acc} when is_number(x) and is_number(y) ->
        {:cont, {:ok, [[unit(x), unit(y)] | acc]}}

      _, _ ->
        {:halt, {:error, :invalid_event}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  # the canvas is a unit square: clamp into it, and 4 decimals is plenty (it is a drawing)
  defp unit(n), do: Float.round(min(max(n * 1.0, 0.0), 1.0), 4)

  defp check_stroke_budget(%{game: game}) do
    this_turn = game.strokes |> Enum.take_while(&(&1.turn == game.turn.n)) |> length()

    cond do
      this_turn >= @max_strokes_per_turn -> {:error, :too_many_strokes}
      length(game.strokes) >= @max_strokes -> {:error, :canvas_full}
      true -> :ok
    end
  end

  defp check_stroke_length(stroke, clean) do
    if stroke.count + length(clean) <= @max_points_per_stroke,
      do: :ok,
      else: {:error, :stroke_too_long}
  end

  defp assign_colors(players) do
    players
    |> Map.values()
    |> Enum.sort_by(& &1.joined_at, DateTime)
    |> Enum.zip(@colors)
    |> Map.new(fn {player, color} -> {player.id, color} end)
  end

  @doc """
  What THIS player is allowed to know about the round, or nil in the lobby.
  The imposter gets the category and one hint, never the word. Everyone else gets the word.
  """
  def secret_for(%__MODULE__{game: nil}, _player_id), do: nil

  def secret_for(%__MODULE__{game: game} = room, player_id) do
    cond do
      not member?(room, player_id) ->
        nil

      player_id == game.imposter_id ->
        %{role: "imposter", category: game.entry.category, hint: game.hint}

      true ->
        %{role: "crew", category: game.entry.category, word: game.entry.word}
    end
  end

  defp check_host(room, player_id) do
    if room.host_id == player_id, do: :ok, else: {:error, :not_host}
  end

  defp check_lobby(room) do
    if room.phase == :lobby, do: :ok, else: {:error, :game_in_progress}
  end

  defp check_member(room, player_id) do
    if member?(room, player_id), do: :ok, else: {:error, :not_a_member}
  end

  # the host can't be kicked or "ready": they are the one pressing start
  defp check_not_host(room, player_id) do
    if player_id == room.host_id, do: {:error, :host_cannot}, else: :ok
  end

  # Players who are away don't hold up the start; everyone else must be ready.
  defp check_everyone_ready(room) do
    waiting =
      Enum.any?(room.players, fn {id, p} ->
        id != room.host_id and p.connected? and not p.ready?
      end)

    if waiting, do: {:error, :not_all_ready}, else: :ok
  end

  defp reset_ready(players) do
    Map.new(players, fn {id, p} -> {id, %{p | ready?: false}} end)
  end

  defp check_enough_players(room) do
    connected = Enum.count(room.players, fn {_id, p} -> p.connected? end)
    if connected >= @min_players, do: :ok, else: {:error, :not_enough_players}
  end

  defp merge_settings(settings, changes) do
    rounds = Map.get(changes, :rounds, settings.rounds)
    draw_time = Map.get(changes, :draw_time, settings.draw_time)

    if valid_in?(rounds, @round_range) and valid_in?(draw_time, @draw_time_range) do
      {:ok, %{settings | rounds: rounds, draw_time: draw_time}}
    else
      {:error, :invalid_settings}
    end
  end

  defp valid_in?(value, range), do: is_integer(value) and value in range

  def member?(%__MODULE__{} = room, player_id), do: Map.has_key?(room.players, player_id)

  def player_count(%__MODULE__{} = room), do: map_size(room.players)

  @doc """
  The version of the room that is safe to send to browsers.

  Built by hand on purpose: later the room will hold secrets (the word, who the imposter is),
  and an explicit allow-list means a new field is never sent by accident.
  """
  def to_public(%__MODULE__{} = room, now \\ System.system_time(:millisecond)) do
    colors = (room.game && room.game.colors) || %{}

    players =
      room.players
      |> Map.values()
      |> Enum.sort_by(& &1.joined_at, DateTime)
      |> Enum.map(
        &%{
          id: &1.id,
          name: &1.name,
          connected: &1.connected?,
          ready: &1.ready?,
          color: colors[&1.id]
        }
      )

    %{
      code: room.code,
      host_id: room.host_id,
      phase: room.phase,
      round: room.game && room.game.round,
      reveal_seconds: div(room.reveal_ms, 1000),
      turn: turn_public(room, now),
      settings: room.settings,
      min_players: @min_players,
      max_players: @max_players,
      players: players
    }
  end

  defp turn_public(%__MODULE__{game: %{turn: %{} = turn}} = room, now) do
    %{
      player_id: turn.player_id,
      lap: turn.lap,
      laps: room.settings.rounds,
      # the order everyone draws in, every lap (not a secret: it is on show at the table)
      order: Enum.filter(room.game.turn_order, &Map.has_key?(room.players, &1)),
      ms_left: turn_ms_left(room, now)
    }
  end

  defp turn_public(_room, _now), do: nil
end

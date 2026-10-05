defmodule Backend.Rooms.Room do
  @moduledoc """
  The state of one room. Plain data plus pure functions: no processes, no side effects.

  Every function takes a room and returns a new room (data is immutable).
  `Backend.Rooms.RoomServer` is the process that holds the current value.
  """

  alias Backend.Rooms.Voting

  @max_players 8
  @min_players 3
  @round_range 2..4
  @draw_time_range 30..90//10

  # How many times everyone draws per word. `:auto` picks by group size, to keep a word to about
  # 5 to 8 turns: a small group needs two goes each to give the vote anything to work with, a
  # big one would drag on.
  @laps_options [:auto, 1, 2]
  @auto_two_laps_up_to 4

  # One colour per seat, so everyone can tell who drew what. Eight seats, eight colours.
  @colors ~w(#ff48b0 #0078bf #ff7a1a #14a76c #8a4fd6 #e63946 #c99700 #1fb5b5)

  # Every colour also has a shape, so nobody has to tell colours apart by eye alone (colour
  # blindness, a dim screen, two similar reds). The browser draws these; the order matches @colors.
  @shapes ~w(circle square triangle diamond star plus hexagon cross)

  @doc "The shape that goes with a seat's colour, or nil for no colour."
  def shape_for(color) do
    case Enum.find_index(@colors, &(&1 == color)) do
      nil -> nil
      i -> Enum.at(@shapes, i)
    end
  end

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
            # `categories`: :all or a list of category names; `difficulty`: :all, :medium or :easy
            # (see `Backend.Words`)
            settings: %{
              rounds: 3,
              draw_time: 30,
              laps: :auto,
              categories: :all,
              difficulty: :all
            },
            # The secret part of a round (word, imposter). NEVER put this in `to_public/1`.
            game: nil,
            # points kept across rounds: %{player_id => integer}
            scores: %{},
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

  # `spectator: true` is someone who arrived after the game began: they watch, and they play from
  # the next round (see `promote_spectators/1`).
  def add_player(%__MODULE__{} = room, player_id, name, opts \\ []) do
    player = %{
      id: player_id,
      name: name,
      connected?: false,
      ready?: false,
      spectator?: Keyword.get(opts, :spectator, false),
      # their face: the one they chose if it checks out, else one made from their id
      avatar: Keyword.get(opts, :avatar) || Backend.Avatar.from_seed(player_id),
      joined_at: DateTime.utc_now()
    }

    %{room | players: Map.put(room.players, player_id, player)}
  end

  @doc """
  A member changes their face (any time: it is only how they look). `face` is as `Backend.Avatar`
  checks it.
  """
  def set_avatar(%__MODULE__{} = room, player_id, face) do
    with :ok <- check_member(room, player_id),
         {:ok, face} <- Backend.Avatar.parse(face) |> avatar_result() do
      player = %{room.players[player_id] | avatar: face}
      {:ok, %{room | players: Map.put(room.players, player_id, player)}}
    end
  end

  defp avatar_result({:ok, face}), do: {:ok, face}
  defp avatar_result(:error), do: {:error, :invalid_avatar}

  @doc """
  The rules for joining, kept pure so they are trivial to test.
  Returns `{:ok, room}` or `{:error, reason}`. Joining after the game has begun is allowed: you
  watch until the next round starts.
  """
  def join(%__MODULE__{} = room, player_id, name, avatar \\ nil) do
    cond do
      player_count(room) >= @max_players -> {:error, :room_full}
      name_taken?(room, name) -> {:error, :name_taken}
      room.phase == :lobby -> {:ok, add_player(room, player_id, name, avatar: avatar)}
      true -> {:ok, add_player(room, player_id, name, spectator: true, avatar: avatar)}
    end
  end

  @doc "Is this player only watching (they joined after the game began)?"
  def spectator?(%__MODULE__{} = room, player_id) do
    match?(%{^player_id => %{spectator?: true}}, room.players)
  end

  @doc """
  The players actually in the game, as `{id, player}`: everyone except spectators. Turns, votes,
  secrets, scoring and colours are all about these.
  """
  def contestants(%__MODULE__{} = room) do
    for {id, %{spectator?: false} = player} <- room.players, do: {id, player}
  end

  @doc """
  A new round is starting: everyone who was watching joins in. They get a colour that nobody
  else is using, and start on no points.
  """
  def promote_spectators(%__MODULE__{game: nil} = room), do: room

  def promote_spectators(%__MODULE__{} = room) do
    newcomers =
      room.players
      |> Map.values()
      |> Enum.filter(& &1.spectator?)
      |> Enum.sort_by(& &1.joined_at, DateTime)

    free = @colors -- Map.values(room.game.colors)
    colors = newcomers |> Enum.zip(free) |> Map.new(fn {player, color} -> {player.id, color} end)

    players = Map.new(room.players, fn {id, p} -> {id, %{p | spectator?: false}} end)
    %{room | players: players, game: %{room.game | colors: Map.merge(room.game.colors, colors)}}
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
      Voting.forget(%{room | game: %{room.game | queue: queue}}, player_id)
    else
      room
    end
  end

  defp next_host(players) when map_size(players) == 0, do: nil

  defp next_host(players) do
    # someone who is playing, if there is anyone; a spectator only as a last resort
    candidates = Map.values(players)
    playing = Enum.reject(candidates, & &1.spectator?)
    candidates = if playing == [], do: candidates, else: playing
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
        turn_n: 0,
        laps: 1,
        next_at: nil,
        names: Map.new(room.players, fn {id, player} -> {id, player.name} end),
        # after the drawing (see `Backend.Rooms.Voting`)
        votes: %{},
        vote_ends_at: nil,
        guess_ends_at: nil,
        accused: nil,
        result: nil
      }

      {:ok, %{room | phase: :reveal, game: game}}
    end
  end

  @doc """
  Move on from the reveal to the drawing phase and start the first turn. `now` is the current
  time in ms and `turn_ms` how long a turn lasts; they are passed in so this stays pure.
  """
  def end_reveal(%__MODULE__{phase: :reveal} = room, now, turn_ms) do
    # everyone draws once per lap, in the order dealt for the round
    laps = laps_for(room)
    queue = for lap <- 1..laps, id <- room.game.turn_order, do: {lap, id}
    room = %{room | phase: :drawing, game: %{room.game | queue: queue, laps: laps}}
    {:ok, next_turn(room, now, turn_ms)}
  end

  def end_reveal(%__MODULE__{}, _now, _turn_ms), do: {:error, :not_revealing}

  @doc """
  Hand the pen to the next player in the queue. Anyone who has left, or is away right now, is
  skipped. When nobody is left the drawing is finished and the room moves on to voting.
  """
  def next_turn(%__MODULE__{game: game} = room, now, turn_ms, vote_ms \\ 45_000) do
    {next, rest} = pop_drawer(game.queue, room)

    case next do
      nil ->
        Voting.open(room, now, vote_ms)

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

  @doc """
  After a round's result: is there another round? There is if the game isn't on its last round
  and enough players are still here to play it.
  """
  def continue?(%__MODULE__{phase: :result, game: game} = room) do
    # (spectators join in at the start of the next round, so they count toward carrying on)
    connected = Enum.count(room.players, fn {_id, p} -> p.connected? end)
    game.round < room.settings.rounds and connected >= @min_players
  end

  def continue?(%__MODULE__{}), do: false

  @doc """
  Start the next round: a fresh deal (word, imposter, drawing order), an empty canvas, and the
  reveal again. Scores, colours and the history that keeps the imposter and words from repeating
  carry over. `deal` comes from `Backend.Rooms.Dealer`, as for the first round.
  """
  def next_round(%__MODULE__{phase: :result, game: game} = room, deal) do
    game = %{
      game
      | round: game.round + 1,
        imposter_id: deal.imposter_id,
        imposter_history: deal.imposter_history,
        entry: deal.entry,
        hint: deal.hint,
        used_words: deal.used_words,
        turn_order: deal.turn_order,
        names: Map.new(room.players, fn {id, player} -> {id, player.name} end),
        strokes: [],
        open_stroke: nil,
        queue: [],
        turn: nil,
        turn_n: 0,
        votes: %{},
        vote_ends_at: nil,
        guess_ends_at: nil,
        accused: nil,
        result: nil,
        next_at: nil
    }

    {:ok, %{room | phase: :reveal, game: game}}
  end

  def next_round(%__MODULE__{}, _deal), do: {:error, :not_result}

  @doc "The last round is over: show the final standings."
  def finish_game(%__MODULE__{phase: :result} = room), do: {:ok, %{room | phase: :final}}
  def finish_game(%__MODULE__{}), do: {:error, :not_result}

  @doc "Host-only. Back to the lobby for another game: scores start again, ready flags stay."
  def play_again(%__MODULE__{phase: :final} = room, player_id) do
    with :ok <- check_host(room, player_id) do
      # anyone who was only watching is a player in the lobby, like everyone else (and has to say
      # they are ready, since they have not agreed to anything yet)
      players =
        Map.new(room.players, fn
          {id, %{spectator?: true} = p} -> {id, %{p | spectator?: false, ready?: false}}
          other -> other
        end)

      {:ok, %{room | phase: :lobby, game: nil, scores: %{}, players: players}}
    end
  end

  def play_again(%__MODULE__{}, _player_id), do: {:error, :not_finished}

  @doc "Host-only. Skip the wait after a result and go on to the next round (or the final)."
  def check_can_skip(%__MODULE__{phase: :result} = room, player_id),
    do: check_host(room, player_id)

  def check_can_skip(%__MODULE__{}, _player_id), do: {:error, :not_result}

  @doc """
  How many laps (turns each) a round has with the room as it is now. Resolves the `:auto`
  setting from the number of players.
  """
  def laps_for(%__MODULE__{settings: %{laps: :auto}} = room),
    do: if(player_count(room) <= @auto_two_laps_up_to, do: 2, else: 1)

  def laps_for(%__MODULE__{settings: %{laps: laps}}), do: laps

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

      # someone who is only watching is not dealt a card
      spectator?(room, player_id) ->
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
    laps = Map.get(changes, :laps, settings.laps)
    categories = Map.get(changes, :categories, settings.categories)
    difficulty = Map.get(changes, :difficulty, settings.difficulty)

    if valid_in?(rounds, @round_range) and valid_in?(draw_time, @draw_time_range) and
         laps in @laps_options and valid_categories?(categories) and
         difficulty in Backend.Words.difficulties() do
      {:ok,
       %{
         settings
         | rounds: rounds,
           draw_time: draw_time,
           laps: laps,
           categories: normalize_categories(categories),
           difficulty: difficulty
       }}
    else
      {:error, :invalid_settings}
    end
  end

  # every category, or at least one category that exists, each named once
  defp valid_categories?(:all), do: true

  defp valid_categories?(names) when is_list(names) do
    known = Backend.Words.categories()
    names != [] and Enum.all?(names, &(&1 in known)) and length(Enum.uniq(names)) == length(names)
  end

  defp valid_categories?(_), do: false

  # choosing every category one by one is the same as choosing "all"
  defp normalize_categories(:all), do: :all

  defp normalize_categories(names) do
    if Enum.sort(names) == Backend.Words.categories(), do: :all, else: Enum.sort(names)
  end

  # what the game deals from, for the lobby to show and the dealer to use
  def word_filter(%__MODULE__{settings: settings}),
    do: %{categories: settings.categories, difficulty: settings.difficulty}

  defp valid_in?(value, range), do: is_integer(value) and value in range

  def member?(%__MODULE__{} = room, player_id), do: Map.has_key?(room.players, player_id)

  def player_count(%__MODULE__{} = room), do: map_size(room.players)

  @doc """
  The version of the room that is safe to send to browsers.

  Built by hand on purpose: later the room will hold secrets (the word, who the imposter is),
  and an explicit allow-list means a new field is never sent by accident.
  """
  def to_public(%__MODULE__{} = room, now \\ System.system_time(:millisecond)) do
    # In a game, the colours it dealt. Before one, the colours it WILL deal (by join order, the same
    # way), so the lobby already shows each person as they will look, and nobody changes when it starts.
    colors = (room.game && room.game.colors) || assign_colors(room.players)

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
          spectator: &1.spectator?,
          color: colors[&1.id],
          shape: shape_for(colors[&1.id]),
          avatar: &1.avatar,
          score: Map.get(room.scores, &1.id, 0)
        }
      )

    %{
      code: room.code,
      host_id: room.host_id,
      phase: room.phase,
      round: room.game && room.game.round,
      rounds: room.settings.rounds,
      final: final_public(room),
      reveal_seconds: div(room.reveal_ms, 1000),
      turn: turn_public(room, now),
      # whether people can talk right now (see `Backend.Rooms.Chat`)
      chat_open: Backend.Rooms.Chat.open?(room.phase),
      # what "auto" comes to for the players here now (so the lobby can say so)
      laps_now: laps_for(room),
      # what the host can choose from, and how many words their choices leave
      words: %{
        categories: Backend.Words.categories(),
        pool: Backend.Words.pool_size(word_filter(room))
      },
      vote: stage(room, :voting, now),
      guess: stage(room, :guess, now),
      result: stage(room, :result, now),
      settings: room.settings,
      min_players: @min_players,
      max_players: @max_players,
      players: players
    }
  end

  defp turn_public(%__MODULE__{game: %{turn: %{} = turn}} = room, now) do
    %{
      player_id: turn.player_id,
      # which turn this is: it changes every turn, even if the same player draws twice running
      n: turn.n,
      lap: turn.lap,
      laps: room.game.laps,
      # the order everyone draws in each lap (not a secret: it is on show at the table)
      order: Enum.filter(room.game.turn_order, &Map.has_key?(room.players, &1)),
      ms_left: turn_ms_left(room, now)
    }
  end

  defp turn_public(_room, _now), do: nil

  # the winner(s) of the game: whoever has the top score (a tie shares it; nobody if no one scored)
  defp final_public(%__MODULE__{phase: :final} = room) do
    top = room.scores |> Map.values() |> Enum.max(fn -> 0 end)

    winners =
      if top > 0,
        do: for({id, score} <- room.scores, score == top, Map.has_key?(room.players, id), do: id),
        else: []

    %{winner_ids: Enum.sort(winners), rounds_played: room.game.round}
  end

  defp final_public(_room), do: nil

  # the voting / guessing / result details exist only while the room is in that phase
  defp stage(%__MODULE__{phase: phase} = room, phase, now), do: Voting.public(room, now)
  defp stage(_room, _phase, _now), do: nil

  @doc "Who `player_id` has voted for (only they may know; sent to them alone)."
  defdelegate my_vote(room, player_id), to: Voting
end

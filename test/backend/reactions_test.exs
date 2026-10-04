defmodule Backend.ReactionsTest do
  # Emoji reactions: only a fixed set of names gets through, so they can't carry the word.
  # (config/test.exs: at most one per player every 150ms.)
  use ExUnit.Case, async: true

  alias Backend.Rooms
  alias Backend.Rooms.{Reactions, RoomServer}

  defp channel, do: spawn(fn -> Process.sleep(:infinity) end)

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  defp lobby do
    {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
    {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
    {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")
    for id <- [host, p2, p3], do: {:ok, _} = Rooms.connect(code, id, channel())
    Rooms.subscribe(code)
    flush()
    %{code: code, host: host, p2: p2, p3: p3}
  end

  defp started do
    %{code: code, host: host, p2: p2, p3: p3} = room = lobby()
    {:ok, _} = Rooms.set_ready(code, p2, true)
    {:ok, _} = Rooms.set_ready(code, p3, true)
    {:ok, _} = Rooms.start_game(code, host)
    assert_receive {:room_updated, %{phase: :drawing}}, 2000
    flush()
    room
  end

  describe "the rules" do
    test "a fixed handful of names" do
      assert Reactions.ids() == ~w(laugh think sus eyes clap fire)
      assert Enum.all?(Reactions.ids(), &Reactions.valid?/1)
    end

    test "anything else is not a reaction" do
      for bad <- ["", "Giraffe", "LAUGH", "laugh ", "laugh!", "😂", nil, 5, :laugh, %{}, ["laugh"]],
          do: refute(Reactions.valid?(bad), inspect(bad))
    end

    test "open while there's a drawing to react to, closed otherwise" do
      for phase <- [:drawing, :voting, :result], do: assert(Reactions.open?(phase))
      for phase <- [:lobby, :reveal, :guess, :final], do: refute(Reactions.open?(phase))
    end
  end

  describe "in a room" do
    test "not in the lobby" do
      %{code: code, host: host} = lobby()
      assert {:error, :reactions_closed} = Rooms.react(code, host, "laugh")
    end

    test "while drawing, everyone is told who reacted and how; the name comes from the room" do
      %{code: code, p2: p2} = started()
      assert :ok = Rooms.react(code, p2, "fire")
      assert_receive {:reaction, %{player_id: ^p2, name: "Two", id: "fire"}}, 500
    end

    test "only the names on the list" do
      %{code: code, p2: p2} = started()

      for bad <- ["Giraffe", "", nil, 5, "laugh and a word"] do
        assert {:error, :invalid_reaction} = Rooms.react(code, p2, bad), inspect(bad)
        Process.sleep(160)
      end

      refute_receive {:reaction, _}, 100
    end

    test "not too fast" do
      %{code: code, p2: p2} = started()
      assert :ok = Rooms.react(code, p2, "clap")
      assert {:error, :too_fast} = Rooms.react(code, p2, "clap")
      Process.sleep(170)
      assert :ok = Rooms.react(code, p2, "clap")
    end

    test "one person's pace doesn't slow another's" do
      %{code: code, p2: p2, p3: p3} = started()
      assert :ok = Rooms.react(code, p2, "clap")
      assert :ok = Rooms.react(code, p3, "clap")
    end

    test "strangers can't" do
      %{code: code} = started()
      assert {:error, :not_a_member} = Rooms.react(code, "nobody", "laugh")
    end

    test "someone watching can" do
      %{code: code} = started()
      {:ok, %{player_id: watcher}} = Rooms.join_room(code, "Late")
      {:ok, _} = Rooms.connect(code, watcher, channel())
      assert :ok = Rooms.react(code, watcher, "eyes")
    end

    test "nothing is kept: the room is the same after" do
      %{code: code, p2: p2} = started()
      {:ok, before} = RoomServer.get_state(code)
      :ok = Rooms.react(code, p2, "think")
      assert {:ok, ^before} = RoomServer.get_state(code)
    end

    test "still open for the vote" do
      %{code: code, p2: p2} = started()

      finish = fn finish ->
        case RoomServer.get_state(code) do
          {:ok, %{phase: :drawing, game: %{turn: %{player_id: id}}}} ->
            :ok = Rooms.finish_turn(code, id)
            finish.(finish)

          _ ->
            :ok
        end
      end

      finish.(finish)
      assert_receive {:room_updated, %{phase: :voting}}, 2000
      assert :ok = Rooms.react(code, p2, "sus")
    end
  end
end

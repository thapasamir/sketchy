defmodule Backend.ChatFlowTest do
  # Chat in a real room: relayed to everyone, kept by no one, open only when it can't give the
  # game away. (config/test.exs: at most one message per 150ms.)
  use ExUnit.Case, async: true

  alias Backend.Rooms
  alias Backend.Rooms.RoomServer

  defp channel, do: spawn(fn -> Process.sleep(:infinity) end)

  defp state(code) do
    {:ok, room} = RoomServer.get_state(code)
    room
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  # three connected players, in the lobby; this test process is subscribed
  defp lobby do
    {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
    {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
    {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")
    pids = Map.new([host, p2, p3], fn id -> {id, channel()} end)
    for {id, pid} <- pids, do: {:ok, _} = Rooms.connect(code, id, pid)
    Rooms.subscribe(code)
    flush()
    %{code: code, host: host, players: [host, p2, p3]}
  end

  # a game of `rounds` rounds, started: the drawing has begun
  defp started(rounds \\ 2) do
    %{code: code, host: host, players: [_, p2, p3]} = room = lobby()
    {:ok, _} = Rooms.update_settings(code, host, %{"rounds" => rounds})
    {:ok, _} = Rooms.set_ready(code, p2, true)
    {:ok, _} = Rooms.set_ready(code, p3, true)
    {:ok, _} = Rooms.start_game(code, host)
    assert_receive {:room_updated, %{phase: :drawing}}, 2000
    flush()
    room
  end

  defp finish_all_turns(code) do
    case state(code) do
      %{phase: :drawing, game: %{turn: %{player_id: id}}} ->
        :ok = Rooms.finish_turn(code, id)
        finish_all_turns(code)

      _ ->
        :ok
    end
  end

  defp voting do
    %{code: code} = room = started()
    finish_all_turns(code)
    assert state(code).phase == :voting
    flush()
    Map.merge(room, %{word: state(code).game.entry.word, imposter: state(code).game.imposter_id})
  end

  # everyone accuses the imposter (they are caught and get to guess)
  defp guessing do
    %{code: code, players: players, imposter: imposter} = room = voting()

    for voter <- players do
      target = if voter == imposter, do: Enum.find(players, &(&1 != imposter)), else: imposter
      :ok = Rooms.vote(code, voter, target)
    end

    assert state(code).phase == :guess
    flush()
    room
  end

  # the crew accuse one of their own: the round is over at once
  defp result do
    %{code: code, players: players, imposter: imposter} = room = voting()
    innocent = Enum.find(players, &(&1 != imposter))
    other = Enum.find(players, &(&1 != innocent))

    for voter <- players do
      :ok = Rooms.vote(code, voter, if(voter == innocent, do: other, else: innocent))
    end

    assert state(code).phase == :result
    flush()
    room
  end

  describe "talking" do
    test "a message is relayed to everyone in the room, with the speaker's name from the room" do
      %{code: code, host: host} = lobby()
      assert :ok = Rooms.chat(code, host, "hello everyone")

      assert_receive {:chat,
                      %{text: "hello everyone", name: "Host", player_id: ^host, id: id, at: at}}

      assert is_integer(id) and is_integer(at)
    end

    test "there is no way to speak as someone else (the name is the room's, not the message's)" do
      %{code: code, host: host} = lobby()
      :ok = Rooms.chat(code, host, "I am Two")
      assert_receive {:chat, %{name: "Host"}}
    end

    test "someone who is not in the room cannot speak" do
      %{code: code} = lobby()
      assert {:error, :not_a_member} = Rooms.chat(code, "ghost", "hi")
      refute_receive {:chat, _}, 50
    end

    test "the text is tidied before it is passed on" do
      %{code: code, host: host} = lobby()
      :ok = Rooms.chat(code, host, "  hi \n   there  ")
      assert_receive {:chat, %{text: "hi there"}}
    end

    test "empty and over-long messages are refused and not relayed" do
      %{code: code, host: host} = lobby()
      assert {:error, :empty} = Rooms.chat(code, host, "   ")
      Process.sleep(200)
      assert {:error, :too_long} = Rooms.chat(code, host, String.duplicate("a", 201))
      refute_receive {:chat, _}, 50
    end

    test "one message per interval per person; others are not held up by it" do
      %{code: code, players: [host, p2, _]} = lobby()
      assert :ok = Rooms.chat(code, host, "one")
      assert {:error, :too_fast} = Rooms.chat(code, host, "two")
      assert :ok = Rooms.chat(code, p2, "someone else, straight away")

      Process.sleep(200)
      assert :ok = Rooms.chat(code, host, "three")

      assert_receive {:chat, %{text: "one"}}
      assert_receive {:chat, %{text: "someone else, straight away"}}
      assert_receive {:chat, %{text: "three"}}
      refute_receive {:chat, %{text: "two"}}, 50
    end

    test "messages come in order, each with a higher id" do
      %{code: code, host: host} = lobby()

      for n <- 1..4 do
        :ok = Rooms.chat(code, host, "m#{n}")
        Process.sleep(160)
      end

      ids =
        for _ <- 1..4 do
          assert_receive {:chat, %{id: id}}
          id
        end

      assert ids == Enum.sort(ids)
      assert length(Enum.uniq(ids)) == 4
    end

    test "chat does not disturb the game: no room update is sent for a message" do
      %{code: code, host: host} = lobby()
      :ok = Rooms.chat(code, host, "hi")
      refute_receive {:room_updated, _}, 100
    end
  end

  describe "the room keeps no chat" do
    test "after many messages the room's state is no bigger, apart from a timestamp per speaker" do
      %{code: code, players: players} = lobby()
      [{pid, _}] = Registry.lookup(Backend.RoomRegistry, code)
      before = :erlang.external_size(:sys.get_state(pid))

      # 30 messages, paced so that each speaker is within the rate limit: all of them go through
      accepted =
        for n <- 1..30 do
          result = Rooms.chat(code, Enum.at(players, rem(n, 3)), String.duplicate("blah ", 30))
          Process.sleep(55)
          result
        end

      assert Enum.all?(accepted, &(&1 == :ok))

      Process.sleep(200)
      grown = :erlang.external_size(:sys.get_state(pid)) - before
      assert grown < 200, "the room grew by #{grown} bytes: it must not be storing chat"
    end

    test "the state has no field holding messages" do
      %{code: code, host: host} = lobby()
      :ok = Rooms.chat(code, host, "remember me?")
      [{pid, _}] = Registry.lookup(Backend.RoomRegistry, code)
      refute inspect(:sys.get_state(pid)) =~ "remember me?"
    end
  end

  describe "when chat is open" do
    test "in the lobby" do
      %{code: code, host: host} = lobby()
      assert :ok = Rooms.chat(code, host, "waiting for friends")
    end

    test "while voting" do
      %{code: code, host: host} = voting()
      assert :ok = Rooms.chat(code, host, "I think it's you")
      assert_receive {:chat, %{text: "I think it's you"}}
    end

    test "after a round's result" do
      %{code: code, host: host} = result()
      assert :ok = Rooms.chat(code, host, "I knew it!")
      assert_receive {:chat, %{text: "I knew it!"}}
    end

    test "on the final standings" do
      %{code: code, host: host} = started(2)

      play_round = fn ->
        finish_all_turns(code)
        room = state(code)
        players = Map.keys(room.players)
        imposter = room.game.imposter_id
        innocent = Enum.find(players, &(&1 != imposter))
        other = Enum.find(players, &(&1 != innocent))

        for voter <- players do
          :ok = Rooms.vote(code, voter, if(voter == innocent, do: other, else: innocent))
        end
      end

      play_round.()
      assert_receive {:room_updated, %{phase: :drawing, game: %{round: 2}}}, 4000
      play_round.()
      assert_receive {:room_updated, %{phase: :final}}, 4000

      assert :ok = Rooms.chat(code, host, "good game")
    end
  end

  describe "when chat is closed" do
    test "while people draw (the drawings are the clues)" do
      %{code: code, host: host} = started()
      assert {:error, :chat_closed} = Rooms.chat(code, host, "it's a giraffe")
      refute_receive {:chat, _}, 50
    end

    test "while the caught imposter guesses" do
      %{code: code, host: host} = guessing()
      assert {:error, :chat_closed} = Rooms.chat(code, host, "say giraffe!")
      refute_receive {:chat, _}, 50
    end

    test "the public room says whether chat is open" do
      %{code: code} = lobby()
      assert Backend.Rooms.Room.to_public(state(code)).chat_open
    end
  end

  describe "the secret word" do
    test "is hidden in anything said during the vote, so it can't reach the imposter" do
      %{code: code, host: host, word: word} = voting()
      :ok = Rooms.chat(code, host, "pretty sure it's a #{word}!")

      assert_receive {:chat, %{text: text}}
      refute text =~ ~r/#{Regex.escape(word)}/i
      assert text =~ "pretty sure it's a "
      assert text =~ "!"
    end

    test "is hidden even with different capitals" do
      %{code: code, host: host, word: word} = voting()
      :ok = Rooms.chat(code, host, String.upcase(word))
      assert_receive {:chat, %{text: text}}
      refute text =~ ~r/#{Regex.escape(word)}/i
    end

    test "is shown once the round is over, because by then everyone knows it" do
      %{code: code, host: host, word: word} = result()
      :ok = Rooms.chat(code, host, "it was #{word} all along")
      assert_receive {:chat, %{text: text}}
      assert text =~ word
    end

    test "lobby chat is untouched (there is no secret yet)" do
      %{code: code, host: host} = lobby()
      :ok = Rooms.chat(code, host, "giraffe")
      assert_receive {:chat, %{text: "giraffe"}}
    end
  end
end

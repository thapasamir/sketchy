defmodule Backend.Rooms.WordSettingsTest do
  # The host chooses which categories the words come from, and how hard they may be.
  use ExUnit.Case, async: true

  alias Backend.Rooms
  alias Backend.Rooms.{Dealer, Room, RoomServer}
  alias Backend.Words

  defp room do
    room =
      Enum.reduce(0..3, Room.new("ABCD", "p0"), &Room.add_player(&2, "p#{&1}", "Player#{&1}"))

    Enum.reduce(Map.keys(room.players), room, &Room.set_connected(&2, &1, true))
  end

  defp set(room, changes) do
    {:ok, room} = Room.update_settings(room, "p0", changes)
    room
  end

  describe "the defaults" do
    test "every category, every difficulty" do
      room = Room.new("ABCD", "p0")
      assert room.settings.categories == :all
      assert room.settings.difficulty == :all
    end
  end

  describe "choosing categories" do
    test "one or several known categories are accepted" do
      assert %{categories: ["Animals"]} = set(room(), %{categories: ["Animals"]}).settings

      assert %{categories: ["Animals", "Food"]} =
               set(room(), %{categories: ["Food", "Animals"]}).settings
    end

    test "they are stored in alphabetical order, so the same choice is always the same setting" do
      assert set(room(), %{categories: ["Food", "Animals"]}).settings ==
               set(room(), %{categories: ["Animals", "Food"]}).settings
    end

    test "choosing every category is the same as 'all'" do
      assert set(room(), %{categories: Enum.reverse(Words.categories())}).settings.categories ==
               :all
    end

    test ":all is accepted" do
      assert set(set(room(), %{categories: ["Animals"]}), %{categories: :all}).settings.categories ==
               :all
    end

    test "at least one category is required" do
      assert {:error, :invalid_settings} = Room.update_settings(room(), "p0", %{categories: []})
    end

    test "a category that doesn't exist is refused" do
      assert {:error, :invalid_settings} =
               Room.update_settings(room(), "p0", %{categories: ["Animals", "Dragons"]})

      assert {:error, :invalid_settings} =
               Room.update_settings(room(), "p0", %{categories: ["animals"]})
    end

    test "naming a category twice is refused" do
      assert {:error, :invalid_settings} =
               Room.update_settings(room(), "p0", %{categories: ["Animals", "Animals"]})
    end

    test "junk is refused" do
      for bad <- [nil, "Animals", 5, %{}, [1, 2], [nil], "all", :everything] do
        assert {:error, :invalid_settings} =
                 Room.update_settings(room(), "p0", %{categories: bad}),
               inspect(bad)
      end
    end
  end

  describe "choosing how hard" do
    test "all, medium and easy are accepted" do
      for level <- [:all, :medium, :easy],
          do: assert(set(room(), %{difficulty: level}).settings.difficulty == level)
    end

    test "anything else is refused" do
      for bad <- [:hard, "easy", nil, 1, :none, "medium"] do
        assert {:error, :invalid_settings} =
                 Room.update_settings(room(), "p0", %{difficulty: bad}),
               inspect(bad)
      end
    end
  end

  describe "who can change them" do
    test "only the host" do
      assert {:error, :not_host} = Room.update_settings(room(), "p1", %{difficulty: :easy})
      assert {:error, :not_host} = Room.update_settings(room(), "p1", %{categories: ["Animals"]})
    end

    test "only in the lobby" do
      started = %{room() | phase: :drawing}

      assert {:error, :game_in_progress} =
               Room.update_settings(started, "p0", %{difficulty: :easy})
    end

    test "changing them asks everyone to say ready again; saving the same choice does not" do
      base = %{room() | players: Map.update!(room().players, "p1", &%{&1 | ready?: true})}
      same = set(base, %{difficulty: :all})
      assert same.players["p1"].ready?

      changed = set(base, %{difficulty: :easy})
      refute changed.players["p1"].ready?
    end

    test "other settings are untouched when only these change" do
      room = set(room(), %{rounds: 4, laps: 1})
      room = set(room, %{difficulty: :easy})
      assert %{rounds: 4, laps: 1, draw_time: 30, difficulty: :easy} = room.settings
    end
  end

  describe "what the lobby is told" do
    test "the categories to choose from, and how many words the current choice leaves" do
      public = Room.to_public(room())
      assert public.words.categories == Words.categories()
      assert public.words.pool == Words.count()
    end

    test "the pool shrinks as choices are made" do
      all = Room.to_public(room()).words.pool
      easy = Room.to_public(set(room(), %{difficulty: :easy})).words.pool
      animals = Room.to_public(set(room(), %{categories: ["Animals"]})).words.pool
      both = Room.to_public(set(room(), %{categories: ["Animals"], difficulty: :easy})).words.pool

      assert easy < all and animals < all
      assert both < easy and both < animals
    end

    test "the choices are in the public settings" do
      public = Room.to_public(set(room(), %{categories: ["Animals"], difficulty: :medium}))
      assert public.settings.categories == ["Animals"]
      assert public.settings.difficulty == :medium
    end
  end

  describe "the dealer uses them" do
    test "every word dealt comes from the chosen categories" do
      room = set(room(), %{categories: ["Animals", "Space and Science"]})
      cats = for _ <- 1..200, do: Dealer.deal(room).entry.category
      assert cats |> Enum.uniq() |> Enum.sort() == ["Animals", "Space and Science"]
    end

    test "every word dealt is as easy as chosen" do
      for {level, allowed} <- [easy: ["easy"], medium: ["easy", "medium"]] do
        room = set(room(), %{difficulty: level})
        levels = for _ <- 1..300, do: Dealer.deal(room).entry.difficulty
        assert Enum.all?(levels, &(&1 in allowed)), "difficulty #{level}"
      end
    end

    test "both together" do
      room = set(room(), %{categories: ["Food"], difficulty: :easy})

      for _ <- 1..200 do
        entry = Dealer.deal(room).entry
        assert entry.category == "Food" and entry.difficulty == "easy"
      end
    end

    test "the imposter's hint still belongs to the word" do
      room = set(room(), %{categories: ["Food"], difficulty: :easy})
      deal = Dealer.deal(room)
      assert deal.hint in deal.entry.hints
    end
  end

  describe "through the room API (what the browser sends)" do
    setup do
      {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
      %{code: code, host: host}
    end

    test "a list of categories and a difficulty", %{code: code, host: host} do
      assert {:ok, room} =
               Rooms.update_settings(code, host, %{
                 "categories" => ["Food", "Animals"],
                 "difficulty" => "easy"
               })

      assert room.settings.categories == ["Animals", "Food"]
      assert room.settings.difficulty == :easy
    end

    test "the word 'all' means all", %{code: code, host: host} do
      {:ok, _} =
        Rooms.update_settings(code, host, %{"categories" => ["Food"], "difficulty" => "easy"})

      assert {:ok, room} =
               Rooms.update_settings(code, host, %{"categories" => "all", "difficulty" => "all"})

      assert room.settings.categories == :all and room.settings.difficulty == :all
    end

    test "'medium' is accepted", %{code: code, host: host} do
      assert {:ok, %{settings: %{difficulty: :medium}}} =
               Rooms.update_settings(code, host, %{"difficulty" => "medium"})
    end

    test "text that is not one of the choices is refused (and never turned into an atom)", %{
      code: code,
      host: host
    } do
      before = :erlang.system_info(:atom_count)

      for n <- 1..200 do
        assert {:error, :invalid_settings} =
                 Rooms.update_settings(code, host, %{
                   "difficulty" => "nonsense#{n}_#{System.unique_integer()}"
                 })
      end

      # a client sending made-up words must not be able to grow the atom table
      assert :erlang.system_info(:atom_count) - before < 50
    end

    test "garbage categories are refused", %{code: code, host: host} do
      for bad <- ["Animals", 7, %{"a" => 1}, [], ["Nope"], [1]] do
        assert {:error, :invalid_settings} =
                 Rooms.update_settings(code, host, %{"categories" => bad}),
               inspect(bad)
      end
    end

    test "a refused change leaves the settings as they were", %{code: code, host: host} do
      {:ok, _} = Rooms.update_settings(code, host, %{"difficulty" => "easy"})

      assert {:error, :invalid_settings} =
               Rooms.update_settings(code, host, %{"categories" => ["Nope"]})

      assert {:ok, room} = RoomServer.get_state(code)
      assert room.settings.difficulty == :easy and room.settings.categories == :all
    end
  end
end

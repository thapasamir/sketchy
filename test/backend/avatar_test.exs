defmodule Backend.AvatarTest do
  use ExUnit.Case, async: true

  alias Backend.Avatar
  alias Backend.Rooms
  alias Backend.Rooms.Room

  describe "parse/1: what counts as a face" do
    test "three numbers in range, from a browser (text keys)" do
      assert {:ok, %{eyes: 2, mouth: 0, hat: 5}} =
               Avatar.parse(%{"eyes" => 2, "mouth" => 0, "hat" => 5})
    end

    test "or from inside the server (atom keys)" do
      assert {:ok, %{eyes: 1, mouth: 1, hat: 1}} = Avatar.parse(%{eyes: 1, mouth: 1, hat: 1})
    end

    test "the first and the last choice of each part are fine" do
      %{eyes: e, mouth: m, hat: h} = Avatar.counts()
      assert {:ok, _} = Avatar.parse(%{"eyes" => 0, "mouth" => 0, "hat" => 0})
      assert {:ok, _} = Avatar.parse(%{"eyes" => e - 1, "mouth" => m - 1, "hat" => h - 1})
    end

    test "one past the end of any part is refused" do
      %{eyes: e, mouth: m, hat: h} = Avatar.counts()
      assert :error = Avatar.parse(%{"eyes" => e, "mouth" => 0, "hat" => 0})
      assert :error = Avatar.parse(%{"eyes" => 0, "mouth" => m, "hat" => 0})
      assert :error = Avatar.parse(%{"eyes" => 0, "mouth" => 0, "hat" => h})
    end

    test "negative numbers, fractions, text and nothing are refused" do
      for bad <- [-1, 1.5, "2", nil, [1], %{}, :eyes] do
        assert :error = Avatar.parse(%{"eyes" => bad, "mouth" => 0, "hat" => 0}), inspect(bad)
      end
    end

    test "a missing part is refused" do
      assert :error = Avatar.parse(%{"eyes" => 0, "mouth" => 0})
      assert :error = Avatar.parse(%{})
    end

    test "anything that isn't a map is refused" do
      for bad <- [nil, "face", 5, [1, 2, 3]], do: assert(:error = Avatar.parse(bad))
    end

    test "extra things in it are ignored, so nothing else can be smuggled in" do
      assert {:ok, face} =
               Avatar.parse(%{
                 "eyes" => 0,
                 "mouth" => 0,
                 "hat" => 0,
                 "url" => "http://x",
                 "n" => 1
               })

      assert face == %{eyes: 0, mouth: 0, hat: 0}
    end

    test "parse_or_nil/1 is nil for a bad one" do
      assert Avatar.parse_or_nil(%{"eyes" => 99}) == nil

      assert %{eyes: 3, mouth: 3, hat: 3} =
               Avatar.parse_or_nil(%{"eyes" => 3, "mouth" => 3, "hat" => 3})
    end
  end

  describe "from_seed/1: a face for someone who hasn't chosen" do
    test "is always the same for the same id" do
      assert Avatar.from_seed("abc") == Avatar.from_seed("abc")
    end

    test "is always a valid face" do
      for n <- 1..200, do: assert({:ok, _} = Avatar.parse(Avatar.from_seed("player-#{n}")))
    end

    test "differs between people" do
      faces = for n <- 1..60, into: MapSet.new(), do: Avatar.from_seed("player-#{n}")
      assert MapSet.size(faces) > 40
    end
  end

  describe "in a room" do
    test "a player has the face they chose" do
      room =
        Room.new("ABCD", "p0") |> Room.add_player("p0", "A", avatar: %{eyes: 1, mouth: 2, hat: 3})

      assert %{avatar: %{eyes: 1, mouth: 2, hat: 3}} = room.players["p0"]
    end

    test "or one made from their id, which stays the same" do
      room = Room.new("ABCD", "p0") |> Room.add_player("p0", "A")
      assert room.players["p0"].avatar == Avatar.from_seed("p0")
    end

    test "joining with a face keeps it" do
      room = Room.new("ABCD", "p0") |> Room.add_player("p0", "A")
      {:ok, room} = Room.join(room, "p1", "B", %{eyes: 4, mouth: 4, hat: 4})
      assert room.players["p1"].avatar == %{eyes: 4, mouth: 4, hat: 4}
    end

    test "everybody can see everybody's face" do
      room =
        Room.new("ABCD", "p0") |> Room.add_player("p0", "A", avatar: %{eyes: 1, mouth: 2, hat: 3})

      assert [%{avatar: %{eyes: 1, mouth: 2, hat: 3}}] = Room.to_public(room).players
    end

    test "a member can change theirs, and nobody else's changes" do
      room =
        Room.new("ABCD", "p0")
        |> Room.add_player("p0", "A")
        |> Room.add_player("p1", "B")

      before = room.players["p1"].avatar
      assert {:ok, room} = Room.set_avatar(room, "p0", %{"eyes" => 7, "mouth" => 7, "hat" => 7})
      assert room.players["p0"].avatar == %{eyes: 7, mouth: 7, hat: 7}
      assert room.players["p1"].avatar == before
    end

    test "a bad face is refused and leaves the old one" do
      room =
        Room.new("ABCD", "p0") |> Room.add_player("p0", "A", avatar: %{eyes: 1, mouth: 1, hat: 1})

      assert {:error, :invalid_avatar} =
               Room.set_avatar(room, "p0", %{"eyes" => 99, "mouth" => 0, "hat" => 0})

      assert {:error, :invalid_avatar} = Room.set_avatar(room, "p0", "a face")
      assert room.players["p0"].avatar == %{eyes: 1, mouth: 1, hat: 1}
    end

    test "someone who isn't in the room can't change anything" do
      room = Room.new("ABCD", "p0") |> Room.add_player("p0", "A")

      assert {:error, :not_a_member} =
               Room.set_avatar(room, "stranger", %{"eyes" => 0, "mouth" => 0, "hat" => 0})
    end

    test "it can be changed in the middle of a game: it is only how someone looks" do
      room = %{Room.new("ABCD", "p0") | phase: :drawing} |> Room.add_player("p0", "A")
      assert {:ok, _} = Room.set_avatar(room, "p0", %{"eyes" => 0, "mouth" => 0, "hat" => 0})
    end
  end

  describe "through the room API (what the browser sends)" do
    test "creating a room with a face" do
      {:ok, %{code: code, player_id: id}} =
        Rooms.create_room("Host", %{"eyes" => 5, "mouth" => 6, "hat" => 7})

      {:ok, room} = Rooms.fetch_member_room(code, id)
      assert room.players[id].avatar == %{eyes: 5, mouth: 6, hat: 7}
    end

    test "joining with a face" do
      {:ok, %{code: code}} = Rooms.create_room("Host")

      {:ok, %{player_id: id}} =
        Rooms.join_room(code, "Friend", %{"eyes" => 1, "mouth" => 1, "hat" => 1})

      {:ok, room} = Rooms.fetch_member_room(code, id)
      assert room.players[id].avatar == %{eyes: 1, mouth: 1, hat: 1}
    end

    test "a face that doesn't check out is replaced by one made from the id, not an error" do
      {:ok, %{code: code, player_id: id}} =
        Rooms.create_room("Host", %{"eyes" => 500, "mouth" => 0, "hat" => 0})

      {:ok, room} = Rooms.fetch_member_room(code, id)
      assert room.players[id].avatar == Avatar.from_seed(id)
    end

    test "no face at all is fine" do
      {:ok, %{code: code, player_id: id}} = Rooms.create_room("Host")
      {:ok, room} = Rooms.fetch_member_room(code, id)
      assert {:ok, _} = Avatar.parse(room.players[id].avatar)
    end

    test "changing it later, for everyone to see" do
      {:ok, %{code: code, player_id: id}} = Rooms.create_room("Host")
      Rooms.subscribe(code)
      assert {:ok, _} = Rooms.set_avatar(code, id, %{"eyes" => 2, "mouth" => 2, "hat" => 2})

      assert_receive {:room_updated,
                      %{players: %{^id => %{avatar: %{eyes: 2, mouth: 2, hat: 2}}}}},
                     500
    end
  end
end

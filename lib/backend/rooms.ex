defmodule Backend.Rooms do
  @moduledoc """
  The public API of the rooms domain.

  The web layer (controllers, channels) calls ONLY this module. It never starts processes or
  talks to `RoomServer` itself, so how rooms work internally can change without touching the web code.
  """

  alias Backend.Rooms.{Room, RoomServer}

  # No I or O, so codes are easy to read out loud and hard to mix up with 1 and 0.
  @code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ"
  @code_length 4
  @max_name_length 20
  @max_code_attempts 10

  @doc """
  Create a room and make `host_name` its first player (and host).

  Returns `{:ok, %{code: code, player_id: id}}` or `{:error, reason}`.
  """
  def create_room(host_name) do
    with {:ok, name} <- validate_name(host_name) do
      start_room(%{id: new_player_id(), name: name}, @max_code_attempts)
    end
  end

  @doc "Returns `{:ok, room}` only if `player_id` is a member of the room."
  def fetch_member_room(code, player_id) do
    with {:ok, room} <- RoomServer.get_state(normalize_code(code)) do
      if Room.member?(room, player_id), do: {:ok, room}, else: {:error, :not_a_member}
    end
  end

  # Ask the supervisor to start a room under a random code. If that code is taken the start
  # fails atomically with :already_started and we simply try another code. Checking first
  # ("is it free?") and then starting would be a race between two players creating rooms at once.
  defp start_room(_host, 0), do: {:error, :no_free_code}

  defp start_room(host, attempts_left) do
    code = generate_code()
    spec = {RoomServer, code: code, host: host}

    case DynamicSupervisor.start_child(Backend.RoomSupervisor, spec) do
      {:ok, _pid} -> {:ok, %{code: code, player_id: host.id}}
      {:error, {:already_started, _pid}} -> start_room(host, attempts_left - 1)
      {:error, _other} -> {:error, :room_start_failed}
    end
  end

  defp validate_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> {:error, :name_required}
      String.length(trimmed) > @max_name_length -> {:error, :name_too_long}
      true -> {:ok, trimmed}
    end
  end

  defp validate_name(_), do: {:error, :name_required}

  defp generate_code do
    for _ <- 1..@code_length, into: "", do: <<Enum.random(@code_alphabet)>>
  end

  defp new_player_id, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  defp normalize_code(code) when is_binary(code), do: code |> String.trim() |> String.upcase()
  defp normalize_code(_), do: ""
end

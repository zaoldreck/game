defmodule Game.GameServer do
  use GenServer

  @grid_size 100
  @key_interval 10_000   # Key spawns every 10 seconds
  @game_timeout 60_000   # 60-second game timeout

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{
      players: %{},       # %{player_id => %{id, name, pos, alive, color, ready}}
      key: nil,           # current key position (or nil)
      announcements: [],  # list of announcement strings
      game_over: false,   # game over flag
      game_started: false # game started flag
    }, name: __MODULE__)
  end

  def add_player(player_id, name) do
    GenServer.call(__MODULE__, {:add_player, player_id, name})
  end

  def move_player(player_id, new_pos) do
    GenServer.call(__MODULE__, {:move_player, player_id, new_pos})
  end

  def player_ready(player_id) do
    GenServer.call(__MODULE__, {:player_ready, player_id})
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Server Callbacks

  def init(state) do
    {:ok, state}
  end

  def handle_call({:add_player, player_id, name}, _from, state) do
    pos = random_position()
    color = random_color()
    player = %{id: player_id, name: name, pos: pos, alive: true, color: color, ready: false}
    state = put_in(state, [:players, player_id], player)
    {:reply, player, state}
  end

  def handle_call({:player_ready, player_id}, _from, state) do
    state = update_in(state, [:players, player_id], fn player ->
      if player, do: Map.put(player, :ready, true), else: player
    end)

    # For testing, start the game as soon as every joined player is ready (even one).
    if Enum.all?(state.players, fn {_id, p} -> p.ready end) do
      state = %{state | game_started: true}
      schedule_key()
      Process.send_after(self(), :game_timeout, @game_timeout)
      announcement = "Game Started!"
      state = update_in(state, [:announcements], &([announcement | &1]))
      {:reply, :ok, state}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:move_player, player_id, new_pos}, _from, state) do
    # Only update the player's position if they are alive.
    state = update_in(state, [:players, player_id], fn player ->
      if player && player.alive, do: %{player | pos: new_pos}, else: player
    end)

    # If the game has started, a key exists, and this move lands on the key…
    state =
      if state.game_started and state.key != nil and new_pos == state.key do
        case state.players[player_id] do
          %{alive: true} = player ->
            announcement = "#{player.name} passed the key!"
            state = update_in(state, [:announcements], &([announcement | &1]))
            # Remove the player entirely from the game.
            state
            |> update_in([:players], &Map.delete(&1, player_id))
            |> Map.put(:key, nil)
          _ ->
            state
        end
      else
        state
      end

    state = check_game_over(state)
    {:reply, :ok, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Spawning a key every @key_interval milliseconds.
  def handle_info(:spawn_key, state) do
    state = check_game_over(state)

    if state.game_started and not state.game_over do
      if count_alive(state) <= 1 do
        state = check_game_over(state)
        {:noreply, state}
      else
        key_pos = random_position()
        state = %{state | key: key_pos}

        # If any alive players are already on the key, randomly remove one.
        players_on_key =
          state.players
          |> Enum.filter(fn {_id, player} -> player.alive and player.pos == key_pos end)

        state =
          if players_on_key != [] do
            {p_id, p} = Enum.random(players_on_key)
            state = update_in(state, [:announcements], &(["#{p.name} passed the key!" | &1]))
            state
            |> update_in([:players], &Map.delete(&1, p_id))
            |> Map.put(:key, nil)
          else
            state
          end

        state = check_game_over(state)
        schedule_key()
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Game timeout message (after @game_timeout milliseconds)
  def handle_info(:game_timeout, state) do
    state = check_game_over(state)
    {:noreply, state}
  end

  # Helpers

  defp schedule_key do
    Process.send_after(self(), :spawn_key, @key_interval)
  end

  defp random_position do
    x = :rand.uniform(@grid_size) - 1
    y = :rand.uniform(@grid_size) - 1
    {x, y}
  end

  defp random_color do
    r = (:rand.uniform(256) - 1) |> Integer.to_string(16) |> String.pad_leading(2, "0")
    g = (:rand.uniform(256) - 1) |> Integer.to_string(16) |> String.pad_leading(2, "0")
    b = (:rand.uniform(256) - 1) |> Integer.to_string(16) |> String.pad_leading(2, "0")
    "#" <> r <> g <> b
  end

  defp count_alive(state) do
    state.players
    |> Enum.filter(fn {_id, player} -> player.alive end)
    |> length()
  end

  # Check if the game should end. When exactly one player remains,
  # that last player loses and is removed from the game.
  defp check_game_over(state) do
    if state.game_started and not state.game_over do
      cond do
        count_alive(state) == 1 ->
          [{p_id, player}] = Enum.filter(state.players, fn {_id, p} -> p.alive end)
          announcement = "Game Over: #{player.name} loses!"
          state = update_in(state, [:announcements], &([announcement | &1]))
          state = update_in(state, [:players], &Map.delete(&1, p_id))
          %{state | game_over: true, key: nil}
        count_alive(state) == 0 ->
          announcement = "Game Over: No winners!"
          state = update_in(state, [:announcements], &([announcement | &1]))
          %{state | game_over: true, key: nil}
        true ->
          state
      end
    else
      state
    end
  end
end

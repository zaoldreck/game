defmodule GameWeb.GameLive do
  use Phoenix.LiveView
  alias Game.GameServer

  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(1000, self(), :tick)

    socket =
      assign(socket,
        players: %{},
        key: nil,
        announcements: [],
        player_id: nil,
        name: nil,
        joined: false,
        game_started: false,
        game_over: false
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~L"""
    <style>
      .game-container {
        max-width: 800px;
        margin: 0 auto;
        padding: 20px;
        text-align: center;
        font-family: Arial, sans-serif;
      }
      .join-container {
        margin: 20px auto;
        padding: 20px;
        border: 2px solid #ccc;
        border-radius: 8px;
        width: 300px;
      }
      .lobby {
        margin: 20px auto;
        padding: 20px;
        border: 2px solid #ccc;
        border-radius: 8px;
        display: inline-block;
      }
      .ready-button {
        background-color: #007bff;
        color: white;
        border: none;
        padding: 10px 20px;
        border-radius: 4px;
        font-size: 16px;
        cursor: pointer;
        margin-top: 10px;
      }
      .ready-button:hover {
        background-color: #0056b3;
      }
      .game-board-container {
        margin: 20px auto;
        width: 500px;
      }
      .game-board {
        margin: 0 auto;
        background-color: #f0f0f0;
        position: relative;
      }
      .player {
        position: absolute;
        width: 10px;
        height: 10px;
      }
      .player-name {
        font-size: 10px;
        color: #000;
      }
      .controls button {
        margin: 5px;
        padding: 8px 12px;
        font-size: 14px;
        cursor: pointer;
      }
      .game-over {
        margin-top: 10px;
        color: red;
        font-weight: bold;
      }
      .announcements {
        margin-top: 20px;
        text-align: left;
        max-width: 500px;
        margin-left: auto;
        margin-right: auto;
      }
    </style>

    <div class="game-container">
      <%= if not @joined do %>
        <div class="join-container">
          <h2>Join the Game</h2>
          <form phx-submit="join">
            <input type="text" name="name" placeholder="Your name" required />
            <button type="submit">Join</button>
          </form>
        </div>
      <% else %>
        <%= if not @game_started do %>
          <div class="lobby">
            <h2>Lobby</h2>
            <p>Waiting for players to be ready:</p>
            <ul>
              <%= for {_id, player} <- @players do %>
                <li>
                  <%= player.name %> - <%= if player.ready, do: "Ready", else: "Not Ready" %>
                </li>
              <% end %>
            </ul>
            <button class="ready-button" phx-click="ready">Ready</button>
            <p>Waiting for all players to click Ready...</p>
          </div>
        <% else %>
          <div phx-window-keydown="key_move" tabindex="0" class="game-board-container">
            <h2>Game Started – Good Luck, <%= @name %>!</h2>
            <div id="game-board" class="game-board" style="width: 500px; height: 500px; border: 1px solid #000;">
              <%= for {_id, player} <- @players do %>
                <% {x, y} = player.pos %>
                <div class="player" style="left: <%= x * 5 %>px; top: <%= y * 5 %>px; background-color: <%= player.color %>;">
                  <span class="player-name"><%= player.name %></span>
                </div>
              <% end %>
              <%= if @key do %>
                <% {kx, ky} = @key %>
                <div class="key" style="position: absolute; left: <%= kx * 5 %>px; top: <%= ky * 5 %>px; width: 10px; height: 10px; background-color: gold; border: 1px solid #000;"></div>
              <% end %>
            </div>
            <div class="controls">
              <button phx-click="move" phx-value-dir="up">Up</button>
              <button phx-click="move" phx-value-dir="down">Down</button>
              <button phx-click="move" phx-value-dir="left">Left</button>
              <button phx-click="move" phx-value-dir="right">Right</button>
              <p>Or use keyboard keys: W (up), A (left), S (down), D (right)</p>
            </div>
            <%= if @game_over do %>
              <div class="game-over">
                <h3>Game Over</h3>
              </div>
            <% end %>
          </div>
        <% end %>
        <div id="announcements" class="announcements">
          <h3>Announcements</h3>
          <ul>
            <%= for msg <- @announcements do %>
              <li><%= msg %></li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end

  def handle_event("join", %{"name" => name}, socket) do
    player_id = Ecto.UUID.generate()
    Game.GameServer.add_player(player_id, name)
    state = Game.GameServer.get_state()

    {:noreply,
      assign(socket,
        player_id: player_id,
        name: name,
        joined: true,
        players: state.players,
        key: state.key,
        announcements: state.announcements,
        game_started: state.game_started,
        game_over: state.game_over
      )}
  end

  def handle_event("ready", _params, socket) do
    Game.GameServer.player_ready(socket.assigns.player_id)
    state = Game.GameServer.get_state()

    {:noreply,
      assign(socket,
        players: state.players,
        game_started: state.game_started,
        announcements: state.announcements,
        key: state.key,
        game_over: state.game_over
      )}
  end

  def handle_event("move", %{"dir" => dir}, socket) do
    if Map.has_key?(socket.assigns.players, socket.assigns.player_id) do
      player = socket.assigns.players[socket.assigns.player_id]
      Game.GameServer.move_player(socket.assigns.player_id, move(player.pos, dir))
    end

    state = Game.GameServer.get_state()
    {:noreply,
      assign(socket,
        players: state.players,
        key: state.key,
        announcements: state.announcements,
        game_over: state.game_over
      )}
  end

  def handle_event("key_move", %{"key" => key}, socket) do
    direction =
      case String.downcase(key) do
        "w" -> "up"
        "a" -> "left"
        "s" -> "down"
        "d" -> "right"
        _ -> nil
      end

    if direction && Map.has_key?(socket.assigns.players, socket.assigns.player_id) do
      player = socket.assigns.players[socket.assigns.player_id]
      Game.GameServer.move_player(socket.assigns.player_id, move(player.pos, direction))
    end

    state = Game.GameServer.get_state()
    {:noreply,
      assign(socket,
        players: state.players,
        key: state.key,
        announcements: state.announcements,
        game_over: state.game_over
      )}
  end

  def handle_info(:tick, socket) do
    state = Game.GameServer.get_state()
    {:noreply,
      assign(socket,
        players: state.players,
        key: state.key,
        announcements: state.announcements,
        game_over: state.game_over,
        game_started: state.game_started
      )}
  end

  defp move({x, y}, "up"), do: {x, max(y - 1, 0)}
  defp move({x, y}, "down"), do: {x, min(y + 1, 99)}
  defp move({x, y}, "left"), do: {max(x - 1, 0), y}
  defp move({x, y}, "right"), do: {min(x + 1, 99), y}
  defp move(pos, _), do: pos
end

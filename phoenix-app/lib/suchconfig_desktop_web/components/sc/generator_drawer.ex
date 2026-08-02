defmodule SuchConfigDesktopWeb.Sc.GeneratorDrawer do
  @moduledoc false
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  attr :open, :boolean, default: false
  attr :id, :string, default: "generator-drawer"
  attr :value, :string, default: ""
  attr :mode, :string, default: "password"
  attr :length, :integer, default: 20
  attr :length_min, :integer, default: 8
  attr :length_max, :integer, default: 64
  attr :strength_level, :integer, default: 1
  attr :strength_label, :string, default: "—"
  attr :opts, :map, default: %{}
  attr :recent, :list, default: []
  attr :passphrase_words, :integer, default: 4
  attr :context, :atom, default: :standalone
  attr :copied, :boolean, default: false

  def generator_drawer(assigns) do
    gmail_alias? = Map.get(assigns.opts, :gmail_alias, false)
    alias_random? = Map.get(assigns.opts, :alias_random, true)

    assigns =
      assigns
      |> assign(:gmail_alias?, gmail_alias?)
      |> assign(:alias_random?, alias_random?)
      |> assign(:show_strength?, assigns.mode != "username" or not gmail_alias?)
      |> assign(:length_label, length_label(assigns.mode, gmail_alias?, alias_random?))

    ~H"""
    <div
      :if={@open}
      id={@id}
      class="generator-drawer-root"
      phx-window-keydown="close_generator_drawer"
      phx-key="Escape"
    >
      <div class="drawer-backdrop" phx-click="close_generator_drawer" aria-hidden="true" />
      <aside class="drawer" role="dialog" aria-labelledby="generator-drawer-title" aria-modal="true">
        <div class="drawer-head">
          <div class="row" style="justify-content: space-between; align-items: flex-start">
            <div>
              <h3 id="generator-drawer-title">Generator</h3>
              <div class="lede">such entropy — never leaves the device</div>
            </div>
            <button
              type="button"
              class="btn ghost sm icon-only"
              phx-click="close_generator_drawer"
              id="generator-drawer-close"
              aria-label="Close generator"
            >
              <.icon name="x" size={14} />
            </button>
          </div>
        </div>

        <div class="drawer-body">
          <div>
            <div class="gen-output" id="generator-output">
              <span :for={{ch, cls} <- char_classes(@value)} class={"ch #{cls}"}>{ch}</span>
            </div>
            <div class="row" style="margin-top: 10px; justify-content: space-between">
              <div :if={@show_strength?} style="flex: 1; min-width: 0; padding-right: 16px">
                <.password_strength level={@strength_level} label={@strength_label} />
              </div>
              <div :if={!@show_strength?} style="flex: 1; min-width: 0; padding-right: 16px">
                <div class="eyebrow">Gmail plus alias</div>
                <div style="font-size: 12px; color: var(--ink-2); margin-top: 4px">
                  Enter your base address, then roll
                </div>
              </div>
              <div class="gen-actions">
                <div class="row">
                  <button
                    type="button"
                    class="btn sm"
                    phx-click="roll_generator"
                    id="generator-roll-button"
                    title="Re-roll"
                  >
                    <.icon name="refresh" size={13} /> roll
                  </button>
                  <button
                    :if={@context == :secrets_entry && @mode in ["password", "passphrase"]}
                    type="button"
                    class="btn sm primary"
                    phx-click="set_generator_password"
                    id="generator-set-password-button"
                    title="Set password on entry"
                  >
                    Set Password
                  </button>
                  <button
                    :if={@context == :secrets_entry && @mode == "username"}
                    type="button"
                    class="btn sm primary"
                    phx-click="set_generator_username"
                    id="generator-set-username-button"
                    title="Set username on entry"
                  >
                    Set Username
                  </button>
                  <button
                    :if={@context == :standalone}
                    type="button"
                    class="btn sm icon-only"
                    phx-hook="CopyButton"
                    data-copy-text={@value}
                    data-copy-event="copy_generator"
                    id="generator-copy-button"
                    title="Copy"
                  >
                    <.icon name={if(@copied, do: "check", else: "copy")} size={13} />
                  </button>
                </div>
                <p :if={@copied} id="generator-copy-status" class="gen-copy-status" role="status">
                  Copied to clipboard
                </p>
              </div>
            </div>
          </div>

          <div class="divider" />

          <div class="gen-mode-switch">
            <button
              type="button"
              class={["btn", "sm", "gen-mode-btn", @mode == "password" && "active"]}
              phx-click="set_generator_mode"
              phx-value-mode="password"
              id="generator-mode-password"
            >
              Password
            </button>
            <button
              type="button"
              class={["btn", "sm", "gen-mode-btn", @mode == "passphrase" && "active"]}
              phx-click="set_generator_mode"
              phx-value-mode="passphrase"
              id="generator-mode-passphrase"
            >
              Passphrase
            </button>
            <button
              type="button"
              class={["btn", "sm", "gen-mode-btn", @mode == "username" && "active"]}
              phx-click="set_generator_mode"
              phx-value-mode="username"
              id="generator-mode-username"
            >
              Username
            </button>
          </div>

          <div class="gen-controls">
            <%= if @mode == "username" do %>
              <.toggle_row
                label="Gmail plus alias"
                on={@gmail_alias?}
                opt="gmail_alias"
              />
              <form
                :if={@gmail_alias?}
                id="generator-username-form"
                phx-change="set_generator_username_form"
                phx-debounce="120"
                class="gen-username-fields"
              >
                <div class="gen-row">
                  <span class="lbl">Base Gmail</span>
                  <input
                    type="email"
                    name="gmail_base"
                    value={Map.get(@opts, :gmail_base, "")}
                    placeholder="you@gmail.com"
                    id="generator-gmail-base-input"
                    autocomplete="off"
                  />
                </div>
                <.toggle_row
                  label="Random suffix"
                  on={@alias_random?}
                  opt="alias_random"
                />
                <div :if={!@alias_random?} class="gen-row">
                  <span class="lbl">Tag pattern</span>
                  <input
                    type="text"
                    name="alias_pattern"
                    value={Map.get(@opts, :alias_pattern, "{env}.{project}.{date}")}
                    placeholder="{env}.{project}.{date}"
                    id="generator-alias-pattern-input"
                    autocomplete="off"
                    auto-capitalize="none"
                    auto-correct="off"
                  />
                </div>
                <div :if={!@alias_random?} class="gen-row">
                  <span class="lbl">Environment</span>
                  <input
                    type="text"
                    name="tag_env"
                    value={Map.get(@opts, :tag_env, "dev")}
                    placeholder="dev"
                    id="generator-tag-env-input"
                    autocomplete="off"
                    auto-capitalize="none"
                    auto-correct="off"
                  />
                </div>
                <div :if={!@alias_random?} class="gen-row">
                  <span class="lbl">Project</span>
                  <input
                    type="text"
                    name="tag_project"
                    value={Map.get(@opts, :tag_project, "app")}
                    placeholder="app"
                    id="generator-tag-project-input"
                    autocomplete="off"
                    auto-capitalize="none"
                    auto-correct="off"
                  />
                </div>
                <div :if={!@alias_random?} class="eyebrow" style="margin-top: 4px">
                  Tokens: {"{env}"}, {"{project}"}, {"{date}"}, {"{date_compact}"}, {"{rand}"}, {"{time}"}
                </div>
              </form>
              <form
                :if={@gmail_alias? && @alias_random?}
                id="generator-username-length-form"
                phx-change="set_generator_length"
                phx-debounce="120"
                class="gen-row"
              >
                <span class="lbl">{@length_label}</span>
                <input
                  type="range"
                  name="length"
                  min={@length_min}
                  max={@length_max}
                  value={@length}
                  id="generator-length-range"
                />
                <span class="val" id="generator-length-value">{@length}</span>
              </form>
              <form
                :if={!@gmail_alias?}
                id="generator-username-length-form-random"
                phx-change="set_generator_length"
                phx-debounce="120"
                class="gen-row"
              >
                <span class="lbl">{@length_label}</span>
                <input
                  type="range"
                  name="length"
                  min={@length_min}
                  max={@length_max}
                  value={@length}
                  id="generator-length-range"
                />
                <span class="val" id="generator-length-value">{@length}</span>
              </form>
            <% else %>
              <form
                id="generator-length-form"
                phx-change="set_generator_length"
                phx-debounce="120"
                class="gen-row"
              >
                <span class="lbl">Length</span>
                <input
                  type="range"
                  name="length"
                  min={@length_min}
                  max={@length_max}
                  value={@length}
                  id="generator-length-range"
                />
                <span class="val" id="generator-length-value">{@length}</span>
              </form>

              <%= if @mode == "password" do %>
                <.toggle_row
                  label="Lowercase a–z"
                  on={Map.get(@opts, :lower, true)}
                  opt="lower"
                />
                <.toggle_row
                  label="Uppercase A–Z"
                  on={Map.get(@opts, :upper, true)}
                  opt="upper"
                />
                <.toggle_row label="Numbers 2–9" on={Map.get(@opts, :num, true)} opt="num" />
                <.toggle_row label="Symbols !@#$" on={Map.get(@opts, :sym, true)} opt="sym" />
                <.toggle_row
                  label="Allow ambiguous 0Ol"
                  on={Map.get(@opts, :ambig, false)}
                  opt="ambig"
                />
              <% else %>
                <.toggle_row
                  label="Append digit suffix"
                  on={Map.get(@opts, :num, true)}
                  opt="num"
                />
                <div class="eyebrow" style="margin-top: 4px">
                  Length ≈ words ({@passphrase_words})
                </div>
              <% end %>
            <% end %>
          </div>

          <div class="divider" />

          <div :if={@recent != []}>
            <div class="eyebrow" style="margin-bottom: 10px">Recent rolls</div>
            <div class="col" style="gap: 4px; font-family: var(--font-mono); font-size: 12px">
              <div
                :for={{entry, idx} <- Enum.with_index(@recent)}
                class="row"
                style="justify-content: space-between; color: var(--ink-2)"
                id={"generator-recent-#{idx}"}
              >
                <span style="min-width: 0; overflow: hidden; text-overflow: ellipsis">
                  {entry.value}
                </span>
                <span style="color: var(--ink-3); flex-shrink: 0; margin-left: 8px">{entry.ago}</span>
              </div>
            </div>
          </div>
        </div>
      </aside>
    </div>
    """
  end

  attr :level, :integer, required: true
  attr :label, :string, default: "—"

  defp password_strength(assigns) do
    ~H"""
    <div>
      <div class={"strength s#{@level}"}>
        <span :for={_i <- 0..4} />
      </div>
      <div class="strength-label">
        <span>strength</span>
        <span style="color: var(--ink-1)">{@label}</span>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :on, :boolean, required: true
  attr :opt, :string, required: true

  defp toggle_row(assigns) do
    ~H"""
    <div
      class="gen-row"
      style="cursor: pointer"
      phx-click="toggle_generator_opt"
      phx-value-opt={@opt}
      phx-value-on={if(@on, do: "false", else: "true")}
      id={"generator-opt-#{@opt}"}
    >
      <span class="lbl">{@label}</span>
      <span class={["toggle", @on && "on"]} />
    </div>
    """
  end

  defp length_label("username", true, true), do: "Suffix length"
  defp length_label("username", true, false), do: "Suffix length"
  defp length_label("username", false, _), do: "Username length"
  defp length_label(_, _, _), do: "Length"

  defp char_classes(value) when is_binary(value) do
    Enum.map(String.graphemes(value), &{&1, char_class(&1)})
  end

  defp char_classes(_), do: []

  defp char_class("@"), do: "sym"
  defp char_class("."), do: "sym"
  defp char_class("+"), do: "sym"

  defp char_class(ch) do
    cond do
      ch =~ ~r/[A-Z]/ -> "upp"
      ch =~ ~r/[0-9]/ -> "num"
      ch =~ ~r/[^a-zA-Z0-9]/ -> "sym"
      true -> "low"
    end
  end
end

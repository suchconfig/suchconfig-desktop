defmodule SuchConfigDesktopWeb.SecretsVaultLive.Generator do
  @moduledoc """
  Secrets Vault password drawer: UI state and PubSub wiring.

  Generation and strength analysis delegate to
  `SuchConfigCore.Generators.PasswordGenerator` (local path dep in `mix.exs`).
  Username generation (including Gmail plus-address aliases) is handled here.
  """

  alias SuchConfigCore.Generators.PasswordGenerator
  alias SuchConfigDesktopWeb.SecretsVaultLive.Formatting

  @topic "suchconfig:generator"
  @default_opts %{
    lower: true,
    upper: true,
    num: true,
    sym: true,
    ambig: false,
    gmail_alias: false,
    gmail_base: "",
    alias_random: true,
    alias_pattern: "{env}.{project}.{date}",
    tag_env: "dev",
    tag_project: "app"
  }
  @drawer_min_length 8
  @drawer_max_length 64
  @username_min_length 6
  @username_max_length 32
  @alias_suffix_min_length 4
  @alias_suffix_max_length 24
  @modes ~w(password passphrase username)

  def topic, do: @topic
  def default_opts, do: @default_opts
  def default_length, do: PasswordGenerator.default_password_length()
  def default_assigns, do: default_generator_assigns()
  def modes, do: @modes

  def broadcast_open(context \\ :standalone, opts \\ [])
      when context in [:standalone, :secrets_entry] do
    Phoenix.PubSub.broadcast(SuchConfigDesktop.PubSub, @topic, {:generator_open, context, opts})
  end

  def broadcast_apply(value, strength) when is_binary(value) and is_integer(strength) do
    Phoenix.PubSub.broadcast(
      SuchConfigDesktop.PubSub,
      @topic,
      {:generator_apply, value, strength}
    )
  end

  def broadcast_apply_username(value) when is_binary(value) do
    Phoenix.PubSub.broadcast(
      SuchConfigDesktop.PubSub,
      @topic,
      {:generator_apply_username, value}
    )
  end

  def default_generator_assigns do
    [
      show_generator_drawer: false,
      generator_value: "",
      generator_length: default_length(),
      generator_mode: "password",
      generator_opts: @default_opts,
      generator_strength_level: 1,
      generator_strength_label: "—",
      generator_recent: [],
      generator_context: :standalone,
      generator_target: nil,
      generator_copied: false
    ]
  end

  def open(socket, context \\ :standalone, opts \\ [])
      when context in [:standalone, :secrets_entry] do
    mode = Keyword.get(opts, :mode, default_mode_for(context, opts))
    target = Keyword.get(opts, :target)
    generator_opts = default_opts_for(mode, target)

    socket
    |> Phoenix.Component.assign(
      show_generator_drawer: true,
      generator_context: context,
      generator_target: target,
      generator_mode: mode,
      generator_length: default_length_for_mode(mode),
      generator_opts: generator_opts,
      generator_recent: socket.assigns[:generator_recent] || [],
      generator_copied: false
    )
    |> maybe_roll()
  end

  defp maybe_roll(socket) do
    if auto_roll?(socket.assigns) do
      roll(socket)
    else
      Phoenix.Component.assign(socket,
        generator_value: "",
        generator_strength_level: 0,
        generator_strength_label: "—",
        error: nil
      )
    end
  end

  defp auto_roll?(assigns) do
    mode = assigns.generator_mode
    opts = assigns.generator_opts || @default_opts

    mode != "username" or
      not Map.get(opts, :gmail_alias, false) or
      String.trim(Map.get(opts, :gmail_base, "")) != ""
  end

  def open_from_params(params, socket) do
    context = context_from_params(params)
    mode = mode_from_params(params, context)
    target = target_from_params(params)

    open(socket, context, mode: mode, target: target)
  end

  def context_from_params(%{"context" => "secrets_entry"}), do: :secrets_entry
  def context_from_params(_), do: :standalone

  def mode_from_params(%{"mode" => mode}, _context) when mode in @modes, do: mode

  def mode_from_params(%{"target" => "username"}, :secrets_entry), do: "username"
  def mode_from_params(%{"target" => "password"}, :secrets_entry), do: "password"
  def mode_from_params(_, :secrets_entry), do: "password"
  def mode_from_params(_, _), do: "password"

  def target_from_params(%{"target" => target}) when target in ["password", "username"],
    do: target

  def target_from_params(_), do: nil

  def close(socket) do
    Phoenix.Component.assign(socket, show_generator_drawer: false, generator_copied: false)
  end

  def roll(socket) do
    case generate_from_assigns(socket.assigns) do
      {:ok, value, _meta, level, label} ->
        recent = prepend_recent(socket.assigns[:generator_recent] || [], value)

        Phoenix.Component.assign(socket,
          generator_value: value,
          generator_strength_level: level,
          generator_strength_label: label,
          generator_strength: level,
          generator_recent: recent,
          show_generator_drawer: true,
          generator_copied: false,
          error: nil
        )

      {:error, reason} ->
        Phoenix.Component.assign(socket,
          error: format_error(reason),
          show_generator_drawer: true
        )
    end
  end

  def set_mode(socket, mode) when is_binary(mode) do
    if mode in @modes do
      length = default_length_for_mode(mode)
      target = socket.assigns[:generator_target]
      opts = if mode == "username", do: default_opts_for(mode, target), else: @default_opts

      socket
      |> Phoenix.Component.assign(
        generator_mode: mode,
        generator_length: length,
        generator_opts: opts
      )
      |> roll()
    else
      socket
    end
  end

  def set_length(socket, length) when is_integer(length) do
    {min, max} = length_range(socket.assigns.generator_mode, socket.assigns.generator_opts)
    length = clamp(length, min, max)

    socket
    |> Phoenix.Component.assign(generator_length: length)
    |> roll()
  end

  def length_range(mode, opts \\ %{}) do
    case mode do
      "username" ->
        if Map.get(opts, :gmail_alias, false) and Map.get(opts, :alias_random, true) do
          {@alias_suffix_min_length, @alias_suffix_max_length}
        else
          {@username_min_length, @username_max_length}
        end

      "passphrase" ->
        {@drawer_min_length, @drawer_max_length}

      _ ->
        {@drawer_min_length, @drawer_max_length}
    end
  end

  def length_min(mode, opts \\ %{}), do: length_range(mode, opts) |> elem(0)
  def length_max(mode, opts \\ %{}), do: length_range(mode, opts) |> elem(1)

  def parse_length_from_params(params) when is_map(params) do
    params
    |> Map.get("length")
    |> parse_length_value()
  end

  defp parse_length_value(length) when is_integer(length), do: length

  defp parse_length_value(length) when is_binary(length) do
    case Integer.parse(length) do
      {n, _} -> n
      :error -> default_length()
    end
  end

  defp parse_length_value(_), do: default_length()

  def set_username_form(socket, params) when is_map(params) do
    opts =
      socket.assigns.generator_opts
      |> maybe_put_string_opt(params, "gmail_base", :gmail_base)
      |> maybe_put_string_opt(params, "alias_pattern", :alias_pattern)
      |> maybe_put_string_opt(params, "tag_env", :tag_env)
      |> maybe_put_string_opt(params, "tag_project", :tag_project)
      |> maybe_put_bool_opt(params, "gmail_alias", :gmail_alias)
      |> maybe_put_bool_opt(params, "alias_random", :alias_random)

    socket
    |> Phoenix.Component.assign(generator_opts: opts)
    |> maybe_roll()
  end

  def toggle_opt(socket, opt, on) when is_binary(opt) do
    key = opt_atom(opt)
    opts = Map.put(socket.assigns.generator_opts, key, on)

    socket
    |> Phoenix.Component.assign(generator_opts: opts)
    |> maybe_roll()
  end

  def passphrase_word_count(length) when is_integer(length) do
    length
    |> div(5)
    |> max(PasswordGenerator.min_passphrase_words())
    |> min(PasswordGenerator.max_passphrase_words())
  end

  def generate_from_assigns(assigns) do
    mode = assigns.generator_mode
    length = assigns.generator_length
    opts = assigns.generator_opts || @default_opts

    case mode do
      "username" -> generate_username(length, opts)
      _ -> generate_password_or_passphrase(mode, length, opts)
    end
  end

  def format_error(:wordlist_file_missing) do
    "Passphrase wordlist missing. From suchconfig-core run: mix suchconfig.fetch_eff_wordlist"
  end

  def format_error(:wordlist_parse_failed), do: "Could not read any words from the wordlist file."
  def format_error(:empty_wordlist), do: "Wordlist is empty."
  def format_error(:empty_character_pool), do: "Enable at least one character type."

  def format_error(:length_below_required_classes),
    do: "Length is too short for the selected character types."

  def format_error(:invalid_password_length), do: "Invalid password length."
  def format_error(:invalid_passphrase_word_count), do: "Invalid passphrase word count."
  def format_error(:invalid_gmail_base), do: "Enter a valid Gmail address (e.g. you@gmail.com)."
  def format_error(:missing_gmail_base), do: "Enter your Gmail address to build a plus alias."
  def format_error(other), do: "Generator failed: #{inspect(other)}"

  defp generate_password_or_passphrase(mode, length, opts) do
    gen_opts =
      case mode do
        "passphrase" ->
          [
            mode: :passphrase,
            word_count: passphrase_word_count(length),
            separator: "-"
          ]

        _ ->
          password_length =
            length
            |> max(PasswordGenerator.min_password_length())
            |> min(PasswordGenerator.max_password_length())

          [
            mode: :password,
            length: password_length,
            lowercase: Map.get(opts, :lower, true),
            uppercase: Map.get(opts, :upper, true),
            numbers: Map.get(opts, :num, true),
            symbols: Map.get(opts, :sym, true),
            exclude_ambiguous: !Map.get(opts, :ambig, false)
          ]
      end

    case PasswordGenerator.generate(gen_opts) do
      {:ok, %{value: value, meta: meta}} ->
        value = maybe_append_passphrase_suffix(value, mode, opts)
        strength = PasswordGenerator.strength(meta)
        level = strength_level(strength.label)
        label = Formatting.strength_label(level)
        {:ok, value, meta, level, label}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_username(length, opts) do
    if Map.get(opts, :gmail_alias, false) do
      generate_gmail_alias(length, opts)
    else
      generate_random_username(length, opts)
    end
  end

  defp generate_gmail_alias(length, opts) do
    base = opts |> Map.get(:gmail_base, "") |> String.trim()

    cond do
      base == "" ->
        {:error, :missing_gmail_base}

      not valid_email?(base) ->
        {:error, :invalid_gmail_base}

      true ->
        {local, domain} = split_email(base)
        suffix = build_alias_suffix(length, opts)
        value = "#{local}+#{suffix}@#{domain}"
        meta = %{mode: :username, alias_suffix: suffix, entropy_bits: alias_entropy(suffix)}
        {:ok, value, meta, 0, "alias"}
    end
  end

  defp generate_random_username(length, _opts) do
    username_length =
      length
      |> max(@username_min_length)
      |> min(@username_max_length)

    case PasswordGenerator.generate(
           mode: :password,
           length: username_length,
           lowercase: true,
           uppercase: false,
           numbers: true,
           symbols: false,
           exclude_ambiguous: true
         ) do
      {:ok, %{value: value, meta: meta}} ->
        strength = PasswordGenerator.strength(meta)
        level = strength_level(strength.label)
        label = Formatting.strength_label(level)
        {:ok, value, meta, level, label}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_alias_suffix(length, opts) do
    if Map.get(opts, :alias_random, true) do
      suffix_length =
        length
        |> max(@alias_suffix_min_length)
        |> min(@alias_suffix_max_length)

      random_token(suffix_length)
    else
      expand_alias_pattern(Map.get(opts, :alias_pattern, ""), opts)
    end
  end

  defp expand_alias_pattern(pattern, opts) do
    today = Date.utc_today()

    pattern
    |> String.trim()
    |> String.replace("{env}", sanitize_tag(Map.get(opts, :tag_env, "dev")))
    |> String.replace("{project}", sanitize_tag(Map.get(opts, :tag_project, "app")))
    |> String.replace("{date}", Date.to_iso8601(today))
    |> String.replace("{date_compact}", Calendar.strftime(today, "%Y%m%d"))
    |> String.replace("{rand}", random_token(4))
    |> String.replace("{time}", Calendar.strftime(DateTime.utc_now(), "%H%M%S"))
    |> then(fn
      "" -> random_token(6)
      tag -> tag
    end)
  end

  defp sanitize_tag(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]+/u, "")
    |> then(fn
      "" -> "tag"
      tag -> tag
    end)
  end

  defp random_token(length) do
    case PasswordGenerator.generate(
           mode: :password,
           length: length,
           lowercase: true,
           uppercase: false,
           numbers: true,
           symbols: false,
           exclude_ambiguous: true
         ) do
      {:ok, %{value: value}} -> value
      _ -> "x#{:rand.uniform(999_999)}"
    end
  end

  defp alias_entropy(suffix) do
    suffix
    |> String.length()
    |> Kernel.*(3.5)
  end

  defp valid_email?(email) do
    email =~ ~r/^[^\s@+]+@[^\s@]+\.[^\s@]+$/
  end

  defp split_email(email) do
    [local | rest] = String.split(email, "@", parts: 2)
    {local, Enum.join(rest, "@")}
  end

  defp prepend_recent(recent, value) do
    now = DateTime.utc_now()

    [
      %{value: value, at: now, ago: "now"}
      | Enum.reject(recent, &(&1.value == value))
    ]
    |> Enum.take(3)
    |> Enum.map(fn entry -> Map.put(entry, :ago, short_ago(entry.at)) end)
  end

  defp short_ago(at) do
    at
    |> Formatting.format_relative_time()
    |> String.replace_suffix(" ago", "")
    |> String.replace("just now", "now")
  end

  defp maybe_put_string_opt(opts, params, param_key, opt_key) do
    case Map.fetch(params, param_key) do
      {:ok, value} when is_binary(value) -> Map.put(opts, opt_key, value)
      _ -> opts
    end
  end

  defp maybe_put_bool_opt(opts, params, param_key, opt_key) do
    case Map.fetch(params, param_key) do
      {:ok, "true"} -> Map.put(opts, opt_key, true)
      {:ok, "false"} -> Map.put(opts, opt_key, false)
      {:ok, true} -> Map.put(opts, opt_key, true)
      {:ok, false} -> Map.put(opts, opt_key, false)
      _ -> opts
    end
  end

  defp opt_atom("lower"), do: :lower
  defp opt_atom("upper"), do: :upper
  defp opt_atom("num"), do: :num
  defp opt_atom("sym"), do: :sym
  defp opt_atom("ambig"), do: :ambig
  defp opt_atom("gmail_alias"), do: :gmail_alias
  defp opt_atom("alias_random"), do: :alias_random
  defp opt_atom(_), do: :lower

  defp strength_level(:very_weak), do: 1
  defp strength_level(:weak), do: 2
  defp strength_level(:fair), do: 3
  defp strength_level(:strong), do: 4
  defp strength_level(:very_strong), do: 5
  defp strength_level(_), do: 1

  defp maybe_append_passphrase_suffix(value, "passphrase", opts) do
    if Map.get(opts, :num, true) do
      case PasswordGenerator.generate(mode: :pin, length: 4) do
        {:ok, %{value: suffix}} -> value <> "-" <> suffix
        _ -> value
      end
    else
      value
    end
  end

  defp maybe_append_passphrase_suffix(value, _mode, _opts), do: value

  defp default_opts_for("username", "username"), do: Map.put(@default_opts, :gmail_alias, true)
  defp default_opts_for("username", _), do: @default_opts
  defp default_opts_for(_, _), do: @default_opts

  defp default_mode_for(:secrets_entry, opts), do: Keyword.get(opts, :mode, "password")
  defp default_mode_for(_, _), do: "password"

  defp default_length_for_mode("username"), do: 8
  defp default_length_for_mode(_), do: default_length()

  defp clamp(n, min, max), do: n |> max(min) |> min(max)
end

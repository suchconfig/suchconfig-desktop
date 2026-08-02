defmodule SuchConfigCore.Generators.PasswordGenerator do
  @moduledoc """
  Cryptographically secure password, passphrase, and developer-token generation.

  Uses `:crypto.strong_rand_bytes/1` and rejection sampling for uniform indices.

  Configure `Application.put_env(:suchconfig_core, :eff_wordlist_path, path)` to override
  the passphrase wordlist file (default: `priv/wordlists/eff_large_wordlist.txt` relative
  to the `:suchconfig_core` application directory). Run `mix suchconfig.fetch_eff_wordlist`
  to download the EFF large wordlist.
  """

  import Bitwise

  @default_password_length 14
  @min_password_length 5
  @max_password_length 128
  @default_symbol_charset ~c"!@#$%^&*\\"
  @ambiguous_chars ~c"0O1lI"

  @default_passphrase_words 4
  @min_passphrase_words 3
  @max_passphrase_words 20

  @default_pin_length 6
  @min_pin_length 4
  @max_pin_length 12

  @min_hex_bytes 8
  @max_hex_bytes 64

  @default_offline_guess_rate 1.0e10

  @type generate_ok :: {:ok, %{value: String.t(), meta: map()}}
  @type generate_err :: {:error, term()}

  @spec generate(keyword() | map()) :: generate_ok | generate_err
  def generate(opts) when is_list(opts), do: generate(Map.new(opts))

  def generate(opts) when is_map(opts) do
    mode = Map.get(opts, :mode, :password)

    case mode do
      :password -> generate_password(opts)
      :passphrase -> generate_passphrase(opts)
      :pin -> generate_pin(opts)
      :hex -> generate_hex(opts)
      :uuid_v4 -> generate_uuid_v4()
      _ -> {:error, {:invalid_mode, mode}}
    end
  end

  @spec strength(map(), keyword()) :: map()
  def strength(meta, opts \\ []) do
    rate = Keyword.get(opts, :guess_rate_per_second, @default_offline_guess_rate)
    entropy_bits = entropy_from_meta(meta)
    label = label_for_entropy(entropy_bits)
    crack_s = crack_seconds(entropy_bits, rate)
    crack_human = humanize_crack_time(crack_s)

    %{
      entropy_bits: Float.round(entropy_bits, 2),
      label: label,
      crack_time_seconds: crack_s,
      crack_time_human: crack_human,
      guess_rate_per_second: rate * 1.0
    }
  end

  defp generate_password(opts) do
    length = Map.get(opts, :length, @default_password_length)
    uppercase? = Map.get(opts, :uppercase, true)
    lowercase? = Map.get(opts, :lowercase, true)
    numbers? = Map.get(opts, :numbers, true)
    symbols? = Map.get(opts, :symbols, true)
    exclude_ambiguous? = Map.get(opts, :exclude_ambiguous, false)
    symbol_charset = to_charlist(Map.get(opts, :symbol_charset, List.to_string(@default_symbol_charset)))

    with :ok <- validate_password_length(length),
         {:ok, pools} <-
           build_pools(uppercase?, lowercase?, numbers?, symbols?, symbol_charset, exclude_ambiguous?),
         {:ok, {chars, pool_size}} <- password_chars(length, pools) do
      value = chars |> secure_shuffle() |> List.to_string()

      {:ok,
       %{
         value: value,
         meta: %{
           mode: :password,
           length: length,
           pool_size: pool_size,
           uppercase: uppercase?,
           lowercase: lowercase?,
           numbers: numbers?,
           symbols: symbols?,
           exclude_ambiguous: exclude_ambiguous?
         }
       }}
    end
  end

  defp generate_passphrase(opts) do
    word_count = Map.get(opts, :word_count, @default_passphrase_words)
    separator = Map.get(opts, :separator, "-")

    with :ok <- validate_passphrase_word_count(word_count),
         {:ok, words} <- load_wordlist(),
         true <- is_list(words) and words != [] do
      n = length(words)
      picked = for(_i <- 1..word_count, do: Enum.at(words, random_uniform(n)))
      value = Enum.join(picked, separator)

      {:ok,
       %{
         value: value,
         meta: %{
           mode: :passphrase,
           word_count: word_count,
           dictionary_size: n,
           separator: separator
         }
       }}
    else
      false -> {:error, :empty_wordlist}
      {:error, e} -> {:error, e}
    end
  end

  defp generate_pin(opts) do
    length = Map.get(opts, :length, @default_pin_length)

    with :ok <- validate_pin_length(length) do
      digits = ~c"0123456789"
      chars = for(_ <- 1..length, do: Enum.at(digits, random_uniform(10)))
      value = List.to_string(chars)

      {:ok, %{value: value, meta: %{mode: :pin, length: length, pool_size: 10}}}
    end
  end

  defp generate_hex(opts) do
    byte_len = Map.get(opts, :byte_length, 16)

    with :ok <- validate_hex_byte_length(byte_len) do
      bin = :crypto.strong_rand_bytes(byte_len)
      value = Base.encode16(bin, case: :lower)
      {:ok, %{value: value, meta: %{mode: :hex, byte_length: byte_len, pool_size: 16}}}
    end
  end

  defp generate_uuid_v4 do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = bor(band(c, 0x0FFF), 0x4000)
    d = bor(band(d, 0x3FFF), 0x8000)
    raw = <<a::32, b::16, c::16, d::16, e::48>>
    hex = Base.encode16(raw, case: :lower)

    s =
      String.slice(hex, 0, 8) <>
        "-" <>
        String.slice(hex, 8, 4) <>
        "-" <>
        String.slice(hex, 12, 4) <>
        "-" <>
        String.slice(hex, 16, 4) <>
        "-" <>
        String.slice(hex, 20, 12)

    {:ok, %{value: s, meta: %{mode: :uuid_v4, random_bits: 122}}}
  end

  defp validate_password_length(len)
       when is_integer(len) and len >= @min_password_length and len <= @max_password_length,
       do: :ok

  defp validate_password_length(_), do: {:error, :invalid_password_length}

  defp validate_passphrase_word_count(n)
       when is_integer(n) and n >= @min_passphrase_words and n <= @max_passphrase_words,
       do: :ok

  defp validate_passphrase_word_count(_), do: {:error, :invalid_passphrase_word_count}

  defp validate_pin_length(len) when is_integer(len) and len >= @min_pin_length and len <= @max_pin_length, do: :ok
  defp validate_pin_length(_), do: {:error, :invalid_pin_length}

  defp validate_hex_byte_length(n) when is_integer(n) and n >= @min_hex_bytes and n <= @max_hex_bytes, do: :ok
  defp validate_hex_byte_length(_), do: {:error, :invalid_hex_byte_length}

  defp build_pools(upper?, lower?, num?, sym?, symbol_cs, exclude_amb?) do
    upper = if upper?, do: Enum.to_list(?A..?Z), else: []
    lower = if lower?, do: Enum.to_list(?a..?z), else: []
    digit = if num?, do: ~c"0123456789", else: []
    sym = if sym?, do: symbol_cs, else: []

    pools = [
      {:upper, upper},
      {:lower, lower},
      {:digit, digit},
      {:sym, sym}
    ]

    pools =
      if exclude_amb? do
        for {tag, cs} <- pools, do: {tag, exclude_ambiguous(cs)}
      else
        pools
      end

    active = for {_, cs} <- pools, cs != [], do: cs

    if active == [] do
      {:error, :empty_character_pool}
    else
      {:ok, pools}
    end
  end

  defp exclude_ambiguous(charlist) do
    Enum.reject(charlist, fn c -> c in @ambiguous_chars end)
  end

  defp password_chars(length, pools) do
    active_pools = for {_, cs} <- pools, cs != [], do: cs

    required =
      for {_, cs} <- pools, cs != [] do
        Enum.at(cs, random_uniform(length(cs)))
      end

    req_len = length(required)

    if req_len > length do
      {:error, :length_below_required_classes}
    else
      union = active_pools |> Enum.concat() |> Enum.uniq()
      pool_size = length(union)

      rest =
        for _ <- 1..(length - req_len) do
          Enum.at(union, random_uniform(pool_size))
        end

      {:ok, {required ++ rest, pool_size}}
    end
  end

  defp secure_shuffle(list) do
    n = length(list)
    do_shuffle(list, n - 1)
  end

  defp do_shuffle(list, 0), do: list

  defp do_shuffle(list, i) do
    j = random_uniform(i + 1)
    swapped = swap_at(list, i, j)
    do_shuffle(swapped, i - 1)
  end

  defp swap_at(list, i, j) do
    ei = Enum.at(list, i)
    ej = Enum.at(list, j)
    list |> List.replace_at(i, ej) |> List.replace_at(j, ei)
  end

  defp random_uniform(n) when n == 1, do: 0

  defp random_uniform(n) when is_integer(n) and n > 1 do
    max_u32 = 4_294_967_296
    limit = div(max_u32, n) * n

    draw = fn ->
      <<i::unsigned-integer-size(32)>> = :crypto.strong_rand_bytes(4)

      if i < limit do
        {:ok, rem(i, n)}
      else
        :retry
      end
    end

    retry_uniform(draw)
  end

  defp retry_uniform(draw) do
    case draw.() do
      :retry -> retry_uniform(draw)
      {:ok, x} -> x
    end
  end

  defp wordlist_path do
    Application.get_env(:suchconfig_core, :eff_wordlist_path) ||
      Path.join(:code.priv_dir(:suchconfig_core), "wordlists/eff_large_wordlist.txt")
  end

  defp load_wordlist do
    path = wordlist_path()

    case File.read(path) do
      {:ok, body} ->
        words =
          body
          |> String.split(["\r\n", "\n"], trim: true)
          |> Enum.map(&parse_wordlist_line/1)
          |> Enum.reject(&is_nil/1)

        if words == [] do
          {:error, :wordlist_parse_failed}
        else
          {:ok, words}
        end

      {:error, _} ->
        {:error, :wordlist_file_missing}
    end
  end

  defp parse_wordlist_line(line) do
    line = String.trim(line)

    if line == "" do
      nil
    else
      case String.split(line, "\t", parts: 2) do
        [_id, word] -> String.trim(word)
        _ -> parse_space_wordlist_line(line)
      end
    end
  end

  defp parse_space_wordlist_line(line) do
    case String.split(line, " ", parts: 2) do
      [_id, word] -> String.trim(word)
      [single] -> single
      _ -> nil
    end
  end

  defp entropy_from_meta(%{mode: :password, length: len, pool_size: ps}) when ps > 1 do
    len * :math.log2(ps)
  end

  defp entropy_from_meta(%{mode: :passphrase, word_count: w, dictionary_size: d}) when d > 1 do
    w * :math.log2(d)
  end

  defp entropy_from_meta(%{mode: :pin, length: len, pool_size: ps}) when ps > 1 do
    len * :math.log2(ps)
  end

  defp entropy_from_meta(%{mode: :hex, byte_length: bytes}) do
    bytes * 8.0
  end

  defp entropy_from_meta(%{mode: :uuid_v4, random_bits: bits}) do
    bits * 1.0
  end

  defp entropy_from_meta(_), do: 0.0

  defp label_for_entropy(e) when e < 28.0, do: :very_weak
  defp label_for_entropy(e) when e < 36.0, do: :weak
  defp label_for_entropy(e) when e < 60.0, do: :fair
  defp label_for_entropy(e) when e < 80.0, do: :strong
  defp label_for_entropy(_), do: :very_strong

  defp crack_seconds(entropy, rate) when entropy <= 0 or rate <= 0, do: 0.0

  defp crack_seconds(entropy, rate) do
    :math.pow(2, entropy) / rate
  end

  defp humanize_crack_time(s) when s <= 1.0, do: "Instant"
  defp humanize_crack_time(s) when s < 60.0, do: "Under a minute"
  defp humanize_crack_time(s) when s < 3600.0, do: "#{max(1, round(s / 60))} minutes"
  defp humanize_crack_time(s) when s < 86_400.0, do: "#{max(1, round(s / 3600))} hours"
  defp humanize_crack_time(s) when s < 31_536_000.0, do: "#{max(1, round(s / 86_400))} days"
  defp humanize_crack_time(s) when s < 31_536_000.0 * 100.0, do: "#{max(1, round(s / 31_536_000))} years"
  defp humanize_crack_time(s) when s < 31_536_000.0 * 1.0e6, do: "Millions of years"
  defp humanize_crack_time(s) when s < 31_536_000.0 * 1.0e9, do: "Billions of years"
  defp humanize_crack_time(_), do: "Longer than practical estimates"

  def default_password_length, do: @default_password_length
  def min_password_length, do: @min_password_length
  def max_password_length, do: @max_password_length
  def default_passphrase_words, do: @default_passphrase_words
  def min_passphrase_words, do: @min_passphrase_words
  def max_passphrase_words, do: @max_passphrase_words
  def default_offline_guess_rate, do: @default_offline_guess_rate

  def default_pin_length, do: @default_pin_length
  def min_pin_length, do: @min_pin_length
  def max_pin_length, do: @max_pin_length

  def default_hex_byte_length, do: 16
  def min_hex_byte_length, do: @min_hex_bytes
  def max_hex_byte_length, do: @max_hex_bytes
end

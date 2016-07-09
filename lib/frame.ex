defmodule Frame do
  use Bitwise

  defstruct length: 0, type: nil, flags: nil, reserved: nil, stream_id: nil, payload: nil

  @frame_definitions %{
    0x00 => :data,
    0x01 => :headers,
    0x02 => :priority,
    0x03 => :rst_stream,
    0x04 => :settings,
    0x05 => :push_promise,
    0x06 => :ping,
    0x07 => :goaway,
    0x08 => :window_update,
    0x09 => :continuation
  }

  @flag_definitions %{
    data: %{end_stream: 0x01, padded: 0x08},
    headers: %{end_stream: 0x01, end_headers: 0x04, padded: 0x08, priority: 0x20},
    priority: %{},
    rst_stream: %{},
    settings: %{ack: 0x01},
    push_promise: %{end_headers: 0x04, padded: 0x08},
    ping: %{ack: 0x01},
    goaway: %{},
    window_update: %{},
    continuation: %{end_headers: 0x04}
  }

  def decode(<<length::size(24), type::size(8), flags::size(8), reserved::size(1), stream_id::size(31), payload::bitstring>>) do
    with {:ok, frame_type} <- parse_type(type),
         {:ok, frame_flags} <- parse_flags(frame_type, flags),
         do: %Frame{
               length: length,
               type: frame_type,
               flags: frame_flags,
               reserved: parse_reserved(reserved),
               stream_id: parse_stream_id(stream_id),
               payload: parse_payload(length, frame_type, payload, frame_flags)
             }
  end

  def encode(%Frame{} = frame) do
  end

  defp parse_type(type) do
    case @frame_definitions[type] do
      nil -> {:error, "Unknown frame type: #{type}"}
      frame_type -> {:ok, frame_type}
    end
  end

  defp parse_flags(frame_type, flags) do
    case @flag_definitions[frame_type] do
      %{} = definitions ->  {:ok, Enum.reduce(definitions, [], fn ({name, position}, acc) -> if (flags &&& position) == position, do: acc ++ [name], else: acc end)}
      nil -> {:error, "Unknown frame type when parsing flags: #{frame_type}"}
    end
  end

  defp parse_reserved(0x0), do: 0
  defp parse_reserved(0x1), do: 1

  defp parse_stream_id(stream_id) do
    stream_id
  end

  defp parse_payload(length, :data, <<pad_length::size(8), data_with_padding::bitstring>>, [:padded | _flags]) do
    data_length_in_bits = (length - pad_length - 1) * 8

    <<data::bitstring - size(data_length_in_bits), padding::bitstring>> = data_with_padding

    %{
      pad_length: pad_length,
      data: data,
      padding: padding
    }
  end
  defp parse_payload(length, :data, <<data::bitstring>>, _flags), do: %{data: data}

  defp parse_payload(length, :headers, <<pad_length::size(8), data_with_padding::bitstring>>, [:padded | flags]) do
    data_length_in_bits = (length - pad_length - 1) * 8

    <<data_without_padding::bitstring - size(data_length_in_bits), padding::bitstring>> = data_with_padding

    %{pad_length: pad_length, padding: padding}
    |> Map.merge(parse_payload(length, :headers, data_with_padding, flags))
  end

  defp parse_payload(length, :headers, <<exclusive::size(1), stream_dependency::size(31), weight::size(8), header_fragments::bitstring>>, [:priority | flags]) do
    %{exclusive: exclusive, stream_dependency: stream_dependency, weight: weight}
    |> Map.merge(parse_payload(length, :headers, header_fragments, flags))
  end

  defp parse_payload(length, :headers, <<header_fragments::bitstring>>, []) do
    %{headers: parse_header_fragments(header_fragments)}
  end

  defp parse_payload(length, :headers, _, _), do: {:error}

  defp parse_header_fragments(fragments) do
  end

  defp parse_payload(length, :priority, <<exclusive::size(1), stream_dependency::size(31), weight::size(8)>>, _flags) do
    %{
      exclusive: exclusive,
      stream_dependency: stream_dependency,
      weight: weight
    }
  end

  defp parse_payload(length, :rst_stream, error_code, _flags), do: %{error_code: parse_error_code(error_code)}
  defp parse_payload(length, :ping, ping, _flags), do: %{data: ping}

  defp parse_payload(length, :push_promise, <<pad_length::size(8), reserved::size(1), promised_stream_id::size(31), header_fragment_with_padding::bitstring>>, [:padded | _flags]) do
    header_fragment_length_in_bits = (length - pad_length - 1) * 8

    <<header_fragment::bitstring - size(header_fragment_length_in_bits), padding::bitstring>> = header_fragment_with_padding

    %{
      pad_length: pad_length,
      reserved: reserved,
      promised_stream_id: promised_stream_id,
      header_fragment: header_fragment,
      padding: padding
    }
  end
  defp parse_payload(length, :push_promise, <<reserved::size(1), promised_stream_id::size(31), header_fragment::bitstring>>, _flags) do
    %{
      reserved: reserved,
      promised_stream_id: promised_stream_id,
      header_fragment: header_fragment
    }
  end

  defp parse_payload(length, :goaway, <<reserved::size(1), last_stream_id::size(31), error_code::size(32), debug_data::bitstring>>, _flags) do
    %{
      reserved: reserved,
      last_stream_id: last_stream_id,
      error_code: parse_error_code(error_code),
      debug_data: debug_data
    }
  end

  defp parse_payload(length, :window_update, <<reserved::size(1), window_size_increment::size(31)>>, _flags) do
    %{window_size_increment: window_size_increment}
  end

  defp parse_payload(length, :continuation, header_fragment, _flags) do
    %{}
  end

  defp parse_payload(length, :settings, settings, _flags) when rem(length, 6) == 0 do
    Enum.into(parse_settings_parameters(settings), %{})
  end

  defp parse_payload(length, :settings, _, _flags)  do
    {:error, :frame_size_error, "Length #{length} is not a multiple of 6 in a SETTINGS frame"}
  end

  defp parse_settings_parameters(<<identifier::size(16), value::size(32), parameters::bitstring>>) do
    [{parse_parameter_id(identifier), value} | parse_settings_parameters(parameters)]
  end
  defp parse_settings_parameters(<<>>), do: []

  defp parse_parameter_id(id) do
    case id do
      0x0001 -> :settings_header_table_size
      0x0002 -> :settings_enable_push
      0x0003 -> :settings_max_concurrent_streams
      0x0004 -> :settings_initial_window_size
      0x0005 -> :settings_max_frame_size
      0x0006 -> :settings_max_header_list_size
      id -> id
    end
  end

  defp parse_error_code(code) do
    case code do
      0x0000 -> :no_error
      0x0001 -> :protocole_error
      0x0002 -> :internal_error
      0x0003 -> :flow_control_error
      0x0004 -> :settings_timeout
      0x0005 -> :stream_closed
      0x0006 -> :frame_size_error
      0x0007 -> :refused_stream
      0x0008 -> :cancel
      0x0009 -> :compression_error
      0x000a -> :connect_error
      0x000b -> :enhance_your_calm
      0x000c -> :inadequate_security
      0x000d -> :http_1_1_required
      _ -> :unkown_error
    end
  end

  defp parse_payload(_, type, _, _), do: {:error, "Unknown frame type when parsing payload: #{type}"}
end

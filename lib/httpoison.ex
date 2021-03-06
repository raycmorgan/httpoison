defmodule HTTPoison.Base do
  defmacro __using__(_) do
    quote do
      def start do
        {:ok, _} = :application.ensure_all_started(:httpoison)
      end

      def process_url(url) do
        case String.downcase(url) do
          <<"http://"::utf8, _::binary>> -> url
          <<"https://"::utf8, _::binary>> -> url
          _ -> "http://" <> url
        end
      end

      def process_request_body(body), do: body

      def process_response_body(body), do: body

      def process_request_headers(headers), do: headers

      def process_response_chunk(chunk), do: chunk

      def process_headers(headers), do: headers

      def process_status_code(status_code), do: status_code

      def transformer(target) do
        receive do
          {:hackney_response, id, {:status, code, _reason}} ->
            send target, %HTTPoison.AsyncStatus{id: id, code: process_status_code(code)}
            transformer(target)
          {:hackney_response, id, {:headers, headers}} ->
            send target, %HTTPoison.AsyncHeaders{id: id, headers: process_headers(headers)}
            transformer(target)
          {:hackney_response, id, :done} ->
            send target, %HTTPoison.AsyncEnd{id: id}
          {:hackney_response, id, chunk} ->
            send target, %HTTPoison.AsyncChunk{id: id, chunk: process_response_chunk(chunk)}
            transformer(target)
        end
      end

      @doc """
      Sends an HTTP request.
      Args:
        * method - HTTP method, atom (:get, :head, :post, :put, :delete, etc.)
        * url - URL, binary string or char list
        * body - request body, binary string or char list
        * headers - HTTP headers, orddict (eg. [{:Accept, "application/json"}])
        * options - orddict of options
      Options:
        * timeout - timeout in ms, integer
      Returns HTTPoison.Response if successful.
      Raises  HTTPoison.HTTPError if failed.
      """
      def request(method, url, body \\ "", headers \\ [], options \\ []) do
        timeout = Keyword.get options, :timeout, 5000
        stream_to = Keyword.get options, :stream_to
        hn_options = [connect_timeout: timeout] ++ Keyword.get options, :hackney, []
        body = process_request_body body

        if stream_to do
          hn_options = [:async, {:stream_to, spawn(__MODULE__, :transformer, [stream_to])}] ++ hn_options
        end

        case :hackney.request(method,
                              process_url(to_string(url)),
                              process_request_headers(headers),
                              body,
                              hn_options) do
           {:ok, status_code, headers, client} ->
             {:ok, body} = :hackney.body(client)
             %HTTPoison.Response{
               status_code: process_status_code(status_code),
               headers: process_headers(headers),
               body: process_response_body(body)
             }
           {:ok, id} ->
             %HTTPoison.AsyncResponse{id: id}
           {:error, reason} ->
             raise HTTPoison.HTTPError[message: to_string(reason)]
         end
      end

      def get(url, headers \\ [], options \\ []),         do: request(:get, url, "", headers, options)
      def put(url, body, headers \\ [], options \\ []),   do: request(:put, url, body, headers, options)
      def head(url, headers \\ [], options \\ []),        do: request(:head, url, "", headers, options)
      def post(url, body, headers \\ [], options \\ []),  do: request(:post, url, body, headers, options)
      def patch(url, body, headers \\ [], options \\ []), do: request(:patch, url, body, headers, options)
      def delete(url, headers \\ [], options \\ []),      do: request(:delete, url, "", headers, options)
      def options(url, headers \\ [], options \\ []),     do: request(:options, url, "", headers, options)

      defoverridable Module.definitions_in(__MODULE__)
    end
  end
end


defmodule HTTPoison.Response,
  do: defstruct status_code: nil, body: nil, headers: []

defmodule HTTPoison.AsyncResponse,
 do: defstruct id: nil

defmodule HTTPoison.AsyncStatus,
 do: defstruct id: nil, code: nil

defmodule HTTPoison.AsyncHeaders,
 do: defstruct id: nil, headers: []

defmodule HTTPoison.AsyncChunk,
 do: defstruct id: nil, chunk: nil

defmodule HTTPoison.AsyncEnd,
 do: defstruct id: nil


defmodule HTTPoison do
  @moduledoc """
  The HTTP client for Elixir.
  """

  defexception HTTPError, message: nil

  use HTTPoison.Base
end


# Implement Access and Enum protocol for all HTTPoison structs

defimpl Access, for: [
  HTTPoison.Response,
  HTTPoison.AsyncResponse,
  HTTPoison.AsyncStatus,
  HTTPoison.AsyncHeaders,
  HTTPoison.AsyncChunk,
  HTTPoison.AsyncEnd
] do
  def access(map, key) do
    case :maps.find(key, map) do
      { :ok, value } -> value
      :error -> nil
    end
  end
end

defimpl Enumerable, for: [
  HTTPoison.Response,
  HTTPoison.AsyncResponse,
  HTTPoison.AsyncStatus,
  HTTPoison.AsyncHeaders,
  HTTPoison.AsyncChunk,
  HTTPoison.AsyncEnd
] do
  def reduce(map, acc, fun) do
    do_reduce(:maps.to_list(map), acc, fun)
  end

  defp do_reduce(_,     { :halt, acc }, _fun),   do: { :halted, acc }
  defp do_reduce(list,  { :suspend, acc }, fun), do: { :suspended, acc, &do_reduce(list, &1, fun) }
  defp do_reduce([],    { :cont, acc }, _fun),   do: { :done, acc }
  defp do_reduce([h|t], { :cont, acc }, fun),    do: do_reduce(t, fun.(h, acc), fun)

  def member?(map, { key, value }) do
    { :ok, match?({ :ok, ^value }, :maps.find(key, map)) }
  end

  def member?(_map, _other) do
    { :ok, false }
  end

  def count(map) do
    { :ok, map_size(map) }
  end
end

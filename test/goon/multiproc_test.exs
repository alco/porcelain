defmodule PorcelainTest.MultiprocTest do
  use ExUnit.Case

  alias Porcelain.Process, as: Proc

  setup_all do
    :ok = Porcelain.reinit(Porcelain.Driver.Goon)
  end

  test "multiple OR filters" do
    input = [
      "squeak\n",
      "sponge\n",
      "silly\n",
      "にほんごがすきです\n",
      "abcdef\n",
      "elixir\n",
      "erlang\n",
    ]

    filter_s = %Proc{out: stream_s} = make_filter("s")
    filter_i = %Proc{out: stream_i} = make_filter("i")
    filter_go = %Proc{out: stream_go} = make_filter("ご")

    filters = [
      {filter_s, stream_s}, {filter_i, stream_i}, {filter_go, stream_go}
    ]

    parent = self()
    Enum.each(filters, fn {proc, stream} ->
      spawn(fn -> send(parent, {proc, Enum.into(stream, "")}) end)
    end)

    Enum.each(input, fn line ->
      Enum.each(filters, fn {proc, _} -> Proc.send_input(proc, line) end)
    end)
    no_receive(filters)

    Enum.each(filters, fn {proc, _} -> Proc.send_input(proc, "") end)

    assert_receive {^filter_s, "squeak\nsponge\nsilly\n"}
    assert_receive {^filter_i, "silly\nelixir\n"}
    assert_receive {^filter_go, "にほんごがすきです\n"}

    Enum.each(filters, fn {proc, _} -> refute Proc.alive?(proc) end)
  end

  defp make_filter(str) do
    %Proc{} = Porcelain.spawn("grep", [str], in: :receive, out: :stream)
  end

  defp no_receive(filters) do
    Enum.each(filters, fn {proc, _} ->
      refute_receive {^proc, _}
    end)
  end
end


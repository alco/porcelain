Porcelain
=========

**The library is undergoing a revamp. Some things in this README are a lie**

Launch and communicate with external OS processes in Elixir without limitations
of Erlang ports. Porcelain builds on ports for easy integration, but provides
richer functionality and simple API for managing external processes.

Simply put, Porcelain removes the pain of dealing with ports and substitutes it
with happiness and peace of mind.


## Usage

Examples below show some of the common use cases. Refer to the API docs to
learn the complete set of provided functions and options.


### Launching one-off programs

If you need to launch an external program, feed it some input and capture its output and maybe also exit status, use `exec()` or `shell()`:

```elixir
alias Porcelain.Result

%Result{out: output, status: status} = Porcelain.shell("date")
IO.inspect status   #=> 0
IO.inspect output   #=> "Fri Jun  6 14:12:02 EEST 2014\n"

result = Porcelain.shell("date | cut -b 1-3")
IO.inspect result.out   #=> "Fri\n"

# Use exec() when you want launch a program directly without using a shell
File.write!("input.txt", "lines\nread\nfrom\nfile\n")
result = Porcelain.exec("sort", ["input.txt"])
IO.inspect result.out   #=> "file\nfrom\nlines\nread\n"
```


### Passing input and getting output

Porcelain give you many options when it comes to interacting with external
processes. It is possible to feed input from a file or a stream, same for
output.

```elixir
File.write!("input.txt", """
  This file contains some patterns
  >like this<
  interspersed with other text
  ... >like this< the end.
  """)

result = Porcelain.exec("grep", [">like this<", "-m", "2"],
                        in: {:path, "input.txt"})
IO.inspect result.out
#=> ">like this<\n... >like this< the end.\n"
```

Programs can be spawned asynchronously (using `spawn()` and `spawn_shell()`)
allowing for continuously exchaning data between Elixir and the external
process.

In the next example we will use streams for both input and output.

```elixir
alias Porcelain.Process

instream = SocketStream.new('example.com', 80)
opts = [in: instream, out: :stream]
proc = %Process{out: outstream} =
            Porcelain.spawn("grep", ["div", "-m", "4"], opts)
IO.write(outstream)
#     div {
#         div {
# <div>
# </div>

Process.closed?(proc)   #=> true
```

The `SocketStream` module used above wraps a tcp socket in a stream. Its
implementation can be found in the `test/test_helper.exs` file.


### Communicating with long-running programs

```elixir
alias Porcelain, as: Porc

{pid, _port} = Porc.spawn("cat", in: :pid, out: :buffer)

Porc.send(pid, "Hello")
Porc.send(pid, "\nWorld")
Porc.send(pid, :eof)

iex> flush
#=> {#PID<0.51.0>, %Porc{status: 0, in: :pid, out: "Hello\nWorld", err: nil}}
```

### Stream API

It is possible to spawn multiple process and chain them together. One can also
use sockets and Elixir streams as sources of input.

```elixir
sock = :gen_tcp.connect(...)
pipe = Porc.spawn("sed 's/\(.*\)/  \1/'", in: {:socket, sock}, out: :pipe)
Porc.spawn("tr a-z A-Z", in: {:pipe, pipe}, out: :stream)
|> Stream.into(File.stream!("output.txt"))
```

In the above example two OS processes are spawned and chained together so that
the output from one process flows into standard input of the other one.

Roughly equivalent example, but this time using only streams to chain programs
together.

```elixir
# by default stream splits the content into lines; we should probably be able
# to customize that
sock = :gen_tcp.connect(...)
s1 = Porc.spawn("sed 's/\(.*\)/  \1/'", in: {:socket, sock}, out: :stream)
s2 = Porc.spawn("tr a-z A-Z", in: :stream, out: :stream)
s3 = Porc.spawn("sort", in: :stream, out: :stream)
Stream.concat([s1, s2, s3]) |> Stream.each(&IO.puts/1)
```

Note the difference: when using pipes, the chaining will be performed at the
OS level when possible. Using streams makes each program's output pass through
Elixir before going as input into another program.


## Prerequisites

Porcelain relies on one external dependency to provide some of its features:
[goon](https://github.com/alco/goon). Get the binary for your OS and put it in
your application's working directory or somewhere in your `$PATH`.

In case `goon` is not found, Porcelain will fall back to the pure Elixir driver.


### Porcelain and OTP

It is possible to spawn long-running tasks and communicate with them using
standard OTP techniques. A spawned program can also be integrated into a
supervision tree with ability to keep its state and restart in case of errors.

*to be implemeted*


## License

This software is licensed under [the MIT license](LICENSE).

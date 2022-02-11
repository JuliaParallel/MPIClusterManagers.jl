"""
    setup_worker(host, port[, cookie];
        threadlevel=:serialized, stdout_to_master=true, stderr_to_master=true)

This is the entrypoint for MPI workers using TCP transport.

1. it connects to the socket on master
2. sends the process rank and size
3. hands over control via [`Distributed.start_worker`](https://docs.julialang.org/en/v1/stdlib/Distributed/#Distributed.start_worker)
"""
function setup_worker(host::Union{Integer, String}, port::Integer, cookie::Union{String, Symbol, Nothing}=nothing;
        threadlevel=:serialized, stdout_to_master=true, stderr_to_master=true)
    # Connect to the manager
    ip = host isa Integer ? IPv4(host) : parse(IPAddr, host)

    io = connect(ip, port)
    wait_connected(io)
    stdout_to_master && redirect_stdout(io)
    stderr_to_master && redirect_stderr(io)

    MPI.Initialized() || MPI.Init(;threadlevel=threadlevel)
    rank = MPI.Comm_rank(MPI.COMM_WORLD)
    nprocs = MPI.Comm_size(MPI.COMM_WORLD)
    Serialization.serialize(io, rank)
    Serialization.serialize(io, nprocs)

    # Hand over control to Base
    if isnothing(cookie)
        Distributed.start_worker(io)
    else
        if isa(cookie, Symbol)
            cookie = string(cookie)[8:end] # strip the leading "cookie_"
        end
        Distributed.start_worker(io, cookie)
    end
end

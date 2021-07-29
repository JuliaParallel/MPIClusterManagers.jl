"""
    rank_from_env()

Try to determine the MPI rank of the current process from the environment. This looks for
environment variables set by common MPI launchers. The specific environment variable to be
used can be set by `JULIA_MPI_RANK_VARNAME`.
"""
function rank_from_env()
    local val
    var = get(ENV, "JULIA_MPI_RANK_VARNAME", nothing)
    if var !== nothing
        return parse(Int, get(ENV, var, nothing))
    end
    for var in ["PMI_RANK", "MPI_LOCALRANKID", "OMPI_COMM_WORLD_RANK", "SLURM_PROCID"]
        val = get(ENV, var, nothing)
        if val !== nothing
            return parse(Int, val)
        end
    end
    return nothing
end

"""
    size_from_env()

Try to determine the total number of MPI ranks from the environment. This looks for
environment variables set by common MPI launchers. The specific environment variable to be
used can be set by `JULIA_MPI_RANK_VARNAME`.
"""
function size_from_env()
    local val
    var = get(ENV, "JULIA_MPI_SIZE_VARNAME", nothing)
    if var !== nothing
        return parse(Int, get(ENV, var, nothing))
    end
    for var in ["PMI_SIZE", "MPI_LOCALNRANKS", "OMPI_COMM_WORLD_SIZE", "SLURM_NTASKS"]
        val = get(ENV, var, nothing)
        if val !== nothing
            return parse(Int, val)
        end
    end
    return nothing
end

"""
    setup_worker(host, port[, cookie];
        initmpi=true, stdout_to_master=true, stderr_to_master=true)

This is the entrypoint for MPI workers using TCP transport.

1. it connects to the socket on master
2. sends the process rank and size
3. hands over control via [`Distributed.start_worker`](https://docs.julialang.org/en/v1/stdlib/Distributed/#Distributed.start_worker)
"""
function setup_worker(host::Union{Integer, String}, port::Integer, cookie::Union{String, Symbol, Nothing}=nothing;
        initmpi=true, stdout_to_master=true, stderr_to_master=true)
    # Connect to the manager
    ip = host isa Integer ? IPv4(host) : parse(IPAddr, host)

    io = connect(ip, port)
    wait_connected(io)
    stdout_to_master && redirect_stdout(io)
    stderr_to_master && redirect_stderr(io)

    if initmpi
        if !MPI.Initialized()
             MPI.Init()
        end
        # Send our MPI rank to the manager
        rank = MPI.Comm_rank(MPI.COMM_WORLD)
        nprocs = MPI.Comm_size(MPI.COMM_WORLD)
    else
        rank = rank_from_env()
        nprocs = size_from_env()
    end
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

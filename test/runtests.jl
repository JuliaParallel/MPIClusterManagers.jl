using Pkg
pkg"precompile"

using Test, MPI

nprocs = clamp(Sys.CPU_THREADS, 2, 4)

@info "Testing: test_cman_julia.jl"
run(`$(Base.julia_cmd()) $(joinpath(@__DIR__, "test_cman_julia.jl")) $nprocs`)

if VERSION >= v"1.5"
    @info "Testing: test_cman_mpi.jl"
    mpiexec() do cmd
        run(`$cmd -n $nprocs $(Base.julia_cmd()) $(joinpath(@__DIR__, "test_cman_mpi.jl"))`)
    end
else
    @warn "MPI_TRANSPORT_ALL broken on Julia versions < 1.5\nSee https://github.com/JuliaParallel/MPIClusterManagers.jl/issues/9"
end

@info "Testing: test_cman_tcp.jl"
mpiexec() do cmd
    run(`$cmd -n $nprocs $(Base.julia_cmd()) $(joinpath(@__DIR__, "test_cman_tcp.jl"))`)
end

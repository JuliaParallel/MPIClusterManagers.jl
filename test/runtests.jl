using Test, MPI

nprocs = clamp(Sys.CPU_THREADS, 2, 4)


@info "Testing: workermanager.jl"
run(`$(Base.julia_cmd()) $(joinpath(@__DIR__, "workermanager.jl")) $nprocs`)

@info "Testing: test_cman_julia.jl"
run(`$(Base.julia_cmd()) $(joinpath(@__DIR__, "test_cman_julia.jl")) $nprocs`)

@info "Testing: test_cman_mpi.jl"
mpiexec() do cmd
    run(`$cmd -n $nprocs $(Base.julia_cmd()) $(joinpath(@__DIR__, "test_cman_mpi.jl"))`)
end

@info "Testing: test_cman_tcp.jl"
mpiexec() do cmd
    run(`$cmd -n $nprocs $(Base.julia_cmd()) $(joinpath(@__DIR__, "test_cman_tcp.jl"))`)
end

using Pkg
pkg"precompile"

using MPIClusterManagers: mpiexec
using Test

# Code coverage command line options; must correspond to src/julia.h
# and src/ui/repl.c
const JL_LOG_NONE = 0
const JL_LOG_USER = 1
const JL_LOG_ALL = 2
const coverage_opts =
    Dict{Int, String}(JL_LOG_NONE => "none",
                      JL_LOG_USER => "user",
                      JL_LOG_ALL => "all")

function runtests()
    nprocs = clamp(Sys.CPU_THREADS, 2, 4)
    exename = joinpath(Sys.BINDIR, Base.julia_exename())
    extra_args = []
    @static if !Sys.iswindows()
        if occursin( "OpenRTE", read(`$mpiexec --version`, String))
            push!(extra_args,"--oversubscribe")
        end
    end

    coverage_opt = coverage_opts[Base.JLOptions().code_coverage]

    jlexec = `$exename --code-coverage=$coverage_opt`
    mpijlexec = `$mpiexec $extra_args -n $nprocs $jlexec`

    @info "Testing: test_cman_julia.jl"
    run(`$jlexec $(joinpath(@__DIR__, "test_cman_julia.jl"))`)

    @info "Testing: test_cman_mpi.jl"
    run(`$mpijlexec $(joinpath(@__DIR__, "test_cman_mpi.jl"))`)

    @info "Testing: test_cman_tcp.jl"
    run(`$mpijlexec $(joinpath(@__DIR__, "test_cman_tcp.jl"))`)
end

runtests()

################################################################################
# MPI-specific communication methods

# Execute a command on all MPI ranks
# This uses MPI as communication method even if @everywhere uses TCP
function mpi_do(mgr::Union{MPIManager,MPIWorkerManager}, expr)
  !mgr.initialized && wait(mgr.cond_initialized)
  jpids = keys(mgr.j2mpi)
  refs = Array{Any}(undef, length(jpids))
  for (i,p) in enumerate(Iterators.filter(x -> x != myid(), jpids))
      refs[i] = remotecall(expr, p)
  end
  # Execution on local process should be last, since it can block the main
  # event loop
  if myid() in jpids
      refs[end] = remotecall(expr, myid())
  end

  # Retrieve remote exceptions if any
  @sync begin
      for r in refs
          @async begin
              resp = remotecall_fetch(r.where, r) do rr
                  wrkr_result = rr[]
                  # Only return result if it is an exception, i.e. don't
                  # return a valid result of a worker computation. This is
                  # a mpi_do and not mpi_callfetch.
                  isa(wrkr_result, Exception) ? wrkr_result : nothing
              end
              isa(resp, Exception) && throw(resp)
          end
      end
  end
  nothing
end

macro mpi_do(mgr, expr)
  quote
      # Evaluate expression in Main module
      thunk = () -> (Core.eval(Main, $(Expr(:quote, expr))); nothing)
      mpi_do($(esc(mgr)), thunk)
  end
end
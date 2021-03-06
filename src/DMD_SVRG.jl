using StatsBase

# SVRG solver for large scale DMD problem
mutable struct DMD_SVRG_Options{T<:AbstractFloat}
    tau::Integer	# sample size
    eta::T		# step size
    itm::Integer
    tol::T
    ptf::Integer
    # pre-allocate variables
    fars::Vector{T}
    Gars::Matrix{T}
    gars::Array{Vector{T},1}
    prox::Function
end

function prox_null(x)
    return
end

# constructor of the SVRG options
function DMD_SVRG_Options(tau, eta, params; itm=1000, tol=1e-5, ptf=100,
                          prox=prox_null::Function)
    k = params.k;
    T = typeof(real(params.X[1]));

    tol  = T(tol);

    fars = zeros(T, n);
    Gars = zeros(T, 2*k, n);
    gars = col_view(Gars);

    return DMD_SVRG_Options(tau, eta, itm, tol, ptf, fars,
                            Gars, gars, prox)
end

# SVRG solver
function solveDMD_withSVRG(params, opts)
	# load all the variables
    tau    = opts.tau;
    eta    = opts.eta;
    prox = opts.prox;
    n    = params.n;
    k    = params.k;
    T    = typeof(real(params.X[1]));

    ar   = params.ar;
    arold = copy(ar);
    prox(ar);
    dar  = zeros(T, 2*k);
    ind  = collect(1:n);

    fars = opts.fars;
    gars = opts.gars;
    
    tfar = T(0.0); tgar = zeros(T, 2*k);
    dfar = T(0.0); dgar = zeros(T, 2*k);
    rfar = T(0.0); rgar = zeros(T, 2*k);

    itm  = opts.itm;
    tol  = opts.tol;
    ptf  = opts.ptf;
    
    obj_his = zeros(T, itm);
    err_his = zeros(T, itm);

    # first full step
    # initialize the gradient (might take a while)
    for id = 1:n
	fars[id] = abFunc(params, id);
	abGrad(gars[id], params, id);
    end
    tfar = sum(fars);
    sum!(tgar, opts.Gars);
    # update alpha
    copyto!(dar, tgar); dar .*= eta/n;
    copyto!(arold,ar);
    ar .-= dar;

    prox(ar);
    BLAS.axpy!(-1.0,ar,arold)
    err  = sqrt(sum(abs2,arold));
    noi  = 0;

    ind2 = collect(1:tau);
    
    while err ≥ tol
	# random sample columns
	sample!(ind,ind2); fill!(dgar, T(0.0)); dfar = T(0.0);
	for i = 1:tau
	    id = ind2[i];
	    # calcualte the objecitve
	    rfar = abFunc(params, id);
	    dfar = dfar + rfar - fars[id];
	    fars[id] = rfar;
	    # calcualte the gradient
	    dgar .-= gars[id];
	    abGrad(gars[id], params, id)
	    dgar .+= gars[id];
	end
	# update alpha
	copyto!(dar, tgar); dar.*= eta/n;
	BLAS.axpy!(eta/tau, dgar, dar);
        copyto!(arold,ar);
	ar .-= dar;
        prox(ar);
	# update tfar and tgar
	tfar  += dfar;
	tgar .+= dgar;

	# update information
        BLAS.axpy!(-1.0,ar,arold)
	err = sqrt(sum(abs2, arold));
	noi = noi + 1;
	obj_his[noi] = tfar;
	err_his[noi] = err;

	# print information
	noi % ptf == 0 && @printf("iter %5d, obj %1.2e, err %1.2e\n",
			          noi, tfar, err);
	noi ≥ itm && break;
    end
    return obj_his[1:noi], err_his[1:noi]
end

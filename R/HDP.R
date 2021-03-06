#'Hierarchical Dirichlet Process
#'HDP applied to censored data
#'@examples
#'\dontrun{
#'weights <- matrix(c(1,0,0,0,1,0,0,0,1), ncol=3)
#'
#'data <- sim.data(n=100, J=10, weights)
#'
#'G3 <- init.HDP(prior=list(mu=0, n=0.1, v=3, vs2=1*3), L=15, 
#'                    J=length(unique(data@presentation$Sample)), thinning=50,
#'                    burnin = 5000, max_iter = 55000)
#'                    
#'G3 <- MCMC.HDP(G3, data, 55000)
#'
#'validate.HDP(G3, data)
#'
#'plot.ICDF(G3@theta, G3@phi, G3@weights[,1], G3@L, grid=0:500,
#'            distribution=data@presentation, xlim=500)
#'}
#'
#' @export
setClass("HDP", representation(phi = 'matrix', theta='matrix', weights='matrix', Nmat='matrix', details='list', conc_param = 'numeric',
                               prior = 'numeric', posterior = 'array', L = 'numeric', J = 'numeric', Chains='list', pi='matrix', ChainStorage='ChainStorage'))

#'
#' @export
init.HDP <- function(prior, L, J, thinning, burnin, max_iter, ...){
  HDP <- methods::new("HDP")
  HDP@L <- L
  HDP@J <- J
  HDP@prior <- prior
  HDP@posterior <- array(rep(c(prior[1], prior[2], prior[3], prior[4]), each=(L*J)), c(L,J,4))
  HDP@Nmat <- matrix(0, nrow=L, ncol=J)
  HDP@details <- list(iteration=0, thinning=thinning, burnin=burnin, max_iter=max_iter)
  HDP@conc_param <- c(1,1)#rgamma(2, prior[c(5,7)], prior[c(6,8)])
  HDP <- update.HDP(HDP)
  myThetas <- matrix(rep(NA, J), nrow=J, ncol=1)
  myParams <- matrix(rep(NA, J*L), nrow=L, ncol=J)
  HDP@Chains <- list(theta=myParams, phi=myParams, weights=myParams)
  HDP@ChainStorage <- init.ChainStorage(HDP@Chains, max_iter-burnin, thinning)
  return(HDP)
}

#'
#' @export
update.HDP <- function(HDP, ...){
  #print(HDP@conc_param)
  atoms <- rNIG(HDP@L, c(HDP@posterior[,,1]), c(HDP@posterior[,,2]), c(HDP@posterior[,,3]), c(HDP@posterior[,,4]))
  HDP@theta <- matrix(atoms[,1], nrow=HDP@L)
  HDP@phi <- matrix(atoms[,2], nrow=HDP@L)
  # 1st level
  sums <- remainingSum(round(c(HDP@posterior[,1,2])))
  u_k <- rbeta(HDP@L, shape1 = 1 + c(HDP@posterior[,1,2]), shape2 = HDP@conc_param[1] + sums)
  HDP@pi <- as.matrix(stickBreaking(u_k))
  
  # 2nd level
  sumsNmat <- matrix(apply(HDP@Nmat, 2, remainingSum), nrow=dim(HDP@Nmat)[1])
  alpha <- 1
  sums <- sapply(1:HDP@L, function(i) {alpha*(1-sum(HDP@pi[1:i]))})
  sums[which(sums < 0)] <- 0
  
  v_lk <- rbeta(HDP@J*HDP@L, HDP@conc_param[2]*rep(HDP@pi, HDP@J)+c(HDP@Nmat), c(sumsNmat)+HDP@conc_param[2]*rep(sums, HDP@J))
  v_lk <- matrix(v_lk, ncol = HDP@J, byrow = F)
  
  HDP@weights <- apply(v_lk, 2, stickBreaking)
  
  HDP@conc_param[1] <- 1#rgamma(1, HDP@prior[5] + HDP@L - 1, HDP@prior[6] - sum(log(1-u_k[1:HDP@L-1])))
  HDP@conc_param[2] <- 1#rgamma(1, HDP@prior[7] + HDP@J*(HDP@L-1), HDP@prior[8] - sum(log(1-v_lk[-c(seq(HDP@L, HDP@J*HDP@L, HDP@L), which(v_lk==1))])))
  return(HDP)
}

#'
#' @export
selectXi.HDP <- function(HDP, DataStorage, max_lik=F, ...){
  log_prob <- DPsurv::eStep(data=DataStorage@computation, censoring=DataStorage@censoring, theta=HDP@theta, phi=HDP@phi, w=rep(1, length(HDP@phi)))
  prob <- stabilize(log_prob)
  reshape_prob <- array(prob, c(HDP@L, max(DataStorage@mask), length(DataStorage@mask)))
  
  for(i in 1:dim(reshape_prob)[3]){
    #weight each DP by their own weights (weights of the children)
    reshape_prob[,,i] <- exp(log(reshape_prob[,,i]) + log(HDP@weights[,i]))
  }
  
  reshape_prob <- matrix(reshape_prob, nrow=HDP@L)
  #xi <- vapply(as.data.frame(reshape_prob), DP_sample, numeric(1), n=nrow(reshape_prob), size=1, replace=F)
  #xi <- as.vector(xi)
  xi <- apply(reshape_prob, 2, DP_sample, n=HDP@L, size=1, replace=F, max_lik=max_lik)
  return(xi)
}

#'
#' @export
MCMC.HDP <- function(HDP, DataStorage, iter, ...){
  i <- 0
  pb <- utils::txtProgressBar(style = 3)
  while(HDP@details[['iteration']] < HDP@details[['max_iter']] & i < iter){
    
    HDP@details[['iteration']] <- HDP@details[['iteration']] + 1
    i <- i + 1
    xi <- selectXi.HDP(HDP, DataStorage)
    DataStorage@presentation$xi <- xi[!is.na(xi)]
    DataStorage@presentation$zeta <- rep(1:HDP@J, as.vector(table(DataStorage@presentation$Sample, useNA = "no")))
    HDP@Nmat <- createNmat(DataStorage, HDP@L)
    DataStorage <- DPsurv::gibbsStep(DP=HDP, DataStorage=DataStorage, xi=xi, zeta=rep(1, length(xi)))
    HDP@posterior <- DPsurv::mStep(HDP@prior, HDP@posterior, DataStorage@simulation, xi, rep(1, length(xi))) 
    if(HDP@details[["iteration"]] > HDP@details[["burnin"]] & (HDP@details[["iteration"]] %% HDP@details[["thinning"]])==0){
      utils::setTxtProgressBar(pb, i/iter)
      HDP@Chains <- list(theta=HDP@theta, phi=HDP@phi, weights=HDP@weights)
      HDP@ChainStorage <- saveChain.ChainStorage(zeta=1:HDP@J, Chains=HDP@Chains, iteration = (HDP@details[["iteration"]]-HDP@details[["burnin"]])/HDP@details[["thinning"]], ChainStorage=HDP@ChainStorage)
    }
    HDP <- update.HDP(HDP)
  }
  close(pb)
  return(HDP)
}

#'
#' @export
createNmat <- function(DataStorage, L){
  computeAtomNb <- function(vec, L){
    vec <- factor(vec, 1:L)
    table(vec, useNA = 'no')
  }
  X <- lapply(unique(DataStorage@presentation$Sample), function(ss) t(matrix(subset(DataStorage@presentation, Sample == ss)$xi)))
  Nmat <- do.call(plyr::rbind.fill.matrix, X)
  toRet <- apply(Nmat, 1, computeAtomNb, L = L)
  return(toRet)
}

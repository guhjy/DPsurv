% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/RcppExports.R
\name{gibbsStep}
\alias{gibbsStep}
\title{Augment censored data using a Gibbs step}
\usage{
gibbsStep(DP, DataStorage, xi, zeta)
}
\arguments{
\item{DP}{is an S4 object of type DP, HDP, or NDP.}

\item{xi}{is an integer vector that describes to which cluster belong an observation}

\item{zeta}{is an integer vector that describes in which cluster belong a group of observations}

\item{DataStore}{is an S4 object of the same name.}
}
\description{
Augment censored data by drawing them from a truncated normal
}


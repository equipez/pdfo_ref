! NEWUOA_MOD is a module providing a modern Fortran implementation of 
! M. J. D. Powell's NEWUOA algorithm described in 
!
! M. J. D. Powell, The NEWUOA software for unconstrained optimization
! without derivatives, In Large-Scale Nonlinear Optimization, eds. G. Di
! Pillo and M. Roma, pages 255--297, Springer, New York, US, 2006
!
! Coded by Zaikun Zhang in July 2020 based on Powell's Fortran 77 code 
! and the NEWUOA paper.


module newuoa_mod

implicit none
private
public :: newuoa


contains


subroutine newuoa(x, f, rhobeg, rhoend, eta1, eta2, gamma1, gamma2, ftarget, npt, maxfun, iprint, info)
! NEWUOA seeks the least value of a function of many variables, by a 
! trust region method that forms quadratic models by interpolation. 
! There can be some freedom in the interpolation conditions, which is 
! taken up by minimizing the Frobenius norm of the change to the second
! derivative of the quadratic model, beginning with a zero matrix. The
! arguments of the subroutine are as follows.

! N must be set to the number of variables.
!
! NPT is the number of interpolation conditions. Its value must be in 
! the interval [N+2, (N+1)(N+2)/2].
!
! Initial values of the variables must be set in X(1 : N). They will be 
! changed to the values that give the least calculated F.
!
! RHOBEG and RHOEND must be set to the initial and final values of a 
! trust region radius, so both must be positive with RHOEND<=RHOBEG.
! Typically RHOBEG should be about one tenth of the greatest expected
! change to a variable, and RHOEND should indicate the accuracy that is
! required in the final values of the variables.
!
! The value of IPRINT should be set to 0, 1, 2, 3, or 4, which controls 
! the amount of printing. Specifically, there is no output if IPRINT = 0
! and there is output only at the return if IPRINT=1. Otherwise, each
! new value of RHO is printed, with the best vector of variables so far
! and the corresponding value of the objective function. Further, each
! new value of F with its variables are output if IPRINT=3. When 
! IPRINT=4, all the output of IPRINT=3 will be recorded in a file named
! NEWUOA.output, which can be costly in terms of time and space (the 
! file will be created if it does not exist; the new output will be
! appended to the end of this file if it already exists).
!
! MAXFUN must be set to the maximal number of calls of CALFUN.
!
! FTARGET is the target function value. The minimization will terminate
! when a point with function value <= FTARGET is found. 
! 
! ETA1, ETA2, GAMMA1, and GAMMA2 are parameters not included in Powell's
! original interface. Roughly speaking, the trust region radius will be
! contracted by a factor of GAMMA1 when the reduction ratio is below 
! ETA1, and it will be elarged by a factor of GAMMA2 when the reduction
! ratio is above ETA2. Powell set ETA1 = 0.1, ETA2 = 0.7, GAMMA1 = 0.5,
! GAMMA2 = 2. See the TRRAD function in trustregion.f for details.
!
! F is the objective function value when the algorithm exit.
!
! INFO is the exit flag, which can be set to the following values
! defined in info.F:
! SMALL_TR_RADIUS: the lower bound for the trust region radius is reached;
! FTARGET_ACHIEVED: the target function value is reached;
! TRSUBP_FAILED: a trust region step failed to reduce the quadratic model;
! MAXFUN_REACHED: the objective function has been evaluated MAXFUN times;
! NAN_X: NaN occurs in x;
! NAN_INF_F: the objective function returns NaN or nearly infinite value;
! NAN_MODEL: NaN occurs in the models.
!
! Subroutine CALFUN (X, F) must be provided by the user. It must set F
! to the value of the objective function for the variables X(1 : N).

use consts_mod, only : RP, IK, ZERO, ONE, TWO, HALF, TENTH, EPS, RHOBEG_DFT, RHOEND_DFT, FTARGET_DFT, IPRINT_DFT
use newuob_mod, only : newuob
use infnan_mod, only : is_nan, is_inf

implicit none

! Inputs
integer(IK), intent(in) :: iprint
integer(IK), intent(in) :: maxfun
integer(IK), intent(in) :: npt
real(RP), intent(in) :: eta1  ! Threshold for reducing DELTA
real(RP), intent(in) :: eta2  ! Threshold for increasing DELTA
real(RP), intent(in) :: ftarget ! Target function value
real(RP), intent(in) :: gamma1 ! Factor for reducing DELTA
real(RP), intent(in) :: gamma2 ! Factor for increasing DELTA
real(RP), intent(in) :: rhobeg
real(RP), intent(in) :: rhoend

! In-outputs
real(RP), intent(inout) :: x(:)

! Outputs
integer(IK), intent(out) :: info
real(RP), intent(out) :: f

! Intermediate variables
integer(IK) :: iprint_v
integer(IK) :: maxfun_v
integer(IK) :: n
integer(IK) :: nf
integer(IK) :: npt_v
real(RP) :: eta1_v
real(RP) :: eta2_v 
real(RP) :: ftarget_v
real(RP) :: gamma1_v
real(RP) :: gamma2_v 
real(RP) :: rhobeg_v
real(RP) :: rhoend_v

! Get size
n = int(size(x), kind(n))

! If X contains NaN, replace it by ZERO.
where (is_nan(x)) 
    x = ZERO
end where

! Verify and possibly revise the inputs. RHOBEG_V is the value of RHOBEG
! after verification. The others are similar. 
rhobeg_v = rhobeg
rhoend_v = rhoend
eta1_v = eta1
eta2_v = eta2
gamma1_v = gamma1
gamma2_v = gamma2
ftarget_v = ftarget
maxfun_v = maxfun
npt_v = npt
iprint_v = iprint

! When the data is passed from the interfaces (e.g., MEX) to the Fortran
! code, RHOBEG, and RHOEND may change a bit. It was oberved in a MATLAB
! test that MEX passed 1 to Fortran as 0.99999999999999978. Therefore,
! if we set RHOEND = RHOBEG in the interfaces, then it may happen that
! RHOEND > RHOBEG, which is considered as an invalid input. To avoid
! this, we force RHOBEG and RHOEND to equal when their difference is tiny.
if ((rhobeg_v - rhoend_v) < 1.0e2_RP*EPS*max(abs(rhobeg_v), ONE))then
    rhoend_v = rhobeg_v
end if

if (rhobeg_v <= 0 .or. is_nan(rhobeg_v) .or. is_inf(rhobeg_v))then
    rhobeg_v = RHOBEG_DFT
end if
rhobeg_v = max(EPS, rhobeg_v)

if (rhoend_v < 0 .or.  rhobeg_v < rhoend .or. is_nan(rhoend_v) .or. is_inf(rhoend_v)) then
    rhoend_v = min(TENTH*rhobeg_v, RHOEND_DFT)
end if
rhoend_v = max(EPS, rhoend_v)

if (eta1_v < 0.0_RP .or. eta1_v > HALF .or. is_nan(eta1_v)) then
    eta1_v = TENTH
end if

if (eta2_v < eta1_v .or. eta2_v > 1.0_RP .or. is_nan(eta2_v)) then
   eta2_v = min(1.0_RP, max(eta1_v, 0.7_RP))
end if

if (gamma1_v <= 0.0_RP .or. gamma1_v >= 1.0_RP .or. is_nan(gamma1_v)) then
    gamma1_v = HALF
end if

if (gamma2_v <= 1.0_RP .or. is_nan(gamma2_v) .or. is_inf(gamma2_v)) then
    gamma2_v = TWO
end if

if (is_nan(ftarget_v)) then
    ftarget_v = FTARGET_DFT
end if

maxfun_v = max(int(n + 3, kind(maxfun_v)), maxfun_v)

if (npt_v < n + 2 .or. npt > min(maxfun_v - 1, ((n + 2)*(n + 1))/2)) then 
    npt_v = int(min(maxfun_v - 1, 2*n + 1), kind(npt_v))
end if

if (iprint_v /= 0 .and. iprint_v /= 1 .and. iprint_v /= 2 .and. iprint_v /= 3 .and. iprint_v /= 4) then
    iprint_v = IPRINT_DFT
end if

call newuob(iprint_v, maxfun_v, npt_v, eta1_v, eta2_v, ftarget_v, gamma1_v, gamma2_v, rhobeg_v, rhoend_v, x, nf, f, info)

end subroutine newuoa


end module newuoa_mod

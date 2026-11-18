! SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
! Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
!
! Numerical kernels for Reimann-Operator (Fortran 2008, ISO_C_BINDING).
!   ro_eigvalsh        eigenvalues of a complex Hermitian matrix (cyclic Jacobi on the
!                      real 2n x 2n embedding), ascending
!   ro_pairwise_sum    NumPy's pairwise summation order
!   ro_mean / ro_std   np.mean / np.std built on ro_pairwise_sum
!   ro_shannon         H(p) = -sum p log p after normalisation and clipping to tiny
!   ro_vn_entropy      -sum lam log lam over positive eigenvalues
!   ro_priority        J(C) = w1*I + w2*N + w3*D - w4*R, -inf on non-finite input
!   ro_zeta_q          zeta(sigma + i t) by Euler-Maclaurin in REAL(16)
!   ro_zetazero        k-th nontrivial zero (imaginary part) by Z(t) sign scan + REAL(16) refine
module ro_kernels
  use, intrinsic :: iso_c_binding
  use, intrinsic :: ieee_arithmetic
  implicit none
  integer, parameter :: qp = selected_real_kind(33, 4931)
  integer, parameter :: dp = c_double
  real(qp), parameter :: pi_q = 3.14159265358979323846264338327950288_qp
  integer, parameter :: nbern = 40
  real(qp), save :: bq(0:2*nbern)   ! B_n / n!
  logical, save :: bern_ready = .false.
contains

  ! ---------------------------------------------------------------- Jacobi
  subroutine ro_eigvalsh(n, are, aim, w) bind(C, name="ro_eigvalsh")
    integer(c_int), value :: n
    real(c_double), intent(in) :: are(n, n), aim(n, n)   ! column-major view of row-major data
    real(c_double), intent(out) :: w(n)
    real(dp), allocatable :: a(:, :), e(:)
    integer :: m, i, j, p, q, sweep
    real(dp) :: off, theta, t, c, s, tau, apq, app, aqq, g, h, scale
    m = 2 * n
    allocate(a(m, m), e(m))
    ! row-major A(r,c) is are(c,r); embedding [[Re, -Im],[Im, Re]]
    do i = 1, n
      do j = 1, n
        a(i, j) = are(j, i)
        a(i + n, j + n) = are(j, i)
        a(i, j + n) = -aim(j, i)
        a(i + n, j) = aim(j, i)
      end do
    end do
    ! symmetrise exactly as eigvalsh reads the lower triangle
    do j = 1, m
      do i = 1, j - 1
        a(i, j) = a(j, i)
      end do
    end do
    scale = 0.0_dp
    do j = 1, m
      do i = 1, m
        scale = max(scale, abs(a(i, j)))
      end do
    end do
    do sweep = 1, 100
      off = 0.0_dp
      do p = 1, m - 1
        do q = p + 1, m
          off = off + a(p, q)**2
        end do
      end do
      if (off <= (epsilon(1.0_dp) * scale)**2 * 1.0e-6_dp .or. off == 0.0_dp) exit
      do p = 1, m - 1
        do q = p + 1, m
          apq = a(p, q)
          if (apq == 0.0_dp) cycle
          app = a(p, p); aqq = a(q, q)
          theta = (aqq - app) / (2.0_dp * apq)
          t = sign(1.0_dp, theta) / (abs(theta) + sqrt(theta * theta + 1.0_dp))
          c = 1.0_dp / sqrt(t * t + 1.0_dp)
          s = t * c
          tau = s / (1.0_dp + c)
          a(p, p) = app - t * apq
          a(q, q) = aqq + t * apq
          a(p, q) = 0.0_dp; a(q, p) = 0.0_dp
          do i = 1, m
            if (i /= p .and. i /= q) then
              g = a(i, p); h = a(i, q)
              a(i, p) = g - s * (h + g * tau)
              a(i, q) = h + s * (g - h * tau)
              a(p, i) = a(i, p); a(q, i) = a(i, q)
            end if
          end do
        end do
      end do
    end do
    do i = 1, m
      e(i) = a(i, i)
    end do
    call sort_dp(e)
    do i = 1, n
      w(i) = 0.5_dp * (e(2 * i - 1) + e(2 * i))
    end do
  end subroutine ro_eigvalsh

  subroutine sort_dp(x)
    real(dp), intent(inout) :: x(:)
    integer :: i, j
    real(dp) :: v
    do i = 2, size(x)
      v = x(i); j = i - 1
      do while (j >= 1)
        if (x(j) <= v) exit
        x(j + 1) = x(j); j = j - 1
      end do
      x(j + 1) = v
    end do
  end subroutine sort_dp

  ! ---------------------------------------------------------- NumPy sums
  recursive function pw_sum(x, n) result(res)
    integer, intent(in) :: n
    real(dp), intent(in) :: x(n)
    real(dp) :: res, r(8)
    integer :: i, n2
    if (n < 8) then
      res = -0.0_dp
      do i = 1, n
        res = res + x(i)
      end do
    else if (n <= 128) then
      r = x(1:8)
      do i = 9, n - mod(n, 8), 8
        r = r + x(i:i + 7)
      end do
      res = ((r(1) + r(2)) + (r(3) + r(4))) + ((r(5) + r(6)) + (r(7) + r(8)))
      do i = n - mod(n, 8) + 1, n
        res = res + x(i)
      end do
    else
      n2 = n / 2
      n2 = n2 - mod(n2, 8)
      res = pw_sum(x(1:n2), n2) + pw_sum(x(n2 + 1:n), n - n2)
    end if
  end function pw_sum

  function ro_pairwise_sum(n, x) result(res) bind(C, name="ro_pairwise_sum")
    integer(c_int), value :: n
    real(c_double), intent(in) :: x(n)
    real(c_double) :: res
    if (n == 0) then
      res = 0.0_dp
    else
      res = pw_sum(x, int(n))
      if (res == 0.0_dp) res = abs(res) + 0.0_dp
    end if
  end function ro_pairwise_sum

  function ro_mean(n, x) result(res) bind(C, name="ro_mean")
    integer(c_int), value :: n
    real(c_double), intent(in) :: x(n)
    real(c_double) :: res
    res = ro_pairwise_sum(n, x) / real(n, dp)
  end function ro_mean

  function ro_std(n, x) result(res) bind(C, name="ro_std")
    integer(c_int), value :: n
    real(c_double), intent(in) :: x(n)
    real(c_double) :: res, mu
    real(dp), allocatable :: d(:)
    mu = ro_mean(n, x)
    allocate(d(n))
    d = abs(x - mu)
    d = d * d
    res = sqrt(ro_pairwise_sum(n, d) / real(n, dp))
  end function ro_std

  ! -------------------------------------------------------------- entropy
  function ro_shannon(n, p) result(h) bind(C, name="ro_shannon")
    integer(c_int), value :: n
    real(c_double), intent(in) :: p(n)
    real(c_double) :: h, total
    real(dp), allocatable :: q(:)
    allocate(q(n))
    total = ro_pairwise_sum(n, p)
    q = p / total
    q = max(q, tiny(1.0_dp))
    q = q * log(q)
    h = -ro_pairwise_sum(n, q)
  end function ro_shannon

  function ro_vn_entropy(n, lam) result(s) bind(C, name="ro_vn_entropy")
    integer(c_int), value :: n
    real(c_double), intent(in) :: lam(n)
    real(c_double) :: s
    real(dp), allocatable :: q(:)
    integer :: i, k
    allocate(q(n))
    k = 0
    do i = 1, n
      if (lam(i) > 0.0_dp) then
        k = k + 1
        q(k) = lam(i) * log(lam(i))
      end if
    end do
    if (k == 0) then
      s = 0.0_dp
    else
      s = -ro_pairwise_sum(int(k, c_int), q(1:k))
    end if
  end function ro_vn_entropy

  ! ------------------------------------------------------------- priority
  subroutine ro_priority(n, ent, nov, prog, res, wts, out) bind(C, name="ro_priority")
    integer(c_int), value :: n
    real(c_double), intent(in) :: ent(n), nov(n), prog(n), res(n), wts(4)
    real(c_double), intent(out) :: out(n)
    integer :: i
    do i = 1, n
      if (ieee_is_finite(ent(i)) .and. ieee_is_finite(nov(i)) .and. &
          ieee_is_finite(prog(i)) .and. ieee_is_finite(res(i))) then
        out(i) = wts(1) * ent(i) + wts(2) * nov(i) + wts(3) * prog(i) - wts(4) * res(i)
      else
        out(i) = ieee_value(1.0_dp, ieee_negative_inf)
      end if
    end do
  end subroutine ro_priority

  ! ----------------------------------------------------------------- zeta
  subroutine bern_init()
    integer :: nn, j
    real(qp) :: fact(0:2*nbern+1), acc
    if (bern_ready) return
    fact(0) = 1.0_qp
    do j = 1, 2*nbern + 1
      fact(j) = fact(j - 1) * real(j, qp)
    end do
    bq(0) = 1.0_qp
    do nn = 1, 2*nbern
      acc = 0.0_qp
      do j = 0, nn - 1
        acc = acc + bq(j) / fact(nn + 1 - j)
      end do
      bq(nn) = -acc
    end do
    bern_ready = .true.
  end subroutine bern_init

  function zeta_em(s, nterms, mterms) result(z)
    complex(qp), intent(in) :: s
    integer, intent(in) :: nterms, mterms
    complex(qp) :: z, term, poch, nps
    real(qp) :: bigN, ln
    integer :: n, k
    call bern_init()
    z = (0.0_qp, 0.0_qp)
    do n = 1, nterms - 1
      ln = log(real(n, qp))
      z = z + exp(-s * ln)
    end do
    bigN = real(nterms, qp)
    nps = exp(-s * log(bigN))
    z = z + bigN * nps / (s - 1.0_qp) + 0.5_qp * nps
    poch = s
    term = nps / bigN
    do k = 1, mterms
      z = z + bq(2 * k) * poch * term
      poch = poch * (s + real(2 * k - 1, qp)) * (s + real(2 * k, qp))
      term = term / (bigN * bigN)
    end do
  end function zeta_em

  function zeta_d(s) result(z)
    complex(dp), intent(in) :: s
    complex(dp) :: z, poch, nps, term
    real(dp) :: bigN
    integer :: n, k, nterms
    call bern_init()
    nterms = int(abs(s) / 2.0_dp) + 12
    z = (0.0_dp, 0.0_dp)
    do n = 1, nterms - 1
      z = z + exp(-s * log(real(n, dp)))
    end do
    bigN = real(nterms, dp)
    nps = exp(-s * log(bigN))
    z = z + bigN * nps / (s - 1.0_dp) + 0.5_dp * nps
    poch = s
    term = nps / bigN
    do k = 1, 12
      z = z + real(bq(2 * k), dp) * poch * term
      poch = poch * (s + real(2 * k - 1, dp)) * (s + real(2 * k, dp))
      term = term / (bigN * bigN)
    end do
  end function zeta_d

  subroutine ro_zeta_q(sig_str, t_str, slen, tlen, zre, zim, zabs) bind(C, name="ro_zeta_q")
    integer(c_int), value :: slen, tlen
    character(kind=c_char), intent(in) :: sig_str(slen), t_str(tlen)
    real(c_double), intent(out) :: zre, zim, zabs
    character(len=:), allocatable :: a, b
    real(qp) :: sig, t
    complex(qp) :: z
    integer :: i, nt
    allocate(character(len=slen) :: a)
    allocate(character(len=tlen) :: b)
    do i = 1, slen
      a(i:i) = sig_str(i)
    end do
    do i = 1, tlen
      b(i:i) = t_str(i)
    end do
    read(a, *) sig
    read(b, *) t
    nt = int(sqrt(sig * sig + t * t)) + 30
    z = zeta_em(cmplx(sig, t, qp), nt, nbern - 4)
    zre = real(real(z, qp), dp)
    zim = real(aimag(z), dp)
    zabs = real(abs(z), dp)
  end subroutine ro_zeta_q

  ! theta(t) = Im lnGamma(1/4 + i t/2) - t/2 ln pi  (REAL(16), Stirling with shift)
  function theta_q(t) result(th)
    real(qp), intent(in) :: t
    real(qp) :: th
    complex(qp) :: z, zz, lg, zinv, zpow
    integer :: j, k, m
    call bern_init()
    z = cmplx(0.25_qp, 0.5_qp * t, qp)
    m = 24
    zz = z + real(m, qp)
    lg = (zz - 0.5_qp) * log(zz) - zz + 0.5_qp * log(2.0_qp * pi_q)
    zinv = 1.0_qp / zz
    zpow = zinv
    do k = 1, 30
      ! B_2k / (2k(2k-1)) = bq(2k) * (2k)! / (2k(2k-1)) ; use factorial ratio
      lg = lg + bq(2 * k) * gamma(real(2 * k - 1, qp)) * zpow
      zpow = zpow * zinv * zinv
    end do
    do j = 0, m - 1
      lg = lg - log(z + real(j, qp))
    end do
    th = aimag(lg) - 0.5_qp * t * log(pi_q)
  end function theta_q

  function hardy_z_q(t) result(zv)
    real(qp), intent(in) :: t
    real(qp) :: zv
    complex(qp) :: z
    z = zeta_em(cmplx(0.5_qp, t, qp), int(t) + 30, nbern - 4)
    zv = real(exp(cmplx(0.0_qp, theta_q(t), qp)) * z, qp)
  end function hardy_z_q

  function hardy_z_d(t) result(zv)
    real(dp), intent(in) :: t
    real(dp) :: zv
    zv = real(exp(cmplx(0.0_dp, real(theta_q(real(t, qp)), dp), dp)) * &
              zeta_d(cmplx(0.5_dp, t, dp)), dp)
  end function hardy_z_d

  ! Zeros 1..kmax: scan Z(t) from t = 10 with step h, refine each bracket in REAL(16)
  ! (Illinois regula falsi), residual |zeta(1/2 + i t)| at the REAL(16) root.
  subroutine ro_zetazeros(kmax, h, ts, rs) bind(C, name="ro_zetazeros")
    integer(c_int), value :: kmax
    real(c_double), value :: h
    real(c_double), intent(out) :: ts(kmax), rs(kmax)
    real(dp) :: ta, tb, za, zb
    real(qp) :: a, b, fa, fb, c, fc
    integer :: cnt, it, side
    ta = 10.0_dp
    za = hardy_z_d(ta)
    cnt = 0
    do while (cnt < kmax)
      tb = ta + h
      zb = hardy_z_d(tb)
      if ((za < 0.0_dp .and. zb >= 0.0_dp) .or. (za > 0.0_dp .and. zb <= 0.0_dp)) then
        cnt = cnt + 1
        a = real(ta, qp); b = real(tb, qp)
        fa = hardy_z_q(a); fb = hardy_z_q(b)
        side = 0
        c = b
        do it = 1, 200
          c = (a * fb - b * fa) / (fb - fa)
          fc = hardy_z_q(c)
          if (fc == 0.0_qp) exit
          if (sign(1.0_qp, fc) == sign(1.0_qp, fb)) then
            b = c; fb = fc
            if (side == -1) fa = fa / 2.0_qp
            side = -1
          else
            a = c; fa = fc
            if (side == 1) fb = fb / 2.0_qp
            side = 1
          end if
          if (abs(b - a) < 1.0e-31_qp * abs(c)) exit
        end do
        ts(cnt) = real(c, dp)
        rs(cnt) = real(abs(zeta_em(cmplx(0.5_qp, c, qp), int(c) + 30, nbern - 4)), dp)
      end if
      ta = tb; za = zb
    end do
  end subroutine ro_zetazeros

  subroutine ro_zetazero(k, h, t_out, resid) bind(C, name="ro_zetazero")
    integer(c_int), value :: k
    real(c_double), value :: h
    real(c_double), intent(out) :: t_out, resid
    real(dp), allocatable :: ts(:), rs(:)
    allocate(ts(k), rs(k))
    call ro_zetazeros(k, h, ts, rs)
    t_out = ts(k); resid = rs(k)
  end subroutine ro_zetazero

end module ro_kernels

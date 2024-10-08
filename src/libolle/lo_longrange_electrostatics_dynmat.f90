submodule(lo_longrange_electrostatics) lo_longrange_electrostatics_dynmat
!!
!! Calculates dipole-dipole dynamical matrices in a variety of ways.
!!
use konstanter, only: lo_sqtol, lo_imag
use gottochblandat, only: lo_chop, lo_outerproduct, qsort, lo_clean_fractional_coordinates
implicit none

contains

!> longrange dipole-dipole dynamical matrix
module subroutine longrange_dynamical_matrix( &
    ew, p, q, born_effective_charges, born_onsite_correction, eps, D, Dx, Dy, Dz, reconly, chgmult)
    !> Ewald helper
    class(lo_ewald_parameters), intent(in) :: ew
    !> crystalstructure
    type(lo_crystalstructure), intent(in) :: p
    !> q-vector
    real(r8), dimension(3), intent(in) :: q
    !> Born effective charges
    real(r8), dimension(:, :, :), intent(in) :: born_effective_charges
    !> On-site correction for Born charges
    real(r8), dimension(:, :, :), intent(in) :: born_onsite_correction
    !> dielectric constant
    real(r8), dimension(3, 3), intent(in) :: eps
    !> dynamical matrix
    complex(r8), dimension(:, :, :, :), intent(out) :: D
    !> gradient of dynamical matrix
    complex(r8), dimension(:, :, :, :), intent(out), optional :: Dx, Dy, Dz
    !> only calculate the reciprocal sum
    logical, intent(in), optional :: reconly
    !> multiply charges
    logical, intent(in), optional :: chgmult

    complex(r8), dimension(:, :, :, :), allocatable :: D0, Dx0, Dy0, Dz0
    complex(r8), dimension(:, :, :), allocatable :: DQLx1, DQLx2, DQLy1, DQLy2, DQLz1, DQLz2
    complex(r8), dimension(:, :, :), allocatable :: DL1, DL2, DL3
    real(r8), dimension(:, :), allocatable :: ucvl
    real(r8), dimension(3, 3) :: inveps
    real(r8) :: dete
    integer :: npair
    logical :: longrange, mult, gradient

    ! Set some things and precalculate
    init: block
        integer :: a1, a2
        ! First figure out what we are going to calculate
        if (present(reconly)) then
            longrange = reconly
        else
            longrange = .false.
        end if
        if (present(chgmult)) then
            mult = chgmult
        else
            mult = .true.
        end if
        if (present(Dx)) then
            gradient = .true.
        else
            gradient = .false.
        end if

        ! inverse dielectric tensor
        inveps = lo_invert3x3matrix(eps)
        inveps = lo_chop(inveps, lo_sqtol)
        ! inverse determinant
        dete = 1.0_r8/sqrt(lo_determ(eps))

        ! Make some space for temporary things
        allocate (D0(3, 3, p%na, p%na))
        D0 = 0.0_r8

        ! Count the ucvec thing
        npair = 0
        do a1 = 1, p%na
        do a2 = a1, p%na
            npair = npair + 1
        end do
        end do
        allocate (ucvl(3, npair))
        ucvl = 0.0_r8
        npair = 0
        do a1 = 1, p%na
        do a2 = a1, p%na
            npair = npair + 1
            ucvl(:, npair) = lo_chop(p%rcart(:, a2) - p%rcart(:, a1), lo_sqtol)
        end do
        end do
        allocate (DL1(3, 3, npair))
        allocate (DL2(3, 3, npair))
        allocate (DL3(3, 3, p%na))
        DL1 = 0.0_r8
        DL2 = 0.0_r8
        DL3 = 0.0_r8
        if (gradient) then
            allocate (Dx0(3, 3, p%na, p%na))
            allocate (Dy0(3, 3, p%na, p%na))
            allocate (Dz0(3, 3, p%na, p%na))
            allocate (DQLx1(3, 3, npair))
            allocate (DQLy1(3, 3, npair))
            allocate (DQLz1(3, 3, npair))
            allocate (DQLx2(3, 3, npair))
            allocate (DQLy2(3, 3, npair))
            allocate (DQLz2(3, 3, npair))
            Dx0 = 0.0_r8
            Dy0 = 0.0_r8
            Dz0 = 0.0_r8
            DQLx1 = 0.0_r8
            DQLy1 = 0.0_r8
            DQLz1 = 0.0_r8
            DQLx2 = 0.0_r8
            DQLy2 = 0.0_r8
            DQLz2 = 0.0_r8
        end if
    end block init

    ! First the reciprocal part
    reciprocalspace: block
        complex(r8), dimension(3) :: v0
        complex(r8) :: expikr, Chi
        real(r8), dimension(3, 3) :: kkx, kky, kkz, kk
        real(r8), dimension(3) :: Gvec, Kvec, tauvec, Keps
        real(r8) :: inv4lambda2, knorm, expLambdaKnorm, ikr, invknorm, Kx, Ky, Kz, partialChi, f0
        integer :: ig, ip

        inv4lambda2 = 1.0_r8/(4.0_r8*(ew%lambda**2))
        do ig = 1, ew%n_Gvector
            Gvec = ew%Gvec(:, ig)
            Kvec = (Gvec + q)*lo_twopi
            Kvec = lo_chop((Gvec + q)*lo_twopi, lo_sqtol)
            if (lo_sqnorm(Kvec) .lt. lo_sqtol) cycle
            ! K-norm with dielectric metric
            knorm = dot_product(Kvec, matmul(eps, Kvec))
            invknorm = 1.0_r8/knorm
            expLambdaKnorm = exp(-knorm*inv4lambda2)
            ! Half of the Chi-function
            partialChi = expLambdaKnorm*invknorm
            ! do only half of all pairs
            if (gradient) then
                ! Gradients of the outer product:
                Kx = Kvec(1)
                Ky = Kvec(2)
                Kz = Kvec(3)
                ! Simple outer product
                kk = lo_outerproduct(Kvec, Kvec)
                ! Derivatives of outer product
                kkx(:, 1) = [2*Kx, Ky, Kz]
                kkx(:, 2) = [Ky, 0.0_r8, 0.0_r8]
                kkx(:, 3) = [Kz, 0.0_r8, 0.0_r8]

                kky(:, 1) = [0.0_r8, Kx, 0.0_r8]
                kky(:, 2) = [Kx, 2*Ky, Kz]
                kky(:, 3) = [0.0_r8, Kz, 0.0_r8]

                kkz(:, 1) = [0.0_r8, 0.0_r8, Kx]
                kkz(:, 2) = [0.0_r8, 0.0_r8, Ky]
                kkz(:, 3) = [Kx, Ky, 2*Kz]
                ! A few more things for the gradient
                Keps = 2*matmul(Kvec, eps)           ! Keps(i) = sum_j K_j eps_ij
                Keps = Keps*(invknorm + inv4lambda2)  ! ( 1/|K| + 1/4L^2 )
                do ip = 1, npair
                    ! First just the normal thing
                    tauvec = -ucvl(:, ip)
                    ikr = dot_product(Kvec, tauvec)
                    expikr = cmplx(cos(ikr), sin(ikr), r8)
                    chi = partialChi*expikr

                    DL1(:, :, ip) = DL1(:, :, ip) + kk*chi
                    ! Now gather more things for the gradient
                    v0 = lo_imag*tauvec - Keps
                    DQLx1(:, :, ip) = DQLx1(:, :, ip) + kk*v0(1)*Chi + kkx*Chi
                    DQLy1(:, :, ip) = DQLy1(:, :, ip) + kk*v0(2)*Chi + kky*Chi
                    DQLz1(:, :, ip) = DQLz1(:, :, ip) + kk*v0(3)*Chi + kkz*Chi
                end do
            else
                ! Outer product of the vectors
                kk = lo_outerproduct(Kvec, Kvec)
                do ip = 1, npair
                    ikr = -dot_product(Kvec, ucvl(:, ip))
                    expikr = cmplx(cos(ikr), sin(ikr), r8)
                    Chi = partialChi*expikr
                    DL1(:, :, ip) = DL1(:, :, ip) + kk*Chi
                end do
            end if
        end do
        ! and multiply in the prefactor
        f0 = 4.0_r8*lo_pi/p%volume
        DL1 = DL1*f0
        if (gradient) then
            DQLx1 = DQLx1*f0
            DQLy1 = DQLy1*f0
            DQLz1 = DQLz1*f0
        end if
    end block reciprocalspace

    if (longrange .eqv. .false.) then
        ! Realspace part
        realspace: block
            complex(r8) :: expikr
            complex(r8), dimension(3, 3) :: Hp
            real(r8), dimension(3, 3) :: H
            real(r8), dimension(3) :: Rvec, Dvec, delta
            real(r8) :: ikr, bigD, lambdacub
            integer :: ir, ip

            lambdacub = ew%lambda**3
            DL2 = 0.0_r8
            do ir = 1, ew%n_Rvector
                Rvec = ew%Rvec(:, ir)
                do ip = 1, npair
                    Dvec = lo_chop(Rvec + ucvl(:, ip), lo_sqtol)
                    ! exp(iq.r)
                    ikr = dot_product(q*lo_twopi, Rvec)
                    expikr = cmplx(cos(ikr), sin(ikr), r8)
                    ! get the delta, something with inverse dielectric tensor as the metric:
                    delta = matmul(inveps, Dvec)
                    ! get D, distance thingy
                    bigD = sqrt(dot_product(delta, Dvec))
                    ! erf function thingy
                    H = ewald_H_thingy(ew%lambda*delta, ew%lambda*bigD, inveps)
                    ! Multiply in all the prefactors
                    Hp = H*lambdacub*expikr*dete
                    ! Add it up
                    DL2(:, :, ip) = DL2(:, :, ip) + Hp
                    if (gradient) then
                        DQLx2(:, :, ip) = DQLx2(:, :, ip) + lo_imag*Rvec(1)*Hp
                        DQLy2(:, :, ip) = DQLy2(:, :, ip) + lo_imag*Rvec(2)*Hp
                        DQLz2(:, :, ip) = DQLz2(:, :, ip) + lo_imag*Rvec(3)*Hp
                    end if
                end do
            end do
        end block realspace
    end if

    if (longrange .eqv. .false.) then
        ! Connecting part
        connect: block
            integer :: a1
            real(r8), parameter :: fouroverthreesqrtpi = 0.7522527780636750_r8
            DL3 = 0.0_r8
            do a1 = 1, p%na
                DL3(:, :, a1) = (ew%lambda**3)*inveps*dete*fouroverthreesqrtpi
            end do
        end block connect
    end if

    ! And the final touches
    finalize: block
        integer :: a1, a2, i, j, ii, jj, ip
        ! I only calculated half of the things, so fix that. Also add things
        ! together.
        D0 = 0.0_r8
        ip = 0
        do a1 = 1, p%na
        do a2 = a1, p%na
            ip = ip + 1
            if (a1 .eq. a2) then
                D0(:, :, a1, a2) = DL1(:, :, ip) - DL2(:, :, ip) - DL3(:, :, a1)
            else
                D0(:, :, a1, a2) = DL1(:, :, ip) - DL2(:, :, ip)
                do i = 1, 3
                do j = 1, 3
                    D0(j, i, a2, a1) = conjg(D0(i, j, a1, a2))
                end do
                end do
            end if
        end do
        end do
        ! And the gradient, perhaps?
        if (gradient) then
            Dx0 = 0.0_r8
            Dy0 = 0.0_r8
            Dz0 = 0.0_r8
            ip = 0
            do a1 = 1, p%na
            do a2 = a1, p%na
                ip = ip + 1
                if (a1 .eq. a2) then
                    Dx0(:, :, a1, a2) = DQLx1(:, :, ip) - DQLx2(:, :, ip)
                    Dy0(:, :, a1, a2) = DQLy1(:, :, ip) - DQLy2(:, :, ip)
                    Dz0(:, :, a1, a2) = DQLz1(:, :, ip) - DQLz2(:, :, ip)
                else
                    Dx0(:, :, a1, a2) = DQLx1(:, :, ip) - DQLx2(:, :, ip)
                    Dy0(:, :, a1, a2) = DQLy1(:, :, ip) - DQLy2(:, :, ip)
                    Dz0(:, :, a1, a2) = DQLz1(:, :, ip) - DQLz2(:, :, ip)
                    do i = 1, 3
                    do j = 1, 3
                        Dx0(j, i, a2, a1) = conjg(Dx0(i, j, a1, a2))
                        Dy0(j, i, a2, a1) = conjg(Dy0(i, j, a1, a2))
                        Dz0(j, i, a2, a1) = conjg(Dz0(i, j, a1, a2))
                    end do
                    end do
                end if
            end do
            end do
        end if

        if (mult) then
            ! Multiply in the charges
            D = 0.0_r8
            do a2 = 1, p%na
            do a1 = 1, p%na
                do j = 1, 3
                do i = 1, 3
                    do jj = 1, 3
                    do ii = 1, 3
                        ! Reasonably sure this is the correct way of doing it. Or it could be transposed, who knows.
                        !D(i,j,a1,a2)=D(i,j,a1,a2)+fc%atom(a1)%Z(i,ii)*fc%atom(a2)%Z(j,jj)*D0(ii,jj,a1,a2)
                        D(i, j, a1, a2) &
                            = D(i, j, a1, a2) &
                              + born_effective_charges(i, ii, a1)*born_effective_charges(j, jj, a2)*D0(ii, jj, a1, a2)
                    end do
                    end do
                end do
                end do
            end do
            end do
            ! Add the on-site correction
            do a1 = 1, p%na
                D(:, :, a1, a1) = D(:, :, a1, a1) + born_onsite_correction(:, :, a1)
            end do
            ! And the gradient
            if (gradient) then
                Dx = 0.0_r8
                Dy = 0.0_r8
                Dz = 0.0_r8
                do a2 = 1, p%na
                do a1 = 1, p%na
                    do j = 1, 3
                    do i = 1, 3
                        do jj = 1, 3
                        do ii = 1, 3
                            Dx(i, j, a1, a2) &
                                = Dx(i, j, a1, a2) &
                                  + born_effective_charges(i, ii, a1) &
                                  *born_effective_charges(j, jj, a2)*Dx0(ii, jj, a1, a2)
                            Dy(i, j, a1, a2) &
                                = Dy(i, j, a1, a2) &
                                  + born_effective_charges(i, ii, a1) &
                                  *born_effective_charges(j, jj, a2)*Dy0(ii, jj, a1, a2)
                            Dz(i, j, a1, a2) &
                                = Dz(i, j, a1, a2) &
                                  + born_effective_charges(i, ii, a1) &
                                  *born_effective_charges(j, jj, a2)*Dz0(ii, jj, a1, a2)
                        end do
                        end do
                    end do
                    end do
                end do
                end do
            end if
        else
            ! Skip multiplying in the charges
            D = D0
        end if
        ! Remove tiny ugly numbers
        D = lo_chop(D, lo_sqtol)
    end block finalize

    ! Cleanup
    deallocate (D0)
    deallocate (Dl1)
    deallocate (Dl2)
    deallocate (Dl3)
    deallocate (ucvl)
    if (gradient) then
        deallocate (Dx0)
        deallocate (Dy0)
        deallocate (Dz0)
        deallocate (DQLx1)
        deallocate (DQLy1)
        deallocate (DQLz1)
        deallocate (DQLx2)
        deallocate (DQLy2)
        deallocate (DQLz2)
    end if
end subroutine

!> A specialized copy of the generalized routine, really fast for supercells. Only works at Gamma though.
module subroutine supercell_longrange_forceconstant(ew, born_effective_charges, eps, ss, forceconstant, thres)
    !> ewald settings
    class(lo_ewald_parameters), intent(in) :: ew
    !> Born effective charges
    real(r8), dimension(:, :, :), intent(in) :: born_effective_charges
    !> dielectric constant
    real(r8), dimension(3, 3), intent(in) :: eps
    !> supercell
    type(lo_crystalstructure), intent(in) :: ss
    !> forceconstant
    real(r8), dimension(:, :, :, :), intent(out) :: forceconstant
    !> ewald tolerance
    real(r8), intent(in) :: thres

    real(r8), dimension(:, :), allocatable :: qvecs, deltavec
    real(r8) :: inv4lambdasq
    integer, dimension(:), allocatable :: deltavecind

    ! Some shorthand
    inv4lambdasq = 1.0_r8/(4.0_r8*(ew%lambda**2))

    ! Fetch the G-vectors
    getGvecs: block
        integer, parameter :: npts = 20
        real(r8), dimension(:, :), allocatable :: dumv
        real(r8), dimension(3, npts) :: pts
        real(r8), dimension(3, 3) :: m0
        real(r8), dimension(3) :: v0
        real(r8) :: dampsum, krad, radinc, knorm, f0
        integer :: i, j, k, iter, ndim, ctr, ctrtot, nvec

        ! Start by getting the k-radius
        call lo_points_on_sphere(pts)
        krad = lo_inscribed_sphere_in_box(ss%reciprocal_latticevectors)*0.5_r8
        radinc = krad*0.25_r8
        smi: do iter = 1, 100000
            dampsum = 0.0_r8
            do i = 1, npts
                v0 = pts(:, i)*krad*lo_twopi
                knorm = 0.0_r8
                do j = 1, 3
                do k = 1, 3
                    knorm = knorm + v0(k)*eps(k, j)*v0(j)
                end do
                end do
                dampsum = dampsum + exp(-knorm*inv4lambdasq)*knorm
            end do
            if (dampsum .gt. thres) then
                krad = krad + radinc
            else
                exit smi
            end if
        end do smi
        ! get a supercell that contains this radius
        ndim = 0
        do i = 1, 100
            ndim = ndim + 1
            m0 = ss%reciprocal_latticevectors
            do j = 1, 3
                m0(:, j) = m0(:, j)*(2*ndim + 1)
            end do
            if (lo_inscribed_sphere_in_box(m0) .gt. krad + lo_tol) exit
        end do

        ! Count latticevectors
        f0 = krad**2
        nvec = (2*ndim + 1)**3 ! total number of vectors
        nvec = (nvec + 1)/2    ! index when we are at Gamma, can stop there
        ctr = 0
        ctrtot = 0
        vl1: do i = -ndim, ndim
        do j = -ndim, ndim
        do k = -ndim, ndim
            v0 = ss%fractional_to_cartesian([i, j, k]*1.0_r8, reciprocal=.true.)
            if (lo_sqnorm(v0) .lt. f0 .and. lo_sqnorm(v0) .gt. lo_sqtol) ctr = ctr + 1
            ctrtot = ctrtot + 1
            if (ctrtot .eq. nvec) exit vl1
        end do
        end do
        end do vl1
        ! store lattivectors
        allocate (qvecs(3, ctr))
        allocate (dumv(3, ctr))
        ctr = 0
        ctrtot = 0
        vl2: do i = -ndim, ndim
        do j = -ndim, ndim
        do k = -ndim, ndim
            v0 = ss%fractional_to_cartesian([i, j, k]*1.0_r8, reciprocal=.true.)
            if (lo_sqnorm(v0) .lt. f0 .and. lo_sqnorm(v0) .gt. lo_sqtol) then
                ctr = ctr + 1
                qvecs(:, ctr) = v0
            end if
            ctrtot = ctrtot + 1
            if (ctrtot .eq. nvec) exit vl2
        end do
        end do
        end do vl2
    end block getGvecs

    ! There is a lot of redundancy in the Ewald sum. Get rid of that.
    getDeltavecs: block
        real(r8), dimension(:, :), allocatable :: vl1, vl2
        real(r8), dimension(3) :: v0
        integer, dimension(:), allocatable :: ind1, ind2
        integer :: i, j, ii, jj, l, ctr
        ! Get the delta-vectors in the cell
        ctr = 0
        do i = 1, ss%na
        do j = i, ss%na
            ctr = ctr + 1
        end do
        end do
        allocate (vl1(5, ctr))
        allocate (vl2(5, ctr))
        allocate (ind1(ctr))
        allocate (ind2(ctr))
        vl1 = 0.0_r8
        vl2 = 0.0_r8
        ind1 = 0
        ind2 = 0
        ! Build a list of all vectors
        l = 0
        do i = 1, ss%na
        do j = i, ss%na
            l = l + 1
            v0 = ss%r(:, j) - ss%r(:, i)
            v0 = lo_clean_fractional_coordinates(v0 + 0.5_r8) - 0.5_r8
            ii = ss%info%index_in_unitcell(i)
            jj = ss%info%index_in_unitcell(j)
            vl1(:, l) = [v0(1), v0(2), v0(3), ii*1.0_r8, jj*1.0_r8]
        end do
        end do
        ! Sort it
        call qsort(vl1, ind1, lo_tol)
        ! Get the unique
        allocate (deltavecind(ctr))
        deltavecind = 0

        l = 1
        vl2(:, 1) = vl1(:, 1)
        deltavecind(ind1(1)) = l
        do i = 2, ctr
            if (sum(abs(vl2(:, l) - vl1(:, i))) .gt. lo_tol) then
                l = l + 1
                vl2(:, l) = vl1(:, i)
            end if
            deltavecind(ind1(i)) = l
        end do
        ! Store the deltavecs (and convert to Cartesian)
        allocate (deltavec(3, l))
        deltavec = vl2(1:3, 1:l)
        do i = 1, l
            deltavec(:, i) = ss%fractional_to_cartesian(deltavec(:, i))
        end do
    end block getDeltavecs

    dynm: block
        real(r8), dimension(:, :, :, :), allocatable :: dm
        real(r8), dimension(:, :, :), allocatable :: dKK, rDL
        real(r8), dimension(3, 3) :: m0, m1, bc1, bc2
        real(r8), dimension(3) :: Gvec
        real(r8) :: knorm, expLambdaKnorm, f0, ikr
        integer :: qi, p, pp, npair, nvec, a1, a2, i, j, ii, jj, uca1, uca2

        npair = size(deltavec, 2)
        nvec = size(qvecs, 2)

        ! Pre-calculate the K-term
        allocate (dKK(3, 3, nvec))
        dKK = 0.0_r8
        do qi = 1, nvec
            Gvec = qvecs(:, qi)*lo_twopi
            knorm = dot_product(Gvec, matmul(eps, Gvec))
            ! Some random stuff
            expLambdaKnorm = exp(-knorm*inv4lambdasq)
            f0 = expLambdaKnorm/knorm
            ! Outer product of k-vectors
            dKK(:, :, qi) = lo_outerproduct(Gvec, Gvec)*expLambdaKnorm/knorm
        end do

        ! Expensive loop
        allocate (rDL(3, 3, npair))
        rDL = 0.0_r8
        do p = 1, npair
            m0 = 0.0_r8
            do qi = 1, nvec
                ikr = -dot_product(qvecs(:, qi), deltavec(:, p))*lo_twopi
                m0 = m0 + dKK(:, :, qi)*cos(ikr)
            end do
            rDL(:, :, p) = m0
        end do

        ! prefactor and unit
        rDL = rDL*2.0_r8*(4.0_r8*lo_pi/ss%volume)

        ! unflatten it
        allocate (dm(3, 3, ss%na, ss%na))
        dm = 0.0_r8
        p = 0
        do a1 = 1, ss%na
        do a2 = a1, ss%na
            p = p + 1
            pp = deltavecind(p)
            if (a1 .eq. a2) then
                dm(:, :, a1, a2) = rDL(:, :, pp)
            else
                dm(:, :, a1, a2) = rDL(:, :, pp)
                do i = 1, 3
                do j = 1, 3
                    dm(j, i, a2, a1) = dm(i, j, a1, a2)
                end do
                end do
            end if
        end do
        end do
        dm = lo_chop(dm, 1E-13_r8)

        ! multiply in the charges. Had to add the intermediate copies here
        ! to avoid compiler bug in Ifort.
        forceconstant = 0.0_r8
        do a2 = 1, ss%na
        do a1 = 1, ss%na
            uca1 = ss%info%index_in_unitcell(a1)
            uca2 = ss%info%index_in_unitcell(a2)
            m0 = 0.0_r8
            m1 = dm(1:3, 1:3, a1, a2)
            bc1 = born_effective_charges(1:3, 1:3, uca1)
            bc2 = born_effective_charges(1:3, 1:3, uca2)
            do j = 1, 3
            do i = 1, 3
            do jj = 1, 3
            do ii = 1, 3
                ! Reasonably sure this is the correct way of doing it. Or it could be transposed, who knows.
                m0(i, j) = m0(i, j) + bc1(i, ii)*bc2(j, jj)*m1(ii, jj)
            end do
            end do
            end do
            end do
            forceconstant(1:3, 1:3, a1, a2) = m0
        end do
        end do
        ! The onsite-correction
        dm = forceconstant
        do a1 = 1, ss%na
            m0 = 0.0_r8
            do a2 = 1, ss%na
                m0 = m0 + dm(:, :, a2, a1)
            end do
            forceconstant(:, :, a1, a1) = forceconstant(:, :, a1, a1) - m0
        end do
    end block dynm
end subroutine

!> A specialized copy of the generalized routine, really fast for supercells. Only works at Gamma though.
module subroutine supercell_longrange_forceconstant_2D(ew, born_effective_charges, eps, ss, forceconstant, thres)
    !> ewald settings
    class(lo_ewald_parameters), intent(in) :: ew
    !> Born effective charges
    real(r8), dimension(:, :, :), intent(in) :: born_effective_charges
    !> dielectric constant
    real(r8), dimension(3, 3), intent(in) :: eps
    !> supercell
    type(lo_crystalstructure), intent(in) :: ss
    !> forceconstant
    real(r8), dimension(:, :, :, :), intent(out) :: forceconstant
    !> ewald tolerance
    real(r8), intent(in) :: thres

    real(r8), dimension(:, :), allocatable :: qvecs, deltavec
    real(r8) :: inv4lambdasq, L_sep
    integer, dimension(:), allocatable :: deltavecind
    integer :: iii, jjj

    write(*,*) ('Successfully in the 2D Gamma Module: ')

   
    ! Some shorthand
    inv4lambdasq = 1.0_r8/(4.0_r8*(ew%lambda**2))

    L_sep = ew%lambda 
    write(*, *) ('Main L: '),L_sep

   
    ! Fetch the G-vectors
    getGvecs: block
        integer, parameter :: npts = 20
        real(r8), dimension(:, :), allocatable :: dumv, r
        real(r8), dimension(3, npts) :: pts
        real(r8), dimension(3, 3) :: m0
        real(r8), dimension(2) :: normal_a , normal_b
        real(r8), dimension(3) :: v0
        real(r8) :: dampsum, krad, radinc, knorm, f0, offset, angle, x, y, norm_a, norm_b, height_a, height_b, krad_2D
        integer :: i, j, k, iter, ndim, ctr, ctrtot, nvec

        ! Start by getting the k-radius
        !call lo_points_on_sphere(pts)

    
        !allocate (r(3, npts))
        ! Compute the angular increment for equally spaced points
        !offset = 2.0_r8 * lo_pi / 20.0_r8 !for now i stick to 20 points on the unit circle

        ! Generate points on the unit circle
        !do i = 1, npts
        !angle = real(i - 1) * offset
        !x = cos(angle)
        !y = sin(angle)
        !r(:, i) = [x, y, 0.0_r8]
        !end do

        !krad = lo_inscribed_sphere_in_box(ss%reciprocal_latticevectors)*0.5_r8 ! this is half the radius

        normal_a = [-ss%reciprocal_latticevectors(2,1), ss%reciprocal_latticevectors(1,1)]  
        normal_b = [-ss%reciprocal_latticevectors(2,2), ss%reciprocal_latticevectors(1,2)]  
    
        norm_a = norm2(normal_a)
        norm_b = norm2(normal_b)
    
        normal_a = normal_a / norm_a
        normal_b = normal_b / norm_b
    
        height_a = abs(dot_product(normal_a, ss%reciprocal_latticevectors(1:2,2)))  
        height_b = abs(dot_product(normal_b, ss%reciprocal_latticevectors(1:2,1))) 
    
        krad_2D = 0.5_r8 * min(height_a, height_b)*0.5_r8 ! this is half the radius in 2D

        !write(*,*) ('This is krad pre optimization: '),krad
        write(*,*) ('This is krad pre optimization 2D: '),krad_2D

        radinc = krad_2D*0.25_r8
        smi: do iter = 1, 100000
            dampsum = 0.0_r8
            do i = 1, npts
                
                dampsum = dampsum + (1 - tanh(lo_twopi*krad_2D*L_sep/2)) !the norm of the gvector in 2D is nothing but the radius
                !here i want to find the gvector at which the function is largely decayed for a given L_sep
                !with this i fully seperate the 2D module from any ewald parameter, and i generate supercells that are a function of L_sep
            end do
                if (dampsum .gt. thres) then
                    krad_2D = krad_2D + radinc
                else
                    exit smi
                end if
        end do smi

        write(*,*) ('This is krad post optimization: '),krad_2D

        ! get a supercell that contains this radius
        ! AA: i assume this is fine, however can be problematic if the z-direction is not large enough 
        ndim = 0
        do i = 1, 100
            ndim = ndim + 1
            m0 = ss%reciprocal_latticevectors
            do j = 1, 3
                m0(:, j) = m0(:, j)*(2*ndim + 1)
            end do
            if (lo_inscribed_sphere_in_box(m0) .gt. krad_2D + lo_tol) exit
        end do
        write(*,*) ('This is the supercell that contains this radius: '),m0(:,:)

        ! Count latticevectors
        f0 = krad_2D**2
        nvec = (2*ndim + 1)**2 ! total number of vectors in 2D
        nvec = (nvec + 1)/2    ! index when we are at Gamma, can stop there
        write(*,*) ('This is how many times I add a supercell: '),ndim
        write(*,*) ('This is the total number of vectors: '),nvec
        ctr = 0
        ctrtot = 0
        vl1: do i = -ndim, ndim
        do j = -ndim, ndim
            v0 = ss%fractional_to_cartesian([i, j, 0]*1.0_r8, reciprocal=.true.) !strictly 2D
            if (lo_sqnorm(v0) .lt. f0 .and. lo_sqnorm(v0) .gt. lo_sqtol) ctr = ctr + 1
            ctrtot = ctrtot + 1
            if (ctrtot .eq. nvec) exit vl1
        end do
        end do vl1
        write(*,*) ('Here is ctr: '),ctr
        write(*,*) ('Here is ctrtot: '),ctrtot
        ! store lattivectors
        allocate (qvecs(3, ctr)) !the 3rd dimension is always zero
        allocate (dumv(3, ctr))
        ctr = 0
        ctrtot = 0
        vl2: do i = -ndim, ndim
        do j = -ndim, ndim
            v0 = ss%fractional_to_cartesian([i, j, 0]*1.0_r8, reciprocal=.true.)
            if (lo_sqnorm(v0) .lt. f0 .and. lo_sqnorm(v0) .gt. lo_sqtol) then
                ctr = ctr + 1
                qvecs(:, ctr) = v0
            end if
            ctrtot = ctrtot + 1
            if (ctrtot .eq. nvec) exit vl2
        end do
        end do vl2

        write(*,*) ('Getting the Gvecs in 2D: ')
        open(unit=10, file='Gvecs_2D', status='replace', action='write')
        do i = 1, ctr
            write(10, '(3F10.5)') qvecs(:, i)*lo_twopi
        end do
        close(10)


    end block getGvecs

        

    ! There is a lot of redundancy in the Ewald sum. Get rid of that.
    getDeltavecs: block
        real(r8), dimension(:, :), allocatable :: vl1, vl2
        real(r8), dimension(3) :: v0
        integer, dimension(:), allocatable :: ind1, ind2
        integer :: i, j, ii, jj, l, ctr
        ! Get the delta-vectors in the cell
        ctr = 0
        do i = 1, ss%na
        do j = i, ss%na
            ctr = ctr + 1
        end do
        end do
       ! write(*,*) ('Here is the number of atom pairs: '),ctr
        allocate (vl1(5, ctr))
        allocate (vl2(5, ctr))
        allocate (ind1(ctr))
        allocate (ind2(ctr))
        vl1 = 0.0_r8
        vl2 = 0.0_r8
        ind1 = 0
        ind2 = 0
        ! Build a list of all vectors
        l = 0
        do i = 1, ss%na
        do j = i, ss%na
            l = l + 1
            v0 = ss%r(:, j) - ss%r(:, i)
            v0 = lo_clean_fractional_coordinates(v0 + 0.5_r8) - 0.5_r8
            ii = ss%info%index_in_unitcell(i)
            jj = ss%info%index_in_unitcell(j)
            vl1(:, l) = [v0(1), v0(2), v0(3), ii*1.0_r8, jj*1.0_r8] !strictly 2D
        end do
        end do
        ! Sort it
        call qsort(vl1, ind1, lo_tol)
        ! Get the unique
        allocate (deltavecind(ctr))
        deltavecind = 0

        l = 1
        vl2(:, 1) = vl1(:, 1)
        deltavecind(ind1(1)) = l
        do i = 2, ctr
            if (sum(abs(vl2(:, l) - vl1(:, i))) .gt. lo_tol) then
                l = l + 1
                vl2(:, l) = vl1(:, i)
            end if
            deltavecind(ind1(i)) = l
        end do
        ! write(*,*) ('Here are the number of unique ones: '),l
        ! Store the deltavecs (and convert to Cartesian)
        allocate (deltavec(3, l))
        deltavec = vl2(1:3, 1:l)
        do i = 1, l
            deltavec(:, i) = ss%fractional_to_cartesian(deltavec(:, i))
        end do

       ! write(*,*) ('Getting the deltavecs: ')
       ! open(unit=10, file='deltavecs', status='replace', action='write')
       !  do i = 1, l
       !     write(10, '(3F10.5)') deltavec(:, i)
       ! end do
       ! close(10)

    end block getDeltavecs


    dynm: block
        real(r8), dimension(:, :, :, :), allocatable :: dm
        real(r8), dimension(:, :, :), allocatable :: dKK, rDL
        real(r8), dimension(3, 3) :: m0, m1, bc1, bc2
        real(r8), dimension(2,2) :: pol_in
        real(r8), dimension(3) :: Gvec
        real(r8) :: knorm_in, f0, ikr, pol_out, L, eps_out, Area, f_q, eps_in, knorm, expLambdaKnorm, G_vec_norm
        integer :: qi, p, pp, npair, nvec, a1, a2, i, j, ii, jj, uca1, uca2, counter

        npair = size(deltavec, 2)
        nvec = size(qvecs, 2)

        write (*, *) ''
        write (*, *) '2D Polar IFCs being calculated:: '
        ! AA: In this block, i implement the 2D model of Royo and Stengel: hard-coded for 2 things, the seperation parameter L and z being the out-plane direction


        L = norm2(ss%latticevectors(:,3)) 
        Area = abs(ss%latticevectors(1,1)*ss%latticevectors(2,2) - ss%latticevectors(2,1)*ss%latticevectors(1,2) )
        
    
    
        do i = 1, 2
            do j = 1, 2
                if (eps(i,j) .lt. lo_sqtol) then
                    pol_in(i,j) = 0.0_r8
                else
                    pol_in(i,j) = (L/(4.0_r8*lo_pi))*(eps(i,j) - 1)  !-in-plane polarizability
                    !pol_in(i,j) = 1.882_r8  ! royo and stengel polarizability

                end if
            end do
        end do
        pol_out = (L/(4.0_r8*lo_pi))*(1 - 1/eps(3,3)) !out-of-plane polarizability
        !pol_out = 0.310_r8 !royo and stengel polarizability


        write(*,*) ('Here is pol_in: '),pol_in(:,:)
        write(*,*) ('Here is pol_out: '),pol_out

       

        allocate (dKK(3, 3, nvec))
        dKK = 0.0_r8
        counter = 0
         do qi = 1, nvec
            Gvec = qvecs(:, qi)*lo_twopi
            G_vec_norm = sqrt( Gvec(1)*Gvec(1) + Gvec(2)*Gvec(2)  )
           
            f_q = 1 - tanh(G_vec_norm*L_sep/2.0_r8) !seperation function f(q)
            knorm_in = dot_product(Gvec(1:2), matmul(pol_in, Gvec(1:2))) 
            eps_in = 1 + (2.0_r8*lo_pi*f_q/G_vec_norm)*knorm_in 
            eps_out = 1 - (2.0_r8*lo_pi*f_q*G_vec_norm)*pol_out
            f0 = (f_q)/(G_vec_norm)
    
            ! Outer product of k-vectors: do this manually as outerproduct supports 3x1 vectors only 
            dKK(1, 1, qi) = Gvec(1)*Gvec(1)*f0/eps_in
            dKK(1, 2, qi) = Gvec(1)*Gvec(2)*f0/eps_in
            dKK(2, 1, qi) = Gvec(2)*Gvec(1)*f0/eps_in
            dKK(2, 2, qi) = Gvec(2)*Gvec(2)*f0/eps_in
            dKK(3, 3, qi) = - G_vec_norm**2 * ( f0 / eps_out )
            !counter = counter +1
        end do
        !write(*,*) ('This is how many times i skipped the true definition: '),counter

        !write(*,*) ('Here is how many times I skipped over Gvecs'),counter

        ! Expensive loop
        allocate (rDL(3, 3, npair))
        rDL = 0.0_r8
        do p = 1, npair
            m0 = 0.0_r8
            do qi = 1, nvec
                ikr = -dot_product(qvecs(:, qi), deltavec(:, p))*lo_twopi 
                m0 = m0 + dKK(:, :, qi)*cos(ikr)
            end do
            rDL(:, :, p) = m0
        end do

        ! prefactor and unit
        !rDL = rDL*2.0_r8*(4.0_r8*lo_pi/ss%volume) not sure where the first two comes from! (look at lines 188-193 there is no 2 there)
        rDL = rDL*2.0_r8*(2.0_r8*lo_pi/Area) !i keep the 2 for consistency of comparison, is it because we are calculating half the stuff somehow?
        !i think yes, look line 748
        

        ! unflatten it
        allocate (dm(3, 3, ss%na, ss%na))
        dm = 0.0_r8
        p = 0
        do a1 = 1, ss%na
        do a2 = a1, ss%na
            p = p + 1
            pp = deltavecind(p)
            if (a1 .eq. a2) then
                dm(:, :, a1, a2) = rDL(:, :, pp)
            else
                dm(:, :, a1, a2) = rDL(:, :, pp)
                do i = 1, 3
                do j = 1, 3
                    dm(j, i, a2, a1) = dm(i, j, a1, a2)
                end do
                end do
            end if
        end do
        end do
        dm = lo_chop(dm, 1E-13_r8)

        ! multiply in the charges. Had to add the intermediate copies here
        ! to avoid compiler bug in Ifort.
        forceconstant = 0.0_r8
        do a2 = 1, ss%na
        do a1 = 1, ss%na
            uca1 = ss%info%index_in_unitcell(a1)
            uca2 = ss%info%index_in_unitcell(a2)
            m0 = 0.0_r8
            m1 = dm(1:3, 1:3, a1, a2)
            bc1 = born_effective_charges(1:3, 1:3, uca1)
            bc2 = born_effective_charges(1:3, 1:3, uca2)
            bc1(3,3) = bc1(3,3)/eps(3,3) !modifying the out-plane BEC
            bc2(3,3) = bc2(3,3)/eps(3,3)
            do j = 1, 3
            do i = 1, 3
            do jj = 1, 3
            do ii = 1, 3
                ! Reasonably sure this is the correct way of doing it. Or it could be transposed, who knows.
                m0(i, j) = m0(i, j) + bc1(i, ii)*bc2(j, jj)*m1(ii, jj)
            end do
            end do
            end do
            end do
            forceconstant(1:3, 1:3, a1, a2) = m0
        end do
        end do
        ! The onsite-correction
        dm = forceconstant
        do a1 = 1, ss%na
            m0 = 0.0_r8
            do a2 = 1, ss%na
                m0 = m0 + dm(:, :, a2, a1)
            end do
            forceconstant(:, :, a1, a1) = forceconstant(:, :, a1, a1) - m0
        end do

    end block dynm
end subroutine

!> longrange dipole-dipole dynamical matrix
module subroutine longrange_dynamical_matrix_2D( &
    ew, p, q, born_effective_charges, born_onsite_correction, eps, D, Dx, Dy, Dz, reconly, chgmult)
    !> Ewald helper
    class(lo_ewald_parameters), intent(in) :: ew
    !> crystalstructure
    type(lo_crystalstructure), intent(in) :: p
    !> q-vector
    real(r8), dimension(3), intent(in) :: q
    !> Born effective charges
    real(r8), dimension(:, :, :), intent(in) :: born_effective_charges
    !> On-site correction for Born charges
    real(r8), dimension(:, :, :), intent(in) :: born_onsite_correction
    !> dielectric constant
    real(r8), dimension(3, 3), intent(in) :: eps
    !> dynamical matrix
    complex(r8), dimension(:, :, :, :), intent(out) :: D
    !> gradient of dynamical matrix
    complex(r8), dimension(:, :, :, :), intent(out), optional :: Dx, Dy, Dz
    !> only calculate the reciprocal sum
    logical, intent(in), optional :: reconly
    !> multiply charges
    logical, intent(in), optional :: chgmult

    complex(r8), dimension(:, :, :, :), allocatable :: D0, Dx0, Dy0, Dz0
    complex(r8), dimension(:, :, :), allocatable :: DQLx1, DQLx2, DQLy1, DQLy2, DQLz1, DQLz2
    complex(r8), dimension(:, :, :), allocatable :: DL1, DL2, DL3
    real(r8), dimension(:, :), allocatable :: ucvl
    real(r8), dimension(3, 3) :: inveps, bec1, bec2
    real(r8), dimension(2, 2) :: pol_in
    real(r8) :: dete, L, Area, pol_out, L_sep
    integer :: npair
    logical :: longrange, mult, gradient

    !write(*,*) ('Here is q: '),q(:)
    ! Set some things and precalculate
    init: block
        real(r8), dimension(3, 3) :: m0
        integer :: a1, a2, i, j
        real(r8) :: krad

        ! First figure out what we are going to calculate
        if (present(reconly)) then
            longrange = reconly
        else
            longrange = .false.
        end if
        if (present(chgmult)) then
            mult = chgmult
        else
            mult = .true.
        end if
        if (present(Dx)) then
            gradient = .true.
        else
            gradient = .false.
        end if

        
        !2D stuff
        L_sep = ew%lambda
        L = norm2(p%latticevectors(:,3))
        Area = abs(p%latticevectors(1,1)*p%latticevectors(2,2) - p%latticevectors(2,1)*p%latticevectors(1,2) )
        
        do i = 1, 2
            do j = 1, 2
                if (eps(i,j) .lt. lo_sqtol) then
                    pol_in(i,j) = 0.0_r8
                else
                    pol_in(i,j) = (L/(4.0_r8*lo_pi))*(eps(i,j) - 1)  !-in-plane polarizability
                    !pol_in(i,j) = 1.882_r8  !RS

                end if
            end do
        end do
        pol_out = (L/(4.0_r8*lo_pi))*(1 - 1/eps(3,3)) !out-of-plane polarizability
        !pol_out = 0.310_r8 !out-of-plane polarizability



        ! Make some space for temporary things
        allocate (D0(3, 3, p%na, p%na))
        D0 = 0.0_r8

        ! Count the ucvec thing
        npair = 0
        do a1 = 1, p%na
        do a2 = a1, p%na
            npair = npair + 1
        end do
        end do
        allocate (ucvl(3, npair))
        ucvl = 0.0_r8
        npair = 0
        do a1 = 1, p%na
        do a2 = a1, p%na
            npair = npair + 1
            ucvl(:, npair) = lo_chop(p%rcart(:, a2) - p%rcart(:, a1), lo_sqtol)
        end do
        end do
        allocate (DL1(3, 3, npair))
        allocate (DL2(3, 3, npair))
        allocate (DL3(3, 3, p%na))
        DL1 = 0.0_r8
        DL2 = 0.0_r8
        DL3 = 0.0_r8
        if (gradient) then
            allocate (Dx0(3, 3, p%na, p%na))
            allocate (Dy0(3, 3, p%na, p%na))
            allocate (Dz0(3, 3, p%na, p%na))
            allocate (DQLx1(3, 3, npair))
            allocate (DQLy1(3, 3, npair))
            allocate (DQLz1(3, 3, npair))
            allocate (DQLx2(3, 3, npair))
            allocate (DQLy2(3, 3, npair))
            allocate (DQLz2(3, 3, npair))
            Dx0 = 0.0_r8
            Dy0 = 0.0_r8
            Dz0 = 0.0_r8
            DQLx1 = 0.0_r8
            DQLy1 = 0.0_r8
            DQLz1 = 0.0_r8
            DQLx2 = 0.0_r8
            DQLy2 = 0.0_r8
            DQLz2 = 0.0_r8
        end if
    end block init

    ! First the reciprocal part
    reciprocalspace: block
        complex(r8), dimension(3) :: v0
        complex(r8) :: expikr, Chi
        real(r8), dimension(3, 3) :: kkx, kky, kkz, kk
        real(r8), dimension(3) :: Gvec, Kvec, tauvec, Keps
        real(r8) :: inv4lambda2, knorm, expLambdaKnorm, ikr, invknorm, Kx, Ky, Kz, partialChi, f0, K_vec_norm, f_q, knorm_in, eps_in, eps_out
        integer :: ig, ip

        
        do ig = 1, ew%n_Gvector
            Gvec = ew%Gvec(:, ig)
            Kvec = (Gvec + q)*lo_twopi
            Kvec = lo_chop((Gvec + q)*lo_twopi, lo_sqtol)
            K_vec_norm = sqrt(Kvec(1)*Kvec(1) + Kvec(2)*Kvec(2)) !here im skipping over all q(0,0,x)
            if (K_vec_norm**2 .lt. lo_sqtol) cycle
            !2D stuff:
            f_q = 1 - tanh(K_vec_norm*L_sep/2.0_r8) !seperation function f(q)
            knorm_in = dot_product(Kvec(1:2), matmul(pol_in, Kvec(1:2))) 
            eps_in = 1 + (2.0_r8*lo_pi*f_q/K_vec_norm)*knorm_in 
            eps_out = 1 - (2.0_r8*lo_pi*f_q*K_vec_norm)*pol_out
            f0 = (f_q)/(K_vec_norm)

           
            if (gradient) then
               !AA: not dealt with yet
                do ip = 1, npair
                    ! First just the normal thing
                    tauvec = -ucvl(:, ip)
                    ikr = dot_product(Kvec, tauvec) !becomes problematic for two-layered systems tauvec(3) = non-zero
                    expikr = cmplx(cos(ikr), sin(ikr), r8)
                    

                    DL1(1, 1, ip) = DL1(1, 1, ip) + Kvec(1)*Kvec(1)*f0*expikr/eps_in
                    DL1(1, 2, ip) = DL1(1, 2, ip) + Kvec(1)*Kvec(2)*f0*expikr/eps_in
                    DL1(2, 1, ip) = DL1(2, 1, ip) + Kvec(2)*Kvec(1)*f0*expikr/eps_in
                    DL1(2, 2, ip) = DL1(2, 2, ip) + Kvec(2)*Kvec(2)*f0*expikr/eps_in
                    DL1(3, 3, ip) = DL1(3, 3, ip) - K_vec_norm**2 * ( f0 * expikr / eps_out )

                end do
            else
                ! Outer product of the vectors
            
                do ip = 1, npair
                    ikr = -dot_product(Kvec, ucvl(:, ip))
                    expikr = cmplx(cos(ikr), sin(ikr), r8)
    
                    DL1(1, 1, ip) = DL1(1, 1, ip) + Kvec(1)*Kvec(1)*f0*expikr/eps_in
                    DL1(1, 2, ip) = DL1(1, 2, ip) + Kvec(1)*Kvec(2)*f0*expikr/eps_in
                    DL1(2, 1, ip) = DL1(2, 1, ip) + Kvec(2)*Kvec(1)*f0*expikr/eps_in
                    DL1(2, 2, ip) = DL1(2, 2, ip) + Kvec(2)*Kvec(2)*f0*expikr/eps_in
                    DL1(3, 3, ip) = DL1(3, 3, ip) - K_vec_norm**2 * ( f0 * expikr / eps_out )
                end do
            end if
        end do
        ! and multiply in the prefactor
        !f0 = 4.0_r8*lo_pi/p%volume
        f0 = 2.0_r8*lo_pi/Area

        DL1 = DL1*f0
        if (gradient) then
            DQLx1 = DQLx1*f0
            DQLy1 = DQLy1*f0
            DQLz1 = DQLz1*f0
        end if
    end block reciprocalspace

    

    ! And the final touches
    finalize: block
        integer :: a1, a2, i, j, ii, jj, ip
        ! I only calculated half of the things, so fix that. Also add things
        ! together.
        D0 = 0.0_r8
        ip = 0
        do a1 = 1, p%na
        do a2 = a1, p%na
            ip = ip + 1
            D0(:, :, a1, a2) = DL1(:, :, ip) 
            do i = 1, 3
            do j = 1, 3
                D0(j, i, a2, a1) = conjg(D0(i, j, a1, a2))
            end do
            end do
                
        end do
        end do
        ! And the gradient, perhaps?
        if (gradient) then
            Dx0 = 0.0_r8
            Dy0 = 0.0_r8
            Dz0 = 0.0_r8
            ip = 0
            do a1 = 1, p%na
            do a2 = a1, p%na
                    do i = 1, 3
                    do j = 1, 3
                        Dx0(j, i, a2, a1) = conjg(Dx0(i, j, a1, a2))
                        Dy0(j, i, a2, a1) = conjg(Dy0(i, j, a1, a2))
                        Dz0(j, i, a2, a1) = conjg(Dz0(i, j, a1, a2))
                    end do
                    end do
            end do
            end do
        end if

        if (mult) then
            ! Multiply in the charges
            D = 0.0_r8
            do a2 = 1, p%na
            do a1 = 1, p%na
                bec1 = born_effective_charges(:,:, a1)
                bec2 = born_effective_charges(:,:, a2)
                bec1(3,3) = bec1(3,3)/eps(3,3)
                bec2(3,3) = bec2(3,3)/eps(3,3)
                do j = 1, 3
                do i = 1, 3
                    do jj = 1, 3
                    do ii = 1, 3
                        ! Reasonably sure this is the correct way of doing it. Or it could be transposed, who knows.
                        !D(i,j,a1,a2)=D(i,j,a1,a2)+fc%atom(a1)%Z(i,ii)*fc%atom(a2)%Z(j,jj)*D0(ii,jj,a1,a2)
                        D(i, j, a1, a2) &
                            = D(i, j, a1, a2) &
                              + bec1(i, ii)*bec2(j, jj)*D0(ii, jj, a1, a2)
                    end do
                    end do
                end do
                end do
            end do
            end do
            ! Add the on-site correction
            do a1 = 1, p%na
                D(:, :, a1, a1) = D(:, :, a1, a1) + born_onsite_correction(:, :, a1)
            end do
            ! And the gradient
            if (gradient) then
                Dx = 0.0_r8
                Dy = 0.0_r8
                Dz = 0.0_r8
                do a2 = 1, p%na
                do a1 = 1, p%na
                    do j = 1, 3
                    do i = 1, 3
                        do jj = 1, 3
                        do ii = 1, 3
                            Dx(i, j, a1, a2) &
                                = Dx(i, j, a1, a2) &
                                  + born_effective_charges(i, ii, a1) &
                                  *born_effective_charges(j, jj, a2)*Dx0(ii, jj, a1, a2)
                            Dy(i, j, a1, a2) &
                                = Dy(i, j, a1, a2) &
                                  + born_effective_charges(i, ii, a1) &
                                  *born_effective_charges(j, jj, a2)*Dy0(ii, jj, a1, a2)
                            Dz(i, j, a1, a2) &
                                = Dz(i, j, a1, a2) &
                                  + born_effective_charges(i, ii, a1) &
                                  *born_effective_charges(j, jj, a2)*Dz0(ii, jj, a1, a2)
                        end do
                        end do
                    end do
                    end do
                end do
                end do
            end if
        else
            ! Skip multiplying in the charges
            D = D0
        end if
        ! Remove tiny ugly numbers
        D = lo_chop(D, lo_sqtol)
    end block finalize

    ! Cleanup
    deallocate (D0)
    deallocate (Dl1)
    deallocate (Dl2)
    deallocate (Dl3)
    deallocate (ucvl)
    if (gradient) then
        deallocate (Dx0)
        deallocate (Dy0)
        deallocate (Dz0)
        deallocate (DQLx1)
        deallocate (DQLy1)
        deallocate (DQLz1)
        deallocate (DQLx2)
        deallocate (DQLy2)
        deallocate (DQLz2)
    end if
end subroutine


!> No idea what this actually is. Something with distance, perhaps?
module pure function ewald_H_thingy(x, y, inveps) result(H)
    real(r8), dimension(3), intent(in) :: x
    real(r8), intent(in) :: y
    real(r8), dimension(3, 3), intent(in) :: inveps
    real(r8), dimension(3, 3) :: H

    real(r8) :: f0, f1
    real(r8) :: erfcy, invy2, invy3, expminvy2
    real(r8), parameter :: twooversqrtpi = 1.128379167095513_r8
    ! Keep everything at 0 if I'm at a self term
    if (abs(y) .lt. 1E-10_r8) then
        H = 0.0_r8
        return
    end if
    ! Pre-calculate some stuff
    erfcy = erfc(y)
    invy2 = 1.0_r8/(y*y)
    invy3 = 1.0_r8/(y*y*y)
    expminvy2 = exp(-y*y)
    f0 = invy2*(3*erfcy*invy3 + twooversqrtpi*expminvy2*(3*invy2 + 2))
    f1 = erfcy*invy3 + twooversqrtpi*expminvy2*invy2
    ! And get the H-thingy
    H(1, 1) = x(1)*x(1)*f0 - inveps(1, 1)*f1
    H(2, 1) = x(2)*x(1)*f0 - inveps(2, 1)*f1
    H(3, 1) = x(3)*x(1)*f0 - inveps(3, 1)*f1
    H(1, 2) = x(1)*x(2)*f0 - inveps(1, 2)*f1
    H(2, 2) = x(2)*x(2)*f0 - inveps(2, 2)*f1
    H(3, 2) = x(3)*x(2)*f0 - inveps(3, 2)*f1
    H(1, 3) = x(1)*x(3)*f0 - inveps(1, 3)*f1
    H(2, 3) = x(2)*x(3)*f0 - inveps(2, 3)*f1
    H(3, 3) = x(3)*x(3)*f0 - inveps(3, 3)*f1
end function

end submodule

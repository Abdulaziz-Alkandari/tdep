#include "precompilerdefinitions"
program dump_dynamical_matrices
!
use konstanter
use gottochblandat
use options
use type_qpointmesh
use type_crystalstructure
use type_forceconstant_secondorder
use type_phonon_dispersions
use lo_memtracker, only: lo_mem_helper
use mpi_wrappers, only: lo_mpi_helper

!
implicit none
!
type(lo_opts) :: opts
type(lo_crystalstructure) :: uc
type(lo_forceconstant_secondorder) :: fc
!type(lo_loto) :: loto
class(lo_qpoint_mesh), allocatable :: qp
type(lo_mem_helper) :: mem
type(lo_mpi_helper) :: mw


integer :: i,u,a1,a2,ii,jj
integer :: x,y,z
integer :: nq,nb
integer, dimension(:,:,:), allocatable :: symrel
integer, dimension(:), allocatable :: symafm
real(flyt) :: v0(3)
real(flyt), dimension(:,:), allocatable :: tnons
real(flyt), dimension(:,:), allocatable :: spinat
real(flyt), dimension(:,:), allocatable :: qpoints
real(flyt), dimension(:,:), allocatable :: rotmat
complex(flyt), dimension(:,:), allocatable :: dynmat
character(len=500) :: string
character(len=500) :: filnam


call mw%init()
call mem%init()

call opts%parse()
! get the unitcell and forceconstant
call uc%readfromfile('infile.ucposcar')
call uc%classify('bravais')

call uc%classify('bz')
call uc%classify('spacegroup',timereversal=.True.)
call fc%readfromfile(uc,'infile.forceconstant',mem,1)
! I decided to skip the electrostatic stuff, probably better to use the Abinit version or something.
!call loto%initempty()




if ( opts%readqpointsfromfile ) then
    ! The file format is simple, first line is number of q-points, the rest of the lines are a q-point
    ! in fractional coordinates.
    write (*,*) 'error: no longer reads qpt from file'
    stop -1
    u=open_file('in','infile.dynmatqpoints')
        read(u,*) nq
        lo_allocate(qpoints(3,nq))
        do i=1,nq
            read(u,*) qpoints(:,i)
            ! convert to Cartesian
            qpoints(:,i)=matmul(qpoints(:,i),uc%reciprocal_latticevectors)
            
        enddo
            write(*,*) qpoints
            write(*,*) uc%reciprocal_latticevectors(1,:)
            write(*,*) uc%reciprocal_latticevectors(2,:)
            write(*,*) uc%reciprocal_latticevectors(3,:)
    close(u)
end if

write (*,*) ' opts%meshtype opts%qgrid ',opts%meshtype, opts%qgrid

        call lo_generate_qmesh(qp,uc,opts%qgrid,'fft',timereversal=.true.,headrankonly=.false.,&
           mw=mw,mem=mem,verbosity=1)

call fc%write_to_anaddb(uc,opts%qgrid,mw,mem)

!else
!    ! automagically generate a grid. Probably a bad idea, since my version of gridgeneration and 
!    ! Abinits might be different.
!    write (*,*) ' opts%meshtype opts%qgrid ',opts%meshtype, opts%qgrid
!    select case(opts%meshtype)
!        case(1)
!            call lo_generate_qmesh(qp,uc,opts%qgrid,'monkhorst',timereversal=.true.)
!        case(2)
!            call lo_generate_qmesh(qp,uc,opts%qgrid,'fft',timereversal=.true.)
!        case(3)
!            call lo_generate_qmesh(qp,uc,opts%qgrid,'wedge',timereversal=.true.)
!    end select
!    ! rearrange these into a simple array because reasons.
!    nq=qp%nq_tot
!    lo_allocate(qpoints(3,qp%nq_tot))
!    do i=1,nq
!        qpoints(:,i)=qp%ap(i)%v 
!        ! qp%ap(i)%w is the point in the BZ, qp%ap(i)%v is the point in the reciprocal unit cell
!        ! not sure what you prefer. Should not matter.
!    enddo
!! Ok, now I have q-points, generate a bunch of dynamical matrices
!nb=uc%na*3                 ! number of bands
!lo_allocate(dynmat(nb,nb)) ! some space for the dynamical matrix
!!
!!u=open_file('out','outfile.many_dynamical_matrices_DDB')
!!close(u)
!
!
!! dummy arguments
!lo_allocate(spinat(3,uc%na)) ! some space for the dynamical matrix
!spinat = 0.0_flyt
!lo_allocate(symafm(uc%sym%n)) ! some space for the antiferro operation flags
!symafm = 1 
!lo_allocate(symrel(3,3,uc%sym%n)) ! some space for the symops
!lo_allocate(tnons(3,uc%sym%n)) ! some space for the reduced translations
!do i=1,uc%sym%n
!  symrel(:,:,i) = int( matmul(uc%inv_latticevectors, matmul(uc%sym%op(i)%m, transpose(uc%latticevectors))) )
!! CHECKED with respect to abinit output - these are correct in red coordinates 30/6/2016
!  tnons(:,i) = uc%sym%op(i)%ftr
!end do
!
!string = "generated by TDEP with lots of dummy variables"
!filnam = 'outfile.many_dynamical_matrices_DDB'
!call ddb_io_out (string, &
!    filnam, &
!    uc%na,&       ! matom 
!    1, &       ! mband
!    1,&       ! mkpt
!    uc%sym%n,&       ! msym
!    uc%nelements,&       ! mtypat
!    u,&       ! unddb
!    100401,&       ! vrsddb
!    !(/uc%latpar/lo_bohr, uc%latpar/lo_bohr, uc%latpar/lo_bohr/),&       ! acell
!    (/1.0_flyt, 1.0_flyt, 1.0_flyt/),&       ! acell
!    uc%mass(:)*lo_emu_to_amu,&       ! amu
!    1.0_flyt,&       ! dilatmx
!    1.0_flyt,&       ! ecut
!    0.0_flyt,&       ! ecutsm
!    1,&       ! intxc
!    7,&       ! iscf
!    1,&       ! ixc
!    (/0.0_flyt, 0.0_flyt, 0.0_flyt/),&       ! kpt
!    1.0_flyt, &       ! kptnrm
!    uc%na,&       ! natom
!    1,&       ! nband
!    (/10,10,10/),&       ! ngfft
!    1,&       ! nkpt
!    1,&       ! nspden
!    1,&       ! nspinor
!    1,&       ! nsppol
!    uc%sym%n,&       ! nsym
!    uc%nelements,&       ! ntypat
!    (/2.0_flyt/),&       ! occ
!    1, &       ! occopt 
!    2.0_flyt,&       ! pawecutdg
!    transpose(uc%latticevectors)/lo_A_to_bohr,&       ! rprim
!    0.0_flyt,&       ! dfpt_sciss
!    spinat,&       ! spinat
!    symafm,&       ! symafm
!    symrel,&       ! symrel
!    tnons,&       ! tnons
!    1.e-20,&       ! tolwfr
!    0.0_flyt,&       ! tphysel
!    0.001, &       ! tsmear
!    uc%species(:),&       ! typat
!    0,&       ! usepaw
!    (/0.0_flyt/),&       ! wtk
!    uc%r(:,:),&       ! xred
!    3,&       ! zion
!    13)       ! znucl
!!TODO: a few of these should be updated to the physical values for the current system: znucl kpt and so on
!
!
!write (u,*) ""
!write (u,*) "No information on the potentials yet"
!write (u,*) ""
!write (u,*) "**** Database of total energy derivatives ****"
!write (u,'(a,i4)') "Number of data blocks=  ", nq
!
!! big rotation matrix from cartesian to reduced coordinates
!lo_allocate(rotmat(nb,nb))
!rotmat = 0.0_flyt
!do a1=1,uc%na
!  do x=1,3
!    do y=1,3
!       ii=(a1-1)*3+x
!       jj=(a1-1)*3+y
!       rotmat (ii,jj) = uc%latticevectors(x,y)
!    end do
!  end do
!end do
!
!do i=1,nq    
!    q%w=qpoints(:,i)
!    write (u,*) ""
!    write (u,'(a32,12x,i8)') " 2nd derivatives (non-stat.)  - ",  uc%na*uc%na*3*3
!    !write (u,'(a32,a,i8)') " 2nd derivatives (non-stat.)  - ", "# element :  ", uc%na*uc%na*3*3
!    write (u,'(a,3es16.8,f6.1)') " qpt", matmul(qpoints(:,i),uc%inv_reciprocal_latticevectors), 1.0
!
!    call lo_get_dynamical_matrix(fc,uc,q,loto,dynmat)
!
!    ! TODO: replace by a BLAS call?
!    dynmat = matmul( rotmat, matmul(dynmat, transpose(rotmat)) )
!
!    ! this is in eV/reduced coordinate - convert to Hartree and units of electron mass
!    dynmat = dynmat / lo_eV_to_Hartree * lo_emu_to_amu 
!
!    ! write the matrix itself. No idea what you want. Please adjust this to you favourite format.
!    ! the dynamical matrix is nb x nb, flattened as
!    !
!    do a2=1,uc%na
!    do y=1,3
!      jj=(a2-1)*3+y
!      do a1=1,uc%na
!      do x=1,3
!         ii=(a1-1)*3+x
!         dynmat(ii,jj)=dynmat(ii,jj)*sqrt(uc%mass(a1)*uc%mass(a2))
!         write (u,'(4I4,2E23.15)') x,a1,y,a2, real(dynmat(ii,jj)),aimag(dynmat(ii,jj))
!      enddo
!      enddo
!    enddo
!    enddo
!    !
!!    ! In case that helps.
!!    do j=1,nb
!!    do k=1,nb
!!        write(*,*) j,k,real(dynmat(j,k)),aimag(dynmat(j,k))
!!    enddo
!!    enddo
!enddo
!close(u)
!lo_deallocate(rotmat)
!lo_deallocate(qpoints)
!lo_deallocate(dynmat)
!lo_deallocate(symafm)
!lo_deallocate(spinat)
!lo_deallocate(symrel)
!lo_deallocate(tnons)
    
end program


module comm_map_mod
  use sharp
  use healpix_types
  use fitstools
  use pix_tools
  use iso_c_binding, only : c_ptr, c_double
  use head_fits
  implicit none

  include "mpif.h"
      
  private
  public comm_map, comm_mapinfo

  type :: comm_mapinfo
     type(sharp_alm_info)  :: alm_info
     type(sharp_geom_info) :: geom_info
     integer(i4b) :: comm, myid, nprocs
     integer(i4b) :: nside, npix, nmaps, nring, np, lmax, nm, nalm
     integer(c_int), allocatable, dimension(:)   :: rings
     integer(c_int), allocatable, dimension(:)   :: ms
     integer(c_int), allocatable, dimension(:)   :: pix
     real(c_double), allocatable, dimension(:)   :: W
  end type comm_mapinfo

  type :: comm_map
     class(comm_mapinfo), pointer :: info
     real(c_double), allocatable, dimension(:,:) :: map
     real(c_double), allocatable, dimension(:,:) :: alm
   contains
     procedure     :: Y    => exec_sharp_Y
     procedure     :: Yt   => exec_sharp_Yt
     procedure     :: WYt  => exec_sharp_WYt
     procedure     :: writeFITS
     procedure     :: readFITS
  end type comm_map

  interface comm_mapinfo
     procedure constructor_mapinfo
  end interface comm_mapinfo

  interface comm_map
     procedure constructor_map
  end interface comm_map

contains

  !**************************************************
  !             Constructors
  !**************************************************
  function constructor_mapinfo(comm, nside, lmax, pol)
    implicit none
    integer(i4b),                 intent(in) :: comm, nside, lmax
    logical(lgt),                 intent(in) :: pol
    class(comm_mapinfo), pointer             :: constructor_mapinfo

    integer(i4b) :: myid, nprocs, ierr
    integer(i4b) :: m, i, j, iring, np
    integer(i4b), allocatable, dimension(:) :: pixlist

    call mpi_comm_rank(comm, myid, ierr)
    call mpi_comm_size(comm, nprocs, ierr)

    allocate(constructor_mapinfo)
    constructor_mapinfo%comm   = comm
    constructor_mapinfo%myid   = myid
    constructor_mapinfo%nprocs = nprocs
    constructor_mapinfo%nside  = nside
    constructor_mapinfo%nmaps  = 1; if (pol) constructor_mapinfo%nmaps = 3
    constructor_mapinfo%lmax   = lmax
    constructor_mapinfo%npix   = 12*nside**2

    ! Select rings and pixels
    allocate(pixlist(0:4*nside-1))
    constructor_mapinfo%nring = 0
    constructor_mapinfo%np    = 0
    do i = 1+myid, 4*nside-1, nprocs
       call in_ring(nside, i, 0.d0, pi, pixlist, np)
       constructor_mapinfo%nring = constructor_mapinfo%nring + 1
       constructor_mapinfo%np    = constructor_mapinfo%np    + np
    end do
    allocate(constructor_mapinfo%rings(constructor_mapinfo%nring))
    allocate(constructor_mapinfo%pix(constructor_mapinfo%np))
    j = 1
    do i = 1, constructor_mapinfo%nring
       constructor_mapinfo%rings(i) = 1 + myid + (i-1)*nprocs
       call in_ring(nside, constructor_mapinfo%rings(i), 0.d0, pi, pixlist, np)
       constructor_mapinfo%pix(j:j+np-1) = pixlist(0:np-1)
       j = j + np
    end do
    deallocate(pixlist)

    ! Select m's
    constructor_mapinfo%nm = 0
    do m = myid, lmax, nprocs
       constructor_mapinfo%nm   = constructor_mapinfo%nm   + 1
       constructor_mapinfo%nalm = constructor_mapinfo%nalm + 2*m+1
    end do
    allocate(constructor_mapinfo%ms(constructor_mapinfo%nm))
    do m = 1, constructor_mapinfo%nm
       constructor_mapinfo%ms(m) = myid + (m-1)*nprocs
    end do

    ! Read ring weights
    allocate(constructor_mapinfo%W(constructor_mapinfo%nring))
    constructor_mapinfo%W = 1.d0

    ! Create SHARP info structures
!!$    call sharp_make_mmajor_real_packed_alm_info(lmax, ms=constructor_mapinfo%ms, &
!!$         & alm_info=constructor_mapinfo%alm_info)
!!$    call sharp_make_healpix_geom_info(nside, rings=constructor_mapinfo%rings, &
!!$         & geom_info=constructor_mapinfo%geom_info)
    
  end function constructor_mapinfo

  function constructor_map(info, filename)
    implicit none
    class(comm_mapinfo),           intent(in), target   :: info
    character(len=*),              intent(in), optional :: filename
    class(comm_map),     pointer                        :: constructor_map

    allocate(constructor_map)
    constructor_map%info => info
    allocate(constructor_map%map(info%np,info%nmaps))

    if (present(filename)) then
       call constructor_map%readFITS(filename)
    else
       constructor_map%map = 0.d0
    end if
    
  end function constructor_map

  !**************************************************
  !             Spherical harmonic transforms
  !**************************************************

  subroutine exec_sharp_Y(self)
    implicit none

    class(comm_map), intent(inout) :: self

    
    
  end subroutine exec_sharp_Y

  subroutine exec_sharp_Yt(self)
    implicit none

    class(comm_map), intent(inout) :: self

  end subroutine exec_sharp_Yt

  subroutine exec_sharp_WYt(self)
    implicit none

    class(comm_map), intent(inout) :: self

  end subroutine exec_sharp_WYt
  
  !**************************************************
  !                   IO routines
  !**************************************************

  subroutine writeFITS(self, filename, comptype, nu_ref, unit, ttype, spectrumfile)
    implicit none

    class(comm_map),  intent(in) :: self
    character(len=*), intent(in) :: filename
    character(len=*), intent(in), optional :: comptype, unit, spectrumfile, ttype
    real(dp),         intent(in), optional :: nu_ref

    integer(i4b) :: i, nmaps, npix, np, ierr
    real(dp),     allocatable, dimension(:,:) :: map, buffer
    integer(i4b), allocatable, dimension(:)   :: p
    integer(i4b), dimension(MPI_STATUS_SIZE)  :: mpistat
    
    ! Only the root actually writes to disk; data are distributed via MPI
    npix  = self%info%npix
    nmaps = self%info%nmaps
    if (self%info%myid == 0) then

       ! Distribute to other nodes
       allocate(p(npix), map(0:npix-1,nmaps))
       map(self%info%pix,:) = self%map
       do i = 1, self%info%nprocs-1
          call mpi_recv(np,       1, MPI_INTEGER, i, 98, self%info%comm, mpistat, ierr)
          call mpi_recv(p(1:np), np, MPI_INTEGER, i, 98, self%info%comm, mpistat, ierr)
          allocate(buffer(np,nmaps))
          call mpi_recv(buffer, np*nmaps, &
               & MPI_DOUBLE_PRECISION, i, 98, self%info%comm, mpistat, ierr)
          map(p(1:np),:) = buffer(1:np,:)
          deallocate(buffer)
       end do
       call write_map(filename, map, comptype, nu_ref, unit, ttype, spectrumfile)
       deallocate(p, map)

    else
       call mpi_send(self%info%np,  1,              MPI_INTEGER, 0, 98, self%info%comm, ierr)
       call mpi_send(self%info%pix, self%info%np,   MPI_INTEGER, 0, 98, self%info%comm, ierr)
       call mpi_send(self%map,      size(self%map), MPI_DOUBLE_PRECISION, 0, 98, &
            & self%info%comm, ierr)
    end if
    
  end subroutine writeFITS
  
  subroutine readFITS(self, filename)
    implicit none

    class(comm_map),  intent(inout) :: self
    character(len=*), intent(in)    :: filename

    integer(i4b) :: i, np, npix, ordering, nside, nmaps, ierr
    real(dp),     allocatable, dimension(:,:) :: map
    integer(i4b), allocatable, dimension(:)   :: p
    integer(i4b), dimension(MPI_STATUS_SIZE)  :: mpistat

    ! Check file consistency 
    npix = getsize_fits(trim(filename), ordering=ordering, nside=nside, nmaps=nmaps)
    if (nmaps /= self%info%nmaps) then
       if (self%info%myid == 0) write(*,*) 'Incorrect nmaps in ' // trim(filename)
       call mpi_finalize(ierr)
       stop
    end if
    if (nside /= self%info%nside) then
       if (self%info%myid == 0) write(*,*) 'Incorrect nside in ' // trim(filename)
       call mpi_finalize(ierr)
       stop
    end if

    ! Only the root actually reads from disk; data are distributed via MPI
    if (self%info%myid == 0) then

       ! Read map and convert to RING format if necessary
       allocate(map(0:npix-1,nmaps))
       call input_map(filename, map, npix, nmaps)
       if (ordering == 2) then
          do i = 1, nmaps
             call convert_nest2ring(nside, map(:,i))
          end do
       end if

       ! Distribute to other nodes
       allocate(p(npix))
       self%map = map(self%info%pix,:)
       do i = 1, self%info%nprocs-1
          call mpi_recv(np,       1, MPI_INTEGER, i, 98, self%info%comm, mpistat, ierr)
          call mpi_recv(p(1:np), np, MPI_INTEGER, i, 98, self%info%comm, mpistat, ierr)
          call mpi_send(map(p(1:np),:), np*nmaps, MPI_DOUBLE_PRECISION, i, 98, &
               & self%info%comm, ierr)
       end do
       deallocate(p, map)
    else
       call mpi_send(self%info%np,               1, MPI_INTEGER, 0, 98, self%info%comm, ierr)
       call mpi_send(self%info%pix, self%info%np,   MPI_INTEGER, 0, 98, self%info%comm, ierr)
       call mpi_recv(self%map,      size(self%map), MPI_DOUBLE_PRECISION, 0, 98, &
            &  self%info%comm, mpistat, ierr)
    end if
    
  end subroutine readFITS

  subroutine write_map(filename, map, comptype, nu_ref, unit, ttype, spectrumfile)
    implicit none

    character(len=*),                   intent(in)  :: filename
    real(dp),         dimension(0:,1:), intent(in)  :: map
    character(len=*),                   intent(in), optional :: comptype, unit, spectrumfile, ttype
    real(dp),                           intent(in), optional :: nu_ref

    integer(i4b)   :: npix, nlheader, nmaps, i, nside
    logical(lgt)   :: exist, polarization

    character(len=80), dimension(1:120)    :: header
    character(len=16) :: unit_, ttype_

    npix         = size(map(:,1))
    nside        = nint(sqrt(real(npix,sp)/12.))
    nmaps        = size(map(0,:))
    polarization = (nmaps == 3)
    unit_        = '';       if (present(unit)) unit_  = unit
    ttype_       = 'Stokes'; if (present(unit)) ttype_ = ttype


    !-----------------------------------------------------------------------
    !                      write the map to FITS file
    !  This is copied from the synfast.f90 file in the Healpix package
    !-----------------------------------------------------------------------
    
    nlheader = SIZE(header)
    do i=1,nlheader
       header(i) = ""
    enddo

    ! start putting information relative to this code and run
    call add_card(header)
    call add_card(header,"COMMENT","-----------------------------------------------")
    call add_card(header,"COMMENT","     Sky Map Pixelisation Specific Keywords    ")
    call add_card(header,"COMMENT","-----------------------------------------------")
    call add_card(header,"PIXTYPE","HEALPIX","HEALPIX Pixelisation")
    call add_card(header,"ORDERING","RING",  "Pixel ordering scheme, either RING or NESTED")
    call add_card(header,"NSIDE"   ,nside,   "Resolution parameter for HEALPIX")
    call add_card(header,"FIRSTPIX",0,"First pixel # (0 based)")
    call add_card(header,"LASTPIX",npix-1,"Last pixel # (0 based)")
    call add_card(header,"BAD_DATA",  HPX_DBADVAL ,"Sentinel value given to bad pixels")
    call add_card(header) ! blank line
    call add_card(header,"COMMENT","-----------------------------------------------")
    call add_card(header,"COMMENT","     Data Description Specific Keywords       ")
    call add_card(header,"COMMENT","-----------------------------------------------")
    call add_card(header,"POLCCONV","COSMO"," Coord. convention for polarisation (COSMO/IAU)")
    call add_card(header,"INDXSCHM","IMPLICIT"," Indexing : IMPLICIT or EXPLICIT")
    call add_card(header,"GRAIN", 0, " Grain of pixel indexing")
    call add_card(header,"COMMENT","GRAIN=0 : no indexing of pixel data                         (IMPLICIT)")
    call add_card(header,"COMMENT","GRAIN=1 : 1 pixel index -> 1 pixel data                     (EXPLICIT)")
    call add_card(header,"COMMENT","GRAIN>1 : 1 pixel index -> data of GRAIN consecutive pixels (EXPLICIT)")
    call add_card(header) ! blank line
    call add_card(header,"POLAR",polarization," Polarisation included (True/False)")

    call add_card(header) ! blank line
    call add_card(header,"TTYPE1", "I_"//ttype_,"Stokes I")
    call add_card(header,"TUNIT1", unit_,"Map unit")
    call add_card(header)

    if (polarization) then
       call add_card(header,"TTYPE2", "Q_"//ttype_,"Stokes Q")
       call add_card(header,"TUNIT2", unit_,"Map unit")
       call add_card(header)
       
       call add_card(header,"TTYPE3", "U_"//ttype_,"Stokes U")
       call add_card(header,"TUNIT3", unit_,"Map unit")
       call add_card(header)
    endif
    call add_card(header,"COMMENT","-----------------------------------------------")
    call add_card(header,"COMMENT","     Commander Keywords                        ")
    call add_card(header,"COMMENT","-----------------------------------------------")
    call add_card(header,"COMMENT","Commander is a code for global CMB analysis    ")
    call add_card(header,"COMMENT","developed in collaboration between the University")
    call add_card(header,"COMMENT","of Oslo and Jet Propulsion Laboratory (NASA).  ")
    call add_card(header,"COMMENT","-----------------------------------------------")
    if (present(comptype)) call add_card(header,"COMPTYPE",trim(comptype), "Component type")
    if (present(nu_ref))   call add_card(header,"NU_REF",  nu_ref,         "Reference frequency")
    if (present(spectrumfile)) call add_card(header,"SPECFILE",  trim(spectrumfile), &
         & "Reference spectrum")
    call add_card(header,"COMMENT","-----------------------------------------------")

    call output_map(map, header, "!"//trim(filename))

  end subroutine write_map

  
  !**************************************************
  !                   Utility routines
  !**************************************************
  
end module comm_map_mod
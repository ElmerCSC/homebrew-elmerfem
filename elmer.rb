class Elmer < Formula
  desc "Open source multiphysical simulation software (finite element solver)"
  homepage "https://elmerfem.org"

  url "https://github.com/ElmerCSC/elmerfem/archive/refs/tags/release-26.2.tar.gz"
  sha256 "def442937d69234f7e1b36e902a7fcd2a428d671e62f0275bf05aeef7ebbcade"

  head "https://github.com/ElmerCSC/elmerfem.git", branch: "devel"

  # =============================================================================
  # Build Options
  # =============================================================================
  option "with-elmerice", "Build ElmerIce glaciology module"
  option "with-elmergui", "Build ElmerGUI graphical interface"
  option "with-gcc", "Use GCC instead of Clang for C/C++ compilation"
  option "with-mumps", "Build with the MUMPS sparse direct solver (requires the brewsci/num tap)"
  option "with-openmp", "Build with OpenMP support"
  option "with-testing", "Run the quick tests after build"

  # =============================================================================
  # Dependencies
  # =============================================================================

  # Build dependencies
  depends_on "cmake" => :build

  # Required: Fortran compiler (always needed regardless of C/C++ compiler choice)
  depends_on "gcc"

  # Required: Linear algebra
  depends_on "openblas"

  # Optional: Solver libraries
  # MUMPS is no longer in homebrew-core; it lives in the brewsci/num tap. Pull it
  # in only when requested so the formula still loads without that tap tapped.
  depends_on "brewsci/num/brewsci-mumps" if build.with?("mumps")
  depends_on "hypre" => :optional

  # Optional: Parallelization
  depends_on "libomp" => :optional
  depends_on "open-mpi" => :optional

  # Optional: GUI dependencies
  depends_on "opencascade" => :optional
  depends_on "qt" => :optional
  depends_on "qwt" => :optional
  depends_on "vtk" => :optional

  def install
    # Determine CMake binary
    cmake_bin = formula_opt_bin("cmake")/"cmake"
    ctest_bin = formula_opt_bin("cmake")/"ctest"

    # Compiler configuration
    gcc_formula_str = "gcc"
    gcc_formula = Formula[gcc_formula_str]
    gcc_version = gcc_formula.version.major
    use_gcc = build.with?("gcc")

    # SDK configuration
    sdk_path = MacOS.sdk_path
    sdk_version = Utils.safe_popen_read("xcrun", "--show-sdk-version").strip

    odie "Homebrew GCC requires macOS SDK 15.5 or newer (found #{sdk_version})" if build.head? && sdk_version < "15.5"

    # Build sysroot flags
    sys_root = use_gcc ? "--sysroot=#{sdk_path}" : "-isysroot #{sdk_path}"

    # Ensure the compiler is available
    unless gcc_formula.any_version_installed?
      odie "Elmer version requires #{gcc_formula_str}. Run: brew install #{gcc_formula_str}"
    end

    # Compiler flags
    c_flags = "#{sys_root} -Wno-error=implicit-function-declaration -Wno-implicit-function-declaration"
    cxx_flags = sys_root
    cxx_flags += " -Wno-deprecated-declarations" if use_gcc
    fortran_flags = ""

    # =============================================================================
    # CMake Arguments
    # =============================================================================
    cmake_args = std_cmake_args.dup

    # Compiler selection
    if use_gcc
      cmake_args << "-DCMAKE_C_COMPILER=#{gcc_formula.opt_bin}/gcc-#{gcc_version}"
      cmake_args << "-DCMAKE_CXX_COMPILER=#{gcc_formula.opt_bin}/g++-#{gcc_version}"
    else
      cmake_args << "-DCMAKE_C_COMPILER=/usr/bin/clang"
      cmake_args << "-DCMAKE_CXX_COMPILER=/usr/bin/clang++"
    end

    # Fortran always uses gfortran
    cmake_args << "-DCMAKE_Fortran_COMPILER=#{gcc_formula.opt_bin}/gfortran-#{gcc_version}"

    # Linear algebra
    blas_lib = formula_opt_lib("openblas")/shared_library("libopenblas")
    cmake_args << "-DBLAS_LIBRARIES:STRING=#{blas_lib};-lpthread"
    cmake_args << "-DLAPACK_LIBRARIES:STRING=#{blas_lib};-lpthread"

    # Optional solver features
    cmake_args << "-DWITH_ElmerIce=ON" if build.with?("elmerice")

    # NOTE: the 3 mgdyn_airgap2 tests (HYPRE BiCGStab + BoomerAMG block
    # preconditioning) abort with MPI_ABORT/Errorcode -1. This reproduces with
    # both HYPRE 2.33.0 and 3.1.0 and with either Accelerate or OpenBLAS, so it
    # is an upstream Elmer/HYPRE issue, not a build-configuration problem.
    cmake_args << "-DWITH_Hypre=ON" if build.with?("hypre")

    configure_mumps(cmake_args) if build.with?("mumps")

    cmake_args << "-DWITH_MPI=#{build.with?("open-mpi") ? "ON" : "OFF"}"

    # OpenMP configuration
    if build.with?("openmp")
      cmake_args << "-DWITH_OpenMP=ON"
      cmake_args << "-DWITH_CHOLMOD=ON"

      if use_gcc
        # GCC has built-in OpenMP support
        %w[C CXX Fortran].each do |lang|
          cmake_args << "-DOpenMP_#{lang}_FLAGS=-fopenmp"
        end
      else
        # Clang requires libomp
        libomp = Formula["libomp"]
        cmake_args << "-DOpenMP_ROOT=#{libomp.opt_prefix}"
        ENV.append "LDFLAGS", "-L#{libomp.opt_lib} -lomp"
        c_flags += " -I#{libomp.opt_include}"
        cxx_flags += " -I#{libomp.opt_include}"
      end
    end

    # =============================================================================
    # ElmerGUI Configuration
    # =============================================================================
    configure_elmergui(cmake_args, use_gcc) if build.with?("elmergui")

    # SDK and flags
    cmake_args << "-DCMAKE_OSX_SYSROOT=#{sdk_path}"
    cmake_args << "-DCMAKE_C_FLAGS=#{c_flags}"
    cmake_args << "-DCMAKE_CXX_FLAGS=#{cxx_flags}"
    cmake_args << "-DCMAKE_Fortran_FLAGS=#{fortran_flags.strip}" unless fortran_flags.strip.empty?

    cmake_args << "-DBUILD_TESTING=1" if build.with?("testing")

    # Build and install
    system cmake_bin, "-S", ".", "-B", "build", *cmake_args
    system cmake_bin, "--build", "build", "--parallel"
    system cmake_bin, "--install", "build"

    # Optionally run the upstream "quick" test suite. Failures are reported but
    # do NOT abort the install, so a fully-built keg is always produced. The
    # suite drives the build-tree ElmerSolver (via mpiexec when MPI is enabled),
    # so a broken host MPI or a single flaky case should not discard the build.
    if build.with?("testing")
      Dir.chdir("build") do
        ohai "Running quick test suite (ctest -L quick)"
        begin
          system ctest_bin, ".", "-L", "quick", "--output-on-failure"
        rescue BuildError
          opoo "Some quick tests failed (see output above); installation continues."
        end
      end
    end
  end

  def configure_mumps(cmake_args)
    cmake_args << "-DWITH_Mumps=ON"
    cmake_args << "-DMUMPS_ROOT=#{formula_opt_prefix("brewsci/num/brewsci-mumps")}"
    # brewsci-mumps is built with ScaLAPACK ordering plus (Par)Metis, so Elmer's
    # FindMumps also requires ScaLAPACK, ParMetis and Metis. Point each finder at
    # the right keg through the *_ROOT environment hints they consult. Note metis.h
    # lives in brewsci-metis (not brewsci-parmetis), so METIS_ROOT is set separately.
    ENV["SCALAPACK_ROOT"] = formula_opt_prefix("scalapack").to_s
    ENV["PARMETIS_ROOT"]  = formula_opt_prefix("brewsci/num/brewsci-parmetis").to_s
    ENV["METIS_ROOT"]     = formula_opt_prefix("brewsci/num/brewsci-metis").to_s
  end

  def configure_elmergui(cmake_args, use_gcc)
    cmake_args << "-DWITH_ELMERGUI=ON"

    if use_gcc
      # Homebrew's Qt6 is built with Clang/libc++ and exports APIs taking std:: types
      # (e.g. QDir::mkdir(std::optional<...>)) only with libc++ mangling, which
      # GCC/libstdc++ never emits -- so a GCC ElmerGUI cannot link against Qt6. Qt5's
      # API surface does not cross that std:: ABI boundary, so GCC links Qt5 cleanly.
      # This is how the branch built ElmerGUI with GCC prior to the Qt6-everywhere change.
      qt5_dep = "qt@5"
      qwt_dep = "qwt-qt5"
      dep_message = ->(p) { "ElmerGUI with --with-gcc requires #{p}. To install: brew install #{p}" }
      odie dep_message.call(qt5_dep) unless Formula[qt5_dep].any_version_installed?
      odie dep_message.call(qwt_dep) unless Formula[qwt_dep].any_version_installed?

      cmake_args << "-DWITH_QT5=ON"
      qt5_lib = formula_opt_lib(qt5_dep)
      cmake_args << "-DQt5_DIR=#{qt5_lib}/cmake/Qt5"
      # ElmerGUI FIND_PACKAGEs each Qt5 component; qt@5 is keg-only so point each
      # component at its config dir explicitly (mirrors the Qt6 branch below).
      %w[Core Gui Widgets OpenGL Xml Svg PrintSupport Script].each do |mod|
        cmake_args << "-DQt5#{mod}_DIR=#{qt5_lib}/cmake/Qt5#{mod}"
      end

      # ElmerGUI's Qt5 package list only includes Qt5Widgets on WIN32; on macOS it is
      # omitted, but the Application needs it (QT5_WRAP_UI). Add it to the list.
      inreplace "ElmerGUI/CMakeLists.txt",
                "SET(QT5_PKG_LIST Qt5OpenGL Qt5Xml Qt5Script Qt5Gui Qt5Core Qt5Svg Qt5PrintSupport)",
                "SET(QT5_PKG_LIST Qt5OpenGL Qt5Xml Qt5Script Qt5Gui Qt5Core Qt5Svg Qt5Widgets Qt5PrintSupport)"
    else
      qwt_dep = "qwt"
      cmake_args << "-DWITH_QT6=ON"
      qt_lib = formula_opt_lib("qtbase")
      cmake_args << "-DQt6_DIR=#{qt_lib}/cmake/Qt6"
      %w[Xml PrintSupport OpenGL OpenGLWidgets].each do |mod|
        cmake_args << "-DQt6#{mod}_DIR=#{qt_lib}/cmake/Qt6#{mod}"
      end
    end

    # Qwt configuration (qwt for Qt6, qwt-qt5 for Qt5)
    qwt_formula = Formula[qwt_dep]
    cmake_args << "-DWITH_QWT=ON"
    cmake_args << "-DQWT_INCLUDE_DIR=#{qwt_formula.opt_lib}/qwt.framework/Headers"
    cmake_args << "-DQWT_LIBRARY=#{qwt_formula.opt_lib}/qwt.framework/qwt"

    # Optional GUI features
    cmake_args << "-DWITH_OCC=#{build.with?("opencascade") ? "ON" : "OFF"}"
    cmake_args << "-DWITH_VTK=#{build.with?("vtk") ? "ON" : "OFF"}"
  end

  def caveats
    return if build.without?("elmergui")

    <<~EOS
      If ElmerGUI fails to run with the following error message:

        qt.qpa.plugin: Could not find the Qt platform plugin "cocoa" in ""
        This application failed to start because no Qt platform plugin could be initialized. Reinstalling the application may fix this problem.

      Try setting the following environment variable (or add the export to ~/.bash_profile):
        export QT_QPA_PLATFORM_PLUGIN_PATH=$(brew --prefix qtbase)/share/qt/plugins/platforms
    EOS
  end

  test do
    (testpath/"test.sif").write <<~EOS
      Header
        CHECK KEYWORDS Warn
        Mesh DB "." "geomstiff"
      End
      Simulation
        Max Output Level = 4
        Coordinate System = "Cartesian 2D"
        Coordinate Mapping(3) = 1 2 3
        Simulation Type = "Steady State"
        Steady State Max Iterations = 1
        Output Intervals = 1
      End
      Constants
      End
      Body 1
        Equation = 1
        Material = 1
      End
      Equation 1
        Stress Analysis = Logical True
      End
      Solver 1
        Equation = "Stress Analysis"
        Variable = "Displacement"
        Variable Dofs = 2
        Plane Stress = Logical True
        Geometric Stiffness = Logical True
        Eigen Analysis = True
        Eigen System Values = 10
        Eigen System Convergence Tolerance = Real 1.0e-6
        Linear System Scaling = Logical True
        Linear System Solver = Direct
        Optimize Bandwidth = Logical True
      End
      Solver 2
        Equation = SaveScalars
        Procedure = "SaveData" "SaveScalars"
        Show Norm = True
        Show Norm Index = 1
        Variable 1 = Displacement
        Save EigenValues = Logical True
      End
      Material 1
        Density = 1
        Youngs Modulus = 3.890733451865769e+04
        Poisson Ratio = 0.3
      End
      Boundary Condition 1
        Target Boundaries(1) = 1
        Displacement 1 = 0
        Displacement 2 = 0
      End
      Boundary Condition 2
        Target Boundaries(1) = 2
        Force 1 = 20.0
      End
      Solver 2 :: Reference Norm = Real 1.979367879952E+002
      Solver 2 :: Reference Norm Tolerance = Real 1e-3
    EOS

    (testpath/"geomstiff.grd").write <<~EOS
      #####  ElmerGrid input file for structured grid generation  ######
      Version = 210903
      Coordinate System = Cartesian 2D
      Subcell Divisions in 2D = 1 1
      Subcell Sizes 1 = 1
      Subcell Sizes 2 = 0.05
      Material Structure in 2D
        1
      End
      Materials Interval = 1 1
      Boundary Definitions
      # type     out      int
        1        -4        1        1
        2        -2        1        1
      End
      Numbering = Horizontal
      Element Degree = 2
      Element Innernodes = True
      Triangles = False
      Surface Elements = 100
      Element Ratios 1 = 1
      Element Ratios 2 = 1
      Element Densities 1 = 1
      Element Densities 2 = 1
    EOS

    system bin/"ElmerGrid", "1", "2", "geomstiff.grd"
    system bin/"ElmerSolver", "test.sif"
  end
end

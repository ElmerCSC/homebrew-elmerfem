class Elmer < Formula
  desc "Open source multiphysical simulation software (finite element solver)"
  homepage "https://elmerfem.org"

  head "https://github.com/ElmerCSC/elmerfem.git", branch: "devel"

  stable do
    url "https://github.com/ElmerCSC/elmerfem/archive/refs/tags/release-9.0.tar.gz"
    sha256 "08c5bf261e87ff37456c1aa0372db3c83efabe4473ea3ea0b8ec66f5944d1aa0"

    # CMake 3.19 for compatibility with old CHECK_TYPE_SIZE syntax
    resource "cmake" do
      url "https://github.com/Kitware/CMake/releases/download/v3.19.8/cmake-3.19.8-macos-universal.tar.gz"
      sha256 "0976d23d982af05dcbfb3aa34fcb62ead43bea27f0e3bb95222f2a78161423f2"
    end

    # Fix Qwt 6.2 <qwt_compat.h> deprecation
    patch do
      url "https://github.com/ElmerCSC/elmerfem/commit/48e9430ccb858ca5bda28b967a0c84b51e2404b2.patch?full_index=1"
      sha256 "707032d1f899dacc62ffd7c6f09aff6aaa22d6eaa353b707808bef639d774398"
    end

    # Fix Qt5 compile issue
    patch do
      url "https://github.com/ElmerCSC/elmerfem/commit/e057b0d46a6d1708a0d322bc73d70594a63de447.patch?full_index=1"
      sha256 "0abf3d771b720edd3dc27a4b0115f12e325381284b1162568dbbc780c76cf934"
    end

    # Fix DCRComplexSolve.F90 issue
    patch do
      url "https://github.com/ElmerCSC/elmerfem/commit/a28b3521f3c81bd7fe7176555815ffd1d35cf4b2.patch?full_index=1"
      sha256 "ae29e1089fa009345c941fdf11ed346bd21a776874b70f9d2bf393b4bd3e1e71"
    end

    patch do
      url "https://github.com/ElmerCSC/elmerfem/commit/96a33930ee23e785f33bcb257398f1ccca8fdf99.patch?full_index=1"
      sha256 "7935cd13ec54afe84de3ac2c3d3b676110f9926092abcfd414f913311920c09b"
    end

    patch do
      url "https://github.com/ElmerCSC/elmerfem/commit/8f9f2c703b020dc6d21cbaa1cb8b05abbbd7ded1.patch?full_index=1"
      sha256 "4372532a4bc792e4d43466c813f1962c6964389abaa62f545a311a49bda76676"
    end

    patch do
      url "https://github.com/ElmerCSC/elmerfem/commit/54fd87054f687305644b92d0525a3f0cd4423a93.patch?full_index=1"
      sha256 "ea8c5e85230d5e6a08dc04cb2e23161bca19940b9f8c092777586dcfa491dedc"
    end

    # Comment out hard-coded C/C++ compiler paths
    patch :DATA
  end

  # =============================================================================
  # Build Options
  # =============================================================================
  option "with-elmerice", "Build ElmerIce glaciology module"
  option "with-elmergui", "Build ElmerGUI graphical interface"
  option "with-gcc", "Use GCC instead of Clang for C/C++ compilation"
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
  depends_on "hypre" => :optional
  depends_on "mumps" => :optional

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
    if build.stable?
      resource("cmake").stage do
        (buildpath/"local_cmake").install "CMake.app/Contents"
      end
      cmake_bin = buildpath/"local_cmake/Contents/bin/cmake"
      ctest_bin = buildpath/"local_cmake/Contents/bin/ctest"
    else
      cmake_bin = Formula["cmake"].opt_bin/"cmake"
      ctest_bin = Formula["cmake"].opt_bin/"ctest"
    end

    # Compiler configuration
    gcc_formula_str = build.stable? ? "gcc@11" : "gcc"
    gcc_formula = Formula[gcc_formula_str]
    gcc_version = gcc_formula.version.major
    use_gcc = build.with?("gcc")

    # SDK configuration
    sdk_path = MacOS.sdk_path
    sdk_version = Utils.safe_popen_read("xcrun", "--show-sdk-version").strip

    if build.head? && sdk_version < "15.5"
      odie "Homebrew GCC requires macOS SDK 15.5 or newer (found #{sdk_version})"
    end

    # Build sysroot flags
    sys_root = use_gcc ? "--sysroot=#{sdk_path}" : "-isysroot #{sdk_path}"

    # For stable builds with GCC, try to find an older SDK if available
    if build.stable? && use_gcc
      older_sdk = Dir["/Library/Developer/CommandLineTools/SDKs/MacOSX1[0-4].sdk"].max
      if older_sdk
        sys_root = "--sysroot=#{older_sdk}"
        sdk_path = older_sdk
      else
        opoo "No older macOS SDK found; GCC build may have compatibility issues"
      end

      unless gcc_formula.any_version_installed?
        odie "Elmer version requires #{gcc_formula_str}. Run: brew install #{gcc_formula_str}"
      end
    end

    # Compiler flags
    c_flags = "#{sys_root} -Wno-error=implicit-function-declaration -Wno-implicit-function-declaration"
    cxx_flags = sys_root
    cxx_flags += " -Wno-deprecated-declarations" if build.head? && use_gcc

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
    blas_lib = Formula["openblas"].opt_lib/shared_library("libopenblas")
    cmake_args << "-DBLAS_LIBRARIES:STRING=#{blas_lib};-lpthread"
    cmake_args << "-DLAPACK_LIBRARIES:STRING=#{blas_lib};-lpthread"

    # Optional solver features
    cmake_args << "-DWITH_ElmerIce=ON" if build.with?("elmerice")
    cmake_args << "-DWITH_Hypre=ON" if build.with?("hypre")
    cmake_args << "-DWITH_Mumps=ON" if build.with?("mumps")
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

        if build.stable?
          cmake_args << "-DOpenMP_C_FLAGS=-Xpreprocessor -fopenmp"
          cmake_args << "-DOpenMP_CXX_FLAGS=-Xpreprocessor -fopenmp"
          cmake_args << "-DOpenMP_Fortran_FLAGS=-fopenmp"
        end
      end
    end

    # =============================================================================
    # ElmerGUI Configuration
    # =============================================================================
    configure_elmergui(cmake_args) if build.with?("elmergui")

    # SDK and flags
    cmake_args << "-DCMAKE_OSX_SYSROOT=#{sdk_path}"
    cmake_args << "-DCMAKE_C_FLAGS=#{c_flags}"
    cmake_args << "-DCMAKE_CXX_FLAGS=#{cxx_flags}"

    # Apply GCC/Qt compatibility patch if needed
    if build.head? && use_gcc && build.with?("elmergui")
      apply_gcc_qt6_patch
    end

    cmake_args << "-DBUILD_TESTING=1" if build.with?("testing")

    # Build and install
    system cmake_bin, "-S", ".", "-B", "build", *cmake_args
    system cmake_bin, "--build", "build", "--parallel"
    system cmake_bin, "--install", "build"
    Dir.chdir("build") do
      system ctest_bin, ".", "-L", "quick" if build.with?("testing")
    end
  end

  def configure_elmergui(cmake_args)
    cmake_args << "-DWITH_ELMERGUI=ON"

    # Qt version detection
    qt_formula = Formula["qt"]
    qt_version = qt_formula.version.major.to_i
    qwt_dep ="qwt"

    if build.head? && qt_version >= 6
      cmake_args << "-DWITH_QT6=ON"
      qt_lib = Formula["qtbase"].opt_lib
      cmake_args << "-DQt6_DIR=#{qt_lib}/cmake/Qt6"
      %w[Xml PrintSupport OpenGL OpenGLWidgets].each do |mod|
        cmake_args << "-DQt6#{mod}_DIR=#{qt_lib}/cmake/Qt6#{mod}"
      end
    else
      # stable build needs Qt5
      qt5_dep = "qt@5"
      qwt_dep ="qwt-qt5"

      qt5_installed = Formula[qt5_dep].any_version_installed?
      qwt_installed = Formula[qwt_dep].any_version_installed?

      dep_message = ->(p) { "ElmerGUI requires #{p}. To install: brew install #{p}" }
      odie dep_message.call(qt5_dep) unless qt5_installed
      odie dep_message.call(qwt_dep) unless qwt_installed

      cmake_args << "-DWITH_QT5=ON"
      cmake_args << "-DQt5_DIR=#{Formula[qt5_dep].opt_lib}/cmake/Qt5"
    end

    # Qwt configuration
    qwt_formula = Formula[qwt_dep]
    cmake_args << "-DWITH_QWT=ON"
    cmake_args << "-DQWT_INCLUDE_DIR=#{qwt_formula.opt_lib}/qwt.framework/Headers"
    cmake_args << "-DQWT_LIBRARY=#{qwt_formula.opt_lib}/qwt.framework/qwt"

    # Optional GUI features
    cmake_args << "-DWITH_OCC=#{build.with?("opencascade") ? "ON" : "OFF"}"
    cmake_args << "-DWITH_VTK=#{build.with?("vtk") ? "ON" : "OFF"}"
  end

  def apply_gcc_qt6_patch
    patch_content = <<~PATCH
      --- ElmerGUI/CMakeLists.txt
      +++ ElmerGUI/CMakeLists.txt
      @@ -35,6 +35,10 @@
         FOREACH(_pkg ${QT6_PKG_LIST})
           FIND_PACKAGE(${_pkg} PATHS ${QT6_PATH} REQUIRED)
         ENDFOREACH()
      +  
      +  IF(APPLE AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      +    SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D'QT_IGNORE_DEPRECATIONS\\(x\\)=x'")
      +  ENDIF()
         
         ADD_DEFINITIONS(-DWITH_QT6)
         MESSAGE(STATUS "  [ElmerGUI] Qt6:               " ${Qt6_FOUND})
    PATCH

    (buildpath/"qt-gcc.patch").write(patch_content)
    system "patch", "-p0", "-i", "qt-gcc.patch"
  end

  def caveats
    return if build.without?("elmergui") || build.stable?

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

__END__
--- a/CMakeLists.txt	2020-11-10 19:52:44
+++ b/CMakeLists.txt	2025-12-31 06:18:57
@@ -14,9 +14,9 @@
   # message("you need to have gcc-gfrotran installed using HomeBrew")
   # set(CMAKE_C_COMPILER "/usr/bin/gcc")
   # set(CMAKE_CXX_COMPILER "/usr/bin/g++")
-  set(CMAKE_C_COMPILER "/usr/local/bin/gcc-10")
-  set(CMAKE_CXX_COMPILER "/usr/local/bin/g++-10")
-  set(CMAKE_Fortran_COMPILER "/usr/local/bin/gfortran")
+  # set(CMAKE_C_COMPILER "/usr/local/bin/gcc-10")
+  # set(CMAKE_CXX_COMPILER "/usr/local/bin/g++-10")
+  # set(CMAKE_Fortran_COMPILER "/usr/local/bin/gfortran")
   # set(BLA_VENDOR "OpenBLAS")
   # option(HUNTER_ENABLED "Enable Hunter package manager support" OFF)
   # set (CMAKE_GENERATOR "Unix Makefiles" CACHE INTERNAL "" FORCE)
@@ -178,13 +178,6 @@
 ENDIF()

 IF(WITH_OpenMP)
-  # Advanced properties
-  MARK_AS_ADVANCED(
-    OpenMP_C_FLAGS
-    OpenMP_Fortran_FLAGS
-    OpenMP_CXX_FLAGS
-    )
-
   # Add OpenMP flags to compilation flags
   # if(APPLE)
   #   if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
@@ -204,12 +197,13 @@
   #     set(OpenMP_libiomp5_LIBRARY ${OpenMP_CXX_LIB_NAMES})
   #   endif()
   # else()
-    SET(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${OpenMP_C_FLAGS}")
-    SET(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} ${OpenMP_Fortran_FLAGS}")
-    SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")
   # endif()
 
   FIND_PACKAGE(OpenMP REQUIRED)
+
+  SET(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${OpenMP_C_FLAGS}")
+  SET(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} ${OpenMP_Fortran_FLAGS}")
+  SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")
   
   # Test compiler support for OpenMP 4.0 features used
   INCLUDE(testOpenMP40)

--- a/ElmerGUI/CMakeLists.txt	2020-11-10 19:52:44
+++ b/ElmerGUI/CMakeLists.txt	2026-01-03 06:09:27
@@ -18,8 +18,8 @@

 IF(WITH_QT5)
   MESSAGE(STATUS "------------------------------------------------")
-  IF(WIN32)
-    MESSAGE(STATUS "Qt5 Windows packaging")
+  IF(WIN32 OR APPLE)
+    MESSAGE(STATUS "Qt5 Windows/MacOS packaging")
     SET(QT5_PKG_LIST Qt5OpenGL Qt5Xml Qt5Script Qt5Gui Qt5Core Qt5Svg Qt5Widgets Qt5PrintSupport)
   ELSE()
     MESSAGE(STATUS "Qt5 non-Windows packaging")

--- a/ElmerGUI/Application/CMakeLists.txt	2020-11-10 19:52:44
+++ b/ElmerGUI/Application/CMakeLists.txt	2026-01-03 06:20:05
@@ -189,6 +189,7 @@
 ENDIF()

 IF(WITH_QT5)
+  FIND_PACKAGE(Qt5 COMPONENTS Widgets REQUIRED)
   QT5_WRAP_UI(UI_HEADERS ${FORMS})
   QT5_ADD_RESOURCES(UI_RESOURCES ElmerGUI.qrc)
   ADD_DEFINITIONS(-DWITH_QT5)

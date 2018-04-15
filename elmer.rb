class Elmer < Formula
  desc """
  Elmer finite element solver

  * Requires homebrew/science to be tapped for MUMPS.
  * OCC, VTK and QWT (for convergence plot) are not supported
  """
  homepage "http://elmerfem.org"

  head "https://github.com/ElmerCSC/elmerfem.git", :branch => "devel"

  stable do
    url "https://github.com/ElmerCSC/elmerfem/archive/release-8.2.tar.gz"
    sha256 "ed4c87895c76003dd81faa464b6d0f38225d43e584f75290df21df629d0a4ecc"
  end

  option "with-elmerice", "Build ElmerIce"
  option "with-elmergui", "Build ElmerGUI"
  option "with-openmp", "Enable OpenMP support (experimental)"
  option "with-testing", "Run the quick tests"

  depends_on "open-mpi" => [:f90, :recommended]

  depends_on "cmake" => :build
  depends_on "gcc" => :build
  depends_on "openblas"
  depends_on "scalapack"
  depends_on "hypre" => :recommended
  depends_on "mumps" => :recommended

  depends_on "qt5" if build.with? "elmergui"
  # depends_on "oce" if build.with? "elmergui"
  # depends_on "vtk" => "with-qt" if build.with? "elmergui"
  # depends_on "qwt" if build.with? "elmergui"

  def install
    cmake_args = %W[-DCMAKE_INSTALL_PREFIX=#{prefix}]
    cmake_args << "-DWITH_Hypre:BOOL=TRUE" if build.with? "hypre"
    cmake_args << "-DWITH_ElmerIce:BOOL=TRUE" if build.with? "elmerice"
    cmake_args << "-DWITH_Mumps:BOOL=TRUE" if build.with? "mumps"
    cmake_args << "-DWITH_MPI:BOOL=FALSE" if build.without? "mpi"
    cmake_args << "-DWITH_MPI:BOOL=TRUE" if build.with? "mpi"
    cmake_args << "-DWITH_OpenMP:BOOL=TRUE" if build.with? "openmp"

    exten = (OS.mac?) ? "dylib" : "so"
    cmake_args << "-DBLAS_LIBRARIES:STRING=#{Formula["openblas"].opt_lib}/libopenblas.#{exten};-lpthread"
    cmake_args << "-DLAPACK_LIBRARIES:STRING=#{Formula["openblas"].opt_lib}/libopenblas.#{exten};-lpthread"

    if build.with? "elmergui"
      cmake_args << "-DWITH_ELMERGUI:BOOL=TRUE"
      # cmake_args << "-DWITH_QWT:BOOL=TRUE"
      # cmake_args << "-DWITH_OCC:BOOL=TRUE"
      # cmake_args << "-DWITH_VTK:BOOL=TRUE"
      cmake_args << "-DQWT_INCLUDE_DIR=#{Formula["qwt"].lib}/qwt.framework/Headers"
      cmake_args << "-DWITH_QT5:BOOL=TRUE"
    end

    mkdir "build" do
      system "cmake", "../", *cmake_args, *std_cmake_args
      system "make"
      system "make", "install"
      system "ctest -L quick" if build.with? "testing"
    end
  end

  test do
    (testpath / "test.sif").write <<-EOS.undent
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

    (testpath / "geomstiff.grd").write <<-EOS.undent
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

    system "ElmerGrid", "1", "2", "geomstiff.grd"
    system "ElmerSolver", "test.sif"
  end
end

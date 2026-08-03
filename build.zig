const std = @import("std");
const builtin = @import("builtin");

// =============================================================================
// Option-B build: zig cc / libc++ via addCSourceFiles.
//
// Compiles every TU with Zig's bundled clang+libc++ (cross-ready, header-dep
// tracking, real -O), builds libxdyn STATIC (Hazard C / V2), force-includes the
// SSC libc++ serializer shim (Hazard D) on its consumers, and links the bucket-3
// dependency closure rebuilt as libc++ (yaml-cpp, HDF5-C++, Boost,
// gRPC+abseil+protobuf, gtest) from merged archives.
//
// Three targets are exercised: native, aarch64-linux-musl and x86_64-windows-gnu,
// each against its own closure. A missing one warns rather than fails, so
// `zig build --help` still works on a machine that has none.
//
// Codegen is part of the graph rather than a script to remember to run first —
// see addCodegen. The libc++ deps live under a per-target closure root —
// libcxx-<triple>, e.g. libcxx-x86_64-linux-gnu — built by tools/deps/ and overridable
// with -Ddeps=<path> or $XDYN_DEPS_<TRIPLE> (see resolveDepsRoot below). Each closure is merged
// into two archives so lld resolves the absl/gRPC circular graph on-demand within one:
//   - libxdyndeps_core.a : everything except gtest/gmock
//   - libxdyndeps_test.a : gtest + gmock + gmock_main
//
// Build options: -Ddeps=<path>  -Deigen=<path>  -Ddeps-host=<path>  -Dgit-sha=<sha>
// (`zig build --help` lists them all)
// =============================================================================

// Per-target dependency closures (same recipes, different --target): resolved in build().
// Nothing below is an absolute path baked at compile time — see resolveDepsRoot/resolveEigen.
var deps_root: []const u8 = undefined;
var eigen_include: ?[]const u8 = null;
var target_is_windows = false;
var codegen: Codegen = undefined;
var debug_build = false;
var proto_flags: []const []const u8 = undefined;

// The native build names its glibc floor instead of detecting one, exactly as tools/deps/
// already does for every closure compile. "Native" is not a stable target: zig takes the
// dynamic linker from its own PT_INTERP and the glibc *version* from whatever libc it finds
// on disk, and those need not be the same glibc. Under `nix develop` they are not — the
// linker is nixpkgs' 2.42 and the libm is the host's 2.44 — so the binary links cleanly and
// then dies at startup with "version `GLIBC_2.43' not found". The old CMake devShell hid
// this: its cc-wrapper exported LIBRARY_PATH into the nix store, so zig found one glibc for
// both. Naming the floor matches the floor the closure itself was built at
// (tools/deps/common.sh).
//
// This fixes the *version* half only. The dynamic linker path still comes from zig's own
// PT_INTERP, so a target-less build under `nix develop` still bakes a /nix/store interpreter
// and runs on this machine alone. Anything that leaves the machine -- the deploy image above
// all -- must name an explicit -Dtarget, which switches zig to /lib64/ld-linux-x86-64.so.2.
// mise's deploy:stage does exactly that, for exactly this reason.
//
// `-Dtarget=` still overrides, and the install tree is unaffected: installUnderBuildDir
// names it <arch>-<os>-<abi>, and abi stringifies as `gnu` with or without a version.
const native_default: std.Target.Query = if (builtin.os.tag == .linux)
    .{ .abi = .gnu, .glibc_version = .{ .major = 2, .minor = 28, .patch = 0 } }
else
    .{};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = native_default });
    target_is_windows = target.result.os.tag == .windows;
    deps_root = resolveDepsRoot(b, target);
    eigen_include = resolveEigen(b);
    // -Ddebug is a *boolean*, deliberately not -Doptimize=Debug. OptimizeMode
    // .Debug would drop -DNDEBUG, and protobuf declares ~InternalMetadata inline under
    // NDEBUG and out-of-line without it — against a Release-built closure that is a
    // phantom undefined symbol at link time. Keeping .ReleaseFast and appending -O0 -g
    // works because clang's *last* -O wins: xdyn's own TUs come out unoptimized with
    // full debug info while the prebuilt deps stay optimized (you do not want to step
    // into abseil). NDEBUG is defined in both modes, so struct layouts cannot diverge.
    debug_build = b.option(bool, "debug", "Build xdyn -O0 -g for gdb (deps stay optimized)") orelse false;

    installUnderBuildDir(b, target);
    codegen = addCodegen(b);
    // The SSC libc++ shim (Hazard D/G) is xdyn-side source, not a dependency
    // artifact: it lives in-tree. -include needs a path the compiler can open from
    // whatever cwd zig runs it in, hence pathFromRoot (absolute, computed at runtime).
    const shim_hpp = b.pathFromRoot("xdyn/compat/ssc_serialize_compat.hpp");
    // ReleaseFast => -O3 -DNDEBUG. NDEBUG is mandatory: the libc++ protobuf was
    // built Release, and a debug consumer fails to link on protobuf's phantom
    // ~InternalMetadata. Hardcoded for Test 1.
    const optimize: std.builtin.OptimizeMode = .ReleaseFast;

    // ---- flag sets (no -O / no -I here: Zig handles -O; includes go on the
    //      module; only scoped extras live in flags) --------------------------
    // cpp_flags force-includes the SSC libc++ shim globally: it restores the
    // SerializeMapsSetsAndVectors operator<< (Hazard D) and a vector<bool>
    // coerce overload (Hazard G) that vanish under libc++. The operators are
    // global templates, so force-including everywhere is ODR-safe.
    // -Wno-date-time: h5_version.{c,cpp} embed __DATE__/__TIME__; zig cc treats the
    // non-reproducibility as an error by default.
    const cpp_flags = withDebug(b, &.{ "-std=gnu++17", "-Wall", "-Wextra", "-Wno-deprecated", "-Wno-date-time", "-fPIC", "-include", shim_hpp });
    const sir_flags = withDebug(b, &.{ "-std=gnu++17", "-Wall", "-Wno-deprecated", "-fPIC" });
    const c_flags = withDebug(b, &.{ "-std=gnu11", "-Wall", "-Wextra", "-Wno-date-time", "-fno-common", "-fPIC" });
    // f2c.h shadows system ctype.h: scope its include to f2c C files only.
    const f2c_flags = withDebug(b, &.{ "-std=gnu11", "-Wall", "-Wextra", "-fno-common", "-fPIC", "-Iexternal/ssc/ssc/f2c" });
    proto_flags = withDebug(b, &.{ "-std=gnu++17", "-Wno-effc++", "-Wno-sign-conversion", "-Wno-unused-parameter", "-fPIC" });
    const ws_flags = withDebug(b, &.{
        "-std=gnu++17", "-Wall", "-Wextra", "-Wno-deprecated", "-fPIC",
        "-D_WEBSOCKETPP_CPP11_STL_",           "-D_WEBSOCKETPP_CPP11_THREAD_",
        "-D_WEBSOCKETPP_CPP11_FUNCTIONAL_",    "-D_WEBSOCKETPP_CPP11_SYSTEM_ERROR_",
        "-D_WEBSOCKETPP_CPP11_RANDOM_DEVICE_", "-D_WEBSOCKETPP_CPP11_MEMORY_",
        "-Iexternal/ssc/ssc/websocket/inc",    "-Iexternal/websocketpp",
    });

    // =========================================================================
    // libxdyn — one static archive of all SSC + xdyn + generated objects
    // =========================================================================
    const xdyn = b.createModule(.{ .target = target, .optimize = optimize, .link_libcpp = true });
    addCommonIncludes(b, xdyn);

    // --- SSC modules ---
    xdyn.addCSourceFiles(.{ .root = b.path("external/ssc/ssc/f2c"), .files = &f2c_sources, .flags = f2c_flags });
    addCpp(b, xdyn, "external/ssc/ssc/data_source", &.{
        "DataSource.cpp", "DataSourceModule.cpp", "SignalContainer.cpp",
        "SignalContainerTypeLists.cpp", "TypeCoercion.cpp", "PhysicalQuantity.cpp", "DataSourceDrawer.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "external/ssc/ssc/random_data_generator", &.{"DataGenerator.cpp"}, cpp_flags);
    // sir_rand.c uses C++ function-style casts → compile as C++ (Zig language override).
    xdyn.addCSourceFiles(.{ .root = b.path("external/ssc/ssc/random_data_generator"), .files = &.{"sir_rand.c"}, .flags = sir_flags, .language = .cpp });
    addCpp(b, xdyn, "external/ssc/ssc/exception_handling", &.{"Exception.cpp"}, cpp_flags);
    addCpp(b, xdyn, "external/ssc/ssc/decode_unit", &.{"DecodeUnit.cpp"}, cpp_flags);
    addCpp(b, xdyn, "external/ssc/ssc/text_file_reader", &.{"TextFileReader.cpp"}, cpp_flags);
    addCpp(b, xdyn, "external/ssc/ssc/integrate", &.{
        "TrapezoidalIntegration.cpp", "Simpson.cpp", "Integrator.cpp", "QuadPack.cpp",
        "GaussKronrod.cpp", "Rectangle.cpp", "Cumulate.cpp", "ClenshawCurtis.cpp",
        "ClenshawCurtisCosine.cpp", "ClenshawCurtisSine.cpp", "Filon.cpp", "Burcher.cpp",
    }, cpp_flags);
    xdyn.addCSourceFiles(.{ .root = b.path("external/ssc/ssc/integrate"), .files = &.{
        "d1mach.c", "dqags.c", "dqagse.c", "dqelg.c", "dqk21.c", "dqpsrt.c", "dqawoe.c",
        "dqc25f.c", "dqcheb.c", "dqk15w.c", "dqwgtf.c", "dgtsl.c", "filon.c",
    }, .flags = f2c_flags });
    addCpp(b, xdyn, "external/ssc/ssc/numeric", &.{"almost_equal.cpp"}, cpp_flags);
    addCpp(b, xdyn, "external/ssc/ssc/kinematics", &.{
        "Velocity.cpp", "rotation_matrix_builders.cpp", "EulerAngles.cpp", "Kinematics.cpp",
        "Point.cpp", "PointMatrix.cpp", "Transform.cpp", "KinematicTree.cpp",
        "Wrench.cpp", "UnsafeWrench.cpp", "coriolis_and_centripetal.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "external/ssc/ssc/interpolation", &.{
        "Splines.cpp", "NaturalSplines.cpp", "ParabolicRunoutSplines.cpp", "CubicRunoutSplines.cpp",
        "VectorOfEquallySpacedNumbers.cpp", "LinearInterpolation.cpp", "PiecewiseConstant.cpp",
        "ParabolicInterpolation.cpp", "ParabolicCoefficients.cpp", "LinearInterpolationVariableStep.cpp",
        "ConstantStepInterpolator.cpp", "Interpolator.cpp", "SplineVariableStep.cpp", "IndexFinder.cpp",
        "VariableStepInterpolation.cpp", "TwoDimensionalInterpolationVariableStep.cpp",
    }, cpp_flags);
    xdyn.addCSourceFiles(.{ .root = b.path("external/ssc/ssc/interpolation"), .files = &.{ "cubspl.c", "dgtsv.c", "xerbla.c" }, .flags = f2c_flags });
    addCpp(b, xdyn, "external/ssc/ssc/csv_file_reader", &.{"CSVFileReader.cpp"}, cpp_flags);
    addCpp(b, xdyn, "external/ssc/ssc/websocket", &.{
        "src/ConnectionMetadata.cpp", "src/WebSocketClient.cpp", "src/WebSocketMessage.cpp",
        "src/WebSocketMessageImpl.cpp", "src/WebSocketServer.cpp",
    }, ws_flags);
    addCpp(b, xdyn, "external/ssc/ssc/json", &.{"RapidJSON.cpp"}, cpp_flags);
    addCpp(b, xdyn, "external/ssc/ssc/solver", &.{"DiscreteSystem.cpp"}, cpp_flags);

    // --- xdyn modules ---
    addCpp(b, xdyn, "xdyn/binary_stl_data", &.{"generate_test_ship.cpp"}, cpp_flags);
    addCpp(b, xdyn, "xdyn/core", &.{
        "BlockedDOF.cpp", "BodyBuilder.cpp", "Body.cpp", "BodyStates.cpp",
        "BodyWithoutSurfaceForces.cpp", "BodyWithSurfaceForces.cpp", "DefaultSurfaceElevation.cpp",
        "EmergedSurfaceForceModel.cpp", "EnvironmentAndFrames.cpp", "ForceModel.cpp",
        "ImmersedSurfaceForceModel.cpp", "Observer.cpp", "Res.cpp", "Sim.cpp",
        "SimulatorBuilder.cpp", "State.cpp", "StatesFilter.cpp", "SurfaceElevationBuilder.cpp",
        "SurfaceElevationFromWaves.cpp", "SurfaceElevationInterface.cpp", "SurfaceForceModel.cpp",
        "update_kinematics.cpp", "Wrench.cpp", "yaml2eigen.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "xdyn/environment_models", &.{
        "Airy.cpp", "BretschneiderSpectrum.cpp", "Cos2sDirectionalSpreading.cpp", "DefaultWindModel.cpp",
        "DiracDirectionalSpreading.cpp", "DiracSpectralDensity.cpp", "DiscreteDirectionalWaveSpectrum.cpp",
        "discretize.cpp", "JonswapSpectrum.cpp", "LogWindVelocityProfile.cpp", "PiersonMoskowitzSpectrum.cpp",
        "PowerLawWindVelocityProfile.cpp", "Stretching.cpp", "SumOfWaveDirectionalSpreadings.cpp",
        "SumOfWaveSpectralDensities.cpp", "UniformWindVelocityProfile.cpp", "WaveDirectionalSpreading.cpp",
        "WaveModel.cpp", "WaveNumberFunctor.cpp", "WaveSpectralDensity.cpp", "WindMeanVelocityProfile.cpp",
        "WindModel.cpp", "YamlSpectraInput.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "xdyn/external_data_structures", &.{
        "YamlAngle.cpp", "YamlBody.cpp", "YamlController.cpp", "YamlCoordinates.cpp",
        "YamlDynamics6x6Matrix.cpp", "YamlDynamics.cpp", "YamlEnvironmentalConstants.cpp", "YamlGRPC.cpp",
        "YamlModel.cpp", "YamlOutput.cpp", "YamlPoint.cpp", "YamlPosition.cpp",
        "YamlRadiationDamping.cpp", "YamlRAO.cpp", "YamlRotation.cpp", "YamlSimServerInputs.cpp",
        "YamlSimulatorInput.cpp", "YamlSpeed.cpp", "YamlState.cpp", "YamlTimeSeries.cpp",
        "YamlWaveModelInput.cpp", "YamlWaveOutput.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "xdyn/external_file_formats", &.{
        "stl_reader.cpp", "stl_writer.cpp", "stl_io_hdf5.cpp", "hdb_to_ast.cpp", "pretty_print_hdb.cpp",
    }, cpp_flags);
    xdyn.addCSourceFile(.{ .file = codegen.git_sha_c, .flags = c_flags });
    addCpp(b, xdyn, "xdyn/interface_hdf5", &.{ "h5_tools.cpp", "h5_version.cpp" }, cpp_flags);
    addCpp(b, xdyn, "xdyn/interface_hdf5", &.{ "h5_tools.c", "h5_version.c" }, c_flags);
    // mesh: MeshIntersector + ClosingFacetComputer need the SSC libc++ shim.
    addCpp(b, xdyn, "xdyn/mesh", &.{
        "Mesh.cpp", "MeshBuilder.cpp", "mesh_manipulations.cpp", "CenterOfMass.cpp", "2DMeshDisplay.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "xdyn/mesh", &.{ "MeshIntersector.cpp", "ClosingFacetComputer.cpp" }, cpp_flags);
    addCpp(b, xdyn, "xdyn/yaml_parser", &.{
        "SimulatorYamlParser.cpp", "environment_parsers.cpp", "check_input_yaml.cpp",
        "external_data_structures_parsers.cpp", "parse_controllers.cpp", "parse_output.cpp",
        "parse_time_series.cpp", "parse_address.cpp", "parse_unit_value.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "xdyn/hdb_interpolators", &.{
        "HDBParser.cpp", "RadiationDampingBuilder.cpp", "History.cpp", "PrecalParserHelper.cpp",
        "PrecalParser.cpp", "RaoInterpolator.cpp", "HydroDBParser.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "xdyn/force_models", &.{
        "AbstractRaoForceModel.cpp", "AbstractWageningen.cpp", "AeroPolarForceModel.cpp", "calculate_gz.cpp",
        "ConstantForceModel.cpp", "DampingForceModel.cpp", "DiffractionForceModel.cpp", "ExactHydrostaticForceModel.cpp",
        "FastHydrostaticForceModel.cpp", "FlettnerRotorForceModel.cpp", "FroudeKrylovForceModel.cpp", "GMForceModel.cpp",
        "GravityForceModel.cpp", "HoltropMennenForceModel.cpp", "HydroPolarForceModel.cpp", "KtKqForceModel.cpp",
        "LinearDampingForceModel.cpp", "LinearFroudeKrylovForceModel.cpp", "LinearHydrostaticForceModel.cpp",
        "LinearStiffnessForceModel.cpp", "maneuvering_compiler.cpp", "maneuvering_DataSource_builder.cpp",
        "ManeuveringForceModel.cpp", "ManeuveringInternal.cpp", "MMGManeuveringForceModel.cpp", "PhaseModuleRAOEvaluator.cpp",
        "QuadraticDampingForceModel.cpp", "RadiationDampingForceModel.cpp", "ResistanceCurveForceModel.cpp", "RudderForceModel.cpp",
        "SimpleHeadingKeepingController.cpp", "SimpleStationKeepingController.cpp", "WageningenControlledForceModel.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "xdyn/grpc", &.{
        "SurfaceElevationFromGRPC.cpp", "GRPCForceModel.cpp", "ToGRPC.cpp",
        "ToGRPCCommon.cpp", "FromGRPC.cpp", "GrpcControllerInterface.cpp",
    }, cpp_flags);
    addProtoSources(b, xdyn, &.{ "wave_types", "wave_grpc", "force", "controller" });
    addCpp(b, xdyn, "xdyn/listeners_and_controllers", &.{
        "builders.cpp", "listeners.cpp", "InterpolationModule.cpp", "Controller.cpp", "PIDController.cpp",
        "GrpcController.cpp", "CSVController.cpp", "CSVLineByLineReader.cpp", "TempFile.cpp", "CSVYaml.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "xdyn/observers_and_api", &.{
        "ConfBuilder.cpp", "CoSimulationObserver.cpp", "CsvObserver.cpp", "DictObserver.cpp",
        "EverythingObserver.cpp", "gRPCProtoBufServer.cpp", "Hdf5Observer.cpp", "Hdf5WaveObserverBuilder.cpp",
        "Hdf5WaveObserver.cpp", "Hdf5WaveSpectrumObserver.cpp", "JsonObserver.cpp", "JSONSerializer.cpp",
        "ListOfObservers.cpp", "MapObserver.cpp", "SimObserver.cpp", "SimServerInputs.cpp",
        "SimulationServerObserver.cpp", "simulator_api.cpp", "TsvObserver.cpp", "WebSocketObserver.cpp",
        "XdynForCS.cpp", "XdynForME.cpp",
    }, cpp_flags);
    // demo_scripts.cpp #embeds postprocessing/{MatLab,Python}/* instead of having a
    // generator emit them as C++ string literals (migration-plan A8). #embed is
    // C23 and clang takes it in C++ only as an extension, hence the extra -Wno; the
    // embedded files land in the depfile, so the cache invalidates on script edits.
    addCpp(b, xdyn, "xdyn/observers_and_api", &.{"demo_scripts.cpp"}, withFlags(b, cpp_flags, &.{"-Wno-c23-extensions"}));
    // make_sim_for_GZ.cpp is intentionally NOT in libxdyn: only the gz exe and the
    // GZ tests use it, and GZCurveTest.cpp #includes the .cpp directly (to reach
    // internals) — having it in libxdyn.a too would duplicate GZ::make_sim under
    // static linking. The gz exe gets it as an explicit source instead.
    addCpp(b, xdyn, "xdyn/gz_curves", &.{
        "GZTypes.cpp", "ResultantForceComputer.cpp", "gz_newton_raphson.cpp", "GZCurve.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "xdyn/fmi", &.{
        "FMI.cpp", "Sha.cpp", "FMIXml.cpp", "ParseFMIXml.cpp", "EmitFMIXml.cpp", "get_sha.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "xdyn/test_data_generator", &.{
        "big_hdb.cpp", "bug_3185.cpp", "bug_3187.cpp", "bug_3207.cpp", "bug_3235.cpp", "bug_3238.cpp",
        "bug_3241.cpp", "hdb_data_bug_3230.cpp", "hdb_data.cpp", "hdb_data_issue_184.cpp", "issue_20.cpp",
        "precal_test_data.cpp", "stl_data.cpp", "TriMeshTestData.cpp", "yaml_data.cpp", "yml_data_bug_3230.cpp",
    }, cpp_flags);
    addCpp(b, xdyn, "external/thirdparty/boost_program_options_descriptions", &.{
        "CustomOptionDescription.cpp", "OptionPrinter.cpp",
    }, cpp_flags);

    const libxdyn = b.addLibrary(.{ .name = "xdyn", .root_module = xdyn, .linkage = .static });
    libxdyn.step.dependOn(codegen.step);
    b.installArtifact(libxdyn);

    // =========================================================================
    // Executables
    // =========================================================================
    buildExe(b, target, optimize, libxdyn, "xdyn", cpp_flags, &.{
        "xdyn/executables/display_command_line_arguments.cpp",
        "xdyn/executables/parse_XdynCommandLineArguments.cpp",
        "xdyn/executables/build_observers_description.cpp",
        "xdyn/executables/XdynCommandLineArguments.cpp",
        "xdyn/executables/ErrorReporter.cpp",
        "xdyn/executables/xdyn.cpp",
    }, &.{});

    buildExe(b, target, optimize, libxdyn, "gz", cpp_flags, &.{
        "xdyn/executables/gz.cpp",
        "xdyn/gz_curves/make_sim_for_GZ.cpp",
        "xdyn/executables/display_command_line_arguments.cpp",
        "xdyn/executables/parse_XdynCommandLineArguments.cpp",
        "xdyn/executables/XdynCommandLineArguments.cpp",
        "xdyn/executables/ErrorReporter.cpp",
        "xdyn/executables/build_observers_description.cpp",
    }, &.{});

    // xdyn-for-cs / xdyn-for-me carry extra (per-exe) proto sources.
    buildExe(b, target, optimize, libxdyn, "xdyn-for-cs", cpp_flags, &.{
        "xdyn/executables/display_command_line_arguments.cpp",
        "xdyn/executables/parse_XdynForCSCommandLineArguments.cpp",
        "xdyn/executables/build_observers_description.cpp",
        "xdyn/executables/XdynForCSCommandLineArguments.cpp",
        "xdyn/executables/XdynCommandLineArguments.cpp",
        "xdyn/executables/xdyn_for_cs.cpp",
        "xdyn/executables/CosimulationServiceImpl.cpp",
        "xdyn/executables/ErrorReporter.cpp",
        "xdyn/executables/gRPCChecks.cpp",
    }, &.{"cosimulation"});

    buildExe(b, target, optimize, libxdyn, "xdyn-for-me", cpp_flags, &.{
        "xdyn/executables/display_command_line_arguments.cpp",
        "xdyn/executables/parse_XdynForMECommandLineArguments.cpp",
        "xdyn/executables/build_observers_description.cpp",
        "xdyn/executables/XdynForMECommandLineArguments.cpp",
        "xdyn/executables/xdyn_for_me.cpp",
        "xdyn/executables/ModelExchangeServiceImpl.cpp",
        "xdyn/executables/ErrorReporter.cpp",
        "xdyn/executables/gRPCChecks.cpp",
    }, &.{"model_exchange"});

    buildExe(b, target, optimize, libxdyn, "xdyn-grpc-airy", cpp_flags, &.{
        "xdyn/executables/xdyn_grpc_airy.cpp",
        "xdyn/executables/display_command_line_arguments.cpp",
        "xdyn/executables/parse_XdynCommandLineArguments.cpp",
        "xdyn/executables/XdynCommandLineArguments.cpp",
        "xdyn/executables/ErrorReporter.cpp",
        "xdyn/executables/gRPCChecks.cpp",
        "xdyn/grpc/AiryGRPC.cpp",
    }, &.{});

    buildExe(b, target, optimize, libxdyn, "test_orbital_velocities", cpp_flags,
        &.{"xdyn/executables/test_orbital_velocities_and_dynamic_pressures.cpp"}, &.{});
    buildExe(b, target, optimize, libxdyn, "test_hs", cpp_flags, &.{"xdyn/executables/test_hs.cpp"}, &.{});
    buildExe(b, target, optimize, libxdyn, "yml2test", cpp_flags, &.{"xdyn/executables/yml2test.cpp"}, &.{});
    buildExe(b, target, optimize, libxdyn, "convert_stl_files_to_code", cpp_flags,
        &.{"xdyn/executables/convert_stl_files_to_code.cpp"}, &.{});
    buildExe(b, target, optimize, libxdyn, "generate_yaml_example", cpp_flags, &.{
        "xdyn/executables/generate_yaml_examples.cpp", "xdyn/executables/file_writer.cpp",
    }, &.{});
    buildExe(b, target, optimize, libxdyn, "generate_stl_examples", cpp_flags, &.{
        "xdyn/executables/generate_stl_examples.cpp", "xdyn/executables/file_writer.cpp",
    }, &.{});
    buildExe(b, target, optimize, libxdyn, "generate_fmi_xml", cpp_flags, &.{"xdyn/fmi/generate_fmi_xml.cpp"}, &.{});

    // =========================================================================
    // Test runner (run_all_tests) — links gtest/gmock too
    // =========================================================================
    const test_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libcpp = true });
    addCommonIncludes(b, test_mod);
    // tests include headers from their parent module dir
    for ([_][]const u8{
        "xdyn/binary_stl_data", "xdyn/core", "xdyn/exceptions", "xdyn/environment_models",
        "xdyn/external_data_structures", "xdyn/external_file_formats", "xdyn/get_git_sha",
        "xdyn/test_data_generator", "xdyn/interface_hdf5", "xdyn/mesh", "xdyn/yaml_parser",
        "xdyn/hdb_interpolators", "xdyn/force_models", "xdyn/grpc", "xdyn/listeners_and_controllers",
        "xdyn/observers_and_api", "xdyn/gz_curves", "xdyn/fmi", "xdyn/executables",
    }) |inc| test_mod.addIncludePath(b.path(inc));
    addCpp(b, test_mod, "xdyn/executables", &.{"run_all_tests.cpp"}, cpp_flags);
    // tests touch SSC serializers transitively → cpp_flags already force-includes the shim
    test_mod.addCSourceFiles(.{ .root = b.path("xdyn"), .files = &test_sources, .flags = cpp_flags });
    test_mod.linkLibrary(libxdyn);
    test_mod.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libxdyndeps_test.a", .{deps_root}) });
    test_mod.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libxdyndeps_core.a", .{deps_root}) });
    linkWindowsSystemLibs(test_mod);

    const test_exe = b.addExecutable(.{ .name = "run_all_tests", .root_module = test_mod });
    test_exe.step.dependOn(codegen.step);
    if (!target_is_windows) test_exe.pie = false;
    b.installArtifact(test_exe);

    const run_tests = b.addRunArtifact(test_exe);
    run_tests.setCwd(b.path("."));
    if (b.args) |args| run_tests.addArgs(args);
    const test_step = b.step("test", "Run all C++ unit tests");
    test_step.dependOn(&run_tests.step);

    // =========================================================================
    // Python wrapper (pyxdyn) — the one shared object. Opt-in: `zig build python`
    // =========================================================================
    addPythonWrapper(b, target, optimize, libxdyn, cpp_flags);
}

// =============================================================================
// Build layout and codegen (migration-plan.md A2 / A1b)
// =============================================================================

// Everything the build installs goes under one gitignored build/<arch>-<os>-<abi>, so
// `.gitignore` is two lines and `mise run clean` is one. (Generated *sources* do not: they
// are cache entries, and live under .zig-cache with everything else zig can rebuild.)
// Uses the full triple, not <arch>-<os>: x86_64-linux-gnu and
// x86_64-linux-musl are different binaries and must not share a directory.
// Skipped when the user asked for something specific via --prefix or DESTDIR.
fn installUnderBuildDir(b: *std.Build, target: std.Build.ResolvedTarget) void {
    if (b.dest_dir != null) return;
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch return;
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) return;

    const t = target.result;
    // -debug gets its own tree: an -O0 binary and an -O3 one are not interchangeable, and
    // silently overwriting one with the other is how you spend an afternoon wondering why
    // gdb says <optimized out>.
    const triple = b.fmt("{s}-{s}-{s}{s}", .{
        @tagName(t.cpu.arch), @tagName(t.os.tag), @tagName(t.abi),
        if (debug_build) "-debug" else "",
    });
    b.resolveInstallPrefix(b.pathFromRoot(b.pathJoin(&.{ "build", triple })), .{});
}

// Appends -O0 -g to a flag set when -Ddebug is on. Relies on clang taking the *last* -O:
// zig emits -O3 from .ReleaseFast, ours comes after, xdyn wins, the deps are untouched.
// -fno-omit-frame-pointer so backtraces stay walkable through the optimized deps.
fn withDebug(b: *std.Build, base: []const []const u8) []const []const u8 {
    if (!debug_build) return base;
    return withFlags(b, base, &.{ "-O0", "-g", "-fno-omit-frame-pointer" });
}

// One flag set plus a few extras, for the handful of files that need a scoped -Wno-.
fn withFlags(b: *std.Build, base: []const []const u8, extra: []const []const u8) []const []const u8 {
    const out = b.allocator.alloc([]const u8, base.len + extra.len) catch @panic("OOM");
    @memcpy(out[0..base.len], base);
    @memcpy(out[base.len..], extra);
    return out;
}

// The three generators, and how much of each one zig is able to know about. This used to be
// gen.sh, a shell script every compile step depended on wholesale: it re-ran on every build,
// and editing a .proto compiled silently against stale gencode because nothing downstream
// could tell the file had changed.
const Codegen = struct {
    // Ordering edge only. Depended on by every Compile, because one of the three writes into
    // the source tree and so has no output path to hang a dependency off.
    step: *std.Build.Step,
    // protoc's two plugin outputs, and the git stamp: real cached artifacts, consumed by
    // LazyPath so their *contents* reach the compile cache.
    proto_messages: std.Build.LazyPath,
    proto_services: std.Build.LazyPath,
    git_sha_c: std.Build.LazyPath,
};

fn addCodegen(b: *std.Build) Codegen {
    const step = b.step("gen", "Run the code generators on their own");

    // 1. SSC's umbrella headers, from SSC's own script. has_side_effects because it writes
    //    *into the source tree*: SSC is never modified, so its generator stays authoritative
    //    and zig cannot model the result as a cached output. This is the one that can never
    //    become a declared input/output pair, and forking its logic is not on the table.
    //    Cheap enough not to matter: idempotent, <1 s, and zig's C cache is content-hashed,
    //    so regenerating byte-identical headers rebuilds nothing.
    const ssc_headers = b.addSystemCommand(&.{ "sh", "generate_module_header.sh" });
    ssc_headers.setCwd(b.path("external/ssc/ssc"));
    ssc_headers.has_side_effects = true;
    step.dependOn(&ssc_headers.step);

    // 2. protobuf + gRPC. protoc stays an external binary — folding it in would mean
    //    reimplementing it — but every input it reads is now declared: the six .proto files
    //    by content, and both binaries with them, because the gencode and the
    //    libprotobuf/libgrpc it is compiled against come out of the same closure and a
    //    closure swap has to invalidate it.
    //
    //    The *host* closure, never the target's: protoc and grpc_cpp_plugin run on this
    //    machine whatever -Dtarget says, and the C++ they emit is target-independent.
    const host = b.option([]const u8, "deps-host", "Host closure providing protoc (default: ./libcxx-x86_64-linux-gnu)") orelse
        b.graph.environ_map.get("XDYN_DEPS_HOST") orelse
        b.pathJoin(&.{ b.build_root.path orelse ".", "libcxx-x86_64-linux-gnu" });
    const bin = b.pathJoin(&.{ host, "install", "bin" });
    const protoc = b.pathJoin(&.{ bin, "protoc" });
    // Warned, not failed, for the same reason resolveDepsRoot warns: `zig build --help` is
    // where you find out the option naming the fix exists.
    std.Io.Dir.cwd().access(b.graph.io, protoc, .{}) catch {
        std.log.warn("no protoc under '{s}': codegen will fail. Point at the native closure " ++
            "with -Ddeps-host=<path> or $XDYN_DEPS_HOST.", .{bin});
    };

    const gen_proto = b.addSystemCommand(&.{protoc});
    gen_proto.setCwd(b.path("."));
    gen_proto.addFileInput(.{ .cwd_relative = protoc });
    gen_proto.addPrefixedFileArg("--plugin=protoc-gen-grpc=", .{ .cwd_relative = b.pathJoin(&.{ bin, "grpc_cpp_plugin" }) });
    // Two output directories, where gen.sh wrote both into one. A Run step's outputs are
    // distinct by construction and protoc is happy to write its two plugin outputs to two
    // roots; both go on the include path in addCommonIncludes, which is what resolves the
    // cross-includes — force.grpc.pb.cc includes "force.pb.h", which is in the other one.
    const messages = gen_proto.addPrefixedOutputDirectoryArg("--cpp_out=", "proto");
    const services = gen_proto.addPrefixedOutputDirectoryArg("--grpc_out=", "proto-grpc");
    gen_proto.addPrefixedDirectoryArg("-I", b.path("interfaces/proto"));
    for (proto_files) |name|
        gen_proto.addFileArg(b.path(b.fmt("interfaces/proto/{s}.proto", .{name})));
    step.dependOn(&gen_proto.step);

    // 3. The git stamp, which stops being codegen: one interpolation into one C file, written
    //    through WriteFile so the content is its own cache key. A new HEAD recompiles this one
    //    TU and relinks; an unchanged one rebuilds nothing.
    const sha = b.option([]const u8, "git-sha", "Commit stamped into the binaries (default: git rev-parse HEAD)") orelse
        headSha(b);
    const write_sha = b.addWriteFiles();
    const git_sha_c = write_sha.add("get_git_sha.c", b.fmt(
        \\#include "xdyn/get_git_sha/get_git_sha.h"
        \\const char* get_git_sha()
        \\{{
        \\    return "{s}";
        \\}}
        \\
    , .{sha}));
    step.dependOn(&write_sha.step);

    return .{
        .step = step,
        .proto_messages = messages,
        .proto_services = services,
        .git_sha_c = git_sha_c,
    };
}

// "unknown" rather than a hard failure: a source export without .git has to keep building,
// and -Dgit-sha is there for whoever packages it and does know the answer.
fn headSha(b: *std.Build) []const u8 {
    var code: u8 = 0;
    const out = b.runAllowFail(
        &.{ "git", "-C", b.build_root.path orelse ".", "rev-parse", "HEAD" },
        &code,
        .ignore,
    ) catch return "unknown";
    if (code != 0) return "unknown";
    return b.dupe(std.mem.trim(u8, out, " \t\r\n"));
}

// The generated translation units for a set of .proto names. Named by proto rather than by
// file so the message half and the service half cannot drift apart.
fn addProtoSources(b: *std.Build, m: *std.Build.Module, names: []const []const u8) void {
    for (names) |name| {
        m.addCSourceFile(.{
            .file = codegen.proto_messages.path(b, b.fmt("{s}.pb.cc", .{name})),
            .flags = proto_flags,
        });
        m.addCSourceFile(.{
            .file = codegen.proto_services.path(b, b.fmt("{s}.grpc.pb.cc", .{name})),
            .flags = proto_flags,
        });
    }
}

// =============================================================================
// Path resolution — nothing absolute is baked into this file (migration-plan.md A1)
// =============================================================================

// The bucket-3 libc++ closure (merged archives + install/include) for the target being built,
// named by its **full triple**. Two-thirds of one does not identify a closure: x86_64-linux-gnu
// and x86_64-linux-musl differ in the libc, which is precisely what a closure carries — and the
// old arch-only rule handed a musl build the glibc closure and a glibc aarch64 build the musl one.
// Deriving the directory from the whole triple makes that unrepresentable rather than merely
// discouraged. Resolution order:
//   1. -Ddeps=<path>            explicit; applies to whatever -Dtarget was asked for
//   2. $XDYN_DEPS_<TRIPLE>      per-target, e.g. XDYN_DEPS_X86_64_LINUX_MUSL. This is the one an
//                               environment should export, and the only one that stays correct
//                               when a cross build runs in the same shell.
//   3. $XDYN_DEPS               blunt: one path for every target. Kept as a deliberate override,
//                               never as something a devShell exports.
//   4. <build root>/libcxx-<triple>   where tools/deps/ builds them, gitignored
// addCodegen resolves the *host* closure separately, via -Ddeps-host: codegen runs host protoc.
fn resolveDepsRoot(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
    const t = target.result;
    // The abi stringifies without its glibc version — `gnu`, not `gnu.2.28` — which is what we
    // want: exactly one gnu closure exists and tools/deps/common.sh owns its floor.
    const triple = b.fmt("{s}-{s}-{s}", .{ @tagName(t.cpu.arch), @tagName(t.os.tag), @tagName(t.abi) });

    const env_key = b.fmt("XDYN_DEPS_{s}", .{triple});
    for (env_key) |*c| c.* = switch (c.*) {
        '-' => '_',
        'a'...'z' => c.* - ('a' - 'A'),
        else => c.*,
    };

    const root = b.option([]const u8, "deps", "libc++ dependency closure for the target (default: ./libcxx-<triple>)") orelse
        b.graph.environ_map.get(env_key) orelse
        b.graph.environ_map.get("XDYN_DEPS") orelse
        b.pathJoin(&.{ b.build_root.path orelse ".", b.fmt("libcxx-{s}", .{triple}) });

    // Deliberately a warning, not an error: `zig build --help` has to keep working on a
    // machine that has no closure yet — that is exactly where -Ddeps gets discovered. It can
    // afford to be a warning precisely because the triple-named default cannot silently
    // resolve to a closure built for a different libc.
    std.Io.Dir.cwd().access(b.graph.io, b.pathJoin(&.{ root, "libxdyndeps_core.a" }), .{}) catch {
        std.log.warn("no libxdyndeps_core.a under '{s}': the {s} closure is missing. Fetch it " ++
            "with `mise run deps:fetch {s}`, build it with `mise run deps:{s}`, or name one " ++
            "with -Ddeps=<path> or ${s}.", .{ root, triple, triple, triple, env_key });
    };
    return root;
}

// Eigen is header-only and target-independent, so the host copy serves cross builds too.
//   1. -Deigen=<path>   2. $XDYN_EIGEN   3. <deps>/install/include/eigen3
//   4. pkg-config eigen3 (covers Nix/Homebrew store paths)   5. the usual system prefixes
fn resolveEigen(b: *std.Build) ?[]const u8 {
    if (b.option([]const u8, "eigen", "Eigen 3 include directory (default: probe the host)") orelse
        b.graph.environ_map.get("XDYN_EIGEN")) |explicit| return explicit;

    const in_closure = b.pathJoin(&.{ deps_root, "install", "include", "eigen3" });
    if (hasEigen(b, in_closure)) return in_closure;

    if (probeEigenPkgConfig(b)) |probed| return probed;

    for ([_][]const u8{ "/usr/include/eigen3", "/usr/local/include/eigen3", "/opt/homebrew/include/eigen3" }) |candidate|
        if (hasEigen(b, candidate)) return candidate;

    std.log.warn("Eigen 3 not found (tried the closure, pkg-config and the usual prefixes). " ++
        "Point at it with -Deigen=<dir> or $XDYN_EIGEN — the dir that contains Eigen/Core.", .{});
    return null;
}

fn probeEigenPkgConfig(b: *std.Build) ?[]const u8 {
    var code: u8 = 0;
    const out = b.runAllowFail(&.{ "pkg-config", "--cflags-only-I", "eigen3" }, &code, .ignore) catch return null;
    if (code != 0) return null;
    var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
    while (it.next()) |token| {
        if (!std.mem.startsWith(u8, token, "-I")) continue;
        if (hasEigen(b, token[2..])) return b.dupe(token[2..]);
    }
    return null;
}

fn hasEigen(b: *std.Build, dir: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const probe = std.fmt.bufPrint(&buf, "{s}/Eigen/Core", .{dir}) catch return false;
    std.Io.Dir.cwd().access(b.graph.io, probe, .{}) catch return false;
    return true;
}

// =============================================================================
// Helpers
// =============================================================================

fn addCpp(b: *std.Build, m: *std.Build.Module, root: []const u8, files: []const []const u8, flags: []const []const u8) void {
    m.addCSourceFiles(.{ .root = b.path(root), .files = files, .flags = flags });
}

// Transitive Windows link set: ws2_32/iphlpapi (sockets, c-ares), mswsock (boost.asio's
// IOCP AcceptEx), crypt32/bcrypt (boringssl cert store + RNG), dbghelp (absl symbolize).
// zig bundles the MinGW import libs, so no Windows SDK is involved.
fn linkWindowsSystemLibs(m: *std.Build.Module) void {
    if (!target_is_windows) return;
    for ([_][]const u8{ "ws2_32", "mswsock", "crypt32", "bcrypt", "iphlpapi", "dbghelp", "advapi32" }) |lib|
        m.linkSystemLibrary(lib, .{});
}

fn addCommonIncludes(b: *std.Build, m: *std.Build.Module) void {
    // No _WIN32_WINNT pin needed: zig's windows-gnu target already defines a modern one
    // (re-defining it here is a hard error in zig cc).
    // yaml-cpp's dll.h declares everything __declspec(dllimport) on _WIN32 unless told
    // the lib is static (we consume the headers raw, not via the CMake target that
    // would propagate this define).
    if (target_is_windows) m.addCMacro("YAML_CPP_STATIC_DEFINE", "1");
    // deps/include FIRST as a real -I so our libc++ protobuf/grpc/boost/hdf5/yaml
    // headers win over any system copy (Arch ships protobuf v35; our gencode is
    // v31.1 — a version mismatch otherwise errors at compile).
    m.addIncludePath(.{ .cwd_relative = b.fmt("{s}/install/include", .{deps_root}) });
    m.addIncludePath(b.path("."));
    m.addIncludePath(b.path("external/ssc"));
    m.addIncludePath(b.path("external"));
    m.addIncludePath(codegen.proto_messages);
    m.addIncludePath(codegen.proto_services);
    m.addSystemIncludePath(b.path("external/eigen3-hdf5"));
    // The parent, not base91x/ itself: every include spells it "base91x/base91.hpp".
    m.addSystemIncludePath(b.path("external/thirdparty"));
    if (eigen_include) |eigen| m.addSystemIncludePath(.{ .cwd_relative = eigen });
}

fn buildExe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    libxdyn: *std.Build.Step.Compile,
    name: []const u8,
    flags: []const []const u8,
    sources: []const []const u8,
    protos: []const []const u8,
) void {
    const m = b.createModule(.{ .target = target, .optimize = optimize, .link_libcpp = true });
    addCommonIncludes(b, m);
    m.addCSourceFiles(.{ .root = b.path("."), .files = sources, .flags = flags });
    addProtoSources(b, m, protos);
    m.linkLibrary(libxdyn);
    m.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libxdyndeps_core.a", .{deps_root}) });
    linkWindowsSystemLibs(m);
    const exe = b.addExecutable(.{ .name = name, .root_module = m });
    exe.step.dependOn(codegen.step); // for the in-tree half of the codegen
    if (!target_is_windows) exe.pie = false; // prebuilt deps may be non-PIC (PIE is N/A on COFF)
    b.installArtifact(exe);
}

// =============================================================================
// Python wrapper — the one mandatory shared object
// =============================================================================

// What CPython needs to be told about, all of it discovered from one interpreter so the
// three can never disagree: headers, pybind11's headers, and the ABI tag that has to end
// up in the filename (`import xdyn` only finds `xdyn.cpython-310-x86_64-linux-gnu.so`).
const PythonEnv = struct {
    exe: []const u8,
    include: []const u8,
    pybind11: []const u8,
    ext_suffix: []const u8,
};

// A *shared* library, unlike everything else here, because `import xdyn` is a dlopen and
// there is no such thing as a statically linked extension module. That was Hazard L, and
// the closure turned out to already satisfy it: zig cc defaults to -fPIC, so all 3294
// members relocate position-independently and no rebuild was needed.
//
// Opt-in via `zig build python`, not part of `zig build`: it needs an interpreter with
// pybind11 in it, and a plain `zig build` must keep working on a machine that has neither.
fn addPythonWrapper(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    libxdyn: *std.Build.Step.Compile,
    cpp_flags: []const []const u8,
) void {
    const step = b.step("python", "Build the pybind11 extension module (needs -Dpython or a venv)");
    const env = resolvePython(b) orelse {
        step.dependOn(&b.addFail(
            "no usable interpreter: need one with pybind11 importable. " ++
                "Point at it with -Dpython=<python> or $XDYN_PYTHON, or run `mise run python:setup`.",
        ).step);
        return;
    };

    // -fvisibility=hidden is what pybind11_add_module does, and it is not cosmetic: pybind11
    // keys its internal type registry on visibility, and exporting every xdyn symbol out of
    // a 100 MB module also makes the dynamic loader do a lot of pointless work.
    var flags = concatFlags(b, cpp_flags, &.{"-fvisibility=hidden"});

    // Becomes the module's __version__ (main.cpp falls back to "dev" when undefined). The
    // quotes belong inside the argument: there is no shell here, so the macro's value is
    // the C string literal clang sees. Same -D CMake passed.
    if (b.option([]const u8, "git-version", "Version stamped into the module's __version__ (default: dev)")) |v|
        flags = concatFlags(b, flags, &.{b.fmt("-DGIT_VERSION=\"{s}\"", .{v})});

    const m = b.createModule(.{ .target = target, .optimize = optimize, .link_libcpp = true, .pic = true });
    addCommonIncludes(b, m);
    // System include paths: pybind11 and CPython are third-party headers whose warnings are
    // not ours to fix, and cpp_flags is -Wall -Wextra.
    m.addSystemIncludePath(.{ .cwd_relative = env.include });
    m.addSystemIncludePath(.{ .cwd_relative = env.pybind11 });
    m.addCSourceFiles(.{ .root = b.path("xdyn_wrapper_python/src"), .files = &.{
        "main.cpp",       "py_ssc.cpp",     "py_xdyn_core.cpp", "py_xdyn_exe.cpp",
        "py_xdyn_data.cpp", "py_xdyn_env.cpp", "py_xdyn_force.cpp", "py_xdyn_hdb.cpp",
    }, .flags = flags });
    // These three are per-executable sources, not libxdyn members (they carry main()-adjacent
    // command-line plumbing), so the module needs its own copies — same list CMake used.
    m.addCSourceFiles(.{ .root = b.path("."), .files = &.{
        "xdyn/executables/XdynCommandLineArguments.cpp",
        "xdyn/executables/ErrorReporter.cpp",
        "xdyn/executables/build_observers_description.cpp",
    }, .flags = flags });
    m.linkLibrary(libxdyn);
    m.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libxdyndeps_core.a", .{deps_root}) });
    linkWindowsSystemLibs(m);

    // Deliberately not libxdyn's name: both end up in the same install tree, and libxdyn.a
    // next to libxdyn.so is how you get a link that silently picks the wrong one.
    const lib = b.addLibrary(.{ .name = "pyxdyn", .root_module = m, .linkage = .dynamic });
    lib.step.dependOn(codegen.step);
    // libpython is deliberately NOT linked — the standard Linux contract is that Py* stays
    // undefined and resolves against the already-loaded interpreter. The cost is that a
    // *missing xdyn* symbol also links quietly and only shows up at import, which is why
    // `mise run python:build` finishes by importing the module it just built.
    lib.linker_allow_shlib_undefined = true;

    // CPython does not care where the file is, only what it is called, so install under a
    // plain python/ and let the packaging step decide where setuptools wants it — that path
    // is a setuptools implementation detail and it has already changed once
    // (lib.linux-x86_64-3.10 -> lib.linux-x86_64-cpython-310).
    const install = b.addInstallFileWithDir(
        lib.getEmittedBin(),
        .prefix,
        b.fmt("python/xdyn{s}", .{env.ext_suffix}),
    );
    step.dependOn(&install.step);
}

// Resolution order mirrors resolveDepsRoot/resolveEigen: explicit option, environment, then
// the layout this repo develops in. The interpreter is asked for all four values at once —
// deriving the ABI tag separately from the headers is how you get a module that links and
// then cannot be imported.
fn resolvePython(b: *std.Build) ?PythonEnv {
    const explicit = b.option([]const u8, "python", "Interpreter to build the extension module for (needs pybind11)") orelse
        b.graph.environ_map.get("XDYN_PYTHON");

    // No bare `python3` fallback. uv owns every interpreter this repo uses (pyproject.toml,
    // migration-plan A8), so a PATH interpreter is by definition one nobody pinned — and the
    // failure it produces is silent, not loud: the module builds against whatever ABI that
    // interpreter reports and simply never imports. Failing here instead prints the message
    // in addPythonWrapper, which names the two ways to say which interpreter you meant.
    const candidates: []const []const u8 = if (explicit) |e| &.{e} else &.{
        b.pathJoin(&.{ b.build_root.path orelse ".", "build", "venv-wrapper", "bin", "python" }),
    };

    const probe =
        \\import sysconfig, pybind11
        \\print(sysconfig.get_paths()["include"])
        \\print(pybind11.get_include())
        \\print(sysconfig.get_config_var("EXT_SUFFIX"))
    ;

    for (candidates) |exe| {
        var code: u8 = 0;
        const out = b.runAllowFail(&.{ exe, "-c", probe }, &code, .ignore) catch continue;
        if (code != 0) continue;
        var it = std.mem.tokenizeScalar(u8, out, '\n');
        const include = it.next() orelse continue;
        const pybind11 = it.next() orelse continue;
        const ext_suffix = it.next() orelse continue;
        return .{
            .exe = b.dupe(exe),
            .include = b.dupe(include),
            .pybind11 = b.dupe(pybind11),
            .ext_suffix = b.dupe(std.mem.trim(u8, ext_suffix, " \r")),
        };
    }
    return null;
}

fn concatFlags(b: *std.Build, base: []const []const u8, extra: []const []const u8) []const []const u8 {
    const out = b.allocator.alloc([]const u8, base.len + extra.len) catch @panic("OOM");
    @memcpy(out[0..base.len], base);
    @memcpy(out[base.len..], extra);
    return out;
}

// =============================================================================
// Source file lists
// =============================================================================

// All six, in one protoc invocation. wave_types has no service of its own, but
// grpc_cpp_plugin emits a (near-empty) .grpc.pb.cc for it anyway and the build has always
// compiled that, so the two halves stay symmetric.
const proto_files = [_][]const u8{
    "wave_types", "wave_grpc", "force", "controller", "cosimulation", "model_exchange",
};

const f2c_sources = [_][]const u8{
    "f77vers.c",  "i77vers.c",   "s_rnge.c",    "abort_.c",    "exit_.c",
    "getenv_.c",  "signal_.c",   "s_stop.c",    "system_.c",   "cabs.c",
    "ctype.c",    "derf_.c",     "derfc_.c",     "erf_.c",      "erfc_.c",
    "sig_die.c",  "pow_ci.c",    "pow_dd.c",     "pow_di.c",    "pow_hh.c",
    "pow_ii.c",   "pow_ri.c",    "pow_zi.c",     "pow_zz.c",    "c_abs.c",
    "c_cos.c",    "c_div.c",     "c_exp.c",      "c_log.c",     "c_sin.c",
    "c_sqrt.c",   "z_abs.c",     "z_cos.c",      "z_div.c",     "z_exp.c",
    "z_log.c",    "z_sin.c",     "z_sqrt.c",     "r_abs.c",     "r_acos.c",
    "r_asin.c",   "r_atan.c",    "r_atn2.c",     "r_cnjg.c",    "r_cos.c",
    "r_cosh.c",   "r_dim.c",     "r_exp.c",      "r_imag.c",    "r_int.c",
    "r_lg10.c",   "r_log.c",     "r_mod.c",      "r_nint.c",    "r_sign.c",
    "r_sin.c",    "r_sinh.c",    "r_sqrt.c",     "r_tan.c",     "r_tanh.c",
    "d_abs.c",    "d_acos.c",    "d_asin.c",     "d_atan.c",    "d_atn2.c",
    "d_cnjg.c",   "d_cos.c",     "d_cosh.c",     "d_dim.c",     "d_exp.c",
    "d_imag.c",   "d_int.c",     "d_lg10.c",     "d_log.c",     "d_mod.c",
    "d_nint.c",   "d_prod.c",    "d_sign.c",     "d_sin.c",     "d_sinh.c",
    "d_sqrt.c",   "d_tan.c",     "d_tanh.c",     "i_abs.c",     "i_dim.c",
    "i_dnnt.c",   "i_indx.c",    "i_len.c",      "i_mod.c",     "i_nint.c",
    "i_sign.c",   "lbitbits.c",  "lbitshft.c",   "h_abs.c",     "h_dim.c",
    "h_dnnt.c",   "h_indx.c",    "h_len.c",      "h_mod.c",     "h_nint.c",
    "h_sign.c",   "l_ge.c",      "l_gt.c",       "l_le.c",      "l_lt.c",
    "hl_ge.c",    "hl_gt.c",     "hl_le.c",      "hl_lt.c",     "ef1asc_.c",
    "ef1cmc_.c",  "f77_aloc.c",  "s_cat.c",      "s_cmp.c",     "s_copy.c",
    "backspac.c", "close.c",     "dfe.c",        "dolio.c",     "due.c",
    "endfile.c",  "err.c",       "fmt.c",        "fmtlib.c",    "ftell_.c",
    "iio.c",      "ilnw.c",      "inquire.c",    "lread.c",     "lwrite.c",
    "open.c",     "rdfmt.c",     "rewind.c",     "rsfe.c",      "rsli.c",
    "rsne.c",     "sfe.c",       "sue.c",        "typesize.c",  "uio.c",
    "util.c",     "wref.c",      "wrtfmt.c",     "wsfe.c",      "wsle.c",
    "wsne.c",     "xwsne.c",
};

const test_sources = [_][]const u8{
    "mesh/unit_tests/MeshBuilderTest.cpp",
    "mesh/unit_tests/MeshIntersectorTest.cpp",
    "mesh/unit_tests/mesh_manipulationsTest.cpp",
    "mesh/unit_tests/RandomEPointGenerator.cpp",
    "mesh/unit_tests/ClosingFacetComputerTest.cpp",
    "mesh/unit_tests/TestMeshes.cpp",
    "yaml_parser/unit_tests/environment_parsersTest.cpp",
    "yaml_parser/unit_tests/parse_addressTest.cpp",
    "yaml_parser/unit_tests/parse_controllersTest.cpp",
    "yaml_parser/unit_tests/parse_outputTest.cpp",
    "yaml_parser/unit_tests/parse_time_seriesTest.cpp",
    "yaml_parser/unit_tests/SimulatorYamlParserTest.cpp",
    "external_file_formats/unit_tests/low_level_hdb_parserTest.cpp",
    "external_file_formats/unit_tests/stl_io_hdf5Test.cpp",
    "external_file_formats/unit_tests/stl_readerTest.cpp",
    "external_file_formats/unit_tests/stl_writerTest.cpp",
    "core/unit_tests/BlockedDOFTest.cpp",
    "core/unit_tests/BodyBuilderTest.cpp",
    "core/unit_tests/BodyTest.cpp",
    "core/unit_tests/EnvironmentAndFramesTest.cpp",
    "core/unit_tests/ForceModelTest.cpp",
    "core/unit_tests/SimulatorBuilderTest.cpp",
    "core/unit_tests/StatesFilterTest.cpp",
    "core/unit_tests/SurfaceElevationFromWavesTest.cpp",
    "core/unit_tests/WrenchTest.cpp",
    "core/unit_tests/generate_body_for_tests.cpp",
    "core/unit_tests/random_kinematics.cpp",
    "core/unit_tests/update_kinematicsTests.cpp",
    "environment_models/unit_tests/AiryTest.cpp",
    "environment_models/unit_tests/BretschneiderSpectrumTest.cpp",
    "environment_models/unit_tests/Cos2sDirectionalSpreadingTest.cpp",
    "environment_models/unit_tests/DefaultWindModelTest.cpp",
    "environment_models/unit_tests/DiracDirectionalSpreadingTest.cpp",
    "environment_models/unit_tests/DiracSpectralDensityTest.cpp",
    "environment_models/unit_tests/discretizeTest.cpp",
    "environment_models/unit_tests/JonswapSpectrumTest.cpp",
    "environment_models/unit_tests/PiersonMoskowitzSpectrumTest.cpp",
    "environment_models/unit_tests/StretchingTest.cpp",
    "environment_models/unit_tests/WaveNumberFunctorTest.cpp",
    "environment_models/unit_tests/WaveSpectralDensityTest.cpp",
    "environment_models/unit_tests/WindMeanVelocityProfileTest.cpp",
    "force_models/unit_tests/AeroPolarForceModelTest.cpp",
    "force_models/unit_tests/ConstantForceModelTest.cpp",
    "force_models/unit_tests/DefaultSurfaceElevationTest.cpp",
    "force_models/unit_tests/DiffractionForceModelTest.cpp",
    "force_models/unit_tests/env_for_tests.cpp",
    "force_models/unit_tests/FlettnerRotorForceModelTest.cpp",
    "force_models/unit_tests/FroudeKrylovForceModelTest.cpp",
    "force_models/unit_tests/GravityForceModelTest.cpp",
    "force_models/unit_tests/HDBParserForTests.cpp",
    "force_models/unit_tests/HoltropMennenForceModelTest.cpp",
    "force_models/unit_tests/HydroPolarForceModelTest.cpp",
    "force_models/unit_tests/HydrostaticForceModelTest.cpp",
    "force_models/unit_tests/KtKqForceModelTest.cpp",
    "force_models/unit_tests/LinearDampingForceModelTest.cpp",
    "force_models/unit_tests/LinearFroudeKrylovForceModelTest.cpp",
    "force_models/unit_tests/LinearHydrostaticForceModelTest.cpp",
    "force_models/unit_tests/LinearStiffnessForceModelTest.cpp",
    "force_models/unit_tests/maneuvering_compilerTest.cpp",
    "force_models/unit_tests/maneuvering_DataSource_builderTest.cpp",
    "force_models/unit_tests/ManeuveringForceModelTest.cpp",
    "force_models/unit_tests/maneuvering_parserTest.cpp",
    "force_models/unit_tests/MMGManeuveringForceModelTest.cpp",
    "force_models/unit_tests/NumericalEvaluator.cpp",
    "force_models/unit_tests/QuadraticDampingForceModelTest.cpp",
    "force_models/unit_tests/RadiationDampingForceModelTest.cpp",
    "force_models/unit_tests/ResistanceCurveForceModelTest.cpp",
    "force_models/unit_tests/RudderForceModelTest.cpp",
    "force_models/unit_tests/SimpleHeadingKeepingControllerTest.cpp",
    "force_models/unit_tests/SimpleStationKeepingControllerTest.cpp",
    "force_models/unit_tests/StringEvaluator.cpp",
    "force_models/unit_tests/WageningenControlledForceModelTest.cpp",
    "listeners_and_controllers/unit_tests/GrpcControllerTest.cpp",
    "listeners_and_controllers/unit_tests/CSVLineByLineReaderTest.cpp",
    "hdb_interpolators/unit_tests/HDBParserTest.cpp",
    "hdb_interpolators/unit_tests/HistoryTest.cpp",
    "hdb_interpolators/unit_tests/RadiationDampingBuilderTest.cpp",
    "hdb_interpolators/unit_tests/DiffractionInterpolatorTest.cpp",
    "hdb_interpolators/unit_tests/hdb_test.cpp",
    "hdb_interpolators/unit_tests/PrecalParserTest.cpp",
    "interface_hdf5/unit_tests/h5_interface_tests.cpp",
    "observers_and_api/unit_tests/ConfBuilderTest.cpp",
    "observers_and_api/unit_tests/CSVControllerTest.cpp",
    "observers_and_api/unit_tests/EnvironmentTest.cpp",
    "observers_and_api/unit_tests/EverythingObserverTest.cpp",
    "observers_and_api/unit_tests/ForceTester.cpp",
    "observers_and_api/unit_tests/ForceTests.cpp",
    "observers_and_api/unit_tests/Hdf5ObserverTest.cpp",
    "observers_and_api/unit_tests/Hdf5WaveObserverBuilderTest.cpp",
    "observers_and_api/unit_tests/Hdf5WaveObserverTest.cpp",
    "observers_and_api/unit_tests/JsonObserverTest.cpp",
    "observers_and_api/unit_tests/JSONSerializerTest.cpp",
    "observers_and_api/unit_tests/listenersTest.cpp",
    "observers_and_api/unit_tests/ListOfObserversTest.cpp",
    "observers_and_api/unit_tests/MapObserverTest.cpp",
    "observers_and_api/unit_tests/ObserverTests.cpp",
    "observers_and_api/unit_tests/PIDControllerTest.cpp",
    "observers_and_api/unit_tests/SimTest.cpp",
    "observers_and_api/unit_tests/SimulationServerObserverTest.cpp",
    "observers_and_api/unit_tests/XdynForCSTest.cpp",
    "observers_and_api/unit_tests/XdynForMETest.cpp",
    "gz_curves/unit_tests/ResultantForceComputerTest.cpp",
    "gz_curves/unit_tests/gz_newton_raphsonTest.cpp",
    "gz_curves/unit_tests/GZCurveTest.cpp",
    "fmi/unit_tests/calculate_hashTest.cpp",
    "fmi/unit_tests/EmitFMIXmlTest.cpp",
    "fmi/unit_tests/FMITest.cpp",
    "fmi/unit_tests/ParseFMIXmlTest.cpp",
    "fmi/unit_tests/random_FMI_XML.cpp",
    "grpc/unit_tests/GRPCForceModelTest.cpp",
    "grpc/unit_tests/GrpcControllerInterfaceTest.cpp",
    // NB: test_data_generator/*.cpp is already compiled into libxdyn.a (pulled
    // on-demand by the tests) — listing it here too would duplicate symbols.
};

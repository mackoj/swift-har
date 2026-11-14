// swift-tools-version: 6.1
import PackageDescription

// swift-har's benchmarks, on ordo-one/benchmark (https://www.swift.org/blog/benchmarks/). A separate
// package so the benchmark dependency stays out of HARKit's dependency budget. Run from the repository root:
// `swift package --package-path Benchmarks benchmark`.
let package = Package(
    name: "Benchmarks",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "swift-har", path: ".."),
        .package(url: "https://github.com/ordo-one/benchmark.git", from: "1.38.0"),
    ],
    targets: [
        .executableTarget(
            name: "HARBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark"),
                .product(name: "HARKit", package: "swift-har"),
            ],
            path: "Benchmarks/HARBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        ),
        // Reads two `benchmark --format markdown` outputs and prints each benchmark's p50 before and after.
        .executableTarget(name: "p50", path: "Tools/P50"),
        // Reads an exported Time Profiler table and prints the hottest functions (scripts/profile.sh).
        .executableTarget(name: "hotspots", path: "Tools/Hotspots"),
    ]
)

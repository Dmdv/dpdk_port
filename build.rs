fn main() {
    println!("cargo:rustc-link-search=native=/usr/lib/aarch64-linux-gnu");
    
    // Core DPDK libraries
    println!("cargo:rustc-link-lib=dylib=rte_eal");
    println!("cargo:rustc-link-lib=dylib=rte_mempool");
    println!("cargo:rustc-link-lib=dylib=rte_ring");
    println!("cargo:rustc-link-lib=dylib=rte_mbuf");
    println!("cargo:rustc-link-lib=dylib=rte_net");
    println!("cargo:rustc-link-lib=dylib=rte_ethdev");
    println!("cargo:rustc-link-lib=dylib=rte_pci");
    println!("cargo:rustc-link-lib=dylib=rte_bus_pci");
    
    // Essential DPDK libraries for basic functionality
    println!("cargo:rustc-link-lib=dylib=rte_kvargs");
    println!("cargo:rustc-link-lib=dylib=rte_hash");
    println!("cargo:rustc-link-lib=dylib=rte_timer");
    println!("cargo:rustc-link-lib=dylib=rte_cmdline");
    
    // System libraries
    println!("cargo:rustc-link-lib=dylib=numa");
    println!("cargo:rustc-link-lib=dylib=bsd");
    println!("cargo:rustc-link-lib=dylib=pcap");
    println!("cargo:rustc-link-lib=dylib=dl");
    println!("cargo:rustc-link-lib=dylib=pthread");
    println!("cargo:rustc-link-lib=dylib=m");
    
    // Add pkg-config support
    if let Ok(lib) = pkg_config::probe_library("libdpdk") {
        for path in lib.include_paths {
            println!("cargo:include={}", path.display());
        }
    }
} 
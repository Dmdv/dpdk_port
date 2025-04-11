fn main() {
    println!("cargo:rustc-link-search=native=/usr/lib/x86_64-linux-gnu");
    println!("cargo:rustc-link-lib=dylib=dpdk");
    println!("cargo:rustc-link-lib=dylib=numa");
    println!("cargo:rustc-link-lib=dylib=bsd");
    println!("cargo:rustc-link-lib=dylib=pcap");
} 
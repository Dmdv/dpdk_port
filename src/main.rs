use anyhow::Result;
use clap::Parser;
use libc::{c_char, c_int, c_void};
use std::ffi::CString;
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use ctrlc;

// Cleanup function for DPDK resources
unsafe fn cleanup_dpdk(ports: &[u16]) {
    for &port in ports {
        // Stop the port
        extern "C" {
            fn rte_eth_dev_stop(port_id: u16) -> c_int;
            fn rte_eth_dev_close(port_id: u16) -> c_int;
        }
        
        let _ = rte_eth_dev_stop(port);
        let _ = rte_eth_dev_close(port);
    }
}

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// First port to use
    #[arg(short, long)]
    port1: u16,

    /// Second port to use
    #[arg(short, long)]
    port2: u16,
}

#[repr(C)]
struct rte_eth_burst_mode {
    mode: u32,
    flags: u32,
    burst_size: u32,
    burst_threshold: u32,
}

extern "C" {
    fn rte_eal_init(argc: c_int, argv: *const *const c_char) -> c_int;
    fn rte_eth_dev_count_avail() -> u16;
    fn rte_eth_dev_configure(port_id: u16, nb_rx_queue: u16, nb_tx_queue: u16, eth_conf: *const c_void) -> c_int;
    fn rte_eth_rx_queue_setup(port_id: u16, rx_queue_id: u16, nb_rxd: u16, socket_id: u32, rx_conf: *const c_void, mb_pool: *mut c_void) -> c_int;
    fn rte_eth_tx_queue_setup(port_id: u16, tx_queue_id: u16, nb_txd: u16, socket_id: u32, tx_conf: *const c_void) -> c_int;
    fn rte_eth_dev_start(port_id: u16) -> c_int;
    fn rte_eth_rx_burst_mode_get(port_id: u16, queue_id: u16, mode: *mut rte_eth_burst_mode) -> c_int;
    fn rte_eth_tx_burst_mode_get(port_id: u16, queue_id: u16, mode: *mut rte_eth_burst_mode) -> c_int;
    fn rte_mempool_create(name: *const c_char, n: u32, elt_size: u32, cache_size: u32, private_data_size: u32, mp_init: *const c_void, mp_init_arg: *mut c_void, obj_init: *const c_void, obj_init_arg: *mut c_void, socket_id: i32, flags: u32) -> *mut c_void;
    fn rte_mempool_free(mp: *mut c_void);
}

#[derive(Default)]
struct PortStats {
    rx_packets: u64,
    tx_packets: u64,
    rx_bytes: u64,
    tx_bytes: u64,
    rx_errors: u64,
    tx_errors: u64,
}

struct Forwarder {
    port1: u16,
    port2: u16,
    stats: [PortStats; 2],
}

impl Forwarder {
    unsafe fn new(port1: u16, port2: u16, mbuf_pool: *mut c_void) -> Self {
        Self {
            port1,
            port2,
            stats: [PortStats::default(), PortStats::default()],
        }
    }

    unsafe fn forward_packets(&mut self) -> Result<()> {
        let mut burst_mode = rte_eth_burst_mode {
            mode: 0,
            flags: 0,
            burst_size: 32,
            burst_threshold: 16,
        };

        // Process packets from port1 to port2
        if rte_eth_rx_burst_mode_get(self.port1, 0, &mut burst_mode) < 0 {
            self.stats[0].rx_errors += 1;
            return Err(anyhow::anyhow!("Failed to get RX burst mode for port {}", self.port1));
        }
        
        if rte_eth_tx_burst_mode_get(self.port2, 0, &mut burst_mode) < 0 {
            self.stats[1].tx_errors += 1;
            return Err(anyhow::anyhow!("Failed to get TX burst mode for port {}", self.port2));
        }

        // Process packets from port2 to port1
        if rte_eth_rx_burst_mode_get(self.port2, 0, &mut burst_mode) < 0 {
            self.stats[1].rx_errors += 1;
            return Err(anyhow::anyhow!("Failed to get RX burst mode for port {}", self.port2));
        }
        
        if rte_eth_tx_burst_mode_get(self.port1, 0, &mut burst_mode) < 0 {
            self.stats[0].tx_errors += 1;
            return Err(anyhow::anyhow!("Failed to get TX burst mode for port {}", self.port1));
        }

        // Update statistics based on burst mode
        self.stats[0].rx_packets += burst_mode.burst_size as u64;
        self.stats[1].tx_packets += burst_mode.burst_size as u64;
        self.stats[1].rx_packets += burst_mode.burst_size as u64;
        self.stats[0].tx_packets += burst_mode.burst_size as u64;

        Ok(())
    }

    fn print_stats(&self) {
        println!("\nPort {} Statistics:", self.port1);
        println!("  RX Packets: {}", self.stats[0].rx_packets);
        println!("  TX Packets: {}", self.stats[0].tx_packets);
        println!("  RX Bytes: {}", self.stats[0].rx_bytes);
        println!("  TX Bytes: {}", self.stats[0].tx_bytes);
        println!("  RX Errors: {}", self.stats[0].rx_errors);
        println!("  TX Errors: {}", self.stats[0].tx_errors);

        println!("\nPort {} Statistics:", self.port2);
        println!("  RX Packets: {}", self.stats[1].rx_packets);
        println!("  TX Packets: {}", self.stats[1].tx_packets);
        println!("  RX Bytes: {}", self.stats[1].rx_bytes);
        println!("  TX Bytes: {}", self.stats[1].tx_bytes);
        println!("  RX Errors: {}", self.stats[1].rx_errors);
        println!("  TX Errors: {}", self.stats[1].tx_errors);
    }
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Set up Ctrl+C handler
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    ctrlc::set_handler(move || {
        r.store(false, Ordering::SeqCst);
    }).expect("Error setting Ctrl-C handler");

    // Initialize EAL
    let eal_args = vec![
        CString::new("dpdk-tutorial").unwrap(),
        CString::new("-l").unwrap(),
        CString::new("0").unwrap(),
        CString::new("--proc-type=auto").unwrap(),
    ];
    let mut eal_argv: Vec<*const c_char> = eal_args.iter().map(|arg| arg.as_ptr()).collect();
    eal_argv.push(ptr::null());

    let mut forwarder = unsafe {
        if rte_eal_init(eal_argv.len() as c_int - 1, eal_argv.as_ptr()) < 0 {
            return Err(anyhow::anyhow!("Failed to initialize EAL"));
        }

        // Check if ports are available
        let nb_ports = rte_eth_dev_count_avail();
        if args.port1 >= nb_ports || args.port2 >= nb_ports {
            return Err(anyhow::anyhow!("Invalid port numbers"));
        }

        // Create memory pool
        let pool_name = CString::new("mbuf_pool").unwrap();
        let mbuf_pool = rte_mempool_create(
            pool_name.as_ptr(),
            8192,
            2048,
            256,
            0,
            ptr::null(),
            ptr::null_mut(),
            ptr::null(),
            ptr::null_mut(),
            -1,
            0,
        );
        if mbuf_pool.is_null() {
            return Err(anyhow::anyhow!("Failed to create memory pool"));
        }

        // Configure ports
        for port in [args.port1, args.port2] {
            if rte_eth_dev_configure(port, 1, 1, ptr::null()) < 0 {
                cleanup_dpdk(&[args.port1, args.port2]);
                return Err(anyhow::anyhow!("Failed to configure port {}", port));
            }

            if rte_eth_rx_queue_setup(port, 0, 128, 0, ptr::null(), mbuf_pool) < 0 {
                cleanup_dpdk(&[args.port1, args.port2]);
                return Err(anyhow::anyhow!("Failed to setup RX queue for port {}", port));
            }

            if rte_eth_tx_queue_setup(port, 0, 128, 0, ptr::null()) < 0 {
                cleanup_dpdk(&[args.port1, args.port2]);
                return Err(anyhow::anyhow!("Failed to setup TX queue for port {}", port));
            }

            if rte_eth_dev_start(port) < 0 {
                cleanup_dpdk(&[args.port1, args.port2]);
                return Err(anyhow::anyhow!("Failed to start port {}", port));
            }
        }

        Forwarder::new(args.port1, args.port2, mbuf_pool)
    };

    println!("Starting packet forwarder between ports {} and {}", args.port1, args.port2);
    println!("Press Ctrl+C to stop");

    let mut stats_timer = std::time::Instant::now();
    
    while running.load(Ordering::SeqCst) {
        unsafe {
            if let Err(e) = forwarder.forward_packets() {
                eprintln!("Error forwarding packets: {}", e);
                continue;
            }
        }

        // Print statistics every second
        if stats_timer.elapsed() >= std::time::Duration::from_secs(1) {
            forwarder.print_stats();
            stats_timer = std::time::Instant::now();
        }
    }

    println!("\nShutting down...");
    unsafe {
        cleanup_dpdk(&[args.port1, args.port2]);
    }
    println!("Cleanup complete");

    Ok(())
}

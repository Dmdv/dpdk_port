use anyhow::Result;
use clap::Parser;
use libc::{c_char, c_int, c_void};
use std::ffi::CString;
use std::ptr;

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
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize EAL
    let eal_args = vec![
        CString::new("dpdk-tutorial").unwrap(),
        CString::new("-l").unwrap(),
        CString::new("0").unwrap(),
        CString::new("--proc-type=auto").unwrap(),
    ];
    let mut eal_argv: Vec<*const c_char> = eal_args.iter().map(|arg| arg.as_ptr()).collect();
    eal_argv.push(ptr::null());

    unsafe {
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
                return Err(anyhow::anyhow!("Failed to configure port {}", port));
            }

            if rte_eth_rx_queue_setup(port, 0, 128, 0, ptr::null(), mbuf_pool) < 0 {
                return Err(anyhow::anyhow!("Failed to setup RX queue for port {}", port));
            }

            if rte_eth_tx_queue_setup(port, 0, 128, 0, ptr::null()) < 0 {
                return Err(anyhow::anyhow!("Failed to setup TX queue for port {}", port));
            }

            if rte_eth_dev_start(port) < 0 {
                return Err(anyhow::anyhow!("Failed to start port {}", port));
            }
        }

        println!("Starting packet forwarder between ports {} and {}", args.port1, args.port2);
        println!("Press Ctrl+C to stop");

        let mut burst_mode = rte_eth_burst_mode {
            mode: 0,
            flags: 0,
            burst_size: 32,
            burst_threshold: 16,
        };

        loop {
            // Process packets from port1 to port2
            if rte_eth_rx_burst_mode_get(args.port1, 0, &mut burst_mode) < 0 {
                println!("Failed to get RX burst mode for port {}", args.port1);
                continue;
            }
            
            if rte_eth_tx_burst_mode_get(args.port2, 0, &mut burst_mode) < 0 {
                println!("Failed to get TX burst mode for port {}", args.port2);
                continue;
            }

            // Process packets from port2 to port1
            if rte_eth_rx_burst_mode_get(args.port2, 0, &mut burst_mode) < 0 {
                println!("Failed to get RX burst mode for port {}", args.port2);
                continue;
            }
            
            if rte_eth_tx_burst_mode_get(args.port1, 0, &mut burst_mode) < 0 {
                println!("Failed to get TX burst mode for port {}", args.port1);
                continue;
            }
        }
    }
}
